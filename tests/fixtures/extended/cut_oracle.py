#!/usr/bin/env python3
"""Compare text-cut with GNU cut under LC_ALL=C, byte for byte.

usage: cut_oracle.py TEXT_CUT WORKDIR [CASES]

Each case draws a mode (-b, -c or -f, short, bundled or long, sometimes
abbreviated as getopt_long allows), a LIST (N, N-, -M, N-M joined by commas
or blanks, with invalid entries now and then: 0, decreasing ranges, a lone
-, letters, numbers past 2^64, an empty list), and any of --complement, -d
(one byte, empty, two bytes, or LF itself so the input becomes one record),
-s, --output-delimiter (empty and multi-byte too), -n and -z, with options
before or after the files and "--" sometimes. Inputs reach the tools on
standard input, as named files (one to three), as "-", or as a missing file.
stdout and the exit status must match. Content groups:

  fields    lines of fields split by : , TAB or space, some without any
  ragged    empty lines, NULs, high bytes, no final line end
  records   NUL-terminated records for -z
  large     300 KB to 1.2 MB, so input crosses the 256 KiB read chunks
"""
import os
import random
import subprocess
import sys

TOOL, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
CASES = int(sys.argv[3]) if len(sys.argv) > 3 else 1000
os.makedirs(WORK, exist_ok=True)
ENV = dict(os.environ, LC_ALL="C")
counts = {}
failures = []
DELIMS = [b":", b"\t", b",", b" "]


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def line(rng, delim, eol):
    if rng.random() < 0.15:
        return bytes(rng.choice(b"abc xyz") for _ in range(rng.randint(0, 12))).replace(delim, b"") + eol
    fields = [bytes(rng.choice(b"abcdefgh0123 \t") for _ in range(rng.randint(0, 6))).replace(delim, b"") for _ in range(rng.randint(1, 9))]
    return delim.join(fields) + eol


def gen(rng, group, delim):
    if group == "fields":
        t = b"".join(line(rng, delim, b"\n") for _ in range(rng.randint(0, 30)))
    elif group == "ragged":
        t = bytes(rng.choice(b"ab:\t,\n\n\x00\x80\xff ") for _ in range(rng.randint(0, 300)))
    elif group == "records":
        t = b"".join(line(rng, delim, b"\x00") for _ in range(rng.randint(0, 20))).replace(b"\x00\x00", b"\x00\n\x00")
    else:
        unit = b"".join(line(rng, delim, b"\n") for _ in range(rng.randint(20, 80)))
        t = unit * (rng.randint(300000, 1200000) // max(1, len(unit)))
    if t and rng.random() < 0.25:
        t = t[:-1]
    return t


def number(rng):
    r = rng.random()
    if r < 0.9:
        return str(rng.randint(1, 12))
    if r < 0.95:
        return "0"
    return rng.choice(["18446744073709551615", "18446744073709551616", "9223372036854775808", "007", "99999999999999999999999"])


def gen_list(rng):
    if rng.random() < 0.02:
        return ""
    parts = []
    for _ in range(rng.randint(1, 4)):
        r = rng.random()
        if r < 0.4:
            parts.append(number(rng))
        elif r < 0.6:
            parts.append(number(rng) + "-")
        elif r < 0.75:
            parts.append("-" + number(rng))
        elif r < 0.95:
            a, b = sorted([int(number(rng)) % 20 + 1, int(number(rng)) % 20 + 1])
            if rng.random() < 0.1:
                a, b = b + 1, a
            parts.append(f"{a}-{b}")
        else:
            parts.append(rng.choice(["-", "x", "1--2", "2-3-4", "a-", "", "1-x"]))
    sep = rng.choice([",", ",", " ", "\t", ", "])
    return sep.join(parts)


def options(rng):
    opts = []
    mode = rng.choice(["b", "c", "f", "f", "f"])
    lst = gen_list(rng)
    style = rng.random()
    if style < 0.4:
        opts += ["-" + mode, lst]
    elif style < 0.7:
        opts += ["-" + mode + lst] if lst else ["-" + mode, lst]
    else:
        long = {"b": "bytes", "c": "characters", "f": "fields"}[mode]
        cut = rng.randint(1, len(long)) if rng.random() < 0.3 else len(long)
        if mode == "c":
            cut = max(cut, 2)
        name = "--" + long[:cut]
        opts += [name + "=" + lst] if rng.random() < 0.5 else [name, lst]
    delim = rng.choice(DELIMS)
    if mode == "f" or rng.random() < 0.05:
        r = rng.random()
        if r < 0.85:
            d = delim
        elif r < 0.9:
            d = b""
        elif r < 0.95:
            d = b"\n"
        else:
            d = b"::"
        opts += [b"-d" + d] if rng.random() < 0.5 else ([b"--delimiter=" + d] if rng.random() < 0.5 else [b"--del", d])
    elif mode != "f":
        delim = b"\t"
    if rng.random() < 0.25 and (mode == "f" or rng.random() < 0.1):
        opts.append(rng.choice(["-s", "--only-delimited", "--only"]))
    if rng.random() < 0.25:
        opts.append(rng.choice(["--complement", "--compl"]))
    if rng.random() < 0.25:
        od = rng.choice([b"", b"|", b"<>", b"\t", b"::"])
        opts += [b"--output-delimiter=" + od] if rng.random() < 0.6 else [b"--output-d", od]
    if rng.random() < 0.05:
        opts.append("-n")
    if rng.random() < 0.02:
        opts.append(rng.choice(["--b", "--o=x", "-q"]))
    zero = rng.random() < 0.08
    if zero:
        opts.append(rng.choice(["-z", "--zero-terminated"]))
    if rng.random() < 0.05:
        extra = rng.choice(["b", "f"])
        opts += ["-" + extra, "1"]
    return [o if isinstance(o, bytes) else o.encode() for o in opts], delim, zero


def run(cmd, stdin_path=None):
    if stdin_path:
        with open(stdin_path, "rb") as f:
            return subprocess.run(cmd, stdin=f, capture_output=True, cwd=WORK, env=ENV, timeout=60)
    return subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, cwd=WORK, env=ENV, timeout=60)


def fail(msg, files, mine, ref):
    failures.append(msg)
    if len(failures) <= 5:
        d = os.path.join(WORK, f"fail{len(failures)}")
        os.makedirs(d, exist_ok=True)
        for name, data in files + [("mine", mine), ("ref", ref)]:
            with open(os.path.join(d, name), "wb") as f:
                f.write(data)
        print("FAIL", msg, "->", d)


def main():
    rng = random.Random(20261103)
    for case in range(CASES):
        opts, delim, zero = options(rng)
        group = "large" if case % 40 == 39 else ("records" if zero and rng.random() < 0.7 else rng.choice(["fields", "fields", "ragged"]))
        files = [(f"f{i}", gen(rng, group, delim)) for i in range(rng.randint(1, 3))]
        for name, data in files:
            with open(os.path.join(WORK, name), "wb") as f:
                f.write(data)
        mode = rng.choice(["named", "named", "stdin", "stdin", "dash", "missing", "after"])
        names = [n.encode() for n, _ in files]
        stdin_path = None
        if mode == "stdin":
            names = []
            stdin_path = os.path.join(WORK, "f0")
        elif mode == "dash":
            names[0] = b"-"
            stdin_path = os.path.join(WORK, "f0")
        elif mode == "missing":
            names.insert(rng.randint(0, len(names)), b"no-such-file")
        if mode == "after":
            args = names[:1] + opts + names[1:]
        elif rng.random() < 0.1:
            args = opts + [b"--"] + names
        else:
            args = opts + names
        mine = run([TOOL.encode()] + args, stdin_path)
        ref = run([b"cut"] + args, stdin_path)
        key = f"{group}/{mode}/{'ok' if ref.returncode == 0 else 'error'}"
        bump(key + "/cases")
        if mine.returncode != ref.returncode or mine.stdout != ref.stdout:
            fail(f"{key} {repr(b' '.join(args))[:200]} rc {mine.returncode}/{ref.returncode}", files, mine.stdout, ref.stdout)
        else:
            bump(key + "/agree")
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
