#!/usr/bin/env python3
"""Oracle for ext::kv_log: a Python dict model over generated op sequences,
plus crash injection.

Usage: oracle.py BATCH_BINARY WORK_DIR [--cases N] [--crashes N] [--seed S] [--cli KV]

With --cli, the kv sample program also runs a random put/get/delete/list
session against the same dict model (values given as arguments or on stdin).

Model cases run a random script (puts, deletes, gets, syncs, flushes,
compactions, iteration, clean close + reopen, and simulated crashes that drop
the unflushed buffer) and compare every output line, plus the exact bytes of
the log after each clean close, with the model.

Crash cases build a log, then damage a copy: truncate at a random offset,
flip a random byte, or append garbage. Reopening must report exactly the
records of the longest undamaged prefix and the bytes cut, iterate to the
dict state after those records (a prefix of the committed operations, and
all of them whenever the cut is at or past the synced length), and accept
further writes that survive another reopen.
"""
import os
import random
import struct
import subprocess
import sys
import zlib

HEADER = b"LKVLOG01"
PUT, DELETE = 1, 2


def record(kind, key, value=b""):
    body = struct.pack("<BII", kind, len(key), len(value)) + key + value
    return struct.pack("<I", zlib.crc32(body)) + body


def field(data):
    if isinstance(data, int):
        data = str(data).encode()
    return str(len(data)).encode() + b":" + data


def item(data):
    return str(len(data)).encode() + b":" + data


def replay(records):
    state = {}
    for kind, key, value in records:
        if kind == PUT:
            state[key] = value
        else:
            state.pop(key, None)
    return state


def iterate_line(state):
    parts = [b"i " + str(len(state)).encode()]
    for key, value in state.items():
        parts.append(item(key) + b" " + item(value))
    return b" ".join(parts)


class Model:
    """Tracks the records in the log, how many are flushed, and the options."""

    def __init__(self, buffer, sync_every, auto):
        self.buffer, self.sync_every, self.auto = buffer, sync_every, auto
        self.records = []  # (kind, key, value) in file order
        self.flushed = 0  # records written to the file
        self.synced_bytes = len(HEADER)

    def size(self, records):
        return len(HEADER) + sum(13 + len(k) + len(v) for _, k, v in records)

    def file_bytes(self):
        return self.size(self.records)

    def pending_bytes(self):
        return self.file_bytes() - self.size(self.records[: self.flushed])

    def state(self):
        return replay(self.records)

    def live_bytes(self):
        return sum(13 + len(k) + len(v) for k, v in self.state().items())

    def flush(self):
        self.flushed = len(self.records)

    def sync(self):
        self.flush()
        self.synced_bytes = self.file_bytes()

    def compact(self):
        self.records = [(PUT, k, v) for k, v in self.state().items()]
        self.flushed = len(self.records)
        self.synced_bytes = self.file_bytes()

    def after_write(self):
        if self.sync_every:
            self.sync()
        elif self.pending_bytes() >= self.buffer:
            self.flush()
        dead = self.file_bytes() - len(HEADER) - self.live_bytes()
        if self.auto > 0 and dead >= self.auto and dead > self.live_bytes():
            self.compact()

    def crash(self):
        self.records = self.records[: self.flushed]

    def encoded(self):
        return HEADER + b"".join(record(*r) for r in self.records)


def rand_bytes(rng, low, high):
    return bytes(rng.randrange(256) for _ in range(rng.randint(low, high)))


def gen_options(rng):
    buffer = rng.choice([0, 1, 40, 200, 4096, 1048576])
    sync_every = rng.random() < 0.15
    auto = rng.choice([0, 0, 0, 64, 300, 2000])
    return buffer, sync_every, auto


def open_op(path, options):
    buffer, sync_every, auto = options
    return field(b"o") + field(path) + field(buffer) + field(1 if sync_every else 0) + field(auto)


def run(binary, script):
    proc = subprocess.run(["sh", "-c", "ulimit -c 1; exec \"$0\"", binary], input=script, capture_output=True, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError("batch exited %d: %r" % (proc.returncode, proc.stderr[:400]))
    return proc.stdout


def compare(got, expected):
    """None when the output equals the expected lines, else a description.
    Values may hold newlines, so compare the whole text."""
    want = b"".join(line + b"\n" for line in expected)
    if got == want:
        return None
    at = 0
    while at < min(len(got), len(want)) and got[at] == want[at]:
        at += 1
    line = want[:at].count(b"\n")
    return "line %d: got %r expected %r" % (line, got[max(0, at - 40):at + 40], want[max(0, at - 40):at + 40])


def model_case(rng, binary, path):
    """Returns (script, expected lines, list of (line index, expected file bytes))."""
    options = gen_options(rng)
    model = Model(*options)
    keys = [rand_bytes(rng, 0, 6) for _ in range(rng.randint(1, 12))]
    script = [open_op(path, options)]
    expected = [b"o 0 0 8"]
    checks = []
    for _ in range(rng.randint(1, 80)):
        roll = rng.random()
        key = rng.choice(keys) if rng.random() < 0.85 else rand_bytes(rng, 0, 6)
        if roll < 0.40:
            if rng.random() < 0.02:
                value = rand_bytes(rng, 0, 4) * rng.randint(1, 400000)
            else:
                value = rand_bytes(rng, 0, 30)
            script.append(field(b"p") + field(key) + field(value))
            model.records.append((PUT, key, value))
            model.after_write()
            expected.append(b"p %d" % model.file_bytes())
        elif roll < 0.55:
            script.append(field(b"d") + field(key))
            found = key in model.state()
            if found:
                model.records.append((DELETE, key, b""))
                model.after_write()
            expected.append(b"d %d %d" % (1 if found else 0, model.file_bytes()))
        elif roll < 0.70:
            script.append(field(b"g") + field(key))
            state = model.state()
            expected.append(b"g " + item(state[key]) if key in state else b"g none")
        elif roll < 0.75:
            script.append(field(b"s"))
            model.sync()
            expected.append(b"s %d" % model.file_bytes())
        elif roll < 0.78:
            script.append(field(b"f"))
            model.flush()
            expected.append(b"f %d" % model.file_bytes())
        elif roll < 0.82:
            script.append(field(b"c"))
            model.compact()
            expected.append(b"c %d" % model.file_bytes())
        elif roll < 0.87:
            script.append(field(b"i"))
            expected.append(iterate_line(model.state()))
        elif roll < 0.89:
            script.append(field(b"n"))
            expected.append(b"n %d" % len(model.state()))
        elif roll < 0.92:
            script.append(field(b"b"))
            live = model.live_bytes()
            expected.append(b"b %d %d %d %d" % (model.file_bytes(), live, model.file_bytes() - 8 - live, model.synced_bytes))
        elif roll < 0.96:
            # Clean close, check the file bytes, reopen with fresh options.
            script.append(field(b"q"))
            model.sync()
            expected.append(b"q 0")
            checks.append((len(expected), model.encoded()))
            options = gen_options(rng)
            model.buffer, model.sync_every, model.auto = options
            script.append(open_op(path, options))
            expected.append(b"o %d 0 %d" % (len(model.records), model.file_bytes()))
        else:
            # Crash: unflushed records are lost; written ones survive.
            script.append(field(b"x"))
            expected.append(b"x")
            model.crash()
            options = gen_options(rng)
            model.buffer, model.sync_every, model.auto = options
            script.append(open_op(path, options))
            model.synced_bytes = model.file_bytes()
            expected.append(b"o %d 0 %d" % (len(model.records), model.file_bytes()))
    script.append(field(b"i"))
    expected.append(iterate_line(model.state()))
    script.append(field(b"q"))
    expected.append(b"q 0")
    model.sync()
    return b"".join(script), expected, model.encoded()


def check_model(rng, binary, work, index):
    path = os.path.join(work, "model.log").encode()
    if os.path.exists(path):
        os.remove(path)
    script, expected, final = model_case(rng, binary, path)
    differs = compare(run(binary, script), expected)
    if differs:
        return "model case %d %s" % (index, differs)
    with open(path, "rb") as handle:
        data = handle.read()
    if data != final:
        return "model case %d: final log bytes differ (%d vs %d)" % (index, len(data), len(final))
    return None


def build_log(rng):
    """A random committed op sequence and its log encoding: (records, bytes, boundaries)."""
    keys = [rand_bytes(rng, 0, 5) for _ in range(rng.randint(1, 8))]
    state = {}
    records = []
    for _ in range(rng.randint(0, 40)):
        key = rng.choice(keys)
        if key in state and rng.random() < 0.3:
            records.append((DELETE, key, b""))
            del state[key]
        else:
            value = rand_bytes(rng, 0, 20)
            records.append((PUT, key, value))
            state[key] = value
    data = HEADER
    boundaries = [len(HEADER)]
    for r in records:
        data += record(*r)
        boundaries.append(len(data))
    return records, data, boundaries


def crash_case(rng, binary, work, index):
    records, data, boundaries = build_log(rng)
    mode = rng.choice(["truncate", "truncate", "flip", "garbage", "stale"])
    damaged = data
    if mode == "truncate":
        cut = rng.randint(0, len(data))
        damaged = data[:cut]
    elif mode == "flip" and len(data) > len(HEADER):
        at = rng.randrange(len(HEADER), len(data))
        damaged = data[:at] + bytes([data[at] ^ (1 << rng.randrange(8))]) + data[at + 1:]
    elif mode == "garbage":
        damaged = data + rand_bytes(rng, 1, 30)
    path = os.path.join(work, "crash.log")
    with open(path, "wb") as handle:
        handle.write(damaged)
    stale = path + ".compact"
    if mode == "stale":
        with open(stale, "wb") as handle:
            handle.write(rand_bytes(rng, 0, 50))
    # The longest prefix of records that is intact in the damaged file.
    if len(damaged) < len(HEADER):
        kept = 0
        good_end = len(HEADER)
        truncated = 0
    else:
        kept = 0
        while kept < len(records) and boundaries[kept + 1] <= len(damaged) and damaged[boundaries[kept]:boundaries[kept + 1]] == data[boundaries[kept]:boundaries[kept + 1]]:
            kept += 1
        good_end = boundaries[kept]
        truncated = len(damaged) - good_end
    survivors = records[:kept]
    # Committed operations survive any cut at or past their end.
    if mode == "truncate":
        assert all(b <= len(damaged) for b in boundaries[1:kept + 1])
    state = replay(survivors)
    extra_key = rand_bytes(rng, 0, 5)
    extra_value = rand_bytes(rng, 0, 20)
    # No auto compaction here: the expected end offsets assume plain appends.
    options = gen_options(rng)[:2] + (0,)
    script = open_op(path.encode(), options) + field(b"i") + field(b"p") + field(extra_key) + field(extra_value) + field(b"q")
    script += open_op(path.encode(), gen_options(rng)) + field(b"i") + field(b"q")
    after = dict(state)
    after[extra_key] = extra_value
    end = good_end + 13 + len(extra_key) + len(extra_value)
    expected = [
        b"o %d %d %d" % (kept, truncated, good_end),
        iterate_line(state),
        b"p %d" % end,
        b"q 0",
        b"o %d 0 %d" % (kept + 1, end),
        iterate_line(after),
        b"q 0",
    ]
    differs = compare(run(binary, script), expected)
    if differs:
        return "crash case %d (%s) %s" % (index, mode, differs)
    if os.path.exists(stale):
        return "crash case %d: stale compaction file left behind" % index
    with open(path, "rb") as handle:
        final = handle.read()
    want = HEADER + b"".join(record(*r) for r in survivors) + record(PUT, extra_key, extra_value)
    if final != want:
        return "crash case %d (%s): final bytes differ" % (index, mode)
    return None


def not_a_log(binary, work):
    path = os.path.join(work, "bad.log")
    with open(path, "wb") as handle:
        handle.write(b"LKVLOG02" + record(PUT, b"k", b"v"))
    differs = compare(run(binary, open_op(path.encode(), (0, False, 0))), [b"err NotKvLog"])
    if differs:
        return "NotKvLog case " + differs
    return None


def cli_cases(rng, kv, work, count):
    """Random kv CLI sessions against a dict; returns failure strings."""
    failures = []
    path = os.path.join(work, "cli.log")
    for case in range(count):
        if os.path.exists(path):
            os.remove(path)
        state = {}
        for _ in range(rng.randint(1, 25)):
            key = rng.choice([b"a", b"bb", b"key-3", b"\xff\x01", b"x y"])
            roll = rng.random()
            if roll < 0.45:
                value = bytes(rng.choice(b"abc\n\t\x00\xfe") for _ in range(rng.randint(0, 12)))
                if rng.random() < 0.5 and b"\x00" not in value:
                    argv, stdin = [kv, "-f", path, "put", key, value], b""
                else:
                    argv, stdin = [kv, "-f", path, "put", key], value
                state[key] = value
                expect = (0, b"")
            elif roll < 0.65:
                argv, stdin = [kv, "-f", path, "get", key], b""
                expect = (0, state[key]) if key in state else (1, b"")
            elif roll < 0.8:
                argv, stdin = [kv, "-f", path, "delete", key], b""
                expect = (0, b"") if key in state else (1, b"")
                state.pop(key, None)
            elif roll < 0.9:
                argv, stdin = [kv, "-f", path, "compact"], b""
                expect = (0, b"")
            else:
                argv, stdin = [kv, "-f", path, "list"], b""
                expect = (0, b"".join(k + b"\t" + v + b"\n" for k, v in state.items()))
            proc = subprocess.run(["sh", "-c", "ulimit -c 1; exec \"$@\"", "sh"] + argv, input=stdin, capture_output=True, timeout=60)
            if (proc.returncode, proc.stdout) != expect:
                failures.append("cli case %d: %r gave %r expected %r" % (case, argv[3:], (proc.returncode, proc.stdout), expect))
                break
    return failures


def main():
    args = sys.argv[1:]
    binary, work = args[0], args[1]
    cases, crashes, seed, cli, cli_count = 300, 600, 1, None, 40
    at = 2
    while at < len(args):
        if args[at] == "--cases":
            cases = int(args[at + 1])
        elif args[at] == "--crashes":
            crashes = int(args[at + 1])
        elif args[at] == "--seed":
            seed = int(args[at + 1])
        elif args[at] == "--cli":
            cli = args[at + 1]
        at += 2
    os.makedirs(work, exist_ok=True)
    rng = random.Random(seed)
    failures = []
    for index in range(cases):
        failure = check_model(rng, binary, work, index)
        if failure:
            failures.append(failure)
    for index in range(crashes):
        failure = crash_case(rng, binary, work, index)
        if failure:
            failures.append(failure)
    failure = not_a_log(binary, work)
    if failure:
        failures.append(failure)
    cli_note = ""
    if cli:
        failures += cli_cases(rng, cli, work, cli_count)
        cli_note = ", %d cli sessions" % cli_count
    for failure in failures[:10]:
        print(failure)
    print("kv_log oracle: %d model cases, %d crash cases%s, %d failures" % (cases, crashes, cli_note, len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
