"""Exact source/native/inherited descriptor ownership for this native test."""
import importlib.util
from pathlib import Path
import re

PATH = Path(__file__).resolve().parents[1] / "https_batch" / "resources.py"
SPEC = importlib.util.spec_from_file_location("server_exchange_resource_sites", PATH)
SHARED = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHARED)


def analyze(executable, path, inherited_fd):
    pairs, named = SHARED.verified_sites(str(executable))
    return parse(Path(path).read_text(), pairs, named, inherited_fd)


def parse(text, pairs, named, inherited_fd):
    allocations = {a for a, _ in pairs} | set(named)
    releases = {f for _, f in pairs} | set(named)
    live, fds, frames, counters = {}, {inherited_fd: "inherited-tcp"}, [], {}
    attempts, steps, waits, polls = [], 0, 0, 0
    for line in text.splitlines():
        if not line or line.startswith(("+++", "---")):
            continue
        match = SHARED.PATTERN.fullmatch(line)
        assert match, ("unknown native trace line", line)
        address, name, args, result = match.groups()
        ip = int(address, 16)
        counters[name] = counters.get(name, 0) + 1
        event = dict(ip=ip, name=name, args=args, result=result, ordinal=counters[name], line=line)
        attempts.append(event)
        marker = re.fullmatch(r'2, "([CcSsWwPpHhRrXxB])", 1', args) if name == "write" and result == "1" else None
        if marker:
            value = marker[1]
            if value == "B":
                assert not frames, line
            elif value.isupper():
                frames.append(value)
            else:
                assert frames and frames.pop() == value.upper(), line
                steps += value == "s"
                waits += value == "w"
        elif name == "poll":
            assert frames == ["P"], ("internal or unmarked poll", frames, line)
            polls += 1
        value = result.split()[0]
        if name == "mmap" and "MAP_32BIT" in args:
            assert ip in allocations, ("unverified source allocation", line)
            size = int(args.split(",", 2)[1])
            if value.startswith("0x"):
                pointer = int(value, 16)
                assert pointer < 0x80000000 and pointer not in live, line
                live[pointer] = size
            else:
                assert result.startswith("-1 ENOMEM "), line
        elif name == "munmap":
            pointer, size = args.split(",", 1)
            pointer, size = int(pointer, 16), int(size)
            if pointer in live:
                assert ip in releases and value == "0" and live.pop(pointer) == size, line
            elif pointer < 0x80000000:
                raise AssertionError(("unowned low mapping release", line))
        elif name in ("openat", "open", "socket") and int(value) >= 0:
            fd = int(value)
            assert fd not in fds, ("descriptor owner collision", line, fds)
            fds[fd] = "native-file" if name != "socket" else "source-socket"
        elif name == "close":
            fd = int(args)
            assert fd in fds and value == "0", ("unowned or failed close", line, fds)
            del fds[fd]
    assert not live and not fds and not frames and steps > 0, (live, fds, frames, steps)
    assert polls == waits and waits > 0, (polls, waits)
    return dict(steps=steps, waits=waits, polls=polls, attempts=attempts)


def controls():
    a, f, native = 0x401002, 0x401012, 0x7fff12340000
    def event(ip, value):
        return f"[{ip:016x}] {value}\n"
    def mark(value):
        return event(a, f'write(2, "{value}", 1) = 1')
    allocate = event(a, "mmap(NULL, 32, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x40001000")
    release = event(f, "munmap(0x40001000, 32) = 0")
    close = event(a, "close(7) = 0")
    poll = event(a, "poll([{fd=7, events=POLLIN}], 1, 25) = 0 (Timeout)")
    before = allocate + mark("S")
    after = mark("s") + mark("W") + mark("w") + mark("P") + poll + mark("p") + release + close
    valid = before + after
    assert parse(valid, [(a, f)], {}, 7)["steps"] == 1
    high = event(native, "mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff20000000") + event(native, "munmap(0x7fff20000000, 8192) = 0")
    assert parse(high + valid, [(a, f)], {}, 7)["waits"] == 1
    mutations = [before + poll + after, valid.replace(close, ""), valid + close,
                 valid.replace(allocate, allocate.replace(f"{a:016x}", f"{native:016x}")),
                 valid.replace(release, release.replace(", 32)", ", 16)")),
                 valid.replace(allocate, ""), valid.replace(mark("s"), "")]
    for mutation in mutations:
        try:
            parse(mutation, [(a, f)], {}, 7)
        except AssertionError:
            continue
        raise AssertionError(("accepted ownership/step mutant", mutation))
    return 2 + len(mutations)


if __name__ == "__main__":
    print(f"https-server-exchange ledger CPU controls={controls()}")
