/-! # What a certificate means

A certificate (formal/cert/FORMAT.md) is a list of 32-bit words. This file
gives their meaning in a model: a value for every constructor applied to the
values of its arguments, and a formula holds when its value is not 0. A rule
holds in a model when, for every value of its variables, its conclusion
holds whenever its hypotheses do. `natModel` is the 27-axiom theory's
intended model (formal/cert/gen.py: `z` is 0, `b0 x` is 2x, `b1 x` is 2x+1,
`add`, `mul`, and `le` and `eq` as 1 or 0), and `referenceAxioms` are its
axioms, with constructors numbered as gen.py declares them.

Nothing here runs the checker: `Lanius.Cert.Shallow` mirrors check_mini.lani,
and the open statements under `Lanius.Open.Cert` connect the two. -/

namespace Lanius.Cert

/-- The certificate's words: `w[i]` in check_mini.lani is word `i` as an `i32`. -/
abbrev Words := List Int

/-- `w[i]`; 0 outside the words (where check_mini's index traps). -/
def rd (w : Words) (i : Int) : Int := if i < 0 then 0 else w.getD i.toNat 0

/-- A variable node's head word. -/
def VAR : Int := 2147483647

/-- The words of a byte string, four little-endian bytes each as an `i32`
(what `slice_from_raw_parts(input, size / 4)` reads); a last partial word is dropped. -/
def wordsOf (b : List UInt8) : Words :=
  (List.range (b.length / 4)).map fun i =>
    let v : Nat := (b.getD (4 * i) 0).toNat + 256 * (b.getD (4 * i + 1) 0).toNat +
      65536 * (b.getD (4 * i + 2) 0).toNat + 16777216 * (b.getD (4 * i + 3) 0).toNat
    if v < 2 ^ 31 then (v : Int) else (v : Int) - 2 ^ 32

/-! ## The layout: where each table starts (check's `o_*`) -/

def nSorts (w : Words) : Int := rd w 2
def nCons (w : Words) : Int := rd w 3
def nNodes (w : Words) : Int := rd w 4
def nRules (w : Words) : Int := rd w 5
def nSteps (w : Words) : Int := rd w 6
def nPool (w : Words) : Int := rd w 7
def oSorts (_ : Words) : Int := 8
def oCons (w : Words) : Int := oSorts w + nSorts w
def oNodes (w : Words) : Int := oCons w + 3 * nCons w
def oRules (w : Words) : Int := oNodes w + 3 * nNodes w
def oSteps (w : Words) : Int := oRules w + 6 * nRules w
def oPool (w : Words) : Int := oSteps w + 4 * nSteps w

/-- Node `n`'s head: a constructor number, or `VAR`. -/
def head (w : Words) (n : Int) : Int := rd w (oNodes w + 3 * n)
/-- A constructor's arity. -/
def arity (w : Words) (c : Int) : Int := rd w (oCons w + 3 * c + 1)
/-- Argument `i` of node `n` (a node number). -/
def arg (w : Words) (n : Int) (i : Nat) : Int := rd w (oPool w + rd w (oNodes w + 3 * n + 1) + i)
/-- A variable node's variable number. -/
def varIndex (w : Words) (n : Int) : Nat := (rd w (oNodes w + 3 * n + 1)).toNat

/-- Rule `r`'s words: kind (0 axiom, 1 theorem), variables, hypotheses, the
pool offset of its hypothesis list, conclusion node, end of its steps. -/
def ruleWord (w : Words) (r : Int) (k : Int) : Int := rd w (oRules w + 6 * r + k)
def kind (w : Words) (r : Int) : Int := ruleWord w r 0
def nHyps (w : Words) (r : Int) : Int := ruleWord w r 2
def hyp (w : Words) (r : Int) (j : Nat) : Int := rd w (oPool w + ruleWord w r 3 + j)
def concl (w : Words) (r : Int) : Int := ruleWord w r 4

/-! ## Values in a model -/

/-- A model: each constructor's value on its arguments' values. -/
abbrev Model := Nat → List Nat → Nat

/-- Node `n`'s value when variable `k` has value `σ k`. An argument that is
not an earlier node counts as 0 (the checker rejects such nodes, code 33). -/
def den (M : Model) (w : Words) (σ : Nat → Nat) (n : Int) : Nat :=
  if 0 ≤ n then
    if head w n = VAR then σ (varIndex w n)
    else
      M (head w n).toNat ((List.range (arity w (head w n)).toNat).map fun i =>
        let x := arg w n i
        if hx : 0 ≤ x ∧ x < n then den M w σ x else 0)
  else 0
termination_by n.toNat
decreasing_by omega

/-- A formula holds when its value is not 0. -/
def Holds (M : Model) (w : Words) (σ : Nat → Nat) (n : Int) : Prop := den M w σ n ≠ 0

/-- Rule `r` holds in `M`: for every value of its variables, its conclusion
holds when its hypotheses do. -/
def RuleHolds (M : Model) (w : Words) (r : Int) : Prop :=
  ∀ σ : Nat → Nat, (∀ j : Nat, (j : Int) < nHyps w r → Holds M w σ (hyp w r j)) → Holds M w σ (concl w r)

/-- Every axiom (kind 0) of the certificate holds in `M`. -/
def AxiomsHold (M : Model) (w : Words) : Prop :=
  ∀ r : Int, 0 ≤ r → r < nRules w → kind w r = 0 → RuleHolds M w r

/-- Every theorem (every rule not an axiom) of the certificate holds in `M`. -/
def TheoremsHold (M : Model) (w : Words) : Prop :=
  ∀ r : Int, 0 ≤ r → r < nRules w → kind w r ≠ 0 → RuleHolds M w r

/-! ## The theory: gen.py's signature and axioms, and Nat -/

/-- gen.py's constructors in order: `z b0 b1 add mul le eq`. -/
def natModel : Model
  | 0, _ => 0
  | 1, xs => 2 * xs.getD 0 0
  | 2, xs => 2 * xs.getD 0 0 + 1
  | 3, xs => xs.getD 0 0 + xs.getD 1 0
  | 4, xs => xs.getD 0 0 * xs.getD 1 0
  | 5, xs => if xs.getD 0 0 ≤ xs.getD 1 0 then 1 else 0
  | 6, xs => if xs.getD 0 0 = xs.getD 1 0 then 1 else 0
  | _, _ => 0

/-- Terms as trees: a variable, or a constructor on its arguments. -/
inductive Tm where
  | var (k : Nat)
  | app (c : Nat) (args : List Tm)


/-- Node `n` as a tree (the same recursion as `den`). -/
def decode (w : Words) (n : Int) : Tm :=
  if 0 ≤ n then
    if head w n = VAR then .var (varIndex w n)
    else
      .app (head w n).toNat ((List.range (arity w (head w n)).toNat).map fun i =>
        let x := arg w n i
        if hx : 0 ≤ x ∧ x < n then decode w x else .app 0 [])
  else .app 0 []
termination_by n.toNat
decreasing_by omega

/-- A rule's statement as trees: its hypotheses and its conclusion. -/
def statement (w : Words) (r : Int) : List Tm × Tm :=
  ((List.range (nHyps w r).toNat).map fun j => decode w (hyp w r j), decode w (concl w r))

/-- Every axiom of the certificate is one of gen.py's 27 (`referenceAxioms`). -/
def AxiomsAreReference (w : Words) : Prop :=
  ∀ r : Int, 0 ≤ r → r < nRules w → kind w r = 0 → statement w r ∈ referenceAxioms
where
  /-- gen.py's `THEORY`, constructors numbered `z b0 b1 add mul le eq`. -/
  referenceAxioms : List (List Tm × Tm) :=
    let v := Tm.var
    let z := Tm.app 0 []
    let b0 x := Tm.app 1 [x]
    let b1 x := Tm.app 2 [x]
    let add x y := Tm.app 3 [x, y]
    let mul x y := Tm.app 4 [x, y]
    let le x y := Tm.app 5 [x, y]
    let eq x y := Tm.app 6 [x, y]
    let a := v 0
    let b := v 1
    let c := v 2
    let d := v 3
    [([], eq a a),                                                  -- eq_refl
     ([eq a b], eq b a),                                            -- eq_symm
     ([eq a b, eq b c], eq a c),                                    -- eq_trans
     ([eq a b, eq c d], eq (add a c) (add b d)),                    -- cong_add
     ([eq a b, eq c d], eq (mul a c) (mul b d)),                    -- cong_mul
     ([eq a b], eq (b0 a) (b0 b)),                                  -- cong_b0
     ([eq a b], eq (b1 a) (b1 b)),                                  -- cong_b1
     ([le a b, eq b c], le a c),                                    -- le_eq
     ([], le a a),                                                  -- le_refl
     ([le a b, le b c], le a c),                                    -- le_trans
     ([], le a (add a b)),                                          -- le_add_r
     ([le a b, le c d], le (add a c) (add b d)),                    -- add_le_add
     ([le (add a c) (add b c)], le a b),                            -- le_cancel
     ([], eq (add a b) (add b a)),                                  -- add_comm
     ([], eq (add (add a b) c) (add a (add b c))),                  -- add_assoc
     ([], eq (add a z) a),                                          -- add_z
     ([], eq (mul a b) (mul b a)),                                  -- mul_comm
     ([], eq (mul a (mul b c)) (mul (mul a b) c)),                  -- mul_assoc
     ([], eq (mul z a) z),                                          -- mul_z
     ([], eq (mul (b0 a) b) (add (mul a b) (mul a b))),             -- mul_b0 (x a)
     ([], eq (mul (b1 a) b) (add (add (mul a b) (mul a b)) b)),     -- mul_b1 (x a)
     ([], eq (mul a (add b c)) (add (mul a b) (mul a c))),          -- distrib (x a b)
     ([], eq (add (mul a c) (mul b c)) (mul (add a b) c)),          -- rdistrib (x y a)
     ([], eq (add (b0 a) (b0 b)) (b0 (add a b))),                   -- add_b0_b0
     ([], eq (add (b0 a) (b1 b)) (b1 (add a b))),                   -- add_b0_b1
     ([], eq (add (b1 a) (b0 b)) (b1 (add a b))),                   -- add_b1_b0
     ([], eq (add (b1 a) (b1 b)) (b0 (add (add a b) (b1 z))))]      -- add_b1_b1

end Lanius.Cert
