import Lanius.Cert.Facts

/-! Open statement `CertCheckFacts` (formal/OPEN_STATEMENTS.md). -/

/-- **What an accepting `check` has verified.** When `check fuel w` is 0,
`CheckFacts w` holds: every word is at least 0 (code 11), a node's arguments
are earlier nodes (33), each rule's conclusion and hypotheses are nodes (40,
42), and a rule other than an axiom is a theorem (44) whose steps, from the
end of the previous theorem's to its own end, are each a hypothesis of it
(51) or an instance of an earlier rule (52, 55) whose premises are earlier
steps of the same theorem (56, 57), and whose last step's result is its
conclusion (58). Why it holds: each loop of `check` returns 0 only when the
check it makes passes at every index (induction on each loop's fuel). -/
def Lanius.Open.CertCheckFacts : Prop :=
  ∀ (fuel : Nat) (w : Lanius.Cert.Words), Lanius.Cert.check fuel w = 0 → Lanius.Cert.CheckFacts w
