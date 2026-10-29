"""Independent zlib output oracle and chunk/accounting laws for resumable decode."""
from __future__ import annotations
from dataclasses import dataclass, replace
from pathlib import Path
import random
import struct
import subprocess
import sys
import zlib

SEED = 0x1F1A7E0261107
MASK = (1 << 64) - 1
MAX_CALLS = 20000

class Bits:
    """Small RFC bitstream writer for boundary witnesses; never a decoder."""
    def __init__(self): self.data, self.used = bytearray(), 0
    def bits(self, value, count):
        for bit in range(count):
            if not self.used: self.data.append(0)
            self.data[-1] |= ((value >> bit) & 1) << self.used
            self.used = (self.used + 1) % 8
    def code(self, value, count):
        for bit in range(count - 1, -1, -1): self.bits((value >> bit) & 1, 1)
    def fixed(self, symbol):
        if symbol <= 143: self.code(symbol + 48, 8)
        elif symbol <= 255: self.code(symbol - 144 + 400, 9)
        elif symbol <= 279: self.code(symbol - 256, 7)
        else: self.code(symbol - 280 + 192, 8)
    def stored(self, plain, final=True):
        self.bits(int(final), 1); self.bits(0, 2)
        while self.used: self.bits(0, 1)
        self.data += struct.pack('<HH', len(plain), len(plain) ^ 65535) + plain
    def match(self, length, distance):
        bases = (3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258)
        index = max(index for index, base in enumerate(bases) if base <= length)
        self.fixed(257 + index)
        extra = 0 if index < 8 or index == 28 else (index - 4) // 4
        self.bits(length - bases[index], extra)
        def distance_base(symbol):
            return symbol + 1 if symbol < 4 else ((2 + (symbol & 1)) << (symbol // 2 - 1)) + 1
        symbol = max(symbol for symbol in range(30) if distance_base(symbol) <= distance)
        self.code(symbol, 5)
        self.bits(distance - distance_base(symbol), 0 if symbol < 4 else symbol // 2 - 1)


def stored(plain):
    bits = Bits(); bits.stored(plain); return bytes(bits.data)


def encoded(plain, level=6, strategy=zlib.Z_DEFAULT_STRATEGY):
    encoder = zlib.compressobj(level, zlib.DEFLATED, -15, 8, strategy)
    return encoder.compress(plain) + encoder.flush()


def repeat_header(use17):
    bits = Bits(); bits.bits(1,1); bits.bits(2,2)
    bits.bits(0 if use17 else 1,5); bits.bits(0 if use17 else 2,5); bits.bits(14,4)
    alphabet = (0,1,17,18) if use17 else (0,1,16,18)
    for symbol in (16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1):
        bits.bits(2 if symbol in alphabet else 0,3)
    if use17:
        for code, value, width in ((2,0,3),(2,7,3),(3,127,7),(3,94,7)):
            bits.code(code,2); bits.bits(value,width)
        bits.code(1,2); bits.code(0,2)
    else:
        bits.code(3,2); bits.bits(127,7); bits.code(3,2); bits.bits(107,7)
        bits.code(1,2); bits.code(0,2); bits.code(2,2); bits.bits(0,2)
    bits.bits(0,1)
    result = bytes(bits.data)
    assert zlib.decompress(result,-15) == b''
    return result


def wrap(raw, plain, kind, optional=False):
    if kind in (0,1): return raw
    if kind == 2: return b'\x78\x01' + raw + struct.pack('>I',zlib.adler32(plain))
    flags = 30 if optional else 0
    header = b'\x1f\x8b\x08' + bytes([flags]) + b'\0\0\0\0\0\xff'
    if optional:
        extra = b'\0\x80EXTRA\xff'
        header += struct.pack('<H',len(extra)) + extra + b'name\xff\0' + b'comment\x80\0'
        header += struct.pack('<H',zlib.crc32(header) & 65535)
    return header + raw + struct.pack('<II',zlib.crc32(plain),len(plain) & 0xffffffff)


def reference_decode(data,kind,complete=True):
    """Explicitly visit gzip members and reject every unused trailing byte."""
    if kind != 3:
        decoder = zlib.decompressobj(15 if kind == 2 else -15)
        plain = decoder.decompress(data)
        if complete:
            assert decoder.eof
            assert kind == 0 or not decoder.unused_data
        end = len(data) - len(decoder.unused_data) if decoder.eof else None
        return plain, (() if end is None else (end,))
    remaining, output, ends, used = data, bytearray(), [], 0
    if complete: assert remaining
    while remaining:
        assert remaining[:1] == b'\x1f'
        if len(remaining) > 1: assert remaining[:2] == b'\x1f\x8b'
        decoder = zlib.decompressobj(31)
        output += decoder.decompress(remaining)
        if not decoder.eof:
            if complete: raise AssertionError('truncated gzip member')
            break
        count = len(remaining) - len(decoder.unused_data)
        assert count > 0
        used += count; ends.append(used); remaining = decoder.unused_data
    return bytes(output), tuple(ends)


@dataclass(frozen=True)
class Case:
    name: str
    kind: int
    data: bytes
    plain: bytes
    code: int = 0
    layout: int = 0
    window: int = 32768
    max_input: int = 1000000
    max_output: int = 1000000
    max_members: int = 1000
    input_mode: int = 0
    split: int = 0
    output_mode: int = 0
    defer_final: int = 0
    reset: int = 0
    boundary: int = -1
    members: int = -1
    analytic: bool = False


def cases():
    rng = random.Random(SEED)
    dynamic_plain = bytes(rng.randrange(5) for _ in range(64))
    dynamic = encoded(dynamic_plain)
    assert (dynamic[0] >> 1) & 3 == 2
    samples = [('empty-stored',stored(b''),b'',True),
               ('stored',stored(b'hello\0\xff'),b'hello\0\xff',True),
               ('fixed',encoded(b'abab\0\xffabcabcabc',strategy=zlib.Z_FIXED),b'abab\0\xffabcabcabc',False),
               ('dynamic',dynamic,dynamic_plain,False),
               ('repeat16-18',repeat_header(False),b'',False),
               ('repeat17-18',repeat_header(True),b'',False)]
    result = []
    for kind in range(4):
        for name,raw,plain,analytic in samples:
            data = wrap(raw,plain,kind)
            assert reference_decode(data,kind)[0] == plain
            for split in range(len(data)+1):
                for layout in (split % 8, (split+7) % 8):
                    result.append(Case(f'{name}-split-{split}',kind,data,plain,layout=layout,input_mode=1,
                                       split=split,output_mode=1,defer_final=split%2,reset=int(split%11==0),
                                       boundary=len(data),members=1,analytic=analytic and kind==0))
            # Every truncation, with tiny chunks and explicit final EOF.
            if name in ('stored','dynamic'):
                for cut in range(len(data)):
                    partial = data[:cut]
                    produced, ends = reference_decode(partial,kind,False)
                    result.append(Case(f'{name}-truncated-{cut}',kind,partial,produced,
                                       code=2 if kind==0 else 7,layout=cut%8,input_mode=2,output_mode=1,
                                       defer_final=1,reset=int(cut%13==0),members=len(ends)))
    optional_plain = b'optional\0header\xff'*3
    optional = wrap(encoded(optional_plain),optional_plain,3,True)
    members_plain = (b'', b'first\0\xff', dynamic_plain)
    members = [wrap(encoded(plain),plain,3,index==1) for index,plain in enumerate(members_plain)]
    joined = b''.join(members)
    for name,data,plain,count in (('gzip-optional',optional,optional_plain,1),
                                  ('gzip-concatenated',joined,b''.join(members_plain),3)):
        assert reference_decode(data,3)[0] == plain
        for split in range(len(data)+1):
            result.append(Case(f'{name}-split-{split}',3,data,plain,layout=split%8,input_mode=1,split=split,
                               output_mode=1,defer_final=1,reset=int(split%17==0),boundary=len(data),members=count))
        for cut in range(len(data)):
            produced, ends = reference_decode(data[:cut],3,False)
            valid = bool(ends) and ends[-1] == cut
            result.append(Case(f'{name}-prefix-{cut}',3,data[:cut],produced,code=0 if valid else 7,
                               layout=cut%8,input_mode=3,output_mode=1,defer_final=1,
                               boundary=cut if valid else -1,members=len(ends)))
    # A stored seed followed by references at exactly distance 32768, then
    # distance-one overlap. The history wraps repeatedly while output is reused.
    seed = bytes((index*31+index//37)&255 for index in range(32768))
    bits = Bits(); bits.stored(seed,False); bits.bits(1,1); bits.bits(1,2)
    plain = bytearray(seed)
    for _ in range(180):
        bits.match(258,32768)
        for _ in range(258): plain.append(plain[-32768])
    for _ in range(140):
        bits.match(258,1)
        for _ in range(258): plain.append(plain[-1])
    bits.fixed(256)
    large = [('window-wrap-overlap',bytes(bits.data),bytes(plain)),
             ('distance-one',encoded(b'a'*98305),b'a'*98305)]
    encoder = zlib.compressobj(6,zlib.DEFLATED,-15)
    sync_plain = bytes(range(256))*40
    sync = encoder.compress(sync_plain[:4000])+encoder.flush(zlib.Z_SYNC_FLUSH)+encoder.compress(sync_plain[4000:])+encoder.flush()
    large.append(('cross-block-history',sync,sync_plain))
    for kind in range(4):
        for name,raw,plain in large:
            data = wrap(raw,plain,kind)
            assert reference_decode(data,kind)[0] == plain
            for layout in (0,7):
                result.append(Case(name,kind,data,plain,layout=layout,input_mode=3,output_mode=2,
                                   defer_final=1,reset=int(name=='distance-one'),boundary=len(data),members=1))
    # Structural errors have explicit format-level expectations. Their outputs
    # come from the valid originals or literal stored-prefix witnesses.
    raw_bad = ((b'\x07',3),(b'\x01\x01\0\0\0',4))
    for raw,raw_code in raw_bad:
        for kind in range(4):
            data = wrap(raw,b'',kind)
            for split in range(len(data)+1):
                result.append(Case('malformed-raw',kind,data,b'',code=raw_code if kind==0 else 100+raw_code,
                                   input_mode=1,split=split,output_mode=1,layout=split%8,reset=1,members=0))
    for kind in range(4):
        raw,plain = samples[1][1:3]
        data = wrap(raw,plain,kind)
        suffix = b'\xaa\xbb\xcc'
        result.append(Case('trailing-bytes',kind,data+suffix,plain,code=0 if kind==0 else 14,
                           input_mode=3,output_mode=1,layout=7,boundary=len(data),members=1,reset=1))
        if kind > 0:
            for allowance in (0,len(data)-1,len(data)):
                result.append(Case('input-admission',kind,data,plain if allowance==len(data) else b'',code=0 if allowance==len(data) else 2,
                                   max_input=allowance,input_mode=0,output_mode=1,layout=kind,
                                   boundary=len(data),members=1 if allowance==len(data) else 0))
            for allowance in (0,len(plain)-1,len(plain)):
                result.append(Case('output-admission',kind,data,plain[:allowance],code=0 if allowance==len(plain) else 3,
                                   max_output=allowance,input_mode=3,output_mode=1,layout=kind+3,
                                   boundary=len(data),members=1 if allowance==len(plain) else 0))
            result.append(Case('member-admission',kind,data,b'',code=4,max_members=0,layout=7))
    for kind in (2,3):
        raw,plain = samples[2][1:3]
        original = wrap(raw,plain,kind)
        for position,code in ((len(original)-(4 if kind==2 else 8),12),):
            bad = bytearray(original); bad[position] ^= 1
            for split in (0,position,position+1,len(bad)):
                result.append(Case('checksum',kind,bytes(bad),plain,code=code,input_mode=1,split=split,
                                   output_mode=1,layout=split%8,reset=1,members=0))
        if kind==3:
            bad=bytearray(original); bad[-4]^=1
            result.append(Case('size',3,bytes(bad),plain,code=13,input_mode=2,output_mode=1,members=0))
    for suffix in (b'\0',b'\x1f\0'):
        data=members[0]+suffix
        for split in range(len(members[0]),len(data)+1):
            result.append(Case('gzip-tail-before-member-limit',3,data,b'',code=14,max_members=1,
                               input_mode=1,split=split,output_mode=1,layout=split%8,members=1))
    for allowance in (1,2):
        data=members[0]+b'\x1f'
        for split in (len(members[0]),len(data)):
            result.append(Case('gzip-lone-magic-budget',3,data,b'',code=4 if allowance==1 else 7,
                               max_members=allowance,input_mode=1,split=split,output_mode=1,members=1))
    dictionary_flags = 32 + ((31-(((120<<8)|32)%31))%31)
    headers = ((2,b'\x79\x00',9),(2,b'\x88\x00',10),(2,b'\x78\x00',8),
               (2,bytes((120,dictionary_flags))+b'\x01\x02\x03\x04',11),
               (3,b'\x00\x8b\x08'+b'\0'*7,8),
               (3,b'\x1f\x8b\x09'+b'\0'*7,9),
               (3,b'\x1f\x8b\x08\xe0'+b'\0'*6,8))
    for kind,data,code in headers:
        for split in range(len(data)+1):
            result.append(Case('invalid-header',kind,data,b'',code=code,input_mode=1,split=split,
                               output_mode=1,layout=split%8,reset=1,members=0))
    bad_optional=bytearray(optional)
    # The header checksum immediately precedes the known raw compressed body.
    header_end=len(optional)-len(encoded(optional_plain))-8
    bad_optional[header_end-1]^=1
    for split in (0,header_end-1,header_end,len(bad_optional)):
        result.append(Case('gzip-fhcrc',3,bytes(bad_optional),b'',code=12,input_mode=1,split=split,
                           output_mode=1,layout=split%8,reset=1,members=0))
    for limit in (1,2,3):
        result.append(Case('gzip-member-budget',3,joined,b''.join(members_plain[:limit]),code=0 if limit==3 else 4,
                           max_members=limit,input_mode=3,output_mode=1,layout=7,boundary=len(joined),members=limit))
    for case in result:
        assert len(case.data)<=70000 and len(case.plain)<=200000
    return result


def packet(values):
    data=bytearray()
    for case in values:
        words=(case.kind,case.layout,len(case.data),case.window,case.max_input,case.max_output,case.max_members,
               case.input_mode,case.split,case.output_mode,case.defer_final,case.reset)
        data+=struct.pack('<12Q',*words)+case.data
    return data

class Reader:
    def __init__(self,data): self.data,self.at=data,0
    def words(self,count):
        size=count*8
        assert self.at+size<=len(self.data),('truncated words',self.at,count,len(self.data))
        result=struct.unpack_from('<'+'Q'*count,self.data,self.at); self.at+=size; return result
    def bytes(self,count):
        assert self.at+count<=len(self.data),('truncated bytes',self.at,count,len(self.data))
        result=self.data[self.at:self.at+count]; self.at+=count; return result


def capacities(mode,call):
    return 509 if mode==0 else ((0,1,0,3,7,0,31,509) if mode==1 else (0,127,509,1,509,257))[call%(8 if mode==1 else 6)]


def frontier_after(mode,frontier,length,turn):
    return length if mode in (0,1) else min(length,frontier+(1 if mode==2 else (0,1,2,0,7,31,128,509)[turn%8]))


def stored_step(case,position,written,offered,capacity,final):
    """Analytical five-byte stored header plus literal payload, no bit decoder."""
    header=min(offered,max(0,5-position))
    if position+header<5: return header,0,0 if final else 1,2 if final else 0
    available=offered-header
    copied=min(len(case.plain)-written,available,capacity)
    if copied==len(case.plain)-written: return header+copied,copied,3,0
    if copied==available: return header+copied,copied,0 if final else 1,2 if final else 0
    return header+copied,copied,2,0


def pattern(call): return bytes((193+call%29+index*7)&255 for index in range(520))


def expected_source(case,position):
    data=bytearray((81+index*11)&255 for index in range(len(case.data)+8))
    data[4:4+len(case.data)]=case.data
    data[4:4+position]=bytes((index*17+43)&255 for index in range(position))
    return data


class PrefixOracle:
    """Feed only bytes the native implementation reports actually consumed."""
    def __init__(self,kind):
        self.kind=kind; self.decoder=None; self.output=bytearray(); self.ends=0
        self.done=False
    def feed(self,data):
        if not data: return
        if self.done and self.kind!=3: return
        while data:
            if self.decoder is None:
                self.decoder=zlib.decompressobj(31 if self.kind==3 else (15 if self.kind==2 else -15))
            self.output+=self.decoder.decompress(data)
            if not self.decoder.eof: break
            self.ends+=1
            data=self.decoder.unused_data
            self.done=True
            if self.kind!=3: break
            self.decoder=None


def verify_pass(reader,case,pass_index,metrics):
    mode=case.input_mode if pass_index==0 else 0
    output_mode=case.output_mode if pass_index==0 else 0
    defer=case.defer_final if pass_index==0 else 0
    frontier=len(case.data) if mode==0 else (case.split if mode==1 else 0)
    final=frontier==len(case.data) and not defer
    position=written=call=turn=members=0
    check_prefix=case.code in ((0,2) if case.kind==0 else (0,3,7))
    independent=PrefixOracle(case.kind) if check_prefix else None
    while True:
        assert call<MAX_CALLS,('unbounded call schedule',case,pass_index)
        words=reader.words(15)
        (record,observed_pass,observed_call,offered,capacity,final_flag,read,count,status,code,done,failed,total_read,total_written,current_members)=words
        assert (record,observed_pass,observed_call)==(0,pass_index,call)
        assert (offered,capacity,final_flag)==(frontier-position,capacities(output_mode,call),int(final)),('schedule',words)
        assert read<=offered and count<=capacity and status<=3
        assert (code==0)==(status!=0)
        assert (done,failed)==(int(status==3),int(code!=0))
        if case.analytic:
            assert (read,count,status,code)==stored_step(case,position,written,offered,capacity,final),('stored progress',words,position,written)
        if status==1: assert read==offered and not final,('NeedInput contract',words)
        if status==2: assert count==capacity,('NeedOutput contract',words)
        if case.kind>0 and offered>case.max_input-position:
            assert (read,count,status,code)==(0,0,0,2),('whole-span input admission',words)
        if independent is not None:
            independent.feed(case.data[position:position+read])
            assert written+count<=len(independent.output),('output before independently decoded input',words,len(independent.output))
            if status==1: assert written+count==len(independent.output),('undrained input exhaustion',words,len(independent.output))
        observed=reader.bytes(520)
        expected=bytearray(pattern(call))
        expected[4:4+count]=case.plain[written:written+count]
        assert len(expected)==520 and observed==expected,('output prefix/guards/tail',words,written)
        position+=read; written+=count
        if case.kind==0: assert (total_read,total_written,current_members)==(0,0,0)
        else:
            assert (total_read,total_written)==(position,written),('cumulative counters',words,position,written)
            assert members<=current_members<=case.max_members and current_members<=1000
            members=current_members
        metrics['calls']+=1; metrics['bytes']+=count
        call+=1
        if code or status==3:
            assert code==case.code,('terminal error',case.name,code,case.code,words)
            assert written==len(case.plain),('terminal bytes',case.name,written,len(case.plain))
            if code==0:
                assert status==3 and position==case.boundary,('terminal input boundary',position,case.boundary)
                if case.kind>0: assert final,('container completed without final input',words)
            if case.kind>0 and case.members>=0: assert members==case.members,('completed members',members,case.members)
            break
        if status==1:
            if frontier==len(case.data): final=True
            else:
                frontier=frontier_after(mode,frontier,len(case.data),turn); turn+=1
                if frontier==len(case.data) and not defer: final=True
    # First a valid terminal call, then invalid metadata. Both must leave
    # completion/failure and cumulative counters exactly as they were.
    for record in (1,2):
        words=reader.words(15)
        expected_code=code if record==1 else 1
        expected_status=status if record==1 else 0
        assert words[:6]==(record,pass_index,call,0,0,1)
        assert words[6:10]==(0,0,expected_status,expected_code)
        assert words[10:12]==(int(status==3),int(code!=0))
        assert words[12:]==((0,0,0) if case.kind==0 else (position,written,members))
        assert reader.bytes(520)==pattern(call)
        call+=1
    assert reader.words(4)==(4,pass_index,position,len(case.data))
    assert reader.bytes(len(case.data)+8)==expected_source(case,position),('recycled input/guards',case.name)
    metrics['passes']+=1
    return code,written,position


def verify(actual,values):
    reader=Reader(actual); metrics=dict(calls=0,passes=0,bytes=0)
    for index,case in enumerate(values):
        try:
            strides=tuple((1 if case.layout&(1<<bit) else -8)&MASK for bit in range(3))+(4,)
            assert reader.words(4)==strides,('source/output/history/workspace strides',case.layout)
            initial=verify_pass(reader,case,0,metrics)
            if case.reset:
                assert reader.words(7)==(3,1,0,0,0,0,0),('reset state',case.name)
                repeated=verify_pass(reader,case,1,metrics)
                assert repeated==initial,('reset/chunk invariance',case.name,initial,repeated)
            assert reader.words(1)==(5,)
            assert reader.bytes(8)==bytes(word for index in range(4) for word in (211+index,231+index))
            assert reader.words(8)==tuple(word&MASK for index in range(4) for word in (-131-index,-151-index))
        except (AssertionError,zlib.error) as failure:
            raise AssertionError((f'seed={SEED:#x}','case',index,case.name,'kind',case.kind,'layout',case.layout,
                                  'input mode',case.input_mode,'split',case.split,'offset',reader.at,str(failure))) from failure
    assert reader.at==len(actual),('trailing output',reader.at,len(actual))
    return metrics


def synthetic_stored(case):
    """Host verifier controls only: serialize the literal stored-block law."""
    assert case.kind==0 and case.analytic and not case.reset
    data=bytearray(struct.pack('<4Q',*((1 if case.layout&(1<<bit) else -8)&MASK for bit in range(3)),4))
    mode=case.input_mode; frontier=len(case.data) if mode==0 else(case.split if mode==1 else 0)
    final=frontier==len(case.data) and not case.defer_final
    position=written=call=turn=0
    while True:
        offered=frontier-position; cap=capacities(case.output_mode,call)
        read,count,status,code=stored_step(case,position,written,offered,cap,final)
        data+=struct.pack('<15Q',0,0,call,offered,cap,int(final),read,count,status,code,int(status==3),int(code!=0),0,0,0)
        out=bytearray(pattern(call));out[4:4+count]=case.plain[written:written+count];data+=out
        position+=read;written+=count;call+=1
        if status==3 or code:break
        if status==1:
            if frontier==len(case.data):final=True
            else:
                frontier=frontier_after(mode,frontier,len(case.data),turn);turn+=1
                if frontier==len(case.data) and not case.defer_final:final=True
    for record in (1,2):
        data+=struct.pack('<15Q',record,0,call,0,0,1,0,0,status if record==1 else 0,code if record==1 else 1,int(status==3),int(code!=0),0,0,0)
        data+=pattern(call);call+=1
    data+=struct.pack('<4Q',4,0,position,len(case.data))+expected_source(case,position)
    data+=struct.pack('<Q',5)+bytes(word for index in range(4) for word in (211+index,231+index))
    data+=struct.pack('<8Q',*(word&MASK for index in range(4) for word in(-131-index,-151-index)))
    return data


def controls():
    values=cases(); assert packet(values)
    assert stored(b'abc')==b'\x01\x03\x00\xfc\xffabc'
    assert len(repeat_header(False))==13 and len(repeat_header(True))==13
    chosen=[replace(case,reset=0) for case in values if case.analytic]
    data=b''.join(synthetic_stored(case) for case in chosen)
    metrics=verify(data,chosen)
    # The complete valid stream reference rejects concatenation for raw/zlib;
    # gzip uses an explicit member loop and rejects trailing non-member bytes.
    for kind in (1,2,3):
        valid=wrap(stored(b'x'),b'x',kind)
        assert reference_decode(valid,kind)[0]==b'x'
        try: reference_decode(valid+b'!',kind)
        except (AssertionError,zlib.error):pass
        else:raise AssertionError('oracle accepted trailing bytes')
    # A literal ample-output stored call has exact read/write/Done, so each
    # deliberate mutation targets a distinct contract observation.
    sample=Case('literal-control',0,stored(b'abc'),b'abc',layout=7,boundary=8,members=1,analytic=True)
    baseline=synthetic_stored(sample); assert verify(baseline,[sample])['calls']==1
    mutations=((32+6*8,7),(32+7*8,2),(32+8*8,1),(32+10*8,0),(32+12*8,1))
    rejected=0
    for offset,value in mutations:
        bad=bytearray(baseline); assert struct.unpack_from('<Q',bad,offset)[0]!=value
        struct.pack_into('<Q',bad,offset,value)
        try:verify(bad,[sample])
        except AssertionError:rejected+=1
        else:raise AssertionError(('accepted count/state corruption',offset))
    for offset in (32+15*8,32+15*8+4,32+15*8+7,len(baseline)-1):
        bad=bytearray(baseline);bad[offset]^=1
        try:verify(bad,[sample])
        except AssertionError:rejected+=1
        else:raise AssertionError(('accepted byte corruption',offset))
    for bad in (baseline[:-1],baseline+b'\0'):
        try:verify(bad,[sample])
        except AssertionError:rejected+=1
        else:raise AssertionError('accepted framing corruption')
    assert rejected==11
    print(f'inflate-stream CPU cases={len(values)} reset-cases={sum(case.reset for case in values)} analytic-cases={len(chosen)} analytic-calls={metrics["calls"]} verifier-corruptions={rejected} seed={SEED:#x}')


def main():
    if len(sys.argv)==2 and sys.argv[1]=='controls':controls();return
    assert len(sys.argv)==2,'usage: oracle.py <model-executable> | controls'
    values=cases()
    process=subprocess.run([str(Path(sys.argv[1]).resolve())],input=packet(values),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=75)
    assert process.returncode==0,(process.returncode,process.stderr,len(process.stdout))
    assert not process.stderr,process.stderr
    metrics=verify(process.stdout,values)
    print(f'inflate-stream cases={len(values)} reset-cases={sum(case.reset for case in values)} passes={metrics["passes"]} calls={metrics["calls"]} output-bytes={metrics["bytes"]} formats=4 layouts=8 seed={SEED:#x}')


if __name__=='__main__':main()
