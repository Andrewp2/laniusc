"""Thin regex-text composition of the existing verified full-width source ledger.

No runtime scanner or ownership ledger is copied here. Rust supplies actual
strace files; stdout is the reached source mmap ordinals, never an assumed
historical allocation count. Native execution stays in the Rust driver.
"""
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile


def load():
    path = Path(__file__).resolve().parent.parent / "archive_source/ledger.py"
    spec = importlib.util.spec_from_file_location("regex_text_verified_source_ledger", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


LEDGER = load()
PHASES = b"AaBbZzCcWwSsNnDdLlTtEe"


def mapping_events(text):
    """Keep all mapping events; diagnostic stderr is not a phase protocol."""
    assert not text or text.endswith("\n"), "incomplete strace output"
    output = []
    for line in text.splitlines():
        match = LEDGER.TRUSTED.LINE.fullmatch(line)
        assert match, ("unsupported trace line", line)
        if match[2] in ("mmap", "munmap"):
            output.append(line + "\n")
    return "".join(output)


def checked(text, profile, directory):
    maps = mapping_events(text)
    state = LEDGER.source(maps, profile)
    assert not state["live"], ("explicit source release missing", state["live"])
    LEDGER.TRUSTED.source_maps(maps, profile, directory)
    return state


def bind_failure(actual, baseline, ordinal):
    """Bind a reached OOM through its exact baseline request/site prefix."""
    old = baseline["attempts"]
    new = actual["attempts"]
    selected = [index for index, item in enumerate(old) if item["ordinal"] == ordinal]
    assert len(selected) == 1, ("injected ordinal is not a reached source allocation", ordinal)
    end = selected[0] + 1
    assert len(new) >= end, ("allocation injection not reached", ordinal, len(new))
    for before, after in zip(old[:end], new[:end]):
        assert (before["ip"], before["args"], before["ordinal"]) == (
            after["ip"], after["args"], after["ordinal"]), (before, after)
    injected = [item for item in actual["events"] if "INJECTED" in item["result"]]
    assert len(injected) == 1 and injected[0]["name"] == "mmap", injected
    item = injected[0]
    assert item["ordinal"] == ordinal and item["result"].split()[:2] == ["-1", "ENOMEM"], item
    assert "INJECTED" in new[end - 1]["result"], new[end - 1]


def verify(executable, trace, baseline=None, ordinal=None):
    directory = Path(tempfile.mkdtemp(prefix="regex-text-source-ledger-"))
    try:
        text = Path(trace).read_text()
        (directory / "actual.trace").write_text(text)
        profile = LEDGER.TRUSTED.verified_sites(executable, directory)
        assert not profile[1] and getattr(profile[0], "executable_ranges", []), "expected verified raw ELF"
        actual = checked(text, profile, directory)
        if baseline is not None:
            old = Path(baseline).read_text()
            (directory / "baseline.trace").write_text(old)
            bind_failure(actual, checked(old, profile, directory), ordinal)
        elif ordinal is not None:
            raise AssertionError("injection ordinal without baseline")
        ordinals = [item["ordinal"] for item in actual["attempts"]]
        shutil.rmtree(directory)
        return ordinals
    except BaseException:
        print(f"regex-text source ledger evidence={directory}", file=sys.stderr)
        raise


def phases(text):
    """Exact single-byte test markers; ordinary diagnostics are not accepted."""
    result, active, markers = {}, None, bytearray()
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        match = LEDGER.TRUSTED.LINE.fullmatch(line.rstrip("\n"))
        assert match, line
        args = LEDGER.TRUSTED.arguments(match[3])
        if match[2] == "write" and args[0] == "2":
            assert match[4] == "1" and args[2] == "1", line
            value = LEDGER.TRUSTED.quoted(args[1])
            assert len(value) == 1, line
            token = value.decode("ascii")
            markers.extend(value)
            assert PHASES.startswith(markers), ("unexpected lazy ownership marker", markers)
            if token.isupper():
                assert active is None and token not in result
                active = token
                result[token] = dict(begin=index, end=None, lines=[])
            else:
                assert active == token.upper(), (active, token)
                result[active]["end"] = index
                active = None
        elif active is not None:
            result[active]["lines"].append(line)
    assert active is None and markers == PHASES, ("unfinished lazy ownership phases", markers)
    return lines, result


def requests(body):
    output = []
    for line in body:
        match = LEDGER.TRUSTED.LINE.fullmatch(line.rstrip("\n"))
        if match[2] == "mmap":
            assert match[4].startswith("0x"), line
            output.append(int(LEDGER.TRUSTED.arguments(match[3])[1]))
    return output


def lazy(executable, trace):
    directory = Path(tempfile.mkdtemp(prefix="regex-text-lazy-ledger-"))
    try:
        text = Path(trace).read_text()
        (directory / "actual.trace").write_text(text)
        profile = LEDGER.TRUSTED.verified_sites(executable, directory)
        assert not profile[1] and getattr(profile[0], "executable_ranges", [])
        checked(text, profile, directory)
        lines, regions = phases(text)
        span, full = requests(regions["A"]["lines"]), requests(regions["B"]["lines"])
        assert span and len(span) == len(full) and sum(full) > sum(span), (span, full)
        for name in ("Z", "C", "W", "S"):
            assert mapping_events("".join(regions[name]["lines"])) == "", ("scratch before admission", name)
        assert requests(regions["N"]["lines"]) == span
        assert requests(regions["D"]["lines"]) == [], "split next allocated per delimiter"
        assert requests(regions["L"]["lines"]) == span, "literal replacement did not use one span workspace"
        assert requests(regions["T"]["lines"]) == full, "template replacement did not use one full-capture workspace"
        def live_at(index):
            return LEDGER.source(mapping_events("".join(lines[:index + 1])), profile)["live"]
        before = live_at(regions["N"]["begin"])
        after = live_at(regions["N"]["end"])
        assert all(after.get(pointer) == count for pointer, count in before.items())
        retained = {pointer: count for pointer, count in after.items() if pointer not in before}
        assert len(retained) == len(span) and sum(retained.values()) == sum(span), retained
        assert live_at(regions["D"]["end"]) == before, "split scratch survived terminal next/destroy"
        for name in ("A", "B", "L", "T"):
            assert live_at(regions[name]["begin"]) == live_at(regions[name]["end"]), ("phase owner leaked", name)
        shutil.rmtree(directory)
        print(f"PASS regex-text lazy workspace span-allocations={len(span)} span-bytes={sum(span)} "
              f"capture-allocations={len(full)} capture-bytes={sum(full)}")
    except BaseException:
        print(f"regex-text lazy ledger evidence={directory}", file=sys.stderr)
        raise


def controls():
    """Focused CPU checks of new selectors/prefix binding, not Lanius runs."""
    def line(value, ip=0x401002):
        return f"[{ip:016x}] {value}\n"
    def mark(value):
        return line(f'write(2, "\\x{value:02x}", 1) = 1')
    text = "".join(mark(value) for value in PHASES)
    assert len(phases(text)[1]) == len(PHASES) // 2
    count = 1
    for bad in (text[:-len(mark(PHASES[-1]))], text.replace(mark(ord("a")), mark(ord("b")), 1),
                text + mark(ord("A")) + mark(ord("a"))):
        try:
            phases(bad)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("lazy phase selector accepted an invalid owner interval")
    baseline = dict(attempts=[dict(ip=1, args="request1", ordinal=2), dict(ip=3, args="request2", ordinal=4)])
    injected = dict(name="mmap", ordinal=4, result="-1 ENOMEM (Cannot allocate memory) (INJECTED)")
    actual = dict(attempts=[dict(ip=1, args="request1", ordinal=2),
                           dict(ip=3, args="request2", ordinal=4, result=injected["result"])], events=[injected])
    bind_failure(actual, baseline, 4)
    count += 1
    import copy
    mutations = []
    for field, value in (("ip", 99), ("args", "other"), ("ordinal", 3)):
        changed = copy.deepcopy(actual)
        changed["attempts"][0][field] = value
        mutations.append(changed)
    changed = copy.deepcopy(actual);changed["events"] = [];mutations.append(changed)
    changed = copy.deepcopy(actual);changed["events"][0]["result"] = "-1 EIO (INJECTED)";mutations.append(changed)
    for bad in mutations:
        try:
            bind_failure(bad, baseline, 4)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("OOM selector accepted a changed/unreached baseline prefix")
    assert mapping_events(line('write(2, "\\x65", 1) = 1')) == ""
    count += 1
    print(f"PASS regex-text resource CPU controls={count}")


def main():
    if sys.argv[1:] == ["controls"]:
        controls()
        return
    if len(sys.argv) == 4 and sys.argv[1] == "lazy":
        lazy(*sys.argv[2:])
        return
    assert len(sys.argv) in (3, 5), "resources.py EXECUTABLE TRACE [BASELINE SOURCE_MMAP_ORDINAL]"
    executable, trace = sys.argv[1:3]
    baseline, ordinal = (None, None) if len(sys.argv) == 3 else (sys.argv[3], int(sys.argv[4]))
    print(",".join(str(value) for value in verify(executable, trace, baseline, ordinal)))


if __name__ == "__main__":
    main()
