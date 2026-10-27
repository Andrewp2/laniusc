"""Finite completion contexts, authored transitions and literal candidate catalogs.

This peer does not parse options. Every complete-word transition and active
context is an authored expectation; candidate filtering is ordinary bytes-prefix
selection over the admitted public schema/value catalog.
"""
from dataclasses import dataclass
from pathlib import Path
import struct
import subprocess
import sys


def W(*values): return struct.pack('<'+'Q'*len(values),*values)
def B(value): return W(len(value))+value


# Declaring node, option ID, short, long, arity, global. Parent fields in the
# native schema are indices, while these expectations use logical identities.
OPTIONS={
    40:[(40,10,b'v',b'verbose','flag',True),
        (40,20,b'C',b'config','required',True),
        (40,30,b'x',b'root-only','flag',False)],
    17:[(17,40,b'q',b'quiet','flag',True),
        (17,30,b'x',b'mode','optional',False),
        (17,50,b'o',b'output','required',False)],
    91:[(91,30,b'x',b'mode','optional',False),
        (91,60,b'f',b'force','flag',False)],
    6:[(6,30,b'x',b'mode','required',False)],
}
PARENT={40:None,17:40,91:17,6:40}
CHILDREN={40:[(17,b'work'),(6,b'list')],17:[(91,b'run')],91:[],6:[]}
KIND={'command':0,'operand':1,'long':2,'short':3,'value':4}
DEFAULT_VALUES=((b'blue',True),(b'black',False),(b'red',True),(b'',False))


@dataclass(frozen=True)
class Context:
    command: int
    operand: int
    kind: str
    prefix: bytes=b''
    stem: bytes=b''
    option: object=None
    enabled: bool=True
    cluster: str='names'
    last: object=None


@dataclass(frozen=True)
class Case:
    name: str
    args: tuple
    argument: int
    byte: int
    context: object=None
    error: object=None
    profile: int=0
    values: tuple=DEFAULT_VALUES


def case(name,args,context,*,argument=None,byte=None,profile=0,values=DEFAULT_VALUES):
    args=tuple(args)
    if argument is None:argument=len(args)
    if byte is None:byte=0 if argument==len(args) else len(args[argument])
    return Case(name,args,argument,byte,context,None,profile,tuple(values))


# Complete-word state is specified here, not computed by a second lexer/router.
CASES=[
    case('empty-root',[],Context(40,0,'command')),
    case('root-command-prefix',[b'wo'],Context(40,0,'command',b'wo'),argument=0),
    case('active-exact-command-not-selected',[b'work'],Context(40,0,'command',b'work'),argument=0),
    case('completed-command-selected',[b'work'],Context(17,0,'command')),
    case('leaf-values',[b'work',b'run'],Context(91,0,'operand')),
    case('sibling-is-leaf',[b'list'],Context(6,0,'operand')),
    case('completed-global-flag',[b'-v'],Context(40,0,'command')),
    case('root-long-prefix',[b'--con'],Context(40,0,'long',b'con',b'--'),argument=0),
    case('root-active-double-dash',[b'--'],Context(40,0,'long',b'',b'--'),argument=0),
    case('root-active-config-name',[b'--config'],Context(40,0,'long',b'config',b'--'),argument=0),
    case('inherited-root-long-prefix',[b'work',b'run',b'--ver'],Context(91,0,'long',b'ver',b'--'),argument=2),
    case('inherited-middle-long-prefix',[b'work',b'run',b'--qu'],Context(91,0,'long',b'qu',b'--'),argument=2),
    case('parent-local-disappeared',[b'work',b'run',b'--root'],Context(91,0,'long',b'root',b'--'),argument=2),
    case('root-required-pending',[b'--config'],Context(40,0,'value',b'',b'',(40,20))),
    case('middle-required-pending',[b'work',b'-o'],Context(17,0,'value',b'',b'',(17,50))),
    case('pending-value-prefix',[b'work',b'-o',b'bl'],Context(17,0,'value',b'bl',b'',(17,50)),argument=2),
    case('pending-command-looking-value',[b'--config',b'work'],Context(40,0,'value',b'work',b'',(40,20)),argument=1),
    case('required-command-value-completed',[b'--config',b'work'],Context(40,0,'command')),
    case('required-dashdash-value-completed',[b'--config',b'--'],Context(40,0,'command')),
    case('attached-long-required',[b'work',b'--config=bl'],Context(17,0,'value',b'bl',b'--config=',(40,20)),argument=1),
    case('attached-long-empty-value',[b'--config='],Context(40,0,'value',b'',b'--config=',(40,20)),argument=0),
    case('attached-optional-value',[b'work',b'--mode=bl'],Context(17,0,'value',b'bl',b'--mode=',(17,30)),argument=1),
    case('completed-optional-not-pending',[b'work',b'-x'],Context(17,0,'command')),
    case('actual-terminator-root',[b'--'],Context(40,0,'operand',enabled=False)),
    case('actual-terminator-middle',[b'work',b'--'],Context(17,0,'operand',enabled=False)),
    case('terminator-command-word-is-operand',[b'work',b'--',b'run'],Context(17,1,'operand',enabled=False)),
    case('operand-index-with-options',[b'work',b'run',b'file',b'-v',b'next'],Context(91,2,'operand')),
    case('options-first-stops-options',[b'work',b'run',b'file',b'--ver'],Context(91,1,'operand',b'--ver',enabled=False),argument=3,profile=1),
    case('intermixed-keeps-options',[b'work',b'run',b'file',b'--ver'],Context(91,1,'long',b'ver',b'--'),argument=3),
    case('operand-literal-prefix',[b'work',b'run',b'bl'],Context(91,0,'operand',b'bl'),argument=2),
    case('raw-byte-prefix',[b'list',b'\xff'],Context(6,0,'operand',b'\xff'),argument=1,
         values=((b'\xffa',True),(b'\xff\x80',False),(b'a',True),(b'\xff',False))),
    case('literal-response-prefix',[b'list',b'@'],Context(6,0,'operand',b'@'),argument=1,
         values=((b'@file',False),(b'plain',True),(b'@@escaped',True),(b'',False))),
]

CASES += [
    case('initial-short-dash',[b'-'],Context(40,0,'short',b'',b'-'),argument=0),
    case('leaf-short-dash',[b'work',b'run',b'-'],Context(91,0,'short',b'',b'-'),argument=2),
    case('leaf-long-dash',[b'work',b'run',b'--'],Context(91,0,'long',b'',b'--'),argument=2),
    case('known-flag-cluster',[b'-v'],Context(40,0,'short',b'',b'-v',cluster='flags',last=(40,10)),argument=0),
    case('inherited-flag-cluster',[b'work',b'run',b'-vq'],Context(91,0,'short',b'',b'-vq',cluster='flags',last=(17,40)),argument=2),
    case('unknown-final-short',[b'-vz'],Context(40,0,'short',b'z',b'-v',cluster='continuations'),argument=0),
    case('required-short-empty',[b'-C'],Context(40,0,'value',b'',b'-C',(40,20)),argument=0),
    case('required-short-attached',[b'-vCbl'],Context(40,0,'value',b'bl',b'-vC',(40,20)),argument=0),
    case('optional-short-empty',[b'work',b'-x'],Context(17,0,'value',b'',b'-x',(17,30)),argument=1),
    case('optional-short-attached',[b'work',b'-qxbl'],Context(17,0,'value',b'bl',b'-qx',(17,30)),argument=1),
    case('sibling-required-short',[b'list',b'-x'],Context(6,0,'value',b'',b'-x',(6,30)),argument=1),
    case('optional-long-name-adds-equals',[b'work',b'--mode'],Context(17,0,'long',b'mode',b'--'),argument=1),
    case('scope-resets-after-selection',[b'-v',b'work',b'-q',b'run'],Context(91,0,'operand')),
    case('completed-operand-prefix',[b'list',b'first',b'second',b'bl'],Context(6,2,'operand',b'bl'),argument=3),
]


def err(name,args,error,*,argument=None,byte=0,profile=0):
    args=tuple(args)
    if argument is None:argument=len(args)
    return Case(name,args,argument,byte,None,error,profile)


# Error tuple is a lossless projection of the actual public nested error:
# kind/declaring command/first location-or-index/second location-or-index.
CASES += [
    err('unknown-complete-long',[b'--bad'],(102,40,0,2)),
    err('unknown-complete-short',[b'work',b'-z'],(102,17,1,1)),
    err('unknown-complete-child',[b'work',b'wrong'],(50,0,1,0)),
    err('unexpected-complete-value',[b'--verbose=x'],(104,40,0,9)),
    err('unknown-earlier-active-short',[b'-zv'],(102,40,0,1),argument=0,byte=3),
    err('unknown-completed-final-short',[b'-vz'],(102,40,0,2)),
    err('active-unknown-long-with-equals',[b'--bad=x'],(102,40,0,2),argument=0,byte=7),
    err('active-flag-value-error',[b'--verbose=x'],(104,40,0,9),argument=0,byte=11),
    err('nul-complete-word',[b'work\0'],(2,0,0,4)),
    err('nul-active-prefix',[b'-\0'],(2,0,0,1),argument=0,byte=2),
    err('cursor-argument-too-large',[],(1,0,0,0),argument=1),
    err('cursor-endpoint-byte-nonzero',[],(1,0,0,0),byte=1),
    err('cursor-byte-too-large',[b'wo'],(1,0,0,0),argument=0,byte=3),
]

# Cursor suffixes are never parsed. The only intentional suffix-dependent field
# is append_space=false while inside the active word; later words change nothing.
CASES += [
    case('command-suffix-nul',[b'wo\0bad',b'--not-real'],Context(40,0,'command',b'wo'),argument=0,byte=2),
    case('long-suffix-independent',[b'--verBAD',b'--invalid'],Context(40,0,'long',b'ver',b'--'),argument=0,byte=5),
    case('long-later-word-independent',[b'--ver',b'\0'],Context(40,0,'long',b'ver',b'--'),argument=0,byte=5),
    case('value-suffix-independent',[b'work',b'--config=bljunk',b'--invalid'],Context(17,0,'value',b'bl',b'--config=',(40,20)),argument=1,byte=11),
    case('short-cluster-suffix-independent',[b'-vz',b'--invalid'],Context(40,0,'short',b'',b'-v',cluster='flags',last=(40,10)),argument=0,byte=2),
    case('dash-suffix-nul',[b'-\0'],Context(40,0,'short',b'',b'-'),argument=0,byte=1),
]

CASES.append(case('long-flag-prefix',[b'--ver'],Context(40,0,'long',b'ver',b'--'),argument=0))
CASES.append(case('duplicate-policy-values',[b'--'],Context(40,0,'operand',enabled=False),values=((b'same',True),(b'same',False))))

def visible(command):
    path=[];current=PARENT[command]
    while current is not None:path.append(current);current=PARENT[current]
    return [option for node in reversed(path) for option in OPTIONS[node] if option[5]]+OPTIONS[command]


def alias(option,long):
    owner,id,short,name,arity,_=option
    if long:return b'--'+name+(b'=' if arity!='flag' else b''),owner,id,'long',arity=='flag'
    return b'-'+short,owner,id,'short',arity=='flag'


def candidates(case):
    ctx=case.context;out=[]
    if ctx.kind in ('command','operand'):
        if ctx.kind=='command':out += [(name,id,-1,'command',True) for id,name in CHILDREN[ctx.command]]
        if ctx.enabled:
            for option in visible(ctx.command):out.extend((alias(option,False),alias(option,True)))
        if ctx.kind=='operand':out += [(value,ctx.command,-1,'operand',space) for value,space in case.values]
        out=[item for item in out if item[0].startswith(ctx.prefix)]
    elif ctx.kind=='long':
        for option in visible(ctx.command):
            if option[3].startswith(ctx.prefix):out.append(alias(option,True))
    elif ctx.kind=='short':
        if ctx.cluster=='flags':out.append((ctx.stem,*ctx.last,'short',True))
        for option in visible(ctx.command):
            if not option[2].startswith(ctx.prefix):continue
            if ctx.stem==b'-':
                out.append(alias(option,False));out.append(alias(option,True))
            else:
                out.append((ctx.stem+option[2],option[0],option[1],'short',option[4]=='flag'))
    else:
        assert ctx.kind=='value'
        owner,id=ctx.option
        out=[(ctx.stem+value,owner,id,'value',space) for value,space in case.values if value.startswith(ctx.prefix)]
    inside=case.argument<len(case.args) and case.byte<len(case.args[case.argument])
    return [(value,owner,id,kind,space and not inside) for value,owner,id,kind,space in out]


def expected(case):
    if case.error is not None:return W(0x434d50,1,*case.error)
    ctx=case.context
    result=W(0x434d50,0,ctx.command,ctx.operand,KIND[ctx.kind])+B(ctx.prefix)+B(ctx.stem)
    result+=W(case.argument,0,case.byte,int(ctx.option is not None))
    if ctx.option is not None:result+=W(*ctx.option)
    for value,owner,id,kind,space in candidates(case):
        result+=W(1)+B(value)+W(owner,id+1,KIND[kind],int(space),case.argument,0,case.byte)
    return result+W(0)


def packet(case):
    assert len(case.args)<=8 and all(len(arg)<=32 for arg in case.args)
    assert len(case.values)<=4 and all(len(value)<=24 for value,_ in case.values)
    result=W(case.profile,len(case.args),case.argument,case.byte,len(case.values))
    result+=b''.join(W(len(arg))+arg.ljust(32,b'\0') for arg in case.args+(b'',)*(8-len(case.args)))
    result+=b''.join(W(len(value))+value.ljust(24,b'\0')+W(int(space)) for value,space in case.values+((b'',False),)*(4-len(case.values)))
    assert len(result)==520
    return result


def compare(actual,reference):
    assert actual==reference,(len(actual),len(reference),next((i for i,(a,b) in enumerate(zip(actual,reference)) if a!=b),None),actual[:120].hex(),reference[:120].hex())


def controls():
    assert len({case.name for case in CASES})==len(CASES)
    assert all(len(packet(case))==520 for case in CASES)
    for sample in (expected(CASES[index]) for index in (0,7,13,19,30,len(CASES)-1)):
        mutation=bytearray(sample);mutation[-1]^=1
        try:compare(bytes(mutation),sample)
        except AssertionError:pass
        else:raise AssertionError('same-case byte mutation accepted')
    lookup={case.name:case for case in CASES}
    for original,changed in [('long-flag-prefix','long-later-word-independent')]:
        assert expected(lookup[original])==expected(lookup[changed])
    for original,changed in [('long-flag-prefix','long-suffix-independent'),('root-command-prefix','command-suffix-nul'),('known-flag-cluster','short-cluster-suffix-independent')]:
        left,right=lookup[original],lookup[changed]
        assert left.context==right.context
        assert [entry[:4] for entry in candidates(left)]==[entry[:4] for entry in candidates(right)]
        assert all(not entry[4] for entry in candidates(right))
    assert candidates(lookup['unknown-final-short'])==[]
    assert [entry[0] for entry in candidates(lookup['raw-byte-prefix'])]==[b'\xffa',b'\xff\x80',b'\xff']
    print('cli-complete model CPU controls passed')


def main():
    if len(sys.argv)==2 and sys.argv[1]=='--self-test':controls();return
    assert len(sys.argv)==2
    process=subprocess.run([str(Path(sys.argv[1]))],input=b''.join(packet(case) for case in CASES),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=15)
    assert process.returncode==0 and process.stderr==b'',process
    compare(process.stdout,b''.join(expected(case) for case in CASES))
    print(f'cli-complete model cases={len(CASES)}')


if __name__=='__main__':main()
