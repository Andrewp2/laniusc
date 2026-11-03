#!/usr/bin/env python3
"""Generate `formal/Lanius/Faithful/SelfPre/HB.lean`: the list height `hb` of every
type of the verified compiler's front end and compiler (F14).

`hb` counts list cells along the deepest path through a value: `hb (a :: l) =
max (hb a) (hb l) + 1`, an `Option` or a structure is the max of its parts, a
number counts nothing except a token's `start`. A list is at most its height
long (`length_le_hb`), and a cell costs the self program one box, so a run's
result is at most as high as its arguments plus the run's allocations.

Usage: hb_gen.py OUT.lean TYPES.lean...
"""
import re
import sys

FLAT_ATOMS = {'Nat', 'Bool', 'UInt8'}


def parse(paths):
    """[(kind, name, fields_or_ctors)] in file order. A structure's fields are
    [(name, type)]; an inductive's constructors are [(name, [argtype])]."""
    out = []
    for p in paths:
        lines = open(p).read().split('\n')
        i = 0
        while i < len(lines):
            m = re.match(r'(structure|inductive) (\w+) where\s*$', lines[i])
            if not m:
                i += 1
                continue
            kind, name = m.groups()
            items = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith('deriving') and lines[i].strip():
                s = lines[i].strip()
                i += 1
                if s.startswith('--') or s.startswith('/--') or s.startswith('-/'):
                    continue
                if kind == 'structure':
                    f = re.match(r'(\w+) : (.+)$', s)
                    if f:
                        items.append((f.group(1), f.group(2).strip()))
                else:
                    c = re.match(r'\| (\w+) : (.+)$', s)
                    if c:
                        parts = split_arrows(c.group(2))
                        assert parts[-1] == name, (name, s)
                        items.append((c.group(1), parts[:-1]))
            out.append((kind, name, items))
    return out


def split_arrows(s):
    parts, depth, cur = [], 0, ''
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if depth == 0 and s.startswith('→', i):
            parts.append(cur.strip())
            cur = ''
            i += 1
            continue
        cur += ch
        i += 1
    parts.append(cur.strip())
    return [strip_parens(p) for p in parts]


def strip_parens(t):
    t = t.strip()
    while t.startswith('(') and t.endswith(')') and balanced(t[1:-1]):
        t = t[1:-1].strip()
    return t


def balanced(t):
    d = 0
    for ch in t:
        d += ch == '('
        d -= ch == ')'
        if d < 0:
            return False
    return d == 0


def head(t):
    """('List', inner) / ('Option', inner) / ('BitVec', None) / (name, None)."""
    t = strip_parens(t)
    m = re.match(r'(List|Option) (.+)$', t)
    if m:
        return m.group(1), strip_parens(m.group(2))
    if t.startswith('BitVec'):
        return 'BitVec', None
    return t, None


class Gen:
    def __init__(self, decls):
        self.decls = decls
        self.byname = {n: (k, it) for k, n, it in decls}
        self.flat = {}

    def is_flat(self, t, self_name=None):
        h, inner = head(t)
        if h == 'List':
            return False
        if h == 'Option':
            return self.is_flat(inner, self_name)
        if h in FLAT_ATOMS or h == 'BitVec':
            return True
        if h == self_name:
            return False
        if h not in self.flat:
            raise KeyError(f'type {h} used before its definition')
        return self.flat[h]

    def mentions(self, t, name):
        return re.search(r'\b' + name + r'\b', t) is not None

    def emit(self):
        out = [HEADER]
        for kind, name, items in self.decls:
            if kind == 'structure':
                out.append(self.structure(name, items))
            else:
                out.append(self.inductive(name, items))
        out.append(FOOTER)
        return '\n'.join(out)

    # structures -----------------------------------------------------------

    def field_hb(self, name, f, t, x):
        if name == 'Token' and f == 'start':
            return x
        return f'hb {x}'

    def structure(self, name, fields):
        live = [(f, t) for f, t in fields if not self.is_flat(t) or (name == 'Token' and f == 'start')]
        self.flat[name] = not live
        if not live:
            return (f'instance : HB {Q(name)} := ⟨fun _ => 0⟩\n'
                    f'@[simp, hb_simp] theorem hb_{name} (x : {Q(name)}) : hb x = 0 := rfl\n'
                    f'@[simp, hb_simp] theorem hb_opt_{name} (x : Option {Q(name)}) : hb x = 0 := by cases x <;> rfl\n')
        body = maxes([self.field_hb(name, f, t, f's.{f}') for f, t in live])
        xs = [f'a{i}' for i in range(len(fields))]
        mk_body = maxes([self.field_hb(name, f, t, xs[i]) for i, (f, t) in enumerate(fields) if (f, t) in live])
        binders = ' '.join(f'({xs[i]} : {qt(t)})' for i, (f, t) in enumerate(fields))
        lines = [f'instance : HB {Q(name)} := ⟨fun s => {body}⟩',
                 f'@[simp, hb_simp] theorem hb_{name}_mk {binders} : hb ({Q(name)}.mk {" ".join(xs)}) = {mk_body} := rfl']
        for f, t in live:
            lhs = 's.' + f if (name == 'Token' and f == 'start') else f'hb s.{f}'
            lines.append(f'theorem hb_le_{name}_{f} (s : {Q(name)}) : {lhs} ≤ hb s := by\n'
                         f'  show _ ≤ {body}\n  omega')
        return '\n'.join(lines) + '\n'

    # inductives -----------------------------------------------------------

    def inductive(self, name, ctors):
        recursive = any(self.mentions(t, name) for _, ts in ctors for t in ts)
        live = any(not self.is_flat(t, name) for _, ts in ctors for t in ts)
        self.flat[name] = not live
        if not live:
            return (f'instance : HB {Q(name)} := ⟨fun _ => 0⟩\n'
                    f'@[simp, hb_simp] theorem hb_{name} (x : {Q(name)}) : hb x = 0 := rfl\n'
                    f'@[simp, hb_simp] theorem hb_opt_{name} (x : Option {Q(name)}) : hb x = 0 := by cases x <;> rfl\n')
        shapes = {}  # nested type text -> (helper name, 'List'/'Option', inner text)

        def fn_of(t):
            """The function measuring t inside the block: hbT for T itself, a helper
            for a list or option around T, None when t does not mention T."""
            t = strip_parens(t)
            if not self.mentions(t, name):
                return None
            if t == name:
                return f'hb{name}'
            if t not in shapes:
                h, inner = head(t)
                fn_of(inner)
                shapes[t] = (f'hb{name}{len(shapes)}', h, inner)
            return shapes[t][0]

        arms = []
        for c, ts in ctors:
            xs = [f'a{i}' for i in range(len(ts))]
            parts = []
            for x, t in zip(xs, ts):
                if self.is_flat(t, name):
                    continue
                g = fn_of(t)
                parts.append(f'{g} {x}' if g else f'hb {x}')
            arms.append((c, ts, xs, maxes(parts) if parts else '0'))
        defs = [f'def hb{name} : {Q(name)} → Nat\n' +
                '\n'.join(f'  | .{c}{"".join(" " + x for x in xs)} => {body}' for c, ts, xs, body in arms)]
        for t, (g, h, inner) in shapes.items():
            sub = fn_of(inner) or 'hb'
            if h == 'List':
                defs.append(f'def {g} : {qt(t)} → Nat\n  | [] => 0\n  | a :: l => max ({sub} a) ({g} l) + 1')
            else:
                defs.append(f'def {g} : {qt(t)} → Nat\n  | none => 0\n  | some a => {sub} a')
        text = ('mutual\n' + '\n'.join(defs) + '\nend\n') if recursive else '\n'.join(defs) + '\n'
        text += f'instance : HB {Q(name)} := ⟨hb{name}⟩\n'
        eqs = []
        for t, (g, h, inner) in sorted(shapes.items(), key=lambda kv: depth_of(kv[0])):
            inner_eq = [shapes[inner][0] + '_eq'] if inner in shapes else []
            if h == 'List':
                rws = [f'{g}_eq l'] + [e + ' a' for e in inner_eq]
                text += (f'theorem {g}_eq : ∀ l : {qt(t)}, {g} l = HB.hb l\n'
                         f'  | [] => rfl\n'
                         f'  | a :: l => by\n'
                         f'    show max _ _ + 1 = max _ _ + 1\n'
                         f'    (rw [{", ".join(rws)}]) <;> rfl\n')
            else:
                text += (f'theorem {g}_eq : ∀ o : {qt(t)}, {g} o = HB.hb o\n'
                         f'  | none => rfl\n'
                         f'  | some a => by\n'
                         f'    show _ = HB.hb a\n' +
                         (f'    (rw [{inner_eq[0]} a]) <;> rfl\n' if inner_eq else '    rfl\n'))
            eqs.append(f'{g}_eq')
        for c, ts, xs, body in arms:
            binders = ' '.join(f'({x} : {qt(t)})' for x, t in zip(xs, ts))
            parts = [f'hb {x}' for x, t in zip(xs, ts) if not self.is_flat(t, name)]
            rhs = maxes(parts) if parts else '0'
            used = sorted({fn_of(t) + '_eq' for x, t in zip(xs, ts)
                           if not self.is_flat(t, name) and fn_of(t) not in (None, f'hb{name}')})
            proof = (f'by show hb{name} _ = _; simp only [hb{name}{"".join(", " + e for e in used)}] <;> rfl'
                     if used else 'rfl')
            text += (f'@[simp, hb_simp] theorem hb_{name}_{c} {binders} : '
                     f'hb ({Q(name)}.{c}{"".join(" " + x for x in xs)}) = {rhs} := {proof}\n')
        return text


TYPES = set()


def Q(name):
    return 'Lanius.Mini.' + name


def qt(t):
    return re.sub(r'\b([A-Z]\w*)\b', lambda m: Q(m.group(1)) if m.group(1) in TYPES else m.group(1), t)


def key_ty(key):
    return key


def depth_of(key):
    return key.count('List') + key.count('Option')


def maxes(parts):
    if len(parts) == 1:
        return parts[0]
    return f'max ({parts[0]}) ({maxes(parts[1:])})' if len(parts) > 2 else f'max ({parts[0]}) ({parts[1]})'


HEADER = '''import Lanius.Mini.Frontend.Types
import Lanius.Faithful.SelfPre.HBAttr

/-! Generated by formal/tools/hb_gen.py: the list height `hb` of the front end's and the
compiler's types (F14). Do not edit.

A list cell adds one to the higher of its head and its tail; an `Option` or a
structure is as high as its highest part; numbers count nothing except a
token's `start`. A list is at most as long as it is high (`length_le_hb`). -/

set_option linter.unusedVariables false

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

/-- The list height of a value. -/
class HB (α : Type) where
  hb : α → Nat

export HB (hb)

def hbList {α : Type} [HB α] : List α → Nat
  | [] => 0
  | a :: l => max (hb a) (hbList l) + 1

instance {α : Type} [HB α] : HB (List α) := ⟨hbList⟩

def hbOption {α : Type} [HB α] : Option α → Nat
  | none => 0
  | some a => hb a

instance {α : Type} [HB α] : HB (Option α) := ⟨hbOption⟩
instance : HB Nat := ⟨fun _ => 0⟩
instance : HB Bool := ⟨fun _ => 0⟩
instance : HB UInt8 := ⟨fun _ => 0⟩
instance {w : Nat} : HB (BitVec w) := ⟨fun _ => 0⟩

@[simp, hb_simp] theorem hb_nat (x : Nat) : hb x = 0 := rfl
@[simp, hb_simp] theorem hb_bool (x : Bool) : hb x = 0 := rfl
@[simp, hb_simp] theorem hb_uint8 (x : UInt8) : hb x = 0 := rfl
@[simp, hb_simp] theorem hb_bitvec {w : Nat} (x : BitVec w) : hb x = 0 := rfl
@[simp, hb_simp] theorem hb_opt_nat (x : Option Nat) : hb x = 0 := by cases x <;> rfl
@[simp, hb_simp] theorem hb_opt_bool (x : Option Bool) : hb x = 0 := by cases x <;> rfl
@[simp, hb_simp] theorem hb_opt_uint8 (x : Option UInt8) : hb x = 0 := by cases x <;> rfl
@[simp, hb_simp] theorem hb_opt_bitvec {w : Nat} (x : Option (BitVec w)) : hb x = 0 := by cases x <;> rfl
@[simp, hb_simp] theorem hb_nil {α : Type} [HB α] : hb ([] : List α) = 0 := rfl
@[simp, hb_simp] theorem hb_cons {α : Type} [HB α] (a : α) (l : List α) : hb (a :: l) = max (hb a) (hb l) + 1 := rfl
@[simp, hb_simp] theorem hb_none {α : Type} [HB α] : hb (none : Option α) = 0 := rfl
@[simp, hb_simp] theorem hb_some {α : Type} [HB α] (a : α) : hb (some a) = hb a := rfl

attribute [hb_simp] Nat.zero_max Nat.max_zero Nat.max_self

/-- A list is at most as long as it is high. -/
theorem length_le_hb {α : Type} [HB α] : ∀ l : List α, l.length ≤ hb l
  | [] => Nat.le_refl _
  | a :: l => by simp only [List.length_cons, hb_cons]; have := length_le_hb l; omega

theorem hb_append {α : Type} [HB α] : ∀ xs ys : List α, hb (xs ++ ys) ≤ max (hb xs) (hb ys) + xs.length
  | [], ys => by simp
  | a :: xs, ys => by
    have := hb_append xs ys
    simp only [List.cons_append, hb_cons, List.length_cons]
    omega

theorem hb_le_of_mem {α : Type} [HB α] {a : α} : ∀ {l : List α}, a ∈ l → hb a < hb l
  | _ :: l, .head _ => by simp only [hb_cons]; omega
  | b :: l, .tail _ h => by have := hb_le_of_mem h; simp only [hb_cons]; omega
'''

FOOTER = '''end Lanius.Faithful.SelfPre
'''


def main():
    out, paths = sys.argv[1], sys.argv[2:]
    decls = parse(paths)
    TYPES.update(n for _, n, _ in decls)
    g = Gen(decls)
    open(out, 'w').write(g.emit())


if __name__ == '__main__':
    main()
