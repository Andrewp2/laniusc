module



@[expose] public section

/-! # Linear certificates (F14)

`pre_auto`'s arithmetic goals are almost all `L ≤ R` over a few atoms (heights,
costs), implied by a few hypotheses `Lᵢ ≤ Rᵢ` that its search (`certify` in
`Tactic.lean`) has already found. Such a search succeeds only when
`L + Σ Rᵢ ≤ R + Σ Lᵢ` coefficient by coefficient (the atoms are naturals, so
that sum inequality holds at every value, and with `Lᵢ ≤ Rᵢ` gives `L ≤ R`).
`cert` proves the goal from that check, which the kernel evaluates on short
lists of numerals, in place of an `omega` proof (its preprocessing and its
proof term were most of the precondition modules' time and size).

Terms are reflected as `LTm` over a list of atom values: `LTm.den` unfolds to
the original term, so a hypothesis or goal is used as it stands. -/

namespace Lanius.Faithful.SelfPre.LinCert

/-- A linear term over atoms `0, 1, ..`. -/
inductive LTm where
  | atom (i : Nat)
  | lit (k : Nat)
  | add (a b : LTm)
  | mulL (k : Nat) (a : LTm)
  | mulR (a : LTm) (k : Nat)

/-- Atom `i` of `vs` (`0` past the end). -/
def nth : List Nat → Nat → Nat
  | [], 0 => 0
  | [], _ + 1 => 0
  | v :: _, 0 => v
  | _ :: vs, i + 1 => nth vs i

def LTm.den (vs : List Nat) : LTm → Nat
  | .atom i => nth vs i
  | .lit k => k
  | .add a b => a.den vs + b.den vs
  | .mulL k a => k * a.den vs
  | .mulR a k => a.den vs * k

/-- Coefficients against `1 :: vs`: the constant first, then atom `i` at `i + 1`. -/
def addL : List Nat → List Nat → List Nat
  | [], b => b
  | x :: a, [] => x :: a
  | x :: a, y :: b => (x + y) :: addL a b

def scaleL (k : Nat) : List Nat → List Nat
  | [] => []
  | x :: a => k * x :: scaleL k a

def unitL : Nat → List Nat
  | 0 => [1]
  | i + 1 => 0 :: unitL i

def LTm.lin : LTm → List Nat
  | .atom i => 0 :: unitL i
  | .lit k => [k]
  | .add a b => addL a.lin b.lin
  | .mulL k a => scaleL k a.lin
  | .mulR a k => scaleL k a.lin

def evalA : List Nat → List Nat → Nat
  | [], [] => 0
  | [], _ :: _ => 0
  | _ :: _, [] => 0
  | v :: vs, c :: cs => c * v + evalA vs cs

/-- Coefficient by coefficient at most. -/
def leL : List Nat → List Nat → Bool
  | [], [] => true
  | [], _ :: _ => true
  | x :: a, [] => x == 0 && leL a []
  | x :: a, y :: b => Nat.ble x y && leL a b

def sumL : List (List Nat) → List Nat
  | [] => []
  | a :: t => addL a (sumL t)

theorem evalA_nil (vs : List Nat) : evalA vs [] = 0 := by cases vs <;> rfl

theorem evalA_addL : ∀ (vs a b : List Nat), evalA vs (addL a b) = evalA vs a + evalA vs b
  | [], [], [] => rfl
  | [], [], _ :: _ => by simp [addL, evalA]
  | [], _ :: _, [] => by simp [addL, evalA]
  | [], _ :: _, _ :: _ => by simp [addL, evalA]
  | _ :: _, [], [] => rfl
  | _ :: _, [], _ :: _ => by simp [addL, evalA]
  | _ :: _, _ :: _, [] => by simp [addL, evalA]
  | v :: vs, x :: a, y :: b => by
    simp only [addL, evalA, evalA_addL vs a b, Nat.add_mul]
    omega

theorem evalA_scaleL (k : Nat) : ∀ (vs a : List Nat), evalA vs (scaleL k a) = k * evalA vs a
  | [], [] => rfl
  | [], _ :: _ => by simp [scaleL, evalA]
  | _ :: _, [] => by simp [scaleL, evalA]
  | v :: vs, x :: a => by
    simp only [scaleL, evalA, evalA_scaleL k vs a, Nat.mul_add, Nat.mul_assoc]

theorem evalA_unitL : ∀ (vs : List Nat) (i : Nat), evalA vs (unitL i) = nth vs i
  | [], 0 => rfl
  | [], _ + 1 => by simp [unitL, evalA, nth]
  | v :: vs, 0 => by simp [unitL, evalA, nth, evalA_nil]
  | v :: vs, i + 1 => by simp [unitL, evalA, nth, evalA_unitL vs i]

theorem lin_den (vs : List Nat) : ∀ (e : LTm), evalA (1 :: vs) e.lin = e.den vs
  | .atom i => by simp [LTm.lin, LTm.den, evalA, evalA_unitL]
  | .lit k => by simp [LTm.lin, LTm.den, evalA, evalA_nil]
  | .add a b => by simp only [LTm.lin, LTm.den, evalA_addL, lin_den vs a, lin_den vs b]
  | .mulL k a => by simp only [LTm.lin, LTm.den, evalA_scaleL, lin_den vs a]
  | .mulR a k => by simp only [LTm.lin, LTm.den, evalA_scaleL, lin_den vs a, Nat.mul_comm]

theorem evalA_le : ∀ (vs a b : List Nat), leL a b = true → evalA vs a ≤ evalA vs b
  | [], [], [], _ => Nat.le_refl _
  | [], [], _ :: _, _ => by simp [evalA]
  | [], _ :: _, [], _ => by simp [evalA]
  | [], _ :: _, _ :: _, _ => by simp [evalA]
  | _ :: _, [], [], _ => Nat.le_refl _
  | _ :: _, [], _ :: _, _ => by simp [evalA]
  | v :: vs, x :: a, [], h => by
    simp only [leL, Bool.and_eq_true, beq_iff_eq] at h
    have := evalA_le vs a [] h.2
    have e : evalA vs [] = 0 := by cases vs <;> rfl
    simp only [evalA, h.1, Nat.zero_mul, Nat.zero_add]
    omega
  | v :: vs, x :: a, y :: b, h => by
    simp only [leL, Bool.and_eq_true, Nat.ble_eq] at h
    have := evalA_le vs a b h.2
    simp only [evalA]
    have := Nat.mul_le_mul_right v h.1
    omega

/-- The hypotheses `Lᵢ ≤ Rᵢ` hold at `vs`. -/
def AllLe (vs : List Nat) : List (LTm × LTm) → Prop
  | [] => True
  | p :: t => p.1.den vs ≤ p.2.den vs ∧ AllLe vs t

def sideSum (vs : List Nat) (side : LTm × LTm → LTm) : List (LTm × LTm) → Nat
  | [] => 0
  | p :: t => (side p).den vs + sideSum vs side t

theorem evalA_sumL (vs : List Nat) (side : LTm × LTm → LTm) : ∀ (hs : List (LTm × LTm)),
    evalA (1 :: vs) (sumL (hs.map fun p => (side p).lin)) = sideSum vs side hs
  | [] => by cases vs <;> rfl
  | p :: t => by
    simp only [List.map_cons, sumL, evalA_addL, lin_den, evalA_sumL vs side t, sideSum]

theorem sideSum_le (vs : List Nat) : ∀ (hs : List (LTm × LTm)), AllLe vs hs →
    sideSum vs (·.1) hs ≤ sideSum vs (·.2) hs
  | [], _ => Nat.le_refl _
  | p :: t, ⟨h, ht⟩ => by
    have := sideSum_le vs t ht
    simp only [sideSum]
    omega

/-- **`L ≤ R` from hypotheses `Lᵢ ≤ Rᵢ`** when `L + Σ Rᵢ ≤ R + Σ Lᵢ` coefficient by
coefficient. -/
theorem cert (vs : List Nat) (hs : List (LTm × LTm)) (l r : LTm) (hh : AllLe vs hs)
    (hc : leL (addL l.lin (sumL (hs.map fun p => p.2.lin))) (addL r.lin (sumL (hs.map fun p => p.1.lin))) = true) :
    l.den vs ≤ r.den vs := by
  have h := evalA_le (1 :: vs) _ _ hc
  simp only [evalA_addL, lin_den, evalA_sumL] at h
  have := sideSum_le vs hs hh
  have e1 : sideSum vs (fun x => x.fst) hs = sideSum vs Prod.fst hs := rfl
  have e2 : sideSum vs (fun x => x.snd) hs = sideSum vs Prod.snd hs := rfl
  omega

/-! A truncated subtraction `a - c` is an atom of its own, with these facts. -/

theorem sub_le' (a c : Nat) : a - c ≤ a := Nat.sub_le a c

theorem le_sub_add' (a c : Nat) : a ≤ a - c + c := by omega

theorem sub_add_le_of_le (a c : Nat) (h : c ≤ a) : a - c + c ≤ a := by omega

theorem sub_add_le_of_lt (a c : Nat) (h : c < a) : a - c + c ≤ a := by omega

end Lanius.Faithful.SelfPre.LinCert
