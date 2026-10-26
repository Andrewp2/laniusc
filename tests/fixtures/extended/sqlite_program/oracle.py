#!/usr/bin/env python3
"""Test orchestration only; persisted state is read through CPython sqlite3."""
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

MODE, EXE = sys.argv[1], os.fsencode(sys.argv[2])
OBSERVER = sys.argv[3] if len(sys.argv) > 3 else None
CASES = 0


def child(argv, **kwargs):
    if not OBSERVER:
        return subprocess.run(argv, timeout=10, **kwargs)
    with tempfile.TemporaryFile() as trace:
        environment = os.environ.copy()
        environment["LD_PRELOAD"] = OBSERVER
        environment["LANIUS_SQLITE_TRACE_FD"] = str(trace.fileno())
        result = subprocess.run(argv, timeout=10, env=environment,
                                pass_fds=(trace.fileno(),), **kwargs)
        trace.seek(0)
        events = trace.read().splitlines()
        owners = {b"D": 0, b"S": 0}
        for event in events:
            assert event in [b"D+", b"D-", b"S+", b"S-"], events
            kind, direction = event[:1], event[1:]
            owners[kind] += 1 if direction == b"+" else -1
            assert 0 <= owners[kind] <= 1, events
        assert owners == {b"D": 0, b"S": 0}, (argv, result, events)
        return result


def invoke(args, data=b"", status=0, word=None, **kwargs):
    global CASES
    argv = [EXE] + [arg if isinstance(arg, bytes) else os.fsencode(arg) for arg in args]
    result = child(argv, input=data, stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, **kwargs)
    CASES += 1
    assert result.returncode == status, (argv, status, result)
    if status == 0:
        assert not result.stderr, result
    else:
        assert not result.stdout, result
        assert result.stderr.startswith(b"sqlite-kv: ") and result.stderr.endswith(b"\n"), result
        assert b"\0" not in result.stderr, result
        if word:
            assert word in result.stderr, result
    return result.stdout


def rows(path):
    with sqlite3.connect(path) as database:
        values = database.execute("SELECT key,value,typeof(key),typeof(value) FROM kv ORDER BY key").fetchall()
        assert all(key_type == value_type == "blob" for _, _, key_type, value_type in values), values
        assert database.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
        return {key: value for key, value, _, _ in values}


def put(path, key, value, *options):
    assert invoke([path, "put", key, *options], value) == b""


def matrix(directory):
    path = directory / "persisted.db"
    expected = {}
    for index, length in enumerate([0, 1, 7, 1023, 1024, 1025, 8193, 65537]):
        key = [b"", b"plain", b"quote'); DROP TABLE kv;--", b"\xff\x80key",
               b"spaces and\ttabs", b"key\nline", b"x" * 4096, b"last"][index]
        value = bytes(((i * 37) ^ (i // 256)) & 255 for i in range(length))
        put(path, key, value)
        expected[key] = value
        assert invoke([path, "get", key]) == value
        assert rows(path) == expected
    assert invoke([path, "count"]) == b"8\n"
    replacement = b"new\0value\xff\n"
    put(path, b"plain", replacement)
    expected[b"plain"] = replacement
    assert invoke([path, "get", b"plain"]) == replacement
    assert invoke([path, "count"]) == b"8\n"
    assert invoke([path, "delete", b"plain"]) == b""
    del expected[b"plain"]
    invoke([path, "get", b"plain"], status=5, word=b"not found")
    invoke([path, "delete", b"plain"], status=5, word=b"not found")
    assert rows(path) == expected
    # Seed and modify rows independently, then read the exact BLOB through Lanius.
    with sqlite3.connect(path) as database:
        database.execute("INSERT INTO kv(key,value) VALUES (?,?)", (b"python", b"\0\xffpeer\0"))
    assert invoke([path, "get", "python"]) == b"\0\xffpeer\0"
    put(path, b"python", b"round-trip")
    assert rows(path)[b"python"] == b"round-trip"
    # The delimiter permits a key that begins with a dash.
    assert invoke(["--", path, "put", b"-key"], b"dash") == b""
    assert invoke(["--", path, "get", b"-key"]) == b"dash"


def limits(directory):
    path = directory / "limits.db"
    put(path, b"stable", b"original")
    before = rows(path)
    invalid = [[], [path], [path, "other"], [path, "get"], [path, "count", "extra"],
               [path, "put", "a", "extra"], [path, "get", "a", "--unknown"],
               [path, "put", "a", "--max-input"], [path, "put", "a", "--max-input=-1"],
               [path, "put", "a", "--max-input=+1"], [path, "put", "a", "--max-input=16777217"],
               [path, "get", "a", "--max-output=16777217"], [path, "count", "--max-io-calls=2147483648"],
               [path, "count", "--max-io-calls="], [path, "get", b"x" * 4097],
               [b"", "put", "a"], [":memory:", "put", "a"],
               ["file::memory:", "put", "a"], ["file:ambiguous.db", "put", "a"],
               [b"bad\xffpath", "put", "a"], ["--help", "--unknown"], ["--help=yes"]]
    for args in invalid:
        invoke(args, b"unread", 2)
        assert rows(path) == before
    invoke(["-h"] * 17, status=2)
    invoke(["x" * 16385], status=2)
    assert invoke(["--help"]).startswith(b"Usage: sqlite-kv DB put|get|delete KEY")
    for value in [b"", b"abc", b"x" * 1024, b"x" * 1025]:
        put(path, b"bounded", value, f"--max-input={len(value)}")
        assert invoke([path, "get", "bounded", f"--max-output={len(value)}"]) == value
        if value:
            invoke([path, "put", "bounded", f"--max-input={len(value)-1}"], b"z" * len(value), 2, b"input limit")
            assert rows(path)[b"bounded"] == value
            invoke([path, "get", "bounded", f"--max-output={len(value)-1}"], status=2, word=b"output limit")
    for budget in [0, 1]:
        invoke([path, "put", "bounded", f"--max-io-calls={budget}"], b"changed", 2, b"call limit")
    assert rows(path)[b"bounded"] == b"x" * 1025
    put(path, "empty", b"", "--max-input=0", "--max-io-calls=1")
    assert invoke([path, "get", "empty", "--max-output=0", "--max-io-calls=0"]) == b""
    invoke([path, "get", "stable", "--max-io-calls=0"], status=2, word=b"call limit")
    invoke([path, "count", "--max-output=1"], status=2, word=b"output limit")
    invoke([path, "count", "--max-io-calls=0"], status=2, word=b"call limit")
    put(path, "exact", b"abc", "--max-io-calls=2")
    put(path, "last-option", b"abc", "--max-input=0", "--max-input", "3")
    untouched = directory / "not-created.db"
    invoke([untouched, "put", "key", "--max-input=0"], b"x", 2, b"input limit")
    assert not untouched.exists()
    missing = directory / "missing.db"
    invoke([missing, "get", "key"], status=4, word=b"database")
    invoke([missing, "count"], status=4, word=b"database")
    invoke([missing, "delete", "key"], status=4, word=b"database")
    assert not missing.exists()


def errors(directory):
    path = directory / "errors.db"
    put(path, "stable", b"original")
    with sqlite3.connect(path) as locked:
        locked.execute("BEGIN EXCLUSIVE")
        for command, data in [("get", b""), ("put", b"replacement"), ("delete", b"")]:
            invoke([path, command, "stable"], data, 4, b"busy or locked")
        invoke([path, "count"], status=4, word=b"busy or locked")
        locked.rollback()
    assert rows(path) == {b"stable": b"original"}
    # A constraint created by an independent client must fail atomically.
    with sqlite3.connect(path) as database:
        database.execute("CREATE TRIGGER reject_value BEFORE UPDATE ON kv BEGIN SELECT RAISE(ABORT,'rejected'); END")
    invoke([path, "put", "stable"], b"rejected replacement", 4, b"constraint")
    assert rows(path) == {b"stable": b"original"}
    with sqlite3.connect(path) as database:
        database.execute("DROP TRIGGER reject_value")
    put(path, "stable", b"after error")
    # File permissions force SQLite's read/write open to fall back to read-only.
    # Exercise the same boundary in root-owned CI by dropping the child UID.
    readonly = directory / "readonly.db"
    put(readonly, "key", b"readable")
    readonly.chmod(0o444)
    child = {}
    if os.geteuid() == 0:
        directory.chmod(0o755)
        os.chmod(EXE, 0o755)
        child["preexec_fn"] = lambda: os.setuid(65534)
    assert invoke([readonly, "get", "key"], **child) == b"readable"
    assert invoke([readonly, "count"], **child) == b"1\n"
    invoke([readonly, "put", "key"], b"replacement", 4, b"read-only", **child)
    invoke([readonly, "delete", "key"], status=4, word=b"read-only", **child)
    readonly.chmod(0o600)
    assert rows(readonly) == {b"key": b"readable"}
    bad = directory / "not-a-database.db"
    bad.write_bytes(b"not a sqlite database\0\xff")
    invoke([bad, "get", "key"], status=4, word=b"database")
    empty = directory / "empty.db"
    with sqlite3.connect(empty):
        pass
    invoke([empty, "count"], status=4, word=b"database")
    text = directory / "wrong-type.db"
    with sqlite3.connect(text) as database:
        database.execute("CREATE TABLE kv(key BLOB PRIMARY KEY,value)")
        database.execute("INSERT INTO kv VALUES (?,?)", (b"text", "text is not a BLOB"))
    invoke([text, "get", "text"], status=4, word=b"database")


def io(directory):
    path = directory / "io.db"
    put(path, "stable", b"binary\0value\xff" * 200)
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        result = child([EXE, os.fsencode(path), b"put", b"stable"], stdin=fd,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    finally:
        os.close(fd)
    global CASES
    CASES += 1
    assert result.returncode == 3 and not result.stdout and b"input I/O" in result.stderr, result
    assert rows(path)[b"stable"] == b"binary\0value\xff" * 200
    with open("/dev/full", "wb") as full:
        result = child([EXE, os.fsencode(path), b"get", b"stable"], stdout=full,
                       stderr=subprocess.PIPE)
        CASES += 1
        assert result.returncode == 3 and b"output I/O" in result.stderr, result
        result = child([EXE, os.fsencode(path), b"get", b"stable"], stdout=full,
                       stderr=full)
        CASES += 1
        assert result.returncode == 3, result
    # A subsequent independent writer can take an exclusive lock after errors.
    with sqlite3.connect(path, timeout=0) as database:
        database.execute("BEGIN EXCLUSIVE")
        database.rollback()


with tempfile.TemporaryDirectory(prefix="laniusc_sqlite_program_") as name:
    directory = Path(name)
    {"matrix": matrix, "limits": limits, "errors": errors, "io": io}[MODE](directory)
print(f"sqlite-program-{MODE} cases={CASES}")
