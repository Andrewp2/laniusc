import Lanius.Cert.Model

/-! Open statement `CertReferenceAxiomsHold` (formal/OPEN_STATEMENTS.md). -/

/-- **gen.py's 27 axioms hold of Nat.** A certificate whose every axiom is
one of `AxiomsAreReference.referenceAxioms` (gen.py's `THEORY`, constructors
numbered `z b0 b1 add mul le eq`) has every axiom true in `natModel`
(`z` = 0, `b0 x` = 2x, `b1 x` = 2x+1, `add`, `mul`, and `le`, `eq` as 1 or 0).
Why it holds: a node's value is its tree's value (`den` and `decode` recur
alike), and each of the 27 is a fact about Nat (formal/cert/theory_lean.py
proves them with omega and the ring laws). -/
def Lanius.Open.CertReferenceAxiomsHold : Prop :=
  ∀ w : Lanius.Cert.Words, Lanius.Cert.AxiomsAreReference w → Lanius.Cert.AxiomsHold Lanius.Cert.natModel w
