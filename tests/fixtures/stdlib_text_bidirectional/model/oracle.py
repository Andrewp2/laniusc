"""Independent semantic partitions and deque schedules for borrowed Text cursors."""
from __future__ import annotations
from collections import deque,Counter
from dataclasses import dataclass
import itertools
from pathlib import Path
import random
import re
import struct
import subprocess
import sys

SEED=0xB1D17E0261108
MASK=(1<<64)-1
BACKING=2056
SEPARATORS=frozenset((9,10,11,12,13,32))

@dataclass(frozen=True)
class Case:
    family:int
    layout:int
    origin:int
    data:bytes
    actions:tuple
    drain:int


def items(case):
    data=case.data
    if case.family==0:
        # Partition by LF positions first. Only its immediately preceding CR
        # can be a terminator byte. Other Unicode line separators are content.
        ends=[index for index,value in enumerate(data) if value==10]
        starts=[0]+[index+1 for index in ends]
        result=[]
        for start,end in zip(starts,ends):
            stop=end-1 if end>start and data[end-1]==13 else end
            result.append((start,data[start:stop]))
        if starts[-1]<len(data):result.append((starts[-1],data[starts[-1]:]))
        return result
    if case.family==1:
        offset=0;result=[]
        for scalar in data.decode('utf-8'):
            result.append((offset,ord(scalar)));offset+=len(scalar.encode('utf-8'))
        assert offset==len(data)
        return result
    assert case.family==2
    # Explicit six-byte character class, without Python's broader whitespace.
    return [(match.start(),match.group()) for match in re.finditer(rb'[^\x09\x0a\x0b\x0c\x0d\x20]+',data)]


def backing(case):
    result=bytearray((211+index*17)&255 for index in range(BACKING))
    result[case.origin:case.origin+len(case.data)]=case.data
    return result


def schedules(short,ordinal,rng):
    if short:
        actions=[]
        # All eight front/back patterns for three pulls. Every short-text
        # family has <=3 items, so this also crosses and repeats exhaustion.
        for mask in range(8):
            actions.append(6)
            actions.extend((mask>>bit)&1 for bit in range(3))
        return tuple(actions+[6,0,4,1,2,3,5,0,1,4,2,3,5,1,0,7,2,4,3])
    actions=[6,7,0,4,1,2,3,5,0,1]
    choices=(0,0,0,1,1,1,2,2,3,3,4,5,6,7)
    actions += [rng.choice(choices) for _ in range(48)]
    return tuple(actions)


def cases():
    result=[];rng=random.Random(SEED)
    texts=[]
    alphabet=('a','\r','\n',' ','\t','\0','é','😀')
    for length in range(4):
        texts.extend((''.join(value),True) for value in itertools.product(alphabet,repeat=length))
    assert len(texts)==585
    texts += [(''.join(value),False) for value in itertools.product(('a','\r','\n'),repeat=4)]
    special=('', '\n','\r','\r\n','\n\n','\r\r\n','x\r\ny\rz\n','\n\r\n\r',
             '\t\n\v\f\r ', ' \tword\v\fend\r\n', '\0\u00a0\u0085\u2028\u2029',
             'a\u00a0b c\u2028d\0', 'x\r\r\n\n\r\nlast\r',
             '\u007f\u0080\u07ff\u0800\ud7ff\ue000\uffff\U00010000\U0010ffff',
             '\u0301A\u200d\ufe0f\ufdd0\ufdef\ufffe\U0010fffe')
    texts += [(value,False) for value in special]
    # Every separator independently borders NUL/Unicode content and meets
    # every other separator, including the CRLF special case for Lines.
    for first in sorted(SEPARATORS):
        for second in sorted(SEPARATORS):
            texts.append((chr(first)+'é\0'+chr(second)+'😀'+chr(first),False))
    pool=('a','b','\0','\t','\n','\v','\f','\r',' ','é','界','😀','\u00a0','\u0085','\u2028','\u2029','\uffff','\U0010ffff')
    for ordinal in range(96):
        length=(0,1,2,3,7,31,63,127,255,511)[ordinal%10]
        value=''.join(rng.choice(pool) for _ in range(length))
        if ordinal%3==0:value='\r\n'+value+'\r\n'
        if ordinal%3==1:value='\n'+value+'\r'
        assert len(value.encode())<=2048
        texts.append((value,False))
    for ordinal,(value,short) in enumerate(texts):
        data=value.encode('utf-8');actions=schedules(short,ordinal,rng)
        for family in range(3):
            for layout in (0,1):
                result.append(Case(family,layout,3+(ordinal%3)*2,data,actions,ordinal%3))
    return result


def packet(values):
    result=bytearray()
    for case in values:
        assert case.family in range(3) and case.layout in (0,1)
        assert len(case.data)<=2048 and case.origin+len(case.data)<BACKING
        assert len(case.actions)<=96 and all(0<=action<=7 for action in case.actions)
        result+=struct.pack('<6Q',case.family,case.layout,case.origin,len(case.data),len(case.actions),case.drain)
        result+=case.data+bytes(case.actions)
    return result


def encode_item(case,opcode,value):
    if value is None:return bytes((opcode,0))
    start,payload=value
    if case.family==1:return bytes((opcode,1))+struct.pack('<2Q',start,payload)
    stride=1 if case.layout else -8
    return bytes((opcode,1))+struct.pack('<3Q',start,len(payload),stride&MASK)+payload


def drain_opcode(cursor,turn,mode):
    direction=(turn+cursor)%2 if mode==0 else (cursor if mode==1 else 1-cursor)
    return 2*cursor+direction


def reference(case,counts=None):
    original=items(case);cursors=[deque(original),deque(original)]
    output=bytearray(struct.pack('<3Q',case.origin,len(case.data),(1 if case.layout else -8)&MASK))
    def execute(opcode):
        if opcode>=4:
            if opcode==4:cursors[1]=cursors[0].copy()
            elif opcode==5:cursors[0]=cursors[1].copy()
            elif opcode==6:cursors[0]=deque(original)
            else:cursors[1]=deque(original)
            if counts is not None:counts['copies']+=1
            output.extend((opcode,2));return False
        cursor=cursors[opcode//2]
        item=(cursor.pop() if opcode%2 else cursor.popleft()) if cursor else None
        output.extend(encode_item(case,opcode,item))
        if counts is not None:
            counts['pulls']+=1;counts['items']+=int(item is not None)
        return item is None
    for action in case.actions:execute(action)
    for cursor in range(2):
        turn=0
        while not execute(drain_opcode(cursor,turn,case.drain)):
            turn+=1;assert turn<=2048
    for opcode in (0,1,2,3,1,0,3,2):assert execute(opcode)
    output+=struct.pack('<3Q',case.origin,len(case.data),(1 if case.layout else -8)&MASK)
    output+=backing(case)
    return output


def verify(actual,values):
    position=0;counts=Counter(pulls=0,items=0,copies=0)
    for index,case in enumerate(values):
        expected=reference(case,counts)
        assert position+len(expected)<=len(actual),(f'seed={SEED:#x}',index,case,'truncated')
        observed=actual[position:position+len(expected)]
        if observed!=expected:
            first=next(index for index,pair in enumerate(zip(observed,expected)) if pair[0]!=pair[1])
            raise AssertionError((f'seed={SEED:#x}','case',index,'family',case.family,'layout',case.layout,
                                  'origin',case.origin,'text',case.data,'byte',first,'observed',observed[first],'expected',expected[first]))
        position+=len(expected)
    assert position==len(actual),('extra output',position,len(actual))
    return counts


def controls():
    values=cases();assert packet(values)
    def sample(family,text,actions=(0,4,1,2,3,5,0)):
        return Case(family,1,5,text.encode(),actions,0)
    assert items(sample(0,''))==[]
    assert items(sample(0,'\r\n\r'))==[(0,b''),(2,b'\r')]
    assert items(sample(0,'\n\n'))==[(0,b''),(1,b'')]
    assert items(sample(0,'a\r\r\n\u2028\r'))==[(0,b'a\r'),(4,'\u2028\r'.encode())]
    assert items(sample(1,'Aé界😀'))==[(0,65),(1,233),(3,30028),(6,128512)]
    assert items(sample(2,'\t a\0\u00a0b\v界\f'))==[(2,'a\0\u00a0b'.encode()),(8,'界'.encode())]
    counts=verify(b''.join(reference(case) for case in values),values)
    base=sample(0,'\nalpha\r\nβ\r',actions=(0,4,1,2,3,5,0))
    output=reference(base)
    # Distinct metadata, Some(empty), item offset/content, copy framing and
    # immutable backing observations are deliberately broken.
    offsets=(0,16,24,25,26,50,51,len(output)-1)
    rejected=0
    for offset in offsets:
        bad=bytearray(output);bad[offset]^=1
        try:verify(bad,[base])
        except AssertionError:rejected+=1
        else:raise AssertionError(('accepted corruption',offset))
    for bad in (output[:-1],output+b'\0'):
        try:verify(bad,[base])
        except AssertionError:rejected+=1
        else:raise AssertionError('accepted framing corruption')
    assert rejected==10
    print(f'text-bidirectional CPU cases={len(values)} families=3 layouts=2 pulls={counts["pulls"]} items={counts["items"]} copies={counts["copies"]} verifier-corruptions=10 seed={SEED:#x}')


def main():
    if len(sys.argv)==2 and sys.argv[1]=='controls':controls();return
    assert len(sys.argv)==2,'usage: oracle.py <model-executable> | controls'
    values=cases()
    process=subprocess.run([str(Path(sys.argv[1]).resolve())],input=packet(values),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=75)
    assert process.returncode==0,(process.returncode,process.stderr,len(process.stdout))
    assert not process.stderr,process.stderr
    counts=verify(process.stdout,values)
    print(f'text-bidirectional cases={len(values)} families=3 layouts=2 pulls={counts["pulls"]} items={counts["items"]} copies={counts["copies"]} seed={SEED:#x}')


if __name__=='__main__':main()
