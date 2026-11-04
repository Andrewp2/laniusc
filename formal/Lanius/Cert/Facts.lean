import Lanius.Cert.Shallow

/-! # What the checker establishes

`CheckFacts w` lists what `check` verifies of the words `w` when it accepts
them (the open statement `Lanius.Open.CertCheckFacts`), in the terms the
soundness argument uses: words are not negative, a node's arguments are
earlier nodes, rules name nodes, and each step of a theorem is a hypothesis
of it or an instance of an earlier rule whose premises are earlier steps. -/

namespace Lanius.Cert

def nVars (w : Words) (r : Int) : Int := ruleWord w r 1
def ruleEnd (w : Words) (r : Int) : Int := ruleWord w r 5
def stepRule (w : Words) (s : Int) : Int := rd w (oSteps w + 4 * s)
def stepSubst (w : Words) (s : Int) : Int := rd w (oSteps w + 4 * s + 1)
def stepPrems (w : Words) (s : Int) : Int := rd w (oSteps w + 4 * s + 2)
def result (w : Words) (s : Int) : Int := rd w (oSteps w + 4 * s + 3)

/-- Template `t` gives node `x` under the substitution at `pool[so..so+nv)`:
`matchTemplate` says so for some fuel. -/
def Matches (w : Words) (t so nv x : Int) : Prop :=
  ∃ fuel, matchTemplate w (oNodes w) (oCons w) (oPool w) t so nv x fuel = true

/-- Step `s` of theorem `r`, whose steps start at `s0`, is justified: its
result is a node, and it is hypothesis `j` of `r`, or the instance of an
earlier rule under its substitution with each of that rule's hypotheses the
result of an earlier step of `r`. -/
def StepOk (w : Words) (r s0 s : Int) : Prop :=
  0 ≤ result w s ∧ result w s < nNodes w ∧
    ((stepRule w s = VAR ∧ ∃ j : Nat, (j : Int) < nHyps w r ∧ hyp w r j = result w s) ∨
     (0 ≤ stepRule w s ∧ stepRule w s < r ∧
      Matches w (concl w (stepRule w s)) (stepSubst w s) (nVars w (stepRule w s)) (result w s) ∧
      ∀ k : Nat, (k : Int) < nHyps w (stepRule w s) → ∃ p, s0 ≤ p ∧ p < s ∧
        Matches w (hyp w (stepRule w s) k) (stepSubst w s) (nVars w (stepRule w s)) (result w p)))

/-- Node `n`'s arguments are earlier nodes. -/
def Ordered (w : Words) : Prop :=
  ∀ n, 0 ≤ n → n < nNodes w → head w n ≠ VAR → ∀ i : Nat, (i : Int) < arity w (head w n) → arg w n i < n

structure CheckFacts (w : Words) : Prop where
  nonneg : ∀ i, 0 ≤ rd w i
  ordered : Ordered w
  rules : ∀ r, 0 ≤ r → r < nRules w →
    concl w r < nNodes w ∧ ∀ j : Nat, (j : Int) < nHyps w r → hyp w r j < nNodes w
  theorems : ∀ r, 0 ≤ r → r < nRules w → kind w r ≠ 0 →
    ∃ s0, s0 < ruleEnd w r ∧ result w (ruleEnd w r - 1) = concl w r ∧
      ∀ s, s0 ≤ s → s < ruleEnd w r → StepOk w r s0 s

end Lanius.Cert
