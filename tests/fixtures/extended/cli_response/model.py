"""Explicit byte-token goldens and independent finite include-tree expectations.

No library implementation lives here. Each file's lexical spans/maps are hand
specified; expansion expectations splice that finite include tree, record source
occurrences and provider calls, and compare the complete native binary receipt.
"""
from dataclasses import dataclass, field
from pathlib import Path
import struct
import subprocess
import sys

MAX=(1<<64)-1


def W(*values): return struct.pack('<'+'Q'*len(values),*(value & MAX for value in values))
def B(value): return W(len(value))+value
def O(origin): return W(origin[0]+1,origin[1]+1,origin[2],origin[3])


@dataclass(frozen=True)
class Token:
    value: bytes
    start: int
    length: int
    positions: tuple


def T(value,start,length,positions=None):
    return Token(value,start,length,tuple(range(len(value))) if positions is None else tuple(positions))


# Positions are relative to each raw token. Endpoints map to its raw end.
GRAMMAR=[
    (b'',[]), (b' \t\r\n',[]), (b'plain',[T(b'plain',0,5)]),
    (b'one\t two\r\nthree',[T(b'one',0,3),T(b'two',5,3),T(b'three',10,5)]),
    (b'""',[T(b'',0,2,[])]), (b"''",[T(b'',0,2,[])]),
    (b"a''b",[T(b'ab',0,4,[0,3])]),
    (b'''ab" c"'d' '' ""''',[T(b'ab cd',0,9,[0,1,3,4,7]),T(b'',10,2,[]),T(b'',13,2,[])]),
    (b'''a\\ b "c\\"d" 'e\\'f' ''',[T(b'a b',0,4,[0,2,3]),T(b'c"d',5,6,[1,3,4]),T(b"e'f",12,6,[1,3,4])]),
    (b'x\\\ny \xff\x80 #$*~',[T(b'x\ny',0,4,[0,2,3]),T(b'\xff\x80',5,2),T(b'#$*~',8,4)]),
    (b'"a\'b"',[T(b"a'b",0,5,[1,2,3])]),
    (b"'a\"b'",[T(b'a"b',0,5,[1,2,3])]),
    (b'a\vb\fc',[T(b'a\vb\fc',0,5)]),
    (b'\xef\xbb\xbfabc',[T(b'\xef\xbb\xbfabc',0,6)]),
    (b'@file @@file @',[T(b'@file',0,5),T(b'@@file',6,6),T(b'@',13,1)]),
    (b'one\\\ttwo',[T(b'one\ttwo',0,8,[0,1,2,4,5,6,7])]),
    (b'"a\\\nb"',[T(b'a\nb',0,6,[1,3,4])]),
]
SYNTAX=[(b'\0',(2,0)),(b'a\0b',(2,1)),(b'\\\0',(2,1)),
        (b'good bad\0later',(2,8)),(b'abc\\',(3,3)),
        (b'"abc',(4,0)),(b"ok 'abc",(4,3)),
        (b'"a\\',(3,2)),(b"'a\\",(3,2)),(b'a""b\'x',(4,4))]
LEX=dict(GRAMMAR)


def lex(raw):
    assert raw in LEX, ('missing explicit lexical golden',raw)
    return LEX[raw]


def grammar_expected(raw,tokens=None,error=None):
    if error is not None: return W(0x525350,0,1,*error)
    decoded=b''.join(token.value for token in tokens)
    out=W(0x525350,0,0,len(tokens),len(decoded))+B(decoded)
    cursor=0
    for token in tokens:
        out+=W(token.start,token.length,cursor,len(token.value))
        out+=W(*(token.positions+(token.length,)))
        cursor+=len(token.value)
    return out


@dataclass
class Case:
    name: str
    args: list
    files: dict = field(default_factory=dict)
    limit: tuple = (99,0)
    cli: int = 0
    oversize: int = 0
    # Fully specified expected failure/effects used for limit/error boundaries.
    # Healthy include-tree cases are modeled independently below.
    failure: object = None


# Limits: arguments,tokens,argbytes,output,filebytes,sourcebytes,files,depth,path,work.
DEFAULT=[16,32,64,512,160,1024,8,4,16,1048576]


def add_lex(raw,tokens):
    assert raw not in LEX or LEX[raw]==tokens
    LEX[raw]=tokens
    return raw


EMPTY=add_lex(b'',[])
ONE=add_lex(b'leaf',[T(b'leaf',0,4)])
BLANK=add_lex(b'""',[T(b'',0,2,[])])
PAIR=add_lex(b'a b',[T(b'a',0,1),T(b'b',2,1)])
ESCAPED=add_lex(b'''pre" two" \\@literal @@tail @''',
                [T(b'pre two',0,9,[0,1,2,4,5,6,7]),T(b'@literal',10,9,[1,2,3,4,5,6,7,8]),T(b'@@tail',20,6),T(b'@',27,1)])
INNER=add_lex(b'''"blue green"''',[T(b'blue green',0,12,range(1,11))])
OUTER=add_lex(b'''first @B last''',[T(b'first',0,5),T(b'@B',6,2),T(b'last',9,4)])
TWICE=add_lex(b'@B @B',[T(b'@B',0,2),T(b'@B',3,2)])
AT=add_lex(b'@@x',[T(b'@@x',0,3)])
CYCLE=add_lex(b'@A',[T(b'@A',0,2)])
DIRECTIVE=add_lex(b'@empty',[T(b'@empty',0,6)])
CLI=add_lex(b'--config @value work @opts -- @post',
            [T(b'--config',0,8),T(b'@value',9,6),T(b'work',16,4),T(b'@opts',21,5),T(b'--',27,2),T(b'@post',30,5)])
OPTS=add_lex(b'run -v',[T(b'run',0,3),T(b'-v',4,2)])
POST=add_lex(b'@@value',[T(b'@@value',0,7)])
WORDS=add_lex(b'work run -v',[T(b'work',0,4),T(b'run',5,3),T(b'-v',9,2)])
BADOPT=add_lex(b'work run "--bad"',[T(b'work',0,4),T(b'run',5,3),T(b'--bad',9,7,range(1,6))])
QUOTEDAT=add_lex(b"'@B'",[T(b'@B',0,4,[1,2])])


CASES=[
    Case('no-args',[]),
    Case('argv-is-already-tokenized',[b'"two words"',b"a'b",b'\\x',b'']),
    Case('literal-at-and-atat',[b'@',b'@@x',b'@@@x'],{b'x':ONE}),
    Case('empty-file',[b'left',b'@empty',b'right'],{b'empty':EMPTY}),
    Case('quoted-empty-file-token',[b'@A'],{b'A':BLANK}),
    Case('nested-depth-first',[b'head',b'@A',b'tail'],{b'A':OUTER,b'B':INNER}),
    Case('repeated-occurrences',[b'@A'],{b'A':TWICE,b'B':ONE}),
    Case('quoted-directive-expands',[b'@A'],{b'A':QUOTEDAT,b'B':ONE}),
    Case('escaped-directive-expands',[b'@A'],{b'A':ESCAPED,b'literal':ONE}),
    Case('dash-is-a-real-file',[b'@-'],{b'-':ONE}),
    Case('raw-path-and-content',[b'@\xff'],{b'\xff':add_lex(b'\xff\x80',[T(b'\xff\x80',0,2)])}),
    Case('nested-atat-provenance',[b'@A'],{b'A':AT}),
    Case('cli-required-values-and-after-terminator',[b'@cli'],{b'cli':CLI,b'value':INNER,b'opts':OPTS,b'post':POST},cli=1),
    Case('cli-required-terminator-is-value',[b'--config',b'--',b'work',b'@opts'],{b'opts':OPTS},cli=1),
    Case('cli-actual-terminator-still-expands',[b'--',b'@A'],{b'A':WORDS},cli=1),
    Case('cli-quoted-error-location',[b'@A'],{b'A':BADOPT},cli=1),
]


# Failure records are explicit boundary expectations, not a copied expansion
# state machine. All partial outputs remain unpublished.
SENTINEL=(-1,-1,0,0)

def failure(kind,at=SENTINEL,*,detail=0,extra=0,originals=(),sources=(),calls=()):
    return ((kind,detail,extra),at,list(originals),list(sources),list(calls))

def loaded(path,at,raw):return (path,at,True,raw)
def unloaded(path,at):return (path,at,False,b'')

for category in range(9):
    CASES.append(Case(f'negative-limit-{category}',[b'@A'],{b'A':ONE},limit=(category,-1),failure=failure(2)))
CASES += [
    Case('initial-nul-before-provider',[b'@A',b'x\0y'],{b'A':ONE},failure=failure(14,(-1,1,1,1),detail=2,extra=1)),
    Case('initial-token-cap',[b'@A',b'x'],{b'A':ONE},limit=(1,1),failure=failure(4)),
    Case('initial-argument-byte-cap',[b'@A',b'long'],{b'A':ONE},limit=(2,3),failure=failure(6,(-1,1,0,4))),
    Case('initial-source-cap',[b'ab',b'cd'],limit=(5,3),failure=failure(3,(-1,1,0,2))),
    Case('initial-work-cap',[b'a'],limit=(9,3),failure=failure(11)),
    Case('zero-allows-empty-input',[],limit=(1,0)),
    Case('zero-token-rejects-empty-token',[b''],limit=(1,0),failure=failure(4)),
    Case('zero-argument-allows-empty-file',[b'@empty'],{b'empty':EMPTY},limit=(0,0)),
    Case('zero-argument-rejects-empty-token',[b''],limit=(0,0),failure=failure(5,(-1,0,0,0),originals=[b''])),
    Case('zero-byte-output-empty-token',[b''],limit=(3,0)),
    Case('zero-argument-bytes-empty-token',[b''],limit=(2,0)),
    Case('zero-output-rejects-real-byte',[b'a'],limit=(3,0),failure=failure(7,(-1,0,0,1),originals=[b'a'])),
    Case('zero-file-byte-empty-file',[b'@empty'],{b'empty':EMPTY},limit=(4,0)),
    Case('zero-files-before-provider',[b'@A'],{b'A':ONE},limit=(6,0),failure=failure(8,(-1,0,0,2),originals=[b'@A'])),
    Case('zero-depth-before-provider',[b'@A'],{b'A':ONE},limit=(7,0),failure=failure(9,(-1,0,0,2),originals=[b'@A'])),
    Case('zero-path-before-provider',[b'@A'],{b'A':ONE},limit=(8,0),failure=failure(10,(-1,0,0,2),originals=[b'@A'])),
    Case('zero-work-empty-input',[],limit=(9,0)),
    Case('directive-count-exact',[b'@A'],{b'A':DIRECTIVE,b'empty':EMPTY},limit=(1,2)),
    Case('file-token-count-exact',[b'@A'],{b'A':ONE},limit=(1,2)),
    Case('file-token-count-too-small',[b'@A'],{b'A':ONE},limit=(1,1),failure=failure(4,(0,-1,0,4),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),ONE)],calls=[(b'A',160)])),
    Case('output-count-exact',[b'@A'],{b'A':PAIR},limit=(0,2)),
    Case('output-count-one-below',[b'@A'],{b'A':PAIR},limit=(0,1),failure=failure(5,(0,-1,2,1),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),PAIR)],calls=[(b'A',160)])),
    Case('output-bytes-exact',[b'@A'],{b'A':PAIR},limit=(3,2)),
    Case('output-bytes-one-below',[b'@A'],{b'A':PAIR},limit=(3,1),failure=failure(7,(0,-1,2,1),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),PAIR)],calls=[(b'A',160)])),
    Case('file-argument-bytes',[b'@A'],{b'A':ONE},limit=(2,3),failure=failure(6,(0,-1,0,4),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),ONE)],calls=[(b'A',160)])),
    Case('file-byte-grant-exact',[b'@A'],{b'A':ONE},limit=(4,4)),
    Case('source-byte-grant-exact',[b'@A'],{b'A':ONE},limit=(5,6)),
    Case('source-byte-lowered-provider-grant',[b'@A'],{b'A':ONE},limit=(5,5),failure=failure(15,(0,-1,0,0),detail=600,extra=1,originals=[b'@A'],sources=[unloaded(b'A',(-1,0,0,2))],calls=[(b'A',3)])),
    Case('work-exact',[b'@A'],{b'A':ONE},limit=(9,34)),
    Case('work-final-descriptor',[b'@A'],{b'A':ONE},limit=(9,33),failure=failure(11,(0,-1,0,4),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),ONE)],calls=[(b'A',6)])),
    Case('work-file-decoding-preflight',[b'@A'],{b'A':ONE},limit=(9,32),failure=failure(11,(0,-1,0,4),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),ONE)],calls=[(b'A',6)])),
    Case('work-lowered-provider-grant',[b'@A'],{b'A':ONE},limit=(9,23),failure=failure(15,(0,-1,0,0),detail=600,extra=1,originals=[b'@A'],sources=[unloaded(b'A',(-1,0,0,2))],calls=[(b'A',3)])),
    Case('oversized-provider-contract',[b'@A'],{b'A':ONE},limit=(4,0),oversize=1,failure=failure(13,(0,-1,0,0),originals=[b'@A'],sources=[unloaded(b'A',(-1,0,0,2))],calls=[(b'A',0)])),
    Case('nominal-provider-error',[b'@bad'],{b'bad':777},failure=failure(15,(0,-1,0,0),detail=777,extra=3,originals=[b'@bad'],sources=[unloaded(b'bad',(-1,0,0,4))],calls=[(b'bad',160)])),
    Case('missing-provider-key',[b'@missing'],failure=failure(15,(0,-1,0,0),detail=404,extra=7,originals=[b'@missing'],sources=[unloaded(b'missing',(-1,0,0,8))],calls=[(b'missing',160)])),
    Case('syntax-error-keeps-loaded-source',[b'@A'],{b'A':b'good "bad'},failure=failure(14,(0,-1,5,1),detail=4,extra=5,originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),b'good "bad')],calls=[(b'A',160)])),
    Case('cycle-depth-cap',[b'@A'],{b'A':CYCLE},limit=(7,2),failure=failure(9,(1,-1,0,2),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),CYCLE),loaded(b'A',(0,-1,0,2),CYCLE)],calls=[(b'A',160),(b'A',160)])),
    Case('repeated-file-cap',[b'@empty',b'@empty'],{b'empty':EMPTY},limit=(6,1),failure=failure(8,(-1,1,0,6),originals=[b'@empty',b'@empty'],sources=[loaded(b'empty',(-1,0,0,6),EMPTY)],calls=[(b'empty',160)])),
]
LATE=add_lex(b'@B long',[T(b'@B',0,2),T(b'long',3,4)])
CASES.append(Case('all-file-tokens-preflight-before-child',[b'@A'],{b'A':LATE,b'B':ONE},limit=(2,3),failure=failure(6,(0,-1,3,4),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),LATE)],calls=[(b'A',160)])))

LONG_DIRECTIVE=add_lex(b'@long',[T(b'@long',0,5)])
CASES += [
    Case('zero-source-empty-token',[b''],limit=(5,0)),
    Case('zero-source-rejects-byte',[b'a'],limit=(5,0),failure=failure(3,(-1,0,0,1))),
    Case('file-empty-token-counted',[b'@A'],{b'A':BLANK},limit=(1,1),failure=failure(4,(0,-1,0,2),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),BLANK)],calls=[(b'A',160)])),
    Case('file-directive-counted',[b'@A'],{b'A':DIRECTIVE,b'empty':EMPTY},limit=(1,1),failure=failure(4,(0,-1,0,6),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),DIRECTIVE)],calls=[(b'A',160)])),
    Case('file-directive-argument-byte-cap',[b'@A'],{b'A':LONG_DIRECTIVE},limit=(2,3),failure=failure(6,(0,-1,0,5),originals=[b'@A'],sources=[loaded(b'A',(-1,0,0,2),LONG_DIRECTIVE)],calls=[(b'A',160)])),
]

def limits(case):
    values=DEFAULT.copy()
    if case.limit[0] < 10: values[case.limit[0]]=case.limit[1]
    return values


# Explicit CLI events after the known expanded sequences. No second lexer.
def C(id,arg): return W(1,id,arg,0)
def V(owner,id,arg,byte=1,value=None):
    out=W(2,owner,id,arg,byte,int(value is not None))
    if value is not None:
        at,offset,payload=value;out+=W(at,offset)+B(payload)
    return out

def P(owner,arg,value): return W(3,owner,arg,0)+B(value)


class Healthy:
    def __init__(self,case):
        self.case=case;self.outputs=[];self.sources=[];self.calls=[]
        self.originals=case.args.copy();self.work=3*sum(map(len,case.args))+len(case.args)
        self.sourcebytes=sum(map(len,case.args))
        self.expand([(arg,(-1,i,0,len(arg)),tuple(range(len(arg)))) for i,arg in enumerate(case.args)],0)

    def expand(self,tokens,depth):
        # This independent recursion walks a finite fixture tree. Production
        # must instead use its explicit owner/frame stack and retained offsets.
        for value,origin,mapping in tokens:
            if value.startswith(b'@@'):
                self.outputs.append((value[1:],origin,mapping[1:]+(origin[3],)))
            elif value.startswith(b'@') and len(value)>1:
                path=value[1:];raw=self.case.files[path]
                assert isinstance(raw,bytes)
                source=len(self.sources)
                self.work+=1
                grant=min(limits(self.case)[4],limits(self.case)[5]-self.sourcebytes,
                          (limits(self.case)[9]-self.work)//4)
                self.calls.append((path,grant))
                self.sources.append((path,origin,True,raw))
                children=lex(raw);self.sourcebytes+=len(raw)
                self.work+=4*len(raw)+sum(2*len(token.value)+1 for token in children)
                self.expand([(token.value,(source,-1,token.start,token.length),token.positions)
                             for token in children],depth+1)
            else:
                self.outputs.append((value,origin,mapping+(origin[3],)))
            # @@ has emitted a final descriptor; @directive has not.
            if not(value.startswith(b'@') and len(value)>1 and not value.startswith(b'@@')):
                self.work+=1

    def locate(self,index,byte):
        value,origin,mapping=self.outputs[index]
        assert 0<=byte<=len(value)
        return origin[0],origin[1],origin[2]+mapping[byte],int(byte<len(value))


def cli_expected(case,state):
    if not case.cli: return W(0)
    name=case.name
    if name=='cli-required-values-and-after-terminator':
        flat=V(40,1,0,2,(1,0,b'blue green'))+P(40,2,b'work')+P(40,3,b'run')+V(40,2,4)+P(40,6,b'@value')+W(0,40)
        hierarchy=V(40,1,0,2,(1,0,b'blue green'))+C(17,2)+C(91,3)+V(40,2,4)+P(91,6,b'@value')+W(0,91)
    elif name=='cli-required-terminator-is-value':
        flat=V(40,1,0,2,(1,0,b'--'))+P(40,2,b'work')+P(40,3,b'run')+V(40,2,4)+W(0,40)
        hierarchy=V(40,1,0,2,(1,0,b'--'))+C(17,2)+C(91,3)+V(40,2,4)+W(0,91)
    elif name=='cli-actual-terminator-still-expands':
        flat=P(40,1,b'work')+P(40,2,b'run')+P(40,3,b'-v')+W(0,40)
        hierarchy=flat
    else:
        assert name=='cli-quoted-error-location'
        mapped=O(state.locate(2,2))
        flat=P(40,0,b'work')+P(40,1,b'run')+W(4,40,2,2,2)+mapped+W(0,40)
        hierarchy=C(17,0)+C(91,1)+W(4,91,2,2,2)+mapped+W(0,91)
    return W(1)+flat+hierarchy


def failure_expected(case):
    cause,at,originals,sources,calls=case.failure
    out=W(0x525350,1,1,*cause)+O(at)+W(len(calls))
    for path,grant in calls:out+=B(path)+W(grant)
    out+=W(0,0)+W(len(originals))
    for value in originals:out+=B(value)
    out+=W(len(sources))
    for path,origin,loaded,raw in sources:out+=B(path)+O(origin)+W(loaded)+B(raw)
    return out+W(0,1)


def healthy_expected(case):
    if case.failure is not None:return failure_expected(case)
    state=Healthy(case)
    out=W(0x525350,1,0)+W(len(state.calls))
    for path,grant in state.calls:out+=B(path)+W(grant)
    out+=W(1,len(state.outputs))
    for i,(value,origin,mapping) in enumerate(state.outputs):
        out+=B(value)+O(origin)
        out+=b''.join(O(state.locate(i,byte)) for byte in range(len(value)+1))
    out+=W(len(state.originals))
    for value in state.originals:out+=B(value)
    out+=W(len(state.sources))
    for path,origin,loaded,raw in state.sources:out+=B(path)+O(origin)+W(loaded)+B(raw)
    out+=cli_expected(case,state)+W(1)
    return out


def packet_pure(raw):
    assert len(raw)<=160
    return W(0,len(raw),0,0,0,0,0,0)+raw.ljust(1248,b'\0')


def packet(case):
    assert len(case.args)<=8 and len(case.files)<=4
    header=W(1,case.cli,len(case.args),len(case.files),*case.limit,case.oversize,1)
    args=b''.join((W(len(arg))+arg.ljust(48,b'\0')) for arg in case.args+[b'']*(8-len(case.args)))
    files=b''
    for path,value in case.files.items():
        content=value if isinstance(value,bytes) else b''
        code=0 if isinstance(value,bytes) else value
        assert len(path)<=16 and len(content)<=160
        files+=W(len(path))+path.ljust(16,b'\0')+W(len(content))+content.ljust(160,b'\0')+W(code)
    return header+args+files.ljust(800,b'\0')


def compare(actual,reference):
    assert actual==reference,(len(actual),len(reference),next((i for i,(a,b) in enumerate(zip(actual,reference)) if a!=b),None),actual[:80].hex(),reference[:80].hex())


def controls():
    # Every token's authored raw byte is precisely its decoded byte; endpoints
    # and spans remain distinct, including empty and adjacent quoted pieces.
    for raw,tokens in LEX.items():
        last=0
        for token in tokens:
            assert token.start>=last and token.length>0 and len(token.positions)==len(token.value)
            assert bytes(raw[token.start+at] for at in token.positions)==token.value
            last=token.start+token.length
        assert len(packet_pure(raw))==1312
    samples=[grammar_expected(raw,tokens) for raw,tokens in GRAMMAR[:4]]
    samples += [healthy_expected(case) for case in CASES[:4]]
    for sample in samples:
        mutated=bytearray(sample);mutated[-1]^=1
        try:compare(bytes(mutated),sample)
        except AssertionError:pass
        else:raise AssertionError('same-case mutation accepted')
    for case in CASES:
        assert len(packet(case))==1312
        if case.failure is not None:
            continue
        state=Healthy(case)
        assert all(len(mapping)==len(value)+1 for value,_,mapping in state.outputs)
        assert all(state.locate(i,len(value))[3]==0 for i,(value,_,_) in enumerate(state.outputs))
        assert state.work<=limits(case)[9] and state.sourcebytes<=limits(case)[5]
    print('cli-response model CPU controls passed')


def main():
    if len(sys.argv)==2 and sys.argv[1]=='--self-test':controls();return
    assert len(sys.argv)==2
    commands=[packet_pure(raw) for raw,_ in GRAMMAR]+[packet_pure(raw) for raw,_ in SYNTAX]+[packet(case) for case in CASES]
    reference=b''.join(grammar_expected(raw,tokens) for raw,tokens in GRAMMAR)
    reference+=b''.join(grammar_expected(raw,error=error) for raw,error in SYNTAX)
    reference+=b''.join(healthy_expected(case) for case in CASES)
    result=subprocess.run([str(Path(sys.argv[1]))],input=b''.join(commands),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
    assert result.returncode==0 and result.stderr==b'',result
    compare(result.stdout,reference)
    print(f'cli-response model cases={len(commands)}')


if __name__=='__main__':main()
