"""Adoption epochs/fd generations; reuse the existing raw ELF/source verifier."""
from collections import Counter
import importlib.util
from pathlib import Path
import re


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
SOURCE = load("url_adoption_live_source", HERE.parent / "archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
CALLS = {"mmap", "munmap", "socket", "connect", "poll", "getsockopt", "getpeername", "fcntl", "close",
         "clock_gettime", "sendto", "recvfrom", "shutdown", "read", "write", "rt_sigaction"}
PHASES = "PpCcAaRrDdTtKk"


def body(text, profile, executable, final=False):
    """Only a verified launch and final successful raw exit may disappear."""
    assert text.endswith("\n"), "partial trace body"
    lines = text.splitlines(keepends=True)
    launch = TRUSTED.LINE.fullmatch(lines.pop(0).rstrip("\n"))
    assert launch and launch[2] == "execve" and launch[4] == "0", launch
    path = re.match(r'("(?:\\x[0-9a-f]{2})*"), \[', launch[3])
    assert path and TRUSTED.quoted(path[1]) == bytes(Path(executable).resolve()), launch
    ranges = profile[0].executable_ranges
    assert ranges and not any(low <= int(launch[1], 16) < high for low, high in ranges), launch
    if final:
        terminal = TRUSTED.LINE.fullmatch(lines.pop().rstrip("\n"))
        assert terminal and terminal[2] in ("exit", "exit_group") and (terminal[3], terminal[4]) == ("0", "?"), terminal
        assert any(low <= int(terminal[1], 16) < high for low, high in ranges), terminal
    return "".join(lines)


def prefix_signature(entries):
    """Bind the causal call/phase/site prefix without ASLR or clock samples."""
    result = []
    for item in entries:
        name = item["name"]
        if name in ("read", "write", "clock_gettime"):
            continue
        fields = ()
        if name == "mmap":
            args = TRUSTED.arguments(item["args"])
            fields = (int(args[1]), args[2], args[3])
        elif name == "munmap":
            fields = (int(item["args"].rsplit(",", 1)[1]),)
        elif name == "socket":
            fields = (item["args"],)
        elif name in ("fcntl", "connect", "getpeername", "getsockopt", "close", "poll"):
            fields = (item.get("fd"), item.get("generation"))
        result.append((name, item["ip"], item["phase"], fields))
    return result


def analyze(text, profile, executable, *, final=False, target=None):
    text = body(text, profile, executable, final)
    counts, generations = Counter(), Counter()
    entries, epochs, frames, live, retired, closes, sockets = [], [], [], {}, set(), [], []
    for line in text.splitlines():
        match = TRUSTED.LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unexpected syscall", line)
        ip, name, args, result = match.groups()
        ip = int(ip, 16)
        assert any(low <= ip < high for low, high in profile[0].executable_ranges), ("call outside raw image", line)
        counts[name] += 1
        item = dict(ip=ip, name=name, args=args, result=result, ordinal=counts[name],
                    index=len(entries), phase=frames[-1] if frames else None, line=line)
        entries.append(item)
        marker = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args) if name == "write" and result == "1" else None
        if marker:
            token = chr(int(marker[1], 16))
            assert token in PHASES, item
            if token.isupper():
                assert not frames, ("nested public operation", item, frames)
                frames.append(token)
                item["phase"] = token
                epochs.append(dict(phase=token, events=[]))
            else:
                assert frames == [token.upper()], (item, frames)
                frames.pop()
            item["marker"] = token
            continue
        if frames:
            epochs[-1]["events"].append(item)
        value, phase = result.split()[0], item["phase"]
        if name == "socket":
            assert phase == "C" and value.isdecimal(), item
            fd = int(value)
            assert fd not in live, (item, live)
            generations[fd] += 1
            live[fd] = generations[fd]
            item.update(fd=fd, generation=generations[fd])
            sockets.append(item)
        elif name in ("connect", "getpeername", "getsockopt", "fcntl", "close", "sendto", "recvfrom", "shutdown"):
            fd = int(args.split(",", 1)[0])
            assert fd in live, ("unowned or reused network descriptor", item, live)
            item.update(fd=fd, generation=live[fd])
            key = fd, live[fd]
            if key in retired:
                assert phase == "K" and name == "close" and value == "0", ("used logically retired fd", item)
            if name == "connect":
                assert phase == "C", ("adoption/exchange reconnected", item)
            elif name == "fcntl":
                assert phase in ("A", "C") and "F_DUPFD" not in args, ("socket duplicated or hidden flags query", item)
            elif name in ("getpeername", "getsockopt"):
                assert phase in ("A", "C"), item
            elif name in ("sendto", "recvfrom", "shutdown"):
                assert phase == "R", ("adoption sent/received", item)
            else:
                assert phase in ("C", "A", "R", "K"), item
                closes.append(item)
                if value == "0":
                    live.pop(fd)
                else:
                    assert target and phase == "A" and "INJECTED" in result and result.split()[:2] == ["-1", "EIO"], item
                    assert (item["ip"], item["ordinal"], fd, live[fd]) == (target["ip"], target["ordinal"], target["fd"], target["generation"]), ("wrong close reached", item, target)
                    assert prefix_signature(entries[:-1]) == target["prefix"], "changed causal prefix before close injection"
                    retired.add(key)
        elif name == "poll":
            assert phase in ("C", "R"), ("hidden adoption poll", item)
            found = re.findall(r"fd=(\d+)", args)
            assert len(found) == 1 and int(found[0]) in live, ("poll not on selected socket", item, live)
            item.update(fd=int(found[0]), generation=live[int(found[0])])
        elif name in ("read", "write"):
            fd = int(args.split(",", 1)[0])
            assert fd == (0 if name == "read" else 1), ("nonprotocol ordinary I/O", item)
        if "INJECTED" in result or "POKED" in result:
            assert name == "close" and target and phase == "A", item
    assert not frames, ("unclosed phase at checkpoint", frames)
    assert len(sockets) == 1, ("socket selection replaced", sockets)
    for epoch in epochs:
        if epoch["phase"] == "T":
            assert not epoch["events"], ("terminal replay performed work", epoch)
        if epoch["phase"] == "A":
            assert all(item["name"] in ("clock_gettime", "fcntl", "getpeername", "close", "mmap", "munmap")
                       for item in epoch["events"]), ("adoption performed unrelated work", epoch)
    maps = "".join(item["line"] + "\n" for item in entries if item["name"] in ("mmap", "munmap"))
    source = SOURCE.source(maps, profile)
    if final:
        assert not live and not source["live"], ("resources retained after explicit release", live, source["live"])
        marked = [item for item in entries if "INJECTED" in item["result"]]
        assert len(marked) == int(target is not None), marked
    return dict(entries=entries, epochs=epochs, source=source, live=live, retired=retired,
                closes=closes, sockets=sockets, counts=counts)


def close_target(result):
    matches = [item for item in result["closes"] if item["phase"] == "A"]
    assert len(matches) == 1 and matches[0]["result"] == "0", matches
    item = matches[0]
    return dict(item, prefix=prefix_signature(result["entries"][:item["index"]]))


def controls():
    """Causal FD checks use synthetic traces, not a copied allocation verifier."""
    class Pairs(list):
        executable_ranges = [(0x400000, 0x402000)]
        mmap_flags = {}
    profile = Pairs(), []
    executable = Path("/tmp/url-adoption-control")
    encoded = "".join("\\x%02x" % byte for byte in bytes(executable))
    launch = '[00007fff00001000] execve("%s", [], NULL) = 0\n' % encoded
    def call(value, ip=0x401002):
        return "[%016x] %s\n" % (ip, value)
    def mark(token):
        return call('write(2, "\\x%02x", 1) = 1' % ord(token))
    opened = call("socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK|SOCK_CLOEXEC, IPPROTO_IP) = 3")
    closed = call("close(3) = 0")
    base = launch + mark("C") + opened + mark("c") + mark("A") + closed + mark("a") + mark("T") + mark("t")
    result = analyze(base, profile, executable)
    target = close_target(result)
    fault = base.replace(closed, call("close(3) = -1 EIO (Input/output error) (INJECTED)"))
    assert analyze(fault, profile, executable, target=target)["live"] == {3: 1}
    repaired = fault + mark("K") + closed + mark("k")
    assert not analyze(repaired, profile, executable, target=target)["live"]
    count = 3
    for mutant in (base.replace(mark("A"), mark("A") + opened),
                   base.replace(closed, call("close(4) = 0")),
                   base.replace(closed, closed + closed),
                   base.replace(closed, call("connect(3, NULL, 0) = 0") + closed),
                   base.replace(closed, call("sendto(3, NULL, 1, 0, NULL, 0) = 1") + closed),
                   base.replace(mark("T") + mark("t"), mark("T") + call("clock_gettime(CLOCK_MONOTONIC, {}) = 0") + mark("t")),
                   repaired.replace(mark("K"), mark("R")).replace(mark("k"), mark("r")),
                   fault.replace("[0000000000401002] close", "[0000000000401003] close")):
        try:
            analyze(mutant, profile, executable, target=target if "INJECTED" in mutant else None)
        except AssertionError:
            count += 1
        else:
            raise AssertionError(("adoption FD control admitted mutation", mutant))
    return count


if __name__ == "__main__":
    print("url-adoption ledger CPU controls=%d" % controls())
