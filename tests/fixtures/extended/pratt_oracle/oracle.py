"""Differential oracle: sample_programs/library/pratt_calc.lani against CPython.

usage: python3 -I oracle.py PRATT_CALC_EXE [--seed N] [--count N]

The Lanius program tokenizes each stdin line with ext::lexer, parses it with
ext::pratt using Python's precedence and associativity, and evaluates the
postfix events in checked i64. The oracle never uses the Lanius parser's
rules. CPython's own parser (`ast.parse(..., mode="eval")`) fixes the tree
shape. A small evaluator over that tree applies the same i64 semantics:
- `//` and `%` floor, as Python does;
- `**` with a negative exponent, and shifts by a negative count, are `domain`;
- any intermediate value outside i64 is `overflow`;
- `abs` takes one argument and `min`/`max` take at least two (`arity`);
- a function name is valid only as a callee (`name`).
Errors follow postorder evaluation: operands first, left to right, then the
operator. A call evaluates its callee and its arguments before checking them.

Two input families are generated. Well-formed expressions come from a grammar
over every operator, with random spacing and optional parentheses. Token soup
is random token sequences, most of which CPython rejects. A soup line with `,`
directly before `)` is expected to be a syntax error. CPython accepts that
trailing comma; ext::pratt deliberately does not.
Output lines are a decimal value or `error <class number>`.
"""

import ast
import random
import subprocess
import sys
import warnings

MIN, MAX = -(1 << 63), (1 << 63) - 1
SYNTAX, OVERFLOW, ZERO, DOMAIN, NAME, ARITY = 1, 2, 3, 4, 5, 6
BINARY = ["|", "^", "&", "<<", ">>", "+", "-", "*", "//", "%", "**"]
UNARY = ["-", "+", "~"]
FUNCS = ["abs", "min", "max"]


class Fail(Exception):
    def __init__(self, kind):
        self.kind = kind


def fit(v):
    if v < MIN or v > MAX:
        raise Fail(OVERFLOW)
    return v


def ev(node):
    """Return an int, or ("fn", name) for a bare function name."""
    if isinstance(node, ast.Expression):
        v = ev(node.body)
        if not isinstance(v, int):
            raise Fail(NAME)
        return v
    if isinstance(node, ast.Constant) and type(node.value) is int:
        return fit(node.value)
    if isinstance(node, ast.Name) and node.id in FUNCS:
        return ("fn", node.id)
    if isinstance(node, ast.UnaryOp):
        v = ev(node.operand)
        if not isinstance(v, int):
            raise Fail(NAME)
        if isinstance(node.op, ast.USub):
            return fit(-v)
        if isinstance(node.op, ast.UAdd):
            return v
        if isinstance(node.op, ast.Invert):
            return ~v
        raise Fail(SYNTAX)
    if isinstance(node, ast.BinOp):
        a, b = ev(node.left), ev(node.right)
        if not isinstance(a, int) or not isinstance(b, int):
            raise Fail(NAME)
        op = node.op
        if isinstance(op, ast.Add): return fit(a + b)
        if isinstance(op, ast.Sub): return fit(a - b)
        if isinstance(op, ast.Mult): return fit(a * b)
        if isinstance(op, ast.FloorDiv):
            if b == 0: raise Fail(ZERO)
            return fit(a // b)
        if isinstance(op, ast.Mod):
            if b == 0: raise Fail(ZERO)
            return a % b
        if isinstance(op, ast.Pow):
            if b < 0: raise Fail(DOMAIN)
            if abs(a) >= 2 and b > 64: raise Fail(OVERFLOW)
            return fit(a ** b)
        if isinstance(op, ast.LShift):
            if b < 0: raise Fail(DOMAIN)
            if a != 0 and b > 63: raise Fail(OVERFLOW)
            return fit(a << b)
        if isinstance(op, ast.RShift):
            if b < 0: raise Fail(DOMAIN)
            return a >> b
        if isinstance(op, ast.BitAnd): return a & b
        if isinstance(op, ast.BitOr): return a | b
        if isinstance(op, ast.BitXor): return a ^ b
        raise Fail(SYNTAX)
    if isinstance(node, ast.Call) and not node.keywords:
        f = ev(node.func)
        args = [ev(a) for a in node.args]
        if not isinstance(f, tuple) or any(not isinstance(a, int) for a in args):
            raise Fail(NAME)
        if f[1] == "abs":
            if len(args) != 1: raise Fail(ARITY)
            return fit(abs(args[0]))
        if len(args) < 2: raise Fail(ARITY)
        return min(args) if f[1] == "min" else max(args)
    raise Fail(SYNTAX)


def expected(line, tokens):
    if any(a == "," and b == ")" for a, b in zip(tokens, tokens[1:])):
        return f"error {SYNTAX}"
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            # As eval() does, drop leading blanks that ast.parse would reject.
            tree = ast.parse(line.lstrip(" \t"), mode="eval")
    except SyntaxError:
        return f"error {SYNTAX}"
    # Syntax ext::pratt's table lacks, such as `()` tuples, is rejected
    # before any evaluation, as the Lanius parser rejects it before evaluating.
    allowed = (ast.Expression, ast.Constant, ast.Name, ast.Load, ast.UnaryOp, ast.BinOp,
               ast.Call, ast.unaryop, ast.operator)
    if any(not isinstance(n, allowed) for n in ast.walk(tree)):
        return f"error {SYNTAX}"
    try:
        return str(ev(tree))
    except Fail as failure:
        return f"error {failure.kind}"


def literal(rng):
    r = rng.random()
    if r < 0.55: return str(rng.randint(0, 12))
    if r < 0.80: return str(rng.randint(0, 100000))
    if r < 0.95: return str(rng.randint(1 << 30, 1 << 62))
    return str(rng.randint(MAX - 3, MAX + 3))


def expr(rng, depth):
    """Token list for a well-formed expression."""
    r = rng.random()
    if depth <= 0 or r < 0.25:
        return [literal(rng)]
    if r < 0.33:
        return [rng.choice(UNARY)] + expr(rng, depth - 1)
    if r < 0.40:
        return ["("] + expr(rng, depth - 1) + [")"]
    if r < 0.47:
        f = rng.choice(FUNCS)
        n = 1 if f == "abs" else rng.randint(2, 3)
        if rng.random() < 0.08:
            n = rng.randint(0, 2)  # sometimes the wrong arity, including f()
        args = []
        for i in range(n):
            if i: args.append(",")
            args += expr(rng, depth - 1)
        return [f, "("] + args + [")"]
    op = rng.choice(BINARY)
    right = expr(rng, depth - 1)
    if op in ("**", "<<", ">>") and rng.random() < 0.8:
        right = [str(rng.randint(0, 5 if op == "**" else 70))]
    return expr(rng, depth - 1) + [op] + right


def soup(rng):
    pool = BINARY + UNARY + FUNCS + ["(", ")", ",", "1", "2", "0", "7"]
    return [rng.choice(pool) for _ in range(rng.randint(0, 8))]


def render(rng, tokens):
    out = ""
    for i, t in enumerate(tokens):
        if i:
            prev = tokens[i - 1]
            glue = (prev[-1].isalnum() and t[0].isalnum()) or (prev[-1] + t[0]) in ("**", "//", "<<", ">>", "*/", "/*", "<>", "><")
            out += " " if glue else rng.choice(["", "", " ", "  ", "\t"])
        out += t
    return rng.choice(["", " "]) + out + rng.choice(["", " "])


def main():
    args = sys.argv[1:]
    seed, count = 20261031, 20000
    if "--seed" in args:
        i = args.index("--seed"); seed = int(args[i + 1]); del args[i:i + 2]
    if "--count" in args:
        i = args.index("--count"); count = int(args[i + 1]); del args[i:i + 2]
    (exe,) = args
    rng = random.Random(seed)
    lines, want, family = [], [], []
    for n in range(count + count // 4):
        tokens = expr(rng, rng.randint(1, 6)) if n < count else soup(rng)
        line = render(rng, tokens)
        lines.append(line); want.append(expected(line, tokens)); family.append("formed" if n < count else "soup")
    data = "".join(l + "\n" for l in lines).encode()
    result = subprocess.run([exe], input=data, capture_output=True, timeout=120)
    got = result.stdout.decode().split("\n")[:-1]
    print(f"python {sys.version.split()[0]} seed {seed}")
    if result.returncode != 0 or len(got) != len(lines):
        print(f"harness failed: status {result.returncode}, {len(got)}/{len(lines)} lines")
        return 1
    bad = 0
    for name in ("formed", "soup"):
        idx = [i for i, f in enumerate(family) if f == name]
        wrong = [i for i in idx if got[i] != want[i]]
        values = sum(not want[i].startswith("error") for i in idx)
        classes = {}
        for i in idx:
            if want[i].startswith("error"):
                classes[want[i]] = classes.get(want[i], 0) + 1
        print(f"{name} {len(idx) - len(wrong)}/{len(idx)}")
        print(f"  {name} coverage: {values} values, " + ", ".join(f"{k}: {v}" for k, v in sorted(classes.items())))
        for i in wrong[:8]:
            print(f"  {name} mismatch: {lines[i]!r} want {want[i]} got {got[i]}")
        bad += len(wrong)
    print(f"disagreements {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
