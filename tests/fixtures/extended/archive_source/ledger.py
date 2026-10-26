"""Live archive-owner checkpoints around the existing verified ELF ledger.

The ELF opcode verifier and final source-map ledger are reused unchanged. This
small extension accepts a *prefix* and returns live requested mappings, without
treating process exit or rounded kernel pages as owner release.
"""
import importlib.util
from pathlib import Path
import re


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TRUSTED = load("archive_source_trusted_ledger",
               Path(__file__).resolve().parents[2] / "stdlib_execution/temp_file/ledger.py")
TRACE = TRUSTED.TRACE


class CheckpointPending(AssertionError):
    pass


def completed(text):
    """A blocked single-threaded syscall can leave only the last line partial."""
    lines = text.splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines.pop()
    return "".join(lines)


def output_prefix(text, expected):
    """Locate a frame by actual successful stdout bytes, across short writes."""
    output = bytearray()
    prefix = []
    for line in completed(text).splitlines(keepends=True):
        match = TRUSTED.LINE.fullmatch(line.rstrip("\n"))
        assert match, ("unsupported checkpoint trace", line)
        prefix.append(line)
        _, name, args, result = match.groups()
        if name == "write":
            args = TRUSTED.arguments(args)
            if args[0] == "1" and result.split()[0].isdecimal():
                count = int(result.split()[0])
                data = TRUSTED.quoted(args[1])
                assert count <= len(data) and count <= int(args[2]), line
                output.extend(data[:count])
                assert expected.startswith(output), ("stdout/trace disagreement", len(output), len(expected))
                if output == expected:
                    return "".join(prefix)
    raise CheckpointPending(("checkpoint stdout missing from trace", len(output), len(expected)))


def source(text, profile):
    pairs, named = profile
    alloc = {a for a, _ in pairs} | set(named)
    free = {f for _, f in pairs} | set(named)
    flags = getattr(pairs, "mmap_flags", {a: 0x62 for a, _ in pairs})
    ranges = getattr(pairs, "executable_ranges", [])
    live, attempts, peak = {}, [], 0
    entries = TRUSTED.events(text)[0]
    for item in entries:
        name, ip = item["name"], item["ip"]
        args = TRUSTED.arguments(item["args"])
        result = item["result"].split()[0]
        in_image = any(start <= ip < end for start, end in ranges)
        if name == "mmap" and ip in alloc:
            wanted = {"MAP_PRIVATE", "MAP_ANONYMOUS"}
            assert flags[ip] in (0x22, 0x62), ("unverified mmap flags", item)
            if flags[ip] == 0x62:
                wanted.add("MAP_32BIT")
            assert len(args) == 6 and args[0] == "NULL" and int(args[1]) > 0, item
            assert args[2] == "PROT_READ|PROT_WRITE" and set(args[3].split("|")) == wanted, item
            assert args[4:] == ["-1", "0"], item
            attempt = dict(item, length=int(args[1]))
            attempts.append(attempt)
            if result.startswith("0x"):
                pointer = int(result, 16)
                assert 0 < pointer < (1 << 64) and pointer not in live, item
                assert pointer + attempt["length"] < (1 << 64), item
                assert flags[ip] != 0x62 or pointer < 0x80000000, item
                live[pointer] = attempt["length"]
                peak = max(peak, sum(live.values()))
            else:
                assert result == "-1", item
        elif name == "mmap":
            assert not in_image and "MAP_32BIT" not in item["args"], ("unknown source map", item)
        elif name == "munmap":
            pointer, length = int(args[0], 16), int(args[1])
            if pointer in live:
                assert ip in free and result == "0" and live[pointer] == length, item
                del live[pointer]
            else:
                assert ip not in free and not in_image and pointer >= 0x80000000, ("unknown source release", item)
    return dict(live=live, attempts=attempts, peak=peak, events=entries)


def process_owners(pid, live):
    assert {int(path.name) for path in Path(f"/proc/{pid}/fd").iterdir()} == {0, 1, 2}, "unexpected archive host fd"
    ranges = []
    for line in Path(f"/proc/{pid}/maps").read_text().splitlines():
        start, end = line.split()[0].split("-")
        ranges.append((int(start, 16), int(end, 16)))
    for pointer, count in live.items():
        assert any(start <= pointer and pointer + count <= end for start, end in ranges), (pointer, count, ranges)
    return ranges


def no_host_effects(entries):
    allowed = {"mmap", "munmap", "read", "write", "getpid"}
    assert all(item["name"] in allowed for item in entries), ("archive planning performed host work", entries)


def controls():
    """Finite mutations of the new live/prefix logic, with both mmap profiles."""
    a, f = 0x401002, 0x401012
    def line(body, ip=a):
        return f"[{ip:016x}] {body}\n"
    class Pairs(list):
        pass
    count = 0
    for full in (False, True):
        pairs = Pairs([(a, f)])
        pairs.mmap_flags = {a: 0x22 if full else 0x62}
        pairs.executable_ranges = [(0x400000, 0x402000)]
        flags = "MAP_PRIVATE|MAP_ANONYMOUS" + ("" if full else "|MAP_32BIT")
        pointer = "0x7fff10000000" if full else "0x41000000"
        allocated = line(f"mmap(NULL, 37, PROT_READ|PROT_WRITE, {flags}, -1, 0) = {pointer}")
        released = line(f"munmap({pointer}, 37) = 0", f)
        assert source(allocated, (pairs, []))["live"] == {int(pointer, 16): 37}
        assert source(allocated + released, (pairs, []))["live"] == {}
        count += 2
        for bad in (allocated + released + released,
                    allocated + released.replace(", 37)", ", 36)"),
                    allocated.replace(f"{a:016x}", "0000000000401003"),
                    allocated + released.replace(" = 0", " = -1 EINVAL (Invalid argument)"),
                    allocated + allocated):
            try:
                source(bad, (pairs, []))
            except AssertionError:
                count += 1
            else:
                raise AssertionError("live source ledger accepted an ownership mutation")
    text = line('write(1, "\\x61\\x62", 2) = 1') + line('write(1, "\\x62", 1) = 1')
    assert output_prefix(text + "[0000000000401002] read(", b"ab") == text
    count += 1
    for bad in (b"aa", b"abc"):
        try:
            output_prefix(text, bad)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("checkpoint ledger accepted changed/missing stdout")
    print(f"PASS archive-source ledger CPU controls={count}")
    return count


if __name__ == "__main__":
    controls()
