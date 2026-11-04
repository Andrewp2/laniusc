import Lanius.Cert.Src
import Lanius.Cert.Model
import Lanius.Mini.SourceCorrect

/-! Open statement `CertNatSound` (formal/OPEN_STATEMENTS.md), the root of
the certificate checker's soundness. -/

/-- **What check_mini's acceptance means.** When Core runs check_mini.lani's
`main()` on standard input `given.input` and it returns the `i32` 0 (so the
executable `Lanius.Cert.checkMini_process` describes exits with 0), and every
axiom of the certificate is one of gen.py's 27, then every theorem of the
certificate holds in Nat: for all values of its variables, its conclusion
holds when its hypotheses do. These theorems are the arithmetic obligations
gen.py proved (formal/cert/FORMAT.md). Why it holds: `CertMainFaithful`,
`CertShallowSound` and `CertReferenceAxiomsHold` (`red1`). -/
def Lanius.Open.CertNatSound : Prop :=
  ∀ (given : Lanius.X86.Machine.Io) (fuel : Nat) (final : Lanius.Semantics.State),
    Lanius.Semantics.evalExpr fuel Lanius.Cert.prog.toCore (Lanius.Mini.startState given) (.call 0 []) =
      .done (.signed .i32 0) final →
    Lanius.Cert.AxiomsAreReference (Lanius.Cert.wordsOf given.input) →
    Lanius.Cert.TheoremsHold Lanius.Cert.natModel (Lanius.Cert.wordsOf given.input)
