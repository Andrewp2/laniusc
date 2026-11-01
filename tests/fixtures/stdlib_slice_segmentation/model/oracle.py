"""Candidate-cut and callback-prefix reference for borrowed segmentation."""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED=0x5E6A0261109
MASK=(1<<64)-1
BACKING=520

@dataclass(frozen=True)
class Case:
    family:int
    layout:int
    origin:int
    data:bytes
    mode:int
    key:int
    actions:tuple


def action(op,index=0,value=0):return (op,index,value)


def cases():
    rng=random.Random(SEED);profiles=[]
    for size in range(4):
        profiles += [(bytes(values),True) for values in itertools.product((0,10,44,255),repeat=size)]
    for size in range(4,7):
        profiles += [(bytes(values),True) for values in itertools.product((0,44),repeat=size)]
    specials=(b'',b'\0',b',',b',,',b'a,b,',b',a,,b',b'\1\2\2',b'\1\1\2\2\3',
              bytes(range(32)),bytes(range(255,-1,-1)),b'\xff\0\xff\0',b'\r\n\0,\xff',
              b'Z'*127,b','*127,b'\0'*128,b'abbaabba')
    profiles += [(data,True) for data in specials]
    for ordinal in range(64):
        size=(0,1,2,3,7,31,63,127,255,511)[ordinal%10]
        pool=(0,0,0,44,44,10,255,1,2,3) if ordinal%2 else tuple(range(256))
        profiles.append((bytes(rng.choice(pool) for _ in range(size)),False))
    result=[]
    for ordinal,(data,short) in enumerate(profiles):
        # First a complete unedited traversal, then forks, boundary edits,
        # retained views and context-dependent interleavings.
        ops=[action(9),action(0),action(2),action(1),action(4),action(5),action(0),
             action(2),action(11,value=3),action(8),action(1),action(0),
             action(6,0,99),action(8),action(7,2,17),action(1),action(0),
             action(3),action(7,1,44),action(0),action(1),action(4),action(5)]
        for _ in range(18 if short else 36):
            op=rng.choice((0,0,1,1,2,3,4,5,6,7,8,11))
            index=rng.randrange(len(data)) if data else 0
            if op==7:index=rng.randrange(3)
            ops.append(action(op,index,rng.randrange(256)))
        contexts=((0,0),(0,44),(1,10),(2,255)) if short else ((ordinal%3,(ordinal*37)&255),)
        for mode,key in contexts:
            for family in range(3):
                for layout in (0,1):
                    result.append(Case(family,layout,3+(ordinal%3)*2,data,mode,key,tuple(ops)))
    return result


def decision(family,mode,key,tick,left,right=0):
    if family<2:
        if mode==0:return left==key
        if mode==1:return ((left^key)&3)==tick%4
        return (left+key+tick)%5==0
    if mode==0:return left==right
    if mode==1:return ((left^key)&15)<=((right^key)&15)
    return (left+3*right+key+tick)%5!=0


def packet(values):
    output=bytearray()
    for case in values:
        assert len(case.data)<=511 and len(case.actions)<=64
        output+=struct.pack('<7Q',case.family,case.layout,case.origin,len(case.data),case.mode,case.key,len(case.actions))
        output+=case.data
        for op,index,value in case.actions:output+=struct.pack('<BHB',op,index,value)
    return output


class Reference:
    def __init__(self,case,counts=None):
        self.case=case;self.counts=counts
        self.bytes=bytearray((193+index*19)&255 for index in range(BACKING))
        self.bytes[case.origin:case.origin+len(case.data)]=case.data
        self.original=tuple(range(len(case.data)))
        # None is a terminal cursor; an empty tuple remains a pending empty Split.
        self.cursors=[self.original,self.original]
        self.mode=case.mode;self.key=case.key;self.calls=0;self.saved=None
        self.output=bytearray();self.descriptor();self.context()

    def word(self,value):self.output+=struct.pack('<Q',value&MASK)
    def context(self):self.word(self.calls);self.output.extend((self.mode,self.key))
    def descriptor(self):
        self.word(self.case.origin);self.word(len(self.case.data));self.word(1 if self.case.layout else -8)
    def byte_at(self,index):return self.bytes[self.case.origin+index]
    def item(self,span):
        if span is None:self.output.append(0);return
        start,stop=span;self.output.append(1)
        self.word(self.case.origin+start);self.word(stop-start);self.word(1 if self.case.layout else -8)
        self.output+=self.bytes[self.case.origin+start:self.case.origin+stop]

    def pull(self,cursor):
        self.output.append(cursor)
        if self.counts is not None:self.counts['pulls']+=1
        indices=self.cursors[cursor];span=None
        if indices is not None and (indices or self.case.family==0):
            # Evaluate every candidate cut from the current immutable snapshot.
            # Only the prefix through the first boundary becomes observable.
            operands=[(index,self.byte_at(index),0) for index in indices] if self.case.family<2 else [
                (right,self.byte_at(left),self.byte_at(right)) for left,right in zip(indices,indices[1:])]
            candidates=[(index,left,right,decision(self.case.family,self.mode,self.key,self.calls+rank+1,left,right))
                        for rank,(index,left,right) in enumerate(operands)]
            boundary_ranks=[rank for rank,entry in enumerate(candidates) if entry[3]!=(self.case.family==2)]
            rank=boundary_ranks[0] if boundary_ranks else len(candidates)
            events=candidates[:rank+1]
            for _,left,right,answer in events:
                self.calls+=1;self.output.append(160+int(self.case.family==2));self.word(self.calls)
                self.output.extend((self.mode,self.key,left,right,int(answer)))
            if self.counts is not None:self.counts['callbacks']+=len(events)
            start=indices[0] if indices else len(self.case.data)
            if rank==len(candidates):
                span=(start,len(self.case.data));self.cursors[cursor]=None
            else:
                boundary=candidates[rank][0]
                stop=boundary+int(self.case.family==1)
                span=(start,stop)
                next_index=boundary+int(self.case.family<2)
                self.cursors[cursor]=tuple(index for index in indices if index>=next_index)
            self.saved=span
            if self.counts is not None:self.counts['items']+=1
        else:self.cursors[cursor]=None
        self.item(span);self.context()
        return span is None

    def execute(self,op,index=0,value=0):
        if op<2:return self.pull(op)
        self.output.append(op)
        if op in (2,3,4,5):
            if op==2:self.cursors[1]=self.cursors[0]
            if op==3:self.cursors[0]=self.cursors[1]
            if op==4:self.cursors[0]=self.original
            if op==5:self.cursors[1]=self.original
            self.output.append(2)
            if self.counts is not None:self.counts['copies']+=1
        elif op in (6,11):
            if op==11:index=self.saved[1] if self.saved is not None else len(self.case.data)
            self.output.append(3)
            if index<len(self.case.data):
                old=self.byte_at(index);self.bytes[self.case.origin+index]=value
                self.word(index);self.output.extend((old,value))
                if self.counts is not None:self.counts['edits']+=1
            else:self.word(MASK);self.output.extend((0,0))
        elif op==7:
            self.mode=index;self.key=value;self.output.append(4)
            if self.counts is not None:self.counts['context_edits']+=1
        elif op==8:
            self.item(self.saved)
            if self.counts is not None:self.counts['saved_views']+=1
        else:
            assert op in (9,10);self.output.append(5);self.context()
            calls_before=self.calls;cursor=op-9
            for _ in range(len(self.case.data)+2):
                if self.pull(cursor):break
            else:raise AssertionError('unbounded reference drain')
            return self.calls-calls_before
        self.context()

    def run(self):
        for ordinal,operation in enumerate(self.case.actions):
            count=self.execute(*operation)
            if ordinal==0:
                assert count==(len(self.case.data) if self.case.family<2 else max(len(self.case.data)-1,0))
        self.execute(9);self.execute(10)
        self.execute(6,0,191);self.execute(7,2,97);self.execute(8)
        for cursor in (0,1,0,1):assert self.execute(cursor)
        self.execute(2);assert self.execute(1)
        self.descriptor();self.context();self.output+=self.bytes
        return self.output


def verify(actual,values):
    counts=Counter();position=0
    for ordinal,case in enumerate(values):
        expected=Reference(case,counts).run();observed=actual[position:position+len(expected)]
        if observed!=expected:
            first=next((index for index,pair in enumerate(zip(observed,expected)) if pair[0]!=pair[1]),len(observed))
            raise AssertionError((f'seed={SEED:#x}','case',ordinal,'family',case.family,'layout',case.layout,
                                  'mode/key',case.mode,case.key,'data',case.data,'actions',case.actions,
                                  'byte',first,'observed',observed[first:first+8],'expected',expected[first:first+8]))
        position+=len(expected)
    assert position==len(actual),('extra output',position,len(actual))
    return counts


def controls():
    values=cases();assert packet(values)
    # Literal alias witness: the false (1,2) boundary is consumed once. The
    # next pair must reread the edited left operand, rather than retain 2.
    witness=Case(2,1,5,b'\1\2\2',0,0,())
    ref=Reference(witness);assert not ref.pull(0);assert ref.saved==(0,1) and ref.calls==1
    ref.execute(11,value=3);assert not ref.pull(0);assert ref.saved==(1,2) and ref.calls==2
    ref.execute(6,1,9);ref.execute(8);assert ref.byte_at(1)==9
    assert not ref.pull(0);assert ref.saved==(2,3) and ref.calls==2
    assert ref.pull(0);assert ref.calls==2
    for family,expected in ((0,[(0,0),(1,1),(2,2)]),(1,[(0,1),(1,2)]),(2,[(0,2)])):
        sample=Reference(Case(family,1,3,b',,',0,44,()))
        spans=[]
        while not sample.pull(0):spans.append(sample.saved)
        assert spans==expected
    counts=verify(b''.join(Reference(case).run() for case in values),values)
    base=Case(2,1,5,b'\1\2\2',0,0,(action(9),action(4),action(0),action(11,value=3),action(0),action(8)))
    expected=Reference(base).run()
    # Descriptor, action, callback tag/ordinal/operand/answer, returned view
    # metadata/content, retained-view content and final backing/framing.
    offsets=(0,16,34,46,47,55,57,58,59,60,86,len(expected)-1)
    rejected=0
    for offset in offsets:
        corrupted=bytearray(expected);corrupted[offset]^=1
        try:verify(corrupted,[base])
        except AssertionError:rejected+=1
        else:raise AssertionError(('accepted corruption',offset))
    for corrupted in (expected[:-1],expected+b'\0'):
        try:verify(corrupted,[base])
        except AssertionError:rejected+=1
        else:raise AssertionError('accepted framing corruption')
    assert rejected==14
    print(summary(values,counts,' CPU')+' verifier-corruptions=14')


def summary(values,counts,suffix=''):
    return (f'slice-segmentation{suffix} cases={len(values)} families=3 layouts=2 pulls={counts["pulls"]} '
            f'items={counts["items"]} callbacks={counts["callbacks"]} copies={counts["copies"]} '
            f'backing-edits={counts["edits"]} context-edits={counts["context_edits"]} '
            f'saved-views={counts["saved_views"]} seed={SEED:#x}')


def main():
    if len(sys.argv)==2 and sys.argv[1]=='controls':controls();return
    assert len(sys.argv)==2,'usage: oracle.py <executable> | controls'
    values=cases()
    process=subprocess.run([str(Path(sys.argv[1]).resolve())],input=packet(values),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=75)
    assert process.returncode==0,(process.returncode,process.stderr,len(process.stdout))
    assert not process.stderr,process.stderr
    print(summary(values,verify(process.stdout,values)))


if __name__=='__main__':main()
