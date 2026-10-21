import Lanius.Semantics.ScalarAssignment
import Lanius.Semantics.ExpressionProof

namespace Lanius.Semantics

open Lanius.Core

-- The RHS is computed from the existing local, not an injected result literal.
theorem computedQuotient (formed : state.CellsWellFormed) (value : Nat) (fits : value < 2 ^ 31) :
    ∃ after, RunsExpr program (state.bindLocal 17 (.signed .i32 value))
        (.assign .set (.local 17) (.binary .divide (.local 17) (.value (.signed .i32 10)))) .unit after ∧
      after.local? 17 = some (.signed .i32 (value / 10 : Nat)) ∧ CallerFrame state after := by
  obtain ⟨after, run, assigned, _⟩ := RunsExpr.assignI32
    (program := program) (op := .set)
    (State.bindLocal_cellId state 17 (.signed .i32 value)) (formed.bindLocal_local 17 (.signed .i32 value))
    (.ofStable (by core_expr : StableExpr 2 program (state.bindLocal 17 (.signed .i32 value))
      (.binary .divide (.local 17) (.value (.signed .i32 10))) (.signed .i32 (value / 10 : Nat)) _) rfl) rfl
  exact ⟨after, run, assignLocal_finds_assigned _ _ _ (State.bindLocal_cellId state 17 _) assigned,
    ((CallerFrame.refl formed).bindLocal 17 _).assignLocalFresh 17 state.nextCell _
      (State.bindLocal_cellId state 17 _) (Nat.le_refl _) assigned⟩

-- An invented operation result cannot certify the computed RHS.
example : True := by
  fail_if_success
    have wrong : evalAssignValue Lanius.Target.x86_64 .subtract (some (.signed .i32 10))
        (.signed .i32 1) = .ok (.signed .i32 8) := by decide
  trivial

#print axioms computedQuotient

end Lanius.Semantics
