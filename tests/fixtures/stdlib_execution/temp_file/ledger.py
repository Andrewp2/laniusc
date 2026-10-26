"""Independent file generations/phases and reused verified source-map accounting."""
import ast
from collections import Counter
import importlib.util
from pathlib import Path
import re
import struct
import subprocess
import types

FIXTURES = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SHARED = load("temp_file_trusted_source_ledger", FIXTURES / "extended/https_batch/resources.py")
# These exact trusted functions admit raw compiler ELF output without a new
# scanner or importing another executable oracle's unguarded CLI/dependencies.
_source = FIXTURES / "extended/server_concurrency/scale_ledger.py"
_definitions = [node for node in ast.parse(_source.read_text()).body
                if isinstance(node, ast.FunctionDef) and node.name in ("raw_runtime_pairs", "verified_sites")]
assert len(_definitions) == 2
_namespace = dict(RESOURCES=SHARED, Path=Path, re=re, struct=struct, subprocess=subprocess)
exec(compile(ast.Module(body=_definitions, type_ignores=[]), str(_source), "exec"), _namespace)
verified_sites = _namespace["verified_sites"]

CALLS = {"read", "write", "openat", "close", "fcntl", "statx", "getrandom",
         "unlinkat", "renameat2", "mkdir", "mkdirat", "chdir", "fchdir", "lseek",
         "getpid", "mmap", "munmap", "fsync", "fdatasync"}
TRACE = ",".join(sorted(CALLS))
LINE = re.compile(r"^\[([0-9a-fA-F]+)\]\s+([a-z0-9_]+)\((.*)\)\s+=\s+(.+)$")
PHASES = "CcFfKkRrUuAaBbXxQqPp"
U64_MAX = (1 << 64) - 1


def quoted(value):
    assert re.fullmatch(r'"(?:\\x[0-9a-f]{2})*"', value), value
    return bytes.fromhex(value[1:-1].replace("\\x", ""))


def arguments(value):
    """Comma-separated scalar/hex-string syscall arguments used in this gate."""
    parts = re.findall(r'"(?:\\x[0-9a-f]{2})*"|[^,]+', value)
    return [part.strip() for part in parts]


def events(text):
    assert not text or text.endswith("\n"), "incomplete native trace"
    found, counts, phase, epochs = [], Counter(), None, []
    for number, line in enumerate(text.splitlines()):
        assert line and not line.startswith(("+++", "---")), ("unexpected trace event", line)
        match = LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unsupported syscall", line)
        address, name, args, result = match.groups()
        counts[name] += 1
        entry = dict(ip=int(address, 16), name=name, args=args, result=result,
                     ordinal=counts[name], line=line, index=number, phase=phase)
        token = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args) if name == "write" and result == "1" else None
        if token:
            token = chr(int(token[1], 16))
            assert token in PHASES, entry
            if token.isupper():
                assert phase is None, (phase, entry)
                phase = token
                entry["phase"] = phase
                epochs.append(dict(phase=phase, start=number, end=None, events=[]))
            else:
                assert phase == token.upper(), (phase, entry)
                entry["phase"] = phase
                epochs[-1]["end"] = number
                phase = None
            entry["marker"] = token
        elif phase is not None:
            epochs[-1]["events"].append(entry)
        found.append(entry)
    assert phase is None, ("unclosed phase", phase)
    return found, epochs


def source_maps(text, profile, directory):
    """Run the existing source ownership checker unchanged on all map events."""
    pairs, named = profile
    # A private function binding supplies the already-verified raw ELF profile.
    # No shared module, source file, runtime or production operation is patched.
    namespace = dict(SHARED.analyze.__globals__)
    namespace["verified_sites"] = lambda _executable: (pairs, named)
    checker = types.FunctionType(SHARED.analyze.__code__, namespace)
    path = Path(directory) / "verified-source-mappings.trace"
    selected = [entry["line"] for entry in events(text)[0] if entry["name"] in ("mmap", "munmap")]
    path.write_text("".join(line + "\n" for line in selected))
    return checker(path, "verified-temp-file-profile", epochs=False, injected_close=None)


def analyze(text, profile, directory, *, repaired_close=None, repair_phase="A"):
    entries, epochs = events(text)
    live, generations, acquisitions, closes = {}, Counter(), [], []
    for entry in entries:
        name, args, result = entry["name"], arguments(entry["args"]), entry["result"].split()[0]
        if name == "openat" and result.isdecimal():
            fd = int(result)
            assert fd not in live, ("fd reopened while still owned", live, entry)
            generations[fd] += 1
            owner = dict(fd=fd, generation=generations[fd], acquired=entry, closed=None)
            live[fd] = owner
            acquisitions.append(owner)
        elif name == "fcntl" and len(args) >= 2 and args[1] in ("F_DUPFD", "F_DUPFD_CLOEXEC") and result.isdecimal():
            source, fd = int(args[0]), int(result)
            assert source in live and fd not in live, (live, entry)
            generations[fd] += 1
            owner = dict(fd=fd, generation=generations[fd], acquired=entry, closed=None,
                         duplicate_of=(source, live[source]["generation"]))
            live[fd] = owner
            acquisitions.append(owner)
        elif name == "close":
            fd = int(args[0])
            assert fd in live, ("unowned/repeated close", live, entry)
            entry["generation"] = live[fd]["generation"]
            closes.append(entry)
            if result == "0":
                live.pop(fd)["closed"] = entry
            else:
                # strace skips the kernel close. Keep the same fd generation
                # live until its separately marked raw repair succeeds.
                assert repaired_close is not None and entry["ordinal"] == repaired_close and "INJECTED" in entry["result"] and entry["result"].split()[:2] == ["-1", "EIO"] and entry["phase"] == repair_phase, entry
    assert not live, ("native fd survived release checkpoint", live)
    if repaired_close is not None:
        failed = [entry for entry in closes if entry["ordinal"] == repaired_close]
        assert len(failed) == 1 and failed[0]["result"].startswith("-1 EIO "), failed
        item = failed[0]
        repairs = [entry for entry in closes if entry["args"] == item["args"] and entry["generation"] == item["generation"] and entry["index"] > item["index"]]
        assert len(repairs) == 1 and repairs[0]["phase"] == "Q" and repairs[0]["result"] == "0", repairs
    for epoch in epochs:
        phase, body = epoch["phase"], epoch["events"]
        if phase == "K":
            assert not body, ("keep performed native work", body)
        if phase == "X":
            assert not any(entry["name"] != "munmap" for entry in body), ("terminal destroy repeated native cleanup", body)
        if phase == "Q":
            assert len(body) == 1 and body[0]["name"] == "close" and body[0]["result"] == "0", body
    maps = source_maps(text, profile, directory)
    return dict(events=entries, epochs=epochs, acquisitions=acquisitions, closes=closes,
                source=maps, markers="".join(entry["marker"] for entry in entries if "marker" in entry).encode())


def check_injections(ledger, rules):
    """Each declared synthetic call must be reached; no unexplained tampering."""
    entries = ledger["events"]
    marked = [entry for entry in entries if "INJECTED" in entry["result"] or "POKED" in entry["result"]]
    expected = []
    for rule in rules:
        matches = [entry for entry in entries if entry["name"] == rule["syscall"]
                   and (entry["ordinal"] >= rule["when"] if rule.get("repeat") else entry["ordinal"] == rule["when"])]
        assert matches, ("injection not reached", rule)
        for entry in matches:
            assert entry in marked, ("intended call was not synthetic", rule, entry)
            if "error" in rule:
                assert entry["result"].split()[:2] == ["-1", rule["error"]], entry
            if "retval" in rule:
                assert entry["result"].split()[0] == str(rule["retval"]), entry
        expected.extend(matches)
    assert sorted(entry["index"] for entry in marked) == sorted(entry["index"] for entry in expected), (marked, expected)


def controls():
    """Only synthetic traces and exact trusted source-ledger invariants."""
    import tempfile
    a, f = 0x401002, 0x401012
    def event(text, ip=a):
        return f"[{ip:016x}] {text}\n"
    def mark(token):
        return event('write(2, "\\x%02x", 1) = 1' % ord(token))
    allocated = event("mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x41000000")
    free = event("munmap(0x41000000, 37) = 0", f)
    opened = event('openat(AT_FDCWD, "\\x61", O_RDONLY|O_DIRECTORY|O_CLOEXEC) = 3')
    copied = event("fcntl(3, F_DUPFD_CLOEXEC, 0) = 4")
    close4, close3 = event("close(4) = 0"), event("close(3) = 0")
    base = opened + mark("C") + allocated + copied + mark("c") + mark("A") + close4 + free + mark("a") + mark("B") + mark("b") + mark("X") + mark("x") + mark("P") + close3 + mark("p")
    bad_close = event("close(4) = -1 EIO (Input/output error) (INJECTED)")
    repaired = base.replace(close4, bad_close).replace(mark("B"), mark("Q") + close4 + mark("q") + mark("B"))
    count = 0
    with tempfile.TemporaryDirectory(prefix="temp_file_ledger_cpu_") as directory:
        assert len(analyze(base, ([(a, f)], []), directory)["source"]["allocations"]) == 1
        count += 1
        assert analyze(repaired, ([(a, f)], []), directory, repaired_close=1)["closes"][1]["phase"] == "Q"
        count += 1
        explicit = repaired.replace(mark("A") + bad_close + free + mark("a"),
                                    mark("F") + bad_close + mark("f") + mark("A") + free + mark("a"))
        assert analyze(explicit, ([(a, f)], []), directory, repaired_close=1, repair_phase="F")["closes"][0]["phase"] == "F"
        count += 1
        try:
            analyze(explicit, ([(a, f)], []), directory, repaired_close=1, repair_phase="A")
        except AssertionError:
            count += 1
        else:
            raise AssertionError("temporary-file ledger accepted the wrong declared close phase")
        mutations = [base.replace(free, ""), base + free, base.replace(", 37) = 0", ", 36) = 0"),
                     base.replace(close4, ""), base + close4, base.replace(copied, ""),
                     base.replace(mark("b"), close4 + mark("b")),
                     base.replace(mark("X"), mark("K") + close3 + mark("k") + mark("X")),
                     base.replace(allocated, allocated.replace(f"{a:016x}", "00007fff00001000")),
                     base.rstrip("\n")]
        for text in mutations:
            try:
                analyze(text, ([(a, f)], []), directory)
            except AssertionError:
                count += 1
            else:
                raise AssertionError("temporary-file ledger accepted an ownership mutation")
        for text in (base.replace(close4, bad_close), repaired.replace(mark("Q"), mark("A")).replace(mark("q"), mark("a")), repaired.replace("EIO", "EBADF")):
            try:
                analyze(text, ([(a, f)], []), directory, repaired_close=1)
            except AssertionError:
                count += 1
            else:
                raise AssertionError("temporary-file ledger accepted an unretired close fault")
    return count


if __name__ == "__main__":
    print("temp-file ledger CPU-controls=%d native-cases=0" % controls())
