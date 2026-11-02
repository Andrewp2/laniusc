"""Differential oracle: text-sed (ext::sed) against GNU sed 4.9.

    python3 -I oracle.py TEXT_SED_EXE [--seed N] [--count N] [--from K] [--sed /usr/bin/sed]

TEXT_SED_EXE is sample_programs/library/text_sed.lani built with lcc. Each
case is a generated script (s///, p, d, n, q, Q, =, blocks, !, every address
form, BRE or -E syntax, -n, several -e, -s, -i) over generated UTF-8 files.
Both programs run with LC_ALL=en_US.UTF-8 in their own copy of the files.
Compared: exit status, standard output, every file afterwards (-i) and the
names in "can't read NAME" messages. A script both reject (status 1) only
compares status and output. GNU sed 4.9 steps one byte after an empty
match, splitting a multibyte character (s/x*/-/g on \u00e9 writes invalid
UTF-8); text-sed steps one character. A difference where GNU's output is
not valid UTF-8 is counted as "GNU split a character", not a disagreement.
--from K generates every case but runs those from K on,
so one seed can be split across commands. Exits 1 on any disagreement.
"""
import argparse, os, random, re, shutil, subprocess, sys, time

WORDS = ["a", "b", "c", "x", "ab", "abc", "ba", "xx", "aab", "é", "日", "1", "2", "12", "A", "B"]
PUNCT = [".", "*", "+", "(", ")", "|", "?", "{", "}", "-", "]", "^", "$"]
DELIMS = ["/", "#", ",", "@", ":"]


def line(rng, ascii_only):
    out = []
    for _ in range(rng.randint(0, 6)):
        r = rng.random()
        if r < 0.12: out.append(rng.choice(PUNCT))
        else:
            w = rng.choice(WORDS)
            if ascii_only and ord(w[0]) > 127: w = "c"
            out.append(w)
        if rng.random() < 0.6: out.append(" ")
    return "".join(out)


def contents(rng, ascii_only):
    n = rng.choice([0, 1, 2, 3, 4, 5, 6, 8, 12])
    text = "".join(line(rng, ascii_only) + "\n" for _ in range(n))
    if text and rng.random() < 0.2: text = text[:-1]
    return text


class Gen:
    def __init__(self, rng, ere, ascii_only):
        self.rng, self.ere, self.ascii = rng, ere, ascii_only

    def q(self, s):  # BRE operator spelled for the dialect: \+ in BRE, + in ERE
        return s if self.ere else "\\" + s

    def atom(self):
        rng = self.rng; r = rng.random()
        if r < 0.45:
            w = rng.choice(["a", "b", "c", "x", "1", "A", " ", "é", "日"])
            if self.ascii and ord(w) > 127: w = "b"
            return w
        if r < 0.55: return "."
        if r < 0.75:
            choices = ["[abc]", "[^a ]", "[a-c]", "[[:digit:]]", "[[:space:]]", "[^[:digit:]x]", "[]a]", "[a-]", "[^]b]", "[.]", "[*+]", "[\\.]"]
            if self.ascii: choices += ["[[:alpha:]]", "[[:upper:]]", "[[:alnum:]_]", "[[:punct:]]", "[^[:lower:]]"]
            return rng.choice(choices)
        if r < 0.85:
            choices = ["\\.", "\\*", "\\[", "\\$", "\\^", "\\s", "\\S"]
            if self.ascii: choices += ["\\w", "\\W"]
            # Literal in BRE, escaped in ERE.
            lit = rng.choice(["+", "?", "(", ")", "|", "{", "}"])
            choices.append(("\\" + lit) if self.ere else lit)
            return rng.choice(choices)
        return rng.choice(["a", "b", "x"])

    def quantified(self, body, grouped):
        rng = self.rng
        if rng.random() < 0.35:
            k = rng.random()
            if k < 0.4: return body + "*"
            if k < 0.6: return body + self.q("+")
            if k < 0.75: return body + self.q("?")
            lo = rng.randint(0, 2); hi = lo + rng.randint(0, 2)
            inner = rng.choice([f"{lo}", f"{lo},{hi}", f"{lo},"])
            return body + (("{" + inner + "}") if self.ere else ("\\{" + inner + "\\}"))
        return body

    def regex(self, safe, solid=False, boundary=True):
        """(text, group count). safe: captures have one possible span.
        solid: cannot match empty. boundary: may use \\b and \\B."""
        rng = self.rng; parts = []; groups = 0
        if rng.random() < 0.15: parts.append("^")
        for _ in range(rng.randint(1, 4)):
            if rng.random() < 0.25:
                inner = "".join(self.quantified(self.atom(), False) for _ in range(rng.randint(1, 2)))
                if not safe and rng.random() < 0.3:
                    inner = inner + self.q("|") + self.quantified(self.atom(), False)
                g = self.q("(") + inner + self.q(")")
                groups += 1
                parts.append(self.quantified(g, True) if not safe else g)
            else:
                if self.ascii and boundary and rng.random() < 0.05: parts.append(rng.choice(["\\b", "\\B"])); continue
                parts.append(self.quantified(self.atom(), False))
        if solid: parts.insert(rng.randint(0, len(parts)), self.atom())
        text = "".join(parts)
        if not safe and not solid and rng.random() < 0.1:
            text += self.q("|") + "".join(self.quantified(self.atom(), False) for _ in range(rng.randint(1, 2)))
        if rng.random() < 0.15: text += "$"
        return text, groups

    def address(self, second=False):
        rng = self.rng; r = rng.random()
        if r < 0.35: return str(rng.randint(1, 8))
        if r < 0.45: return "$"
        if r < 0.85:
            text, _ = self.regex(False)
            if rng.random() < 0.2: return "\\%" + text.replace("%", "\\%") + "%"
            return "/" + text + "/"
        if second: return rng.choice(["+", "~"]) + str(rng.randint(0, 3))
        return f"{rng.randint(0, 3)}~{rng.randint(0, 3)}"

    def addresses(self):
        rng = self.rng; r = rng.random()
        if r < 0.4: return ""
        if r < 0.7: a = self.address()
        elif r < 0.75: a = "0,/" + self.regex(False)[0] + "/"
        else: a = self.address() + "," + self.address(True)
        if rng.random() < 0.15: a += "!"
        return a

    def substitute(self):
        rng = self.rng
        safe = rng.random() < 0.6
        flags = rng.choice(["", "", "g", "g", "p", "2", "2g", "gp", "3"])
        # After an empty match GNU sed steps one byte, even inside a
        # multibyte character, and its next search loses the left context
        # of \b and \B. Repeated matches over UTF-8 use regexes that cannot
        # match empty, and never \b or \B.
        repeated = flags not in ("", "p")
        if rng.random() < 0.08 and not repeated: text, groups = "", 0  # the last regex used
        else: text, groups = self.regex(safe, solid=repeated and not self.ascii, boundary=not repeated)
        d = rng.choice([c for c in DELIMS if c not in text] or DELIMS)
        rep = []
        for _ in range(rng.randint(0, 4)):
            r = rng.random()
            if r < 0.4: rep.append(rng.choice(["y", "Z", "-", "" if self.ascii else "ü", "", " "]))
            elif r < 0.6: rep.append("&")
            elif r < 0.7: rep.append(rng.choice(["\\&", "\\n", "\\\\", "\\" + d]))
            elif safe and groups: rep.append("\\" + str(rng.randint(1, groups)))
        return "s" + d + text + d + "".join(rep) + d + flags

    def command(self, depth=0):
        rng = self.rng; r = rng.random()
        a = self.addresses()
        if r < 0.45: return a + self.substitute()
        if r < 0.55: return a + "p"
        if r < 0.62: return a + "d"
        if r < 0.7: return a + "n"
        if r < 0.75: return a + "="
        if r < 0.78:
            src = rng.sample(["a", "b", "c", "x", " ", "\u00e9", "\u65e5", "1"], rng.randint(1, 4))
            if self.ascii: src = [c for c in src if ord(c) < 128] or ["a"]
            dst = [rng.choice(["y", "Z", "-", "\\n", "a"] + ([] if self.ascii else ["\u00fc"])) for _ in src]
            d = rng.choice(DELIMS)
            return a + "y" + d + "".join(src) + d + "".join(dst) + d
        if r < 0.8:
            a1 = rng.choice(["", self.address()])
            return a1 + rng.choice(["q", "Q"]) + rng.choice(["", "", "3", " 5"])
        if depth < 2:
            inner = ";".join(self.command(depth + 1) for _ in range(rng.randint(1, 3)))
            return a + "{" + inner + ";}"
        return a + "p"


BAD = ["k", "s/a/b", "s/\\(a\\)/\\2/", "{p", "p}", "p x", "3,p", "s/a/b/gg", "s/[a/b/", "0p", "s/a/b/0", "2,3q", "y/ab/c/", "y/a/b"]


def generate(rng):
    ascii_only = rng.random() < 0.3
    ere = rng.random() < 0.4
    g = Gen(rng, ere, ascii_only)
    commands = [g.command() for _ in range(rng.randint(1, 4))]
    bad = rng.random() < 0.05
    if bad: commands.insert(rng.randint(0, len(commands)), rng.choice(BAD))
    opts = []
    if ere: opts.append(rng.choice(["-E", "-r", "--regexp-extended"]))
    if rng.random() < 0.3: opts.append(rng.choice(["-n", "--quiet"]))
    mode = rng.random()
    nfiles = rng.choice([0, 1, 1, 2, 2, 3])
    files = [(f"f{i}", contents(rng, ascii_only)) for i in range(nfiles)]
    stdin = contents(rng, ascii_only) if nfiles == 0 or rng.random() < 0.1 else ""
    names = [n for n, _ in files]
    if nfiles and mode < 0.15: opts.append(rng.choice(["-i", "--in-place"]))
    elif nfiles and mode < 0.3: opts.append(rng.choice(["-s", "--separate"]))
    else:
        if rng.random() < 0.15 and nfiles: names.insert(rng.randint(0, len(names)), "missing")
        if nfiles and rng.random() < 0.1: names.insert(rng.randint(0, len(names)), "-")
    if rng.random() < 0.3 and len(commands) > 1:
        script_args = []
        for c in commands: script_args += ["-e", c]
    else:
        script_args = [rng.choice([";", "\n"]).join(commands)]
        if rng.random() < 0.3: script_args = ["-e"] + script_args
    return {"args": opts + script_args + names, "files": files, "stdin": stdin, "in_place": any(o in ("-i", "--in-place") for o in opts)}


def valid(data):
    try: data.decode("utf-8"); return True
    except UnicodeDecodeError: return False


def run(exe, case, where):
    if os.path.isdir(where): shutil.rmtree(where)
    os.makedirs(where)
    for name, text in case["files"]:
        with open(os.path.join(where, name), "wb") as f: f.write(text.encode())
    env = {"LC_ALL": "en_US.UTF-8", "PATH": "/usr/bin:/bin"}
    p = subprocess.run([exe] + case["args"], input=case["stdin"].encode(), cwd=where, capture_output=True, timeout=20, env=env)
    after = {}
    for name in sorted(os.listdir(where)):
        with open(os.path.join(where, name), "rb") as f: after[name] = f.read()
    unread = re.findall(rb"can't read (.*?): ", p.stderr)
    return p.returncode, p.stdout, after, unread, p.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("exe"); ap.add_argument("--seed", type=int, default=1); ap.add_argument("--count", type=int, default=500)
    ap.add_argument("--from", dest="start", type=int, default=0); ap.add_argument("--sed", default="/usr/bin/sed")
    ap.add_argument("--work", default="target/claude-work/s3/sed/oracle"); ap.add_argument("--show", type=int, default=5)
    a = ap.parse_args()
    exe = os.path.abspath(a.exe); rng = random.Random(a.seed)
    cases = [generate(rng) for _ in range(a.count)]
    work = os.path.abspath(os.path.join(a.work, f"seed{a.seed}"))
    agree = 0; total = 0; rejected = 0; split = 0; bad = []; started = time.time()
    for index in range(a.start, a.count):
        case = cases[index]; total += 1
        g = run(a.sed, case, os.path.join(work, "gnu"))
        o = run(exe, case, os.path.join(work, "ours"))
        if g[0] == 1 and o[0] == 1:
            same = o[1] == g[1]; rejected += 1
        else:
            same = g[0] == o[0] and g[1] == o[1] and g[2] == o[2] and g[3] == o[3]
        if same: agree += 1
        elif not valid(g[1]) or not all(valid(v) for v in g[2].values()): split += 1
        else: bad.append((index, case, g, o))
    print(f"seed {a.seed} cases {a.start}-{a.count}: agree {agree}/{total} (both rejected {rejected}), "
          f"GNU split a character {split} in {time.time() - started:.1f} s")
    for index, case, g, o in bad[:a.show]:
        print(f"--- case {index}: args {case['args']!r} stdin {case['stdin']!r}")
        for name, text in case["files"]: print(f"    {name}: {text!r}")
        print(f"    gnu  status {g[0]} out {g[1][:300]!r} files {g[2] if case['in_place'] else ''} err {g[4][:200]!r}")
        print(f"    ours status {o[0]} out {o[1][:300]!r} files {o[2] if case['in_place'] else ''} err {o[4][:200]!r}")
    print(f"disagreements {len(bad)}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
