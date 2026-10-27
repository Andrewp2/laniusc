"""Actual TempDir owners, independent namespace observations, verified raw maps.

Python supplies fixtures, finite injections and observations only. No production
filesystem owner, entropy, directory naming, or cleanup is implemented here.
"""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import select
import stat
import struct
import subprocess
import sys
import tempfile
import time
import traceback


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SOURCE = load("temp_dir_source", Path(__file__).resolve().parents[2] / "extended/archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
MAX = (1 << 64)-1
DATA = b"\0\xff\x80a\r\n"
ZERO = b".tmp-" + b"0"*32
ONE = b".tmp-" + b"01"*16
TRACE = TRUSTED.TRACE


def rule(name, ordinal=1, *, error=None, retval=None, poke=None, repeat=False):
    assert ordinal > 0 and (error is None) != (retval is None)
    return dict(syscall=name, when=ordinal, error=error, retval=retval, poke=poke, repeat=repeat)


def injection(value):
    result = value["syscall"] + (":error="+value["error"] if value["error"] else ":retval="+str(value["retval"]))
    if value["poke"] is not None:
        result += ":poke_exit=@arg1="+value["poke"]
    return result+":when="+str(value["when"])+("+" if value["repeat"] else "")


def injection_options(rules):
    options=[]; seen=set()
    for value in rules:
        name=value["syscall"]
        assert name not in seen, "strace replaces earlier injection rules for the same syscall"
        seen.add(name)
        options += ["-e","inject="+injection(value)]
    return options


def clean(words, start):
    return dict(zip(("child_attempt", "child_error", "remove_attempt", "removal", "remove_error", "parent_attempt", "parent_error", "retained"), words[start:start+8]))


def decode(packet):
    assert len(packet) == 549
    words = struct.unpack("<64Q", packet[:512])
    assert words[:2] == (1413761362, 1), words[:2]
    return dict(words=words, checkpoint=words[2], pid=words[3], mode=words[4], parent_case=words[5],
                created=words[6], create_cause=words[7], create_stage=words[8], state=words[9], owns=words[10],
                caller=words[11], parent=words[12], child=words[13], name_length=words[14],
                stats=dict(zip(("names", "mkdir", "opens", "collisions", "entropy"), words[15:20])),
                primary=(words[20], words[21]), primary_retained=words[23], latest=clean(words,24),
                action=words[32], action_cause=words[33], action_stage=words[34], action_cleanup=clean(words,35),
                saved_parent=words[43], saved_child=words[44], saved_caller=words[45],
                active=(words[46],words[47]), preserved=words[48], keep=(words[49],words[50]),
                explicit=(words[51],words[52],words[53],words[54]), name=packet[512:])


def selected(value, name, phase=None):
    return [item for item in value["events"] if item["name"] == name and (phase is None or item["phase"] == phase)]


def analyze(text, sites, directory, *, final=False, repair=None):
    found, epochs = TRUSTED.events(text)
    ranges = sites[0].executable_ranges
    assert all(any(low <= item["ip"] < high for low,high in ranges) for item in found), "syscall outside raw executable"
    maps = "".join(item["line"]+"\n" for item in found if item["name"] in ("mmap","munmap"))
    source = SOURCE.source(maps, sites)
    live, generations, retired = {}, Counter(), set()
    for item in found:
        name, args, result = item["name"], TRUSTED.arguments(item["args"]), item["result"].split()[0]
        assert name not in ("renameat2","chdir","fchdir","mkdir","fsync","fdatasync","lseek"), item
        if name == "openat":
            leaf = TRUSTED.quoted(args[1])
            if item["phase"] == "C":
                assert args[0].isdecimal() and int(args[0]) in live and re.fullmatch(rb"\.tmp-[0-9a-f]{32}",leaf), item
                assert "O_DIRECTORY" in args[2] and "O_NOFOLLOW" in args[2] and "O_CLOEXEC" in args[2] and "O_CREAT" not in args[2], item
            if item["phase"] == "U":
                assert args[0].isdecimal() and int(args[0]) in live and leaf == b"payload", item
                assert "O_CREAT" in args[2] and "O_EXCL" in args[2] and "O_NOFOLLOW" in args[2] and args[3] == "0600", item
            if result.isdecimal():
                fd = int(result)
                assert fd not in live, ("reopened live descriptor", item)
                generations[fd] += 1
                role = leaf if args[0] == "AT_FDCWD" else live[int(args[0])]["role"]+b"/"+leaf
                live[fd] = dict(generation=generations[fd], role=role)
        elif name == "fcntl" and args[1] in ("F_DUPFD","F_DUPFD_CLOEXEC"):
            assert int(args[0]) in live, item
            if item["phase"]=="C": assert args[1]=="F_DUPFD_CLOEXEC", "parent duplicate lacks close-on-exec"
            if result.isdecimal():
                fd = int(result)
                assert fd not in live
                generations[fd] += 1
                live[fd] = dict(generation=generations[fd], role=live[int(args[0])]["role"])
        elif name == "close":
            fd = int(args[0]); assert fd in live, ("unowned/repeated close", item)
            key = fd,live[fd]["generation"]
            if key in retired:
                assert item["phase"] == "Q" and result == "0", ("production retried retired fd", item)
            if result == "0":
                del live[fd]
            else:
                assert repair and item["ordinal"] == repair[0] and item["phase"] == repair[1], item
                assert item["result"].startswith("-1 EIO ") and "INJECTED" in item["result"] and key not in retired, item
                retired.add(key)
        elif name in ("fcntl","statx"):
            assert int(args[0]) in live, ("query through unowned fd", item)
        elif name == "mkdirat":
            assert item["phase"] == "C" and int(args[0]) in live and args[2] == "0700", item
            assert re.fullmatch(rb"\.tmp-[0-9a-f]{32}",TRUSTED.quoted(args[1])), item
        elif name == "unlinkat":
            assert int(args[0]) in live, item
            leaf = TRUSTED.quoted(args[1])
            if item["phase"] in ("A","B"):
                assert re.fullmatch(rb"\.tmp-[0-9a-f]{32}",leaf) and args[2] == "AT_REMOVEDIR", item
            else:
                assert item["phase"] == "U" and leaf == b"payload" and args[2] == "0", item
        elif name in ("read","write") and int(args[0]) > 2:
            assert int(args[0]) in live, item
        elif name == "getrandom":
            assert item["phase"] == "C" and args[2] == "GRND_NONBLOCK", item
    for epoch in epochs:
        if epoch["phase"] in ("K","X"):
            assert not epoch["events"], ("pure keep/repeated cleanup performed work", epoch)
        if epoch["phase"] == "Q":
            assert len(epoch["events"]) == 1 and epoch["events"][0]["name"] == "close" and epoch["events"][0]["result"] == "0", epoch
    if final:
        assert not source["live"] and not live, (source["live"], live)
        TRUSTED.analyze(text,sites,directory,repaired_close=repair[0] if repair else None,repair_phase=repair[1] if repair else "A")
    return dict(events=found,epochs=epochs,source=source,live=live)


def observe(pid, owners, directory, index):
    descriptors = {int(value) for value in os.listdir(f"/proc/{pid}/fd")}
    assert descriptors == {0,1,2}|set(owners["live"]), (descriptors,owners["live"])
    maps = Path(f"/proc/{pid}/maps").read_text()
    Path(directory,f"checkpoint-{index}.maps").write_text(maps)
    ranges = [(int(line.split()[0].split("-")[0],16),int(line.split()[0].split("-")[1],16)) for line in maps.splitlines()]
    for pointer,length in owners["source"]["live"].items():
        assert any(low <= pointer and pointer+length <= high for low,high in ranges), (pointer,length)
    for item in owners["source"]["attempts"]:
        value = item["result"].split()[0]
        if value.startswith("0x") and int(value,16) not in owners["source"]["live"]:
            assert not any(low <= int(value,16) < high for low,high in ranges), "released source mapping remains"


def bind(before, after, rules):
    def norm(value):
        try:
            data = TRUSTED.quoted(value)
        except AssertionError:
            return value
        return b"<temporary>" if re.fullmatch(rb"\.tmp-[0-9a-f]{32}",data) else data
    for fault in rules:
        left = selected(before,fault["syscall"])[fault["when"]-1]
        right = selected(after,fault["syscall"])[fault["when"]-1]
        assert (left["ip"],left["phase"]) == (right["ip"],right["phase"]), (left,right)
        a,b = TRUSTED.arguments(left["args"]),TRUSTED.arguments(right["args"])
        if fault["syscall"] == "getrandom":
            assert a[1:] == b[1:]
        elif fault["syscall"] == "statx":
            assert a[:4] == b[:4], (left,right)
        else:
            assert [norm(value) for value in a] == [norm(value) for value in b], (left,right)
        if fault["syscall"] == "mmap":
            first,second = selected(before,"mmap"),selected(after,"mmap")
            assert [(value["ip"],value["args"]) for value in first[:fault["when"]]] == [(value["ip"],value["args"]) for value in second[:fault["when"]]]


def entropy_names(owners):
    pending = bytearray(); count = 0
    for item in owners["events"]:
        if item["phase"] != "C":
            continue
        args = TRUSTED.arguments(item["args"])
        if item["name"] == "getrandom" and item["result"].split()[0].isdecimal():
            size = int(item["result"].split()[0])
            if size <= int(args[1]) and size:
                pending.extend(TRUSTED.quoted(args[0])[:size])
        if item["name"] == "mkdirat":
            assert len(pending) == 16 and TRUSTED.quoted(args[1]) == b".tmp-"+pending.hex().encode(), (item,pending)
            pending.clear(); count += 1
    return count


def collision_recovered(value):
    created=value["frames"][1]; owners=value["owners"]
    draws=selected(owners,"getrandom","C"); attempts=selected(owners,"mkdirat","C")
    assert created["created"]==1 and not created["create_cause"]
    assert 2 <= len(attempts) <= 8 and len(draws)==len(attempts)
    assert created["stats"]==dict(names=len(attempts),mkdir=len(attempts),opens=1,
                                  collisions=len(attempts)-1,entropy=len(draws))
    assert all(item["result"].split()[0]=="16" and TRUSTED.arguments(item["args"])[1:]==["16","GRND_NONBLOCK"] for item in draws)
    assert "INJECTED" in draws[0]["result"] and TRUSTED.quoted(TRUSTED.arguments(draws[0]["args"])[0])==bytes(16)
    assert all("INJECTED" not in item["result"] and "POKED" not in item["result"] for item in draws[1:])
    assert TRUSTED.quoted(TRUSTED.arguments(attempts[0]["args"])[1])==ZERO
    assert all(item["result"].startswith("-1 EEXIST ") for item in attempts[:-1])
    assert attempts[-1]["result"]=="0" and created["name"]!=ZERO
    assert TRUSTED.quoted(TRUSTED.arguments(attempts[-1]["args"])[1])==created["name"]
    assert entropy_names(owners)==len(attempts)
    return created["name"]


def read_exact(stream,count,deadline):
    output = bytearray()
    while len(output) < count:
        remaining = deadline-time.monotonic()
        assert remaining > 0 and select.select([stream],[],[],remaining)[0], "native snapshot timeout"
        value = os.read(stream.fileno(),count-len(output)); assert value, "premature native EOF"
        output.extend(value)
    return bytes(output)


def validate_result(owners,rules,result,check):
    expectations=[]
    for value in rules:
        expectation=dict(syscall=value["syscall"],when=value["when"],repeat=value["repeat"])
        if value["error"] is not None: expectation["error"]=value["error"]
        if value["retval"] is not None: expectation["retval"]=value["retval"]
        expectations.append(expectation)
    TRUSTED.check_injections(owners,expectations)
    if check: check(result)


class Suite:
    def __init__(self,group,executable):
        self.group,self.executable = group,Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="temp-dir-"+group+"-"))
        self.sites = TRUSTED.verified_sites(self.executable,self.directory)
        assert self.sites[0] and not self.sites[1] and self.sites[0].executable_ranges, "raw ELF requires verified runtime opcodes"
        self.count,self.started = 0,time.monotonic()

    def case(self,label,*,mode=0,names=8,entropy=16,parent=0,rules=(),baseline=None,setup=None,check=None,repair=None):
        assert time.monotonic()-self.started < 75, "split group before adding more native cases"
        self.count += 1
        directory = self.directory/f"{self.count:03d}-{label}"; directory.mkdir()
        cwd = directory/"cwd"; cwd.mkdir(); anchor=cwd/"anchor"; anchor.mkdir(mode=0o751)
        (anchor/"sentinel").write_bytes(DATA); (cwd/"regular").write_bytes(b"regular-parent")
        original = os.stat(anchor); replacement=None
        if setup:
            setup(cwd)
        trace = directory/"native.trace"
        command = ["strace","--kill-on-exit","-qq","-xx","-i","-s","4096","-e","signal=none","-e","trace="+TRACE,"-o",str(trace)]
        command += injection_options(rules)
        command += [str(self.executable)]
        request = struct.pack("<5Q",mode,names,entropy,parent,repair[2] if repair else 0)
        (directory/"request.bin").write_bytes(request)
        process = subprocess.Popen(command,cwd=cwd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0,umask=0o077)
        frames,stdout = [],bytearray()
        try:
            assert process.stdin.write(request) == len(request)
            for index in range(4):
                deadline = time.monotonic()+12
                packet = read_exact(process.stdout,549,deadline); stdout.extend(packet)
                frame = decode(packet); assert frame["checkpoint"] == index and frame["mode"] == mode and frame["parent_case"] == parent
                if frames:
                    assert frame["pid"] == frames[0]["pid"]
                    if index > 1: assert frame["stats"] == frames[1]["stats"]
                while True:
                    try:
                        prefix = SOURCE.output_prefix(trace.read_text(),bytes(stdout)); break
                    except (AssertionError,FileNotFoundError):
                        assert time.monotonic() < deadline, "native snapshot absent from trace"
                        time.sleep(0.005)
                owners = analyze(prefix,self.sites,directory,final=index==3,repair=repair)
                observe(frame["pid"],owners,directory,index)
                frame["owners"]=owners; frames.append(frame)
                (directory/f"checkpoint-{index}.bin").write_bytes(packet)
                if index == 0:
                    assert not owners["source"]["live"] and not frame["owns"]
                    if mode == 3:
                        anchor.rename(cwd/"moved"); anchor.mkdir(); (anchor/"replacement").write_bytes(DATA); replacement=os.stat(anchor); anchor=cwd/"moved"
                if index == 1:
                    assert frame["created"] in (1,3)
                    assert sum(owners["source"]["live"].values()) == (0 if frame["create_stage"] in (1,2) else 37)
                    if frame["created"] == 1 or frame["owns"]:
                        target=anchor/os.fsdecode(frame["name"])
                        assert target.is_dir() and not target.is_symlink() and stat.S_IMODE(os.stat(target).st_mode)==0o700
                        assert os.stat(f"/proc/{frame['pid']}/fd/{frame['saved_parent']}").st_ino == original.st_ino
                        if frame["child"] != MAX:
                            assert os.stat(f"/proc/{frame['pid']}/fd/{frame['child']}").st_ino == os.stat(target).st_ino
                        if mode in (2,3,9):
                            assert (target/"payload").read_bytes() == DATA
                        if mode == 4:
                            target.rmdir()
                    created_names=[TRUSTED.quoted(TRUSTED.arguments(item["args"])[1]) for item in selected(owners,"mkdirat","C") if item["result"]=="0"]
                    assert created_names == ([frame["name"]] if frame["name_length"]==37 else []), (frame,created_names)
                    for item in selected(owners,"openat","C"):
                        assert TRUSTED.quoted(TRUSTED.arguments(item["args"])[1]) == frame["name"]
                    if mode == 3 and frame["created"] == 1:
                        assert frame["caller"] == MAX
                    elif parent != 2:
                        assert frame["caller"] == frames[0]["caller"] and frame["caller"] in owners["live"], "borrowed caller parent retired"
                if index == 2:
                    assert sum(owners["source"]["live"].values()) == (37 if frame["action_cleanup"]["retained"] else 0)
                    if mode in (2,3,9):
                        assert frame["action"] == 3 and (frame["action_cause"],frame["action_stage"]) == (1039,10)
                        assert frame["owns"] and frame["name_length"] == 37 and frame["parent"] != MAX and frame["child"] != MAX
                        assert frame["action_cleanup"]["retained"] and not frame["action_cleanup"]["child_attempt"] and not frame["action_cleanup"]["parent_attempt"]
                    if frame["owns"]:
                        assert frame["parent"] != MAX and owners["source"]["live"], "removal failure lost recovery owner"
                if index == 3:
                    assert frame["state"] == 5 and not frame["owns"] and frame["parent"] == frame["child"] == frame["caller"] == MAX
                    assert not any(frame["latest"].values()), frame["latest"]
                    assert frame["primary"] == frames[2]["primary"], "recovery replaced first diagnostic"
                    assert not frame["primary_retained"]
                if index in (1,2):
                    for role in ("caller","parent","child"):
                        if frame[role] != MAX: assert frame[role] in owners["live"], (role,frame,owners["live"])
                    if parent!=2 and not (mode==3 and frame["created"]==1):
                        raw=frames[0]["caller"]
                        assert frame["caller"]==raw and owners["live"][raw]["generation"]==frames[0]["owners"]["live"][raw]["generation"], "borrowed caller descriptor retired or reused"
                assert (anchor/"sentinel").read_bytes() == DATA and (cwd/"regular").read_bytes() == b"regular-parent"
                assert (os.stat(anchor).st_ino,stat.S_IMODE(os.stat(anchor).st_mode),os.stat(anchor).st_uid) == (original.st_ino,stat.S_IMODE(original.st_mode),original.st_uid)
                if replacement:
                    assert sorted((cwd/"anchor").iterdir()) == [cwd/"anchor/replacement"] and (cwd/"anchor/replacement").read_bytes() == DATA
                assert process.stdin.write(b"A") == 1
            process.stdin.close(); process.stdin=None
            extra,stderr=process.communicate(timeout=3)
            assert process.returncode == 0 and not extra, (process.returncode,extra,stderr)
            whole=analyze(trace.read_text(),self.sites,directory,final=True,repair=repair)
            assert whole["events"][-1]["name"] == "read" and whole["events"][-1]["args"] == '0, "\\x41", 1'
            assert "".join(item["marker"] for item in whole["events"] if "marker" in item).encode() == stderr
            assert entropy_names(whole) == frames[1]["stats"]["mkdir"]
            for item in selected(whole,"unlinkat"):
                if item["phase"] in ("A","B"):
                    assert TRUSTED.quoted(TRUSTED.arguments(item["args"])[1]) == frames[1]["name"], "cleanup targeted another name"
            for epoch in whole["epochs"]:
                if epoch["phase"] in ("A","B"):
                    removals=[item for item in epoch["events"] if item["name"]=="unlinkat"]
                    closes=[item for item in epoch["events"] if item["name"]=="close"]
                    if removals and closes: assert removals[0]["index"] < closes[0]["index"], "cleanup closed recovery descriptors before removal"
            if baseline:
                for fault in rules:
                    reference=baseline if "owners" in baseline else baseline[fault["syscall"]]
                    bind(reference["owners"],whole,[fault])
            result=dict(frames=frames,owners=whole,cwd=cwd,anchor=anchor)
            validate_result(whole,rules,result,check)
            return result
        except BaseException:
            if process.poll() is None: process.kill()
            try: process.communicate(timeout=3)
            except Exception: pass
            (directory/"failure.txt").write_text(traceback.format_exc())
            print(f"TempDir evidence: {directory}",file=sys.stderr)
            raise


def ordinary(value):
    before,created,first,final=value["frames"]
    assert created["created"] == 1 and not created["create_cause"]
    assert created["stats"] == dict(names=1,mkdir=1,opens=1,collisions=0,entropy=1)
    assert final["action"] == 1 and not final["action_cause"]
    target=value["anchor"]/os.fsdecode(created["name"])
    kept=created["mode"] in (1,9)
    assert target.exists() == kept
    if kept: assert final["keep"] == (1,0)
    if created["mode"] not in (2,3,9):
        assert first["action"] == 1 and not final["primary"][0]
    else:
        assert final["primary"] == (1039,10) and final["preserved"]


def failed(cause,stage,*,owned=False):
    def check(value):
        created=value["frames"][1]; first=value["frames"][2]; final=value["frames"][3]
        assert (created["created"],created["create_cause"],created["create_stage"]) == (3,cause,stage), created
        assert created["owns"] == owned
        assert final["primary"] == (cause,stage) and final["action"] == 1
        if owned: assert created["name_length"] == 37 and created["parent"] != MAX and created["child"] == MAX
        assert not any(path.name.startswith(".tmp-") for path in value["anchor"].iterdir())
    return check


def owner_group(suite):
    for mode in range(10):
        if mode == 8: continue
        suite.case(f"mode-{mode}",mode=mode,check=ordinary)


def admission_entropy_group(suite):
    for names,entropy in ((0,16),(1025,16),(8,0),(8,1048577)):
        value=suite.case(f"limits-{names}-{entropy}",names=names,entropy=entropy,check=failed(2,1))
        assert not selected(value["owners"],"mmap") and not selected(value["owners"],"fcntl","C")
    for parent,cause,stage in ((1,5,4),(2,1009,3),(3,6,5)):
        suite.case(f"parent-{parent}",parent=parent,check=failed(cause,stage))
    for error,retval,cause in (("EIO",None,2105),("EAGAIN",None,2111),(None,0,2002),(None,17,2003)):
        suite.case(f"entropy-{error or retval}",rules=[rule("getrandom",error=error,retval=retval)],check=failed(cause,6))
    value=suite.case("entropy-exhaustion",entropy=3,rules=[rule("getrandom",error="EINTR",repeat=True)],check=failed(2004,6))
    assert value["frames"][1]["stats"] == dict(names=1,mkdir=0,opens=0,collisions=0,entropy=3)
    suite.case("entropy-interrupted",rules=[rule("getrandom",error="EINTR")],check=lambda value: assert_recovered(value,2))
    suite.case("entropy-partial",rules=[rule("getrandom",retval=5,poke="0123456789")],check=lambda value: assert_recovered(value,2))
    for kind in ("file","directory","symlink"):
        def setup(cwd,kind=kind):
            leaf=cwd/"anchor"/os.fsdecode(ZERO)
            if kind=="file": leaf.write_bytes(DATA)
            if kind=="directory": leaf.mkdir(mode=0o751); leaf.chmod(0o751)
            if kind=="symlink": os.symlink("sentinel",leaf)
        def check(value,kind=kind):
            created_name=collision_recovered(value)
            leaf=value["anchor"]/os.fsdecode(ZERO)
            if kind=="file": assert leaf.read_bytes()==DATA
            if kind=="directory": assert leaf.is_dir() and not list(leaf.iterdir()) and stat.S_IMODE(os.stat(leaf).st_mode)==0o751
            if kind=="symlink": assert leaf.is_symlink() and os.readlink(leaf)=="sentinel"
            assert not (value["anchor"]/os.fsdecode(created_name)).exists()
        suite.case("collision-"+kind,setup=setup,rules=[rule("getrandom",retval=16,poke="00"*16)],check=check)
    def setup(cwd): (cwd/"anchor"/os.fsdecode(ZERO)).write_bytes(DATA)
    for limit,entropy,names,kind in ((3,16,3,"name-exhaustion"),(2,1,2,"shared-entropy")):
        value=suite.case(kind,names=limit,entropy=entropy,setup=setup,rules=[rule("getrandom",retval=16,poke="00"*16,repeat=entropy!=1)],check=None)
        created=value["frames"][1]
        assert (created["create_cause"],created["create_stage"]) == ((7,7) if entropy!=1 else (2004,6))
        assert created["stats"] == dict(names=names,mkdir=3 if entropy!=1 else 1,opens=0,collisions=3 if entropy!=1 else 1,entropy=3 if entropy!=1 else 1)
        assert (value["anchor"]/os.fsdecode(ZERO)).read_bytes()==DATA


def assert_recovered(value,calls):
    created=value["frames"][1]
    assert created["created"]==1 and created["stats"]==dict(names=1,mkdir=1,opens=1,collisions=0,entropy=calls)
    assert not value["frames"][3]["primary"][0]


def creation_faults_group(suite):
    baseline=suite.case("baseline",check=ordinary)
    attempts=baseline["owners"]["source"]["attempts"]
    assert attempts and all(value["length"]==37 for value in attempts)
    for item in attempts:
        suite.case("allocation",rules=[rule("mmap",item["ordinal"],error="ENOMEM")],baseline=baseline,check=failed(3,2))
    operations=[("fcntl",lambda item:"F_DUPFD_CLOEXEC" in item["args"],3,False),
                ("statx",lambda item:True,4,False),("fcntl",lambda item:"F_GETFL" in item["args"],5,False),
                ("mkdirat",lambda item:True,7,False),("openat",lambda item:True,8,True)]
    for name,predicate,stage,owned in operations:
        found=[item for item in selected(baseline["owners"],name,"C") if predicate(item)]; assert len(found)==1
        suite.case(f"{name}-{stage}",rules=[rule(name,found[0]["ordinal"],error="EIO")],baseline=baseline,check=failed(1005,stage,owned=owned))
    mkdir=selected(baseline["owners"],"mkdirat","C")[0]
    suite.case("mkdir-invalid-count",rules=[rule("mkdirat",mkdir["ordinal"],retval=1)],baseline=baseline,check=failed(1901,7))


def cleanup_faults_group(suite):
    baseline=suite.case("baseline",check=ordinary)
    unlink=selected(baseline["owners"],"unlinkat","A")[0]
    for mode in (0,6,8):
        def check(value,mode=mode):
            first,final=value["frames"][2:]
            assert (first["action"],first["action_cause"],first["action_stage"])==(3,1005,10)
            assert first["parent"]!=MAX and (first["child"]==MAX if mode==6 else first["child"]!=MAX) and first["owns"] and first["action_cleanup"]["retained"]
            assert not first["action_cleanup"]["child_attempt"] and not first["action_cleanup"]["parent_attempt"]
            assert final["primary"]==(1005,10) and final["preserved"]
            target=value["anchor"]/os.fsdecode(value["frames"][1]["name"])
            assert target.exists()==(mode==8)
            if mode==8: assert final["keep"]==(1,0)
        suite.case(f"remove-{'retry' if mode==0 else 'keep'}",mode=mode,rules=[rule("unlinkat",unlink["ordinal"],error="EIO")],baseline=baseline,check=check)
    for role,key,stage in ((1,"saved_child",9),(2,"saved_parent",11)):
        fd=baseline["frames"][1][key]
        found=[item for item in selected(baseline["owners"],"close","A") if item["args"]==str(fd)]; assert len(found)==1
        def check(value,stage=stage):
            first=value["frames"][2]
            assert (first["action_cause"],first["action_stage"])==(1005,stage) and first["primary"]==(1005,stage)
            assert not first["action_cleanup"]["retained"] and not first["owns"]
        suite.case(f"close-{role}",rules=[rule("close",found[0]["ordinal"],error="EIO")],baseline=baseline,repair=(found[0]["ordinal"],"A",role),check=check)
    explicit=suite.case("explicit-baseline",mode=6,check=ordinary)
    closed=selected(explicit["owners"],"close","F")[0]
    def explicit_check(value):
        first,cleanup,final=value["frames"][1:]
        assert first["explicit"]==(3,1005,9,1) and first["primary"]==(1005,9)
        assert first["latest"]["child_attempt"] and first["latest"]["child_error"]==5
        assert cleanup["action"]==1 and not cleanup["action_cleanup"]["child_attempt"] and final["primary"]==(1005,9)
    suite.case("explicit-close-error",mode=6,rules=[rule("close",closed["ordinal"],error="EIO")],baseline=explicit,repair=(closed["ordinal"],"F",3),check=explicit_check)
    opened=selected(baseline["owners"],"openat","C")[0]
    control=suite.case("open-failure-control",rules=[rule("openat",opened["ordinal"],error="EIO")],baseline=baseline,check=failed(1005,8,owned=True))
    remove=selected(control["owners"],"unlinkat","A")[0]
    def secondary(value):
        created,first,final=value["frames"][1:]
        assert created["primary"]==(1005,8) and first["primary"]==(1005,8) and final["primary"]==(1005,8)
        assert (first["action_cause"],first["action_stage"])==(1005,8)
        assert first["latest"]["remove_error"]==first["action_cleanup"]["remove_error"]==1 and first["parent"]!=MAX and first["child"]==MAX and final["preserved"]
    suite.case("first-vs-secondary",rules=[rule("openat",opened["ordinal"],error="EIO"),rule("unlinkat",remove["ordinal"],error="EPERM")],baseline={"openat":baseline,"unlinkat":control},check=secondary)


def controls():
    count=SOURCE.controls()
    packet=struct.pack("<64Q",1413761362,1,*([0]*62))+bytes(37)
    assert decode(packet)["checkpoint"]==0; count+=1
    for bad in (packet[:-1],packet+b"x",bytes(549)):
        try: decode(bad)
        except (AssertionError,struct.error): count+=1
        else: raise AssertionError("accepted changed TempDir frame")
    class Pairs(list): pass
    pairs=Pairs([(0x401002,0x401012)]); pairs.mmap_flags={0x401002:0x22}; pairs.executable_ranges=[(0x400000,0x402000)]
    sites=(pairs,[])
    def line(body,ip=0x401002): return f"[{ip:016x}] {body}\n"
    def quoted(value): return '"'+''.join(f"\\x{byte:02x}" for byte in value)+'"'
    def marker(value): return line(f'write(2, "\\x{ord(value):02x}", 1) = 1')
    opened=line(f'openat(AT_FDCWD, {quoted(b"anchor")}, O_RDONLY|O_DIRECTORY|O_CLOEXEC) = 3')
    child=line(f'openat(3, {quoted(ZERO)}, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC) = 4')
    close4=line('close(4) = 0'); close3=line('close(3) = 0')
    base=opened+marker("C")+child+marker("c")+marker("A")+close4+close3+marker("a")
    failed_close=line('close(4) = -1 EIO (Input/output error) (INJECTED)')
    # Construct the repair epochs explicitly; never treat a skipped close as
    # a physical release or permit production to retry that fd generation.
    repaired=opened+marker("C")+child+marker("c")+marker("A")+failed_close+marker("a")+marker("Q")+close4+marker("q")+marker("P")+close3+marker("p")
    with tempfile.TemporaryDirectory(prefix="temp-dir-ledger-cpu-") as directory:
        assert not analyze(base,sites,directory,final=True)["live"]; count+=1
        assert not analyze(repaired,sites,directory,final=True,repair=(1,"A",1))["live"]; count+=1
        wrong_parent=opened+marker("C")+child.replace('openat(3,','openat(9,')+marker("c")+close3
        bad_query=opened+line('fcntl(9, F_GETFL) = -1 EBADF (Bad file descriptor)')+close3
        retry=repaired.replace(marker("Q"),marker("B")).replace(marker("q"),marker("b"))
        for bad,repair in ((opened+line('close(9) = 0')+close3,None),
                           (base+close4,None),(retry,(1,"A",1)),(wrong_parent,None),(bad_query,None),
                           (opened+line('fcntl(3, F_GETFL) = 0x8000 (flags O_RDONLY|O_LARGEFILE)',0x500002)+close3,None),
                           (opened+marker("K")+close3+marker("k"),None)):
            try: analyze(bad,sites,directory,final=True,repair=repair)
            except AssertionError: count+=1
            else: raise AssertionError("accepted descriptor/phase/instruction provenance mutation")
    draw=line('getrandom('+quoted(bytes(16))+', 16, GRND_NONBLOCK) = 16')
    mkdir=line('mkdirat(3, '+quoted(ZERO)+', 0700) = 0')
    candidate=dict(events=TRUSTED.events(marker("C")+draw+mkdir+marker("c"))[0])
    assert entropy_names(candidate)==1; count+=1
    changed=mkdir.replace(quoted(ZERO),quoted(ONE))
    try: entropy_names(dict(events=TRUSTED.events(marker("C")+draw+changed+marker("c"))[0]))
    except AssertionError: count+=1
    else: raise AssertionError("accepted entropy/name disagreement")
    injected=draw.replace(" = 16"," = -1 EIO (Input/output error) (INJECTED)")+mkdir.replace(" = 0"," = 1 (INJECTED)")
    owners=dict(events=TRUSTED.events(injected)[0])
    rules=[rule("getrandom",error="EIO"),rule("mkdirat",retval=1)]
    observed=[]; result=object()
    validate_result(owners,rules,result,lambda actual: observed.append(actual))
    assert observed==[result], "injection expectation assembly lost or replaced the callback"
    count+=1
    def rejecting(actual):
        assert actual is result
        raise RuntimeError("callback-rejection-witness")
    try: validate_result(owners,rules,result,rejecting)
    except RuntimeError as error:
        assert str(error)=="callback-rejection-witness"; count+=1
    else: raise AssertionError("injection validation skipped the callback")
    assert injection_options(rules)==["-e","inject=getrandom:error=EIO:when=1","-e","inject=mkdirat:retval=1:when=1"]
    count+=1
    try: injection_options([rule("getrandom",retval=16,poke="00"*16),rule("getrandom",2,retval=16,poke="01"*16)])
    except AssertionError: count+=1
    else: raise AssertionError("accepted strace options that overwrite the first entropy injection")
    forced=draw.replace(" = 16"," = 16 (INJECTED: args, retval)")
    collision=mkdir.replace(" = 0"," = -1 EEXIST (File exists)")
    fresh=draw.replace(quoted(bytes(16)),quoted(bytes([1])*16))
    succeeded=mkdir.replace(quoted(ZERO),quoted(ONE))
    def recovery(text,*,name=ONE,attempts=2,entropy=None):
        created=dict(created=1,create_cause=0,name=name,stats=dict(names=attempts,mkdir=attempts,opens=1,
                     collisions=attempts-1,entropy=attempts if entropy is None else entropy))
        return dict(frames=[{},created],owners=dict(events=TRUSTED.events(marker("C")+text+marker("c"))[0]))
    recovered=forced+collision+fresh+succeeded
    assert collision_recovered(recovery(recovered))==ONE; count+=1
    assert collision_recovered(recovery(forced+collision+draw+collision+fresh+succeeded,attempts=3))==ONE
    count+=1
    other=b".tmp-"+b"02"*16
    mutations=(recovery(recovered.replace(forced,draw)),
               recovery(recovered.replace(collision,mkdir)),
               recovery(recovered,name=other),
               recovery(recovered,entropy=3),
               recovery(recovered.replace(fresh,fresh.replace(" = 16"," = 16 (INJECTED: args, retval)"))),
               recovery(recovered.replace(succeeded,succeeded.replace(quoted(ONE),quoted(other))),name=other),
               recovery(recovered.replace("EEXIST (File exists)","EIO (Input/output error)")))
    for changed in mutations:
        try: collision_recovered(changed)
        except AssertionError: count+=1
        else: raise AssertionError("accepted changed collision/draw/name/counter evidence")
    print(f"temp-dir controls={count} native-cases=0")


def main():
    if len(sys.argv)==2 and sys.argv[1]=="controls": controls(); return
    assert len(sys.argv)==3
    group=sys.argv[1]; assert group in ("owner","admission_entropy","creation_faults","cleanup_faults")
    suite=Suite(group,sys.argv[2]); globals()[group+"_group"](suite)
    assert suite.count>0
    print(f"temp-dir group={group} cases={suite.count}")


if __name__=="__main__": main()
