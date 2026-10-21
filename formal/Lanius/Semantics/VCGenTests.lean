import Lanius.Semantics.VCGen

namespace Lanius.Semantics.CoreVCGen

open Lanius Lanius.Core Lean.Order Std.Internal.Do

section
variable (program : Program)

theorem sequence_consumer (first second : Stmt) (P R : State → Prop)
    (Q : Completion → State → Prop)
    (head : coreTriple program first P (fun completion state => completion = .next ∧ R state))
    (tail : coreTriple program second R Q) {before : State} (input : P before) :
    ∃ completion after, RunsStmt program before (.sequence first second) completion after ∧
      Q completion after := by
  letI := coreWP program
  apply coreTriple_sound program (P := P) ?_ input
  vcgen [head, tail]
  rename_i completion state post
  rcases post with ⟨rfl, retained⟩
  exact tail.le_wp state retained

theorem earlyReturn_consumer (argument : Expr) (suffix : Stmt) (P : State → Prop)
    (Q : Completion → State → Prop)
    (argumentRun : ∀ before, P before → ∃ value after,
      RunsExpr program before argument value after ∧ Q (.returned (some value)) after)
    {before : State} (input : P before) :
    ∃ completion after,
      RunsStmt program before (.sequence (.returnValue (some argument)) suffix) completion after ∧
      Q completion after := by
  letI := coreWP program
  apply coreTriple_sound program (P := P) ?_ input
  vcgen
  rename_i state accepted
  exact argumentRun state accepted

private def start : State := ({} : State).bindLocal 99 (.signed .i32 0)
private def write : Expr := .assign .set (.local 99) (.value (.signed .i32 1))
private def written : State := (start.assignLocal 99 (.signed .i32 1)).getD start
private def scopeState : State := (written.bindLocal 10 .unit).bindLocal 11 .unit
private def guarded : State := (scopeState.assignLocal 99 (.signed .i32 2)).getD scopeState

theorem nested_scope_consumer (suffix : Stmt) :
    ∃ completion after, RunsStmt program start
      (.letLocal 10 .unit write (.letLocal 11 .unit (.value .unit)
        (.ifThenElse (.binary .equal (.assign .add (.local 99) (.value (.signed .i32 1))) (.value .unit))
          (.sequence (.returnValue (some (.local 99))) suffix) .skip))) completion after ∧
      completion = .returned (some (.signed .i32 2)) ∧ after.locals = start.locals ∧
      after.local? 99 = some (.signed .i32 2) := by
  letI := coreWP program
  apply coreTriple_sound program (P := fun state => state = start) ?_ rfl
  vcgen
  rename_i state same
  subst state
  refine ⟨.unit, written, RunsExpr.ofEval (fuel := 5) (by rfl), ?_⟩
  vcgen
  refine ⟨.unit, _, RunsExpr.ofStable .value rfl, ?_⟩
  vcgen
  refine ⟨true, guarded, RunsExpr.ofEval (fuel := 5) (by rfl), ?_⟩
  vcgen
  all_goals try contradiction
  exact ⟨.signed .i32 2, guarded, RunsExpr.ofEval (fuel := 2) (by rfl), rfl, rfl, rfl⟩

theorem expression_state_consumer :
    ∃ completion after, RunsStmt program start (.expression write) completion after ∧
      completion = .next ∧ after.locals = start.locals ∧ after.local? 99 = some (.signed .i32 1) := by
  letI := coreWP program
  apply coreTriple_sound program (P := fun state => state = start) ?_ rfl
  vcgen
  rename_i state same
  subst state
  exact ⟨.unit, written, RunsExpr.ofEval (fuel := 5) (by rfl), rfl, rfl, rfl⟩

#print axioms core_letLocal
#print axioms core_ifThenElse
#print axioms core_expression
#print axioms nested_scope_consumer
#print axioms expression_state_consumer

#print axioms coreWP
#print axioms coreTriple_sound
#print axioms coreTriple_exec
#print axioms core_skip
#print axioms core_sequence
#print axioms core_returnValue
#print axioms sequence_consumer
#print axioms earlyReturn_consumer

end
end Lanius.Semantics.CoreVCGen
