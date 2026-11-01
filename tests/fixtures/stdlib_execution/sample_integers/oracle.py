"""Test-only xoshiro reference anchored to immutable author-generated vectors."""
from collections import Counter
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

MASK = (1 << 64) - 1
HEAVY = (1 << 63) + 1
SEEDS = (0, 1, 42, 1 << 63, MASK, 0x123456789ABCDEF0)
HELP = (b"Usage: sample_integers SEED BOUND COUNT DRAW_LIMIT\n"
        b"Print COUNT deterministic non-cryptographic integers in [0, BOUND), one per line.\n"
        b"All arguments are unsigned decimal u64 with at most 20 bytes; leading zeros are allowed.\n"
        b"BOUND must be positive; COUNT is 0..4096. DRAW_LIMIT is shared across the whole request.\n"
        b"Rejected draws spend the limit. Exhaustion returns status 2 without output.\n"
        b"COUNT zero produces empty output; BOUND one needs no draws. No stdin is read.\n"
        b"Output permits 128 write attempts. A sole --help or -h shows help.\n")
ERROR = b"sample_integers: operation failed\n"
COUNTS = {"model": 32, "budget": 19, "cli": 36, "io": 11}
VECTORS = Path(__file__).resolve().parents[2] / "stdlib_foundation/random_vectors.txt"


def rotate(value, amount):
    return ((value << amount) | (value >> (64 - amount))) & MASK


class Reference:
    def __init__(self, seed):
        self.state = []
        for index in range(1, 5):
            value = (seed + index * 0x9E3779B97F4A7C15) & MASK
            value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & MASK
            value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & MASK
            self.state.append(value ^ (value >> 31))

    def draw(self):
        a, b, c, d = self.state
        answer = (rotate((a + d) & MASK, 23) + a) & MASK
        self.state = [(a ^ b ^ d) & MASK, (a ^ b ^ c) & MASK,
                      (a ^ c ^ (b << 17)) & MASK, rotate(b ^ d, 45)]
        return answer


class DrawLimit(Exception): pass


def samples(seed, bound, count, limit):
    if not 0 <= seed <= MASK or not 1 <= bound <= MASK or not 0 <= count <= 4096 or not 0 <= limit <= MASK:
        raise ValueError("input range")
    generator, used, values = Reference(seed), 0, []
    threshold = (1 << 64) % bound
    for _ in range(count):
        if bound == 1:
            values.append(0); continue
        while True:
            if used == limit: raise DrawLimit
            used += 1
            word = generator.draw()
            if word >= threshold:
                values.append(word % bound); break
    return b"".join(f"{value}\n".encode("ascii") for value in values), used


def author_controls():
    rows = [list(map(int, line.split())) for line in VECTORS.read_text().splitlines()]
    assert len(rows) == 6 and tuple(row[0] for row in rows) == SEEDS
    for row in rows:
        generator = Reference(row[0]); assert generator.state == row[1:5]
        assert [generator.draw() for _ in range(4)] == row[5:9]


def events(text):
    result, counts, live = [], Counter(), {}
    for line in text.splitlines():
        match = re.fullmatch(r"(read|write|close|mmap|munmap|mremap|brk|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups(); counts[name] += 1
        result.append(dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line))
        if name == "mmap":
            size = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]; assert address not in live; live[address] = size
            else: assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("mremap", "brk", "read", "close"):
            raise AssertionError(("unexpected host input/borrowed close/allocation service", line))
        elif name == "write" and args.startswith("2,"):
            assert not live, "diagnostic before owned storage cleanup"
    assert not live, ("observed unreleased mappings", live)
    return result


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18], "little") == 2 and int.from_bytes(header[18:20], "little") == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f"sample-integers-{mode}-")); self.count = 0

    def run(self, name, arguments=(), *, status=0, output=b"", trace=False, injection=None,
            closed_stdout=False, diagnostic=True, budget=False):
        prefix = self.directory / name; command = [self.executable, *arguments]
        if budget:
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=write", "-e",
                       "inject=write:error=EINTR:when=1..128", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none", "-e",
                      "trace=read,write,close,mmap,munmap,mremap,brk,rt_sigaction", "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection; traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            if closed_stdout:
                reader, writer = os.pipe(); os.close(reader)
                try: result = subprocess.run(command, stdin=descriptor, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
                finally: os.close(writer)
                result.stdout = b""
            else: result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
        finally: os.close(descriptor)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, len(result.stdout), len(output), result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected and selected[0]["answer"].startswith("-1 " + failure + " ")
        else: assert not marked, marked
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == ["write"]]
            assert len(selected) == 1 and selected[0][-3:] == ["129", "128", "write"], rows
        self.count += 1; return found

    def model(self, name, seed, bound, count, limit=None, **options):
        expected, needed = samples(seed, bound, count, MASK)
        if limit is None: limit = needed
        return self.run(name, list(map(str, (seed, bound, count, limit))), output=expected, **options)


def model(r):
    for seed in SEEDS:
        r.model(f"seed-{seed}-unit-bound", seed, 1, 4, 0)
        r.model(f"seed-{seed}-binary-bound", seed, 2, 8)
        r.model(f"seed-{seed}-maximum-bound", seed, MASK, 8)
        r.model(f"seed-{seed}-rejection-heavy", seed, HEAVY, 8)
    r.model("zero-count-zero-budget", 0, MASK, 0, 0)
    r.model("maximum-count-no-draws", 0, 1, 4096, 0)
    r.model("maximum-count-full-width", 42, MASK, 4096)
    r.model("power-of-two-63", 1, 1 << 63, 257)
    r.model("power-of-two-32", MASK, 1 << 32, 65)
    r.model("odd-small-bound", 0, 3, 1024)
    r.model("maximum-count-small-bound", 42, 1000003, 4096)
    r.model("maximum-draw-limit", MASK, MASK, 4, MASK)


def budget_cases(r):
    for seed in (0, 1, 42, MASK):
        for count in (1, 7):
            expected, needed = samples(seed, HEAVY, count, MASK)
            r.run(f"last-draw-{seed}-{count}", list(map(str, (seed, HEAVY, count, needed))), output=expected)
            r.run(f"one-draw-short-{seed}-{count}", list(map(str, (seed, HEAVY, count, needed - 1))), status=2)
    r.run("zero-budget-nontrivial-bound", ["0", "2", "1", "0"], status=2)
    r.run("shared-budget-not-reset-per-sample", ["0", "2", "8", "7"], status=2)
    r.model("shared-budget-exact", 0, 2, 8, 8)


def cli(r):
    valid = ["0", "2", "1", "1"]
    invalid = [[], ["0", "2", "1"], valid + ["extra"], ["--help", "0"], ["-h", "0"],
               ["--help", "--help"], ["-hh"], ["--help=yes"], ["--"]]
    for position in range(4):
        for malformed in ("", "-1", "0" * 21):
            changed = valid.copy(); changed[position] = malformed; invalid.append(changed)
        changed = valid.copy(); changed[position] = str(1 << 64); invalid.append(changed)
    for malformed in ("+0", " 1", "1.0", "1_0", "١", b"\xff"):
        changed = valid.copy(); changed[0] = malformed; invalid.append(changed)
    invalid += [["0", "0", "0", "0"], ["0", "1", "4097", "0"]]
    for index, arguments in enumerate(invalid): r.run(f"invalid-{index}", arguments, status=2, trace=True)
    for name, argument in (("help-long", "--help"), ("help-short", "-h")):
        found = r.run(name, [argument], output=HELP, trace=True)
        first_output = next(index for index, item in enumerate(found) if item["name"] == "write" and item["args"].startswith("1,"))
        assert all(index < first_output for index, item in enumerate(found) if item["name"] == "munmap")
    found = r.run("exact-eighty-byte-arguments", ["0" * 20, "0" * 19 + "1", "0" * 20, "0" * 20], trace=True)
    assert len([item for item in found if item["name"] == "mmap"]) == 2, "zero count acquired sample storage"


def io(r):
    args = ["42", str(MASK), "256", "512"]
    expected, _ = samples(42, MASK, 256, 512)
    baseline = r.run("baseline", args, output=expected, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    assert len(maps) == 3 and int(maps[-1]["args"].split(",")[1]) == 256 * 8
    reserve = baseline.index(maps[-1])
    for owner in maps[:2]:
        assert next(index for index, item in enumerate(baseline) if item["name"] == "munmap" and item["args"].split(",")[0] == owner["answer"]) < reserve
    assert not any(item["name"] == "mmap" for item in baseline[reserve + 1:])
    last_output = max(index for index, item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,"))
    assert next(index for index, item in enumerate(baseline) if index > reserve and item["name"] == "munmap" and item["args"].split(",")[0] == maps[-1]["answer"]) > last_output
    for old in maps:
        ordinal = old["ordinal"]
        found = r.run(f"owner-oom-{ordinal}", args, status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in found if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert fault["args"] == old["args"]
    r.run("closed-data-stdout", args, status=5, trace=True, closed_stdout=True)
    r.run("closed-help-stdout", ["--help"], status=5, trace=True, closed_stdout=True)
    r.run("output-eintr-retry", args, output=expected, trace=True, injection=("write", 1, "EINTR"))
    r.run("output-eio", args, status=5, trace=True, injection=("write", 1, "EIO"))
    r.run("signal-setup-eio", args, status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("output-attempt-cap", args, status=5, budget=True)
    r.run("draw-limit-cleanup-before-diagnostic", ["0", "2", "8", "7"], status=2, trace=True)


def controls():
    assert len(HELP) == 532 and len(ERROR) == 34
    author_controls()
    assert samples(0, 1, 4096, 0) == (b"0\n" * 4096, 0)
    assert samples(MASK, MASK, 0, 0) == (b"", 0)
    expected, used = samples(0, HEAVY, 7, MASK); assert used > 7
    try: samples(0, HEAVY, 7, used - 1)
    except DrawLimit: pass
    else: raise AssertionError("shared budget ignored rejected draw")
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs):
            if len(args) >= 2 and kwargs.get("status") == 2 and len(args[1]) == 4 and all(re.fullmatch(r"[0-9]{1,20}", str(value)) for value in args[1]):
                try: samples(*map(int, args[1]))
                except (ValueError, DrawLimit): pass
                else: raise AssertionError("invalid/budget reference accepted")
            self.count += 1; return [dict(name="mmap"), dict(name="mmap"), dict(name="write", args="1,")]
        def model(self, name, seed, bound, count, limit=None, **kwargs):
            expected, needed = samples(seed, bound, count, MASK)
            if limit is not None: assert samples(seed, bound, count, limit)[0] == expected
            self.count += 1; return []
    for function, name in ((model, "model"), (budget_cases, "budget"), (cli, "cli")):
        runner = CounterOnly(); function(runner); assert runner.count == COUNTS[name], (name, runner.count)
    trace = "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\n"
    assert len(events(trace)) == 2
    try: events(trace.split("munmap")[0])
    except AssertionError: pass
    else: raise AssertionError("missing cleanup accepted")
    print(f"sample-integers CPU controls=8; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]: controls()
    else:
        author_controls()
        mode, executable = sys.argv[1:]; runner = Runner(executable, mode)
        {"model": model, "budget": budget_cases, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"sample-integers-{mode} cases={runner.count} evidence={runner.directory}")
