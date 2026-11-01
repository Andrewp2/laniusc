#!/usr/bin/env python3
"""Compare text-sort with GNU sort under LC_ALL=C, byte for byte.

usage: sort_oracle.py TEXT_SORT WORKDIR [CASES]

Each case draws global options (-b -f -n -r -s -u -z, short, bundled or
long, sometimes abbreviated as getopt_long allows), zero to three -k keys
(POS1 and optional POS2 with field and character positions and b, f, n, r
modifiers, invalid specs now and then), -t (one byte, "\\0", or empty and
two bytes for the errors), and the ignored -S, plus -o for an output file
(the output file's bytes are compared; sometimes the input itself). Inputs
reach the tools on standard input, as one to three named files (options
before, between or after them, "--" sometimes), as "-", or as a missing
file. stdout (or the -o file) and the exit status must match. Content
groups:

  words     blank- or tab-separated fields from a small vocabulary, mixed
            case, leading blanks, many equal keys
  numbers   signed and padded numbers with fractions, long digit strings,
            '-0', '.5', '+5', byte 0x80 (GNU's C-locale thousands
            separator), words, so -n meets GNU's numcompare cases
  binary    random bytes with NULs, high bytes, no final line end
  records   NUL-terminated records for -z
  large     20 000 to 120 000 lines (every 25th case), so the long-run
            sorts and the forked workers are used: plain pools, a long
            shared prefix, a few distinct lines, long numbers, or lines
            already in order
Small word and number inputs are sometimes already in order (bytewise or
case folded, forwards or reversed), for the in-order check.
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
VOCAB = [b"alpha", b"Alpha", b"beta", b"BETA", b"gamma", b"a", b"b", b"", b"zeta", b"Zeta", b"eta", b"x.y", b"x:y", b"10", b"9", b"-3"]


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def number(rng):
    r = rng.random()
    if r < 0.5:
        s = str(rng.randint(-2000, 2000)).encode()
    elif r < 0.65:
        s = b"%d.%d" % (rng.randint(-50, 50), rng.randint(0, 999))
    elif r < 0.75:
        s = rng.choice([b"-0", b"0", b"00", b".5", b"-.5", b"0.50", b"+5", b"-", b".", b"-0.0", b"1e3", b"0x10", b"5.", b"-5.",
                        b"1\x80000", b"-\x805", b"\x80\x807", b"-0\x80.5", b"12\x80\x803.4", b"\x80-1", b"-1\x80"])
    elif r < 0.85:
        s = (rng.choice([b"", b"-"]) + bytes(rng.choice(b"0123456789") for _ in range(rng.randint(12, 30))))
        if rng.random() < 0.4:
            s += b"." + bytes(rng.choice(b"0123456789") for _ in range(rng.randint(1, 20)))
    else:
        s = rng.choice(VOCAB)
    return rng.choice([b"", b"", b" ", b"  ", b"\t"]) + s


def field(rng, numeric):
    if numeric or rng.random() < 0.2:
        return number(rng)
    return rng.choice(VOCAB)


def line(rng, numeric, sep):
    n = rng.randint(1, 5)
    out = sep.join(field(rng, numeric) for _ in range(n))
    if rng.random() < 0.15:
        out = rng.choice([b" ", b"\t", b"  "]) + out
    return out


def gen(rng, group, sep):
    if group == "words" or group == "numbers":
        pool = [line(rng, group == "numbers", sep) for _ in range(rng.randint(1, 30))]
        lines = [rng.choice(pool) for _ in range(rng.randint(0, 60))]
        if rng.random() < 0.15:
            fold = rng.random() < 0.3
            lines.sort(key=(lambda x: (x.upper(), x)) if fold else None, reverse=rng.random() < 0.3)
        t = b"".join(x + b"\n" for x in lines)
    elif group == "binary":
        t = bytes(rng.choice(b"aAb1 -.\t\n\n\x00\x80\xff\r") for _ in range(rng.randint(0, 400)))
    elif group == "records":
        pool = [line(rng, rng.random() < 0.5, sep).replace(b"\x00", b"") + rng.choice([b"", b"\nx"]) for _ in range(rng.randint(1, 12))]
        t = b"".join(rng.choice(pool) + b"\x00" for _ in range(rng.randint(0, 40)))
    else:
        # Large inputs take the forked-worker path (50,000 lines and more):
        # plain pools, a long shared prefix, a handful of distinct lines,
        # or numbers too long to pack.
        kind = rng.choice(["pool", "pool", "prefix", "few", "long", "sorted"])
        numeric = rng.random() < 0.5
        pool = [line(rng, numeric, sep) for _ in range(rng.randint(50, 3000))]
        if kind == "prefix":
            head = b"shared prefix of some length " * rng.randint(1, 3)
            pool = [head + x for x in pool]
        elif kind == "few":
            pool = pool[:rng.randint(1, 3)]
        elif kind == "long":
            pool = [b"%d%s %d" % (rng.randint(-10**12, 10**12), bytes(rng.choice(b"0123456789") for _ in range(rng.randint(0, 20))), rng.randint(0, 9)) for _ in range(rng.randint(50, 3000))]
        lines = [rng.choice(pool) for _ in range(rng.randint(20000, 120000))]
        if kind == "sorted":
            lines.sort(reverse=rng.random() < 0.3)
        t = b"".join(x + b"\n" for x in lines)
    if t and rng.random() < 0.2:
        t = t[:-1]
    return t


def key_spec(rng):
    r = rng.random()
    if r < 0.04:
        return rng.choice(["0", "1.0", "a", "1,", "1.2.3", "-1", "1,0", "2,1x", "", "1.", "99999999999999999999999"])
    spec = str(rng.randint(1, 4))
    if rng.random() < 0.3:
        spec += "." + str(rng.randint(1, 4))
    if rng.random() < 0.25:
        spec += "".join(c for c in "bfnr" if rng.random() < 0.3)
    if rng.random() < 0.7:
        spec += "," + str(rng.randint(1, 5))
        if rng.random() < 0.3:
            spec += "." + str(rng.randint(0, 4))
        if rng.random() < 0.25:
            spec += "".join(c for c in "bfnr" if rng.random() < 0.3)
    return spec


LONG = {"b": ["--ignore-leading-blanks", "--ignore-l"], "f": ["--ignore-case", "--ignore-c"], "n": ["--numeric-sort", "--nu"],
        "r": ["--reverse", "--rev"], "s": ["--stable", "--sta"], "u": ["--unique", "--un"], "z": ["--zero-terminated", "--zero"]}


def options(rng, sep_char):
    opts = []
    letters = [c for c in "bfnrsu" if rng.random() < 0.2]
    zero = rng.random() < 0.08
    if zero:
        letters.append("z")
    if letters:
        if rng.random() < 0.6:
            opts.append("-" + "".join(letters))
        else:
            opts += [rng.choice(LONG[c]) for c in letters]
    for _ in range(rng.choice([0, 0, 1, 1, 1, 2, 3])):
        spec = key_spec(rng)
        style = rng.randint(0, 3)
        if style == 0:
            opts += ["-k", spec]
        elif style == 1:
            opts += ["-k" + spec] if spec else ["-k", spec]
        elif style == 2:
            opts += ["--key=" + spec]
        else:
            opts += ["--ke", spec]
    if sep_char is not None:
        t = sep_char
        if rng.random() < 0.05:
            t = rng.choice(["", "ab", "\\0"])
        style = rng.randint(0, 2)
        if style == 0:
            opts += ["-t", t]
        elif style == 1:
            opts += ["-t" + t] if t else ["-t", t]
        else:
            opts += ["--field-separator=" + t]
        if rng.random() < 0.03:
            opts += ["-t", "%"]
    if rng.random() < 0.05:
        opts += rng.choice([["-S", "1M"], ["--buffer-size=10%"], ["--parallel=2"]])
    return opts, zero


def run(cmd, stdin_path=None):
    if stdin_path:
        with open(stdin_path, "rb") as f:
            return subprocess.run(cmd, stdin=f, capture_output=True, cwd=WORK, env=ENV, timeout=120)
    return subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, cwd=WORK, env=ENV, timeout=120)


def fail(msg, data, mine, ref):
    failures.append(msg)
    if len(failures) <= 5:
        d = os.path.join(WORK, f"fail{len(failures)}")
        os.makedirs(d, exist_ok=True)
        for name, blob in (("input", data), ("mine", mine), ("ref", ref)):
            with open(os.path.join(d, name), "wb") as f:
                f.write(blob)
        print("FAIL", msg, "->", d)


def write(name, data):
    with open(os.path.join(WORK, name), "wb") as f:
        f.write(data)


# The output file's bytes (removed afterwards unless it is the input).
def take(path):
    if not os.path.exists(path):
        return b"<none>"
    with open(path, "rb") as f:
        data = f.read()
    if not path.endswith("/in"):
        os.remove(path)
    return b"<file>" + data


def main():
    rng = random.Random(20261105)
    for case in range(CASES):
        sep_char = rng.choice([None, None, None, ":", "\t", " ", "."])
        sep = {None: rng.choice([b" ", b"\t", b"  "]), "\t": b"\t"}.get(sep_char, (sep_char or " ").encode())
        opts, zero = options(rng, sep_char)
        group = "large" if case % 25 == 24 else ("records" if zero and rng.random() < 0.7 else rng.choice(["words", "numbers", "binary", "words", "numbers"]))
        data = gen(rng, group, sep)
        mode = rng.choice(["stdin", "stdin", "named", "named", "files", "dash", "output", "inplace", "dashdash", "missing"])
        stdin_path = None
        operands = []
        out_path = None
        write("in", data)
        if mode == "stdin":
            stdin_path = os.path.join(WORK, "in")
        elif mode == "named":
            operands = ["in"]
        elif mode == "files":
            cut = rng.randint(0, len(data))
            write("in2", data[cut:])
            write("in", data[:cut])
            operands = ["in", "in2"] + (["in"] if rng.random() < 0.3 else [])
        elif mode == "dash":
            stdin_path = os.path.join(WORK, "in")
            operands = ["-"]
        elif mode == "output":
            operands = ["in"]
            opts = opts + rng.choice([["-o", "out"], ["-oout"], ["--output=out"], ["--out", "out"]])
            out_path = os.path.join(WORK, "out")
        elif mode == "inplace":
            operands = ["in"]
            opts = opts + ["-o", "in"]
            out_path = os.path.join(WORK, "in")
        elif mode == "dashdash":
            operands = ["--", "in"]
        else:
            operands = ["in", "no-such-file"]
        args = opts + operands
        if mode in ("named", "files") and rng.random() < 0.3:
            k = rng.randint(0, len(opts))
            args = opts[:k] + operands + opts[k:]
        mine = run([TOOL] + args, stdin_path)
        mine_out = mine.stdout
        if out_path:
            mine_out += take(out_path)
            if mode == "inplace":
                write("in", data)
        ref = run(["sort"] + args, stdin_path)
        ref_out = ref.stdout
        if out_path:
            ref_out += take(out_path)
        key = f"{group}/{mode}/{'ok' if ref.returncode == 0 else 'error'}"
        bump(key + "/cases")
        if mine.returncode != ref.returncode or mine_out != ref_out:
            fail(f"{key} {' '.join(args)[:200]!r} rc {mine.returncode}/{ref.returncode}", data, mine_out, ref_out)
        else:
            bump(key + "/agree")
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
