#!/usr/bin/env python3
"""Generate `formal/Lanius/Faithful/SelfPre/HB.lean`: the list height `hb` of every
type of the verified compiler's front end and compiler (F14).

`hb` counts list cells along the deepest path through a value: `hb (a :: l) =
max (hb a) (hb l) + 1`, an `Option` or a structure is the max of its parts, a
number counts nothing except a token's `start`. A list is at most its height
long (`length_le_hb`), and a cell costs the self program one box, so a run's
result is at most as high as its arguments plus the run's allocations.

With `--sum` it generates `SelfPre/SZ.lean` instead: the total size `sz`, every
node counted once: `sz (a :: l) = sz a + sz l + 1`, a constructor of a type with
lists in it adds one to the sum of its arguments, an `Option` or a structure is
the sum of its parts, numbers (a token's `start` too) and types without lists
count nothing. Sharing does not make a value smaller, so a function that copies
a part of its argument can return a value larger than its argument plus its cost;
sizes bound sums over a value (a list is at most its size long, and the sum over
a list of its elements' sizes is at most its size).

With `--slots` it generates `SelfPre/TS.lean`, the largest slot count `ts`: a
`SrcType` counts `tySlots`, the largest `SrcType.size` of it and of every type
inside it, anything else the max of its parts. It is a max, so a value
shared or copied many times is no larger for it.

Usage: hb_gen.py [--sum | --slots] OUT.lean TYPES.lean...
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
    def __init__(self, decls, mode='hb'):
        self.mode = mode
        self.sum = mode == 'sz'
        self.m = mode
        # ts counts one type's slots; a type without it counts nothing
        self.focus = 'SrcType' if mode == 'ts' else None
        self.decls = decls
        self.byname = {n: (k, it) for k, n, it in decls}
        self.flat = {}

    def is_flat(self, t, self_name=None, self_flat=None):
        """Whether t counts nothing. A reference to self_name, the type being
        defined, counts as self_flat (default: only in `ts` mode, where whether the
        type counts anything is decided by its other parts)."""
        h, inner = head(t)
        if h == 'List':
            return self.is_flat(inner, self_name, self_flat) if self.mode == 'ts' else False
        if h == 'Option':
            return self.is_flat(inner, self_name, self_flat)
        if h in FLAT_ATOMS or h == 'BitVec':
            return True
        if h == self_name:
            return self.mode == 'ts' if self_flat is None else self_flat
        if h == self.focus:
            return False
        if h not in self.flat:
            raise KeyError(f'type {h} used before its definition')
        return self.flat[h]

    def mentions(self, t, name):
        return re.search(r'\b' + name + r'\b', t) is not None

    def emit(self):
        out = [{'hb': HEADER, 'sz': SZ_HEADER, 'ts': TS_HEADER}[self.mode]]
        for kind, name, items in self.decls:
            if kind == 'structure':
                out.append(self.structure(name, items))
            else:
                out.append(self.inductive(name, items))
        out.append(FOOTER)
        return '\n'.join(out)

    def comb(self, parts):
        """The parts' max (height) or sum (size)."""
        return sums(parts) if self.sum else maxes(parts)

    def node(self, parts):
        """A constructor of a type with lists: its parts' max, or one more than their sum."""
        if self.mode in ('hb', 'ts'):
            return maxes(parts) if parts else '0'
        return sums(parts + ['1']) if parts else '1'

    def flat_inst(self, name):
        m, M = self.m, self.m.upper()
        return (f'instance : {M} {Q(name)} := ⟨fun _ => 0⟩\n'
                f'@[simp, {m}_simp] theorem {m}_{name} (x : {Q(name)}) : {m} x = 0 := rfl\n'
                f'@[simp, {m}_simp] theorem {m}_opt_{name} (x : Option {Q(name)}) : {m} x = 0 := by cases x <;> rfl\n')

    # structures -----------------------------------------------------------

    def field_hb(self, name, f, t, x):
        if name == 'Token' and f == 'start' and self.mode == 'hb':
            return x
        return f'{self.m} {x}'

    def structure(self, name, fields):
        start = name == 'Token' and self.mode == 'hb'
        live = [(f, t) for f, t in fields if not self.is_flat(t) or (start and f == 'start')]
        self.flat[name] = not [(f, t) for f, t in fields if not self.is_flat(t)] and not start
        if not live:
            return self.flat_inst(name)
        m, M = self.m, self.m.upper()
        body = self.comb([self.field_hb(name, f, t, f's.{f}') for f, t in live])
        xs = [f'a{i}' for i in range(len(fields))]
        mk_body = self.comb([self.field_hb(name, f, t, xs[i]) for i, (f, t) in enumerate(fields) if (f, t) in live])
        binders = ' '.join(f'({xs[i]} : {qt(t)})' for i, (f, t) in enumerate(fields))
        lines = [f'instance : {M} {Q(name)} := ⟨fun s => {body}⟩',
                 f'@[simp, {m}_simp] theorem {m}_{name}_mk {binders} : {m} ({Q(name)}.mk {" ".join(xs)}) = {mk_body} := rfl']
        for f, t in live:
            lhs = 's.' + f if (start and f == 'start') else f'{m} s.{f}'
            lines.append(f'theorem {m}_le_{name}_{f} (s : {Q(name)}) : {lhs} ≤ {m} s := by\n'
                         f'  show _ ≤ {body}\n  omega')
        return '\n'.join(lines) + '\n'

    # inductives -----------------------------------------------------------

    def inductive(self, name, ctors):
        if self.mode == 'ts' and name == 'SrcType':
            self.flat[name] = False
            return ('instance : TS Lanius.Mini.SrcType := ⟨tySlots⟩\n'
                    '@[simp, ts_simp] theorem ts_SrcType (t : Lanius.Mini.SrcType) : ts t = tySlots t := rfl\n')
        recursive = any(self.mentions(t, name) for _, ts in ctors for t in ts)
        live = any(not self.is_flat(t, name) for _, ts in ctors for t in ts) or name == self.focus
        self.flat[name] = not live
        if not live:
            return self.flat_inst(name)
        m, M = self.m, self.m.upper()
        shapes = {}  # nested type text -> (helper name, 'List'/'Option', inner text)

        def fn_of(t):
            """The function measuring t inside the block: hbT for T itself, a helper
            for a list or option around T, None when t does not mention T."""
            t = strip_parens(t)
            if not self.mentions(t, name):
                return None
            if t == name:
                return f'{m}{name}'
            if t not in shapes:
                h, inner = head(t)
                fn_of(inner)
                shapes[t] = (f'{m}{name}{len(shapes)}', h, inner)
            return shapes[t][0]

        arms = []
        for c, ts in ctors:
            xs = [f'a{i}' for i in range(len(ts))]
            parts = []
            for x, t in zip(xs, ts):
                if self.is_flat(t, name, False):
                    continue
                g = fn_of(t)
                parts.append(f'{g} {x}' if g else f'{m} {x}')
            arms.append((c, ts, xs, self.node(parts)))
        defs = [f'def {m}{name} : {Q(name)} → Nat\n' +
                '\n'.join(f'  | .{c}{"".join(" " + x for x in xs)} => {body}' for c, ts, xs, body in arms)]
        for t, (g, h, inner) in shapes.items():
            sub = fn_of(inner) or m
            if h == 'List':
                cell = {'sz': f'{sub} a + {g} l + 1', 'ts': f'max ({sub} a) ({g} l)'}.get(
                    self.mode, f'max ({sub} a) ({g} l) + 1')
                defs.append(f'def {g} : {qt(t)} → Nat\n  | [] => 0\n  | a :: l => {cell}')
            else:
                defs.append(f'def {g} : {qt(t)} → Nat\n  | none => 0\n  | some a => {sub} a')
        text = ('mutual\n' + '\n'.join(defs) + '\nend\n') if recursive else '\n'.join(defs) + '\n'
        text += f'instance : {M} {Q(name)} := ⟨{m}{name}⟩\n'
        eqs = []
        for t, (g, h, inner) in sorted(shapes.items(), key=lambda kv: depth_of(kv[0])):
            inner_eq = [shapes[inner][0] + '_eq'] if inner in shapes else []
            if h == 'List':
                rws = [f'{g}_eq l'] + [e + ' a' for e in inner_eq]
                cell = {'sz': '_ + _ + 1 = _ + _ + 1', 'ts': 'max _ _ = max _ _'}.get(
                    self.mode, 'max _ _ + 1 = max _ _ + 1')
                text += (f'theorem {g}_eq : ∀ l : {qt(t)}, {g} l = {M}.{m} l\n'
                         f'  | [] => rfl\n'
                         f'  | a :: l => by\n'
                         f'    show {cell}\n'
                         f'    (rw [{", ".join(rws)}]) <;> rfl\n')
            else:
                text += (f'theorem {g}_eq : ∀ o : {qt(t)}, {g} o = {M}.{m} o\n'
                         f'  | none => rfl\n'
                         f'  | some a => by\n'
                         f'    show _ = {M}.{m} a\n' +
                         (f'    (rw [{inner_eq[0]} a]) <;> rfl\n' if inner_eq else '    rfl\n'))
            eqs.append(f'{g}_eq')
        for c, ts, xs, body in arms:
            binders = ' '.join(f'({x} : {qt(t)})' for x, t in zip(xs, ts))
            parts = [f'{m} {x}' for x, t in zip(xs, ts) if not self.is_flat(t, name, False)]
            rhs = self.node(parts)
            used = sorted({fn_of(t) + '_eq' for x, t in zip(xs, ts)
                           if not self.is_flat(t, name, False) and fn_of(t) not in (None, f'{m}{name}')})
            proof = (f'by show {m}{name} _ = _; simp only [{m}{name}{"".join(", " + e for e in used)}] <;> rfl'
                     if used else 'rfl')
            text += (f'@[simp, {m}_simp] theorem {m}_{name}_{c} {binders} : '
                     f'{m} ({Q(name)}.{c}{"".join(" " + x for x in xs)}) = {rhs} := {proof}\n')
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


def sums(parts):
    return ' + '.join(f'({p})' if ' ' in p and not p.startswith('sz ') else p for p in parts) if parts else '0'


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

SZ_HEADER = '''import Lanius.Mini.Frontend.Types
import Lanius.Faithful.SelfPre.SZAttr

/-! Generated by formal/tools/hb_gen.py --sum: the total size `sz` of the front end's and
the compiler's types (F14). Do not edit.

Every node counts once: a list cell adds one to its head's and its tail's sizes, a
constructor of a type with lists in it one to its arguments' sizes; an `Option` or
a structure is the sum of its parts; numbers and types without lists count
nothing. A list is at most as long as its size (`length_le_sz`), and its elements'
sizes sum to less than its size. -/

set_option linter.unusedVariables false

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

/-- The total size of a value. -/
class SZ (α : Type) where
  sz : α → Nat

export SZ (sz)

def szList {α : Type} [SZ α] : List α → Nat
  | [] => 0
  | a :: l => sz a + szList l + 1

instance {α : Type} [SZ α] : SZ (List α) := ⟨szList⟩

def szOption {α : Type} [SZ α] : Option α → Nat
  | none => 0
  | some a => sz a

instance {α : Type} [SZ α] : SZ (Option α) := ⟨szOption⟩
instance : SZ Nat := ⟨fun _ => 0⟩
instance : SZ Bool := ⟨fun _ => 0⟩
instance : SZ UInt8 := ⟨fun _ => 0⟩
instance {w : Nat} : SZ (BitVec w) := ⟨fun _ => 0⟩

@[simp, sz_simp] theorem sz_nat (x : Nat) : sz x = 0 := rfl
@[simp, sz_simp] theorem sz_bool (x : Bool) : sz x = 0 := rfl
@[simp, sz_simp] theorem sz_uint8 (x : UInt8) : sz x = 0 := rfl
@[simp, sz_simp] theorem sz_bitvec {w : Nat} (x : BitVec w) : sz x = 0 := rfl
@[simp, sz_simp] theorem sz_opt_nat (x : Option Nat) : sz x = 0 := by cases x <;> rfl
@[simp, sz_simp] theorem sz_opt_bool (x : Option Bool) : sz x = 0 := by cases x <;> rfl
@[simp, sz_simp] theorem sz_opt_uint8 (x : Option UInt8) : sz x = 0 := by cases x <;> rfl
@[simp, sz_simp] theorem sz_opt_bitvec {w : Nat} (x : Option (BitVec w)) : sz x = 0 := by cases x <;> rfl
@[simp, sz_simp] theorem sz_nil {α : Type} [SZ α] : sz ([] : List α) = 0 := rfl
@[simp, sz_simp] theorem sz_cons {α : Type} [SZ α] (a : α) (l : List α) : sz (a :: l) = sz a + sz l + 1 := rfl
@[simp, sz_simp] theorem sz_none {α : Type} [SZ α] : sz (none : Option α) = 0 := rfl
@[simp, sz_simp] theorem sz_some {α : Type} [SZ α] (a : α) : sz (some a) = sz a := rfl

/-- A list is at most as long as its size. -/
theorem length_le_sz {α : Type} [SZ α] : ∀ l : List α, l.length ≤ sz l
  | [] => Nat.le_refl _
  | a :: l => by simp only [List.length_cons, sz_cons]; have := length_le_sz l; omega

@[simp, sz_simp] theorem sz_append {α : Type} [SZ α] : ∀ xs ys : List α, sz (xs ++ ys) = sz xs + sz ys
  | [], ys => by simp
  | a :: xs, ys => by
    have := sz_append xs ys
    simp only [List.cons_append, sz_cons]
    omega

theorem sz_lt_of_mem {α : Type} [SZ α] {a : α} : ∀ {l : List α}, a ∈ l → sz a < sz l
  | _ :: l, .head _ => by simp only [sz_cons]; omega
  | b :: l, .tail _ h => by have := sz_lt_of_mem h; simp only [sz_cons]; omega

/-- A sum over a list of at most its elements' sizes is at most its size. -/
theorem sum_le_sz {α : Type} [SZ α] (f : α → Nat) (hf : ∀ a, f a ≤ sz a) :
    ∀ l : List α, (l.map f).sum ≤ sz l
  | [] => Nat.le_refl _
  | a :: l => by
    have := sum_le_sz f hf l
    have := hf a
    simp only [List.map_cons, List.sum_cons, sz_cons]
    omega
'''

TS_HEADER = '''import Lanius.Mini.Frontend.Types
import Lanius.Mini.Compiler.P.SrcType_same
import Lanius.Faithful.SelfPre.SZAttr

/-! Generated by formal/tools/hb_gen.py --slots: the largest slot count `ts` of a type
anywhere in a value of the front end's and the compiler's types (F14). Do not edit.

A `SrcType` counts `tySlots`: the largest `SrcType.size` (the compiler's slot
count) of the type and of every type inside it, so of a slice's element, an
array's element and a struct's or an enum's fields too. A list, an `Option`, a
structure or a constructor counts its largest part; types with no `SrcType` in
them count nothing. -/

set_option linter.unusedVariables false

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

mutual
/-- The largest slot count of a type and of the types inside it. -/
def tySlots : SrcType → Nat
  | .i32 => SrcType.size .i32
  | .bool => SrcType.size .bool
  | .uint k => SrcType.size (.uint k)
  | .struct id fields => max (SrcType.size (.struct id fields)) (tySlotsList fields)
  | .enum id variants => max (SrcType.size (.enum id variants)) (tySlotsVariants variants)
  | .ptr => SrcType.size .ptr
  | .slice element => max (SrcType.size (.slice element)) (tySlots element)
  | .array element length => max (SrcType.size (.array element length)) (tySlots element)
  | .unit => SrcType.size .unit
  | .isize => SrcType.size .isize
  | .char => SrcType.size .char
  | .float ft => SrcType.size (.float ft)
  | .sint k => SrcType.size (.sint k)
  | .view length => SrcType.size (.view length)
  | .str => SrcType.size .str
def tySlotsList : List SrcType → Nat
  | [] => 0
  | t :: rest => max (tySlots t) (tySlotsList rest)
def tySlotsVariants : List (List SrcType) → Nat
  | [] => 0
  | v :: rest => max (tySlotsList v) (tySlotsVariants rest)
end

/-- A type's own slot count is at most its `tySlots`. -/
theorem size_le_tySlots : ∀ t : SrcType, SrcType.size t ≤ tySlots t
  | .i32 => Nat.le_refl _
  | .bool => Nat.le_refl _
  | .uint k => Nat.le_refl _
  | .struct id fields => Nat.le_max_left _ _
  | .enum id variants => Nat.le_max_left _ _
  | .ptr => Nat.le_refl _
  | .slice element => Nat.le_max_left _ _
  | .array element length => Nat.le_max_left _ _
  | .unit => Nat.le_refl _
  | .isize => Nat.le_refl _
  | .char => Nat.le_refl _
  | .float ft => Nat.le_refl _
  | .sint k => Nat.le_refl _
  | .view length => Nat.le_refl _
  | .str => Nat.le_refl _

/-- The largest slot count of a type anywhere in a value. -/
class TS (α : Type) where
  ts : α → Nat

export TS (ts)

def tsList {α : Type} [TS α] : List α → Nat
  | [] => 0
  | a :: l => max (ts a) (tsList l)

instance {α : Type} [TS α] : TS (List α) := ⟨tsList⟩

def tsOption {α : Type} [TS α] : Option α → Nat
  | none => 0
  | some a => ts a

instance {α : Type} [TS α] : TS (Option α) := ⟨tsOption⟩
instance : TS Nat := ⟨fun _ => 0⟩
instance : TS Bool := ⟨fun _ => 0⟩
instance : TS UInt8 := ⟨fun _ => 0⟩
instance {w : Nat} : TS (BitVec w) := ⟨fun _ => 0⟩

@[simp, ts_simp] theorem ts_nat (x : Nat) : ts x = 0 := rfl
@[simp, ts_simp] theorem ts_bool (x : Bool) : ts x = 0 := rfl
@[simp, ts_simp] theorem ts_uint8 (x : UInt8) : ts x = 0 := rfl
@[simp, ts_simp] theorem ts_bitvec {w : Nat} (x : BitVec w) : ts x = 0 := rfl
@[simp, ts_simp] theorem ts_opt_nat (x : Option Nat) : ts x = 0 := by cases x <;> rfl
@[simp, ts_simp] theorem ts_opt_bool (x : Option Bool) : ts x = 0 := by cases x <;> rfl
@[simp, ts_simp] theorem ts_opt_uint8 (x : Option UInt8) : ts x = 0 := by cases x <;> rfl
@[simp, ts_simp] theorem ts_opt_bitvec {w : Nat} (x : Option (BitVec w)) : ts x = 0 := by cases x <;> rfl
@[simp, ts_simp] theorem ts_nil {α : Type} [TS α] : ts ([] : List α) = 0 := rfl
@[simp, ts_simp] theorem ts_cons {α : Type} [TS α] (a : α) (l : List α) : ts (a :: l) = max (ts a) (ts l) := rfl
@[simp, ts_simp] theorem ts_none {α : Type} [TS α] : ts (none : Option α) = 0 := rfl
@[simp, ts_simp] theorem ts_some {α : Type} [TS α] (a : α) : ts (some a) = ts a := rfl

theorem ts_le_of_mem {α : Type} [TS α] {a : α} : ∀ {l : List α}, a ∈ l → ts a ≤ ts l
  | _ :: l, .head _ => by simp only [ts_cons]; omega
  | b :: l, .tail _ h => by have := ts_le_of_mem h; simp only [ts_cons]; omega
'''

FOOTER = '''end Lanius.Faithful.SelfPre
'''


def main():
    args = sys.argv[1:]
    mode = {'--sum': 'sz', '--slots': 'ts'}.get(args[0], 'hb')
    if mode != 'hb':
        args = args[1:]
    out, paths = args[0], args[1:]
    decls = parse(paths)
    TYPES.update(n for _, n, _ in decls)
    g = Gen(decls, mode)
    open(out, 'w').write(g.emit())


if __name__ == '__main__':
    main()
