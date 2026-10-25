#!/usr/bin/env python3
"""Independent, deliberately direct Unicode17 string-casing test oracle.

The oracle interprets original-input contexts by backward/forward searches,
not the runtime's prefix state. Official WordBreakTest offsets independently
exercise title boundary integration. Binary records are test transport only.
"""
import gzip
import itertools
import random
import struct
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
UCD = ROOT / 'data/unicode/17.0.0'

def read(name):
    return gzip.decompress((UCD / (name + '.gz')).read_bytes()).decode()

def props(name, wanted):
    result = set()
    for raw in read(name).splitlines():
        fields = [x.strip() for x in raw.split('#')[0].split(';')]
        if len(fields) > 1 and fields[1] == wanted:
            r = [int(x, 16) for x in fields[0].split('..')]
            result.update(range(r[0], r[-1] + 1))
    return result

SIMPLE = [{}, {}, {}]
CCC = {}
for raw in read('UnicodeData.txt').splitlines():
    f = raw.split(';'); value = int(f[0], 16)
    CCC[value] = int(f[3])
    for kind, col in enumerate([13, 12, 14]):
        if f[col]: SIMPLE[kind][value] = (int(f[col], 16),)
SPECIAL = {}
for raw in read('SpecialCasing.txt').splitlines():
    line = raw.split('#')[0].strip()
    if line:
        f = [x.strip() for x in line.split(';')]
        maps = [tuple(int(x, 16) for x in f[col].split()) for col in [1, 3, 2]]
        SPECIAL.setdefault(int(f[0], 16), []).append((f[4].split(), maps))
FOLD = {}; TURKIC = {}
for raw in read('CaseFolding.txt').splitlines():
    line = raw.split('#')[0].strip()
    if line:
        f = [x.strip() for x in line.split(';')]
        if f[1] in ('C', 'F', 'T'):
            (TURKIC if f[1] == 'T' else FOLD)[int(f[0],16)] = tuple(int(x,16) for x in f[2].split())
CASED = props('DerivedCoreProperties.txt', 'Cased')
IGNORABLE = props('DerivedCoreProperties.txt', 'Case_Ignorable')
SOFT = props('PropList.txt', 'Soft_Dotted')
WB = {}
for raw in read('auxiliary/WordBreakProperty.txt').splitlines():
    f = [x.strip() for x in raw.split('#')[0].split(';')]
    if len(f) > 1:
        r = [int(x,16) for x in f[0].split('..')]
        for value in range(r[0],r[-1]+1): WB[value] = f[1]
EP = props('emoji/emoji-data.txt','Extended_Pictographic')
IGNORE_WB = {'Extend','Format','ZWJ'}
NL = {'CR','LF','Newline'}
AH = {'ALetter','Hebrew_Letter'}
MID_L = {'MidLetter','MidNumLet','Single_Quote'}
MID_N = {'MidNum','MidNumLet','Single_Quote'}
BASE = AH | {'Numeric','Katakana','ExtendNumLet'}

def boundaries(values):
    """Direct rule evaluation at each offset; no streaming state."""
    classes = [WB.get(v,'Other') for v in values]
    result = {0,len(values)}
    for i in range(1,len(values)):
        raw, current = classes[i-1:i+1]
        if raw == 'CR' and current == 'LF': continue
        if raw in NL or current in NL: result.add(i); continue
        if raw == 'ZWJ' and values[i] in EP: continue
        if raw == current == 'WSegSpace': continue
        if current in IGNORE_WB: continue
        before = [j for j in range(i) if classes[j] not in IGNORE_WB]
        p = classes[before[-1]] if before else 'Other'
        pp = classes[before[-2]] if len(before)>1 else 'Other'
        after = [j for j in range(i+1,len(values)) if classes[j] not in IGNORE_WB]
        n = classes[after[0]] if after else 'Other'
        if p in AH and current in AH: continue
        if p in AH and current in MID_L and n in AH: continue
        if pp in AH and p in MID_L and current in AH: continue
        if p == 'Hebrew_Letter' and current == 'Single_Quote': continue
        if p == 'Hebrew_Letter' and current == 'Double_Quote' and n == 'Hebrew_Letter': continue
        if pp == 'Hebrew_Letter' and p == 'Double_Quote' and current == 'Hebrew_Letter': continue
        if p == current == 'Numeric' or p in AH and current == 'Numeric' or p == 'Numeric' and current in AH: continue
        if pp == 'Numeric' and p in MID_N and current == 'Numeric': continue
        if p == 'Numeric' and current in MID_N and n == 'Numeric': continue
        if p == current == 'Katakana': continue
        if p in BASE and current == 'ExtendNumLet' or p == 'ExtendNumLet' and current in (AH|{'Numeric','Katakana'}): continue
        if p == current == 'Regional_Indicator':
            count = 0
            for j in reversed(before):
                if classes[j] != 'Regional_Indicator': break
                count += 1
            if count % 2: continue
        result.add(i)
    return result

def context(name, values, at):
    if name.startswith('Not_'): return not context(name[4:],values,at)
    if name == 'Final_Sigma':
        left = next((v for v in reversed(values[:at]) if v not in IGNORABLE),None)
        right = next((v for v in values[at+1:] if v not in IGNORABLE),None)
        return left in CASED and right not in CASED
    if name in ('After_I','After_Soft_Dotted'):
        for value in reversed(values[:at]):
            matches = value == 0x49 if name == 'After_I' else value in SOFT
            if matches: return True
            if CCC.get(value,0) in (0,230): return False
        return False
    for value in values[at+1:]:
        if name == 'More_Above' and CCC.get(value,0) == 230: return True
        if name == 'Before_Dot' and value == 0x307: return True
        if CCC.get(value,0) in (0,230): return False
    return False

def scalar_mapping(values, at, kind, locale):
    value = values[at]
    if kind == 3: return TURKIC.get(value,FOLD.get(value,(value,))) if locale == 1 else FOLD.get(value,(value,))
    mapped = SIMPLE[kind].get(value,(value,))
    for conditions, maps in SPECIAL.get(value,[]):
        if all((locale == (2 if c == 'lt' else 1)) if c in ('lt','tr','az') else context(c,values,at) for c in conditions):
            mapped = maps[kind]
    return mapped

def transform(values, kind, locale, word_edges=None):
    edges = boundaries(values) if kind == 2 and word_edges is None else word_edges
    output=[]; seen=False
    for i,value in enumerate(values):
        op = kind
        if kind == 2:
            if i in edges: seen=False
            if seen: op=0
            elif value in CASED: seen=True
            else: output.append(value); continue
        output.extend(scalar_mapping(values,i,op,locale))
    return output

def encoded(values): return ''.join(map(chr,values)).encode()

def emit(values,kind,locale,expected=None,mode=0,limit=10**9,capacity=None,code=0,detail=0):
    source = encoded(values) if not isinstance(values,bytes) else values
    target = encoded(transform(values,kind,locale)) if expected is None else expected
    capacity = len(target) if capacity is None else capacity
    sys.stdout.buffer.write(struct.pack('<BBBBIIQIQI',kind,locale,mode,0,len(source),capacity,limit,code,detail,len(target)))
    sys.stdout.buffer.write(source); sys.stdout.buffer.write(target)

def scalar_cases():
    # NUL prevents every contextual interaction and creates independent words.
    for kind,locale in [(0,0),(1,0),(2,0),(3,0),(3,1)]:
        source=[]; target=[]
        for value in range(0x110000):
            if 0xd800 <= value <= 0xdfff: continue
            source.extend((value,0))
            if kind == 2 and value not in CASED: target.append(value)
            else: target.extend(scalar_mapping([value],0,kind,locale))
            target.append(0)
            if len(source) >= 512:
                emit(source,kind,locale,encoded(target)); source=[]; target=[]
        if source: emit(source,kind,locale,encoded(target))

def context_cases():
    targets=[0x3a3,0x49,0x4a,0x12e,0x307,0x130,0x69,0xcc,0xcd,0x128]
    prefixes=[[],[0x41],[0x345],[0x41,0x345],[0x69],[0x6a],[0x1d422],[0x49],[0x49,0x323],[0x49,0x301],[0x69,0x301],[0x69,0x323],[0x41,0x27],[0x49,0x301,0x323]]
    suffixes=[[],[0x41],[0x345],[0x345,0x41],[0x20],[0x301],[0x307],[0x323,0x307],[0x301,0x307],[0x323,0x301],[0x323,0x41,0x307]]
    for target,prefix,suffix in itertools.product(targets,prefixes,suffixes):
        values=prefix+[target]+suffix
        for kind,locale in itertools.product(range(4),range(3)): emit(values,kind,locale,mode=2)
    # Every Soft_Dotted scalar and every nonzero CCC exercise the exact blockers.
    classes = {}
    for value, ccc in CCC.items():
        if ccc: classes.setdefault(ccc, value)
    for soft in sorted(SOFT):
        for marks in ([0x307],[0x323,0x307],[0x301,0x307]):
            for kind in range(3): emit([soft]+marks,kind,2,mode=2)
    for mark in classes.values():
        for values in ([0x49,mark,0x307],[0x69,mark,0x307],[0x4a,mark,0x301]):
            for kind,locale in itertools.product(range(3),range(3)): emit(list(values),kind,locale,mode=2)
    # Official offsets determine the first-cased/lowercase choice independently.
    rows=0
    for raw in read('auxiliary/WordBreakTest.txt').splitlines():
        tokens=raw.split('#')[0].split()
        if not tokens: continue
        values=[]; edges=set()
        for token in tokens:
            if token=='÷': edges.add(len(values))
            elif token!='×': values.append(int(token,16))
        assert boundaries(values)==edges
        for locale in range(3): emit(values,2,locale,encoded(transform(values,2,locale,edges)),mode=1)
        rows+=1
    assert rows==1944
    rng=random.Random(0xCA5E17)
    alphabet=targets+[0x41,0x3b1,0x345,0x27,0x323,0x301,0x307,0x200d,0x200c,0,0x20,0x1d422,0x34f,0x30a,0xdf,0xfb03,0x1f80]
    for _ in range(256):
        values=rng.choices(alphabet,k=rng.randrange(1,30))
        for kind,locale in itertools.product(range(4),range(3)): emit(values,kind,locale,mode=2)
    for values in [[],[0,0x378,0xfdd0,0xffff,0x10ffff,0xe000],[0x41,0x3a3]+[0x345]*4000,[0x49]+[0x323]*4000+[0x307],[0x69]+[0x323]*4000+[0x307],list(map(ord,'a\''))+[0x301]*4000+list(map(ord,'BC'))]:
        for kind,locale in itertools.product(range(4),range(3)): emit(values,kind,locale,mode=2)
    for invalid,offset in [(b'\x80',0),(b'\xc0\x80',0),(b'\xed\xa0\x80',0),(b'\xf4\x90\x80\x80',0),(b'A\xe2\x82',1),(b'A\xf0\x9f\x92',1)]:
        for kind in range(4): emit(invalid,kind,0,b'',capacity=32,code=2,detail=offset)
    emit([0x130],0,0,b'',capacity=2,code=4,detail=3)
    emit([0x41],0,0,b'',capacity=8,limit=0,code=5,detail=0)
    emit([0x41,0x3a3]+[0x345]*4000,0,0,b'',capacity=16000,limit=5000,code=5,detail=2**64-1)

def python_cases():
    # Host operations are a second oracle only on its assigned repertoire.
    values=[v for v in range(0x110000) if not 0xd800<=v<=0xdfff and unicodedata.category(chr(v))!='Cn'
            and all(unicodedata.category(chr(x))!='Cn' for kind in (0,1,3) for x in scalar_mapping([v],0,kind,0))]
    for at in range(0,len(values),256):
        sample=values[at:at+256]
        text='\0'.join(map(chr,sample))+'\0'
        source=list(map(ord,text))
        for kind,expected in [(0,text.lower()),(1,text.upper()),(3,text.casefold())]:
            authoritative=encoded(transform(source,kind,0))
            assert authoritative==expected.encode(),(unicodedata.unidata_version,at,kind)
            emit(source,kind,0,expected.encode())
    for text in ['ΟΣ','ΑΣ\u0345','\u0345Σ','AΣ\u0345A','AΣ\u0301\u0345','İßﬃ\0ᾀ','I\u0323\u0307',"CAN'T A\u0301Σ"]:
        for kind,expected in [(0,text.lower()),(1,text.upper()),(3,text.casefold())]: emit(list(map(ord,text)),kind,0,expected.encode(),mode=2)

if __name__=='__main__':
    {'scalars':scalar_cases,'contexts':context_cases,'python':python_cases}[sys.argv[1]]()
