import Lanius.Mini.FrontSpec

/-! # One reading (roadmap step V4)

At most one tree for `file` is `Picked` for a file's tokens, so the tree the
validator accepts from laniusc is the only one (`validate_unique`).

The grammar is checked by a certificate, `Cert`: for each nonterminal, a set
holding the first two leaf kinds (fewer if the leaves are fewer) of every tree
for it, `first`, and of whatever follows it in a tree for `file`, `follow`.
`certOK` checks, by computation, that the sets are closed under the grammar's
productions (so they hold at least what they claim) and that two productions
of one nonterminal never both fit: after their common prefix, the first two
kinds the rest of each can begin with, followed by the nonterminal's follow
set, are told apart by the tokens, even where a `>>` may be read as two `>`.
The two exceptions are the generic path segment `x<...>` against `x`, which
`picks` decides, and the two productions `picks` never allows.

Sets are `Kinds2`, of lists of codes: the certificate gives each token kind a
code below 80 (`Cert.ix`; the grammar has 78 kinds), `>` code 1 and `>>`
code 2. A set says whether the empty list is in it, has a bit per code for
the one-code lists, and a bit `80 * a + b` per two-code prefix `a b`. Codes
need not be one per kind: two kinds with one code are only told apart less. -/

namespace Lanius.Mini

/-- A set of lists of at most two codes, each standing for the lists that
begin with it. -/
structure Kinds2 where
  empty : Bool
  one : Nat
  two : Nat
  deriving Repr

namespace Kinds2

/-- `w` is in `S`: its first two kinds (all of it, if shorter) are. -/
def Mem (S : Kinds2) : List Nat → Prop
  | [] => S.empty = true
  | [a] => a < 80 ∧ S.one.testBit a = true
  | a :: b :: _ => a < 80 ∧ b < 80 ∧ S.two.testBit (80 * a + b) = true

def eps : Kinds2 := ⟨true, 0, 0⟩

def single (k : Nat) : Kinds2 := ⟨false, 2 ^ k, 0⟩

/-- Row `a` of the pairs: the second kinds after `a`. -/
def row (x a : Nat) : Nat := (x >>> (80 * a)) % 2 ^ 80

/-- A bit per first kind of the pairs, for the rows below `n`. -/
def heads (x : Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => heads x n ||| (if row x n = 0 then 0 else 2 ^ n)

/-- The first kinds of `T`'s nonempty lists. -/
def firsts (T : Kinds2) : Nat := T.one ||| heads T.two 80

/-- The pairs `a b` with `a` in `A` (below `n`) and `b` in `F`. -/
def outer (A F : Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => outer A F n ||| (if A.testBit n then F <<< (80 * n) else 0)

/-- The first two kinds of `u ++ v`, for `u` in `S` and `v` in `T`. -/
def concat (S T : Kinds2) : Kinds2 :=
  ⟨S.empty && T.empty,
   (if S.empty then T.one else 0) ||| (if T.empty then S.one else 0),
   (if S.empty then T.two else 0) ||| S.two ||| outer S.one (firsts T) 80⟩

def sub (S T : Kinds2) : Bool :=
  (!S.empty || T.empty) && (S.one &&& T.one == S.one) && (S.two &&& T.two == S.two)

/-- A bit `80 * a + k` for each row `a` below `n`. -/
def column (k : Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => column k n ||| 2 ^ (80 * n + k)

/-- The pairs with a second code `>>` (2) or `>` (1) also given the other. -/
def widen (x : Nat) : Nat :=
  x ||| ((x &&& column 2 80) >>> 1) ||| ((x &&& column 1 80) <<< 1)

/-- No list in `S` and list in `T` can be the leaf kinds of two readings of
one token sequence (`Compat`). -/
def apart (S T : Kinds2) : Bool :=
  !(S.empty && T.empty) && (S.one &&& T.one == 0) &&
  !(S.one.testBit 2 && T.two.testBit (80 * 1 + 1)) &&
  !(T.one.testBit 2 && S.two.testBit (80 * 1 + 1)) &&
  (S.two &&& widen T.two == 0) &&
  !(row S.two 2 != 0 && T.two.testBit (80 * 1 + 1)) &&
  !(row T.two 2 != 0 && S.two.testBit (80 * 1 + 1))

/-! ### The sets' lemmas -/

theorem testBit_or_left {x y i : Nat} (h : x.testBit i = true) : (x ||| y).testBit i = true := by
  simp [Nat.testBit_or, h]

theorem testBit_or_right {x y i : Nat} (h : y.testBit i = true) : (x ||| y).testBit i = true := by
  simp [Nat.testBit_or, h]

theorem testBit_pair {a b : Nat} (hb : b < 80) (x : Nat) :
    (x >>> (80 * a)).testBit b = x.testBit (80 * a + b) := by
  rw [Nat.testBit_shiftRight]

theorem row_testBit {x a b : Nat} (hb : b < 80) : (row x a).testBit b = x.testBit (80 * a + b) := by
  unfold row
  rw [Nat.testBit_mod_two_pow, Nat.testBit_shiftRight]
  simp [hb]

theorem row_ne_zero {x a b : Nat} (hb : b < 80) (h : x.testBit (80 * a + b) = true) : row x a ≠ 0 := by
  intro z
  have := row_testBit (x := x) (a := a) hb
  rw [z, h, Nat.zero_testBit] at this
  exact Bool.false_ne_true this

theorem heads_testBit {x a b : Nat} (hb : b < 80) (h : x.testBit (80 * a + b) = true) :
    ∀ n, a < n → (heads x n).testBit a = true
  | 0, lt => absurd lt (Nat.not_lt_zero _)
  | n + 1, lt => by
    rcases Nat.lt_succ_iff_lt_or_eq.mp lt with lt | eq
    · exact testBit_or_left (heads_testBit hb h n lt)
    · subst eq
      apply testBit_or_right
      simp [row_ne_zero hb h, Nat.testBit_two_pow]

theorem outer_testBit {A F a b : Nat} (ha : A.testBit a = true) (hf : F.testBit b = true) :
    ∀ n, a < n → (outer A F n).testBit (80 * a + b) = true
  | 0, lt => absurd lt (Nat.not_lt_zero _)
  | n + 1, lt => by
    rcases Nat.lt_succ_iff_lt_or_eq.mp lt with lt | eq
    · exact testBit_or_left (outer_testBit ha hf n lt)
    · subst eq
      apply testBit_or_right
      simp only [ha, if_true, Nat.testBit_shiftLeft]
      simp [hf]

theorem firsts_of_mem {T : Kinds2} {b : Nat} {rest : List Nat} (h : T.Mem (b :: rest)) :
    (firsts T).testBit b = true := by
  cases rest with
  | nil => exact testBit_or_left h.2
  | cons c more =>
    obtain ⟨hb, hc, bit⟩ := h
    exact testBit_or_right (heads_testBit hc bit 80 hb)

theorem mem_concat {S T : Kinds2} {u v : List Nat} (hu : S.Mem u) (hv : T.Mem v) :
    (concat S T).Mem (u ++ v) := by
  match u, v with
  | [], [] => simp_all [Mem, concat]
  | [], [b] => exact ⟨hv.1, testBit_or_left (by simp [show S.empty = true from hu, hv.2])⟩
  | [], b :: c :: more =>
    exact ⟨hv.1, hv.2.1, testBit_or_left (testBit_or_left (by simp [show S.empty = true from hu, hv.2.2]))⟩
  | [a], [] =>
    exact ⟨hu.1, testBit_or_right (by simp [show T.empty = true from hv, hu.2])⟩
  | [a], b :: more =>
    have hb : b < 80 := by
      cases more with
      | nil => exact hv.1
      | cons c rest => exact hv.1
    exact ⟨hu.1, hb, testBit_or_right (outer_testBit hu.2 (firsts_of_mem hv) 80 hu.1)⟩
  | a :: b :: more, v => exact ⟨hu.1, hu.2.1, testBit_or_left (testBit_or_right hu.2.2)⟩

theorem testBit_of_and_eq {x y i : Nat} (h : (x &&& y == x) = true) (hx : x.testBit i = true) :
    y.testBit i = true := by
  have e : x &&& y = x := by simpa using h
  have := congrArg (fun z => z.testBit i) e
  simp only [Nat.testBit_and, hx, Bool.true_and] at this
  exact this

theorem mem_sub {S T : Kinds2} {w : List Nat} (h : sub S T = true) (hw : S.Mem w) : T.Mem w := by
  simp only [sub, Bool.and_eq_true] at h
  obtain ⟨⟨he, h1⟩, h2⟩ := h
  match w with
  | [] =>
    have : S.empty = true := hw
    show T.empty = true
    simpa [this] using he
  | [a] => exact ⟨hw.1, testBit_of_and_eq h1 hw.2⟩
  | a :: b :: more => exact ⟨hw.1, hw.2.1, testBit_of_and_eq h2 hw.2.2⟩

theorem mem_single {k : Nat} (hk : k < 80) : (single k).Mem [k] :=
  ⟨hk, by simp [single, Nat.testBit_two_pow]⟩

theorem mem_eps : eps.Mem [] := rfl

end Kinds2

/-! ### Two readings of one token sequence -/

/-- The first kinds of two leaf sequences that read the same tokens: equal,
or a `>>` (`hi`) against the first half `>` (`lo`) of it. -/
def Compat1 (hi lo : Nat) : List Nat → List Nat → Prop
  | [], [] => True
  | [], _ :: _ => False
  | _ :: _, [] => False
  | a :: _, b :: _ => a = b ∨ (a = hi ∧ b = lo) ∨ (a = lo ∧ b = hi)

/-- The first two kinds of two leaf sequences that read the same tokens. -/
def Compat (hi lo : Nat) : List Nat → List Nat → Prop
  | [], [] => True
  | [], _ :: _ => False
  | _ :: _, [] => False
  | a :: r, b :: s => (a = b ∧ Compat1 hi lo r s) ∨ (a = hi ∧ b = lo ∧ s.head? = some lo) ∨
      (a = lo ∧ b = hi ∧ r.head? = some lo)

theorem compat1_symm {hi lo : Nat} : ∀ {u v : List Nat}, Compat1 hi lo u v → Compat1 hi lo v u
  | [], [], h => h
  | [], _ :: _, h => h.elim
  | _ :: _, [], h => h.elim
  | _ :: _, _ :: _, h => by
    rcases h with h | ⟨h₁, h₂⟩ | ⟨h₁, h₂⟩
    · exact .inl h.symm
    · exact .inr (.inr ⟨h₂, h₁⟩)
    · exact .inr (.inl ⟨h₂, h₁⟩)

theorem compat_symm {hi lo : Nat} : ∀ {u v : List Nat}, Compat hi lo u v → Compat hi lo v u
  | [], [], h => h
  | [], _ :: _, h => h.elim
  | _ :: _, [], h => h.elim
  | _ :: _, _ :: _, h => by
    rcases h with ⟨h₁, h₂⟩ | ⟨ha, hb, hs⟩ | ⟨ha, hb, hr⟩
    · exact .inl ⟨h₁.symm, compat1_symm h₂⟩
    · exact .inr (.inr ⟨hb, ha, hs⟩)
    · exact .inr (.inl ⟨hb, ha, hr⟩)

theorem compat1_map {hi lo : Nat} (f : Nat → Nat) :
    ∀ {u v : List Nat}, Compat1 hi lo u v → Compat1 (f hi) (f lo) (u.map f) (v.map f)
  | [], [], h => h
  | [], _ :: _, h => h.elim
  | _ :: _, [], h => h.elim
  | a :: _, b :: _, h => by
    rcases h with rfl | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact .inl rfl
    · exact .inr (.inl ⟨rfl, rfl⟩)
    · exact .inr (.inr ⟨rfl, rfl⟩)

theorem compat_map {hi lo : Nat} (f : Nat → Nat) :
    ∀ {u v : List Nat}, Compat hi lo u v → Compat (f hi) (f lo) (u.map f) (v.map f)
  | [], [], h => h
  | [], _ :: _, h => h.elim
  | _ :: _, [], h => h.elim
  | a :: r, b :: s, h => by
    simp only [List.map_cons, Compat]
    rcases h with ⟨h₁, h₂⟩ | ⟨ha, hb, hs⟩ | ⟨ha, hb, hr⟩
    · subst h₁
      exact .inl ⟨rfl, compat1_map f h₂⟩
    · refine .inr (.inl ⟨by rw [ha], by rw [hb], ?_⟩)
      cases s with
      | nil => simp at hs
      | cons x s => simp at hs; simp [hs]
    · refine .inr (.inr ⟨by rw [ha], by rw [hb], ?_⟩)
      cases r with
      | nil => simp at hr
      | cons x r => simp at hr; simp [hr]

theorem shrFirst_kind (t : Token) : (shrFirst t).kind = 13 := rfl

theorem shrSecond_kind (t : Token) : (shrSecond t).kind = 13 := rfl

/-- What reads a token sequence that begins with a `>`'s second half begins
with that token. -/
theorem reads_second_head {l : List Token} {t : Token} {ts : List Token} (h : Reads l (shrSecond t :: ts) []) :
    ∃ more, l = shrSecond t :: more := by
  cases h with
  | token _ => exact ⟨_, rfl⟩
  | halves k _ => exact absurd k (by simp [shrSecond_kind])

theorem reads_compat1 {l₁ l₂ tokens : List Token} (h₁ : Reads l₁ tokens []) (h₂ : Reads l₂ tokens []) :
    Compat1 44 13 (l₁.map Token.kind) (l₂.map Token.kind) := by
  cases h₁ with
  | done =>
    cases h₂ with
    | done => trivial
  | token _ =>
    cases h₂ with
    | token _ => exact .inl rfl
    | halves k _ => exact .inr (.inl ⟨k, rfl⟩)
  | halves k _ =>
    cases h₂ with
    | token _ => exact .inr (.inr ⟨rfl, k⟩)
    | halves _ _ => exact .inl rfl

theorem reads_compat {l₁ l₂ tokens : List Token} (h₁ : Reads l₁ tokens []) (h₂ : Reads l₂ tokens []) :
    Compat 44 13 (l₁.map Token.kind) (l₂.map Token.kind) := by
  cases h₁ with
  | done =>
    cases h₂ with
    | done => trivial
  | token r₁ =>
    cases h₂ with
    | token r₂ => exact .inl ⟨rfl, reads_compat1 r₁ r₂⟩
    | halves k r₂ =>
      obtain ⟨more, rfl⟩ := reads_second_head r₂
      exact .inr (.inl ⟨k, rfl, rfl⟩)
  | halves k r₁ =>
    cases h₂ with
    | token r₂ =>
      obtain ⟨more, rfl⟩ := reads_second_head r₁
      exact .inr (.inr ⟨rfl, k, rfl⟩)
    | halves _ r₂ => exact .inl ⟨rfl, reads_compat1 r₁ r₂⟩

namespace Kinds2

theorem column_testBit {k a : Nat} : ∀ n, a < n → (column k n).testBit (80 * a + k) = true
  | 0, lt => absurd lt (Nat.not_lt_zero _)
  | n + 1, lt => by
    rcases Nat.lt_succ_iff_lt_or_eq.mp lt with lt | eq
    · exact testBit_or_left (column_testBit n lt)
    · subst eq
      exact testBit_or_right (by simp [Nat.testBit_two_pow])

theorem widen_self {x i : Nat} (h : x.testBit i = true) : (widen x).testBit i = true :=
  testBit_or_left (testBit_or_left h)

theorem widen_down {x a : Nat} (ha : a < 80) (h : x.testBit (80 * a + 2) = true) :
    (widen x).testBit (80 * a + 1) = true := by
  apply testBit_or_left
  apply testBit_or_right
  rw [Nat.testBit_shiftRight, show 1 + (80 * a + 1) = 80 * a + 2 by omega, Nat.testBit_and, h,
    column_testBit 80 ha]
  rfl

theorem widen_up {x a : Nat} (ha : a < 80) (h : x.testBit (80 * a + 1) = true) :
    (widen x).testBit (80 * a + 2) = true := by
  apply testBit_or_right
  rw [Nat.testBit_shiftLeft, show 80 * a + 2 - 1 = 80 * a + 1 by omega, Nat.testBit_and, h,
    column_testBit 80 ha]
  simp

theorem and_ne_zero {x y i : Nat} (hx : x.testBit i = true) (hy : y.testBit i = true) : (x &&& y == 0) = false := by
  apply Bool.eq_false_iff.mpr
  intro e
  have e' : x &&& y = 0 := by simpa using e
  have := congrArg (fun z => z.testBit i) e'
  simp [Nat.testBit_and, hx, hy] at this

/-- `apart` is sound: no two lists of its sets are `Compat`. -/
theorem apart_sound {S T : Kinds2} (h : apart S T = true) {u v : List Nat} (hu : S.Mem u) (hv : T.Mem v) :
    ¬Compat 2 1 u v := by
  simp only [apart, Bool.and_eq_true, Bool.not_eq_true', Bool.and_eq_false_iff] at h
  obtain ⟨⟨⟨⟨⟨⟨hee, h11⟩, h1s⟩, hs1⟩, h22⟩, h4t⟩, ht4⟩ := h
  intro c
  match u, v with
  | [], [] =>
    have e1 : S.empty = true := hu
    have e2 : T.empty = true := hv
    simp [e1, e2] at hee
  | [], _ :: _ => exact c
  | _ :: _, [] => exact c
  | [a], [b] =>
    have c' : a = b := by simpa [Compat, Compat1] using c
    subst c'
    rw [and_ne_zero hu.2 hv.2] at h11
    exact Bool.false_ne_true h11
  | [a], b :: d :: r =>
    have c' : a = 2 ∧ b = 1 ∧ d = 1 := by simpa [Compat, Compat1] using c
    obtain ⟨rfl, rfl, rfl⟩ := c'
    have x1 : S.one.testBit 2 = true := hu.2
    have x2 : T.two.testBit (80 * 1 + 1) = true := hv.2.2
    rcases h1s with h | h
    · simp [x1] at h
    · simp [x2] at h
  | a :: b :: r, [d] =>
    have c' : a = 1 ∧ d = 2 ∧ b = 1 := by simpa [Compat, Compat1] using c
    obtain ⟨rfl, rfl, rfl⟩ := c'
    have x1 : T.one.testBit 2 = true := hv.2
    have x2 : S.two.testBit (80 * 1 + 1) = true := hu.2.2
    rcases hs1 with h | h
    · simp [x1] at h
    · simp [x2] at h
  | a :: b :: r, d :: e :: s =>
    obtain ⟨ha, hb, bitS⟩ := hu
    obtain ⟨hd, he, bitT⟩ := hv
    have c' : (a = d ∧ (b = e ∨ (b = 2 ∧ e = 1) ∨ (b = 1 ∧ e = 2))) ∨ (a = 2 ∧ d = 1 ∧ e = 1) ∨
        (a = 1 ∧ d = 2 ∧ b = 1) := by simpa [Compat, Compat1] using c
    rcases c' with ⟨rfl, cb⟩ | ⟨rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl⟩
    · have wide : (widen T.two).testBit (80 * a + b) = true := by
        rcases cb with rfl | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
        · exact widen_self bitT
        · exact widen_up ha bitT
        · exact widen_down ha bitT
      rw [and_ne_zero bitS wide] at h22
      exact Bool.false_ne_true h22
    · have x1 : (row S.two 2 != 0) = true := by simpa using row_ne_zero hb bitS
      rcases h4t with h | h
      · simp [x1] at h
      · simp [bitT] at h
    · have x1 : (row T.two 2 != 0) = true := by simpa using row_ne_zero he bitT
      rcases ht4 with h | h
      · simp [x1] at h
      · simp [bitS] at h

end Kinds2

/-! ### The certificate and its check -/

/-- The claimed first and follow sets of each nonterminal. -/
structure Cert where
  index : List Nat
  first : List Kinds2
  follow : List Kinds2

namespace Cert

def none2 : Kinds2 := ⟨false, 0, 0⟩

/-- The code of a token kind. -/
def ix (C : Cert) (k : Nat) : Nat := C.index.getD k 0 % 80

/-- The codes of leaves. -/
def codes (C : Cert) (l : List Token) : List Nat := l.map fun t => C.ix t.kind

def firstOf (C : Cert) (X : Nat) : Kinds2 := C.first.getD X none2

def followOf (C : Cert) (X : Nat) : Kinds2 := C.follow.getD X none2

def symFirst (C : Cert) : Sym → Kinds2
  | .term k => Kinds2.single (C.ix k)
  | .nonterm Y => C.firstOf Y

/-- The first two kinds of what the symbols `rhs` derive. -/
def seqFirst (C : Cert) : List Sym → Kinds2
  | [] => Kinds2.eps
  | s :: rest => Kinds2.concat (C.symFirst s) (C.seqFirst rest)

/-- Each nonterminal on `rhs` can be followed by what the rest of `rhs` and
then `lhs`'s follow set begin with. -/
def itemsOK (C : Cert) (lhs : Nat) : List Sym → Bool
  | [] => true
  | .term _ :: rest => C.itemsOK lhs rest
  | .nonterm Y :: rest =>
    Kinds2.sub (Kinds2.concat (C.seqFirst rest) (C.followOf lhs)) (C.followOf Y) && C.itemsOK lhs rest

/-- What the rest of `rhs`, after `j` symbols, and then `lhs`'s follow set
begin with. -/
def lookahead (C : Cert) (lhs j : Nat) (rhs : List Sym) : Kinds2 :=
  Kinds2.concat (C.seqFirst (rhs.drop j)) (C.followOf lhs)

end Cert

/-- The number of symbols two right sides begin with alike. -/
def commonPrefix : List Sym → List Sym → Nat
  | [], [] => 0
  | [], _ :: _ => 0
  | _ :: _, [] => 0
  | a :: r, b :: s => if a = b then commonPrefix r s + 1 else 0

/-- The productions `picks` never allows. -/
def ruledOut (p : Nat) : Bool := p == 298

/-- The pairs of productions `picks` tells apart: a path segment with or
without type arguments, and a block or expression statement. -/
def pickedPair (p q : Nat) : Bool := (p == 48 && q == 49) || (p == 84 && q == 85)

namespace Cert

def ruleOK (C : Cert) (p : Nat) (r : Rule) : Bool :=
  ruledOut p || (Kinds2.sub (C.seqFirst r.rhs) (C.firstOf r.lhs) && C.itemsOK r.lhs r.rhs)

def pairOK (C : Cert) (p : Nat) (r : Rule) (q : Nat) (r' : Rule) : Bool :=
  ruledOut p || ruledOut q || r.lhs != r'.lhs || pickedPair p q ||
    Kinds2.apart (C.lookahead r.lhs (commonPrefix r.rhs r'.rhs) r.rhs)
      (C.lookahead r.lhs (commonPrefix r.rhs r'.rhs) r'.rhs)

end Cert

def allWith (f : Nat → Rule → Bool) : Nat → List Rule → Bool
  | _, [] => true
  | i, r :: rs => f i r && allWith f (i + 1) rs

def pairsAll (f : Nat → Rule → Nat → Rule → Bool) : Nat → List Rule → Bool
  | _, [] => true
  | i, r :: rs => allWith (f i r) (i + 1) rs && pairsAll f (i + 1) rs

/-- The certificate holds for the grammar `g`: `>` has code 1 and `>>` code
2, `file`'s follow set has the empty list, each production's right side derives only what its left side's
first set has and gives each of its nonterminals a follow set that holds
what can follow it there, and two productions of one nonterminal are
`apart` after their common prefix (except as `picks` decides). -/
def certOK (g : List Rule) (C : Cert) : Bool :=
  C.ix 13 == 1 && C.ix 44 == 2 && (C.followOf 0).empty && allWith C.ruleOK 0 g && pairsAll C.pairOK 0 g

/-! ### Lemmas about the check -/

theorem allWith_get {f : Nat → Rule → Bool} :
    ∀ {i : Nat} {rs : List Rule} {p : Nat} {r : Rule}, allWith f i rs = true → rs[p]? = some r → f (i + p) r = true
  | _, [], _, _, _, h => by simp at h
  | i, r :: rs, 0, r', h, e => by
    simp only [allWith, Bool.and_eq_true] at h
    simp only [List.getElem?_cons_zero, Option.some.injEq] at e
    subst e
    simpa using h.1
  | i, r :: rs, p + 1, r', h, e => by
    simp only [allWith, Bool.and_eq_true] at h
    simp only [List.getElem?_cons_succ] at e
    have := allWith_get h.2 e
    rwa [show i + 1 + p = i + (p + 1) by omega] at this

theorem pairsAll_get {f : Nat → Rule → Nat → Rule → Bool} :
    ∀ {i : Nat} {rs : List Rule} {p q : Nat} {r r' : Rule}, pairsAll f i rs = true → rs[p]? = some r →
      rs[q]? = some r' → p < q → f (i + p) r (i + q) r' = true
  | _, [], _, _, _, _, _, e, _, _ => by simp at e
  | i, r :: rs, 0, q + 1, r₁, r₂, h, e₁, e₂, _ => by
    simp only [pairsAll, Bool.and_eq_true] at h
    simp only [List.getElem?_cons_zero, Option.some.injEq] at e₁
    simp only [List.getElem?_cons_succ] at e₂
    subst e₁
    have := allWith_get h.1 e₂
    rwa [show i + 1 + q = i + (q + 1) by omega, show i = i + 0 by omega] at this
  | _, _ :: _, _ + 1, 0, _, _, _, _, _, lt => absurd lt (Nat.not_lt_zero _)
  | _, _ :: _, 0, 0, _, _, _, _, _, lt => absurd lt (Nat.lt_irrefl 0)
  | i, r :: rs, p + 1, q + 1, r₁, r₂, h, e₁, e₂, lt => by
    simp only [pairsAll, Bool.and_eq_true] at h
    simp only [List.getElem?_cons_succ] at e₁ e₂
    have := pairsAll_get h.2 e₁ e₂ (by omega)
    rwa [show i + 1 + p = i + (p + 1) by omega, show i + 1 + q = i + (q + 1) by omega] at this

theorem picks_ruledOut {p : Nat} {tokens : List Token} (h : picks p tokens = true) : ruledOut p = false := by
  unfold picks at h
  unfold ruledOut
  by_cases e : p = 298
  · subst e; simp at h
  · simp [e]

theorem picks_pair {p q : Nat} {tokens : List Token} (pair : pickedPair p q = true) (h₁ : picks p tokens = true)
    (h₂ : picks q tokens = true) : False := by
  simp only [pickedPair, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq] at pair
  rcases pair with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  · unfold picks at h₁ h₂
    simp only [show ¬(48 = 84) by decide, show ¬(48 = 85) by decide, show ¬(48 = 298) by decide,
      show ¬(49 = 84) by decide, show ¬(49 = 85) by decide, show ¬(49 = 298) by decide,
      show ¬(49 = 48) by decide, if_false, if_true] at h₁ h₂
    simp [h₂] at h₁
  · unfold picks at h₁ h₂
    simp only [show ¬(84 = 298) by decide, show ¬(85 = 298) by decide, show ¬(85 = 84) by decide,
      if_false, if_true] at h₁ h₂
    simp [h₁] at h₂

theorem commonPrefix_symm : ∀ (r s : List Sym), commonPrefix r s = commonPrefix s r
  | [], [] => rfl
  | [], _ :: _ => rfl
  | _ :: _, [] => rfl
  | a :: r, b :: s => by
    by_cases e : a = b
    · subst e; simp [commonPrefix, commonPrefix_symm r s]
    · simp [commonPrefix, e, Ne.symm e]

theorem commonPrefix_take : ∀ (r s : List Sym), r.take (commonPrefix r s) = s.take (commonPrefix r s)
  | [], [] => rfl
  | [], _ :: _ => rfl
  | _ :: _, [] => rfl
  | a :: r, b :: s => by
    by_cases e : a = b
    · subst e; simp [commonPrefix, commonPrefix_take r s]
    · simp [commonPrefix, e]

/-! ### Trees -/

mutual
def CTree.size : CTree → Nat
  | .leaf _ => 1
  | .node _ kids => CTree.kidsSize kids + 1

def CTree.kidsSize : List CTree → Nat
  | [] => 0
  | c :: cs => c.size + CTree.kidsSize cs
end

theorem CTree.size_pos : ∀ (c : CTree), 0 < c.size
  | .leaf _ => by simp [CTree.size]
  | .node _ _ => by simp [CTree.size]

theorem CTree.kidsSize_append : ∀ (a b : List CTree), CTree.kidsSize (a ++ b) = CTree.kidsSize a + CTree.kidsSize b
  | [], b => by simp [CTree.kidsSize]
  | c :: a, b => by simp [CTree.kidsSize, CTree.kidsSize_append a b, Nat.add_assoc]

theorem CTree.leavesOf_append : ∀ (a b : List CTree), CTree.leavesOf (a ++ b) = CTree.leavesOf a ++ CTree.leavesOf b
  | [], b => by simp [CTree.leavesOf]
  | c :: a, b => by simp [CTree.leavesOf, CTree.leavesOf_append a b]

theorem KidsShape.split {g : List Rule} :
    ∀ {β γ : List Sym} {kids : List CTree}, KidsShape g (β ++ γ) kids →
      ∃ k₁ k₂, kids = k₁ ++ k₂ ∧ KidsShape g β k₁ ∧ KidsShape g γ k₂
  | [], _, kids, h => ⟨[], kids, rfl, .nil, h⟩
  | .term _ :: β, _, _, .term k rest => by
    obtain ⟨k₁, k₂, rfl, h₁, h₂⟩ := KidsShape.split rest
    exact ⟨_ :: k₁, k₂, rfl, .term k h₁, h₂⟩
  | .nonterm _ :: β, _, _, .nonterm s rest => by
    obtain ⟨k₁, k₂, rfl, h₁, h₂⟩ := KidsShape.split rest
    exact ⟨_ :: k₁, k₂, rfl, .nonterm s h₁, h₂⟩

theorem PickedKids.split : ∀ {k₁ k₂ : List CTree} {tokens rest : List Token}, PickedKids (k₁ ++ k₂) tokens rest →
    ∃ mid, PickedKids k₁ tokens mid ∧ PickedKids k₂ mid rest
  | [], _, tokens, _, h => ⟨tokens, .nil, h⟩
  | _ :: _, _, _, _, .cons c rest => by
    obtain ⟨mid, h₁, h₂⟩ := PickedKids.split rest
    exact ⟨mid, .cons c h₁, h₂⟩

theorem reads_nil {tokens rest : List Token} (h : Reads [] tokens rest) : rest = tokens := by
  cases h
  rfl

/-- A leaf of a given kind reads the next token one way. -/
theorem reads_leaf_unique {l₁ l₂ : Token} {tokens m₁ m₂ : List Token} (h₁ : Reads [l₁] tokens m₁)
    (h₂ : Reads [l₂] tokens m₂) (k : l₁.kind = l₂.kind) : l₁ = l₂ ∧ m₁ = m₂ := by
  cases h₁ with
  | token r₁ =>
    cases h₂ with
    | token r₂ => exact ⟨rfl, (reads_nil r₁).trans (reads_nil r₂).symm⟩
    | halves k₂ _ => rw [k₂, shrFirst_kind] at k; exact absurd k (by decide)
  | halves k₁ r₁ =>
    cases h₂ with
    | token _ => rw [k₁, shrFirst_kind] at k; exact absurd k (by decide)
    | halves _ r₂ => exact ⟨rfl, (reads_nil r₁).trans (reads_nil r₂).symm⟩

namespace Cert

variable {g : List Rule} {C : Cert}

theorem codes_append (l₁ l₂ : List Token) : C.codes (l₁ ++ l₂) = C.codes l₁ ++ C.codes l₂ := List.map_append

theorem codes_eq (l : List Token) : C.codes l = (l.map Token.kind).map C.ix := by
  simp [codes, List.map_map, Function.comp_def]

theorem ix_lt (k : Nat) : C.ix k < 80 := Nat.mod_lt _ (by decide)

theorem certOK_codes (ok : certOK g C = true) : C.ix 13 = 1 ∧ C.ix 44 = 2 := by
  simp only [certOK, Bool.and_eq_true, beq_iff_eq] at ok
  exact ⟨ok.1.1.1.1, ok.1.1.1.2⟩

/-- The facts `certOK` gives about a production `picks` allows somewhere. -/
theorem rule_facts (ok : certOK g C = true) {p : Nat} {prod : Rule} (found : g[p]? = some prod)
    {tokens : List Token} (hp : picks p tokens = true) :
    Kinds2.sub (C.seqFirst prod.rhs) (C.firstOf prod.lhs) = true ∧ C.itemsOK prod.lhs prod.rhs = true := by
  simp only [certOK, Bool.and_eq_true] at ok
  have := allWith_get ok.1.2 found
  simp only [Nat.zero_add, ruleOK, picks_ruledOut hp, Bool.false_or, Bool.and_eq_true] at this
  exact this

theorem pairs_ok (ok : certOK g C = true) : pairsAll C.pairOK 0 g = true := by
  simp only [certOK, Bool.and_eq_true] at ok
  exact ok.2

mutual
/-- A tree's first two leaf codes are in its nonterminal's first set. -/
theorem first_tree (ok : certOK g C = true) : ∀ {X : Nat} {t : CTree} {tokens m : List Token},
    Shape g X t → Picked t tokens m → (C.firstOf X).Mem (C.codes t.leaves)
  | _, _, _, _, .node found lhs kids, .node hp pk => by
    obtain ⟨sub, -⟩ := rule_facts ok found hp
    have := Kinds2.mem_sub sub (first_kids ok kids pk)
    rw [lhs] at this
    simpa [CTree.leaves] using this

theorem first_kids (ok : certOK g C = true) : ∀ {rhs : List Sym} {kids : List CTree} {tokens m : List Token},
    KidsShape g rhs kids → PickedKids kids tokens m → (C.seqFirst rhs).Mem (C.codes (CTree.leavesOf kids))
  | _, _, _, _, .nil, .nil => Kinds2.mem_eps
  | .term kind :: _, _, _, _, .term (token := tok) hk rest, .cons _ pr => by
    have := Kinds2.mem_concat (Kinds2.mem_single (ix_lt (C := C) kind)) (first_kids ok rest pr)
    rw [← hk] at this
    simpa [CTree.leavesOf, CTree.leaves, seqFirst, symFirst, hk, codes] using this
  | .nonterm _ :: _, _, _, _, .nonterm s rest, .cons pc pr => by
    have := Kinds2.mem_concat (first_tree ok s pc) (first_kids ok rest pr)
    simpa [CTree.leavesOf, seqFirst, symFirst, codes_append] using this
end

/-- Each nonterminal child's leaves are followed by codes in its follow set. -/
def KidsFollow (C : Cert) : List Sym → List CTree → List Token → Prop
  | [], [], _ => True
  | [], _ :: _, _ => True
  | _ :: _, [], _ => True
  | .term _ :: rhs, _ :: kids, c => KidsFollow C rhs kids c
  | .nonterm Y :: rhs, _ :: kids, c => (C.followOf Y).Mem (C.codes (CTree.leavesOf kids ++ c)) ∧ KidsFollow C rhs kids c

theorem kidsFollow_of (ok : certOK g C = true) {A : Nat} :
    ∀ {rhs : List Sym} {kids : List CTree} {tokens m c : List Token}, C.itemsOK A rhs = true →
      KidsShape g rhs kids → PickedKids kids tokens m → (C.followOf A).Mem (C.codes c) → KidsFollow C rhs kids c
  | _, _, _, _, _, _, .nil, .nil, _ => trivial
  | .term _ :: _, _, _, _, _, items, .term _ rest, .cons _ pr, fa => by
    simp only [itemsOK] at items
    have := kidsFollow_of ok items rest pr fa
    exact this
  | .nonterm _ :: _, _, _, _, _, items, .nonterm _ rest, .cons _ pr, fa => by
    simp only [itemsOK, Bool.and_eq_true] at items
    refine ⟨?_, kidsFollow_of ok items.2 rest pr fa⟩
    have := Kinds2.mem_sub items.1 (Kinds2.mem_concat (first_kids ok rest pr) fa)
    simpa [codes_append] using this

theorem kidsFollow_prefix : ∀ {β γ : List Sym} {k₁ k₂ : List CTree} {c : List Token},
    KidsShape g β k₁ → KidsFollow C (β ++ γ) (k₁ ++ k₂) c → KidsFollow C β k₁ (CTree.leavesOf k₂ ++ c)
  | _, _, _, _, _, .nil, _ => trivial
  | .term _ :: β, γ, _ :: k₁, k₂, c, .term _ rest, h => by
    have h' : KidsFollow C (β ++ γ) (k₁ ++ k₂) c := h
    have := kidsFollow_prefix rest h'
    exact this
  | .nonterm _ :: β, γ, _ :: k₁, k₂, c, .nonterm _ rest, h => by
    have h' : _ ∧ KidsFollow C (β ++ γ) (k₁ ++ k₂) c := h
    refine ⟨?_, kidsFollow_prefix rest h'.2⟩
    have := h'.1
    simpa [CTree.leavesOf_append] using this

/-- Uniqueness for trees of size at most `n`. -/
def TreeU (g : List Rule) (C : Cert) (n : Nat) : Prop :=
  ∀ (X : Nat) (t₁ t₂ : CTree) (tokens m₁ m₂ c₁ c₂ : List Token), t₁.size ≤ n →
    Shape g X t₁ → Shape g X t₂ → Picked t₁ tokens m₁ → Picked t₂ tokens m₂ → Reads c₁ m₁ [] → Reads c₂ m₂ [] →
    (C.followOf X).Mem (C.codes c₁) → (C.followOf X).Mem (C.codes c₂) → t₁ = t₂ ∧ m₁ = m₂

theorem kids_unique {n : Nat} (hT : TreeU g C n) :
    ∀ {rhs : List Sym} {k₁ k₂ : List CTree} {tokens m₁ m₂ c₁ c₂ : List Token}, CTree.kidsSize k₁ ≤ n →
      KidsShape g rhs k₁ → KidsShape g rhs k₂ → PickedKids k₁ tokens m₁ → PickedKids k₂ tokens m₂ →
      Reads c₁ m₁ [] → Reads c₂ m₂ [] → KidsFollow C rhs k₁ c₁ → KidsFollow C rhs k₂ c₂ → k₁ = k₂ ∧ m₁ = m₂
  | _, _, _, _, _, _, _, _, _, .nil, s₂, p₁, p₂, _, _, _, _ => by
    cases s₂; cases p₁; cases p₂; exact ⟨rfl, rfl⟩
  | _, _, _, _, _, _, _, _, size, .term hk₁ rest₁, s₂, p₁, p₂, r₁, r₂, f₁, f₂ => by
    cases s₂ with
    | term hk₂ rest₂ =>
      cases p₁ with
      | cons pl₁ pr₁ =>
        cases p₂ with
        | cons pl₂ pr₂ =>
          cases pl₁ with
          | leaf rl₁ =>
            cases pl₂ with
            | leaf rl₂ =>
              obtain ⟨rfl, rfl⟩ := reads_leaf_unique rl₁ rl₂ (hk₁.trans hk₂.symm)
              have small : CTree.kidsSize _ ≤ n := Nat.le_trans (Nat.le_add_left _ _) size
              obtain ⟨rfl, rfl⟩ := kids_unique hT small rest₁ rest₂ pr₁ pr₂ r₁ r₂ f₁ f₂
              exact ⟨rfl, rfl⟩
  | _, _, _, _, _, _, _, _, size, .nonterm s₁ rest₁, s₂, p₁, p₂, r₁, r₂, f₁, f₂ => by
    cases s₂ with
    | nonterm s₂ rest₂ =>
      cases p₁ with
      | cons pc₁ pr₁ =>
        cases p₂ with
        | cons pc₂ pr₂ =>
          simp only [CTree.kidsSize] at size
          obtain ⟨rfl, rfl⟩ := hT _ _ _ _ _ _ _ _ (by omega) s₁ s₂ pc₁ pc₂
            (pr₁.reads.append r₁) (pr₂.reads.append r₂) f₁.1 f₂.1
          obtain ⟨rfl, rfl⟩ := kids_unique hT (by omega) rest₁ rest₂ pr₁ pr₂ r₁ r₂ f₁.2 f₂.2
          exact ⟨rfl, rfl⟩

/-- Two productions `apart` after their common prefix cannot both read the
tokens. -/
theorem apart_false (ok : certOK g C = true) {n : Nat} (hT : TreeU g C n) {A : Nat} {r₁ r₂ : List Sym}
    {k₁ k₂ : List CTree} {tokens m₁ m₂ c₁ c₂ : List Token}
    (ap : Kinds2.apart (C.lookahead A (commonPrefix r₁ r₂) r₁) (C.lookahead A (commonPrefix r₁ r₂) r₂) = true ∨
      Kinds2.apart (C.lookahead A (commonPrefix r₁ r₂) r₂) (C.lookahead A (commonPrefix r₁ r₂) r₁) = true)
    (size : CTree.kidsSize k₁ ≤ n) (s₁ : KidsShape g r₁ k₁) (s₂ : KidsShape g r₂ k₂)
    (p₁ : PickedKids k₁ tokens m₁) (p₂ : PickedKids k₂ tokens m₂) (rd₁ : Reads c₁ m₁ []) (rd₂ : Reads c₂ m₂ [])
    (f₁ : KidsFollow C r₁ k₁ c₁) (f₂ : KidsFollow C r₂ k₂ c₂) (fa₁ : (C.followOf A).Mem (C.codes c₁))
    (fa₂ : (C.followOf A).Mem (C.codes c₂)) : False := by
  generalize hj : commonPrefix r₁ r₂ = j at ap
  have e₁ : r₁ = r₁.take j ++ r₁.drop j := (List.take_append_drop j r₁).symm
  have e₂ : r₂ = r₁.take j ++ r₂.drop j := by
    rw [← hj, commonPrefix_take, List.take_append_drop]
  rw [e₁] at s₁ f₁
  rw [e₂] at s₂ f₂
  obtain ⟨kβ₁, kγ₁, rfl, sβ₁, sγ₁⟩ := KidsShape.split s₁
  obtain ⟨kβ₂, kγ₂, rfl, sβ₂, sγ₂⟩ := KidsShape.split s₂
  obtain ⟨mid₁, pβ₁, pγ₁⟩ := PickedKids.split p₁
  obtain ⟨mid₂, pβ₂, pγ₂⟩ := PickedKids.split p₂
  rw [CTree.kidsSize_append] at size
  obtain ⟨rfl, rfl⟩ := kids_unique hT (by omega) sβ₁ sβ₂ pβ₁ pβ₂ (pγ₁.reads.append rd₁) (pγ₂.reads.append rd₂)
    (kidsFollow_prefix sβ₁ f₁) (kidsFollow_prefix sβ₂ f₂)
  have m₁ := Kinds2.mem_concat (first_kids ok sγ₁ pγ₁) fa₁
  have m₂ := Kinds2.mem_concat (first_kids ok sγ₂ pγ₂) fa₂
  rw [← codes_append] at m₁ m₂
  have compat := compat_map C.ix (reads_compat (pγ₁.reads.append rd₁) (pγ₂.reads.append rd₂))
  rw [(certOK_codes ok).1, (certOK_codes ok).2, ← codes_eq, ← codes_eq] at compat
  rcases ap with ap | ap
  · exact Kinds2.apart_sound ap m₁ m₂ compat
  · exact Kinds2.apart_sound ap m₂ m₁ (compat_symm compat)

theorem treeU_succ (ok : certOK g C = true) {n : Nat} (hT : TreeU g C n) : TreeU g C (n + 1) := by
  intro X t₁ t₂ tokens m₁ m₂ c₁ c₂ size s₁ s₂ p₁ p₂ rd₁ rd₂ fa₁ fa₂
  cases s₁ with
  | @node q₁ _ prod₁ kids₁ found₁ lhs₁ ks₁ =>
    cases s₂ with
    | @node q₂ _ prod₂ kids₂ found₂ lhs₂ ks₂ =>
      cases p₁ with
      | node hp₁ pk₁ =>
        cases p₂ with
        | node hp₂ pk₂ =>
          simp only [CTree.size] at size
          obtain ⟨-, items₁⟩ := rule_facts ok found₁ hp₁
          obtain ⟨-, items₂⟩ := rule_facts ok found₂ hp₂
          rw [lhs₁] at items₁
          rw [lhs₂] at items₂
          have kf₁ := kidsFollow_of ok items₁ ks₁ pk₁ fa₁
          have kf₂ := kidsFollow_of ok items₂ ks₂ pk₂ fa₂
          by_cases e : q₁ = q₂
          · subst e
            rw [found₁, Option.some.injEq] at found₂
            subst found₂
            obtain ⟨rfl, rfl⟩ := kids_unique hT (by omega) ks₁ ks₂ pk₁ pk₂ rd₁ rd₂ kf₁ kf₂
            exact ⟨rfl, rfl⟩
          · exfalso
            rcases Nat.lt_or_gt_of_ne e with lt | lt
            · have pair := pairsAll_get (pairs_ok ok) found₁ found₂ lt
              simp only [Nat.zero_add, pairOK, picks_ruledOut hp₁, picks_ruledOut hp₂, lhs₁, lhs₂,
                bne_self_eq_false, Bool.false_or] at pair
              cases rule : pickedPair q₁ q₂ with
              | true => exact picks_pair rule hp₁ hp₂
              | false =>
                rw [rule, Bool.false_or] at pair
                exact apart_false ok hT (.inl pair) (by omega) ks₁ ks₂ pk₁ pk₂ rd₁ rd₂ kf₁ kf₂ fa₁ fa₂
            · have pair := pairsAll_get (pairs_ok ok) found₂ found₁ lt
              simp only [Nat.zero_add, pairOK, picks_ruledOut hp₁, picks_ruledOut hp₂, lhs₁, lhs₂,
                bne_self_eq_false, Bool.false_or] at pair
              cases rule : pickedPair q₂ q₁ with
              | true => exact picks_pair rule hp₂ hp₁
              | false =>
                rw [rule, Bool.false_or, commonPrefix_symm] at pair
                exact apart_false ok hT (.inr pair) (by omega) ks₁ ks₂ pk₁ pk₂ rd₁ rd₂ kf₁ kf₂ fa₁ fa₂

theorem treeU_all (ok : certOK g C = true) : ∀ n, TreeU g C n
  | 0 => fun _ t₁ _ _ _ _ _ _ size => absurd size (Nat.not_le_of_gt t₁.size_pos)
  | n + 1 => treeU_succ ok (treeU_all ok n)

/-- At most one tree for `file` is `Picked` for given tokens. -/
theorem parse_unique (ok : certOK g C = true) {t₁ t₂ : CTree} {tokens : List Token}
    (s₁ : Shape g 0 t₁) (p₁ : Picked t₁ tokens []) (s₂ : Shape g 0 t₂) (p₂ : Picked t₂ tokens []) : t₁ = t₂ := by
  have root : (C.followOf 0).Mem (C.codes []) := by
    simp only [certOK, Bool.and_eq_true] at ok
    exact ok.1.1.2
  exact (treeU_all ok t₁.size 0 t₁ t₂ tokens [] [] [] [] (Nat.le_refl _) s₁ s₂ p₁ p₂ .done .done root root).1

end Cert

end Lanius.Mini
