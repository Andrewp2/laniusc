"""Two real-file concatenation prefixes with observed syscall ownership."""
from collections import Counter
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

MAXIMUM = 1048576
HELP = (b'Usage: concat_bytes --limit N [--] FIRST SECOND\n'
        b'Write up to N bytes from FIRST followed by SECOND, unchanged, to stdout.\n'
        b'N is 0..1048576; use 1..64 ASCII decimal digits. Leading zeros are allowed.\n'
        b'Early EOF succeeds. Limit zero still opens both files but performs no data reads.\n'
        b'Paths are literal nonempty byte paths, at most 4095 bytes each; - is a filename.\n'
        b'Short options: -n N, -h. --help shows help without opening files or reading stdin.\n'
        b'Help waives required limit and paths but checks supplied arguments.\n'
        b'Duplicate options, extra operands and malformed supplied values are errors.\n'
        b'Input is staged before stdout; both files and the input buffer are retired first.\n'
        b'Limits: 16 arguments, 8192 argument bytes, 16384 collection calls, 4096 output attempts.\n'
        b'The input buffer is 4096 bytes. Interrupted operations spend attempts.\n'
        b'Output failures can leave a confirmed prefix; blocking I/O has no time limit.\n')
ERROR = b"concat_bytes: operation failed\n"
COUNTS = {"model": 29, "limits": 12, "cli": 45, "io": 29}
TRACE = "openat,close,read,write,mmap,munmap,mremap,brk,rt_sigaction"


def pattern(length, salt=19):
    block = bytes((index * 73 + salt) % 256 for index in range(256))
    return (block * ((length + 255) // 256))[:length]


def reference(first, second, limit):
    assert 0 <= limit <= MAXIMUM
    return (first + second)[:limit]


def events(text, limit=None, preflight=False):
    result, counts, live, descriptors = [], Counter(), {}, set()
    opened, closed_errors, consumed, second_started, first_eof = [], [], 0, False, False
    for line in text.splitlines():
        match = re.fullmatch(r"([a-z0-9_]+)\((.*)\)\s+=\s+(.*)", line)
        assert match and match[1] in TRACE.split(","), ("unexpected trace line", line)
        name, args, answer = match.groups(); counts[name] += 1
        event = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        result.append(event)
        if name == "mmap":
            size = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]; assert address not in live; live[address] = size
            else: assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("mremap", "brk"):
            raise AssertionError(("unaccounted allocation service", line))
        elif name == "openat":
            assert not preflight and "O_RDONLY" in args
            assert not any(flag in args for flag in ("O_CREAT", "O_TRUNC", "O_APPEND", "O_RDWR", "O_WRONLY"))
            if answer.split()[0].isdigit():
                descriptor = int(answer.split()[0]); assert descriptor > 2 and descriptor not in descriptors
                descriptors.add(descriptor); opened.append(descriptor)
                assert len(opened) <= 2
        elif name == "close":
            descriptor = int(args); assert descriptor in descriptors and descriptor > 2
            descriptors.remove(descriptor)
            if answer != "0":
                assert "INJECTED" in answer and (answer.startswith("-1 EIO ") or answer.startswith("-1 EINTR "))
                closed_errors.append(descriptor)
        elif name == "read":
            descriptor = int(args.split(",")[0]); requested = int(args.rsplit(",",1)[1])
            assert not preflight and descriptor in descriptors and descriptor in opened
            assert limit is not None and 0 < requested <= min(4096, limit-consumed), (line, limit, consumed)
            if descriptor == opened[0]: assert not second_started
            else:
                assert len(opened)==2 and descriptor==opened[1] and first_eof
                second_started = True
            if answer.split()[0].isdigit():
                got = int(answer.split()[0]); assert 0 <= got <= requested
                consumed += got
                if descriptor==opened[0] and got==0: first_eof = True
        elif name == "write":
            descriptor = int(args.split(",")[0]); assert descriptor in (1,2)
            assert not descriptors, ("publication before file retirement", line, descriptors)
            if descriptor==2: assert not live, ("diagnostic before allocation cleanup", live)
            else: assert len(live)<=1, ("input or argv owner remains at stdout", live)
    assert not live and not descriptors, ("observed owner not retired", live, descriptors)
    if preflight: assert not opened and not counts["read"] and not counts["close"]
    # A substituted close error proves one attempted retirement. strace skips
    # that syscall, so it is not evidence of successful kernel descriptor release.
    return result, consumed, closed_errors


class Runner:
    observes = True
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header)==64 and header[:6]==b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18],"little")==2 and int.from_bytes(header[18:20],"little")==62
        self.directory = Path(tempfile.mkdtemp(prefix=f"concat-bytes-{mode}-")); self.count=0

    def run(self, name, arguments, *, limit=None, status=0, output=b"", preflight=False,
            injections=(), closed_stdout=False, diagnostic=True, budget=None):
        prefix=self.directory/name
        command=["strace","--kill-on-exit","-qq","-xx","-s","32","-e","signal=none"]
        if budget:
            maximum=16384 if budget=="read" else 4096
            command += ["-c","-e","trace="+budget,"-e",f"inject={budget}:error=EINTR:when=1..{maximum}"]
        else:
            command += ["-e","trace="+TRACE]
            for call, ordinal, failure in injections:
                command += ["-e",f"inject={call}:error={failure}:when={ordinal}"]
        command += ["-o",str(prefix.with_suffix(".trace")),self.executable,*arguments]
        prefix.with_suffix(".command").write_text(repr(command)+"\n")
        if closed_stdout:
            reader,writer=os.pipe(); os.close(reader)
            try: result=subprocess.run(command,stdin=subprocess.DEVNULL,stdout=writer,stderr=subprocess.PIPE,
                                       cwd=self.directory,timeout=20,check=False)
            finally: os.close(writer)
            result.stdout=b""
        else: result=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,cwd=self.directory,timeout=20,check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode)+"\n")
        assert result.returncode==status and result.stdout==output, (name,result.returncode,status,len(result.stdout),len(output),result.stderr)
        assert result.stderr==(ERROR if status and diagnostic else b""), (name,result.stderr)
        if budget:
            rows=prefix.with_suffix(".trace").read_text().splitlines()
            selected=[row.split() for row in rows if row.split()[-1:]==[budget]]
            expected=[str(maximum),str(maximum),budget] if budget=="read" else [str(maximum+1),str(maximum),budget]
            assert len(selected)==1 and selected[0][-3:]==expected,rows
            found=[]
        else:
            found,consumed,close_errors=events(prefix.with_suffix(".trace").read_text(),limit,preflight)
            marked=[event for event in found if "INJECTED" in event["answer"]]; selected=[]
            for call,ordinal,failure in injections:
                reached=[event for event in found if event["name"]==call and event["ordinal"]==ordinal]
                assert len(reached)==1 and reached[0]["answer"].startswith("-1 "+failure+" ")
                selected+=reached
            assert {event["line"] for event in marked}=={event["line"] for event in selected}
            assert len(close_errors)==sum(call=="close" for call,_,_ in injections)
            if status==0 and limit is not None: assert consumed==len(output)
        self.count+=1
        return found

    def concat(self,name,first,second,limit,*,arguments=None,path_names=None,same=False,symlink=False,**options):
        left_name,right_name=path_names or (name+"-first.bin",name+"-second.bin")
        left=os.path.join(os.fsencode(self.directory),os.fsencode(left_name))
        right=left if same else os.path.join(os.fsencode(self.directory),os.fsencode(right_name))
        Path(os.fsdecode(left)).write_bytes(first)
        if same: assert second==first
        else: Path(os.fsdecode(right)).write_bytes(second)
        selected_right=right
        if symlink:
            selected_right=right+b".link"; os.symlink(right,selected_right)
        args=["--limit",str(limit),left,selected_right] if arguments is None else arguments
        output=options.pop("output",reference(first,second,limit))
        found=self.run(name,args,limit=limit,output=output,**options)
        assert Path(os.fsdecode(left)).read_bytes()==first and Path(os.fsdecode(right)).read_bytes()==second
        if symlink: assert os.path.islink(selected_right)
        return found


def model(r):
    cases=[("both-empty",b"",b"",37),("first-empty",b"",b"second",90),
           ("second-empty",b"first",b"",90),("short-both",b"abc",b"DEFG",90),
           ("binary-all-bytes",bytes(range(256)),bytes(reversed(range(256))),500),
           ("split-multibyte-text",b"A\xe2",b"\x82\xacB\x00\xff",7),
           ("first-longer-than-quota",pattern(2100),b"unread",1237),
           ("first-eof-then-second-prefix",pattern(1501),pattern(2301,77),3000)]
    for name,first,second,limit in cases: r.concat(name,first,second,limit)
    rng=random.Random(0xC0CA7B17)
    for index in range(16):
        first=bytes(rng.randrange(256) for _ in range(rng.randrange(6000)))
        second=bytes(rng.randrange(256) for _ in range(rng.randrange(6000)))
        limit=rng.randrange(1,len(first)+len(second)+100)
        r.concat(f"seeded-{index}",first,second,limit)
    r.concat("unicode-path",b"first",b"second",20,path_names=("first-é.bin","second-λ.bin"))
    r.concat("nonutf8-path",b"first",b"second",20,path_names=(b"first-\xff.bin",b"second-\xfe.bin"))
    r.concat("same-file-two-offsets",pattern(1337),pattern(1337),2301,same=True)
    r.concat("follow-second-symlink",b"first",b"second",20,symlink=True)
    r.concat("literal-dash-filename",b"dash",b"tail",8,path_names=("-","tail.bin"),arguments=["--limit","8","--","-","tail.bin"])


def limits(r):
    first,second=pattern(8193),pattern(8193,71)
    for limit in (0,1,1023,1024,1025,4095,4096,4097):
        found=r.concat(f"quota-{limit}",first,second,limit)
        if r.observes:
            assert len([event for event in found if event["name"]=="openat"])==2
            if limit==0: assert not any(event["name"]=="read" for event in found)
            else:
                first_fd=int(next(event["answer"] for event in found if event["name"]=="openat"))
                assert all(int(event["args"].split(",")[0])==first_fd for event in found if event["name"]=="read")
    r.concat("one-byte-from-second",b"",b"second",1)
    r.concat("maximum-across-files",pattern(400001),pattern(MAXIMUM,101),MAXIMUM)
    r.concat("maximum-first-only",pattern(MAXIMUM+1),b"must-not-read",MAXIMUM)
    r.concat("maximum-early-eof",pattern(3011),pattern(5107,71),MAXIMUM)


def cli(r):
    missing=["does-not-exist-first","does-not-exist-second"]
    invalid=[[],["--limit"],["--limit","1"],["--limit","1",missing[0]],
             ["--limit","1",*missing,"extra"],[*missing],["--unknown"],["--help=yes"],["-hh"],["--help","-h"],
             ["--limit","1","-n","2",*missing],["--limit","1","--limit","1",*missing],
             ["--limit","1","",missing[1]],["--limit","1",missing[0],""],
             ["--limit","1","x"*4096,missing[1]], ["--limit","1",missing[0],"x"*4096],
             ["--help","x","y","z"],["--help","--limit","1048577"],["--help",""],
             ["--limit","1",*missing,"x"*8193],["x"]*17]
    for number in ("", "-1", "+1", "1048577", "18446744073709551616", "1.0", "1e0", "0x1",
                   " 1", "1 ", "1_0", "١", b"\xff", "0"*65):
        invalid.append(["--limit",number,*missing])
    for index,args in enumerate(invalid): r.run(f"invalid-{index}",args,status=2,preflight=True)
    for index,args in enumerate((["--help"],["-h"],["--help","--limit","0000"],
                                ["--help",missing[0]],["--help",*missing],
                                ["--limit","1048576",*missing,"--help"],["--help","--", "-h"])):
        r.run(f"help-{index}",args,output=HELP,preflight=True)
    r.concat("short-limit-leading-zeros",b"abcd",b"EFGH",6,path_names=("left.bin","right.bin"),arguments=["-n","0"*63+"6","left.bin","right.bin"])
    r.concat("intermixed-attached-limit",b"abcd",b"EFGH",6,path_names=("left2.bin","right2.bin"),arguments=["left2.bin","-n6","right2.bin"])
    r.concat("long-equals-limit",b"abcd",b"EFGH",6,path_names=("left3.bin","right3.bin"),arguments=["--limit=6","left3.bin","right3.bin"])


def io(r):
    first,second,limit=pattern(5101),pattern(7003,77),12000
    wanted=reference(first,second,limit)
    def exercise(name,**options): return r.concat(name,first,second,limit,path_names=("io-first.bin","io-second.bin"),**options)
    baseline=exercise("baseline")
    maps=[event for event in baseline if event["name"]=="mmap"]
    opens=[event for event in baseline if event["name"]=="openat"]
    reads=[event for event in baseline if event["name"]=="read"]
    closes=[event for event in baseline if event["name"]=="close"]
    assert len(opens)==len(closes)==2 and all(event["answer"]=="0" for event in closes)
    def size(event): return int(event["args"].split(",")[1])
    before_open=[event for event in maps if baseline.index(event)<baseline.index(opens[0])]
    after_open=[event for event in maps if baseline.index(event)>baseline.index(opens[1])]
    assert len(before_open)==2 and len(after_open)>=3
    buffer,initial=after_open[:2]
    assert size(buffer)==4096 and size(initial)==1024
    assert baseline.index(buffer)<baseline.index(initial)<baseline.index(reads[0])
    def release(event):
        return next(item for item in baseline[baseline.index(event)+1:]
                    if item["name"]=="munmap" and item["args"].split(",")[0]==event["answer"])
    for event in before_open: assert baseline.index(opens[1])<baseline.index(release(event))<baseline.index(buffer)
    assert baseline.index(release(buffer))<baseline.index(closes[0])
    assert size(maps[-1])==limit and baseline.index(release(maps[-1]))>baseline.index(closes[-1])
    selected=[*before_open,buffer,initial,maps[-1]]
    assert len({event["ordinal"] for event in selected})==5
    for old in selected:
        actual=exercise(f"owner-oom-{old['ordinal']}",status=4,output=b"",injections=(("mmap",old["ordinal"],"ENOMEM"),))
        actual_maps=[event for event in actual if event["name"]=="mmap"]
        assert len(actual_maps)==old["ordinal"]
        assert [event["args"] for event in actual_maps]==[event["args"] for event in maps[:old["ordinal"]]]
    for ordinal in (1,2): exercise(f"open-{ordinal}-eacces",status=3,output=b"",injections=(("openat",ordinal,"EACCES"),))
    second_fd=int(opens[1]["answer"]); second_read=next(event for event in reads if int(event["args"].split(",")[0])==second_fd)
    first_eof=next(event for event in reads if event["answer"]=="0")
    for label,ordinal in (("first",1),("second",second_read["ordinal"])):
        exercise(label+"-read-eintr",injections=(("read",ordinal,"EINTR"),))
    for label,ordinal in (("first",1),("second",second_read["ordinal"]),("first-eof",first_eof["ordinal"])):
        exercise(label+"-read-eio",status=3,output=b"",injections=(("read",ordinal,"EIO"),))
    for ordinal in (1,2): exercise(f"close-{ordinal}-eio",status=3,output=b"",injections=(("close",ordinal,"EIO"),))
    exercise("allocation-primary-close-secondary",status=4,output=b"",injections=(("mmap",buffer["ordinal"],"ENOMEM"),("close",1,"EIO")))
    exercise("write-eintr",injections=(("write",1,"EINTR"),))
    exercise("first-write-eio",status=5,output=b"",injections=(("write",1,"EIO"),))
    partial=exercise("confirmed-output-prefix",status=5,output=wanted[:1024],injections=(("write",2,"EIO"),))
    assert next(event["answer"] for event in partial if event["name"]=="write")=="1024"
    exercise("closed-stdout",status=5,output=b"",closed_stdout=True)
    exercise("read-attempt-cap",status=2,output=b"",budget="read")
    exercise("write-attempt-cap",status=5,output=b"",budget="write")
    r.run("signal-setup-eio",["--help"],status=5,preflight=True,diagnostic=False,injections=(("rt_sigaction",1,"EIO"),))
    r.run("closed-help-stdout",["--help"],status=5,preflight=True,closed_stdout=True)
    available=r.directory/"available.bin"; available.write_bytes(b"abc")
    missing=r.directory/"missing.bin"
    for name,left,right,quota in (("missing-first",missing,available,9),("missing-second",available,missing,9),
                                   ("directory-first",r.directory,available,9),("directory-second",available,r.directory,9),
                                   ("zero-still-opens-second",available,missing,0)):
        r.run(name,["--limit",str(quota),str(left),str(right)],limit=quota,status=3)
    assert available.read_bytes()==b"abc"


def controls():
    assert len(HELP)==907 and len(ERROR)==31
    assert reference(b"abc",b"DEF",4)==b"abcD"
    assert reference(b"abc",b"DEF",0)==b"" and reference(b"",b"\x00\xff",4)==b"\x00\xff"
    expected=reference(b"a\x00",b"\xffz",3)
    assert expected==b"a\x00\xff"
    corruptions=[b"\xffa\x00",b"a\x00\xffz",b"a\x00",b"a\x00\xfe"]
    assert all(value!=expected for value in corruptions)
    class CounterOnly:
        observes=False
        directory=Path("/unused")
        def __init__(self): self.count=0
        def run(self,*args,**kwargs): self.count+=1; return []
        def concat(self,name,first,second,limit,**kwargs): reference(first,second,limit); self.count+=1; return []
    for function in (model,limits,cli):
        runner=CounterOnly(); function(runner)
        assert runner.count==COUNTS[function.__name__],(function.__name__,runner.count,COUNTS[function.__name__])
    good="mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nopenat(AT_FDCWD, X, O_RDONLY) = 3\nclose(3) = 0\nmunmap(0x1000, 16) = 0\nwrite(2, X, 1) = 1\n"
    assert len(events(good)[0])==5
    bad=[good.replace("munmap(0x1000, 16) = 0\n",""),good.replace("close(3) = 0\n",""),
         good.replace("close(3) = 0\n","close(0) = 0\n")]
    for text in bad:
        try: events(text)
        except AssertionError: pass
        else: raise AssertionError("broken owner trace accepted")
    print(f"concat-bytes CPU controls passed; native cases={sum(COUNTS.values())}")


if __name__=="__main__":
    if sys.argv[1:]==["controls"]: controls()
    else:
        mode,executable=sys.argv[1:]; runner=Runner(executable,mode)
        {"model":model,"limits":limits,"cli":cli,"io":io}[mode](runner)
        assert runner.count==COUNTS[mode],(mode,runner.count)
        print(f"concat-bytes-{mode} cases={runner.count} evidence={runner.directory}")
