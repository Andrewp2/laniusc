import Lanius.Semantics.StmtList

namespace Lanius.Semantics.LexicalFrameTests

open Lanius.Core

private def program : Program := {}
private def caller : State := ({} : State).bindLocal 7 (.signed .i32 3)
private def changed : State := { caller with cells := replaceCell caller.cells 0 (.signed .i32 9) }

-- Equal lexical bindings do not imply equal local values.
example : RunsExpr program caller
    (.assign .set (.local 7) (.value (.signed .i32 9))) .unit changed :=
  .ofEval (fuel := 2) rfl
example : caller.local? 7 = some (.signed .i32 3) := rfl
example : changed.local? 7 = some (.signed .i32 9) := rfl
example : changed.locals = caller.locals := rfl

private def shadowed : State := restoreLocals caller (caller.bindLocal 7 (.boolean true))

-- Shadowing disappears on return, while the allocated cell survives.
example : RunsStmt program caller
    (.letLocal 7 (.scalar .bool) (.value (.boolean true)) (.returnValue (some (.local 7))))
    (.returned (some (.boolean true))) shadowed :=
  .ofExec (fuel := 3) rfl
example : shadowed.local? 7 = some (.signed .i32 3) := rfl
example : shadowed.cell? 1 = some (.boolean true) := rfl
example : RunsExpr program caller
    (.matchValue (.value (.boolean true)) [(.bind 7, .local 7)]) (.boolean true) shadowed :=
  .ofEval (fuel := 3) rfl

-- Traps restore the same scope, without rolling back retained storage.
example : execStmt 4 program caller
    (.letLocal 7 (.scalar .bool) (.value (.boolean true))
      (.expression (.intrinsic .assert (.value (.boolean false))))) =
    .trapped .assertionFailed shadowed := rfl

example (run : execStmt fuel program caller statement = .trapped reason after) :
    after.locals = caller.locals := by
  simpa only [run, Outcome.PreservesLocals] using
    (execStmt_preservesLocals (fuel := fuel) (program := program) (state := caller) (statement := statement))

private def uninitialized : State := restoreLocals caller (caller.bindUninitialized 7)
example : RunsStmt program caller (.letUninitialized 7 .unit .breakLoop) .breakLoop uninitialized :=
  .ofExec (fuel := 2) rfl
example : RunsStmt program caller (.letUninitialized 7 .unit .continueLoop) .continueLoop uninitialized :=
  .ofExec (fuel := 2) rfl
example : execStmt 2 program caller (.letUninitialized 7 .unit (.expression (.local 7))) =
    .outOfFuel := rfl
example : execStmt 3 program caller (.letUninitialized 7 .unit (.expression (.local 7))) =
    .trapped .uninitializedLocal uninitialized := rfl

private def loopAfter : State := restoreLocals caller (caller.bindLocal 7 (.boolean false))
example : execForValues 2 program caller 7 [.boolean false, .boolean true] .breakLoop =
    .done .next loopAfter := rfl

-- Returning a reference must retain its cell, despite removing its name.
private def referenced : State := restoreLocals caller (caller.bindLocal 8 (.boolean true))
example : RunsStmt program caller
    (.letLocal 8 (.scalar .bool) (.value (.boolean true))
      (.returnValue (some (.borrow (.scalar .bool) (.local 8)))))
    (.returned (some (.reference (.scalar .bool) 1 []))) referenced :=
  .ofExec (fuel := 4) rfl
example : referenced.local? 8 = none := rfl
example : referenced.cell? 1 = some (.boolean true) := rfl

private def exitProgram : Program := { functions := [
  { id := 9, parameters := [(1, .scalar (.signed .i32))], returnType := .unit,
    body := none, external := some (.host .exit) },
  { id := 10, parameters := [], returnType := .unit,
    body := some (.letLocal 7 (.scalar .bool) (.value (.boolean false))
      (.expression (.call 9 [.value (.signed .i32 17)]))) }] }
private def exitAfter : State := {
  restoreLocals caller (({ caller with locals := [] }).bindLocal 7 (.boolean false)) with
  world := Lanius.World.record caller.world .exit }

example : evalExpr 6 exitProgram caller (.call 10 []) = .exited 17 exitAfter := rfl
example : exitAfter.locals = caller.locals := rfl
example : exitAfter.cell? 1 = some (.boolean false) := rfl

-- No well-formedness premise excludes broken initial bindings.
private def malformed : State := { locals := [(5, 99)] }
example : evalExpr 1 program malformed (.local 5) = .trapped .typeMismatch malformed := rfl

example (run : Evaluates program caller expression value after) :
    RunsExpr program caller expression value after := run.runs
example (run : Executes program caller statement completion after) :
    RunsStmt program caller statement completion after := run.runs

#print axioms evalExpr_preservesLocals
#print axioms execStmt_preservesLocals
#print axioms RunsExpr.ofEval
#print axioms RunsStmt.ofExec

end Lanius.Semantics.LexicalFrameTests
