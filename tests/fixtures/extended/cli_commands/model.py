"""Curated lexical expectations + a tiny independent command-scope model.

The canonical flat lexer defines spellings/locations. This file does not parse
options: each finite sequence states those expected events explicitly. The
separate scope model checks command-parent/owner/current invariants, then the
complete binary event stream must match the actual public hierarchy parser.
"""
from pathlib import Path
import struct
import subprocess
import sys


def words(*values):
    return struct.pack('<'+'Q'*len(values), *values)


def command(id, argument):
    return (1, id, argument, 0)


def option(owner, id, argument, byte=1, value=None):
    return (2, owner, id, argument, byte, value)


def operand(owner, argument, value):
    return (3, owner, argument, 0, value)


def error(current, kind, argument, byte):
    return (4, current, kind, argument, byte)


def encoded(event):
    tag = event[0]
    if tag in (1,4):
        return words(*event)
    if tag == 2:
        *header,value = event
        data = words(*header, int(value is not None))
        if value is not None:
            argument,byte,payload = value
            data += words(argument,byte,len(payload))+payload
        return data
    *header,payload = event
    return words(*header,len(payload))+payload


C,O,P,E = command,option,operand,error
# kind1 = unknown child; 2/3/4 = canonical unknown/missing/unexpected option.
CASES = [
    ('empty-root',0,[],[],40),
    ('root-option',0,[b'-v'],[O(40,10,0)],40),
    ('optional-child-policy',0,[b'work'],[C(17,0)],17),
    ('optional-operands-policy',0,[b'work',b'run'],[C(17,0),C(91,1)],91),
    ('sibling-id-not-index',0,[b'list'],[C(6,0)],6),
    ('scope-reset-and-all-ancestors',0,[b'-v',b'work',b'-q',b'run',b'-vf'],
     [O(40,10,0),C(17,1),O(17,40,2),C(91,3),O(40,10,4),O(91,60,4,2)],91),
    ('required-command-is-value',0,[b'--config',b'work',b'run'],
     [O(40,20,0,2,(1,0,b'work')),E(40,1,2,0)],40),
    ('attached-value-keeps-routing',0,[b'--config=work',b'work',b'run'],
     [O(40,20,0,2,(0,9,b'work')),C(17,1),C(91,2)],91),
    ('optional-never-eats-child',0,[b'work',b'-x',b'run'],[C(17,0),O(17,30,1),C(91,2)],91),
    ('attached-and-empty-optional',0,[b'work',b'-xblue',b'run',b'--mode='],
     [C(17,0),O(17,30,1,1,(1,2,b'blue')),C(91,2),O(91,30,3,2,(3,7,b''))],91),
    ('short-value-retains-equals',0,[b'work',b'run',b'-x=red'],
     [C(17,0),C(91,1),O(91,30,2,1,(2,2,b'=red'))],91),
    ('branch-required-eats-child',0,[b'work',b'--output',b'run'],
     [C(17,0),O(17,50,1,2,(2,0,b'run'))],17),
    ('required-terminator-is-value',0,[b'--config',b'--',b'work',b'run'],
     [O(40,20,0,2,(1,0,b'--')),C(17,2),C(91,3)],91),
    ('root-actual-terminator',0,[b'--',b'work',b'run',b'-v'],
     [P(40,1,b'work'),P(40,2,b'run'),P(40,3,b'-v')],40),
    ('branch-actual-terminator',0,[b'work',b'--',b'run',b'-v'],
     [C(17,0),P(17,2,b'run'),P(17,3,b'-v')],17),
    ('current-intermixed-order',0,[b'work',b'run',b'file',b'-v'],
     [C(17,0),C(91,1),P(91,2,b'file'),O(40,10,3)],91),
    ('current-options-first-order',1,[b'work',b'run',b'file',b'-v'],
     [C(17,0),C(91,1),P(91,2,b'file'),P(91,3,b'-v')],91),
    ('sibling-required-attached',0,[b'list',b'-xrun',b'work'],
     [C(6,0),O(6,30,1,1,(1,2,b'run')),P(6,2,b'work')],6),
    ('sibling-required-next',0,[b'list',b'-x',b'work',b'-v'],
     [C(6,0),O(6,30,1,1,(2,0,b'work')),O(40,10,3)],6),
    ('branch-global-not-sibling',0,[b'list',b'-q'],[C(6,0),E(6,2,1,1)],6),
    ('leaf-local-not-parent',0,[b'work',b'-f'],[C(17,0),E(17,2,1,1)],17),
    ('parent-local-not-leaf',0,[b'work',b'run',b'--root-only'],[C(17,0),C(91,1),E(91,2,2,2)],91),
    ('bundle-error-is-sticky',0,[b'work',b'run',b'-vz',b'list'],
     [C(17,0),C(91,1),O(40,10,2),E(91,2,2,2)],91),
    ('missing-value-location',0,[b'work',b'--output'],[C(17,0),E(17,3,1,2)],17),
    ('raw-and-empty-operands',0,[b'work',b'run',b'\0\xff',b''],
     [C(17,0),C(91,1),P(91,2,b'\0\xff'),P(91,3,b'')],91),
    ('bundle-required-value',0,[b'work',b'-vo',b'run'],
     [C(17,0),O(40,10,1),O(17,50,1,2,(2,0,b'run'))],17),
    ('flag-value-location',0,[b'work',b'run',b'--verbose=yes'],
     [C(17,0),C(91,1),E(91,4,2,9)],91),
    ('same-id-local-reuse',0,[b'-x',b'work',b'-x',b'run',b'-x'],
     [O(40,30,0),C(17,1),O(17,30,2),C(91,3),O(91,30,4)],91),
]


def expected(case):
    _,_,args,events,final = case
    current = 40
    parent = {17:40,91:17,6:40}
    visible = {40:{(40,10),(40,20),(40,30)},
               17:{(40,10),(40,20),(17,40),(17,30),(17,50)},
               91:{(40,10),(40,20),(17,40),(91,30),(91,60)},
               6:{(40,10),(40,20),(6,30)}}
    selecting = True; failed = False
    output = words(0x434c49,current)
    for event in events:
        assert not failed
        if event[0] == 1:
            assert selecting and parent[event[1]] == current
            current = event[1]
        elif event[0] == 2:
            assert (event[1],event[2]) in visible[current]
        elif event[0] == 3:
            assert event[1] == current
            selecting = False
        else:
            assert event[1] == current
            failed = True
        # Every located event refers to the logical argument view, despite the
        # native descriptor/token views starting away from backing index zero.
        argument = event[2] if event[0] in (1,3) else event[3]
        assert 0 <= argument < len(args)
        output += encoded(event)
    assert final == current
    return output+words(0,current)


def packet(case):
    _,profile,args,_,_ = case
    assert len(args) <= 8 and all(len(arg) <= 32 for arg in args)
    return words(profile,len(args))+b''.join(words(len(arg))+arg.ljust(32,b'\0') for arg in args+[b'']*(8-len(args)))


def compare(actual, expected_bytes):
    assert actual == expected_bytes, (len(actual),len(expected_bytes),
        next((i for i,(a,b) in enumerate(zip(actual,expected_bytes)) if a != b),None),
        actual[:128].hex(),expected_bytes[:128].hex())


def controls():
    baseline = b''.join(expected(case) for case in CASES)
    assert len(CASES) == 28
    assert len({case[0] for case in CASES}) == 28
    assert all(len(packet(case)) == 336 for case in CASES)
    # Reject missing/trailing bytes, a changed magic byte, and four same-length
    # changes to each selected case's final tag word. No native execution here.
    mutations = [(baseline[:-1],baseline),(baseline+b'\0',baseline),
                 (bytes([baseline[0]^1])+baseline[1:],baseline)]
    for case in (CASES[5],CASES[9],CASES[24],CASES[26]):
        original = expected(case)
        sample = bytearray(original); sample[-9] ^= 1
        mutations.append((bytes(sample),original))
    for mutation,reference in mutations:
        try: compare(mutation,reference)
        except AssertionError: pass
        else: raise AssertionError('negative byte-stream control accepted')
    # The independent scope checks reject impossible owner/parent choices.
    for bad in [('',0,[b'work'],[C(91,0)],91),
                ('',0,[b'work',b'-v'],[C(17,0),O(91,60,1)],17),
                ('',0,[b'list',b'word',b'run'],[C(6,0),P(6,1,b'word'),C(91,2)],91)]:
        try: expected(bad)
        except AssertionError: pass
        else: raise AssertionError('invalid scope control accepted')
    print('cli-commands model CPU controls=13')


def main():
    if len(sys.argv) == 2 and sys.argv[1] == '--self-test':
        controls(); return
    assert len(sys.argv) == 2
    executable = Path(sys.argv[1])
    result = subprocess.run([str(executable)],input=b''.join(packet(case) for case in CASES),
                            stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=15)
    assert result.returncode == 0 and result.stderr == b'', result
    compare(result.stdout,b''.join(expected(case) for case in CASES))
    print('cli-commands routing cases=28')


if __name__ == '__main__':
    main()
