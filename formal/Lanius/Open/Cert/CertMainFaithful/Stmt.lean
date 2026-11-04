import Lanius.Cert.Src
import Lanius.Cert.Shallow
import Lanius.Mini.SourceCorrect

/-! Open statement `CertMainFaithful` (formal/OPEN_STATEMENTS.md). -/

/-- **check_mini's run is `check`'s.** When Core runs check_mini.lani's
`main()` (function 0 of `Lanius.Cert.prog`, the verified front end's program
of it) on standard input `given.input` and it returns the `i32` 0, then
`check` accepts the input's words (`wordsOf`) for some fuel. Why it holds:
`main` reads standard input to its end into a block of `2 ^ 28` bytes (it
returns 2 when the input does not fit), views it as `size / 4` words, and
returns 0 only when `check(words, count, stack).code` is 0; each function of
check_mini.lani is the `Lanius.Cert.Shallow` function of the same name, with
`i32` arithmetic that cannot overflow there (count ≤ 2 ^ 26, so every offset
`check` computes is below 2 ^ 31) and each `while` one fuel step per
iteration. -/
def Lanius.Open.CertMainFaithful : Prop :=
  ∀ (given : Lanius.X86.Machine.Io) (fuel : Nat) (final : Lanius.Semantics.State),
    Lanius.Semantics.evalExpr fuel Lanius.Cert.prog.toCore (Lanius.Mini.startState given) (.call 0 []) =
      .done (.signed .i32 0) final →
    ∃ cfuel, Lanius.Cert.check cfuel (Lanius.Cert.wordsOf given.input) = 0
