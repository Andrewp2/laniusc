"""Differential oracle: ext::fnmatch against glibc fnmatch(3) in the C locale.

    python3 -I oracle.py CASES_EXE [--seed N] [--count N]

CASES_EXE is tests/fixtures/extended/fnmatch_oracle/cases.lani built with lcc.
Every generated (pattern, name, flags) case goes to the executable in one
batch and to libc's fnmatch through ctypes, after setlocale(LC_ALL, "C").
Flags are any combination of FNM_PATHNAME, FNM_NOESCAPE, FNM_PERIOD,
FNM_LEADING_DIR and FNM_CASEFOLD. Prints per-surface agree/total and
`disagreements N`; exits 1 on any disagreement.
"""
import argparse, ctypes, random, struct, subprocess, sys, time

PATHNAME, NOESCAPE, PERIOD, LEADING_DIR, CASEFOLD = 1, 2, 4, 8, 16
TOKENS = [b"a", b"b", b"A", b".", b"/", b"\\", b"*", b"?", b"[", b"]", b"!", b"^", b"-", b":", b"=", b"z",
          b"[:alpha:]", b"[:upper:]", b"[:digit:]", b"[:space:]", b"[:punct:]", b"[:xdigit:]", b"[:foo:]", b"[:z:]",
          b"[=a=]", b"[.a.]", b"[.-.]", b"[.ab.]", b"[:", b"[=", b"[.", b"\xe9", b"5", b" ", b"**", b"*/", b"/."]
NAME_BYTES = b"abA./\\[]!^-:=z5 \xe9\t"
PATH_TOKENS = [b"*", b"?", b"a", b"b", b".", b"/", b"[ab]", b"[!a]", b"\\*", b"\\.", b"*/", b"/.", b"[.]", b"[/]", b"\\/", b"**"]


LIKELY = {b"*": None, b"**": None, b"?": None, b"[:alpha:]": b"aZq", b"[:upper:]": b"AZ", b"[:digit:]": b"059",
          b"[:space:]": b" \t", b"[:punct:]": b"!-", b"[:xdigit:]": b"aF5", b"[=a=]": b"a", b"[.a.]": b"a", b"[.-.]": b"-"}


def likely(rng, token):
    if token in (b"*", b"**"): return bytes(rng.choice(NAME_BYTES) for _ in range(rng.randint(0, 3)))
    if token == b"?": return bytes([rng.choice(NAME_BYTES)])
    if token in (b"[", b"]") and rng.random() < 0.5: return b""
    if token in LIKELY: return bytes([rng.choice(LIKELY[token])])
    if token == b"\\" and rng.random() < 0.5: return b""
    if rng.random() < 0.1: return bytes([rng.choice(NAME_BYTES)])
    return token.swapcase() if rng.random() < 0.1 else token


PATH_LIKELY = {b"[ab]": b"ab", b"[!a]": b"b.", b"\\*": b"*", b"\\.": b".", b"[.]": b".", b"[/]": b"/", b"\\/": b"/"}


def path_likely(rng, token):
    if token in (b"*", b"**"): return bytes(rng.choice(b"ab.") for _ in range(rng.randint(0, 3)))
    if token == b"*/": return bytes(rng.choice(b"ab.") for _ in range(rng.randint(0, 2))) + b"/"
    if token == b"?": return bytes([rng.choice(b"ab./")])
    if token in PATH_LIKELY: return bytes([rng.choice(PATH_LIKELY[token])])
    return token


# Malformed and boundary forms, each under all 32 flag combinations.
PINNED = [(b"*.c", b".c"), (b"?c", b".c"), (b"[.]c", b".c"), (b"\\.c", b".c"), (b"a/*", b"a/.x"), (b"a/?x", b"a/.x"),
          (b"*/.x", b"a/.x"), (b"[", b"["), (b"[a", b"[a"), (b"[]", b"[]"), (b"[]a]", b"]"), (b"[!]a]", b"]"), (b"[!]", b"[!]"),
          (b"[[:alpha:]]", b"a"), (b"[[:foo:]]", b"["), (b"[[:alpha:]", b"a"), (b"[[:alpha:]", b"[[:alpha:]"), (b"[[:z:]]", b"z"),
          (b"[[:abcdefgh]", b"["), (b"[[=a=]]", b"a"), (b"[[=a", b"[[=a"), (b"[[=]=]]", b"]"), (b"[[.a.]]", b"a"), (b"[[.", b"[[."),
          (b"[[.a.]", b"a"), (b"[[.ab.]]", b"a"), (b"[[.-.]]", b"-"), (b"[[.a.]-]", b"a"), (b"[[.a.]-]", b"-"), (b"[[.a.]-c]", b"b"),
          (b"[a-[.c.]]", b"b"), (b"[a-[=c=]]", b"b"), (b"[a-[:digit:]]", b"5"), (b"[z-a]", b"m"), (b"[a-]", b"-"), (b"[-a]", b"-"),
          (b"[a-c-e]", b"-"), (b"[a-\\c]", b"b"), (b"[a\\-c]", b"-"), (b"[\\]]", b"]"), (b"[\\]", b"\\"), (b"\\", b"\\"),
          (b"a\\", b"a\\"), (b"[a\\", b"[a\\"), (b"[a-", b"[a-"), (b"[a-\\]", b"b"), (b"[[:alpha:]\\]]", b"]"),
          (b"[a[:x]", b":"), (b"[a[=x]", b"a"), (b"[a[.x]", b"a"), (b"[/]", b"/"), (b"a[/]b", b"a/b"), (b"a[!x]b", b"a/b"),
          (b"a\\/b", b"a/b"), (b"*\\/b", b"a/b"), (b"a*/b", b"a/x/b"), (b"*/b", b"x/y/b"), (b"a*", b"a/b"), (b"a/b", b"a/b/c"),
          (b"a?", b"a/"), (b"*", b"x/y"), (b"*?[.]", b"a."), (b"A", b"a"), (b"[A-C]", b"b"), (b"[[:upper:]]", b"a"),
          (b"[[.A.]]", b"a"), (b"[[=A=]]", b"a"), (b"\xe9", b"\xc9"), (b"?", b"\xe9"), (b"[!a]", b""), (b"*", b""), (b"", b"")]


def generate(rng, count):
    cases = {"pinned": [(p, n, fl) for p, n in PINNED for fl in range(32)], "brackets": [], "paths": [], "names": [], "errors": []}
    for _ in range(count):
        mode = rng.random()
        if mode < 0.3:
            tokens = [rng.choice(PATH_TOKENS) for _ in range(rng.randint(0, 8))]
            pat = b"".join(tokens)
            if rng.random() < 0.5: name = b"".join(path_likely(rng, t) for t in tokens)
            else: name = bytes(rng.choice(b"ab./") for _ in range(rng.randint(0, 14)))
            surface = "paths"
        elif mode < 0.32:
            pat = b"[[:" + bytes(rng.choice(b"abcxyz") for _ in range(rng.randint(250, 260))) + rng.choice([b":]]", b"1]", b"]"])
            name = rng.choice([b"a", b"[", b":", b"1"])
            surface = "brackets"
        else:
            tokens = [rng.choice(TOKENS) for _ in range(rng.randint(0, 10))]
            pat = b"".join(tokens)
            if rng.random() < 0.6:
                # A name that follows the tokens, so that many cases match.
                name = b"".join(likely(rng, t) for t in tokens)
            else:
                name = bytes(rng.choice(NAME_BYTES) for _ in range(rng.randint(0, 9)))
            surface = "brackets" if b"[" in pat else "names"
        cases[surface].append((pat, name, rng.randrange(32)))
    # NUL ends either string, as in C; unknown flag bits are an error.
    for _ in range(max(1, count // 100)):
        pat = b"".join(rng.choice(TOKENS) for _ in range(rng.randint(0, 4)))
        name = bytes(rng.choice(NAME_BYTES) for _ in range(rng.randint(0, 4)))
        cut = rng.randint(0, len(pat))
        cases["names"].append((pat[:cut] + b"\0" + pat[cut:], name + b"\0" + b"x", rng.randrange(32)))
        cases["errors"].append((pat, name, rng.choice([32, 64, -1, 1 << 20])))
    return cases


def run(exe, cases):
    blob = b"".join(struct.pack("<iII", fl, len(p), len(n)) + p + n for p, n, fl in cases)
    out = subprocess.run([exe], input=blob, capture_output=True, timeout=250)
    if out.returncode != 0 or len(out.stdout) != len(cases):
        sys.exit(f"cases executable failed: status {out.returncode}, {len(out.stdout)} answers for {len(cases)}")
    return out.stdout


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("exe"); ap.add_argument("--seed", type=int, default=20261101); ap.add_argument("--count", type=int, default=200000)
    args = ap.parse_args()
    libc = ctypes.CDLL("libc.so.6"); libc.setlocale.restype = ctypes.c_char_p
    if libc.setlocale(6, b"C") != b"C": sys.exit("setlocale failed")
    fn = libc.fnmatch; fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]; fn.restype = ctypes.c_int
    print(f"python {sys.version.split()[0]} seed {args.seed}")
    cases = generate(random.Random(args.seed), args.count)
    total_bad = 0
    for surface, items in cases.items():
        got = run(args.exe, items); bad = 0
        for (p, n, fl), answer in zip(items, got):
            want = ord("E") if surface == "errors" else ord("0") if fn(p, n, fl) == 0 else ord("1")
            if answer != want:
                bad += 1
                if bad <= 5: print(f"  DIFF {surface} pattern={p!r} name={n!r} flags={fl} libc={chr(want)} lanius={chr(answer)}")
        matched = sum(1 for a in got if a == ord("0"))
        print(f"{surface} {len(items) - bad}/{len(items)}" + (f" ({matched} matches)" if surface != "errors" else ""))
        total_bad += bad
    # Many stars against a long name: backtracking only to the last star.
    slow = [(b"*a" * 40 + b"b", b"a" * 4000, 0), (b"*a*a*a*a*a*a*a*a*?b", b"a" * 20000, PATHNAME), (b"*/" * 50 + b"x", b"a/" * 2000, PATHNAME | PERIOD)]
    start = time.perf_counter(); got = run(args.exe, slow); elapsed = time.perf_counter() - start
    bad = sum(1 for a in got if a != ord("1"))
    print(f"linear_time {len(slow) - bad}/{len(slow)} in {elapsed:.2f} s"); total_bad += bad
    print(f"disagreements {total_bad}")
    sys.exit(1 if total_bad else 0)


main()
