"""Old-versus-new differential test for text_grep's buffered scan.

    python3 -I compare.py OLD_TEXT_GREP NEW_TEXT_GREP [--seed N] [--count N]

OLD is a build from before the 64 KiB buffer, literal prefilter and output
buffer; NEW is the current build. Each case runs both on the same generated
stdin and arguments and requires identical stdout, stderr and exit status.
Inputs mix ASCII, two- to four-byte scalars, CR, NUL, invalid UTF-8, records
longer than one 64 KiB read, and records that straddle reads; options mix
-v, -n, -c, small --max-line and small --max-work.
"""
import random
import subprocess
import sys

PATTERNS = ["zz", "ab", "a", "é", "日本", "b+c", "^a", "a$", r"\bab\b", "x|ab", "[0-9]+",
            "(?<=a)b", "(?<!b)a", "a.c", "", r"\d\d", "ab?c", "c", "abc|ab", r"\p{L}+é"]
PIECES = ["a", "b", "c", "ab", "abc", "é", "日本", "🙂", " ", "1", "x", "zz", "\r", "\0"]


def record(rng):
    if rng.random() < 0.02:
        return b"a" * rng.randint(60000, 140000) + rng.choice([b"", b"ab", b"zz"])
    body = "".join(rng.choice(PIECES) for _ in range(rng.randint(0, 12))).encode()
    if rng.random() < 0.008:
        at = rng.randint(0, len(body))
        body = body[:at] + rng.choice([b"\xff", b"\x80", b"\xc3", b"\xe6\x97"]) + body[at:]
    return body


def case(rng):
    lines = [record(rng) for _ in range(rng.randint(0, 40))]
    if rng.random() < 0.1:
        lines += [b"a" * 50] * rng.randint(1000, 3000)
    data = b"\n".join(lines) + (b"\n" if lines and rng.random() < 0.7 else b"")
    args = []
    for flag in ("-v", "-n", "-c"):
        if rng.random() < 0.3:
            args.append(flag)
    if rng.random() < 0.15:
        args += ["--max-line", str(rng.choice([0, 5, 30, 70000, 100000]))]
    if rng.random() < 0.1:
        args += ["--max-work", str(rng.choice([1, 50, 1000, 100000]))]
    return args + ["--", rng.choice(PATTERNS)], data


def main():
    argv = sys.argv[1:]
    seed, count = 20261031, 1500
    if "--seed" in argv:
        i = argv.index("--seed"); seed = int(argv[i + 1]); del argv[i:i + 2]
    if "--count" in argv:
        i = argv.index("--count"); count = int(argv[i + 1]); del argv[i:i + 2]
    old, new = argv
    rng = random.Random(seed)
    failures, statuses, large = [], {}, 0
    for _ in range(count):
        args, data = case(rng)
        large += len(data) > 65536
        a = subprocess.run([old, *args], input=data, capture_output=True, timeout=60)
        b = subprocess.run([new, *args], input=data, capture_output=True, timeout=60)
        statuses[b.returncode] = statuses.get(b.returncode, 0) + 1
        if (a.returncode, a.stdout, a.stderr) != (b.returncode, b.stdout, b.stderr):
            failures.append((args, len(data), a.returncode, b.returncode, a.stderr[:80], b.stderr[:80]))
    print(f"seed {seed}: {count - len(failures)}/{count} identical, {large} inputs over 64 KiB, statuses {dict(sorted(statuses.items()))}")
    for f in failures[:10]:
        print("  mismatch", f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
