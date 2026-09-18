import Lanius.Core.Equality.Lawful
import Lean.Elab.Term
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Equality

open Core

private def nested : Expr :=
  .matchValue (.local 1) [
    (.enumVariant 3 4 [.bind 2], .value (.array [.signed .i32 5])),
    (.wildcard, .assign .set (.index (.field (.local 8) 2) (.local 9))
      (.value (.f32Bits 2143289345)))]

private def program (stop : Option Expr) : Program := {
  functions := [{
    id := 0
    parameters := [(1, .scalar (.signed .i32))]
    returnType := .unit
    body := some (.forRange 2 (.value (.signed .i32 0)) stop false
      (.expression nested))
  }]
}

/- These checks require actual kernel computation, not only rewriting by
lawfulness. They exercise the original opaque-equality failure, including
match-arm lists, nested places, optional statements, and float bit identity. -/
private def cases : List Bool := [
  nested == nested,
  !(nested == .local 1),
  !((.f32Bits 0 : Value) == .f32Bits 2147483648),
  (.f32Bits 2143289345 : Value) == .f32Bits 2143289345,
  !((.f32Bits 2143289345 : Value) == .f32Bits 2143289346),
  !((.f64Bits 0 : Value) == .f64Bits 9223372036854775808),
  !((.array [.boolean true] : Value) == .array []),
  !((.array [.boolean true, .boolean false] : Value) ==
    .array [.boolean false, .boolean true]),
  !((.enumVariant 1 2 [.bind 3] : Pattern) == .enumVariant 1 2 [.bind 4]),
  program none == program none,
  !(program none == program (some (.local 3))),
  !(program (some (.local 3)) == program (some (.local 4)))
]

private theorem cases_pass : cases.all id = true := by decide +kernel

#eval show IO Unit from do
  unless cases.all id do
    throw (IO.userError "Core structural equality disagrees with its kernel-checked cases")
  IO.println "12 Core equality cases agree under kernel and native evaluation."

example (a b : Expr) : (a == b) = true ↔ a = b := beq_iff_eq
example (a b : Program) : (a == b) = true ↔ a = b := beq_iff_eq

run_elab do
  for name in #[``Value.beq, ``Pattern.beq, ``Expr.beq, ``Place.beq,
      ``Value.beq_eq_true, ``Pattern.beq_eq_true, ``Expr.beq_eq_true,
      ``Place.beq_eq_true, ``Core.instLawfulBEqStmt,
      ``Core.instLawfulBEqFunction, ``Core.instLawfulBEqProgram,
      ``cases_pass] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Core equality {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Total Core equality and its all-input correctness proofs use only standard Lean axioms."

end Lanius.Extraction.Tests.Equality
