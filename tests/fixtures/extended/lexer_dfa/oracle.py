"""Side-by-side check: the combined-DFA ext::lexer against the frozen per-rule
VM lexer (root/ext/lexer_vm.lani, the previous ext::lexer verbatim).

usage: python3 -I oracle.py COMPARE_EXE [--seed N] [--count N] [--bench]

Each generated case is a rule list, an input and a set of limits. The
comparator runs both lexers on it and writes one trace line for each. A trace
holds every token (id@start-end), the terminal `.` or error with its payloads,
and the final Usage (steps, tokens, calls, reserved work). Agreement means the
two lines are byte-identical.

Rules mix lexer-shaped patterns with grammar-generated regexes from
../regex_oracle/oracle.py. Some rules contain assertions, which the DFA omits
and the VM still probes. Limits sometimes cut steps, tokens, calls, reserved
work or the per-search VM budget, so that every error and fallback path runs.

--bench times new against old lexing of one 0.9 MB expression corpus with an
18-rule operator lexer and with a 5-rule one.
"""

import os
import random
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "regex_oracle"))
import oracle as regex_oracle  # noqa: E402

LEXER_RULES = [r"[0-9]+", r"[a-z]+", r"[A-Za-z_][A-Za-z_0-9]*", r"[ \t]+", r"\n", r"\+", r"-", r"\*\*", r"\*",
               r"//", r"/", r"[-+*/%(),]", r"\(", r"\)", r"[0-9]+(?:\.[0-9]+)?", r"\"[^\"\n]*\"", r"#[^\n]*",
               r"a|ab|abc", r"(?:ab)*", r"a*", r"\s*", r".", r"[^\n]", r"é+|🙂", r"\p{L}+", r"\bab", r"^a",
               r"a$", r"\w+\b", r"(a|b)*c", r"x{2,4}?", r"[\d\w]{1,3}"]
INPUT_ALPHABET = list("aaabbbcxy0123 \t\n+-*/%(),._\"#AZ") + ["é", "🙂"]


# Each needs more DFA states than its cache holds, forcing the VM fallback.
BLOWUP_RULES = [r"[ab]*a[ab]{7}", r"(?:a|b)*b(?:a|b){9}", r"(?:[ab]*a[ab]{5}|[ab]*b[ab]{6})x?"]


def rule_set(rng):
    rules = []
    for _ in range(rng.randint(1, 8)):
        if rng.random() < 0.6:
            pattern = rng.choice(LEXER_RULES)
        else:
            pattern, _ = regex_oracle.pattern(rng, False)
        rules.append((rng.randint(-3, 40), rng.random() < 0.2, pattern))
    # A trailing catch-all lets most inputs lex to the end.
    if rng.random() < 0.6:
        rules.append((99, rng.random() < 0.3, rng.choice([r"[^\n]|\n", r"[\s\S]", r".|\n"])))
    return rules


def text(rng, hi):
    return "".join(rng.choice(INPUT_ALPHABET) for _ in range(rng.randint(0, hi)))


def case(mode, rules, data, steps=1000000, tokens=1000000, calls=4000000, work=2**31 - 1,
         regex_work=10000000, multiline=0):
    raw = data.encode()
    head = struct.pack("<9I", mode, len(rules), len(raw), steps, tokens, calls, work, regex_work, multiline)
    body = b""
    for ident, skip, pattern in rules:
        p = pattern.encode()
        body += struct.pack("<iII", ident, 1 if skip else 0, len(p)) + p
    return head + body + raw


def generated(rng, count):
    cases = []
    for _ in range(count):
        rules = rule_set(rng)
        data = text(rng, rng.choice([8, 24, 80]))
        if rng.random() < 0.05:
            rules = [(1, False, rng.choice(BLOWUP_RULES)), (2, False, r"[abx]"), (-1, True, r"\s+")]
            data = "".join(rng.choice("aabab" * 8 + " ") for _ in range(rng.randint(50, 600)))
        limits = {}
        r = rng.random()
        if r < 0.08: limits["steps"] = rng.randint(0, 6)
        elif r < 0.16: limits["tokens"] = rng.randint(0, 4)
        elif r < 0.24: limits["calls"] = rng.randint(0, 20)
        elif r < 0.32: limits["work"] = rng.randint(0, 10) * 10000
        elif r < 0.44: limits["regex_work"] = rng.randint(1, 400)
        if rng.random() < 0.2: limits["multiline"] = 1
        cases.append(case(0, rules, data, **limits))
    return cases


def compare(exe, rng, count):
    cases = generated(rng, count)
    result = subprocess.run([exe], input=b"".join(cases), capture_output=True, timeout=240)
    lines = result.stdout.decode().split("\n")[:-1]
    if result.returncode != 0 or len(lines) != 2 * count:
        print(f"harness failed: status {result.returncode}, {len(lines)}/{2 * count} lines")
        return count, count
    same, kinds, examples, rebuilt = 0, {}, [], 0
    for i in range(count):
        a, b = lines[2 * i][2:], lines[2 * i + 1][2:]
        # The new trace ends with " R<cache rebuilds>", an observation only.
        if " R" in a:
            a, resets = a.rsplit(" R", 1)
            if int(resets) > 1:
                rebuilt += 1
        if a == b:
            same += 1
            end = a.split(" U")[0].rsplit(";", 1)[-1]
            key = "ok" if end.endswith(".") else "error " + end.split(":")[0].lstrip("E")
            kinds[key] = kinds.get(key, 0) + 1
        elif len(examples) < 6:
            examples.append((i, a, b))
    print(f"lexer_traces {same}/{count}")
    print(f"  cases whose DFA cache filled and was rebuilt: {rebuilt}")
    print("  outcomes: " + ", ".join(f"{k}: {v}" for k, v in sorted(kinds.items())))
    for i, a, b in examples:
        print(f"  mismatch {i}:\n    new {a}\n    old {b}")
    return count - same, count


def bench(exe):
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pratt_oracle", "oracle.py")
    spec = importlib.util.spec_from_file_location("pratt_oracle", path)
    pratt_oracle = importlib.util.module_from_spec(spec); spec.loader.exec_module(pratt_oracle)
    r = random.Random(1)
    corpus = "".join(pratt_oracle.render(r, pratt_oracle.expr(r, r.randint(1, 6))) + "\n" for _ in range(25000))
    wide = [(0, False, r"[0-9]+"), (1, False, r"[a-z]+")] + [(i + 2, False, p) for i, p in enumerate(
        [r"\|", r"\^", "&", "<<", ">>", r"\+", "-", r"\*", "//", "%", "~", r"\*\*", r"\(", r"\)", ","])] + [(-1, True, r"[ \t\n]+")]
    narrow = [(0, False, r"[0-9]+"), (1, False, r"[a-z]+"), (100, False, r"\*\*|//|<<|>>"),
              (101, False, r"[-+*%&|^~(),]"), (-1, True, r"[ \t\n]+")]
    print(f"corpus {len(corpus.encode())} bytes")
    for name, rules in (("18 rules", wide), ("5 rules", narrow)):
        for mode, label in ((1, "new"), (2, "old")):
            began = time.monotonic()
            result = subprocess.run([exe], input=case(mode, rules, corpus, calls=2000000000, regex_work=10000), capture_output=True, timeout=240)
            print(f"  {name} {label}: {time.monotonic() - began:.3f} s, tokens {result.stdout.decode().strip()}, status {result.returncode}")


def main():
    args = sys.argv[1:]
    seed, count = 20261031, 6000
    if "--seed" in args:
        i = args.index("--seed"); seed = int(args[i + 1]); del args[i:i + 2]
    if "--count" in args:
        i = args.index("--count"); count = int(args[i + 1]); del args[i:i + 2]
    run_bench = "--bench" in args
    if run_bench:
        args.remove("--bench")
    (exe,) = args
    print(f"seed {seed}")
    bad, _ = compare(exe, random.Random(seed), count)
    if run_bench:
        bench(exe)
    print(f"disagreements {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
