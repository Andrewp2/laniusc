"""Independent signed lists, tuple ordering and adjacency predicates."""
from collections import Counter
import csv
from io import StringIO
import itertools
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import sys
import tempfile

CAP=1048576
MAX_COUNT=65536
MINIMUM,MAXIMUM=-(1<<63),(1<<63)-1
HELP=(b"Usage: compare_series [--descending] [--help]\n"
      b"Read CSV side,value from stdin; side is left or right and value is a signed i64.\n"
      b"Preserve the input order within each side, including interleaved rows.\n"
      b"Report counts, equality, lexicographic order and whether each side is sorted.\n"
      b"--descending reverses numeric element order; a shorter equal prefix remains less.\n"
      b"Sortedness allows equal adjacent values. Header-only input means two empty series.\n"
      b"Limits: 1 MiB input, 65536 data rows, 64 decoded bytes per field, 8192 read attempts.\n"
      b"Input is fully validated before output; input errors publish no data.\n"
      b"Short options: -r, -h. Duplicate options and operands are errors.\n"
      b"Help accepts otherwise valid flags and does not read stdin.\n")
ERROR=b"compare_series: operation failed\n"
HEADER=("left_count","right_count","equal","order","left_sorted","right_sorted")
INTEGER=re.compile(rb"[+-]?[0-9]+\Z")
TRACE="read,write,close,mmap,munmap,mremap,brk,rt_sigaction"
COUNTS={"model":44,"rejection":35,"cli":19,"io":21}


def encode(rows,quoted=False,ending="\r\n"):
    stream=StringIO(newline="")
    csv.writer(stream,quoting=csv.QUOTE_ALL if quoted else csv.QUOTE_MINIMAL,lineterminator=ending).writerows(rows)
    return stream.getvalue().encode("ascii")


def input_bytes(left,right,interleaved=False):
    if interleaved:
        rows=[]
        for index in range(max(len(left),len(right))):
            if index<len(left): rows.append(("left",left[index]))
            if index<len(right): rows.append(("right",right[index]))
    else: rows=[("left",value) for value in left]+[("right",value) for value in right]
    return encode([("side","value"),*rows])


def parse_input(data):
    if len(data)>CAP or any(byte<32 and byte not in (10,13) or byte==127 for byte in data): raise ValueError("byte/control cap")
    rows=list(csv.reader(StringIO(data.decode("utf-8","strict"),newline=""),strict=True))
    if not rows or rows[0]!=["side","value"] or len(rows)>MAX_COUNT+1: raise ValueError("schema/count")
    left,right=[],[]
    for row in rows[1:]:
        if len(row)!=2 or row[0] not in ("left","right"): raise ValueError("side/width")
        token=row[1].encode("utf-8")
        if not 1<=len(token)<=64 or not INTEGER.fullmatch(token): raise ValueError("integer syntax/length")
        value=int(token)
        if not MINIMUM<=value<=MAXIMUM: raise ValueError("integer range")
        (left if row[0]=="left" else right).append(value)
    return left,right


def reference(left,right,descending=False):
    assert len(left)+len(right)<=MAX_COUNT and all(MINIMUM<=v<=MAXIMUM for v in (*left,*right))
    a=tuple(-v if descending else v for v in left)
    b=tuple(-v if descending else v for v in right)
    relation="less" if a<b else "greater" if a>b else "equal"
    ordered=lambda values: all(x>=y if descending else x<=y for x,y in zip(values,values[1:]))
    boolean=lambda value: "true" if value else "false"
    return encode([HEADER,(len(left),len(right),boolean(left==right),relation,boolean(ordered(left)),boolean(ordered(right)))],True)


def cap_input():
    normal=b"left,"+b"0"*10+b"\n"
    result=b"side,value\n"+normal*65534+b"left,0\n"+b"left,"+b"0"*8+b"\n"
    assert len(normal)==16 and len(result)==CAP
    return result


def events(text):
    result,counts,live=[],Counter(),{}
    for line in text.splitlines():
        match=re.fullmatch(r"([a-z0-9_]+)\((.*)\)\s+=\s+(.*)",line)
        assert match and match[1] in TRACE.split(","),("unexpected trace line",line)
        name,args,answer=match.groups(); counts[name]+=1
        result.append(dict(name=name,args=args,answer=answer,ordinal=counts[name],line=line))
        if name=="mmap":
            size=int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address=answer.split()[0]; assert address not in live; live[address]=size
            else: assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer,line
        elif name=="munmap":
            address,size=args.split(",")
            assert answer=="0" and live.pop(address.strip(),None)==int(size.strip()),line
        elif name in ("mremap","brk","close"):
            raise AssertionError(("unexpected allocation service/borrowed descriptor close",line))
        elif name=="read": assert args.startswith("0,"),line
        elif name=="write":
            assert int(args.split(",")[0]) in (1,2),line
            assert not live,"publication/diagnostic before all heap owners retire"
    assert not live,("observed unreleased mappings",live)
    return result


class Runner:
    observes=True
    def __init__(self,executable,mode):
        self.executable=str(Path(executable).resolve())
        header=Path(self.executable).read_bytes()[:64]
        assert len(header)==64 and header[:6]==b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18],"little")==2 and int.from_bytes(header[18:20],"little")==62
        self.directory=Path(tempfile.mkdtemp(prefix=f"compare-series-{mode}-")); self.count=0

    def run(self,name,args=(),data=b"",*,status=0,output=b"",trace=False,injections=(),
            read_error=False,closed_stdout=False,diagnostic=True,budget=None,preflight=False,stdout_limit=False):
        prefix=self.directory/name; command=[self.executable,*args]
        if budget:
            maximum=8192 if budget=="read" else 64
            command=["strace","--kill-on-exit","-qq","-c","-e","trace="+budget,"-e",
                     f"inject={budget}:error=EINTR:when=1..{maximum}","-o",str(prefix.with_suffix(".trace")),*command]
        elif trace:
            wrapper=["strace","--kill-on-exit","-qq","-s","32","-e","signal=none","-e","trace="+TRACE,
                     "-o",str(prefix.with_suffix(".trace"))]
            for call,ordinal,failure in injections: wrapper += ["-e",f"inject={call}:error={failure}:when={ordinal}"]
            command=[*wrapper,*command]
        prefix.with_suffix(".command").write_text(repr(command)+"\n"); prefix.with_suffix(".input").write_bytes(data)
        options=dict(timeout=15,check=False,stderr=subprocess.PIPE)
        source=None
        if read_error: source=os.open(self.directory,os.O_RDONLY|os.O_DIRECTORY); options["stdin"]=source
        else: options["input"]=data
        try:
            if stdout_limit:
                assert not trace and not budget and not closed_stdout
                def set_limit():
                    resource.setrlimit(resource.RLIMIT_FSIZE,(10,10)); signal.signal(signal.SIGXFSZ,signal.SIG_IGN)
                with tempfile.TemporaryFile() as target:
                    result=subprocess.run(command,stdout=target,preexec_fn=set_limit,**options)
                    target.seek(0); result.stdout=target.read()
            elif closed_stdout:
                reader,writer=os.pipe(); os.close(reader)
                try: result=subprocess.run(command,stdout=writer,**options)
                finally: os.close(writer)
                result.stdout=b""
            else: result=subprocess.run(command,stdout=subprocess.PIPE,**options)
        finally:
            if source is not None: os.close(source)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode)+"\n")
        assert result.returncode==status and result.stdout==output,(name,result.returncode,status,result.stdout,output,result.stderr)
        assert result.stderr==(ERROR if status and diagnostic else b""),(name,result.stderr)
        found=events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked=[item for item in found if "INJECTED" in item["answer"]]; selected=[]
        for call,ordinal,failure in injections:
            reached=[item for item in found if item["name"]==call and item["ordinal"]==ordinal]
            assert len(reached)==1 and reached[0]["answer"].startswith("-1 "+failure+" ")
            selected += reached
        assert {item["line"] for item in marked}=={item["line"] for item in selected}
        if budget:
            rows=prefix.with_suffix(".trace").read_text().splitlines()
            selected=[row.split() for row in rows if row.split()[-1:]==[budget]]
            expected=["8192","8192","read"] if budget=="read" else ["65","64","write"]
            assert len(selected)==1 and selected[0][-3:]==expected,rows
        if preflight: assert not any(item["name"]=="read" for item in found)
        self.count+=1; return found

    def compare(self,name,left,right,descending=False,*,wire=None,interleaved=False,**kwargs):
        data=input_bytes(left,right,interleaved) if wire is None else wire
        return self.run(name,["--descending"] if descending else [],data,output=reference(left,right,descending),**kwargs)

    def reject(self,name,data,**kwargs): return self.run(name,[],data,status=2,**kwargs)


def model(r):
    pairs=[([],[]),([],[0]),([0],[]),([1,2,2],[1,2,2]),([1],[1,0]),([1,0],[1]),
           ([-9,4],[-8,-100]),([1,1,1,2],[1,1,1,3]),([MINIMUM,0,MAXIMUM],[MINIMUM,0,MINIMUM]),
           ([MAXIMUM],[MINIMUM]),([-1,0,1],[1,0,-1]),([-5]*3,[-5]*3),([0,2,1],[0,1,2]),
           ([2,1,0],[2,1,0]),([2,1],[2,1,0]),([0,0,1,0],[0,0,1,0]),([1,0,0],[1,0,0]),
           ([MINIMUM,MAXIMUM],[MINIMUM,MAXIMUM])]
    for index,(left,right) in enumerate(pairs):
        for descending in (False,True): r.compare(f"pair-{index}-{descending}",left,right,descending)
    for descending in (False,True):
        r.compare(f"interleaved-{descending}",[5,-1,5,0],[-9,4,-9],descending,interleaved=True)
    r.compare("quoted-crlf-unterminated",[1,-2],[3],wire=b'"side","value"\r\n"left","+01"\r\n"right","0003"\r\n"left","-02"')
    r.compare("sixty-four-byte-signed-values",[1],[-1],True,
              wire=b"side,value\nleft,+"+b"0"*62+b"1\nright,-"+b"0"*62+b"1\n")
    r.compare("maximum-combined-one-side",[0]*MAX_COUNT,[])
    left=list(range(32768)); right=list(reversed(left))
    for descending in (False,True): r.compare(f"maximum-combined-interleaved-{descending}",left,right,descending,interleaved=True)
    found=r.compare("maximum-raw-input-and-count",[0]*MAX_COUNT,[],wire=cap_input(),trace=True)
    if r.observes:
        reads=[item for item in found if item["name"]=="read"]
        assert reads[-1]["args"].endswith(", 1") and reads[-1]["answer"]=="0"
        assert sum(int(item["answer"]) for item in reads)==CAP


def rejection(r):
    bad=[b"",b"\n",b"Side,value\n",b"\xef\xbb\xbfside,value\n",b"side,Value\n",b"side\n",b"side,value,extra\n",
         b"side,value\n\n",b"side,value\nleft\n",b"side,value\nleft,1,2\n",b"side,value\nLeft,0\n",
         b"side,value\nunknown,0\n",b"side,value\n,0\n",b"side,value\nleft,\n",b"side,value\nleft,+\n",
         b"side,value\nleft,-\n",b"side,value\nleft, 1\n",b"side,value\nleft,1 \n",b"side,value\nleft,0x1\n",
         b"side,value\nleft,1.0\n",b"side,value\nleft,1e0\n",b"side,value\nleft,1_0\n",b"side,value\nleft,\xd9\xa0\n",
         b"side,value\nleft,\xff\n",b"side,value\nleft,\0\n",b"side,value\nleft,\t1\n",b"side,value\nleft,\x7f\n",
         b"side,value\nleft,9223372036854775808\n",b"side,value\nright,-9223372036854775809\n",
         b"side,value\nleft,"+b"0"*65+b"\n",b'side,value\n"left,1\n',b'side,value\n"left"x,1\n',
         b"side,value\nleft,0\nright,1\nleft,invalid\n"]
    for index,data in enumerate(bad): r.reject(f"invalid-{index}",data)
    r.reject("combined-count-over",b"side,value\n"+b"left,0\n"*(MAX_COUNT+1))
    found=r.reject("raw-byte-over",cap_input()+b"x",trace=True)
    if r.observes:
        reads=[item for item in found if item["name"]=="read"]
        assert reads[-1]["args"].endswith(", 1") and reads[-1]["answer"]=="1"
        assert sum(int(item["answer"]) for item in reads)==CAP+1


def cli(r):
    invalid=[["operand"],["--","operand"],["--unknown"],["--Descending"],["--descending=yes"],["--help=yes"],
             ["--descending","-r"],["-rr"],["--help","-h"],["-hh"],["--help","--unknown"],
             ["--descending","--descending"],["x"]*9,["--help","x"*1019]]
    for index,args in enumerate(invalid): r.run(f"invalid-{index}",args,status=2,trace=True,read_error=True,preflight=True)
    for index,args in enumerate((["--help"],["-h"],["--help","--descending"],["-rh"])):
        r.run(f"help-{index}",args,output=HELP,trace=True,read_error=True,preflight=True)
    r.run("short-descending",["-r"],b"side,value\nleft,2\nright,1\n",output=reference([2],[1],True))


def io(r):
    left=[i-32 for i in range(64)]; right=[32-i for i in range(64)]
    data=input_bytes(left,right,True); args=["--descending"]; wanted=reference(left,right,True)
    def exercise(name,**kwargs):
        status=kwargs.get("status",0); output=kwargs.pop("output",b"" if status else wanted)
        return r.run(name,args,data,output=output,**kwargs)
    baseline=exercise("baseline",trace=True)
    maps=[item for item in baseline if item["name"]=="mmap"]
    eof=next(item for item in baseline if item["name"]=="read" and item["answer"]=="0")
    first_read=next(index for index,item in enumerate(baseline) if item["name"]=="read")
    for owner in maps[:2]:
        freed=next(index for index,item in enumerate(baseline) if index>baseline.index(owner) and item["name"]=="munmap" and item["args"].split(",")[0]==owner["answer"])
        assert freed<baseline.index(maps[2])<first_read
    values=[item for item in maps if baseline.index(item)>baseline.index(eof) and int(item["args"].split(",")[1])==32]
    grown=[item for item in maps if baseline.index(item)>baseline.index(eof) and int(item["args"].split(",")[1])==512]
    assert len(values)>=2 and len(grown)==2
    selected=[maps[0],maps[1],maps[2],values[0],values[1],grown[1],maps[-1]]
    assert len({item["ordinal"] for item in selected})==7
    for old in selected:
        actual=exercise(f"owner-oom-{old['ordinal']}",status=4,trace=True,injections=(("mmap",old["ordinal"],"ENOMEM"),))
        fault=next(item for item in actual if item["name"]=="mmap" and item["ordinal"]==old["ordinal"])
        assert fault["args"]==old["args"]
    r.run("stdin-directory",status=3,trace=True,read_error=True)
    exercise("read-eintr-retry",trace=True,injections=(("read",1,"EINTR"),))
    exercise("later-read-eio",status=3,trace=True,injections=(("read",2,"EIO"),))
    failed=exercise("required-eof-eio",status=3,trace=True,injections=(("read",eof["ordinal"],"EIO"),))
    assert sum(int(item["answer"]) for item in failed if item["name"]=="read" and item["answer"].isdigit())==len(data)
    r.run("input-error-before-schema",[],b"bad header\n",status=3,trace=True,injections=(("read",2,"EIO"),))
    exercise("closed-data-stdout",status=5,trace=True,closed_stdout=True)
    r.run("closed-help-stdout",["--help"],status=5,trace=True,closed_stdout=True)
    exercise("write-eintr-retry",trace=True,injections=(("write",1,"EINTR"),))
    exercise("output-eio",status=5,trace=True,injections=(("write",1,"EIO"),))
    exercise("actual-regular-file-prefix",status=5,output=wanted[:10],stdout_limit=True)
    r.run("signal-setup-eio",status=5,trace=True,injections=(("rt_sigaction",1,"EIO"),),diagnostic=False)
    exercise("read-attempt-cap",status=2,budget="read")
    exercise("output-attempt-cap",status=5,budget="write")


def controls():
    assert len(HELP)==723 and len(ERROR)==33
    assert len(encode([HEADER],True))==73
    literal=b'"left_count","right_count","equal","order","left_sorted","right_sorted"\r\n"0","0","true","equal","true","true"\r\n'
    assert reference([],[])==literal
    assert b'"less"' in reference([1],[1,0],True)
    assert b'"less"' in reference([MAXIMUM],[MINIMUM],True)
    assert parse_input(cap_input())==([0]*MAX_COUNT,[])
    tiny=[list(values) for n in range(4) for values in itertools.product((-1,0,1),repeat=n)]
    for a in tiny:
        for b in tiny:
            for descending in (False,True):
                relation=next(((-1 if x>y else 1) if descending else (-1 if x<y else 1) for x,y in zip(a,b) if x!=y),
                              (len(a)>len(b))-(len(a)<len(b)))
                row=list(csv.reader(StringIO(reference(a,b,descending).decode(),newline="")))[1]
                assert row[3]=={-1:"less",0:"equal",1:"greater"}[relation]
    class CounterOnly:
        observes=False
        def __init__(self): self.count=0
        def run(self,*args,**kwargs): self.count+=1; return []
        def compare(self,name,left,right,descending=False,wire=None,interleaved=False,**kwargs):
            raw=input_bytes(left,right,interleaved) if wire is None else wire
            assert parse_input(raw)==(left,right); reference(left,right,descending); self.count+=1; return []
        def reject(self,name,data,**kwargs):
            try: parse_input(data)
            except (ValueError,csv.Error): pass
            else: raise AssertionError("invalid reference accepted")
            self.count+=1; return []
    for function in (model,rejection,cli):
        runner=CounterOnly(); function(runner)
        assert runner.count==COUNTS[function.__name__]
    good="mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\nwrite(1, X, 1) = 1\n"
    assert len(events(good))==3
    try: events(good.replace("munmap(0x1000, 16) = 0\n",""))
    except AssertionError: pass
    else: raise AssertionError("publication with owned mapping accepted")
    print(f"compare-series CPU controls passed; native cases={sum(COUNTS.values())}")


if __name__=="__main__":
    if sys.argv[1:]==["controls"]: controls()
    else:
        mode,executable=sys.argv[1:]; runner=Runner(executable,mode)
        {"model":model,"rejection":rejection,"cli":cli,"io":io}[mode](runner)
        assert runner.count==COUNTS[mode],(mode,runner.count)
        print(f"compare-series-{mode} cases={runner.count} evidence={runner.directory}")
