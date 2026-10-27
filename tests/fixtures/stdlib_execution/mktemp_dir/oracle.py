"""Actual mktemp_dir CLI/namespace/fault oracle; no library implementation.

Raw ELF allocation authority is reused read-only from the accepted TempFile
verifier. A skipped injected close is logical retirement, never physical close.
"""
import ast
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("mktemp_dir_trusted_resources", HERE.parent / "temp_file/ledger.py")
TRUSTED = importlib.util.module_from_spec(spec)
spec.loader.exec_module(TRUSTED)
CALLS = TRUSTED.CALLS | {"rt_sigaction"}
TRACE = ",".join(sorted(CALLS))
NAME = re.compile(rb"\.tmp-[0-9a-f]{32}")
USAGE = b"usage: mktemp_dir PARENT\n"


def events(text):
    assert not text or text.endswith("\n"), "unfinished trace"
    found, counts = [], Counter()
    for index, line in enumerate(text.splitlines()):
        match = TRUSTED.LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unsupported trace event", line)
        ip, name, raw, result = match.groups()
        counts[name] += 1
        found.append(dict(ip=int(ip, 16), name=name, args=TRUSTED.arguments(raw),
                          result=result, ordinal=counts[name], index=index, line=line))
    return found


def number(entry):
    return int(entry["result"].split()[0], 0)


def rule(syscall, when=1, error=None, retval=None, repeat=False):
    assert syscall in CALLS and when > 0 and ((error is None) != (retval is None))
    return dict(syscall=syscall, when=when, error=error, retval=retval, repeat=repeat)


def injection(item):
    action = "error=" + item["error"] if item["error"] else "retval=" + str(item["retval"])
    return "inject=%s:%s:when=%d%s" % (item["syscall"], action, item["when"], "+" if item["repeat"] else "")


def reached(entries, rules):
    selected = []
    for item in rules:
        matching = [entry for entry in entries if entry["name"] == item["syscall"]
                    and (entry["ordinal"] >= item["when"] if item["repeat"] else entry["ordinal"] == item["when"])]
        assert matching, ("unreached injection", item)
        for entry in matching:
            assert "INJECTED" in entry["result"], (item, entry)
            if item["error"]:
                assert entry["result"].split()[:2] == ["-1", item["error"]], (item, entry)
            else:
                assert number(entry) == item["retval"], (item, entry)
        selected += matching
    injected = [entry for entry in entries if "INJECTED" in entry["result"]]
    assert {entry["index"] for entry in injected} == {entry["index"] for entry in selected}, (rules, injected)


def selected(result, name):
    return [entry for entry in result["events"] if entry["name"] == name]


def semantic(entry):
    """Retain owner fd/scalars; exclude only actual pointer/entropy values."""
    args = entry["args"]
    if entry["name"] == "getrandom":
        return args[1:]
    if entry["name"] == "statx":
        return args[:4]
    if entry["name"] == "rt_sigaction":
        return [args[0], args[-1]]
    return [re.sub(r"(?:\\x[0-9a-f]{2}){37}", "<candidate>", arg)
            if entry["name"] == "write" and args[0] == "1"
            else re.sub(r"\\x2e\\x74\\x6d\\x70\\x2d(?:\\x[0-9a-f]{2}){32}", "<candidate>", arg)
            for arg in args]


def bind(before, after, item):
    old = [entry for entry in before["events"] if entry["name"] == item["syscall"] and entry["ordinal"] == item["when"]]
    new = [entry for entry in after["events"] if entry["name"] == item["syscall"] and entry["ordinal"] == item["when"]]
    assert len(old) == len(new) == 1, ("missing baseline target", item, old, new)
    old, new = old[0], new[0]
    assert old["ip"] == new["ip"] and semantic(old) == semantic(new), ("wrong injected owner/site/arguments", old, new)
    # Exact global syscall ordinal, raw post-IP, flags/requested length and
    # source prefix bind allocation faults; addresses returned by ASLR vary.
    if item["syscall"] == "mmap":
        old_maps = [entry for entry in before["events"] if entry["name"] == "mmap" and entry["ordinal"] <= item["when"]]
        new_maps = [entry for entry in after["events"] if entry["name"] == "mmap" and entry["ordinal"] <= item["when"]]
        assert [(entry["ip"], entry["args"]) for entry in old_maps] == [(entry["ip"], entry["args"]) for entry in new_maps]


def resources(entries, profile, evidence):
    maps = "".join(entry["line"] + "\n" for entry in entries if entry["name"] in ("mmap", "munmap"))
    source = TRUSTED.source_maps(maps, profile, evidence)
    live, physical, generations, owners = {}, {}, Counter(), []
    peak = 0
    for entry in entries:
        name, args, value = entry["name"], entry["args"], number(entry)
        acquired = name == "openat" or (name == "fcntl" and args[1] in ("F_DUPFD", "F_DUPFD_CLOEXEC"))
        if acquired and value >= 0:
            if name == "fcntl":
                assert int(args[0]) in live, ("duplicate of unowned parent", entry, live)
            assert value not in physical and value not in live, ("reused live native owner", entry)
            generations[value] += 1
            owner = dict(fd=value, generation=generations[value], opened=entry, closed=None, skipped=False)
            live[value] = physical[value] = owner
            owners.append(owner)
            peak = max(peak, len(physical))
        elif name == "close":
            fd = int(args[0])
            assert fd in live, ("unowned/repeated close", entry, live)
            owner = live.pop(fd)
            owner["closed"] = entry
            if value == 0:
                assert "INJECTED" not in entry["result"], "fake close success is not release evidence"
                physical.pop(fd)
            else:
                assert "INJECTED" in entry["result"] and value == -1, entry
                owner["skipped"] = True  # Kept in physical until OS process exit.
    assert not live, ("logical fd owner survived explicit cleanup", live)
    assert peak <= 3, ("more than caller parent + anchor + child", peak)
    assert all(owner["skipped"] for owner in physical.values()), physical
    return dict(source=source, owners=owners, peak=peak, skipped=list(physical.values()))


def entropy_names(result):
    pending, candidates = b"", []
    for entry in result["events"]:
        if entry["name"] == "getrandom" and number(entry) > 0:
            count = number(entry)
            if "INJECTED" in entry["result"]:
                continue  # This oracle never invents successful entropy bytes.
            raw = TRUSTED.quoted(entry["args"][0])
            assert len(raw) == count <= int(entry["args"][1])
            pending += raw
            assert len(pending) <= 16
            if len(pending) == 16:
                candidates.append(b".tmp-" + pending.hex().encode())
                pending = b""
        elif entry["name"] == "mkdirat":
            name = TRUSTED.quoted(entry["args"][1])
            assert candidates and name == candidates.pop(0), ("name not derived from this OS entropy", name, candidates)
            assert NAME.fullmatch(name) and entry["args"][2] == "0700", entry
    return [entry for entry in selected(result, "mkdirat") if number(entry) == 0]


def inspect(path):
    info = os.lstat(path)
    assert stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700, (path, info)
    assert info.st_nlink == 2 and not os.listdir(path), (path, info)
    return (info.st_dev, info.st_ino)


def successful(result):
    assert result["code"] == 0 and not result["stderr"], result
    assert len(result["stdout"]) == 38 and result["stdout"][-1:] == b"\n" and NAME.fullmatch(result["stdout"][:-1]), result["stdout"]
    name = result["stdout"][:-1]
    assert result["after"] - result["before"] == {name} and result["before"] <= result["after"], result
    inspect(os.path.join(os.fsencode(result["parent"]), name))
    made = entropy_names(result)
    assert len(made) == 1 and TRUSTED.quoted(made[0]["args"][1]) == name
    assert not selected(result, "unlinkat"), "successful keep unexpectedly removed a name"
    writes = [entry for entry in selected(result, "write") if entry["args"][0] == "1"]
    assert writes and sum(number(entry) for entry in writes if "INJECTED" not in entry["result"] and number(entry) > 0) == 38
    child = [owner for owner in result["resources"]["owners"] if owner["opened"]["name"] == "openat"
             and TRUSTED.quoted(owner["opened"]["args"][1]) == name]
    assert len(child) == 1 and child[0]["closed"]["index"] < writes[0]["index"], child
    caller = [owner for owner in result["resources"]["owners"] if owner["opened"]["name"] == "openat" and owner not in child]
    assert len(caller) == 1 and caller[0]["closed"]["index"] < writes[0]["index"], caller
    assert not result["resources"]["skipped"], "success used a skipped close"


def no_creation(result, code):
    assert result["code"] == code and not result["stdout"] and result["before"] == result["after"], result
    assert not selected(result, "mkdirat") and not selected(result, "unlinkat"), result["events"]


class Cases:
    def __init__(self, executable, group):
        self.executable = Path(executable).resolve()
        self.root = Path(tempfile.mkdtemp(prefix="lanius-mktemp-dir-" + group + "-"))
        self.profile = TRUSTED.verified_sites(self.executable, self.root)
        pairs, named = self.profile
        assert pairs and not named and getattr(pairs, "executable_ranges", []), "raw source provenance required"
        self.count, self.work = 0, set()

    def run(self, label, args=(b"parent",), *, rules=(), work=None, parent=b"parent", broken_pipe=False):
        directory = self.root / ("%03d-" % self.count + label)
        directory.mkdir()
        if work is None:
            work = directory / "work"
            work.mkdir()
            (work / "parent").mkdir()
        self.work.add(work)
        target = os.path.join(os.fsencode(work), parent)
        before = set(os.listdir(target)) if os.path.isdir(target) else set()
        trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "8192", "-e", "signal=none",
                   "-o", str(trace), "-e", "trace=" + TRACE]
        for item in rules:
            command += ["-e", injection(item)]
        command += [os.fsencode(self.executable), *args]
        (directory / "command.txt").write_text(repr(command) + "\n")
        reader = writer = None
        try:
            if broken_pipe:
                reader, writer = os.pipe()
                os.close(reader)
                reader = None
            completed = subprocess.run(command, cwd=work, stdin=subprocess.DEVNULL,
                                       stdout=writer if broken_pipe else subprocess.PIPE,
                                       stderr=subprocess.PIPE, timeout=5, umask=0o022)
        finally:
            if writer is not None:
                os.close(writer)
        stdout = completed.stdout or b""
        (directory / "stdout.bin").write_bytes(stdout)
        (directory / "stderr.bin").write_bytes(completed.stderr)
        (directory / "status.txt").write_text(str(completed.returncode) + "\n")
        found = events(trace.read_text())
        reached(found, rules)
        verified = resources(found, self.profile, directory)
        after = set(os.listdir(target)) if os.path.isdir(target) else set()
        result = dict(code=completed.returncode, stdout=stdout, stderr=completed.stderr,
                      events=found, resources=verified, before=before, after=after,
                      work=work, parent=os.fsdecode(target), evidence=directory)
        (directory / "namespace.txt").write_text(repr((before, after)) + "\n")
        self.count += 1
        return result

    def finish(self, group):
        # The host oracle, not production, removes every kept/recovery directory
        # only inside its owned temporary work roots. Trace evidence remains.
        for work in self.work:
            shutil.rmtree(work)
        print("mktemp-dir group=%s cases=%d" % (group, self.count))


def normal(cases):
    first = cases.run("relative")
    successful(first)
    second = cases.run("new-name", work=first["work"])
    successful(second)
    assert first["stdout"] != second["stdout"]
    absolute = os.fsencode(first["work"] / "parent")
    successful(cases.run("absolute", (absolute,), work=first["work"]))
    raw = b"raw-\xff"
    os.mkdir(os.path.join(os.fsencode(first["work"]), raw))
    successful(cases.run("raw-parent", (raw,), work=first["work"], parent=raw))
    (first["work"] / "alias").symlink_to("parent", target_is_directory=True)
    successful(cases.run("intermediate-symlink", (b"alias/.",), work=first["work"]))


def arguments(cases):
    for label, args in [("no-parent", ()), ("too-many", (b"parent", b"parent")),
                        ("empty", (b"",)), ("unknown-option", (b"--unknown",)),
                        ("help-plus-parent", (b"--help", b"parent")),
                        ("byte-limit", (b"x" * 4096,))]:
        result = cases.run(label, args)
        no_creation(result, 2)
        assert not selected(result, "openat") and not selected(result, "getrandom")
        assert len(selected(result, "rt_sigaction")) == 1
    help_result = cases.run("help", (b"--help",))
    assert help_result["code"] == 0 and help_result["stdout"] == USAGE and not help_result["stderr"]
    assert not selected(help_result, "openat") and not selected(help_result, "getrandom")
    closed_help = cases.run("actual-closed-help-pipe", (b"--help",), broken_pipe=True)
    no_creation(closed_help, 3)
    assert not selected(closed_help, "openat") and not selected(closed_help, "getrandom")
    assert any(entry["result"].startswith("-1 EPIPE ") and "INJECTED" not in entry["result"] for entry in selected(closed_help, "write"))
    for label, args in [("missing", (b"missing",)), ("exact-byte-cap", (b"x" * 4095,))]:
        result = cases.run(label, args)
        no_creation(result, 3)
        assert len(selected(result, "openat")) == 1
    base = cases.run("prepare-parent")
    successful(base)
    (base["work"] / "regular").write_bytes(b"unchanged")
    (base["work"] / "alias").symlink_to("parent", target_is_directory=True)
    for value in (b"regular", b"alias"):
        no_creation(cases.run("not-directory-or-final-symlink", (value,), work=base["work"]), 3)
    assert (base["work"] / "regular").read_bytes() == b"unchanged"


def allocations(cases):
    baseline = cases.run("baseline")
    successful(baseline)
    points = [entry for entry in selected(baseline, "mmap")
              if any(site[0] == entry["ip"] for site in cases.profile[0])]
    assert 0 < len(points) <= 32, points  # Harness safety bound, not an old floor.
    for entry in points:
        item = rule("mmap", entry["ordinal"], error="ENOMEM")
        failed = cases.run("source-oom-%d" % entry["ordinal"], rules=[item])
        bind(baseline, failed, item)
        no_creation(failed, 4)
        assert len([e for e in failed["resources"]["source"]["allocations"] if e["injected"]]) == 1


def faults(cases):
    baseline = cases.run("baseline")
    successful(baseline)
    for call, ordinal in [("rt_sigaction", 1), ("openat", 1), ("fcntl", 1), ("statx", 1), ("fcntl", 2), ("getrandom", 1), ("mkdirat", 1)]:
        item = rule(call, ordinal, error="EIO")
        failed = cases.run("%s-%d" % (call, ordinal), rules=[item])
        bind(baseline, failed, item)
        no_creation(failed, 3) if call != "mkdirat" else None
        assert failed["code"] == 3 and not failed["stdout"] and failed["before"] == failed["after"]
    for item in [rule("getrandom", error="EINTR"), rule("mkdirat", error="EEXIST"), rule("write", error="EINTR")]:
        result = cases.run("one-interruption-or-collision", rules=[item])
        bind(baseline, result, item)
        successful(result)
    for item in [rule("getrandom", retval=0), rule("getrandom", retval=17), rule("getrandom", error="EINTR", repeat=True)]:
        failed = cases.run("entropy-bounds", rules=[item])
        bind(baseline, failed, item)
        no_creation(failed, 3)
        assert 1 <= len(selected(failed, "getrandom")) <= 128
    opened = rule("openat", 2, error="EIO")
    failed = cases.run("child-open", rules=[opened])
    bind(baseline, failed, opened)
    assert failed["code"] == 3 and not failed["stdout"] and failed["before"] == failed["after"]
    assert len(entropy_names(failed)) == len(selected(failed, "unlinkat")) == 1
    for ordinal in (1, 2, 3):
        item = rule("close", ordinal, error="EIO")
        failed = cases.run("close-%d" % ordinal, rules=[item])
        bind(baseline, failed, item)
        assert failed["code"] == 3 and len(failed["resources"]["skipped"]) == 1
        if ordinal < 3:
            assert not failed["stdout"] and failed["before"] == failed["after"]
            assert len(selected(failed, "unlinkat")) == 1
        else:
            assert len(failed["stdout"]) == 38 and NAME.fullmatch(failed["stdout"][:-1])
            assert failed["after"] - failed["before"] == {failed["stdout"][:-1]}
            inspect(os.path.join(os.fsencode(failed["parent"]), failed["stdout"][:-1]))
    output_failure = None
    for item in [rule("write", error="EIO"), rule("write", retval=0), rule("write", retval=39), rule("write", error="EINTR", repeat=True)]:
        failed = cases.run("output-failure", rules=[item])
        bind(baseline, failed, item)
        assert failed["code"] == 3 and not failed["stdout"] and failed["before"] == failed["after"]
        assert len(selected(failed, "unlinkat")) == 1
        if item["repeat"]:
            assert len([entry for entry in selected(failed, "write") if entry["args"][0] == "1"]) == 64
        if item["error"] == "EIO":
            output_failure = failed
    real_pipe = cases.run("actual-broken-pipe", broken_pipe=True)
    assert real_pipe["code"] == 3 and real_pipe["before"] == real_pipe["after"]
    assert any(entry["result"].startswith("-1 EPIPE ") and "INJECTED" not in entry["result"] for entry in selected(real_pipe, "write"))
    for errno in ("EIO", "EINTR", "ENOTEMPTY"):
        cleanup = rule("unlinkat", error=errno)
        retained = cases.run("retained-cleanup", rules=[rule("write", error="EIO"), cleanup])
        bind(output_failure, retained, cleanup)
        assert retained["code"] == 3 and not retained["stdout"]
        new = retained["after"] - retained["before"]
        assert len(new) == 1 and retained["before"] <= retained["after"]
        name = next(iter(new))
        assert NAME.fullmatch(name) and b"remove parent-relative name: " + name + b"\n" in retained["stderr"]
        inspect(os.path.join(os.fsencode(retained["parent"]), name))
        assert len(selected(retained, "unlinkat")) == 1, "CLI retried removal without a selected policy"


def controls():
    count = 0
    def reject(call):
        nonlocal count
        try:
            call()
        except (AssertionError, ValueError):
            count += 1
        else:
            raise AssertionError("negative control accepted")
    sample = events('[10] write(1, "\\x61", 1) = -1 EIO (Input/output error) (INJECTED)\n')
    reached(sample, [rule("write", error="EIO")]); count += 1
    for item in (rule("write", 2, error="EIO"), rule("write", error="EINTR"), rule("write", retval=0)):
        reject(lambda item=item: reached(sample, [item]))
    reject(lambda: reached(sample, []))
    reject(lambda: events('[10] write(1, "\\x61", 1) = 1'))
    reject(lambda: events('[10] execve(0) = 0\n'))
    old = dict(events=events('[10] mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x10000\n'))
    new = dict(events=events('[10] mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (INJECTED)\n'))
    bind(old, new, rule("mmap", error="ENOMEM")); count += 1
    for changed in ('[11] mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (INJECTED)\n',
                    '[10] mmap(NULL, 38, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (INJECTED)\n'):
        reject(lambda changed=changed: bind(old, dict(events=events(changed)), rule("mmap", error="ENOMEM")))
    raw = bytes(range(16)); leaf = b".tmp-" + raw.hex().encode()
    quoted = lambda value: '"' + ''.join('\\x%02x' % byte for byte in value) + '"'
    model = dict(events=events('[10] getrandom(%s, 16, 0) = 16\n[20] mkdirat(4, %s, 0700) = 0\n' % (quoted(raw), quoted(leaf))))
    assert len(entropy_names(model)) == 1; count += 1
    reject(lambda: entropy_names(dict(events=events('[20] mkdirat(4, %s, 0700) = 0\n' % quoted(leaf)))))
    changed = dict(events=[dict(entry) for entry in model["events"]])
    changed["events"][1]["args"][1] = quoted(b".tmp-" + b"f" * 32)
    reject(lambda: entropy_names(changed))
    assert NAME.fullmatch(leaf) and len(leaf) == 37; count += 1
    reject(lambda: rule("write", error="EIO", retval=1))
    source = (HERE.parents[3] / "sample_programs/library/mktemp_dir.lani").read_text()
    for match in re.finditer(r'(?:literal|message)\(("(?:\\.|[^"\\])*"),(\d+)\)', source):
        assert len(ast.literal_eval(match[1]).encode()) == int(match[2]), match[0]
    count += 1
    print("mktemp-dir CPU controls=%d" % count)


def main():
    if sys.argv[1:] == ["controls"]:
        controls()
        return
    assert len(sys.argv) == 3 and sys.argv[1] in ("normal", "arguments", "allocations", "faults")
    group = sys.argv[1]
    cases = Cases(sys.argv[2], group)
    try:
        globals()[group](cases)
        cases.finish(group)
    except BaseException:
        print("mktemp-dir evidence: " + str(cases.root), file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
