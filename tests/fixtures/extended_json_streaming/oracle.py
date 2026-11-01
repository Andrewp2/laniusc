"""Ordered AST wire reference; JSON parsing/reserialization is never used."""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED=0x150A0261110
MASK=(1<<64)-1
I32_MAX=(1<<31)-1

@dataclass(frozen=True)
class Node:
    kind:int
    value:bytes=b''
    children:tuple=()

@dataclass(frozen=True)
class Case:
    tree:Node|None
    limit:int
    layout:int
    actions:tuple


def string(value):return Node(4,value.encode('utf-8'))
def array(*children):return Node(5,children=tuple((b'',child) for child in children))
def obj(*members):return Node(6,children=tuple((key.encode('utf-8'),child) for key,child in members))


def quote(data):
    data.decode('utf-8')
    # A declarative byte substitution table, independent of the production
    # scalar/string/escape progress machine. UTF-8 high bytes pass through.
    table=[bytes((byte,)) for byte in range(256)]
    for byte in range(32):table[byte]=('\\u00'+format(byte,'02x')).encode('ascii')
    table[34]=b'\\"';table[92]=b'\\\\'
    return b'"'+b''.join(table[byte] for byte in data)+b'"'


def wire(node):
    if node.kind<3:return (b'null',b'false',b'true')[node.kind]
    if node.kind==3:return node.value
    if node.kind==4:return quote(node.value)
    if node.kind==5:return b'['+b','.join(wire(child) for _,child in node.children)+b']'
    assert node.kind==6
    return b'{'+b','.join(quote(key)+b':'+wire(child) for key,child in node.children)+b'}'


def flatten(tree):
    records=[]
    def append(node,parent,key):
        index=len(records);records.append((node,parent,key))
        for child_key,child in node.children:append(child,index,child_key)
    if tree is not None:append(tree,-1,b'')
    return records


def snapshot(tree):
    records=flatten(tree);output=bytearray(struct.pack('<Q',len(records)))
    def word(value):output.extend(struct.pack('<Q',value&MASK))
    for index,(node,parent,key) in enumerate(records):
        word(index);word((0,1,1,2,3,4,5)[node.kind])
        siblings=[at for at,(_,up,_) in enumerate(records) if up==parent] if parent>=0 else [0]
        later=siblings[siblings.index(index)+1:];word(later[0]+1 if later else 0)
        if node.kind in (1,2):word(int(node.kind==2))
        if node.kind in (3,4):word(len(node.value));output+=node.value
        if node.kind>=5:
            children=[at for at,(_,up,_) in enumerate(records) if up==index]
            word(len(children));word(children[0]+1 if children else 0)
        if parent>=0 and records[parent][0].kind==6:word(len(key));output+=key
    return output


def schedules(rng,cut):
    result=[(0,3,cut),(2,0,0),(0,5,1),(1,7,2),(0,I32_MAX,0),
            (1,-1,0),(0,I32_MAX,1),(1,0,-1),(3,0,0),(4,0,0),(5,0,0)]
    for _ in range(21):
        op=rng.choice((0,0,0,1,1,1,2,3,4,5))
        result.append((op,rng.randrange(8),rng.choice((0,1,2,3,5,7,13,31))))
    return tuple(result)


def cases():
    rng=random.Random(SEED)
    numbers=(b'0',b'-0',b'1.2300E+05',b'1e400',b'-1E-400',b'0.000',b'-0e+0',
             b'1844674407370955161600000000001',b'1E0002',b'123456789.987654321')
    profiles=[Node(0),Node(1),Node(2)]+[Node(3,value) for value in numbers]
    alphabet=('a','\0','"','\\','é','😀')
    for size in range(3):profiles += [string(''.join(chars)) for chars in itertools.product(alphabet,repeat=size)]
    profiles += [string(chr(value)) for value in range(32)]
    profiles += [string(''.join(map(chr,range(32)))+'"\\/é界😀\u2028\u2029\U0010ffff'),
                 string('\u007f\u0080\u07ff\u0800\ud7ff\ue000\uffff\U00010000'),
                 array(),obj(),array(Node(0),Node(1),Node(2),array(),obj()),
                 obj(('x',Node(3,b'1.0')),('x',Node(3,b'1e0')),('',array(string('\0'),obj()))),
                 obj(('z',Node(0)),('a',Node(2)),('z',Node(1))),
                 obj(('\0"\\é😀',string('\n\t')))]
    for size in (1021,1022,1023,1024,2046):profiles.append(string('a'*size))
    deep=Node(0)
    for depth in range(80):deep=array(deep) if depth%2 else obj(('',deep))
    profiles.append(deep)
    def generated(depth):
        kind=rng.randrange(7 if depth else 5)
        if kind<3:return Node(kind)
        if kind==3:return Node(3,rng.choice(numbers))
        if kind==4:return string(''.join(rng.choice(alphabet+('\n','\t','界','\u2028','\uffff')) for _ in range(rng.randrange(9))))
        children=tuple((b'' if kind==5 else rng.choice(('', 'x','x','z','\0','é','"')).encode(),generated(depth-1))
                       for _ in range(rng.randrange(4)))
        return Node(kind,children=children)
    profiles += [generated(4) for _ in range(48)]
    result=[]
    for ordinal,tree in enumerate(profiles):
        expected=wire(tree);assert len(flatten(tree))<=128 and len(expected)<=4096
        actions=schedules(rng,min(len(expected),ordinal%17))
        for limit in (len(expected),len(expected)+7,max(0,len(expected)-1)):
            for layout in (0,1):result.append(Case(tree,limit,layout,actions))
    # Every initial cut for a compact, diverse selection, in addition to the
    # direct fixture's full 108-byte structure/UTF-8/escape cut campaign.
    split_profiles=[Node(0),Node(1),Node(3,b'1.2300E+05'),string('\0é😀'),
                    obj(('x',Node(0)),('x',Node(2))),array(array(),obj(),string('"\\'))]
    for tree in split_profiles:
        expected=wire(tree)
        for cut in range(len(expected)+1):result.append(Case(tree,len(expected),cut%2,schedules(rng,cut)))
    for limit in (0,1,4096):
        for layout in (0,1):result.append(Case(None,limit,layout,()))
    return result


def packet(values):
    output=bytearray()
    for case in values:
        records=flatten(case.tree);body=bytearray()
        for node,parent,key in records:
            body+=struct.pack('<4Q',node.kind,parent&MASK,len(key),len(node.value))+key+node.value
        assert len(body)<=16384 and len(records)<=128 and len(case.actions)<=48
        output+=struct.pack('<5Q',len(records),len(body),case.limit,case.layout,len(case.actions))+body
        for op,offset,count in case.actions:output+=struct.pack('<Iii',op,offset,count)
    return output


def result_header(code,amount=0):return struct.pack('<3Q',code,amount,MASK if code else 0)


def reference(case,counts=None):
    expected=wire(case.tree) if case.tree is not None else b''
    code=1 if case.tree is None else (2 if len(expected)>case.limit else 0)
    if counts is not None:
        counts['rejected' if code else 'admitted']+=1
        counts['wire_bytes']+=len(expected) if not code else 0
    output=bytearray(result_header(code,len(expected) if not code else 0)*3)
    if not code:output+=expected
    if not code:
        output+=struct.pack('<Q',(1 if case.layout else -8)&MASK)
        positions=[0,0];ordinal=0
        def execute(op,offset=0,count=0):
            nonlocal ordinal
            destination=bytearray((157+index*13+ordinal*7)&255 for index in range(64))
            output.append(op)
            if op>=2:
                if op==2:positions[1]=positions[0]
                if op==3:positions[0]=positions[1]
                if op==4:positions[0]=0
                if op==5:positions[1]=0
                output.append(2);output.extend(struct.pack('<Q',0))
                if counts is not None:counts['copies']+=1
                amount=0
            else:
                if counts is not None:counts['reads']+=1
                bad=offset<0 or count<0 or offset>I32_MAX-count
                if bad:
                    output.append(1);output.extend(struct.pack('<Q',1));amount=-1
                    if counts is not None:counts['invalid']+=1
                else:
                    amount=min(count,len(expected)-positions[op])
                    if amount:destination[offset:offset+amount]=expected[positions[op]:positions[op]+amount]
                    positions[op]+=amount;output.append(0);output.extend(struct.pack('<Q',amount))
                    if counts is not None:
                        counts['zero_requests']+=int(count==0);counts['observed_eof']+=int(count>0 and amount==0)
            output.extend(struct.pack('<2Q',len(expected)-positions[0],len(expected)-positions[1]))
            output.extend(destination);ordinal+=1;return amount
        for operation in case.actions:execute(*operation)
        for cursor in range(2):
            turn=0
            while execute(cursor,3,(1,7,13,31)[turn%4])>0:turn+=1;assert turn<=4096
            execute(cursor,I32_MAX,0);execute(cursor,-1,0);execute(cursor,2,3)
        execute(2);execute(1,0,1)
    output+=snapshot(case.tree)
    # Recheck owned encoding after all cursor operations and public queries.
    output+=result_header(code,len(expected) if not code else 0)
    if not code:output+=expected
    return output


def verify(actual,values):
    counts=Counter();position=0
    for ordinal,case in enumerate(values):
        expected=reference(case,counts);observed=actual[position:position+len(expected)]
        if expected!=observed:
            first=next((at for at,pair in enumerate(zip(observed,expected)) if pair[0]!=pair[1]),len(observed))
            raise AssertionError((f'seed={SEED:#x}','case',ordinal,'limit',case.limit,'layout',case.layout,
                                  'tree',case.tree,'actions',case.actions,'byte',first,
                                  'observed',observed[first:first+12],'expected',expected[first:first+12]))
        position+=len(expected)
    assert position==len(actual),('extra output',position,len(actual))
    return counts


def summary(values,counts,suffix=''):
    fields=('admitted','rejected','reads','copies','invalid','zero_requests','observed_eof','wire_bytes')
    return f'json-streaming{suffix} cases={len(values)} layouts=2 '+ ' '.join(f'{key}={counts[key]}' for key in fields)+f' seed={SEED:#x}'


def controls():
    assert quote(b'\0\x08\x0a\x1f"\\/')==b'"\\u0000\\u0008\\u000a\\u001f\\"\\\\/"'
    literal=obj(('x',Node(3,b'1.2300E+05')),('x',string('é\n')))
    assert wire(literal)==b'{"x":1.2300E+05,"x":"\xc3\xa9\\u000a"}'
    values=cases();assert packet(values)
    counts=verify(b''.join(reference(case) for case in values),values)
    base=Case(literal,len(wire(literal)),1,((0,3,5),(2,0,0),(1,1,7)))
    expected=reference(base);wire_start=72;first_action=wire_start+len(wire(literal))+8
    mutations=(0,8,24,48,wire_start+2,wire_start+7,wire_start+12,wire_start+19,
               first_action,first_action+1,first_action+2,first_action+10,first_action+26,len(expected)-1)
    rejected=0
    for offset in mutations:
        corrupted=bytearray(expected);corrupted[offset]^=1
        try:verify(corrupted,[base])
        except AssertionError:rejected+=1
        else:raise AssertionError(('accepted corruption',offset))
    for corrupted in (expected[:-1],expected+b'\0'):
        try:verify(corrupted,[base])
        except AssertionError:rejected+=1
        else:raise AssertionError('accepted framing corruption')
    assert rejected==16
    print(summary(values,counts,' CPU')+' verifier-corruptions=16')


def main():
    if len(sys.argv)==2 and sys.argv[1]=='controls':controls();return
    assert len(sys.argv)==2,'usage: oracle.py <executable> | controls'
    values=cases()
    process=subprocess.run([str(Path(sys.argv[1]).resolve())],input=packet(values),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=75)
    assert process.returncode==0,(process.returncode,process.stderr,len(process.stdout))
    assert not process.stderr,process.stderr
    print(summary(values,verify(process.stdout,values)))


if __name__=='__main__':main()
