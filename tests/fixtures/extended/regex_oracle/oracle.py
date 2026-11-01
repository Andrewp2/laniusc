"""Differential oracle: ext::regex programs against CPython `re`.

usage: python3 -I oracle.py INPUT_EXE REPLACE_EXE GREP_EXE [--dfa DFA_EXE] [--seed N] [--patterns N]

INPUT_EXE is tests/fixtures/extended_library/regex_input.lani (find_iter with
captures over a binary case stream), REPLACE_EXE is
sample_programs/library/regex_replace.lani and GREP_EXE is
sample_programs/library/text_grep.lani. Patterns come from a seeded grammar
restricted to the dialect both engines share; every case is generated, never
hand-picked. The script prints one `surface agree/total` line per surface and
`disagreements N`; it exits 1 when any case disagrees.

Shared subset (see docs/extended-regex-oracle.md):
- literals, escaped punctuation, \\xHH, \\x{H..}, \\t, \\n;
- `.`, classes with literals, ranges and ASCII shorthands, negation;
- ^ $ \\A \\z \\b \\B (never directly quantified);
- * + ? {n} {n,} {n,m} and lazy forms; | ( ) (?: );
- re.ASCII on the Python side; `$` and `\\z` map to `\\Z` without multiline;
- quantifiers other than `?` apply only to bodies that cannot match empty,
  because the Pike VM's empty-iteration policy is documented to differ.
Inputs and records are nonempty when the pattern contains \\B: CPython 3.12
does not match \\B in empty text (3.14 does, as ext::regex and RE2 do).
Inputs never contain VT, the one ASCII whitespace scalar where `\\s` differs.
Iteration follows the shared canonical progress rule (search from the end of
the last match; after an empty match advance one scalar), which Python's own
finditer/sub do not use, so the Python side runs that loop explicitly.
"""

import random
import re
import struct
import subprocess
import sys

INPUT_ALPHABET = list("aaaaabbbbccA1_ .-\t\n") + ["é", "🙂"]
LITERALS = [("a", "a")] * 6 + [("b", "b")] * 5 + [("c", "c")] * 2 + [
    ("A", "A"), ("1", "1"), ("_", "_"), (" ", " "), ("-", "-"),
    ("é", "é"), ("🙂", "🙂"), (r"\.", r"\."), (r"\-", r"\-"),
    (r"\x61", r"\x61"), (r"\x{e9}", "é"), (r"\x{1f642}", "🙂"),
    (r"\t", r"\t"), (r"\n", r"\n"),
]
CLASS_TERMS = ["a", "b", "c", "é", "1", "_", ".", " ", "a-c", "0-9", "A-Z",
               "é-🙂", r"\d", r"\w", r"\s", r"\D", r"\W", r"\S", r"\n"]
NAMES = ["n", "word", "x_", "Key", "_g"]
SHORTHANDS = [r"\d", r"\w", r"\s", r"\D", r"\W", r"\S"]
QUANTIFIERS = ["?", "*", "+", "{2}", "{1,2}", "{0,2}", "{2,}", "??", "*?",
               "+?", "{1,2}?", "{0,3}?", "{2,}?", "{1}", "{0}"]


class Gen:
    def __init__(self, rng, multiline, lookbehind=0.0, captures=True):
        self.rng = rng
        self.multiline = multiline
        self.groups = 0
        self.names = []
        # Chance that an assertion slot becomes (?<=...) or (?<!...). Zero
        # keeps the random stream of the older surfaces unchanged.
        self.lookbehind = lookbehind
        self.captures = captures
        self.behinds = 0

    def behind(self, depth):
        """A capture-free lookbehind. Fixed counts make most bodies fixed
        width; the rest exercise Python's fixed-width rejection."""
        body = Gen(self.rng, self.multiline, self.lookbehind * 0.5, captures=False)
        body.fixed = self.rng.random() < 0.8
        lan, py, _ = body.expr(min(depth, 1))
        self.behinds += 1 + body.behinds
        opener = self.rng.choice(["(?<=", "(?<!"])
        return opener + lan + ")", opener + py + ")"

    def assertion(self):
        kind = self.rng.choice(["^", "$", r"\A", r"\z", r"\b", r"\B"])
        if kind == "$":
            return ("$", "$" if self.multiline else r"\Z")
        if kind == r"\z":
            return (r"\z", r"\Z")
        return (kind, kind)

    def klass(self):
        terms = [self.rng.choice(CLASS_TERMS) for _ in range(self.rng.randint(1, 3))]
        body = "".join(terms)
        neg = "^" if self.rng.random() < 0.3 else ""
        return ("[" + neg + body + "]",) * 2

    def atom(self, depth):
        """Return (lanius, python, nullable, quantifiable)."""
        r = self.rng.random()
        if r < 0.42:
            lan, py = self.rng.choice(LITERALS)
            return lan, py, False, True
        if r < 0.50:
            return ".", ".", False, True
        if r < 0.62:
            lan, py = self.klass()
            return lan, py, False, True
        if r < 0.68:
            s = self.rng.choice(SHORTHANDS)
            return s, s, False, True
        if r < 0.76:
            if self.lookbehind and self.rng.random() < self.lookbehind:
                lan, py = self.behind(depth)
                return lan, py, True, False
            lan, py = self.assertion()
            return lan, py, True, False
        if depth <= 0:
            lan, py = self.rng.choice(LITERALS)
            return lan, py, False, True
        capture = self.rng.random() < 0.6 and self.captures
        if capture:
            self.groups += 1
        lan, py, nullable = self.expr(depth - 1)
        if capture:
            # Some captures are named, in either Lanius spelling; Python only
            # has (?P<name>...). Names stay unique within a pattern.
            if self.rng.random() < 0.35:
                name = self.rng.choice(NAMES) + str(len(self.names))
                self.names.append(name)
                opener = self.rng.choice(["(?P<", "(?<"]) + name + ">"
                return opener + lan + ")", "(?P<" + name + ">" + py + ")", nullable, True
            return "(" + lan + ")", "(" + py + ")", nullable, True
        return "(?:" + lan + ")", "(?:" + py + ")", nullable, True

    def piece(self, depth):
        lan, py, nullable, quantifiable = self.atom(depth)
        if not quantifiable or self.rng.random() < 0.55:
            return lan, py, nullable
        if nullable:
            q = self.rng.choice(["?", "??"])
        elif getattr(self, "fixed", False):
            q = self.rng.choice(["{2}", "{1}", "{0}", "{3}", "{2}?"])
        else:
            q = self.rng.choice(QUANTIFIERS)
        bare = q.rstrip("?") or "?"
        if bare in ("?", "*") or bare.startswith("{0"):
            nullable = True
        return lan + q, py + q, nullable

    def concat(self, depth):
        count = self.rng.choice([0, 1, 1, 2, 2, 3])
        lan, py, nullable = "", "", True
        for _ in range(count):
            a, b, n = self.piece(depth)
            lan, py, nullable = lan + a, py + b, nullable and n
        return lan, py, nullable

    def expr(self, depth):
        branches = 1 if self.rng.random() < 0.7 else self.rng.randint(2, 3)
        parts = [self.concat(depth) for _ in range(branches)]
        return ("|".join(p[0] for p in parts), "|".join(p[1] for p in parts),
                any(p[2] for p in parts))


def pattern(rng, multiline):
    """One quarter of patterns nest three groups deep, the rest two."""
    depth = 3 if rng.random() < 0.25 else 2
    while True:
        g = Gen(rng, multiline)
        lan, py, _ = g.expr(depth)
        if lan and g.groups <= 8 and len(lan) <= 160:
            return lan, py


def behind_pattern(rng, multiline):
    """A pattern with at least one lookbehind. Python either compiles it or
    rejects it only for lookbehind width; returns (lan, py, error)."""
    while True:
        g = Gen(rng, multiline, lookbehind=0.6)
        lan, py, _ = g.expr(2)
        if not g.behinds or g.groups > 8 or len(lan) > 160:
            continue
        try:
            re.compile(py, re.ASCII)
            return lan, py, False
        except re.error as e:
            if "look-behind requires fixed-width pattern" in str(e):
                return lan, py, True


# Reductions of disagreements this oracle found; they stay in every run.
# Lazy counted repeats once expanded x{0,2}? as x??x??, preferring every
# single iteration over a second one.
PINNED = [
    (r"(?:a|aab){0,2}?b", "aabb"),
    (r"(a|1b|a1b){0,2}?\.", "a1b."),
    (r"([a1]b*|\S{2,}){0,3}? ", "a1b "),
    (r"(a??((a+\t{1,2})a|([^b]+?)){0,3}?)a{1,2}", "-1ccaaac\t🙂_ a"),
    (r"_|\x61*?\x{1f642}+?|((b)+?c{0,2}){0,3}?a", "🙂_céab1aacb1🙂bba."),
]


def text(rng, lo=0, hi=10):
    return "".join(rng.choice(INPUT_ALPHABET) for _ in range(rng.randint(lo, hi)))


def byte_offset(s, i):
    return len(s[:i].encode())


def canonical(q, t):
    """Yield matches using the shared canonical progress rule."""
    position = 0
    while position <= len(t):
        m = q.search(t, position)
        if m is None:
            return
        yield m
        position = m.end() + (m.start() == m.end())


def names(q):
    by_group = {v: k for k, v in q.groupindex.items()}
    return "|" + ",".join(by_group.get(g, "-") for g in range(1, q.groups + 1))


def describe(q, t):
    out = ""
    for m in canonical(q, t):
        spans = []
        for group in range(q.groups + 1):
            s, e = m.span(group)
            spans.append("-" if s < 0 else f"{byte_offset(t, s)},{byte_offset(t, e)}")
        out += "M" + "/".join(spans) + ";"
    return out or "N"


def header(lan, t, flags):
    p, b = lan.encode(), t.encode()
    return struct.pack("<9I", len(p), len(b), flags, 4096, 16, 10_000_000, 64,
                       1000, 65536) + p + b


def run(argv, data, timeout=30):
    return subprocess.run(argv, input=data, capture_output=True, timeout=timeout)


def report(name, agree, total, failures):
    print(f"{name} {agree}/{total}")
    for item in failures[:8]:
        print(f"  {name} mismatch: {item!r}")


def find_iter_surface(exe, rng, count):
    cases, expected = [], []
    for lan, t in PINNED:
        py = lan.replace(r"\x{1f642}", "🙂")
        cases.append((lan, py, t, 0))
        expected.append(describe(re.compile(py, re.ASCII), t))
    for _ in range(count):
        flags = (1 if rng.random() < 0.25 else 0) | (2 if rng.random() < 0.25 else 0) | 4
        lan, py = pattern(rng, flags & 1)
        q = re.compile(py, re.ASCII | (re.M if flags & 1 else 0) | (re.S if flags & 2 else 0))
        for _ in range(4):
            t = text(rng, 1 if r"\B" in lan else 0)
            cases.append((lan, py, t, flags))
            expected.append(describe(q, t) + names(q))
    payload = b"".join(header(lan, t, flags) for lan, _, t, flags in cases)
    result = run([exe], payload, timeout=120)
    actual = result.stdout.decode().split("\n")[:-1]
    if result.returncode != 0 or len(actual) != len(cases):
        print(f"find_iter harness failed: status {result.returncode}, "
              f"{len(actual)}/{len(cases)} lines")
        return 0, len(cases), [("harness", result.returncode)]
    failures = [(cases[i], expected[i], actual[i])
                for i in range(len(cases)) if expected[i] != actual[i]]
    named = sum(any(c not in "-," for c in e.split("|", 1)[1]) for e in expected if "|" in e)
    matched = sum(not e.startswith("N") for e in expected)
    multi = sum(e.count("M") > 1 for e in expected)
    unset = sum("/-" in e for e in expected)
    grouped = sum("/" in e for e in expected)
    print(f"  find_iter_captures coverage: {count} generated patterns, {len(PINNED)} pinned, {matched} cases with a match, "
          f"{multi} with several matches, {grouped} with capture groups, "
          f"{unset} with an unset group, {named} with named groups")
    return len(cases) - len(failures), len(cases), failures


def header_work(lan, t, flags, work):
    p, b = lan.encode(), t.encode()
    return struct.pack("<9I", len(p), len(b), flags, 4096, 16, work, 64, 1000, 65536) + p + b


def dfa_surface(exe, rng, count):
    """ext::regex::Dfa is_match/find_span, one-shot and reusable, against Python
    and the VM. A tenth of cases use a tiny per-search work budget, so the DFA
    must fall back exactly; those compare the DFA with the VM only."""
    cases, expected = [], []
    for _ in range(count):
        flags = (1 if rng.random() < 0.25 else 0) | (2 if rng.random() < 0.25 else 0)
        # Assertions are DFA state; a tenth of patterns have lookbehind, which
        # dfa() must refuse so that the VM answers.
        error = True
        if rng.random() < 0.1:
            lan, py, error = behind_pattern(rng, flags & 1)
        if error:
            lan, py = pattern(rng, flags & 1)
        q = re.compile(py, re.ASCII | (re.M if flags & 1 else 0) | (re.S if flags & 2 else 0))
        # CPython backtracks exponentially on long inputs under quantified
        # groups, so those patterns get at most 20 scalars; others up to 400.
        quantified = re.search(r"\)[*+?{]", py) is not None
        t = text(rng, 1 if r"\B" in lan else 0, min(rng.choice([10, 40, 400]), 20 if quantified else 400))
        work = rng.choice([1, 20, 200]) if rng.random() < 0.1 else 10_000_000
        m = q.search(t)
        b = "0" if m is None else "1"
        span = "N" if m is None else f"{byte_offset(t, m.start())},{byte_offset(t, m.end())}"
        cases.append((lan, t, flags, work))
        expected.append(None if work != 10_000_000 else f"{b} {b} {span} {span} {span}{b}")
    payload = b"".join(header_work(lan, t, flags, work) for lan, t, flags, work in cases)
    result = run([exe], payload, timeout=120)
    actual = result.stdout.decode().split("\n")[:-1]
    if result.returncode != 0 or len(actual) != len(cases):
        print(f"dfa harness failed: status {result.returncode}, {len(actual)}/{len(cases)} lines")
        return 0, len(cases), [("harness", result.returncode)]
    failures, built, budget, asserting, behind = [], 0, 0, 0, 0
    for case, want, got in zip(cases, expected, actual):
        body, kind = got.rsplit(" ", 1)
        built += kind == "D"
        lookbehind = "(?<=" in case[0] or "(?<!" in case[0]
        behind += kind == "V"
        bare = case[0].replace("[^", "[")
        asserting += not lookbehind and any(a in bare for a in ("^", "$", r"\A", r"\z", r"\b", r"\B"))
        # Lookbehind inside a {0} repeat compiles away, so only patterns
        # without lookbehind are required to get a Dfa.
        if kind != "D" and not lookbehind:
            failures.append((case, "D", got))
            continue
        if want is None:
            budget += 1
            dm, vm, ds, vs, again = body.split(" ")
            ok = dm == vm and ds == vs and again == vs + vm
        else:
            ok = body == want
        if not ok:
            failures.append((case, want, got))
    print(f"  dfa_match_find coverage: {built} with a Dfa ({asserting} with assertions), "
          f"{behind} lookbehind patterns on the VM, {budget} with a tiny work budget")
    return len(cases) - len(failures), len(cases), failures


def linear_surface(exe):
    """Inputs where a backtracking engine is exponential or quadratic.

    No Python oracle runs here: CPython backtracks on these. The expected
    result is derived by hand and the elapsed time is reported.
    """
    import time
    n = 30
    cases = [
        ("(?:a?){%d}a{%d}" % (n, n), "a" * n, f"M0,{n};"),
        ("(a+)+b", "a" * 20000, "N"),
        ("(a|aa)*c", "a" * 20000, "N"),
        ("(?:a|a)*b", "a" * 20000, "N"),
        ("(x+x+)+y", "x" * 20000, "N"),
        # Quadratic for a backtracking search; a lookbehind at every boundary.
        ("(?:(?<=(?:a|a){8})a)+b", "a" * 20000, "N"),
    ]
    payload = b"".join(header(lan, t, 0) for lan, t, _ in cases)
    began = time.monotonic()
    result = run([exe], payload, timeout=120)
    elapsed = time.monotonic() - began
    actual = result.stdout.decode().split("\n")[:-1]
    failures = [(c[0], c[2], a) for c, a in zip(cases, actual) if c[2] != a]
    if result.returncode != 0 or len(actual) != len(cases):
        failures.append(("harness", result.returncode, len(actual)))
    print(f"  linear_time: {len(cases)} pathological cases in {elapsed:.2f} s")
    return len(cases) - len(failures), len(cases), failures


def template(rng, groups):
    pieces_lan, refs = "", []
    for _ in range(rng.randint(1, 4)):
        r = rng.random()
        if r < 0.35:
            word = rng.choice(["<", ">", "x", "é", "-", "\\", "[]"])
            pieces_lan += word
            refs.append(("lit", word))
        elif r < 0.45:
            pieces_lan += "$$"
            refs.append(("lit", "$"))
        else:
            n = rng.randint(0, groups)
            pieces_lan += f"${{{n}}}" if rng.random() < 0.5 else f"${n}"
            refs.append(("group", n))
    # `$N` consumes every following digit; no literal piece begins with one.
    return pieces_lan, refs


def substitute(q, t, refs):
    out, last = [], 0
    for m in canonical(q, t):
        out.append(t[last:m.start()])
        for kind, value in refs:
            out.append(value if kind == "lit" else (m.group(value) or ""))
        last = m.end()
    out.append(t[last:])
    return "".join(out)


def replace_surface(exe, rng, count):
    agree, failures = 0, []
    for _ in range(count):
        lan, py = pattern(rng, False)
        q = re.compile(py, re.ASCII)
        tpl, refs = template(rng, q.groups)
        t = text(rng, 1 if r"\B" in lan else 0, 16)
        want = substitute(q, t, refs).encode()
        result = run([exe, "--", "template", lan, tpl], t.encode())
        if result.returncode == 0 and result.stdout == want and not result.stderr:
            agree += 1
        else:
            failures.append((lan, tpl, t, want, result.returncode, result.stdout, result.stderr))
    return agree, count, failures


def grep_surface(exe, rng, count):
    agree, failures = 0, []
    for _ in range(count):
        lan, py = pattern(rng, False)
        q = re.compile(py, re.ASCII)
        lo = 1 if r"\B" in lan else 0
        lines = [text(rng, lo, 8).replace("\n", "") or "a" * lo for _ in range(rng.randint(0, 12))]
        data = "".join(line + "\n" for line in lines)
        flags = rng.choice(["", "-v", "-n", "-c", "-vn", "-vc"])
        selected = [(i + 1, l) for i, l in enumerate(lines)
                    if (q.search(l) is not None) != ("v" in flags)]
        if "c" in flags:
            want = f"{len(selected)}\n"
        elif "n" in flags:
            want = "".join(f"{n}:{l}\n" for n, l in selected)
        else:
            want = "".join(l + "\n" for _, l in selected)
        status = 0 if selected else 1
        argv = [exe] + ([flags] if flags else []) + ["--", lan]
        result = run(argv, data.encode())
        if result.returncode == status and result.stdout == want.encode() and not result.stderr:
            agree += 1
        else:
            failures.append((lan, flags, data, want, status, result.returncode, result.stdout, result.stderr))
    return agree, count, failures


def lookbehind_surface(exe, rng, count):
    """(?<=...) and (?<!...), nested and inside generated patterns, through
    the find_iter/captures harness. A pattern Python rejects for lookbehind
    width must be a Lanius Syntax error."""
    cases, expected = [], []
    rejected = 0
    for _ in range(count):
        flags = (1 if rng.random() < 0.25 else 0) | (2 if rng.random() < 0.25 else 0) | 4
        lan, py, error = behind_pattern(rng, flags & 1)
        if error:
            rejected += 1
            cases.append((lan, py, "a", flags))
            expected.append(None)
            continue
        q = re.compile(py, re.ASCII | (re.M if flags & 1 else 0) | (re.S if flags & 2 else 0))
        for _ in range(4):
            t = text(rng, 1 if r"\B" in lan else 0, rng.choice([10, 20]))
            cases.append((lan, py, t, flags))
            expected.append(describe(q, t) + names(q))
    payload = b"".join(header(lan, t, flags) for lan, _, t, flags in cases)
    result = run([exe], payload, timeout=120)
    actual = result.stdout.decode().split("\n")[:-1]
    if result.returncode != 0 or len(actual) != len(cases):
        print(f"lookbehind harness failed: status {result.returncode}, {len(actual)}/{len(cases)} lines")
        return 0, len(cases), [("harness", result.returncode)]
    failures = []
    for case, want, got in zip(cases, expected, actual):
        ok = got.startswith("E1:") if want is None else got == want
        if not ok:
            failures.append((case, want, got))
    found = [e for e in expected if e is not None]
    matched = sum(not e.startswith("N") for e in found)
    negative = sum("(?<!" in c[0] for c in cases)
    nested = sum(c[0].count("(?<=") + c[0].count("(?<!") > 1 for c in cases)
    print(f"  lookbehind coverage: {count} patterns, {rejected} rejected for width, {len(found)} find cases, "
          f"{matched} with a match, {negative} with negative lookbehind, {nested} with two or more lookbehinds")
    return len(cases) - len(failures), len(cases), failures


def main():
    args = sys.argv[1:]
    seed, patterns = 20261031, 3000
    if "--seed" in args:
        i = args.index("--seed"); seed = int(args[i + 1]); del args[i:i + 2]
    if "--patterns" in args:
        i = args.index("--patterns"); patterns = int(args[i + 1]); del args[i:i + 2]
    dfa_exe = None
    if "--dfa" in args:
        i = args.index("--dfa"); dfa_exe = args[i + 1]; del args[i:i + 2]
    input_exe, replace_exe, grep_exe = args
    print(f"python {sys.version.split()[0]} seed {seed}")
    total_failures = 0
    for name, surface, exe, count in [
        ("find_iter_captures", find_iter_surface, input_exe, patterns),
        ("replace_template", replace_surface, replace_exe, patterns // 3),
        ("grep_filter", grep_surface, grep_exe, patterns // 3),
    ]:
        agree, total, failures = surface(exe, random.Random(f"{seed}:{name}"), count)
        report(name, agree, total, failures)
        total_failures += total - agree
    agree, total, failures = lookbehind_surface(input_exe, random.Random(f"{seed}:lookbehind"), patterns // 3)
    report("lookbehind_find", agree, total, failures)
    total_failures += total - agree
    if dfa_exe:
        agree, total, failures = dfa_surface(dfa_exe, random.Random(f"{seed}:dfa"), patterns)
        report("dfa_match_find", agree, total, failures)
        total_failures += total - agree
    for name, surface, exe in [("linear_time", linear_surface, input_exe)]:
        agree, total, failures = surface(exe)
        report(name, agree, total, failures)
        total_failures += total - agree
    print(f"disagreements {total_failures}")
    return 1 if total_failures else 0


if __name__ == "__main__":
    sys.exit(main())
