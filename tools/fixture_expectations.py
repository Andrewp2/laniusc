#!/usr/bin/env python3
"""Expected outcomes for the runnable stdlib_foundation and generics fixtures.

The stdlib_foundation fixtures carry no expectation convention of their own;
the expectations live in the Rust integration tests.  This module reads
tests/*.rs with a small Rust tokenizer and abstractly executes every #[test]
function: local helper functions and macro_rules! are inlined with their
arguments, `for` loops over literal tables are unrolled, and every compile
call opens a record that later runs and asserts attach to (status.code(),
status.signal(), stdout, diagnostic.code, expect_err, ...).  Values it cannot
evaluate become unknown instead of guesses.  A `laniusc check|build FIXTURE`
command is a compile too: the test's `status.success()` and stderr `LNC` checks
are its outcome.  Unreferenced fixtures fall back to
"run, exit 0" (generics probes: exit 42); a `// expect: N` first line overrides.

usage: tools/fixture_expectations.py [--json] [--summary]
"""
from __future__ import annotations

import argparse
import functools
import json
import re
import sys
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FOUNDATION = "tests/fixtures/stdlib_foundation"
GENERICS = ("tests/fixtures/generics_matrix", "tests/fixtures/generics_backlog")
EXPECT_RE = re.compile(r"//\s*expect:\s*(-?\d+)")
LNC_RE = re.compile(r"LNC\d{4}$")
LNC_ANY = re.compile(r"LNC\d{4}")
CLI_COMPILES = ("check", "build")


@dataclass
class Expectation:
    path: Path                 # absolute fixture path
    kind: str                  # "run" | "compile_error" | "check_only" | "module"
    exit_code: int | None      # expected exit status, None = unchecked
    signal: int | None         # expected terminating signal, e.g. 4 for SIGILL traps
    stdout: bytes | None       # exact expected stdout, None = unchecked
    error_code: str | None     # e.g. "LNC0006" for compile errors
    stdlib_root: Path | None   # None = repo stdlib/
    harness: list[str]         # needs a plain run cannot reproduce
    source: str                # provenance


# ---------------------------------------------------------------- tokenizer
class Tok:
    __slots__ = ("kind", "text", "val", "line")

    def __init__(self, kind, text, val, line):
        self.kind, self.text, self.val, self.line = kind, text, val, line

    def __repr__(self):
        return self.text


class Group:
    __slots__ = ("open", "items", "line")

    def __init__(self, open_, line):
        self.open, self.items, self.line = open_, [], line


class S(str):        # string value remembering its source line and whether it was computed
    line, computed = 0, False


class B(bytes):
    line, computed = 0, False


def mk(cls, value, line=0, computed=False):
    v = cls(value)
    v.line, v.computed = line, computed
    return v


_TOKEN = re.compile(r"""(?P<ws>\s+)|(?P<lc>//[^\n]*)|(?P<bc>/\*)|(?P<raw>b?r\#*")|(?P<str>b?")
  |(?P<chr>b?'(?:\\(?:x[0-9a-fA-F]{2}|u\{[0-9a-fA-F]+\}|.)|[^\\'\n])')|(?P<life>'\w+)
  |(?P<num>\d\w*(?:\.\d+(?:[eE][+-]?\d+)?\w*)?)|(?P<id>r\#\w+|[A-Za-z_]\w*)
  |(?P<p>::|->|=>|==|!=|<=|>=|&&|\|\||\.\.=|\.\.|\+=|-=|[^\s])""", re.X)
_ESCAPE = re.compile(r"\\(x[0-9a-fA-F]{2}|u\{[0-9a-fA-F]+\}|\n\s*|.)", re.S)
_SIMPLE = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}
_SUFFIX = re.compile(r"(?:[iu](?:8|16|32|64|128|size)|f32|f64)$")


def _unescape(body, as_bytes):
    out = bytearray()
    pos = 0
    for m in _ESCAPE.finditer(body):
        out += body[pos:m.start()].encode()
        e = m.group(1)
        if e[0] == "x":
            out.append(int(e[1:], 16)) if as_bytes else out.extend(chr(int(e[1:], 16)).encode())
        elif e[0] == "u":
            out += chr(int(e[2:-1], 16)).encode()
        elif e[0] != "\n":
            out += _SIMPLE.get(e, e).encode()
        pos = m.end()
    out += body[pos:].encode()
    return bytes(out) if as_bytes else out.decode("utf-8", "replace")


def tokenize(src):
    toks, i, line = [], 0, 1
    while i < len(src):
        m = _TOKEN.match(src, i)
        kind, text = m.lastgroup, m.group()
        if kind == "bc":
            depth, j = 1, i + 2
            while j < len(src) and depth:
                depth += {"/*": 1, "*/": -1}.get(src[j:j + 2], 0)
                j += 2 if src[j:j + 2] in ("/*", "*/") else 1
            text = src[i:j]
        elif kind == "raw":
            close = '"' + "#" * text.count("#")
            j = src.index(close, m.end()) + len(close)
            body, text = src[m.end():j - len(close)], src[i:j]
            toks.append(Tok("bstr" if text[0] == "b" else "str", text,
                            body.encode() if text[0] == "b" else body, line))
        elif kind == "str":
            j = m.end()
            while src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            text = src[i:j + 1]
            as_bytes = text[0] == "b"
            toks.append(Tok("bstr" if as_bytes else "str", text,
                            _unescape(src[m.end():j], as_bytes), line))
        elif kind == "chr":
            ch = _unescape(text[text.index("'") + 1:-1], False)
            toks.append(Tok("num" if text[0] == "b" else "chr", text, ord(ch) if text[0] == "b" else ch, line))
        elif kind == "num":
            digits = text.replace("_", "")
            digits = re.sub(r"[iu](?:8|16|32|64|128|size)$", "", digits) if digits.startswith("0x") \
                else _SUFFIX.sub("", digits)
            try:
                val = int(digits, 0)
            except ValueError:
                try:
                    val = float(digits)
                except ValueError:
                    val = None
            toks.append(Tok("num", text, val, line))
        elif kind in ("id", "p", "life"):
            toks.append(Tok(kind, text, text, line))
        line += text.count("\n")
        i += len(text)
    return toks


def build_tree(toks):
    root = Group("", 0)
    stack = [root]
    for t in toks:
        if t.kind == "p" and t.text in "([{":
            g = Group(t.text, t.line)
            stack[-1].items.append(g)
            stack.append(g)
        elif t.kind == "p" and t.text in ")]}":
            if len(stack) > 1:
                stack.pop()
        else:
            stack[-1].items.append(t)
    return root.items


def is_p(x, *texts):
    return isinstance(x, Tok) and x.kind == "p" and x.text in texts


def is_id(x, *texts):
    return isinstance(x, Tok) and x.kind == "id" and (not texts or x.text in texts)


def is_g(x, open_):
    return isinstance(x, Group) and x.open == open_


def split(items, sep=","):
    parts, cur = [], []
    for x in items:
        if is_p(x, sep):
            parts.append(cur)
            cur = []
        else:
            cur.append(x)
    if cur:
        parts.append(cur)
    return parts


def find(items, pred, start=0):
    return next((k for k in range(start, len(items)) if pred(items[k])), len(items))


def has_ident(items, names):
    return any(is_id(x, *names) or (isinstance(x, Group) and has_ident(x.items, names)) for x in items)


# ---------------------------------------------------------------- values
class _Marker:
    def __init__(self, name):
        self.name = name

    def __repr__(self):
        return self.name


UNK, RNONE, MISSING, COMPUTED = _Marker("UNK"), _Marker("None"), _Marker("MISSING"), _Marker("COMPUTED")


@dataclass(eq=False)
class PathV:                 # a path, or (text=True) the contents of the file at that path
    path: Path
    text: bool = False
    line: int = 0


@dataclass(eq=False)
class Derived:               # source text built from fixtures (concat) or a modified copy (replace)
    progs: list
    how: str


@dataclass(eq=False)
class W:                     # interpreter object: run, status, exit, signal, success, stdout,
    tag: str                 # empty, not, result, err, code, cmd, temp, tempdir, null, piped
    ref: object = None


class RList(list):           # a list produced by a range, not a literal table
    pass


@dataclass(eq=False)
class Run:
    flags: set
    injected: bool = False
    exit: object = MISSING
    signal: object = MISSING
    stdout: object = MISSING


@dataclass(eq=False)
class Record:                # one compile call and the runs/asserts that follow it
    progs: list
    kind: str
    stdlib: object
    prov: str
    test: str
    inline_main: bool = False
    derived: str | None = None
    outcome: str | None = None
    code: str | None = None
    runs: list = field(default_factory=list)
    fs: list = field(default_factory=list)       # (read|write, number of runs before it)


IDENTITY_FNS = {"Some", "Ok", "from", "from_utf8", "from_utf8_lossy", "Box::new", "Path::new", "OsStr::new",
                "Cow::from"}
PASS_LAST = {"run_gpu_codegen_with_timeout", "run_gpu_codegen_suite_with_timeout", "run_with_timeout",
             "block_on", "block_on_gpu_with_timeout", "stdout_utf8"}
RUNNERS = {"run_x86_64_elf", "run_x86_64_elf_output", "run_x86_64_elf_output_with_args",
           "short_process_output_with_timeout", "command_output_with_timeout",
           "codegen_command_output_with_timeout"}
IDENTITY_METHODS = {"clone", "to_owned", "to_string", "as_str", "as_ref", "as_path", "to_path_buf", "borrow",
                    "into", "iter", "into_iter", "copied", "cloned", "to_vec", "as_slice", "display", "unwrap",
                    "expect", "unwrap_or_else", "into_owned", "as_deref", "as_mut", "by_ref"}
CHECK_RE = re.compile(r"type_check|semantic_interface|parse_resident|parser_semantic|with_resident_tokens"
                      r"|check_tokens|record_checked")
BINOPS = {"==", "!=", "&&", "||", "+", "-", "/", "%", "<=", ">=", "..", "..=", "=", "+=", "-="}
FS_WRITE = {"write", "create_dir", "create_dir_all", "remove_file", "copy"}
FS_READ = {"read", "read_to_string", "read_dir", "exists"}


# ---------------------------------------------------------------- interpreter
class Interp:
    def __init__(self, repo: Path, rs: Path):
        self.repo, self.rs = repo, rs
        self.fns, self.macros, self.tests, self.consts, self.const_items = {}, {}, [], {}, {}
        self.records, self.cur, self.table, self.macro_depth = [], None, 0, 0   # per-test state
        self.stack, self.rets, self.test, self.from_macro, self.errors = [], [None], "", False, []
        self.collect(build_tree(tokenize(rs.read_text())), False)
        for name, items in self.const_items.items():
            self.consts[name] = self.ev(items, dict(self.consts))
        self.records.clear()

    # -- items
    def collect(self, items, from_macro):
        i, attrs = 0, []
        while i < len(items):
            t = items[i]
            if is_p(t, "#") and i + 1 < len(items) and is_g(items[i + 1], "["):
                attrs.append(" ".join(x.text for x in items[i + 1].items if isinstance(x, Tok)))
                i += 2
                continue
            if is_id(t, "fn") and i + 1 < len(items):
                params = find(items, lambda x: is_g(x, "("), i + 2)
                body = find(items, lambda x: is_g(x, "{"), params + 1)
                if body < len(items):
                    name = items[i + 1].text
                    pnames = []
                    for p in split(items[params].items):
                        ids = [x.text for x in p[:find(p, lambda x: is_p(x, ":"))] if is_id(x) and x.text != "mut"]
                        pnames.append(ids[0] if ids else "_")
                    if any(a.split()[0] == "test" for a in attrs if a):
                        ignored = any(a.startswith("ignore") for a in attrs)
                        self.tests.append((name, items[body], t.line, from_macro, ignored))
                    else:
                        self.fns[name] = (pnames, items[body])
                i, attrs = body + 1, []
                continue
            if is_id(t, "macro_rules") and i + 3 < len(items) and is_g(items[i + 3], "{"):
                arms, parts = [], items[i + 3].items
                for k, x in enumerate(parts):
                    if is_g(x, "(") and k + 2 < len(parts) and is_p(parts[k + 1], "=>") and isinstance(parts[k + 2], Group):
                        params = [parts_k.text for j, parts_k in enumerate(x.items)
                                  if is_id(parts_k) and j > 0 and is_p(x.items[j - 1], "$")]
                        arms.append((params, parts[k + 2].items))
                self.macros[items[i + 2].text] = arms
                i += 4
                continue
            if is_id(t) and i + 2 < len(items) and is_p(items[i + 1], "!") and isinstance(items[i + 2], Group):
                expanded = self.expand(t.text, items[i + 2])
                if expanded is not None:
                    self.collect(expanded, True)
                i, attrs = i + 3, []
                continue
            if is_id(t, "const", "static"):
                end = find(items, lambda x: is_p(x, ";"), i)
                eq = find(items, lambda x: is_p(x, "="), i)
                names = [x.text for x in items[i + 1:eq] if is_id(x) and x.text != "mut"]
                if names and eq < end:
                    self.const_items[names[0]] = items[eq + 1:end]
                i, attrs = end + 1, []
                continue
            if is_id(t, "mod") and i + 2 < len(items) and is_g(items[i + 2], "{"):
                self.collect(items[i + 2].items, from_macro)
                i, attrs = i + 3, []
                continue
            if is_id(t, "impl", "struct", "enum", "trait", "use", "type"):
                j = find(items, lambda x: is_p(x, ";") or is_g(x, "{"), i)
                i, attrs = j + 1, []
                continue
            i += 1

    def expand(self, name, group):
        """Substitute a local macro_rules! invocation; None if unknown or unmatched."""
        args = split(group.items)
        for params, body in self.macros.get(name, []):
            if len(params) != len(args):
                continue
            binding = dict(zip(params, args))

            def subst(items):
                out, k = [], 0
                while k < len(items):
                    x = items[k]
                    if is_p(x, "$") and k + 1 < len(items) and is_id(items[k + 1]) and items[k + 1].text in binding:
                        out.extend(binding[items[k + 1].text])
                        k += 2
                        continue
                    if isinstance(x, Group):
                        g = Group(x.open, x.line)
                        g.items = subst(x.items)
                        x = g
                    out.append(x)
                    k += 1
                return out
            return subst(body)
        return None

    # -- tests
    def run_tests(self):
        for name, body, line, from_macro, ignored in self.tests:
            self.records, self.cur, self.table, self.rets = [], None, 0, [None]
            self.stack, self.macro_depth = [], 0
            self.test, self.from_macro = name + (" [ignored]" if ignored else ""), from_macro
            try:
                self.exec_block(body.items, dict(self.consts))
            except (RecursionError, IndexError, ValueError, KeyError, AttributeError, TypeError) as error:
                self.errors.append(f"{self.rs.name}:{line} {name}: {type(error).__name__}: {error}")
            yield from self.records

    # -- statements
    def exec_block(self, items, env):
        i, tail = 0, None
        while i < len(items):
            t = items[i]
            tail = None
            if is_p(t, "#"):
                i += 2
            elif is_p(t, ";"):
                i += 1
            elif is_id(t, "let"):
                j = find(items, lambda x: is_p(x, ";"), i)
                self.let(items[i + 1:j], env)
                i = j + 1
            elif is_id(t, "const", "static"):
                j = find(items, lambda x: is_p(x, ";"), i)
                self.let(items[i + 1:j], env)
                i = j + 1
            elif is_id(t, "fn", "use", "struct", "enum", "impl", "mod", "type", "trait"):
                j = find(items, lambda x: is_p(x, ";") or is_g(x, "{"), i)
                if is_id(t, "fn"):
                    self.collect(items[i:j + 1], False)
                i = j + 1
            elif is_id(t, "for", "while", "loop", "if", "match", "unsafe") or is_g(t, "{"):
                tail, i = self.compound(items, i, env)
            elif is_id(t, "return"):
                j = find(items, lambda x: is_p(x, ";"), i)
                v = self.ev(items[i + 1:j], env)
                if self.rets[-1] is None:
                    self.rets[-1] = v
                i = j + 1
            else:
                j = find(items, lambda x: is_p(x, ";"), i)
                v = self.ev(items[i:j], env)
                tail = v if j >= len(items) else None
                i = j + 1
        return tail

    def compound(self, items, i, env):
        t = items[i]
        body = find(items, lambda x: is_g(x, "{"), i + (0 if isinstance(t, Group) else 1))
        if body >= len(items):
            return UNK, len(items)
        block = items[body].items
        if is_id(t, "for"):
            k = find(items, lambda x: is_id(x, "in"), i)
            seq = self.ev(items[k + 1:body], env)
            literal = isinstance(seq, (list, tuple)) and not isinstance(seq, RList)
            self.table += literal
            for elem in (seq[:2] if isinstance(seq, RList) else seq if isinstance(seq, (list, tuple)) else [UNK]):
                scope = dict(env)
                self.bind(items[i + 1:k], elem, scope)
                self.exec_block(block, scope)
            self.table -= literal
            return UNK, body + 1
        if is_id(t, "if"):
            cond, scope = items[i + 1:body], dict(env)
            nxt = body + 1
            other = items[nxt + 1] if nxt + 1 < len(items) and is_id(items[nxt], "else") else None
            if cond and is_id(cond[0], "let"):
                eq = find(cond, lambda x: is_p(x, "="))
                v = self.ev(cond[eq + 1:], env)
                head = next((x.text for x in cond[1:eq] if is_id(x)), "")
                if isinstance(v, W) and v.tag == "result":
                    then_panics = has_ident(block, ["panic", "unreachable"])
                    else_panics = is_g(other, "{") and has_ident(other.items, ["panic", "unreachable"])
                    if (head == "Ok") == bool(then_panics) and (then_panics or else_panics):
                        v.ref.outcome = "err"
                    elif then_panics or else_panics:
                        v.ref.outcome = v.ref.outcome or "ok"
                self.bind(cond[1:eq], v, scope)
            else:
                self.ev(cond, env)
            self.exec_block(block, scope)
            if other is not None:
                if is_id(other, "if"):
                    return self.compound(items, nxt + 1, env)
                if is_g(other, "{"):
                    self.exec_block(other.items, dict(env))
                    return UNK, nxt + 2
            return UNK, nxt
        if is_id(t, "match"):
            v = self.ev(items[i + 1:body], env)
            arms, k = [], 0
            while k < len(block):
                arrow = find(block, lambda x: is_p(x, "=>"), k)
                if arrow >= len(block):
                    break
                if arrow + 1 < len(block) and is_g(block[arrow + 1], "{"):
                    end = arrow + 2
                else:
                    end = find(block, lambda x: is_p(x, ","), arrow + 1)
                arms.append((block[k:arrow], block[arrow + 1:end]))
                k = end + (1 if end < len(block) and is_p(block[end], ",") else 0)
            for pat, arm in arms:
                head = next((x.text for x in pat if is_id(x)), "")
                if isinstance(v, W) and v.tag == "result" and has_ident(arm, ["panic", "unreachable"]):
                    if head == "Ok":
                        v.ref.outcome = "err"
                    elif head == "Err":
                        v.ref.outcome = v.ref.outcome or "ok"
                scope = dict(env)
                self.bind(pat, v, scope)
                if len(arm) == 1 and is_g(arm[0], "{"):
                    self.exec_block(arm[0].items, scope)
                else:
                    self.ev(arm, scope)
            return UNK, body + 1
        if is_id(t, "while"):
            self.ev(items[i + 1:body], env)
        return self.exec_block(block, dict(env)), body + 1

    def let(self, items, env):
        eq = find(items, lambda x: is_p(x, "="))
        pat = items[:min(eq, find(items, lambda x: is_p(x, ":")))]
        expr = items[eq + 1:]
        otherwise = None
        if len(expr) >= 2 and is_g(expr[-1], "{") and is_id(expr[-2], "else") and not is_id(expr[0], "if", "match"):
            expr, otherwise = expr[:-2], expr[-1]
        v = self.ev(expr, env) if eq < len(items) else UNK
        if otherwise is not None and isinstance(v, W) and v.tag == "result":
            head = next((x.text for x in pat if is_id(x)), "")
            v.ref.outcome = "err" if head == "Err" else (v.ref.outcome or "ok")
        self.bind(pat, v, env)

    def bind(self, pat, v, env):
        pat = [x for x in pat if not is_p(x, "&") and not is_id(x, "mut", "ref")]
        if len(pat) == 1 and is_id(pat[0]):
            if pat[0].text != "_":
                env[pat[0].text] = v
        elif len(pat) == 1 and is_g(pat[0], "("):
            subs = split(pat[0].items)
            vals = list(v) if isinstance(v, (tuple, list)) and len(v) == len(subs) else [UNK] * len(subs)
            for sub, val in zip(subs, vals):
                self.bind(sub, val, env)
        elif pat and is_g(pat[-1], "(") and is_id(pat[0]):
            if pat[0].text == "Err" and isinstance(v, W) and v.tag == "result":
                v = W("err", v.ref)
            self.bind(pat[-1].items, v, env)

    # -- expressions
    def ev(self, items, env):
        if not items:
            return UNK
        if is_p(items[0], "|", "||") or is_id(items[0], "move", "async"):
            k = 0
            while k < len(items) and is_id(items[k], "move", "async"):
                k += 1
            if k < len(items) and is_p(items[k], "||"):
                k += 1
            elif k < len(items) and is_p(items[k], "|"):
                k = find(items, lambda x: is_p(x, "|"), k + 1) + 1
            return self.ev(items[k:], dict(env))
        if is_id(items[0], "if", "match", "loop", "unsafe", "for", "while"):
            return self.compound(items, 0, env)[0]
        for k in range(1, len(items)):
            if is_p(items[k], *BINOPS) and not (isinstance(items[k - 1], Tok) and items[k - 1].kind == "p"
                                                and items[k - 1].text not in ")]}?"):
                lhs, rhs = self.ev(items[:k], env), self.ev(items[k + 1:], env)
                if items[k].text in ("..", "..=") and isinstance(lhs, int) and isinstance(rhs, int):
                    return RList(range(lhs, rhs + (items[k].text == "..=")))
                return UNK
        v, j = self.chain(items, 0, env)
        if j >= len(items):
            return v
        if j == 0:
            self.ev(items[1:], env)
            return UNK
        cast = is_id(items[j], "as")
        self.ev(items[j + 1:] if cast else items[j:], env)
        return v if cast else UNK

    def chain(self, items, i, env):
        t = items[i]
        if is_p(t, "&", "*"):
            k = i + 1 + (i + 1 < len(items) and is_id(items[i + 1], "mut"))
            return self.chain(items, k, env) if k < len(items) else (UNK, k)
        if is_p(t, "-") and i + 1 < len(items) and isinstance(items[i + 1], Tok) and items[i + 1].kind == "num":
            v, j = -(items[i + 1].val or 0), i + 2
        elif is_p(t, "!"):
            v, j = self.chain(items, i + 1, env) if i + 1 < len(items) else (UNK, i + 1)
            return W("not", v), j
        elif isinstance(t, Tok) and t.kind in ("str", "bstr", "chr", "num"):
            v, j = (mk(B, t.val, t.line) if t.kind == "bstr" else mk(S, t.val, t.line) if t.kind == "str" else t.val), i + 1
        elif is_g(t, "("):
            parts = split(t.items)
            vals = [self.ev(p, env) for p in parts]
            v = vals[0] if len(vals) == 1 and not (t.items and is_p(t.items[-1], ",")) else tuple(vals)
            j = i + 1
        elif is_g(t, "["):
            if any(is_p(x, ";") for x in t.items):
                self.ev(t.items[:find(t.items, lambda x: is_p(x, ";"))], env)
                v = COMPUTED
            else:
                v = [self.ev(p, env) for p in split(t.items)]
            j = i + 1
        elif is_g(t, "{"):
            v, j = self.exec_block(t.items, dict(env)), i + 1
        elif is_id(t):
            segs, j = [t.text], i + 1
            while j + 1 < len(items) and is_p(items[j], "::"):
                if is_p(items[j + 1], "<"):            # turbofish
                    depth, j = 0, j + 1
                    while j < len(items):
                        depth += is_p(items[j], "<") - is_p(items[j], ">")
                        j += 1
                        if depth == 0:
                            break
                    continue
                if not isinstance(items[j + 1], Tok):
                    break
                segs.append(items[j + 1].text)
                j += 2
            if j + 1 < len(items) and is_p(items[j], "!") and isinstance(items[j + 1], Group):
                v, j = self.macro(segs[-1], items[j + 1], env, t.line), j + 2
            elif j < len(items) and is_g(items[j], "("):
                v, j = self.call(segs, items[j], env), j + 1
            elif len(segs) == 1:
                v = {"None": RNONE, "true": True, "false": False}.get(t.text, env.get(t.text, UNK))
            else:
                v = UNK
        else:
            return UNK, i
        while j < len(items):
            x = items[j]
            if is_p(x, ".") and j + 1 < len(items):
                name = items[j + 1].text
                if j + 2 < len(items) and is_g(items[j + 2], "("):
                    args = [self.ev(p, env) for p in split(items[j + 2].items)]
                    v, j = self.method(v, name, args), j + 3
                else:
                    v, j = self.field(v, name), j + 2
            elif is_p(x, "?"):
                j += 1
            elif is_g(x, "[") or is_g(x, "("):
                if not (len(x.items) == 1 and is_p(x.items[0], "..")):
                    self.ev(x.items, env)
                    v = UNK
                j += 1
            else:
                break
        return v, j

    def macro(self, name, group, env, line):
        parts = split(group.items)
        if name in ("include_str", "include_bytes"):
            rel = self.ev(parts[0], env) if parts else UNK
            if isinstance(rel, PathV):
                return PathV(rel.path, True, rel.line or line)
            if isinstance(rel, str):
                return PathV((self.rs.parent / rel).resolve(), True, getattr(rel, "line", 0) or line)
            return UNK
        if name == "concat":
            vals = [self.ev(p, env) for p in parts]
            if vals and isinstance(vals[0], PathV) and all(isinstance(x, str) for x in vals[1:]):
                return PathV(Path(str(vals[0].path) + "".join(vals[1:])), False, line)
            if all(isinstance(x, (str, int)) and not isinstance(x, bool) for x in vals):
                return mk(S, "".join(map(str, vals)), max([x.line for x in vals if isinstance(x, S)] or [line]))
            return UNK
        if name == "env":
            return PathV(self.repo, False, line) if parts and self.ev(parts[0], env) == "CARGO_MANIFEST_DIR" else UNK
        if name in ("format", "format_args"):
            return self.format(parts, env, line)
        if name == "stringify":
            return mk(S, " ".join(x.text for x in group.items if isinstance(x, Tok)), line)
        if name == "vec":
            if any(is_p(x, ";") for x in group.items):
                return COMPUTED
            return [self.ev(p, env) for p in parts]
        if name == "matches" and len(parts) >= 2:
            v = self.ev(parts[0], env)
            head = next((x.text for x in parts[1] if is_id(x)), "")
            if isinstance(v, W) and v.tag == "result" and head in ("Ok", "Err"):
                v.ref.outcome = "err" if head == "Err" else (v.ref.outcome or "ok")
            return UNK
        if name in ("assert_eq", "debug_assert_eq") and len(parts) >= 2:
            self.eq(self.ev(parts[0], env), self.ev(parts[1], env))
            return UNK
        if name in ("assert", "debug_assert") and parts:
            self.cond(parts[0], env)
            return UNK
        if name in ("assert_ne", "debug_assert_ne"):
            for p in parts[:2]:
                self.ev(p, env)
            return UNK
        if name in self.macros:
            expanded = self.expand(name, group)
            if expanded is not None:
                self.macro_depth += 1
                try:
                    return self.exec_block(expanded, dict(env))
                finally:
                    self.macro_depth -= 1
        return UNK

    def format(self, parts, env, line):
        fmt = self.ev(parts[0], env) if parts else UNK
        if not isinstance(fmt, str):
            return UNK
        positional, named = [], {}
        for p in parts[1:]:
            if len(p) >= 2 and is_id(p[0]) and is_p(p[1], "="):
                named[p[0].text] = self.ev(p[2:], env)
            else:
                positional.append(self.ev(p, env))
        out, texts, cursor, src_line = [], [], 0, getattr(fmt, "line", line)   # line of the last substitution
        for piece in re.split(r"(\{\{|\}\}|\{[^{}]*\})", fmt):
            if piece in ("{{", "}}"):
                out.append(piece[0])
                continue
            if not (piece.startswith("{") and piece.endswith("}")):
                out.append(piece)
                continue
            key, _, spec = piece[1:-1].partition(":")
            if key == "":
                value = positional[cursor] if cursor < len(positional) else UNK
                cursor += 1
            elif key.isdigit():
                value = positional[int(key)] if int(key) < len(positional) else UNK
            else:
                value = named.get(key, env.get(key, UNK))
            if isinstance(value, PathV) and value.text:
                texts.append(value)
            elif isinstance(value, PathV):
                out.append(str(value.path))
            elif isinstance(value, bool):
                out.append("true" if value else "false")
            elif isinstance(value, (str, int, float)) and "?" not in spec:
                out.append(str(value))
                src_line = getattr(value, "line", 0) or src_line
            else:
                return UNK if not texts else Derived(texts, "concat")
        if texts:
            return Derived(texts, "concat")
        result = "".join(out)
        if result.startswith(str(self.repo) + "/"):
            return PathV(Path(result), False, src_line)
        return mk(S, result, src_line, computed=True)

    def call(self, segs, group, env):
        name, full = segs[-1], "::".join(segs[-2:])
        parts = split(group.items)
        if len(segs) == 1 and name in self.fns:
            return self.call_local(name, [self.ev(p, env) for p in parts])
        args = [self.ev(p, env) for p in parts]
        if name in IDENTITY_FNS or full in IDENTITY_FNS or name == "Err":
            return args[0] if args else UNK
        if name in PASS_LAST:
            return args[-1] if args else UNK
        if full in ("Vec::new", "String::new"):
            return mk(B, b"") if segs[0] == "Vec" else mk(S, "")
        if full == "Command::new":
            prog = args[0] if args and isinstance(args[0], str) else None
            rec = args[0].ref if args and isinstance(args[0], W) and args[0].tag == "bytes" else None
            return W("cmd", {"flags": set(), "wrapper": prog, "rec": rec})
        if full == "TempArtifact::new":
            return W("temp", [None])
        if full in ("Stdio::null", "Stdio::piped", "Stdio::inherit"):
            return W("null" if name != "piped" else "piped")
        if name in RUNNERS:
            flags, injected, rec = set(), False, None
            if name.endswith("with_args") and len(args) > 3 and isinstance(args[3], (list, tuple)) and args[3]:
                flags.add("args")
            cli = next((a.ref["cli_rec"] for a in args if isinstance(a, W) and a.tag == "cmd"
                        and a.ref.get("cli_rec") is not None), None)
            if cli is not None:
                return W("cli", cli)
            for a in args:
                if isinstance(a, W) and a.tag == "cmd":
                    flags |= a.ref["flags"]
                    injected, rec = a.ref["wrapper"] == "strace", a.ref["rec"]
                elif isinstance(a, W) and a.tag == "bytes":
                    rec = a.ref
            run = self.new_run(flags, injected, rec)
            if name == "run_x86_64_elf":
                run.exit = 0
                return W("stdout", run)
            return W("run", run)
        if "fs" in segs[:-1] and (name in FS_WRITE or name in FS_READ):
            # Files the program reads or writes at run time live in temporary run directories;
            # repo paths are fixture/stdlib audits and strace logs are fault-injection plumbing.
            if not has_ident(group.items, ["trace"]) and not any(isinstance(a, PathV) for a in args):
                self.fs_event("write" if name in FS_WRITE else "read")
            return UNK
        if "compile" in name or CHECK_RE.search(name):
            return self.compile(name, args)
        return UNK

    def call_local(self, name, args):
        params, body = self.fns[name]
        if name in self.stack or len(self.stack) > 8:
            return UNK
        env = dict(self.consts)
        env.update(zip(params, args))
        self.stack.append(name)
        self.rets.append(None)
        try:
            tail = self.exec_block(body.items, env)
        finally:
            self.stack.pop()
            ret = self.rets.pop()
        return tail if tail is not None else (ret if ret is not None else UNK)

    def method(self, v, name, args):
        tag = v.tag if isinstance(v, W) else None
        if tag == "result":
            if name in ("expect_err", "unwrap_err", "err", "is_err"):
                v.ref.outcome = "err"
                return W("err", v.ref)
            if name in ("expect", "unwrap", "unwrap_or_else", "is_ok", "ok"):
                v.ref.outcome = v.ref.outcome or "ok"
                return W("bytes", v.ref) if name != "is_ok" else UNK
            return v if name in ("map_err", "as_ref") else UNK
        if tag == "bytes":
            return v if name in IDENTITY_METHODS else UNK
        if name == "contains" and args and isinstance(args[0], str) and LNC_RE.match(args[0]) and self.cur:
            self.cur.code = self.cur.code or str(args[0])
        if tag == "err":
            return W("code", v.ref) if name == "code" else (v if name not in ("contains", "is_some", "is_none") else UNK)
        if tag == "status":
            return W({"code": "exit", "signal": "signal", "success": "success"}.get(name, "?"), v.ref) \
                if name in ("code", "signal", "success") else UNK
        if tag == "stdout":
            return W("empty", v.ref) if name == "is_empty" else (v if name in IDENTITY_METHODS | {"as_bytes"} else UNK)
        if tag == "cli_status":
            return W("cli_success", v.ref) if name == "success" else UNK
        if tag == "cli_text":
            if name == "contains" and args and isinstance(args[0], str):
                code = LNC_ANY.search(args[0])
                if code:
                    v.ref.code = v.ref.code or code.group()
                return UNK
            return v if name in IDENTITY_METHODS else UNK
        if tag == "cmd":
            spec = v.ref
            if name in ("arg", "args") and not spec["wrapper"]:
                listed = name == "args" and args and isinstance(args[0], (list, tuple))
                self.cli_args(spec, args[0] if listed else args[:1])
            if name in ("output", "status", "spawn") and spec.get("cli_rec") is not None:
                return W("cli", spec["cli_rec"])
            if name in ("arg", "args") and not spec["wrapper"]:
                spec["flags"].add("args")
            elif name == "current_dir":
                spec["flags"].add("cwd")
            elif name in ("env", "envs", "env_clear", "env_remove"):
                spec["flags"].add("env")
            elif name == "stdin" and not (args and isinstance(args[0], W) and args[0].tag == "null"):
                spec["flags"].add("stdin")
            elif name == "arg" and args and isinstance(args[0], W) and args[0].tag == "bytes":
                spec["rec"] = args[0].ref                 # strace/timeout wrapping the fixture
            elif name in ("stdout", "stderr") and not (args and isinstance(args[0], W) and args[0].tag in ("null", "piped")):
                spec["flags"].add("stdout-redirect")
            elif name in ("output", "status", "spawn"):
                flags = set(spec["flags"]) | ({"wrapper"} if spec["wrapper"] not in (None, "strace") else set())
                run = self.new_run(flags, spec["wrapper"] == "strace", spec["rec"])
                return W("status" if name == "status" else "run", run)
            return v
        if tag == "run":
            return v if name in IDENTITY_METHODS | {"wait_with_output", "wait"} else UNK
        if tag == "temp":
            if name in ("write_str", "write_bytes") and args:
                v.ref[0] = args[0]
                return UNK
            if name == "path":
                return v.ref[0] if v.ref[0] is not None else W("tempdir")
            return UNK
        if isinstance(v, Derived):
            return v if name in IDENTITY_METHODS else UNK
        if tag == "tempdir":
            if name == "exists":
                self.fs_event("read")
            return v if name in ("join", "to_path_buf", "clone", "as_path") else UNK
        if isinstance(v, PathV):
            if name == "join" and args and isinstance(args[0], str) and not v.text:
                return PathV(v.path / args[0], False, getattr(args[0], "line", 0) or v.line)
            if name == "replace" and v.text:
                return Derived([v], "replace")
            return v if name in IDENTITY_METHODS else UNK
        if isinstance(v, str):
            if name == "as_bytes":
                return mk(B, v.encode(), v.line if isinstance(v, S) else 0, getattr(v, "computed", False))
            if name in ("repeat", "replace", "trim", "to_uppercase", "to_lowercase"):
                return mk(S, v, 0, computed=True)
            return v if name in IDENTITY_METHODS else UNK
        if isinstance(v, bytes):
            return v if name in IDENTITY_METHODS else (mk(B, v, 0, True) if name == "repeat" else UNK)
        if isinstance(v, (list, tuple)):
            if name == "enumerate":
                return list(enumerate(v))
            if name in ("concat", "join") and any(isinstance(x, PathV) and x.text for x in v):
                return Derived([x for x in v if isinstance(x, PathV)], "concat")
            return v if name in IDENTITY_METHODS else UNK
        if "compile" in name:                     # e.g. GpuCompiler::compile_source_to_x86_64
            return self.compile(name, args)
        if CHECK_RE.search(name) and any(isinstance(a, PathV) for a in args):
            return self.compile(name, args)
        return UNK

    def cli_args(self, spec, values):
        """`laniusc check|build FIXTURE ...` compiles FIXTURE; the command's exit status and
        stderr are the compile's outcome, not a run of the program."""
        for value in values:
            spec["argc"] = spec.get("argc", 0) + 1
            if spec["argc"] == 1 and isinstance(value, str) and value in CLI_COMPILES:
                spec["cli"] = str(value)
            elif spec.get("cli") and spec.get("cli_rec") is None and isinstance(value, PathV) \
                    and not value.text and value.path.suffix == ".lani":
                rec = Record([value], "check" if spec["cli"] == "check" else "build", None, "cli", self.test)
                self.records.append(rec)
                self.cur = rec
                spec["cli_rec"] = rec

    def field(self, v, name):
        if isinstance(v, W) and v.tag == "cli":
            return W("cli_status", v.ref) if name == "status" else \
                W("cli_text", v.ref) if name in ("stderr", "stdout") else UNK
        if isinstance(v, W) and v.tag == "run":
            return W(name, v.ref) if name in ("status", "stdout") else UNK
        if isinstance(v, W) and v.tag == "err":
            return W("code", v.ref) if name == "code" else v
        if isinstance(v, (tuple, list)) and name.isdigit() and int(name) < len(v):
            return v[int(name)]
        return UNK

    # -- records, runs, asserts
    def compile(self, name, args):
        rec = Record([], "check" if CHECK_RE.search(name) else "build", None,
                     "tuple" if self.table else "macro" if self.from_macro or self.macro_depth else
                     "helper" if self.stack else "body-assert", self.test)
        dirs = []

        def walk(v):
            if isinstance(v, PathV):
                (rec.progs if v.path.suffix == ".lani" else dirs).append(v)
            elif isinstance(v, Derived):
                rec.derived = v.how
                rec.progs.extend(v.progs)
            elif isinstance(v, str) and "fn main" in v:
                rec.inline_main = True
            elif isinstance(v, (list, tuple)):
                for x in v:
                    walk(x)
            elif isinstance(v, W) and v.tag == "tempdir":
                dirs.append(v)
        for a in args:
            walk(a)
        if dirs:
            rec.stdlib = dirs[0]
        elif "stdlib" in name or "root" in name:
            rec.stdlib = UNK
        self.records.append(rec)
        self.cur = rec
        return W("result", rec)

    def new_run(self, flags, injected, rec=None):
        """A run belongs to the compile whose bytes it executes, else to the latest compile."""
        run = Run(flags, injected)
        if (rec or self.cur) is not None:
            (rec or self.cur).runs.append(run)
        return run

    def fs_event(self, kind):
        if self.cur is not None:
            self.cur.fs.append((kind, len(self.cur.runs)))

    def cond(self, items, env):
        for part in split(items, "&&"):
            eq = find(part, lambda x: is_p(x, "=="))
            if eq < len(part):
                self.eq(self.ev(part[:eq], env), self.ev(part[eq + 1:], env))
                continue
            v = self.ev(part, env)
            if isinstance(v, W) and v.tag == "empty" and v.ref.stdout is MISSING:
                v.ref.stdout = b""
            elif isinstance(v, W) and v.tag == "success" and v.ref.exit is MISSING:
                v.ref.exit = 0
            elif isinstance(v, W) and v.tag == "cli_success":
                v.ref.outcome = v.ref.outcome or "ok"
            elif isinstance(v, W) and v.tag == "not" and isinstance(v.ref, W) and v.ref.tag == "cli_success":
                v.ref.ref.outcome = "err"

    def eq(self, a, b):
        if isinstance(a, (tuple, list)) and isinstance(b, (tuple, list)) and len(a) == len(b):
            for x, y in zip(a, b):
                self.eq(x, y)
            return
        for x, y in ((a, b), (b, a)):
            if isinstance(y, str) and LNC_RE.match(y) and self.cur is not None:
                target = x.ref if isinstance(x, W) and x.tag == "code" else self.cur
                target.code = target.code or str(y)
                return
            if not isinstance(x, W) or x.tag not in ("exit", "signal", "stdout"):
                continue
            run = x.ref
            if x.tag == "stdout":
                if run.stdout is MISSING:
                    run.stdout = (COMPUTED if getattr(y, "computed", False) else bytes(y)) if isinstance(y, bytes) \
                        else (COMPUTED if getattr(y, "computed", False) else y.encode()) if isinstance(y, str) \
                        else COMPUTED
            elif getattr(run, x.tag) is MISSING:
                value = y if isinstance(y, int) and not isinstance(y, bool) else RNONE if y is RNONE else COMPUTED
                setattr(run, x.tag, value)
            return


# ---------------------------------------------------------------- expectations
def module_dir(path: Path) -> bool:
    return any(part.endswith("_root") or part == "stdlib" for part in path.parts[:-1])


@functools.lru_cache(maxsize=None)
def has_main(path: Path) -> bool:
    try:
        return re.search(r"\bfn\s+main\s*\(", path.read_text()) is not None
    except OSError:
        return False


def _int(v):
    return v if isinstance(v, int) and not isinstance(v, bool) else None


def from_record(rec: Record, rel: str, repo: Path):
    if rec.inline_main or rec.derived == "replace":
        return []
    entries = [p for p in rec.progs if not module_dir(p.path.relative_to(repo) if p.path.is_relative_to(repo)
                                                      else p.path) and has_main(p.path)]
    if not entries:
        return []
    harness, notes = set(), []
    stdlib_root = None
    modules = [p.path for p in rec.progs if p not in entries]
    if modules and rec.derived != "concat":
        harness.add("source-pack")
        roots = [Path(*p.parts[:next(k for k, s in enumerate(p.parts) if s.endswith("_root")) + 1])
                 for p in modules if any(s.endswith("_root") for s in p.parts)]
        stdlib_root = roots[0] if roots else None
    if rec.derived == "concat":
        harness.add("source-concat")
    if isinstance(rec.stdlib, PathV) and rec.stdlib.path.resolve() != (repo / "stdlib").resolve():
        stdlib_root = rec.stdlib.path
    elif rec.stdlib is UNK or isinstance(rec.stdlib, W):
        harness.add("generated-stdlib")
    for run in rec.runs:
        harness |= run.flags
        harness |= {"fault-injection"} if run.injected else set()
    if any(k == "write" and idx < len(rec.runs) or k == "read" and idx > 0 for k, idx in rec.fs):
        harness.add("files")
    plain = [r for r in rec.runs if not r.injected]
    checked = [r for r in plain if r.exit is not MISSING or r.signal is not MISSING or r.stdout is not MISSING]
    primary = next((r for r in checked if not r.flags), None) or (checked or plain or [None])[0]
    if len({(repr(r.exit), repr(r.signal), repr(r.stdout)) for r in checked}) > 1:
        harness.add("multiple-expectations")
    exit_code = signal = stdout = None
    if rec.outcome == "err" or rec.code:
        kind = "compile_error"
    elif primary is not None and rec.kind == "build":
        kind = "run"
        exit_code, signal = _int(primary.exit), _int(primary.signal)
        stdout = primary.stdout if isinstance(primary.stdout, bytes) else None
        if primary.stdout is COMPUTED:
            notes.append("stdout computed")
        if primary.flags:
            notes.append("primary run needs " + ",".join(sorted(primary.flags)))
    elif rec.runs and rec.kind == "build":
        kind = "run"
        notes.append("only runs under fault injection")
    else:
        kind = "check_only"
        notes.append("compile-only" if rec.kind == "build" else "type-check")
    out = []
    for p in entries:
        source = f"{rel}:{p.line} {rec.prov} {rec.test}" + "".join(f"; {n}" for n in notes)
        out.append(Expectation(p.path, kind, exit_code, signal, stdout,
                               rec.code if kind == "compile_error" else None,
                               stdlib_root, sorted(harness), source))
    return out


def _rank(e: Expectation):
    checked = e.exit_code is not None or e.signal is not None
    plain = not (set(e.harness) - {"multiple-expectations"})
    return (e.kind != "run", not checked, not plain, e.stdout is None, e.kind != "compile_error")


def merge(cands: list[Expectation]):
    best = min(cands, key=_rank)
    runs = [c for c in cands if c.kind == "run" and (c.exit_code is not None or c.signal is not None)]
    conflict = len({(c.exit_code, c.signal, c.stdlib_root) for c in runs}) > 1 or (
        runs and any(c.kind == "compile_error" for c in cands))
    stdouts = {c.stdout for c in runs if c.stdout is not None and (c.exit_code, c.signal) == (best.exit_code, best.signal)}
    conflict = conflict or len(stdouts) > 1
    if best.stdout is None and len(stdouts) == 1 and best.kind == "run":
        best.stdout = next(iter(stdouts))
    if conflict:
        best.harness = sorted(set(best.harness) | {"multiple-expectations"})
    if len(cands) > 1:
        best.source += f" (+{len(cands) - 1} more)"
    return best, conflict


def fixture_paths(repo: Path):
    base = repo / FOUNDATION
    paths = sorted(base.glob("*.lani"))
    paths += sorted(p for p in base.rglob("*.lani") if p.parent != base and not module_dir(p.relative_to(base)))
    for d in GENERICS:
        paths += sorted((repo / d).glob("*.lani"))
    return paths


def load_expectations(repo_root: Path = ROOT, *, with_report: bool = False):
    repo_root = Path(repo_root).resolve()
    by_path: dict[Path, list[Expectation]] = {}
    errors, texts, modified = [], {}, set()
    sys.setrecursionlimit(max(sys.getrecursionlimit(), 20000))
    for rs in sorted((repo_root / "tests").glob("*.rs")):
        text = rs.read_text()
        if not any(marker in text for marker in ("stdlib_foundation", "generics_matrix", "generics_backlog")):
            continue
        texts[rs] = text
        interp = Interp(repo_root, rs)
        rel = str(rs.relative_to(repo_root))
        for rec in interp.run_tests():
            if rec.derived == "replace":
                modified.update(p.path.resolve() for p in rec.progs)
            for e in from_record(rec, rel, repo_root):
                by_path.setdefault(e.path.resolve(), []).append(e)
        errors += interp.errors
    result, conflicts = [], []
    for path in fixture_paths(repo_root):
        rel = str(path.relative_to(repo_root))
        generics = rel.startswith(GENERICS)
        first = path.read_text().split("\n", 1)[0]
        override = EXPECT_RE.match(first.strip())
        if not has_main(path):
            e = Expectation(path, "module", None, None, None, None, None, [], "no fn main")
        elif path.resolve() in by_path:
            e, conflict = merge(by_path[path.resolve()])
            if conflict:
                conflicts.append(rel)
        else:
            word = re.compile(r"(?<![\w-])" + re.escape(path.stem) + r"(?![\w-])")
            refs = [r.name for r, t in texts.items() if path.stem in t and word.search(t)] if not generics else []
            reject = path.name.startswith("reject") or "/reject/" in rel
            e = Expectation(path, "compile_error" if reject else "run", None if reject else (42 if generics else 0),
                            None, None, None, None, [],
                            "default" + (":name-reject" if reject else ":generics" if generics else "")
                            + (" (tests only compile modified copies)" if path.resolve() in modified else
                               f" (unresolved refs: {', '.join(refs[:3])})" if refs else ""))
        if override and e.kind != "module":
            e.kind, e.exit_code, e.signal = "run", int(override.group(1)), None
            e.source = "expect-comment" + ("" if e.source.startswith("default") else f"; tests: {e.source}")
        result.append(e)
    if with_report:
        return result, {"conflicts": conflicts, "errors": errors}
    return result


# ---------------------------------------------------------------- CLI
def _provenance(e: Expectation) -> str:
    if e.kind == "module":
        return "module"
    if e.source.startswith("tests/"):
        return e.source.split(" ", 2)[1]
    return re.match(r"[a-z-]+", e.source).group()


def _show(b: bytes | None) -> str:
    if b is None:
        return "-"
    s = repr(b)[1:]
    return s if len(s) <= 40 else s[:37] + "...'"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--json", action="store_true", help="print expectations as JSON")
    parser.add_argument("--summary", action="store_true", help="print counts instead of per-fixture lines")
    parser.add_argument("--repo", default=str(ROOT))
    args = parser.parse_args(argv)
    repo = Path(args.repo).resolve()
    exps, report = load_expectations(repo, with_report=True)
    if args.json:
        def enc(e):
            d = asdict(e)
            d["path"] = str(e.path.relative_to(repo))
            d["stdlib_root"] = str(e.stdlib_root.relative_to(repo)) if e.stdlib_root else None
            d["stdout"] = e.stdout.decode("utf-8", "backslashreplace") if e.stdout is not None else None
            return d
        json.dump([enc(e) for e in exps], sys.stdout, indent=1)
        print()
        return
    if not args.summary:
        for e in exps:
            status = f"exit={e.exit_code}" if e.signal is None else f"signal={e.signal}"
            extra = f" {e.error_code}" if e.error_code else ""
            root = f" stdlib={e.stdlib_root.relative_to(repo)}" if e.stdlib_root else ""
            harness = f" harness={','.join(e.harness)}" if e.harness else ""
            print(f"{e.path.relative_to(repo)}\t{e.kind}{extra} {status} stdout={_show(e.stdout)}{root}{harness}"
                  f"\t[{e.source}]")
        return
    kinds = Counter(e.kind for e in exps)
    provs = Counter(_provenance(e) for e in exps)
    harness = Counter(h for e in exps for h in e.harness)
    print(f"fixtures: {len(exps)}")
    print("by kind:       " + ", ".join(f"{k}={v}" for k, v in kinds.most_common()))
    print("by provenance: " + ", ".join(f"{k}={v}" for k, v in provs.most_common()))
    print(f"default fallback: {sum(e.source.startswith('default') for e in exps)}"
          f" (with unresolved test refs: {sum('unresolved refs' in e.source for e in exps)})")
    print(f"stdout checked: {sum(e.stdout is not None for e in exps)}, "
          f"nonzero exit or signal: {sum(bool(e.exit_code) or e.signal is not None for e in exps)}")
    print(f"needs harness: {sum(bool(e.harness) for e in exps)} -> "
          + ", ".join(f"{k}={v}" for k, v in harness.most_common()))
    print(f"conflicts: {len(report['conflicts'])}" + "".join(f"\n  {c}" for c in report["conflicts"]))
    if report["errors"]:
        print(f"test bodies not fully evaluated: {len(report['errors'])}" + "".join(f"\n  {x}" for x in report["errors"][:10]))


if __name__ == "__main__":
    main()
