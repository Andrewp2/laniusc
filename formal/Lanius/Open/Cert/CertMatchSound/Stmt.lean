import Lanius.Cert.Facts

/-! Open statement `CertMatchSound` (formal/OPEN_STATEMENTS.md). -/

/-- **A match is a substitution instance.** When `matchTemplate` says
template node `t` gives node `x` under the substitution at
`pool[so..so+nv)`, in words whose nodes' arguments are earlier nodes, `x`'s
value under any `σ` is `t`'s value when each variable `k` of `t` has the
value of the substitution's node `k`. Why it holds: an invariant of
`matchLoop`'s stack, by induction on its fuel: every pair still on it has
that property once the loop returns true (a variable's pair by its
substitution entry, a constructor's by its heads and its arguments' pairs). -/
def Lanius.Open.CertMatchSound : Prop :=
  ∀ (M : Lanius.Cert.Model) (σ : Nat → Nat) (w : Lanius.Cert.Words) (t so nv x : Int),
    (∀ i, 0 ≤ Lanius.Cert.rd w i) → Lanius.Cert.Ordered w →
    0 ≤ t → t < Lanius.Cert.nNodes w → 0 ≤ x → x < Lanius.Cert.nNodes w →
    Lanius.Cert.Matches w t so nv x →
    Lanius.Cert.den M w σ x =
      Lanius.Cert.den M w (fun k => Lanius.Cert.den M w σ (Lanius.Cert.rd w (Lanius.Cert.oPool w + so + k))) t
