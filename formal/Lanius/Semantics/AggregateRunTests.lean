import Lanius.Semantics.StatementProof

namespace Lanius.Semantics.AggregateRunTests

open Lanius.Core
variable {state : State} {program : Program}

example (value : Int) (negative : value < 0) : StableExpr 3 ({} : Program) state
    (.binary .lessEqual (.value (.signed .i32 value)) (.unary .negate (.value (.signed .i32 1))))
    (.boolean true) state := by core_expr

example (value : Int) (negative : value < 0) : True := by
  fail_if_success
    suffices wrong : StableExpr 3 ({} : Program) state
        (.binary .lessEqual (.value (.signed .i32 value)) (.unary .negate (.value (.signed .i32 1))))
        (.boolean false) state by trivial
    solve | core_expr
  trivial

example (found : state.local? 4 = some (.structure 9 [.signed .i32 17, .boolean true])) :
    StableExpr 3 program state (.binary .less (.field (.local 4) 0) (.value (.signed .i32 18)))
      (.boolean true) state := by core_expr

example (found : state.local? 4 = some (.structure 9 [.signed .i32 17, .boolean true])) : True := by
  fail_if_success
    suffices wrong : StableExpr 3 program state (.binary .less (.field (.local 4) 0) (.value (.signed .i32 18)))
        (.boolean false) state by trivial
    solve | core_expr
  trivial

example (first second third : Value) : RunsExpr program state
    (.structValue 9 [.value first, .value second, .value third])
    (.structure 9 [first, second, third]) state := by core_run

private def before : State := ({} : State).bindLocal 2 (.boolean false)
private def after : State := boundLocalAssigned {} 2 (.boolean false) (.boolean true)
private def changed : Expr := .field
  (.structValue 9 [.assign .set (.local 2) (.value (.boolean true)), .local 2]) 1

private theorem mutation : RunsExpr {} before
    (.assign .set (.local 2) (.value (.boolean true))) .unit after :=
  .ofStable (StableExpr.assignSetBool {} before 2 0 (.boolean false) true after
    rfl rfl rfl rfl) rfl

-- A later field observes the earlier mutation. Projection retains the
-- base expression's effects instead of quietly imposing record purity.
example : RunsExpr {} before changed (.boolean true) after := by
  have assigned := mutation
  have found : after.local? 2 = some (.boolean true) := rfl
  core_run

-- Automation must not erase a wrong field result or wrong field order.
example : True := by
  fail_if_success
    have wrong : RunsExpr {} before changed (.boolean false) after := by
      have assigned := mutation
      have found : after.local? 2 = some (.boolean true) := rfl
      core_run
  trivial

example : RunsExpr {} before
    (.field (.structValue 9 [.local 2, .assign .set (.local 2) (.value (.boolean true))]) 0)
    (.boolean false) after := by
  have assigned := mutation
  have found : before.local? 2 = some (.boolean false) := rfl
  core_run

#print axioms RunsExpr.structValue
#print axioms RunsExpr.field

-- Eager binary operands retain order and effects, just like record fields.
example : RunsExpr {} before (.binary .equal changed (.local 2)) (.boolean true) after := by
  have first : RunsExpr {} before changed (.boolean true) after := by
    have assigned := mutation
    have found : after.local? 2 = some (.boolean true) := rfl
    core_run
  have found : after.local? 2 = some (.boolean true) := rfl
  core_run

example : RunsExpr {} before (.binary .equal (.local 2) changed) (.boolean false) after := by
  have second : RunsExpr {} before changed (.boolean true) after := by
    have assigned := mutation
    have found : after.local? 2 = some (.boolean true) := rfl
    core_run
  have found : before.local? 2 = some (.boolean false) := rfl
  core_run

-- A caller supplies the effectful result once; scalar guard composition
-- keeps that post-state and uses the result's mathematical bound.
example (call : Expr) (returned : RunsExpr program start call (.signed .i32 value) finish)
    (nonnegative : 0 ≤ value) :
    RunsExpr program start (.binary .less call (.value (.signed .i32 0)))
      (.boolean false) finish := by core_run

example (call : Expr) (returned : RunsExpr program start call (.signed .i32 (-1)) finish) :
    RunsExpr program start (.binary .less call (.value (.signed .i32 0)))
      (.boolean true) finish := by core_run

example (call : Expr) (returned : RunsExpr program start call (.signed .i32 (-1)) finish) : True := by
  fail_if_success
    have wrong : RunsExpr program start (.binary .less call (.value (.signed .i32 0)))
        (.boolean false) finish := by core_run
  trivial

-- A skipped operand must not be evaluated by the eager composition rule.
example : True := by
  fail_if_success
    have wrong : RunsExpr {} before
        (.binary .logicalOr (.value (.boolean true)) changed) (.boolean true) after := by
      have assigned := mutation
      have found : after.local? 2 = some (.boolean true) := rfl
      core_run
  trivial

end Lanius.Semantics.AggregateRunTests
