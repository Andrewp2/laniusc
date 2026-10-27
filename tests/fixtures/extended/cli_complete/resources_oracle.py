"""Actual KV completion owners; reuse full-trace/source authority unchanged."""
import importlib.util
from pathlib import Path
import sys
import time


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
KV = load("completion_resource_kv_runner", HERE.parent / "kv_publication/oracle.py")
SHELL = load("completion_resource_frame_oracle", HERE / "shell_oracle.py")
LEDGER = KV.LEDGER
ALLOWED = {"mmap", "munmap", "write", "rt_sigaction"}
PROFILES = (
    ("candidates", b"p", (), 1, SHELL.frame(words=[b"put"])),
    ("files", b"'db space", (b"put",), 11,
     SHELL.frame(b"files", prefix=b"db space", continuation=b"single")),
    ("none", b"", (b"@sentinel.rsp",), 13, SHELL.NONE),
)


def arguments(prefix, complete):
    return [b"--lanius-complete-bash", b"1", b"", prefix, *complete]


def guard(result):
    assert LEDGER.TRACE == "all", "completion requires complete syscall observation"
    for item in result["events"]:
        assert item["name"] in ALLOWED, ("completion performed non-query host work", item)
        if item["name"] == "write":
            assert LEDGER.arguments(item["args"])[0] in ("1", "2"), item
    assert not result["acquisitions"] and not result["live"]
    # No unverified mmap is counted as a source allocation merely by its place
    # in the trace. The unchanged raw verifier binds the exact allocator site.
    assert len(KV.selected(result, "mmap")) == len(result["source"]["allocations"])


def required_owners(result, args, decoded, expected, candidates=False):
    points = result["source"]["allocations"]
    lengths = [item["length"] for item in points]
    required = [sum(map(len, args)), decoded, len(expected)]
    if candidates:
        required.append(32768)
    assert all(size in lengths for size in required), (required, lengths)
    first = KV.selected(result, "write")[0]
    assert LEDGER.arguments(first["args"])[0] == "1"
    assert all(item["index"] < first["index"] for item in points), "reply was published before allocation completed"
    assert 0 < len(points) <= 32, "split the focused campaign before increasing its bound"
    return points


def run(executable, group):
    suite = KV.Suite(executable, "completion-" + group)
    deadline = time.monotonic() + 70
    denials = 0

    def invoke(directory, cwd, args, **expected):
        assert time.monotonic() < deadline, "completion resource group exceeded finite budget"
        before = KV.tree(cwd)
        result = suite.run(directory, cwd, args, **expected)
        guard(result)
        assert KV.tree(cwd) == before
        return result

    def case(name):
        directory, cwd = suite.case(name)
        (cwd / "sentinel.db").write_bytes(b"must not load this database\0\xff")
        (cwd / "sentinel.rsp").write_bytes(b"--unknown 'unfinished\0")
        return directory, cwd

    if group == "allocations":
        schedules = set()
        for name, prefix, complete, decoded, expected in PROFILES:
            directory, cwd = case(name)
            args = arguments(prefix, complete)
            baseline = invoke(directory, cwd, args, output=expected, label="baseline")
            assert SHELL.unpack_frame(expected)[0].decode() == name
            points = required_owners(baseline, args, decoded, expected, name == "candidates")
            schedules.add(tuple(item["length"] for item in points))
            for item in points:
                invoke(directory, cwd, args, status=4, diagnostic=KV.ALLOCATION,
                       rules=[KV.rule("mmap", item["ordinal"], "ENOMEM")], baseline=baseline,
                       label="oom-%d" % item["ordinal"])
                denials += 1
        assert len(schedules) == 3 and suite.count == denials + 3
    else:
        assert group == "output"
        for name, prefix, complete, _, expected in (
            PROFILES[0], PROFILES[2],
            ("long-files", b"a" * 1200, (b"put",), 1203, SHELL.frame(b"files", prefix=b"a" * 1200)),
        ):
            directory, cwd = case(name)
            args = arguments(prefix, complete)
            baseline = invoke(directory, cwd, args, output=expected, label="baseline")
            writes = KV.selected(baseline, "write")
            assert all(LEDGER.arguments(item["args"])[0] == "1" for item in writes)
            first = writes[0]
            invoke(directory, cwd, args, status=3, diagnostic=KV.IO,
                   rules=[KV.rule("write", first["ordinal"], "EIO")], baseline=baseline, label="first-eio")
            invoke(directory, cwd, args, output=expected,
                   rules=[KV.rule("write", first["ordinal"], "EINTR")], baseline=baseline, label="first-eintr")
            if name == "long-files":
                assert len(writes) == 2 and int(first["result"]) == 1024
                invoke(directory, cwd, args, status=3, output=expected[:1024], diagnostic=KV.IO,
                       rules=[KV.rule("write", writes[1]["ordinal"], "EIO")], baseline=baseline, label="second-eio-real-prefix")
                capped = invoke(directory, cwd, args, status=3, diagnostic=KV.IO,
                                rules=[dict(KV.rule("write", first["ordinal"], "EINTR"), last=first["ordinal"] + 63)], label="attempt-cap")
                stdout = [item for item in KV.selected(capped, "write") if LEDGER.arguments(item["args"])[0] == "1"]
                assert len(stdout) == 64 and all(item["result"].startswith("-1 EINTR ") for item in stdout)
                assert all((item["ip"], item["args"]) == (first["ip"], first["args"]) for item in stdout)
                broken = invoke(directory, cwd, args, status=3, diagnostic=KV.IO, closed_stdout=True, label="real-epipe")
                actual = [item for item in KV.selected(broken, "write") if LEDGER.arguments(item["args"])[0] == "1"]
                assert len(actual) == 1 and actual[0]["result"].startswith("-1 EPIPE ") and "INJECTED" not in actual[0]["result"]
                KV.bind(baseline, broken, KV.rule("write", first["ordinal"], "EPIPE"))
        assert suite.count == 12
    print("cli-completion resources group=%s cases=%d reached-oom=%d evidence=%s" %
          (group, suite.count, denials, suite.directory))


def controls():
    count = 0
    for name, _, _, _, frame in PROFILES:
        assert SHELL.unpack_frame(frame)[0].decode() == name
        count += 1
    empty = dict(events=[], acquisitions=[], live={}, source=dict(allocations=[]))
    guard(empty)
    count += 1
    for name in LEDGER.CALLS - ALLOWED | {"socket", "unlink", "rename", "fork"}:
        try:
            guard(dict(empty, events=[dict(name=name)]))
        except AssertionError:
            count += 1
        else:
            raise AssertionError(("completion accepted a transient host effect", name))
    try:
        guard(dict(empty, events=[dict(name="write", args='3, "\\x61", 1')]))
    except AssertionError:
        count += 1
    else:
        raise AssertionError("completion accepted a nonstandard output descriptor")
    print("cli-completion resources CPU-controls=%d native-cases=0" % count)


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        assert len(sys.argv) == 3 and sys.argv[2] in ("allocations", "output")
        run(Path(sys.argv[1]), sys.argv[2])
