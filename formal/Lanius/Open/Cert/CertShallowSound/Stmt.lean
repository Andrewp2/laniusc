import Lanius.Cert.Shallow

/-! Open statement `CertShallowSound` (formal/OPEN_STATEMENTS.md). -/

/-- **The checker is sound in every model.** When `check` (check_mini.lani's
`check`, as `Lanius.Cert.Shallow` mirrors it) accepts the words `w`, then in
any model in which the certificate's axioms hold, so do its theorems. Why it
holds: every step's result is the instance of its rule's statement under the
step's substitution (`matchTemplate`), and its premises are earlier steps of the
same theorem whose results are the rule's hypotheses under it, or the
theorem's own hypotheses (`VAR` steps); the cited rule is earlier, so by
induction on rules and steps every step's result holds whenever the
theorem's hypotheses do, and the last step is its conclusion (code 58).
Sorts play no part (values in a model are untyped). -/
def Lanius.Open.CertShallowSound : Prop :=
  ∀ (M : Lanius.Cert.Model) (fuel : Nat) (w : Lanius.Cert.Words),
    Lanius.Cert.check fuel w = 0 → Lanius.Cert.AxiomsHold M w → Lanius.Cert.TheoremsHold M w
