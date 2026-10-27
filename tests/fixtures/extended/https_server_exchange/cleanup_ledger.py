"""Native-created socket owners; a skipped close stays live until explicit repair."""
from pathlib import Path
import re

from ledger import SHARED


def parse(text, pairs, named, connection_fd, close_fault=None):
    allocations = {a for a, _ in pairs} | set(named)
    releases = {f for _, f in pairs} | set(named)
    live, fds, frames, counters = {}, {}, [], {}
    events, marked, steps, polls, waits = [], [], 0, 0, 0
    for line in text.splitlines():
        if not line or line.startswith(("+++", "---")):
            continue
        match = SHARED.PATTERN.fullmatch(line)
        assert match, line
        address, name, args, result = match.groups()
        ip = int(address, 16)
        counters[name] = counters.get(name, 0) + 1
        event = dict(ip=ip, name=name, args=args, result=result, ordinal=counters[name], frames=tuple(frames))
        events.append(event)
        if "INJECTED" in result:
            marked.append(event)
            assert name == "close" and counters[name] == close_fault and re.match(r"^-1 EIO\s", result), event
        marker = re.fullmatch(r'2, "([CcSsWwPpRrAaKkXx])", 1', args) if name == "write" and result == "1" else None
        if marker:
            value = marker[1]
            if value.isupper():
                frames.append(value)
            else:
                assert frames and frames.pop() == value.upper(), line
                steps += value == "s"
                waits += value == "w"
        elif name == "poll":
            assert frames == ["P"], ("hidden poll", frames, line)
            polls += 1
        value = result.split()[0]
        if name == "mmap" and "MAP_32BIT" in args:
            assert ip in allocations and value.startswith("0x"), line
            pointer, size = int(value, 16), int(args.split(",", 2)[1])
            assert pointer < 0x80000000 and pointer not in live, line
            live[pointer] = size
        elif name == "munmap":
            pointer, size = args.split(",", 1)
            pointer, size = int(pointer, 16), int(size)
            if pointer in live:
                assert ip in releases and value == "0" and live.pop(pointer) == size, line
            elif pointer < 0x80000000:
                raise AssertionError(("unowned source release", line))
        elif name in ("open", "openat", "socket", "accept", "accept4") and int(value) >= 0:
            fd = int(value)
            assert fd not in fds, (line, fds)
            if name in ("accept", "accept4"):
                listener = int(args.split(",", 1)[0])
                assert fds.get(listener) == "socket" and fd == connection_fd, (line, fds)
                fds[fd] = "accepted"
            else:
                fds[fd] = name
        elif name == "close":
            fd = int(args)
            assert fd in fds, (line, fds)
            event["connection_owner"] = fds[fd] == "accepted"
            if value == "0":
                del fds[fd]
            else:
                assert fd == connection_fd and event["connection_owner"] and counters[name] == close_fault and event in marked, line
    assert not live and not fds and not frames and steps > 0 and polls == waits and waits > 0, (live, fds, frames, steps, polls, waits)
    assert len(marked) == (0 if close_fault is None else 1), marked
    owned_closes = [e for e in events if e["name"] == "close" and e.get("connection_owner")]
    assert len(owned_closes) == (1 if close_fault is None else 2), owned_closes
    if close_fault is not None:
        assert owned_closes[0] == marked[0] and owned_closes[1]["result"] == "0" and owned_closes[1]["frames"] == ("K",), owned_closes
    return dict(events=events, steps=steps, close=owned_closes[0])


def analyze(executable, path, fd, close_fault=None):
    pairs, named = SHARED.verified_sites(str(executable))
    return parse(Path(path).read_text(), pairs, named, fd, close_fault)


def controls():
    a, f = 0x401002, 0x401012
    def event(value, ip=a):
        return f"[{ip:016x}] {value}\n"
    def marker(value):
        return event(f'write(2, "{value}", 1) = 1')
    start = event("socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_TCP) = 6") + event("accept4(6, NULL, NULL, SOCK_NONBLOCK) = 7") + event("close(6) = 0") + marker("S") + marker("s") + marker("W") + marker("w") + marker("P") + event("poll([], 0, 25) = 0 (Timeout)") + marker("p")
    failed = event("close(7) = -1 EIO (Input/output error) (INJECTED)")
    repair = marker("K") + event("close(7) = 0", f) + marker("k")
    assert parse(start + event("close(7) = 0"), [(a, f)], {}, 7)["steps"] == 1
    assert parse(start + marker("A") + failed + marker("a") + repair, [(a, f)], {}, 7, 2)["close"]["ordinal"] == 2
    mutants = [start + failed, start + failed + repair + repair,
               start + failed.replace("EIO", "EBADF") + repair,
               start + failed.replace("(INJECTED)", "") + repair,
               start + failed.replace("close(7)", "close(8)") + repair]
    for text in mutants:
        try:
            parse(text, [(a, f)], {}, 7, 2)
        except AssertionError:
            continue
        raise AssertionError(("cleanup ledger accepted mutation", text))
    return 2 + len(mutants)


if __name__ == "__main__":
    print(f"https-server-exchange cleanup ledger CPU controls={controls()}")
