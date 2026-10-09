import Lanius.Semantics.StmtList

namespace Lanius.Semantics.FuelTests

open Lanius.Core

private def program : Program := {}
private def initial : State := {}
private def introduced : State := initial.bindLocal 8 .unit
private def unbound : State := restoreLocals initial introduced

-- More fuel does not execute a short-circuited, trapping right operand.
example (program : Program) (state : State) (enough : 2 ≤ fuel) :
    evalExpr fuel program state
      (.binary .logicalOr (.value (.boolean true)) (.intrinsic .assert (.value (.boolean false)))) =
      .done (.boolean true) state :=
  evalExpr_of_le (low := 2) rfl (by intro h; cases h) enough

-- Traps are stable observations, not incomplete executions.
example (program : Program) (state : State) (enough : 2 ≤ fuel) :
    evalExpr fuel program state (.intrinsic .assert (.value (.boolean false))) =
      .trapped .assertionFailed state :=
  evalExpr_of_le (low := 2) rfl (by intro h; cases h) enough

-- The observed state includes host output; stability must not repeat effects.
example (program : Program) (state : State) (enough : 2 ≤ fuel) :
    evalExpr fuel program state (.intrinsic .printI32 (.value (.signed .i32 7))) =
      .done .unit { state with world := state.world.afterPrintI32 7 } :=
  evalExpr_of_le (low := 2) rfl (by intro h; cases h) enough

example (enough : 3 ≤ fuel) :
    evalExprs fuel program initial [.value .unit, .value (.boolean true)] =
      .done [.unit, .boolean true] initial :=
  (evalExprs_refines (low := 3) enough).completed (by intro h; cases h)

example (enough : 2 ≤ fuel) :
    evalMatchArms fuel program initial .unit [(.bind 8, .local 8)] = .done .unit unbound :=
  (evalMatchArms_refines (low := 2) enough).completed (by intro h; cases h)

example (enough : 1 ≤ fuel) :
    evalPlace fuel program introduced .read (.local 8) =
      .done { root := 0, projections := [], value := some .unit } introduced :=
  (evalPlace_refines (low := 1) enough).completed (by intro h; cases h)

example (enough : 2 ≤ fuel) :
    execForValues fuel program initial 8 [.unit] .skip = .done .next unbound :=
  (execForValues_refines (low := 2) enough).completed (by intro h; cases h)

private def ranged : State := restoreLocals initial (initial.bindLocal 8 (.signed .i32 0))
example (enough : 2 ≤ fuel) :
    execForRange fuel program initial 8 0 (some 1) false .skip = .done .next ranged :=
  (execForRange_refines (low := 2) enough).completed (by intro h; cases h)

-- A single finite witness becomes the real scoped execution contract. Fresh
-- cells survive, while the lexical binding disappears as before.
example : RunsStmt program initial
    (.letLocal 8 .unit (.value .unit) (.returnValue (some (.local 8))))
    (.returned (some .unit)) unbound :=
  RunsStmt.ofExec (fuel := 3) rfl

private def recursive : Program := { functions := [{
  id := 7, parameters := [(1, .scalar .bool)], returnType := .unit,
  body := some (.ifThenElse (.local 1)
    (.returnValue (some (.call 7 [.value (.boolean false)]))) (.returnValue (some (.value .unit)))) }] }
private def completed : State := {
  cells := [{ id := 0, value := some (.boolean true) }, { id := 1, value := some (.boolean false) }]
  nextCell := 2 }

example (enough : 7 ≤ fuel) :
    evalExpr fuel recursive initial (.call 7 [.value (.boolean true)]) = .done .unit completed :=
  evalExpr_of_le (low := 7) rfl (by intro h; cases h) enough

private def exitProgram : Program := { functions := [{
  id := 9, parameters := [(1, .scalar (.signed .i32))], returnType := .unit,
  body := none, external := some (.host .exit) }] }
private def exited : State := { initial with world := Lanius.World.record initial.world .exit }

example (enough : 3 ≤ fuel) :
    evalExpr fuel exitProgram initial (.call 9 [.value (.signed .i32 17)]) = .exited 17 exited :=
  evalExpr_of_le (low := 3) rfl (by intro h; cases h) enough

-- Exhaustion cannot be used as a completed seed; increasing fuel can finish.
example : evalExpr 0 program initial (.value .unit) = .outOfFuel := rfl
example : evalExpr 1 program initial (.value .unit) = .done .unit initial := rfl
example : evalExpr 0 program initial (.value .unit) ≠ evalExpr 1 program initial (.value .unit) := by
  intro h
  cases h

example (one : Evaluates program initial expression value after)
    (two : Evaluates program initial expression other final) : value = other ∧ after = final := one.unique two

example (run : Evaluates program initial expression value after) :
    ¬ Traps program initial expression reason final := run.not_traps

#print axioms evalExpr_unique
#print axioms StableExpr.ofEval
#print axioms RunsStmt.ofExec

end Lanius.Semantics.FuelTests
