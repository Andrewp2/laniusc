#!/usr/bin/env python3
"""Generate the height and precondition lemmas of the self program (F14).

From the budget certificates' models and statements in `Faithful/GenB/`:

* `post_K`: a costly function's result is at most as high (`hb`) as its
  arguments plus its cost, `Cost_K n xs < 2 ^ 64 → hb (f xs) ≤ max (hb x..) +
  Cost_K n xs`, by `post_auto` (`SelfPre/Tactic.lean`); the list prims'
  (`cons_of`, `single_of`, `concat_of`) by their own proofs. Each is also
  `HBPost.<f>.p<i>`, found by the Lean function `f`.
* `upost_f`: a function that allocates nothing gives a result at most as high
  as its arguments, by induction on the Lean function.
* `pre_K`: `Pre_K n xs b` from `hb x + b ≤ K` for the arguments (and a
  walker's index plus its list's height, `OVERRIDES`), by `pre_auto`.

Usage: pre_certs.py [--ns NAMESPACE] [--base MODULE] GENB OUTDIR ROOT...

The modules are named after OUTDIR (under formal/), e.g. `Lanius.Faithful.SelfPre.GenP`
for build_files. `--ns` puts the lemmas in a namespace of their own below
`Lanius.Faithful.SelfPre` (the tactic looks there first), so the compile side's
(GenPC, `--ns Lanius.Faithful.SelfPre.Compile`) can share names with build_files'.
`--base` replaces the value lemmas' module `SelfPre.Values` in every module's
imports (GenPC: `Lanius.Faithful.SelfPre.CompileValues`, which imports it).
"""
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hb_gen  # noqa: E402

K = '4611686018427387904'
BIG = '18446744073709551616'

# Extra hypotheses of a precondition lemma, over its parameters p0.. and the budget b.
OVERRIDES = {
    'decimal_digit': ['p2 ≤ 2147483647'],
    'inst_index': ['p2 + hb p0 + b ≤ K'],
    'inst_index_at': ['p3 + hb (p0 :: p1) + b ≤ K'],
    'find_type': ['p3 + hb p0 + b ≤ K'],
    'find_type_at': ['p4 + hb (p0 :: p1) + b ≤ K'],
    'position': ['p2 + hb p0 + b ≤ K'],
    'position_at': ['p3 + hb (p0 :: p1) + b ≤ K'],
    'variants_named': ['p3 + hb p0 + b ≤ K'],
    'variants_named_at': ['p4 + hb (p0 :: p1) + b ≤ K'],
    'find_method': ['p3 + hb p2 + b ≤ K'],
    'find_method_at': ['p4 + hb (p2 :: p3) + b ≤ K'],
    'find_fn': ['p3 + hb p0 + b ≤ K'],
    'find_fn_at': ['p4 + hb (p0 :: p1) + b ≤ K'],
    'first_nested': ['p2 + hb p1 + b ≤ K'],
    'row_fits': ['p3 + hb p2 + b ≤ K'],
    'cols_quiet': ['p2 + hb p1 + b ≤ K'],
    'wild_binders': ['p1 + hb p2 + b ≤ K'],
    'wild_binder': ['p1 + b ≤ K'],
    'let_arms_of': ['p6 + hb p7 + b ≤ K'],
    'match_arms_of': ['p4 + hb p5 + b ≤ K'],
    'mono_loop': ['p5 + b ≤ K'],
    'mono_next': ['p5 + b ≤ K'],
    'fl_int_part': ['p2 + hb p0 + b ≤ K'],
    'fl_int_at': ['p3 + hb (p0 :: p1) + b ≤ K'],
    'fl_frac_part': ['p2 + hb p0 + b ≤ K', 'p3 + hb p0 + b ≤ K'],
    'fl_frac_at': ['p3 + hb (p0 :: p1) + b ≤ K', 'p4 + hb (p0 :: p1) + b ≤ K'],
    'root_insts': ['p1 + hb p0 + b ≤ K'],
    'root_at': ['p2 + hb (p0 :: p1) + b ≤ K'],
    'seed_insts': ['p1 + hb p0 + b ≤ K'],
    'seed_at': ['p2 + hb (p0 :: p1) + b ≤ K'],
    # the literal's base (litBase): the digits' accumulator then cannot wrap
    'based_digits': ['p0 = 2 ∨ p0 = 8 ∨ p0 = 16'],
    'based_digit': ['p0 = 2 ∨ p0 = 8 ∨ p0 = 16'],
    'lit_prefixed': ['(∀ v, p0 = some v → v = 2 ∨ v = 8 ∨ v = 16)'],
    # floats (SelfPre/Values): a digit's value, the fraction's digit count k,
    # the exponent's value (flExpDigits stops past 99999), a power's exponent,
    # a bit list's value, a high bit's position
    'fl_nat_half': ['p0 ≤ 255'],
    'fl_of_nat': ['p0 ≤ 255'],
    'fl_push': ['p1 ≤ 57'],
    'fl_finish': ['p2 + b ≤ K', 'p4 ≤ 99999'],
    'fl_exp_digits': ['p3 + b ≤ K'],
    'fl_exp_digit_at': ['p4 + b ≤ K', 'p6 ≤ 99999'],
    'fl_exp_first': ['p3 + b ≤ K'],
    'fl_exp_first_at': ['p4 + b ≤ K'],
    'fl_exp_sign': ['p3 + b ≤ K'],
    'fl_exp_sign_at': ['p4 + b ≤ K'],
    'fl_exp_part': ['p3 + b ≤ K'],
    'fl_exp_at': ['p4 + b ≤ K'],
    'fl_pow2': ['p0 ≤ 63'],
    # the formats flDecimal is called with: f32 and f64
    'fl_decimal': ['(p0 = 8 ∧ p1 = 23) ∨ (p0 = 11 ∧ p1 = 52)'],
    'fl_decimal_at': ['(p0 = 8 ∧ p1 = 23) ∨ (p0 = 11 ∧ p1 = 52)', 'p5 < hb p2'],
    # an alignment's shift: shift_of_u64(31, k, 0, 1) doubles p at most 31 times
    'shift_of_u64': ['p2 + p0 ≤ 63', 'p3 * 2 ^ p0 ≤ 2 ^ 63'],
    # mono_loop's index: it found a table entry before mono_next moves it on
    'mono_next': ['p5 < hb p3'],
    # a struct field's index (below the environment's height, vals_fieldIndex)
    'projection': ['p2 + b ≤ K'],
    'field_value': ['p3 + b ≤ K'],
    'fl_round': ['(p0 = 8 ∧ p1 = 23) ∨ (p0 = 11 ∧ p1 = 52)', '0 < Lanius.Mini.flToNat p3'],
    'fl_to_nat': ['Lanius.Mini.flToNat p0 < 18446744073709551616'],
    'fl_log2_up': ['(∀ i, p1 = some i → i + b ≤ K)'],
    'char_tail': ['p4 ≤ 191', '(p1 = 0 ∧ p2 < 16777216) ∨ (p1 = 1 ∧ p2 < 262144) ∨ (p1 = 2 ∧ p2 < 4096)'],
    'char_tail_at': ['p5 ≤ 191', '(p2 = 0 ∧ p3 < 16777216) ∨ (p2 = 1 ∧ p3 < 262144) ∨ (p2 = 2 ∧ p3 < 4096)'],
}


def split_top(s, sep):
    """Split s at top-level occurrences of sep (outside brackets)."""
    out, d, cur, i = [], 0, '', 0
    while i < len(s):
        ch = s[i]
        if ch in '([{⟨':
            d += 1
        elif ch in ')]}⟩':
            d -= 1
        if d == 0 and s.startswith(sep, i):
            out.append(cur)
            cur = ''
            i += len(sep)
            continue
        cur += ch
        i += 1
    out.append(cur)
    return [x.strip() for x in out]


class Models:
    def __init__(self, genb):
        self.sig = {}       # 'Cost_k' / 'Pre_k' -> [param types] (after the fuel; Pre without b)
        self.body = {}      # name -> body text (the n + 1 case)
        self.group = {}     # name -> tuple of names in its mutual block
        self.recursive = set()
        for f in sorted(os.listdir(genb)):
            if not re.match(r'SelfBModel\d+\.lean$', f):
                continue
            self.read(os.path.join(genb, f))
        self.stmt = {}      # key -> (params [(x, ty)], costly, rep, term)
        for f in sorted(os.listdir(genb)):
            if re.match(r'SelfBStmt\d+\.lean$', f):
                self.read_stmt(os.path.join(genb, f))

    def read(self, path):
        lines = open(path).read().split('\n')
        block = None
        cur = None
        for line in lines:
            if line == 'mutual':
                block = []
                continue
            if line == 'end' and block is not None:
                for n in block:
                    self.group[n] = tuple(block)
                    self.recursive.add(n)
                block = None
                cur = None
                continue
            m = re.match(r'def ((?:Cost|Pre)_\w+) : (.*)$', line)
            if m:
                cur = m.group(1)
                tys = split_top(m.group(2), '→')
                tys = tys[1:-1]
                if cur.startswith('Pre_'):
                    tys = tys[:-1]
                self.sig[cur] = tys
                self.body[cur] = ''
                if block is not None:
                    block.append(cur)
                else:
                    self.group[cur] = (cur,)
                continue
            if line.startswith('termination_by'):
                if cur and block is None:
                    self.recursive.add(cur)
                continue
            if cur and line.startswith('  | n + 1'):
                self.body[cur] = line.split('=>', 1)[1]
            elif not line.strip():
                cur = None if block is None else cur

    def read_stmt(self, path):
        txt = open(path).read()
        for blk in txt.split('abbrev BStmt_')[1:]:
            key = blk.split()[0]
            lines = blk.split('\n')
            ps = re.findall(r'\{(x\d+) : ([^{}]+?)\}', lines[1])
            last = lines[3] if len(lines) > 3 else ''
            m = re.search(r'∧ (Cost_\w+ n[^=]*|0) = k ∧ (.*)$', last)
            if not m:
                continue
            costly = m.group(1) != '0'
            rest = m.group(2).strip()
            if rest.startswith('('):
                d = 0
                for i, ch in enumerate(rest):
                    d += ch == '('
                    d -= ch == ')'
                    if d == 0:
                        break
                rep, term = rest[:i + 1], rest[i + 1:].strip()
            else:
                rep, term = rest.split(' ', 1)
            assert term.endswith(' w'), (key, term)
            self.stmt[key] = ([(x, t.strip()) for x, t in ps], costly, rep, term[:-2].strip())

    def deps(self, name):
        return set(re.findall(r'\b((?:Cost|Pre)_\w+)', self.body.get(name, ''))) - {name, 'Pre_plus', 'Pre_times'}


def rep_ty(rep):
    """A representation relation's Lean type."""
    rep = rep.strip()
    while rep.startswith('(') and rep.endswith(')'):
        rep = rep[1:-1].strip()
    m = re.match(r'Rep(List|Option) \d+ (.*)$', rep)
    if m:
        inner = rep_ty(m.group(2))
        return f'{m.group(1)} ({inner})'
    base = {'RepNat': 'Nat', 'RepBool': 'Bool', 'RepU64': 'BitVec 64', 'RepU32': 'BitVec 32',
            'RepI32': 'BitVec 32', 'RepU8': 'UInt8'}
    if rep in base:
        return base[rep]
    assert rep.startswith('Rep'), rep
    return 'Lanius.Mini.' + rep[3:]


class Gen:
    def __init__(self, genb, roots):
        self.m = Models(genb)
        here = os.path.dirname(os.path.abspath(__file__))
        tys = hb_gen.parse([os.path.join(here, '..', 'Lanius', 'Mini', 'Compiler', 'Types.lean'),
                            os.path.join(here, '..', 'Lanius', 'Mini', 'Frontend', 'Types.lean')])
        g = hb_gen.Gen(tys)
        g.emit()
        self.flat_names = g.flat
        self.roots = roots

    def flat(self, ty):
        t = hb_gen.strip_parens(ty.replace('Lanius.Mini.', ''))
        h, inner = hb_gen.head(t)
        if h == 'List':
            return False
        if h == 'Option':
            return self.flat(inner)
        if h in ('Nat', 'Bool', 'UInt8', 'BitVec'):
            return True
        return self.flat_names.get(h, False)

    def reach(self):
        seen, st = set(), [f'Pre_{r}' for r in self.roots] + [f'Cost_{r}' for r in self.roots]
        while st:
            x = st.pop()
            if x in seen or x not in self.m.sig:
                continue
            seen.add(x)
            st += sorted(self.m.deps(x))
        return seen


LIST_PRIMS = ('cons_of_', 'single_of_', 'concat_of_')


def maxes(parts):
    return hb_gen.maxes(parts)


def proj(i, n):
    """The projection of the `i`th of `n` conjuncts."""
    if n == 1:
        return ''
    return '.2' * i + ('.1' if i < n - 1 else '')


def tuple_(xs):
    return xs[0] if len(xs) == 1 else '⟨' + ', '.join(xs) + '⟩'


# Heights that also grow by a number argument: a wildcard binder's token starts
# at the pattern's plus its index (the index is at most the boxes the binders
# before it took, at the call from the pattern).
POST_EXTRA = {
    'wild_binder': ['x1'],
    'wild_binders': ['x1'],
}

# Hand-written recursive cases (the body after `intro xs M hMs` in the group's
# `succ` case). wild_binders: its index grows by one per binder, absorbed by
# the binder's own cost (at least 1); the potential choice cannot see that.
# Hand proofs of precondition lemmas, in place of `pre_auto n, M` (after the
# model's `eq_def`): numbers' values, which heights do not bound, from the
# lemmas of SelfPre/Values.lean.
PRE_HAND = {
    'wide_isize': '''  cases x0 <;> by_cases hz : x1 = 0 <;> simp_all [Pre_plus] <;> omega
''',
    'wide_sint': '''  split
  · trivial
  · cases x1 <;> by_cases hz : x2 = 0 <;> simp_all [Pre_plus] <;> omega
''',
    'based_digit': '''  split
  · exact pre_based_digits x0 x2 x3 b M h0 h1 h2
  · split
    · trivial
    · rename_i hlim
      split
      · rename_i d hd
        have hdl := baseDigit_lt hd
        refine ⟨?_, ?_, pre_based_digits x0 x2 _ b M h0 h1 h2⟩ <;> simp only [Pre_times, Pre_plus] <;>
          rcases h2 with rfl | rfl | rfl <;> simp [Lanius.Mini.basedLimit] at hlim <;> omega
      · trivial
''',
    'lit_prefixed': '''  rcases x0 with _ | v
  · exact pre_wide_decimal n x2 0 b M h1 h2
  · exact pre_based_digits n v x1 0 b M h0 h2 (h3 v rfl)
''',
    'lit_value_at': '''  split
  · rcases x1 with _ | ⟨c, rest⟩
    · trivial
    · exact pre_lit_prefixed n _ rest x2 b M (by simp only [hb_cons] at h0; omega) h1 h2
        (fun v hv => litBase_cases hv)
  · exact pre_wide_decimal n x2 0 b M h1 h2
''',
    'fl_round': '''  have hq := flRound_q_lt x0 x1 x2 x3 h4
    (by rcases h3 with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> simp only [flPow2_eq] <;> decide)
  rcases h3 with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [flPow2_eq, Nat.reducePow, Nat.reduceSub, Nat.reduceAdd] at hq ⊢ <;> pre_auto n, M
''',
    'fl_decimal_at': '''  have hpos := flTimes10_one_pos x4
  have hone : Lanius.Mini.flToNat [true] = 1 := rfl
  rcases h2 with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [flPow2_eq, Nat.reducePow, Nat.reduceSub, Nat.reduceAdd] <;> pre_auto n, M
''',
    'fl_nat_half': '''  split
  · trivial
  · refine ⟨pre_fl_nat_half (x0 - 2) b M h0 (by omega), ?_⟩
    have := flNatHalf_le (x0 - 2)
    simp only [Pre_plus, Nat.reducePow]
    omega
''',
    'fl_of_nat': '''  split
  · trivial
  · exact ⟨pre_fl_nat_half n x0 b M h0 h1,
      pre_fl_of_nat (Lanius.Mini.flNatHalf x0) (x1 - 1) b M h0 (Nat.le_trans (flNatHalf_le x0) h1)⟩
''',
    'fl_pow2': '''  split
  · trivial
  · refine ⟨pre_fl_pow2 (x0 - 1) b M h0 (by omega), ?_⟩
    have h2 : 2 ^ (x0 - 1) ≤ 2 ^ 62 := Nat.pow_le_pow_right (by decide) (by omega)
    simp only [Pre_times, flPow2_eq, Nat.reducePow] at h2 ⊢
    omega
''',
    'fl_to_nat': '''  rcases x0 with _ | ⟨c, rest⟩
  · trivial
  · rw [Lanius.Mini.flToNat] at h2
    refine ⟨pre_fl_to_nat rest b M (by simp only [hb_cons] at h0; omega) h1 (by omega), ?_, ?_⟩ <;>
      simp only [Pre_times, Pre_plus, Nat.reducePow] <;> omega
''',
    'shift_of_u64': '''  split
  · trivial
  split
  · trivial
  rename_i hz _
  have hx : 1 ≤ x0 := by simp only [decide_eq_true_eq] at hz; omega
  have hm : x3 * 2 * 2 ^ (x0 - 1) = x3 * 2 ^ x0 := by
    rw [Nat.mul_assoc, ← Nat.pow_succ']
    congr 2
    omega
  have hp : x3 * 2 ≤ x3 * 2 ^ x0 := by
    have := Nat.pow_le_pow_right (show 0 < 2 by omega) hx
    exact Nat.mul_le_mul_left _ (by simpa using this)
  refine ⟨?_, ?_, pre_shift_of_u64 (x0 - 1) x1 (x2 + 1) (x3 * 2) b M h0 (by omega) (by omega)⟩ <;>
    simp only [Pre_plus, Pre_times, Nat.reducePow] <;> omega
''',
    'fl_log2_up': '''  rcases x1 with _ | i
  · trivial
  · have := h1 i rfl
    simp only [Pre_plus, Nat.reducePow]
    omega
''',
    'fl_log2': '''  rcases x0 with _ | ⟨c, rest⟩
  · trivial
  · have hr : hb rest ≤ M := by simp only [hb_cons] at h0; omega
    refine ⟨pre_fl_log2 rest b M hr h1, pre_fl_log2_up n c _ b M h1 (fun i hi => ?_)⟩
    have := flLog2_lt rest i hi
    have := length_le_hb rest
    omega
''',
}

HAND_CASE = {
    'wild_binders': '''      intro h
      cases x2 with
      | nil => rw [Lanius.Mini.wildBinders.eq_def]; simp only [hb_nil]; omega
      | cons t rest =>
        rw [Cost_wild_binders.eq_def] at h ⊢; dsimp only at h ⊢
        rw [Lanius.Mini.wildBinders.eq_def]; dsimp only
        simp only [hb_cons] at hM1 ⊢
        have h1 := post_wild_binder n x0 x1 M hM0 (by omega)
        have h2 := post_wild_binders x0 (x1 + 1) rest M hM0 (by omega) (by omega)
        have h3 : 1 ≤ Cost_cons_of_mini_selfhost_CTree n (Lanius.Mini.wildBinder x0 x1)
            (Lanius.Mini.wildBinders x0 (x1 + 1) rest) := by
          rcases n with _ | n <;> simp only [Cost_cons_of_mini_selfhost_CTree] <;> omega
        have h4 : 1 ≤ Cost_wild_binder n x0 x1 := by
          rcases n with _ | n <;> rw [Cost_wild_binder.eq_def] <;> dsimp only <;> omega
        omega
''',
}


# ---------------------------------------------------------------------------
# The compile side (GenPC: roots compile_source, binary_words; leafB).
# Hand proofs of height lemmas, in place of `post_auto n, M` (after the cost
# model's and the Lean function's `eq_def`, the cost premise not introduced).

def bytes_hand(le=(), callees=()):
    """A byte list's height is its length (SelfPre/CompileValues): the list
    primitives cost at least 1 whatever their arguments, an le32/le64 at least
    its 4/8 bytes, and each callee's bytes (lemma, arguments) at most its cost.
    `post_auto` takes about a minute on one of these (an `omega` call over every
    cost atom per cons cell), and plain `omega` too (it unfolds the concatenations'
    costs comparing its atoms): `omega_atoms` abstracts them first."""
    lens = 'pc_hb_u8, List.length_append, List.length_cons, List.length_nil, pc_len_le64, pc_len_le32'
    out = ('  intro h\n'
           f'  simp only [pc_cons_u8, pc_single_u8, pc_le64, pc_le32, {lens}] at h ⊢\n'
           '  have := pc_cons_u8_pos n\n'
           '  have := pc_single_u8_pos n\n' +
           ''.join(f'  have := pc_le{w}_ge n (by omega_atoms)\n' for w in le))
    for lem, args in callees:
        out += (f'  have := {lem} n {args} 0 (by omega_atoms)\n'
                f'  simp only [{lens}] at this\n')
    return out + '  omega_atoms\n'


POST_HAND = {
    'bump_bytes': bytes_hand([64]),
    'frame_memory_bytes': bytes_hand([64]),
    'sys_bytes': bytes_hand([32], [('post_syscall_rsi_bytes', 'x0')]),
    # Inline.link's `if` (post_auto split it again and again, never rewriting it)
    'link': '''  intro h
  split
  · have hl := post_layout n 0 x0 M hM0 (by omega)
    have ho := post_link_onto n (Lanius.Mini.layout 0 x0) 0 x0 x1 (M + Cost_layout n 0 x0) hl (by omega) (by omega) (by omega)
    simp only [hb_some, hb_Binary_mk, Nat.max_le]
    refine ⟨?_, ?_, ?_, ?_⟩ <;> omega
  · simp only [hb_none]
    omega
''',
}

# Hand-written recursive cases (as HAND_CASE): SrcStmt.declare's ifEval and matchArm, whose
# nested `match`es post_auto splits apart from the cost model's (the leaf had
# the cost at `none` and the function at `some`); the other cases by post_auto.
HAND_CASE.update({
    'SrcStmt_declare': '''      rw [Cost_SrcStmt_declare.eq_def]; dsimp only
      rw [Lanius.Mini.SrcStmt.declare.eq_def x0 x1]
      cases x0
      case ifEval c t e =>
        dsimp only
        intro h
        simp only [hb_SrcStmt_ifEval, Nat.max_le] at hM0
        obtain ⟨hc, ht, he⟩ := hM0
        have h1 := post_SrcEff_types n c M hc (by omega)
        have h2 := post_declare_types n (Lanius.Mini.SrcEff.types c) x1 (M + Cost_SrcEff_types n c) h1
          (by omega) (by omega)
        have h3 := post_declare_in (Lanius.Mini.declareTypes (Lanius.Mini.SrcEff.types c) x1) t
          (M + Cost_SrcEff_types n c + Cost_declare_types n (Lanius.Mini.SrcEff.types c) x1) h2 (by omega) (by omega)
        have h4 := post_declare_in
          (Lanius.Mini.Inline.declareIn (Lanius.Mini.declareTypes (Lanius.Mini.SrcEff.types c) x1) t) e
          (M + Cost_SrcEff_types n c + Cost_declare_types n (Lanius.Mini.SrcEff.types c) x1 +
            Cost_declare_in n (Lanius.Mini.declareTypes (Lanius.Mini.SrcEff.types c) x1) t) h3 (by omega) (by omega)
        exact Nat.le_trans h4 (by omega)
      case matchArm s en v bs bd ty body rest =>
        dsimp only
        intro h
        simp only [hb_SrcStmt_matchArm, Nat.max_le] at hM0
        obtain ⟨hty, hbody, hrest⟩ := hM0
        have h1 := post_SrcType_declare n ty x1 M hty hM1 (by omega)
        have h2 := post_declare_in (Lanius.Mini.SrcType.declare ty x1) body (M + Cost_SrcType_declare n ty x1) h1
          (by omega) (by omega)
        have h3 := post_declare_in (Lanius.Mini.Inline.declareIn (Lanius.Mini.SrcType.declare ty x1) body) rest
          (M + Cost_SrcType_declare n ty x1 + Cost_declare_in n (Lanius.Mini.SrcType.declare ty x1) body) h2
          (by omega) (by omega)
        exact Nat.le_trans h3 (by omega)
      all_goals (try dsimp only) <;> post_auto n, M
''',
})

# --- end of the compile side -----------------------------------------------


class Emit:
    """The height and precondition lemmas, at a potential `M`:
    `post_F : ∀ n xs M, hb x ≤ M → .. → Cost_F n xs < 2 ^ 64 → hb (F xs) ≤ M + Cost_F n xs`,
    `upost_F : ∀ xs M, hb x ≤ M → .. → hb (F xs) ≤ M` for a function the cost model does not see,
    `pre_F : ∀ n xs b M, hb x ≤ M → .. → M + b ≤ K → walker bounds → Pre_F n xs b`."""

    def __init__(self, g):
        self.g = g
        self.m = g.m

    def order(self):
        return list(self.m.sig.keys())

    def head(self, k):
        term = self.m.stmt[k][3]
        m = re.match(r'\(?(Lanius\.Mini\.[\w.]+)', term)
        return m.group(1) if m else None

    def used(self, k, ks, model, lemma):
        """The group's induction hypotheses `k`'s step uses (the members its model
        calls), the others dropped (`-`): fewer hypotheses for the tactic to scan."""
        body = self.m.body.get(f'{model}_{k}', '') + HAND_CASE.get(k, '') + PRE_HAND.get(k, '')
        calls = set(re.findall(rf'\b{model}_(\w+)', body)) | set(re.findall(rf'\b{lemma}_(\w+)', body))
        return [f'{lemma}_{m}' if m in calls else '-' for m in ks]

    def live(self, ps):
        return [x for x, t in ps if not self.g.flat(t)]

    # heights -----------------------------------------------------------

    def post_parts(self, k, fuel='n'):
        """(binders, xs, premise names, statement after the binders)."""
        ps, costly, rep, term = self.m.stmt[k]
        xs = ' '.join(x for x, _ in ps)
        binders = ' '.join(f'({x} : {t})' for x, t in ps)
        live = self.live(ps)
        cost = f'Cost_{k} {fuel}{(" " + xs) if xs else ""}'
        hyps = [f'hb {x} ≤ M' for x in live]
        extra = ''.join(f'{x} + ' for x in POST_EXTRA.get(k, []))
        st = '∀ M : Nat, ' + ' → '.join(hyps + [f'{cost} < {BIG}', f'hb {paren(term)} ≤ M + {extra}{cost}'])
        names = ' '.join(f'hM{i}' for i in range(len(hyps)))
        return binders, xs, names, st

    def prim_proof(self, k):
        binders, xs, names, st = self.post_parts(k)
        if k.startswith('concat_of_'):
            return (f'theorem post_{k} : ∀ (n : Nat) {binders}, {st}\n'
                    f'  | 0, x0, x1, M, hM0, hM1, h => absurd h (Nat.lt_irrefl _)\n'
                    f'  | n + 1, [], x1, M, hM0, hM1, h => by simp only [List.nil_append]; omega\n'
                    f'  | n + 1, a :: x0, x1, M, hM0, hM1, h => by\n'
                    f'    simp only [Cost_{k}] at h ⊢\n'
                    f'    simp only [hb_cons, hb_simp] at hM0\n'
                    f'    have := post_{k} n x0 x1 M (by omega) hM1 (by omega)\n'
                    f'    simp only [List.cons_append, hb_cons, hb_simp]\n'
                    f'    omega\n')
        return (f'theorem post_{k} : ∀ (n : Nat) {binders}, {st} := by\n'
                f'  intro n {xs} M {names} h\n'
                f'  rcases n with _ | n\n'
                f'  · exact absurd h (Nat.lt_irrefl _)\n'
                f'  · simp only [Cost_{k}, hb_cons, hb_nil, hb_simp]; omega\n')

    def post_group(self, ks, recursive):
        out = []
        prim = [k for k in ks if k.startswith(LIST_PRIMS) and self.head(k) is None]
        for k in prim:
            out.append(self.prim_proof(k))
        ks = [k for k in ks if k not in prim]
        if not ks:
            return out
        if not recursive and not self.m.stmt[ks[0]][0] and self.literal(ks[0]):
            k = ks[0]
            binders, xs, names, st = self.post_parts(k)
            h = self.head(k)
            prims = 'Cost_cons_of_usize, Cost_single_of_usize'
            # `delta`, not the equation lemmas: making `Cost_{k}`'s took 16 s on a
            # 20-word literal; the height of the literal by the kernel
            dl = f'delta Cost_{k} {prims.replace(",", "")}'
            out.append(f'theorem post_{k} : ∀ (n : Nat), {st} := by\n'
                       f'  intro n M h\n'
                       f'  rcases n with _ | _ | n\n'
                       f'  · exact absurd h (Nat.lt_irrefl _)\n'
                       f'  · {dl} at h; dsimp only at h; omega\n'
                       f'  · {dl}; dsimp only\n'
                       f'    first\n'
                       f'    | exact Nat.le_trans (Nat.le_of_ble_eq_true (by decide)) (Nat.le_add_left _ M)\n'
                       f'    | (simp only [{h}, hb_cons, hb_nil, hb_simp]; omega)\n')
            return out
        if not recursive:
            k = ks[0]
            binders, xs, names, st = self.post_parts(k)
            h = self.head(k)
            out.append(f'theorem post_{k} : ∀ (n : Nat) {binders}, {st} := by\n'
                       f'  intro n {xs} M {names}\n'
                       f'  rcases n with _ | n\n'
                       f'  · intro h; exact absurd h (Nat.lt_irrefl _)\n'
                       f'  rw [Cost_{k}.eq_def]; dsimp only\n' +
                       (f'  rw [{h}.eq_def{(" " + xs) if xs else ""}]\n' if h else '') +
                       POST_HAND.get(k, '  post_auto n, M\n'))
            return out
        first = ks[0]
        conj = ' ∧\n    '.join(f'(∀ {p[0]}, {p[3]})' if p[0] else f'({p[3]})'
                               for p in map(self.post_parts, ks))
        zero = [f'fun {p[1]} M {p[2]} h => absurd h (Nat.lt_irrefl _)'.replace('  ', ' ')
                for k, p in zip(ks, map(self.post_parts, ks))]
        names = [f'post_{k}' for k in ks]
        # one step lemma per member (its own command: heartbeats, errors)
        for k in ks:
            binders, xs, nm, st = self.post_parts(k, '(n + 1)')
            h = self.head(k)
            out.append(f'theorem post_step_{k} (n : Nat) (ih :\n    {conj}) :\n    {"∀ " + binders + ", " if binders else ""}{st} := by\n'
                       f'  {"obtain " + tuple_(self.used(k, ks, "Cost", "post")) + " := ih" if len(ks) > 1 else "have " + names[0] + " := ih"}\n'
                       '  ' + ' '.join(['intro', xs, 'M', nm]).replace('  ', ' ').strip() + '\n' +
                       (HAND_CASE[k].replace('\n    ', '\n').lstrip(' ').join(['  ', '']) if k in HAND_CASE else
                        f'  rw [Cost_{k}.eq_def]; dsimp only\n' +
                        (f'  rw [{h}.eq_def{(" " + xs) if xs else ""}]\n' if h else '') +
                        f'  post_auto n, M\n'))
        steps = [f'post_step_{k} n ih' for k in ks]
        out.append(f'theorem post_group_{first} : ∀ n : Nat,\n    {conj} := by\n'
                   f'  intro n\n'
                   f'  induction n with\n'
                   f'  | zero => exact {tuple_(zero)}\n'
                   f'  | succ n ih => exact {tuple_(steps)}\n')
        for i, k in enumerate(ks):
            binders, xs, nm, st = self.post_parts(k)
            out.append(f'theorem post_{k} : ∀ (n : Nat) {binders}, {st} :=\n'
                       f'  fun n => (post_group_{first} n){proj(i, len(ks))}\n')
        return out

    def literal(self, k):
        """The cost model only builds a literal list of numbers."""
        body = self.m.body.get(f'Cost_{k}', '')
        calls = set(re.findall(r'Cost_\w+', body))
        return bool(calls) and calls <= {'Cost_cons_of_usize', 'Cost_single_of_usize'}

    # the functions the cost model does not see -------------------------

    def uncostly(self):
        out = []
        for k, (ps, costly, rep, term) in sorted(self.m.stmt.items()):
            if costly or self.g.flat(rep_ty(rep)) or self.head(k) is None:
                continue
            out.append(k)
        return out

    def upost(self, k, i):
        ps, costly, rep, term = self.m.stmt[k]
        xs = ' '.join(x for x, _ in ps)
        binders = ' '.join(f'({x} : {t})' for x, t in ps)
        live = self.live(ps)
        hyps = [f'hb {x} ≤ M' for x in live]
        st = '∀ M : Nat, ' + ' → '.join(hyps + [f'hb {paren(term)} ≤ M'])
        names = ' '.join(f'hM{j}' for j in range(len(hyps)))
        h = self.head(k)
        bs = f'∀ {binders}, ' if binders else ''
        return (f'theorem upost_{k} : {bs}{st} := by\n'
                f'  intro {xs} M {names}\n' +
                (f'  first | fun_induction {h} {xs} | fun_cases {h} {xs} | unfold {h}\n' if xs else f'  unfold {h}\n') +
                f'  all_goals upost_auto M\n'
                f'theorem HBPost.{h}.p{i} : {bs}{st} := upost_{k}\n')

    # preconditions -----------------------------------------------------

    def pre_parts(self, k, fuel='n'):
        tys = self.m.sig[f'Pre_{k}']
        xs = [f'x{i}' for i in range(len(tys))]
        binders = ' '.join(f'({x} : {t})' for x, t in zip(xs, tys))
        hyps = [f'hb {x} ≤ M' for x, t in zip(xs, tys) if not self.g.flat(t)]
        hyps.append(f'M + b ≤ {K}')
        for h in OVERRIDES.get(k, []):
            hyps.append(re.sub(r'\bp(\d+)\b', lambda mm: xs[int(mm.group(1))], h).replace('≤ K', f'≤ {K}'))
        concl = f'Pre_{k} {fuel} {" ".join(xs)} b'.replace('  ', ' ')
        st = '∀ M : Nat, ' + ' → '.join(hyps + [concl])
        names = ' '.join(f'h{i}' for i in range(len(hyps)))
        return binders, ' '.join(xs), names, st

    def pre_group(self, ks, recursive):
        if not recursive:
            k = ks[0]
            binders, xs, names, st = self.pre_parts(k)
            return [f'theorem pre_{k} : ∀ (n : Nat) {binders} (b : Nat), {st} := by\n'
                    f'  intro n {xs} b M {names}\n'
                    f'  rcases n with _ | n\n'
                    f'  · exact trivial\n'
                    f'  rw [Pre_{k}.eq_def]; dsimp only\n' +
                    PRE_HAND.get(k, '  pre_auto n, M\n')]
        first = ks[0]
        parts = list(map(self.pre_parts, ks))
        conj = ' ∧\n    '.join(f'(∀ {p[0]} (b : Nat), {p[3]})' for p in parts)
        zero = [f'fun {p[1]} b M {" ".join("_" for _ in p[2].split())} => trivial'
                for k, p in zip(ks, parts)]
        names = [f'pre_{k}' for k in ks]
        out = []
        for k in ks:
            binders, xs, nm, st = self.pre_parts(k, '(n + 1)')
            out.append(f'theorem pre_step_{k} (n : Nat) (ih :\n    {conj}) :\n    ∀ {binders} (b : Nat), {st} := by\n'
                       f'  {"obtain " + tuple_(self.used(k, ks, "Pre", "pre")) + " := ih" if len(ks) > 1 else "have " + names[0] + " := ih"}\n'
                       f'  intro {xs} b M {nm}\n'
                       f'  rw [Pre_{k}.eq_def]; dsimp only\n' +
                       PRE_HAND.get(k, '  pre_auto n, M\n'))
        steps = [f'pre_step_{k} n ih' for k in ks]
        out.append(f'theorem pre_group_{first} : ∀ n : Nat,\n    {conj} := by\n'
                   f'  intro n\n'
                   f'  induction n with\n'
                   f'  | zero => exact {tuple_(zero)}\n'
                   f'  | succ n ih => exact {tuple_(steps)}\n')
        for i, k in enumerate(ks):
            binders, xs, nm, st = self.pre_parts(k)
            out.append(f'theorem pre_{k} : ∀ (n : Nat) {binders} (b : Nat), {st} :=\n'
                       f'  fun n => (pre_group_{first} n){proj(i, len(ks))}\n')
        return out


def model_needs(g, names):
    """The lemmas the models `names` call: `post:k` for `Cost_k`, `pre:k` for `Pre_k`."""
    out = set()
    for nm in names:
        for kind, k in re.findall(r'\b(Cost|Pre)_(\w+)', g.m.body.get(nm, '')):
            out.add(('post:' if kind == 'Cost' else 'pre:') + k)
    return out


def paren(t):
    t = t.strip()
    if t.startswith('(') and t.endswith(')') and hb_gen.balanced(t[1:-1]):
        return t
    return f'({t})'


HEADER = """{imports}

/-! Generated by formal/tools/pre_certs.py: {what} (F14). Do not edit. -/

set_option maxHeartbeats 1000000
set_option maxRecDepth 100000
set_option linter.unusedVariables false
set_option linter.unusedSimpArgs false

namespace {ns}

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre.Tactic

"""


def lean_defs():
    """The Lean functions' bodies, by their names under `Lanius.Mini`."""
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = {}
    for root, _, files in os.walk(os.path.join(here, 'Lanius', 'Mini')):
        for f in files:
            if not f.endswith('.lean'):
                continue
            text = open(os.path.join(root, f)).read()
            ns = []
            cur, body = None, []
            for line in text.split('\n'):
                m = re.match(r'namespace (\S+)', line)
                if m:
                    ns.append(m.group(1))
                m2 = re.match(r'end (\S+)', line)
                if m2 and ns and ns[-1] == m2.group(1):
                    ns.pop()
                d = re.match(r'(?:@\[[^\]]*\]\s*)?(?:private |protected |noncomputable )*(?:partial )?def (\S+)', line)
                if d:
                    if cur:
                        out[cur] = '\n'.join(body)
                    cur = '.'.join(ns + [d.group(1)])
                    body = [line]
                elif cur:
                    body.append(line)
            if cur:
                out[cur] = '\n'.join(body)
    return out


def lean_order(ks, head):
    """`ks` with every function after the functions its Lean body calls."""
    defs = lean_defs()
    name = {k: head(k) for k in ks}
    short = {k: name[k][len('Lanius.Mini.'):] for k in ks}
    by_short = defaultdict(list)
    for k in ks:
        by_short[short[k]].append(k)
    deps = {}
    for k in ks:
        body = defs.get(name[k], '')
        ws = set(re.findall(r'[A-Za-z_][\w.]*', body))
        deps[k] = [k2 for s2, l in by_short.items() if s2 != short[k] and
                   (s2 in ws or s2.split('.')[-1] in ws) for k2 in l]
    out, seen = [], set()
    def visit(k, stack):
        if k in seen or k in stack:
            return
        stack.add(k)
        for d in deps[k]:
            visit(d, stack)
        stack.discard(k)
        seen.add(k)
        out.append(k)
    for k in ks:
        visit(k, set())
    return out


def called_uncostly(e, reached):
    """The functions the cost model does not see that the reached functions' Lean
    bodies call, transitively."""
    defs = lean_defs()
    by_short = defaultdict(list)
    for k in e.uncostly():
        by_short[e.head(k)[len('Lanius.Mini.'):]].append(k)
    words = lambda name: set(re.findall(r'[A-Za-z_][\w.]*', defs.get('Lanius.Mini.' + name, '')))
    todo = [e.head(k)[len('Lanius.Mini.'):] for k in reached if e.head(k)]
    seen, out = set(todo), []
    for s1 in sorted(seen):
        out.extend(by_short.get(s1, []))
    while todo:
        ws = words(todo.pop())
        for s2, ks in by_short.items():
            if s2 in seen:
                continue
            if s2 in ws or (s2.startswith('Inline.') and s2.split('.')[-1] in ws):
                seen.add(s2)
                todo.append(s2)
                out.extend(ks)
    return out


def main():
    args = sys.argv[1:]
    ns = 'Lanius.Faithful.SelfPre'
    values = 'Lanius.Faithful.SelfPre.Values'
    while args[:1] in (['--ns'], ['--base']):
        if args[0] == '--ns':
            ns = args[1]
        else:
            values = args[1]
        args = args[2:]
    genb, outdir = args[0], args[1]
    roots = args[2:]
    formal = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rel = os.path.relpath(os.path.abspath(outdir), formal)
    prefix = rel.replace(os.sep, '.') if rel.startswith('Lanius' + os.sep) else 'Lanius.Faithful.SelfPre.GenP'
    g = Gen(genb, roots)
    e = Emit(g)
    r = g.reach()
    order = e.order()
    seen_groups = set()
    posts, pres = [], []
    reached = []
    for name in order:
        if name not in r:
            continue
        grp = g.m.group[name]
        if grp in seen_groups:
            continue
        seen_groups.add(grp)
        rec = name in g.m.recursive
        if name.startswith('Cost_'):
            ks = [x[5:] for x in grp if x in r and x[5:] in g.m.stmt and not g.flat(rep_ty(g.m.stmt[x[5:]][2]))]
            if ks:
                posts.append((e.post_group(ks, rec), {f'post:{k}' for k in ks}, model_needs(g, ['Cost_' + k for k in ks])))
                reached.extend(ks)
        else:
            ks = [x[4:] for x in grp if x in r]
            pres.append((e.pre_group(ks, rec), {f'pre:{k}' for k in ks}, model_needs(g, ['Pre_' + k for k in ks])))
            # a precondition's facts need the heights its Lean function computes too
            reached.extend(k for k in ks if k in g.m.stmt and e.head(k))
    uks = lean_order(called_uncostly(e, reached), e.head)
    count = defaultdict(int)
    uposts = []
    for k in uks:
        h = e.head(k)
        uposts.append(([e.upost(k, count[h])], set(), set()))
        count[h] += 1
    os.makedirs(outdir, exist_ok=True)
    chunks = []
    def flush(kind, items, per):
        cur, defs, needs, n = [], set(), set(), 0
        for it, d, nd in items:
            cur.append(''.join(it))
            defs |= d
            needs |= nd
            n += 1
            if n >= per:
                chunks.append((kind, cur, defs, needs))
                cur, defs, needs, n = [], set(), set(), 0
        if cur:
            chunks.append((kind, cur, defs, needs))
    # One module of each kind: Lean proves a module's theorems in parallel
    # (a theorem needs only the statements of those it uses), while each module
    # waits for the whole of the ones it imports and pays its own imports. With
    # the precondition lemmas in 5 modules (60 groups each), each waited for the
    # one before: build_files' chain took about 4 minutes, 3 modules about 2.
    flush('UPost', uposts, int(os.environ.get('UPOST_PER', '1000')))
    flush('Post', posts, int(os.environ.get('POST_PER', '2000')))
    flush('Pre', pres, int(os.environ.get('PRE_PER', '1000')))
    # each module imports the uposts' modules before it (found by name, not
    # tracked) and those defining the lemmas its models call (not a chain:
    # independent modules build in parallel)
    base = [values, 'Lanius.Faithful.GenB.SelfBModel4']
    mods = []
    for i, (kind, items, defs, needs) in enumerate(chunks):
        name = f'SelfP{i:02d}'
        deps = [f'{prefix}.SelfP{j:02d}' for j, c in enumerate(chunks[:i])
                if c[0] == 'UPost' or (c[2] & (needs - defs))]
        imports = '\n'.join('import ' + m for m in base + deps)
        prof = 'set_option profiler true\nset_option profiler.threshold 1500\n' if os.environ.get('PRE_PROFILE') else ''
        text = HEADER.format(imports=imports, what=f'{kind} lemmas, part {i}', ns=ns) + prof + '\n'.join(items) + \
            f'\nend {ns}\n'
        open(os.path.join(outdir, name + '.lean'), 'w').write(text)
        mods.append(f'{prefix}.{name}')
    print(len(uposts), 'uposts', len(posts), 'post groups', len(pres), 'pre groups', len(mods), 'modules')


if __name__ == '__main__':
    main()


def uncostly_report(genb, roots):
    g = Gen(genb, roots)
    r = g.reach()
    text = ''.join(g.m.body[x] for x in r)
    heads = set(re.findall(r'Lanius\.Mini\.((?:Inline\.)?[a-z]\w*)', text))
    out = []
    for k, (ps, costly, rep, term) in sorted(g.m.stmt.items()):
        if costly or g.flat(rep_ty(rep)):
            continue
        h = re.match(r'\(?Lanius\.Mini\.((?:Inline\.)?\w+)', term)
        if h and h.group(1) in heads:
            out.append((k, h.group(1), rep_ty(rep), [t for _, t in ps]))
    return out
