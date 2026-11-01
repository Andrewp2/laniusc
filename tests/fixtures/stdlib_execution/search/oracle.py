"""Generate substring-search cases, run the Lanius case runner, compare with
Python bytes.find/rfind/count/str.find. usage: oracle.py RUNNER [SEED] [N]"""
import random, struct, subprocess, sys

def cases(seed, n):
    r = random.Random(seed)
    out = []
    alphabets = [b"ab", b"abc", b"a", bytes(range(256)), b"the quick brown fox\n", "héllo wörld €".encode()]
    for i in range(n):
        alpha = alphabets[i % len(alphabets)]
        hay = bytes(r.choice(alpha) for _ in range(r.choice([0, 1, 7, 8, 9, 15, 16, 17, 63, 64, 65, r.randrange(0, 3000)])))
        kind = r.randrange(5)
        if kind == 0 and hay:   # needle cut from the haystack
            a = r.randrange(len(hay)); needle = hay[a:a + r.randrange(0, 40)]
        elif kind == 1:
            needle = b""
        elif kind == 2:          # periodic worst-ish cases
            needle = alpha[:1] * r.randrange(1, 30) + alpha[-1:]
        else:
            needle = bytes(r.choice(alpha) for _ in range(r.randrange(1, 12)))
        lo = r.randrange(0, len(hay) + 1) if r.random() < 0.4 else 0
        hi = r.randrange(lo, len(hay) + 1) if r.random() < 0.4 else len(hay)
        out.append((hay, needle, lo, hi))
    return out

def expected(hay, needle, lo, hi):
    f = hay.find(needle, lo, hi); rf = hay.rfind(needle, lo, hi); c = hay.count(needle, lo, hi)
    b = hay.find(needle[:1], lo, hi) if needle else -1
    try:
        text = hay[lo:hi].decode("utf-8"); pat = needle.decode("utf-8")
        k = text.find(pat)
        t = -1 if k < 0 else len(text[:k].encode()) + lo
    except UnicodeDecodeError:
        t = -2
    return f"{f} {rf} {c} {b} {t}"

def main():
    runner, seed, n = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 1, int(sys.argv[3]) if len(sys.argv) > 3 else 20000
    data = cases(seed, n)
    blob = b"".join(struct.pack("<I", len(h)) + h + struct.pack("<I", len(nd)) + nd + struct.pack("<II", lo, hi) for h, nd, lo, hi in data)
    got = subprocess.run([runner], input=blob, capture_output=True, timeout=120)
    if got.returncode != 0:
        print(f"runner exit {got.returncode}", got.stderr[:200]); return 1
    lines = got.stdout.decode().splitlines()
    bad = 0
    for i, case in enumerate(data):
        want = expected(*case)
        if i >= len(lines) or lines[i] != want:
            bad += 1
            if bad <= 5: print("MISMATCH", i, case[1][:20], case[2], case[3], len(case[0]), "want", want, "got", lines[i] if i < len(lines) else None)
    texts = sum(1 for case in data if not expected(*case).endswith(" -2"))
    print(f"search cases={len(data)} mismatches={bad} text_cases={texts}")
    return 1 if bad else 0

sys.exit(main())
