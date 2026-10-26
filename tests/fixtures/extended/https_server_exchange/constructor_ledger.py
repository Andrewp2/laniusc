"""Exact source constructor allocations and native-created descriptor owners."""
from pathlib import Path
import re

from ledger import SHARED


def parse(text, pairs, named, connection_fd, allocation_fault=None):
    allocations = {a for a, _ in pairs} | set(named)
    releases = {f for _, f in pairs} | set(named)
    live, fds, frames, counters = {}, {}, [], {}
    events, source, targeted, marked = [], [], [], []
    begin_count, steps, waits, reports, owner_closes = 0, 0, 0, 0, []
    for line in text.splitlines():
        if not line or line.startswith(("+++", "---")):
            continue
        match = SHARED.PATTERN.fullmatch(line)
        assert match, ("unknown constructor trace line", line)
        address, name, args, result = match.groups()
        ip = int(address, 16)
        counters[name] = counters.get(name, 0) + 1
        event = dict(ip=ip, name=name, args=args, result=result,
                     ordinal=counters[name], frames=tuple(frames), line=line)
        events.append(event)
        if "INJECTED" in result:
            marked.append(event)
            assert name == "mmap" and counters[name] == allocation_fault and result.startswith("-1 ENOMEM "), event
        marker = re.fullmatch(r'2, "([CcBbSsWwAaXx])", 1', args) if name == "write" and result == "1" else None
        if marker:
            value = marker[1]
            if value.isupper():
                assert not frames, ("nested fixture frame", line, frames)
                frames.append(value)
                begin_count += value == "B"
            else:
                assert frames and frames.pop() == value.upper(), line
                steps += value == "s"
                waits += value == "w"
        assert name != "poll", ("constructor/quota cases must not poll", line)
        value = result.split()[0]
        if name == "mmap" and "MAP_32BIT" in args:
            assert ip in allocations and "PROT_READ|PROT_WRITE" in args, ("unverified source allocation", line)
            size = int(args.split(",", 2)[1])
            event["length"] = size
            source.append(event)
            if event["frames"] == ("B",):
                targeted.append(event)
            if value.startswith("0x"):
                pointer = int(value, 16)
                assert pointer < 0x80000000 and pointer not in live, line
                live[pointer] = size
            else:
                assert event in marked, ("unexpected source allocation failure", line)
        elif name == "munmap":
            pointer, size = args.split(",", 1)
            pointer, size = int(pointer, 16), int(size)
            if pointer in live:
                assert ip in releases and value == "0" and live.pop(pointer) == size, line
            elif pointer < 0x80000000:
                raise AssertionError(("unowned low source release", line))
        elif name in ("open", "openat", "socket", "accept", "accept4") and int(value) >= 0:
            fd = int(value)
            assert fd not in fds, (line, fds)
            if name in ("accept", "accept4"):
                assert fds.get(int(args.split(",", 1)[0])) == "socket" and fd == connection_fd, (line, fds)
                fds[fd] = "accepted"
            else:
                fds[fd] = name
        elif name == "close":
            fd = int(args)
            assert fd in fds and value == "0", ("unknown/failed close", line, fds)
            if fds.pop(fd) == "accepted":
                owner_closes.append(event)
        if name == "write" and args.startswith("1, ") and args.endswith(", 128") and result == "128":
            # The child is still blocked on its final stdin ACK here. Source
            # or descriptor cleanup at process exit cannot satisfy this gate.
            reports += 1
            assert not live and not fds and not frames, ("report before cleanup", line, live, fds, frames)
    assert not live and not fds and not frames and begin_count == reports == 1 and len(owner_closes) == 1, (live, fds, frames, begin_count, reports, owner_closes)
    assert len(marked) == (0 if allocation_fault is None else 1), marked
    if allocation_fault is not None:
        assert marked[0] in targeted, ("injected allocation was not reached inside constructor", marked, targeted)
    return dict(events=events, source=source, targeted=targeted, steps=steps,
                waits=waits, close=owner_closes[0], injected=marked)


def analyze(executable, path, connection_fd, allocation_fault=None):
    pairs, named = SHARED.verified_sites(str(executable))
    return parse(Path(path).read_text(), pairs, named, connection_fd, allocation_fault)


def controls():
    a, f, native = 0x401002, 0x401012, 0x7fff00001000
    def event(value, ip=a):
        return f"[{ip:016x}] {value}\n"
    def marker(value):
        return event(f'write(2, "{value}", 1) = 1')
    start = marker("C") + event("socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_TCP) = 6") + event("accept4(6, NULL, NULL, SOCK_NONBLOCK) = 7") + event("close(6) = 0") + marker("c") + marker("B")
    alloc = event("mmap(NULL, 97, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x40001000")
    free = event("munmap(0x40001000, 97) = 0", f)
    report = event('write(1, "receipt", 128) = 128')
    end = event("close(7) = 0") + marker("b") + report
    assert len(parse(start + alloc + free + end, [(a, f)], {}, 7)["targeted"]) == 1
    failed = event("mmap(NULL, 97, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = -1 ENOMEM (Cannot allocate memory) (INJECTED)")
    assert len(parse(start + failed + end, [(a, f)], {}, 7, 1)["injected"]) == 1
    high = event("mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000", native) + event("munmap(0x7fff10000000, 8192) = 0", native)
    assert parse(start + high + end, [(a, f)], {}, 7)["targeted"] == []
    mutants = [start + alloc + end, start + free + end,
               start + alloc + free + free + end,
               start + alloc + free.replace(", 97)", ", 16)") + end,
               start + alloc.replace(f"{a:016x}", f"{native:016x}") + free + end,
               start + event("poll([], 0, 1) = 0 (Timeout)") + end,
               start + failed.replace("ENOMEM", "EIO") + end,
               start + failed.replace("(INJECTED)", "") + end,
               start + end.replace("close(7)", "close(8)"),
               start + end + event("close(7) = 0"),
               start + alloc + end + free,
               start + marker("b") + report + event("close(7) = 0"),
               start + end.replace(report, ""), start + end + report]
    for text in mutants:
        try:
            parse(text, [(a, f)], {}, 7, 1 if "INJECTED" in text else None)
        except AssertionError:
            continue
        raise AssertionError(("constructor ledger accepted mutant", text))
    return 3 + len(mutants)


if __name__ == "__main__":
    print(f"https-server-exchange constructor ledger CPU controls={controls()}")
