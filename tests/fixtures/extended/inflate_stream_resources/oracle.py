"""Independent zlib payloads and fixed-workspace syscall accounting."""
from collections import Counter
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zlib

TRACE="read,write,mmap,munmap,mremap,brk"

def compressed(data,format):
    codec=zlib.compressobj(6,zlib.DEFLATED,(-15,15,31)[format])
    wire=codec.compress(data)+codec.flush()
    assert zlib.decompress(wire,(-15,15,31)[format])==data
    return wire

def pattern(size):
    block=bytes((index*73+19)%256 for index in range(256))
    return (block*((size+255)//256))[:size]

def ledger(text):
    events,live,counts,phase,peak=[],{},Counter(),None,0
    for line in text.splitlines():
        m=re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)',line)
        assert m and m[1] in TRACE.split(','),line
        name,args,answer=m.groups();counts[name]+=1
        item=dict(name=name,args=args,answer=answer,ordinal=counts[name],phase=phase,line=line)
        marker=re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1',args) if name=='write' and answer=='1' else None
        if marker:
            token=chr(int(marker[1],16));assert token in 'AaCcRrSsDd'
            if token.isupper(): assert phase is None;phase=token
            else: assert phase==token.upper();phase=None
            item['marker']=token;item['phase']=phase
            item['live']=dict(live)
        elif name=='mmap':
            extent=int(args.split(',')[1]);assert phase in ('A','C'),item
            if answer.startswith('0x'):
                assert answer not in live;live[answer]=extent;peak=max(peak,sum(live.values()))
            else: assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer,item
        elif name=='munmap':
            address,extent=args.split(',');assert answer=='0' and live.pop(address.strip(),None)==int(extent),item
            assert phase in ('C','D'),item
        elif name in ('brk','mremap'): raise AssertionError(item)
        elif phase in ('C','R'): raise AssertionError(('host work in inert phase',item))
        events.append(item)
    assert phase is None and not live,(phase,live)
    return events,peak

class Runner:
    def __init__(self,exe,group):
        self.exe=str(Path(exe).resolve());h=Path(self.exe).read_bytes()[:64]
        assert len(h)==64 and h[:6]==b'\x7fELF\x02\x01' and int.from_bytes(h[16:18],'little')==2 and int.from_bytes(h[18:20],'little')==62
        self.directory=Path(tempfile.mkdtemp(prefix=f'inflate-stream-resources-{group}-'));self.count=0
    def run(self,name,data,oom=None):
        prefix=self.directory/name;prefix.with_suffix('.input').write_bytes(data)
        command=['strace','--kill-on-exit','-qq','-xx','-s','32','-e','signal=none','-e','trace='+TRACE,'-o',str(prefix.with_suffix('.trace'))]
        if oom is not None: command+=['-e',f'inject=mmap:error=ENOMEM:when={oom}']
        command+=[self.exe];prefix.with_suffix('.command').write_text(repr(command)+'\n')
        result=subprocess.run(command,input=data,capture_output=True,timeout=60,check=False)
        prefix.with_suffix('.stdout').write_bytes(result.stdout);prefix.with_suffix('.stderr').write_bytes(result.stderr);prefix.with_suffix('.status').write_text(str(result.returncode)+'\n')
        assert result.returncode==0,(name,result.returncode,result.stderr)
        events,peak=ledger(prefix.with_suffix('.trace').read_text())
        markers=''.join(item['marker'] for item in events if 'marker' in item).encode()
        assert result.stderr==markers,(name,result.stderr,markers)
        faults=[item for item in events if 'INJECTED' in item['answer']]
        if oom is None: assert not faults
        else: assert len(faults)==1 and faults[0]['name']=='mmap' and faults[0]['ordinal']==oom
        self.count+=1;return result.stdout,events,peak

def stream(r):
    peaks=[];total_streams=0
    for size in (2*1024*1024,4*1024*1024):
        large=pattern(size)
        first,second=pattern(65537),b'member-two\x00\xff'*513
        bad_plain=b'checksum-provisional\0\xff'*11
        bad=bytearray(compressed(bad_plain,2));bad[-8]^=1
        cases=[(0,compressed(pattern(262145),0),pattern(262145),0,1),
               (1,compressed(first,1),first,0,1),
               (2,compressed(first,2)+compressed(second,2),first+second,0,2),
               (2,bytes(bad),bad_plain,12,0),
               (1,compressed(b'reset-after-checksum',1),b'reset-after-checksum',0,1),
               (0,b'\x07',b'',15,0),
               (2,compressed(b'',2),b'',0,1),
               (2,compressed(large,2),large,0,1)]
        data=struct.pack('<I',len(cases))
        for format,wire,plain,error,_ in cases:
            data+=struct.pack('<4I',format,len(wire),error,len(plain))+wire
        output,events,peak=r.run(f'stream-{size}',data);peaks.append(peak)
        at=0
        for format,wire,plain,error,members in cases:
            assert output[at:at+len(plain)]==plain,(size,format,error,at);at+=len(plain)
            actual=struct.unpack_from('<4I',output,at);at+=16
            assert actual==(error,len(wire),len(plain),members),(size,format,actual,error,members)
        assert at==len(output)
        maps=[item for item in events if item['name']=='mmap']
        assert [int(item['args'].split(',')[1]) for item in maps]==[32769,708*4]
        assert all(item['phase']=='A' for item in maps)
        assert sum(item.get('marker')=='C' for item in events)==1
        assert sum(item.get('marker')=='R' for item in events)==len(cases)
        assert sum(item.get('marker')=='S' for item in events)==len(cases)
        total_streams+=len(cases)
    assert peaks==[32769+708*4]*2,peaks
    return f'processes={r.count} streams={total_streams} peak={peaks[0]}'

def owned(r):
    plain=pattern(196609);good=compressed(plain,2);bad=bytearray(good);bad[-8]^=1
    workloads=[('valid',2,good,plain,0),('checksum',2,bytes(bad),b'',12),('header',1,b'\x78\x00',b'',8)]
    faults=0
    for name,format,wire,wanted,error in workloads:
        packet=struct.pack('<3I',format,len(wire),len(plain))+wire
        out,base,_=r.run(name+'-baseline',packet)
        assert out==struct.pack('<2I',error,len(wanted))+wanted
        maps=[item for item in base if item['name']=='mmap'];assert len(maps)>=2
        # Workspace allocation is reached before format validation, including
        # a malformed two-byte zlib header. It is not a fixture allocation.
        assert all(item['phase']=='C' for item in maps)
        completed=next(item for item in base if item.get('marker')=='c')
        assert len(completed['live'])==(1 if error==0 else 0)
        for old in maps:
            out,actual,_=r.run(f'{name}-oom-{old["ordinal"]}',packet,old['ordinal'])
            assert out==struct.pack('<2I',5,0)
            reached=[item for item in actual if item['name']=='mmap']
            assert len(reached)==old['ordinal']
            assert [item['args'] for item in reached]==[item['args'] for item in maps[:old['ordinal']]]
            completed=next(item for item in actual if item.get('marker')=='c');assert not completed['live']
            faults+=1
    assert r.count==3+faults
    return f'processes={r.count} baselines=3 reached_oom={faults}'

def controls():
    for format in range(3):
        plain=pattern(65537);wire=compressed(plain,format);assert len(wire)<65536
    good='write(2, "\\x41", 1) = 1\nmmap(NULL, 16, X, Y, -1, 0) = 0x1000\nwrite(2, "\\x61", 1) = 1\nwrite(2, "\\x44", 1) = 1\nmunmap(0x1000, 16) = 0\nwrite(2, "\\x64", 1) = 1\n'
    assert ledger(good)[1]==16
    for bad in (good.replace('munmap(0x1000, 16) = 0\n',''),good.replace('\\x41','\\x53').replace('\\x61','\\x73'),good.replace('munmap(0x1000, 16)','munmap(0x1000, 15)')):
        try: ledger(bad)
        except AssertionError: pass
        else: raise AssertionError('bad workspace trace accepted')
    print('inflate-stream-resources CPU controls passed')

if __name__=='__main__':
    if sys.argv[1:]==['controls']:controls()
    else:
        group,exe=sys.argv[1:];r=Runner(exe,group);detail={'stream':stream,'owned':owned}[group](r)
        print(f'inflate-stream-resources-{group} {detail} evidence={r.directory}')
