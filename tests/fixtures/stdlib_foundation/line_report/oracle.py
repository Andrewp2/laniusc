"""Independent byte/LF splitting and strict UTF-8 counts for owned records."""
from collections import Counter
import csv
from io import StringIO
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

CAP=4194304
MAX_RECORDS=16384
MAX_BYTES=1048576
HELP=(b"Usage: line_report [--text] [--max-bytes N] [--help]\n"
      b"Read LF-separated records from stdin and print quoted CRLF CSV: record,bytes,scalars,ending.\n"
      b"Record positions start at zero; bytes include LF and any preceding CR.\n"
      b"Binary scalar fields are empty; --text requires UTF-8 and counts every Unicode scalar.\n"
      b"Endings are lf or eof; a final unterminated record is kept and empty EOF adds no row.\n"
      b"N is 0..1048576, default 65536, including LF. Leading zeros are allowed.\n"
      b"Limits: 4 MiB input, 16384 records and 1 MiB staged output.\n"
      b"Input permits 131072 buffered operations and output 2048 attempts; interruptions spend budgets.\n"
      b"Input is fully processed before output; input errors publish no data.\n"
      b"Short options: -t, -m N, -h. Duplicate options and operands are errors.\n"
      b"Help accepts otherwise valid options and does not read stdin.\n")
ERROR=b"line_report: operation failed\n"
HEADER=("record","bytes","scalars","ending")
TRACE="read,write,close,mmap,munmap,mremap,brk,rt_sigaction"
COUNTS={"model":43,"rejection":33,"cli":34,"quota":2,"io":19}


def encode(rows):
    stream=StringIO(newline="")
    csv.writer(stream,quoting=csv.QUOTE_ALL,lineterminator="\r\n").writerows(rows)
    return stream.getvalue().encode("ascii")


def split_records(data):
    parts=data.split(b"\n")
    records=[(part+b"\n","lf") for part in parts[:-1]]
    if parts[-1]: records.append((parts[-1],"eof"))
    return records


def reference(data,text=False,maximum=65536):
    if not 0<=maximum<=MAX_BYTES or len(data)>CAP: raise ValueError("byte cap")
    records=split_records(data)
    if len(records)>MAX_RECORDS: raise ValueError("record count")
    rows=[HEADER]
    for index,(record,ending) in enumerate(records):
        if len(record)>maximum: raise ValueError("record cap")
        scalars=len(record.decode("utf-8","strict")) if text else ""
        rows.append((index,len(record),scalars,ending))
    return encode(rows)


def options(text=False,maximum=None):
    return (["--text"] if text else [])+([] if maximum is None else ["--max-bytes",str(maximum)])


def events(trace):
    result,counts,live=[],Counter(),{}
    for line in trace.splitlines():
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
            if args.startswith("2,"): assert not live,"diagnostic before explicit owner retirement"
    assert not live,("observed unreleased mappings",live)
    return result


class Runner:
    observes=True
    def __init__(self,executable,mode):
        self.executable=str(Path(executable).resolve())
        header=Path(self.executable).read_bytes()[:64]
        assert len(header)==64 and header[:6]==b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18],"little")==2 and int.from_bytes(header[18:20],"little")==62
        self.directory=Path(tempfile.mkdtemp(prefix=f"line-report-{mode}-")); self.count=0

    def run(self,name,args=(),data=b"",*,status=0,output=b"",trace=False,injections=(),
            read_error=False,closed_stdout=False,diagnostic=True,budget=None,preflight=False,interruption_schedule=None):
        prefix=self.directory/name; command=[self.executable,*args]
        if budget:
            call,errors,calls=budget
            schedule=f"1..{errors}" if interruption_schedule is None else interruption_schedule
            command=["strace","--kill-on-exit","-qq","-c","-e","trace="+call,"-e",
                     f"inject={call}:error=EINTR:when={schedule}","-o",str(prefix.with_suffix(".trace")),*command]
        elif trace:
            wrapper=["strace","--kill-on-exit","-qq","-s","32","-e","signal=none","-e","trace="+TRACE,
                     "-o",str(prefix.with_suffix(".trace"))]
            for call,ordinal,failure in injections: wrapper += ["-e",f"inject={call}:error={failure}:when={ordinal}"]
            command=[*wrapper,*command]
        prefix.with_suffix(".command").write_text(repr(command)+"\n"); prefix.with_suffix(".input").write_bytes(data)
        if read_error:
            descriptor=os.open(self.directory,os.O_RDONLY|os.O_DIRECTORY)
            try: result=subprocess.run(command,stdin=descriptor,capture_output=True,timeout=15,check=False)
            finally: os.close(descriptor)
        elif closed_stdout:
            reader,writer=os.pipe(); os.close(reader)
            try: result=subprocess.run(command,input=data,stdout=writer,stderr=subprocess.PIPE,timeout=15,check=False)
            finally: os.close(writer)
            result.stdout=b""
        else: result=subprocess.run(command,input=data,capture_output=True,timeout=15,check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode)+"\n")
        assert result.returncode==status and result.stdout==output,(name,result.returncode,status,len(result.stdout),len(output),result.stderr)
        assert result.stderr==(ERROR if status and diagnostic else b""),(name,result.stderr)
        found=events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked=[item for item in found if "INJECTED" in item["answer"]]; selected=[]
        for call,ordinal,failure in injections:
            reached=[item for item in found if item["name"]==call and item["ordinal"]==ordinal]
            assert len(reached)==1 and reached[0]["answer"].startswith("-1 "+failure+" ")
            selected += reached
        assert {item["line"] for item in marked}=={item["line"] for item in selected}
        if budget:
            call,errors,calls=budget; rows=prefix.with_suffix(".trace").read_text().splitlines()
            selected=[row.split() for row in rows if row.split()[-1:]==[call]]
            assert len(selected)==1 and selected[0][-3:]==[str(calls),str(errors),call],rows
        if preflight: assert not any(item["name"]=="read" for item in found)
        self.count+=1; return found

    def report(self,name,data,text=False,maximum=None,**kwargs):
        status=kwargs.get("status",0)
        output=kwargs.pop("output",b"" if status else reference(data,text,65536 if maximum is None else maximum))
        return self.run(name,options(text,maximum),data,output=output,**kwargs)


def model(r):
    examples=[(b"",False),(b"",True),(b"\n",False),(b"\n\n",True),(b"\r\n",True),(b"\r",True),
              (b"a\r\nb\r",True),(b"\0\n\0",True),(bytes(range(256)),False),(b"\xff\0\x01",False),
              ("\0\x7fé中🙂\ufeff\uffff\U0010ffff\n".encode(),True),("e\u0301\n🇺🇸".encode(),True),
              (b"\n\r\n\nlast",False)]
    for index,(data,text) in enumerate(examples): r.report(f"literal-{index}",data,text)
    for text in (False,True):
        found=r.report(f"coalesced-resumption-{text}",b"a\n"*200,text,trace=True)
        if r.observes:
            reads=[item for item in found if item["name"]=="read"]
            assert [item["answer"] for item in reads]==["400","0"]
    for size in (1023,1024,1025): r.report(f"buffer-boundary-{size}",b"A"*(size-1)+b"\n")
    for width,scalar in ((2,"é"),(3,"中"),(4,"🙂")):
        for split in range(1,width): r.report(f"utf8-split-{width}-{split}",b"A"*(1024-split)+scalar.encode()+b"\n",True)
    for text in (False,True):
        r.report(f"zero-cap-empty-{text}",b"",text,0)
        for index,data in enumerate((b"\n",b"A")): r.report(f"one-byte-record-{text}-{index}",data,text,1)
    r.report("two-byte-crlf",b"\r\n",True,2)
    r.report("two-byte-nul-lf",b"\0\n",False,2)
    r.report("multibyte-byte-cap",b"\xc3\xa9\n",True,3)
    r.run("sixty-four-digit-cap",["-m","0"*63+"1"],b"\n",output=reference(b"\n",False,1))
    for ending in (False,True):
        r.report(f"default-record-cap-{ending}",b"A"*(65536-int(ending))+(b"\n" if ending else b""))
        r.report(f"maximum-record-cap-{ending}",b"A"*(MAX_BYTES-int(ending))+(b"\n" if ending else b""),False,MAX_BYTES)
    r.report("maximum-record-multibyte",b"\xc3\xa9"*(MAX_BYTES//2),True,MAX_BYTES)
    for text in (False,True): r.report(f"maximum-record-count-{text}",b"\n"*MAX_RECORDS,text)
    for maximum,rows in ((65536,64),(MAX_BYTES,4)):
        data=(b"A"*(maximum-1)+b"\n")*rows
        found=r.report(f"maximum-logical-input-{maximum}",data,False,maximum,trace=maximum==MAX_BYTES)
        if r.observes and maximum==MAX_BYTES:
            reads=[item for item in found if item["name"]=="read"]
            assert reads[-1]["answer"]=="0" and sum(int(item["answer"]) for item in reads)==CAP


def rejection(r):
    invalid=(b"\x80",b"\xc0\x80",b"\xc1\xbf",b"\xf5\x80\x80\x80",b"\xff",b"\xe0\x80\x80",
             b"\xf0\x80\x80\x80",b"\xed\xa0\x80",b"\xf4\x90\x80\x80",b"\xc2",b"\xe2\x82",b"\xf0\x9f\x92",
             b"\xc2A",b"\xe2A\x80",b"\xf0A\x80\x80",b"valid\0\xfftail")
    for index,data in enumerate(invalid): r.report(f"invalid-utf8-{index}",data+(b"\n" if index%2 else b""),True,status=2)
    for index,data in enumerate((b"A"*1023+b"\xc2A\n",b"A"*1023+b"\xe2\x82",b"good\n\nvalid\xfftail")):
        r.report(f"invalid-split-or-later-{index}",data,True,status=2)
    for text in (False,True):
        for index,data in enumerate((b"A",b"\n")): r.report(f"zero-cap-pending-{text}-{index}",data,text,0,status=2)
        r.report(f"delimiter-exceeds-one-byte-{text}",b"A\n",text,1,status=2)
        r.report(f"too-many-records-{text}",b"\n"*(MAX_RECORDS+1),text,status=2)
    for ended in (False,True): r.report(f"default-record-over-{ended}",b"A"*65536+(b"\n" if ended else b"A"),status=2)
    r.report("maximum-record-over",b"A"*(MAX_BYTES+1),False,MAX_BYTES,status=2)
    r.report("multibyte-plus-delimiter-exceeds-cap",b"\xc3\xa9\n",True,2,status=2)
    data=(b"A"*(MAX_BYTES-1)+b"\n")*4+b"B"*2048
    found=r.report("aggregate-limit-no-drain",data,False,MAX_BYTES,status=2,trace=True)
    if r.observes:
        reads=[item for item in found if item["name"]=="read"]
        assert all(item["answer"]!="0" for item in reads)
        consumed=sum(int(item["answer"]) for item in reads)
        assert CAP<consumed<=CAP+1024
    found=r.report("overlong-record-no-drain",b"A"*5+b"\n"+b"Z"*4096,False,4,status=2,trace=True)
    if r.observes:
        reads=[item for item in found if item["name"]=="read"]
        assert len(reads)==1 and reads[0]["answer"]=="1024"


def cli(r):
    invalid=[["operand"],["--","operand"],["--unknown"],["--Text"],["--text","-t"],["-tt"],["-hh"],["--help","-h"],
             ["--max-bytes","1","-m","2"],["--max-bytes"],["--max-bytes="],["--max-bytes",""],
             ["--max-bytes","-1"],["--max-bytes","+1"],["--max-bytes","1048577"],["--max-bytes"," 1"],
             ["--max-bytes","1 "],["--max-bytes","1.0"],["--max-bytes","1e0"],["--max-bytes","0x1"],
             ["--max-bytes","١"],["--max-bytes",b"\xff"],["--max-bytes","0"*65],
             ["--max-bytes","18446744073709551616"],["--help=yes"],["--help","--max-bytes","1048577"],
             ["x"]*17,["--help","x"*1019]]
    for index,args in enumerate(invalid): r.run(f"invalid-{index}",args,status=2,trace=True,read_error=True,preflight=True)
    valid=[["--help"],["-h"],["--text","--max-bytes","0","--help"],["--help","--max-bytes","1048576"],["-th"]]
    for index,args in enumerate(valid): r.run(f"help-{index}",args,output=HELP,trace=True,read_error=True,preflight=True)
    r.run("long-attached-limit",["--max-bytes=2"],b"\r\n",output=reference(b"\r\n",False,2))


def quota(r):
    data=b"\n\n"
    r.run("long-retry-within-quota",[],data,output=reference(data),budget=("read",65533,65535))
    r.run("shared-quota-interrupted-eof",[],data,status=2,budget=("read",131068,131069),interruption_schedule="2+")


def io(r):
    data=b"x"*20+b"\n"; data*=200; wanted=reference(data,True)
    baseline=r.report("baseline",data,True,trace=True)
    maps=[item for item in baseline if item["name"]=="mmap"]
    first_read=next(index for index,item in enumerate(baseline) if item["name"]=="read")
    first_write=next(index for index,item in enumerate(baseline) if item["name"]=="write" and item["args"].startswith("1,"))
    eof=next(item for item in baseline if item["name"]=="read" and item["answer"]=="0")
    assert int(maps[2]["args"].split(",")[1])==1024
    for owner in maps[:2]:
        released=next(index for index,item in enumerate(baseline) if index>baseline.index(owner) and item["name"]=="munmap" and item["args"].split(",")[0]==owner["answer"])
        assert released<baseline.index(maps[2])<first_read
    record=next(item for item in maps if baseline.index(item)>first_read)
    assert int(record["args"].split(",")[1])==21
    live={}
    for item in baseline[:first_write]:
        if item["name"]=="mmap": live[item["answer"]]=item
        elif item["name"]=="munmap": del live[item["args"].split(",")[0]]
    assert len(live)==1; output=next(iter(live.values()))
    assert int(output["args"].split(",")[1])>=len(wanted)
    selected=[maps[0],maps[1],maps[2],record,output]
    assert len({item["ordinal"] for item in selected})==5
    for old in selected:
        actual=r.report(f"owner-oom-{old['ordinal']}",data,True,status=4,trace=True,injections=(("mmap",old["ordinal"],"ENOMEM"),))
        fault=next(item for item in actual if item["name"]=="mmap" and item["ordinal"]==old["ordinal"])
        assert fault["args"]==old["args"]
    long=b"A"*4097+b"\n"; before=r.report("long-record-baseline",long,True,trace=True)
    first=next(index for index,item in enumerate(before) if item["name"]=="read")
    growth=next(item for item in before if before.index(item)>first and item["name"]=="mmap" and int(item["args"].split(",")[1])==8192)
    actual=r.report("retained-record-growth-oom",long,True,status=4,trace=True,injections=(("mmap",growth["ordinal"],"ENOMEM"),))
    fault=next(item for item in actual if item["name"]=="mmap" and item["ordinal"]==growth["ordinal"])
    assert fault["args"]==growth["args"]
    r.run("stdin-directory",status=3,trace=True,read_error=True)
    r.report("read-eintr-retry",data,True,trace=True,injections=(("read",1,"EINTR"),))
    r.report("later-read-eio",data,True,status=3,trace=True,injections=(("read",2,"EIO"),))
    failed=r.report("required-eof-eio",data,True,status=3,trace=True,injections=(("read",eof["ordinal"],"EIO"),))
    assert sum(int(item["answer"]) for item in failed if item["name"]=="read" and item["answer"].isdigit())==len(data)
    r.report("read-error-before-terminal-utf8",b"valid\xfftail",True,status=3,trace=True,injections=(("read",2,"EIO"),))
    r.report("closed-data-stdout",data,True,status=5,trace=True,closed_stdout=True)
    r.run("closed-help-stdout",["--help"],status=5,trace=True,closed_stdout=True)
    r.report("write-eintr-retry",data,True,trace=True,injections=(("write",1,"EINTR"),))
    partial=r.report("actual-output-prefix",data,True,status=5,output=wanted[:1024],trace=True,injections=(("write",2,"EIO"),))
    assert next(item["answer"] for item in partial if item["name"]=="write")=="1024"
    r.run("signal-setup-eio",status=5,trace=True,injections=(("rt_sigaction",1,"EIO"),),diagnostic=False)
    r.report("output-attempt-cap",data,True,status=5,budget=("write",2048,2049))


def controls():
    assert len(HELP)==823 and len(ERROR)==30
    assert split_records(b"")==[] and split_records(b"\n\n")==[(b"\n","lf"),(b"\n","lf")]
    assert split_records(b"\0\r\nx\r")==[(b"\0\r\n","lf"),(b"x\r","eof")]
    assert reference(b"\0\r\n",True)==b'"record","bytes","scalars","ending"\r\n"0","3","3","lf"\r\n'
    assert reference(b"\xff",False)==b'"record","bytes","scalars","ending"\r\n"0","1","","eof"\r\n'
    assert len(encode([HEADER]))==37
    assert 65533+2+2+1==65538<131072 and 65533+2==65535
    assert 2+2+131068==131072 and 1+131068==131069
    assert 1+131072==131073  # Resetting the final helper would spend four extra calls.
    class CounterOnly:
        observes=False
        def __init__(self): self.count=0
        def run(self,*args,**kwargs): self.count+=1; return []
        def report(self,name,data,text=False,maximum=None,**kwargs):
            if kwargs.get("status")==2:
                try: reference(data,text,65536 if maximum is None else maximum)
                except ValueError: pass
                else: raise AssertionError("invalid reference accepted")
            else: reference(data,text,65536 if maximum is None else maximum)
            self.count+=1; return []
    for function in (model,rejection,cli,quota):
        r=CounterOnly(); function(r)
        assert r.count==COUNTS[function.__name__]
    good="mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\nwrite(2, X, 1) = 1\n"
    assert len(events(good))==3
    try: events(good.replace("munmap(0x1000, 16) = 0\n",""))
    except AssertionError: pass
    else: raise AssertionError("missing release accepted")
    print(f"line-report CPU controls passed; native cases={sum(COUNTS.values())}")


if __name__=="__main__":
    if sys.argv[1:]==["controls"]: controls()
    else:
        mode,executable=sys.argv[1:]; runner=Runner(executable,mode)
        {"model":model,"rejection":rejection,"cli":cli,"quota":quota,"io":io}[mode](runner)
        assert runner.count==COUNTS[mode],(mode,runner.count)
        print(f"line-report-{mode} cases={runner.count} evidence={runner.directory}")
