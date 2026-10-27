"""Direct teardown owners, explicit waits and a pre-ACK source/FD barrier."""
from pathlib import Path
import re

from constructor_ledger import controls as constructor_controls
from ledger import SHARED


def parse(text, pairs, named, connection_fd):
    allocations = {a for a, _ in pairs} | set(named)
    releases = {f for _, f in pairs} | set(named)
    live, fds, frames = {}, {}, []
    steps, waits, polls, reports, constructors = 0, 0, 0, 0, 0
    closes = []
    for line in text.splitlines():
        if not line or line.startswith(("+++", "---")):
            continue
        match = SHARED.PATTERN.fullmatch(line)
        assert match, ("unknown teardown trace line", line)
        address, name, args, result = match.groups()
        ip = int(address, 16)
        assert "INJECTED" not in result, ("teardown uses real peer behavior", line)
        marker = re.fullmatch(r'2, "([CcSsWwPpRrXx])", 1', args) if name == "write" and result == "1" else None
        if marker:
            value = marker[1]
            if value.isupper():
                assert not frames, ("unexpected nested frame", frames, line)
                frames.append(value)
                constructors += value == "C"
            else:
                assert frames and frames.pop() == value.upper(), line
                steps += value == "s"
                waits += value == "w"
        elif name == "poll":
            assert frames == ["P"], ("hidden poll", frames, line)
            polls += 1
        value = result.split()[0]
        if name == "mmap" and "MAP_32BIT" in args:
            assert ip in allocations and "PROT_READ|PROT_WRITE" in args and value.startswith("0x"), ("unverified source allocation", line)
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
                assert fds.get(int(args.split(",", 1)[0])) == "socket" and fd == connection_fd, (line, fds)
                fds[fd] = "accepted"
            else:
                fds[fd] = name
        elif name == "close":
            fd = int(args)
            assert fd in fds and value == "0", ("unowned or failed close", line, fds)
            if fds.pop(fd) == "accepted":
                assert frames in (["S"], ["W"]), ("accepted fd closed outside progress", line, frames)
                closes.append(tuple(frames))
        if name == "write" and args.startswith("1, ") and args.endswith(", 256") and result == "256":
            reports += 1
            assert not live and not fds and not frames, ("report before cleanup", live, fds, frames, line)
    # One final terminal before_wait replay has no physical poll. A timeout
    # first reached in before_wait adds one more unsuccessful reservation.
    assert waits - polls in (1, 2), (waits, polls)
    assert constructors == reports == len(closes) == 1 and steps > 0 and not live and not fds and not frames, (constructors, reports, closes, steps, live, fds, frames)
    return dict(steps=steps, waits=waits, polls=polls, close=closes[0])


def analyze(executable, path, connection_fd):
    pairs, named = SHARED.verified_sites(str(executable))
    return parse(Path(path).read_text(), pairs, named, connection_fd)


def controls():
    assert constructor_controls() == 17
    a, f, native = 0x401002, 0x401012, 0x7fff00001000
    def event(value, ip=a):
        return f"[{ip:016x}] {value}\n"
    def marker(value):
        return event(f'write(2, "{value}", 1) = 1')
    setup = marker("C") + event("socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_TCP) = 6") + event("accept4(6, NULL, NULL, SOCK_NONBLOCK) = 7") + event("close(6) = 0") + marker("c")
    alloc = event("mmap(NULL, 97, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x40001000")
    free = event("munmap(0x40001000, 97) = 0", f)
    poll = marker("W") + marker("w") + marker("P") + event("poll([], 0, 25) = 0 (Timeout)") + marker("p")
    close = marker("S") + event("close(7) = 0") + marker("s")
    replay = marker("S") + marker("s") + marker("W") + marker("w")
    report = event('write(1, "receipt", 256) = 256')
    text = setup + marker("S") + alloc + marker("s") + poll + close + replay + marker("X") + free + marker("x") + report
    assert parse(text, [(a, f)], {}, 7) == dict(steps=3, waits=2, polls=1, close=("S",))
    high = event("mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000", native) + event("munmap(0x7fff10000000, 8192) = 0", native)
    assert parse(high + text, [(a, f)], {}, 7)["steps"] == 3
    mutants = [text.replace(free, ""), text + free,
               text.replace(free, free.replace(", 97)", ", 16)")),
               text.replace(alloc, alloc.replace(f"{a:016x}", f"{native:016x}")),
               text.replace(free, free.replace(f"{f:016x}", f"{native:016x}")),
               text.replace(close, ""), text + close,
               text.replace(poll, event("poll([], 0, 25) = 0 (Timeout)")),
               text.replace(free, "") + free,
               text.replace(report, ""), text + report,
               text.replace("close(7) = 0", "close(7) = -1 EIO (Input/output error) (INJECTED)")]
    for mutant in mutants:
        try:
            parse(mutant, [(a, f)], {}, 7)
        except AssertionError:
            continue
        raise AssertionError(("teardown ledger accepted mutant", mutant))
    return 17 + 2 + len(mutants)


if __name__ == "__main__":
    print(f"https-server-exchange teardown ledger CPU controls={controls()}")
