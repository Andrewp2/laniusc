import Lanius.Semantics.PureProof

namespace Lanius.Semantics

open Lanius.Core

private def someValue (value : Int) : Expr := .enumValue 7 1 [.value (.signed .i32 value)]
private def choiceArms : List (Pattern × Expr) :=
  [(.enumVariant 7 0 [], .value (.signed .i32 0)),
   (.enumVariant 7 1 [.bind 17], .local 17)]

private def enumType : TypeId := 40 + 2
example : evalBinaryValue Target.x86_64 .equal (.enumeration enumType 0 []) (.enumeration 42 1 []) =
    .ok (.boolean false) := by core_scalar
example : True := by
  fail_if_success
    suffices wrong : evalBinaryValue Target.x86_64 .equal (.enumeration enumType 0 []) (.enumeration 42 1 []) =
        .ok (.boolean true) by trivial
    solve | core_scalar
  trivial

-- A symbolic payload is bound and returned; the caller's cell is not replaced.
theorem choiceReturns (program : Program) (state : State) (formed : state.CellsWellFormed) (value : Int) :
    ∃ after, RunsExpr program state (.matchValue (someValue value) choiceArms) (.signed .i32 value) after ∧
      PureFrame state after := by core_pure_expr

example (value : Int) : ∃ after, RunsExpr {} (({} : State).bindLocal 17 (.signed .i32 91))
    (.matchValue (someValue value) choiceArms) (.signed .i32 value) after ∧
    after.local? 17 = some (.signed .i32 91) := by
  obtain ⟨after, run, frame⟩ := choiceReturns {} (({} : State).bindLocal 17 (.signed .i32 91))
    (by simp [State.CellsWellFormed, State.bindLocal, State.bindCell]) value
  exact ⟨after, run, frame.localFound (by apply State.bindLocal_local?; simp [State.CellsWellFormed])⟩

-- Arm order is semantic: the first wildcard wins, and the trapping tail is skipped.
example (program : Program) (state : State) (formed : state.CellsWellFormed) (value : Int) :
    ∃ after, RunsExpr program state
      (.matchValue (someValue value)
        [(.wildcard, .value (.signed .i32 5)),
         (.enumVariant 7 1 [.bind 17], .binary .divide (.local 17) (.value (.signed .i32 0)))])
      (.signed .i32 5) after ∧ PureFrame state after := by core_pure_expr

example (program : Program) (state : State) (formed : state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr program state (.matchValue (someValue 7) choiceArms)
        (.signed .i32 8) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  fail_if_success
    suffices wrong : ∃ after, RunsExpr program state
        (.matchValue (.enumValue 8 1 [.value (.signed .i32 7)]) choiceArms)
        (.signed .i32 7) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  fail_if_success
    suffices wrong : ∃ after, RunsExpr program state
        (.matchValue (.enumValue 7 1 []) choiceArms)
        (.signed .i32 7) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  fail_if_success
    suffices wrong : ∃ after, RunsExpr program state
        (.matchValue (someValue 7) [(.wildcard, .value (.signed .i32 5))])
        (.signed .i32 7) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  trivial

private def before : State := ({} : State).bindLocal 2 (.boolean false)
private def after : State := boundLocalAssigned {} 2 (.boolean false) (.boolean true)
private def effectful : Expr := .field
  (.structValue 9 [.assign .set (.local 2) (.value (.boolean true)), .enumValue 7 1 []]) 1

-- General matching retains scrutinee effects before selecting the arm.
example : RunsExpr {} before (.matchValue effectful [(.wildcard, .local 2)]) (.boolean true) after := by
  have assigned : RunsExpr {} before (.assign .set (.local 2) (.value (.boolean true))) .unit after :=
    .ofStable (StableExpr.assignSetBool {} before 2 0 (.boolean false) true after rfl rfl rfl rfl) rfl
  have found : after.local? 2 = some (.boolean true) := rfl
  have source : RunsExpr {} before effectful (.enumeration 7 1 []) after := by core_run
  have bound : (after.bindLocals []).local? 2 = some (.boolean true) := rfl
  have branch : RunsExpr {} (after.bindLocals []) (.local 2) (.boolean true)
      (after.bindLocals []) := by core_run
  exact RunsExpr.matchValue (arms := [(.wildcard, .local 2)]) (bindings := []) (body := .local 2)
    source rfl branch

#print axioms RunsExpr.matchValue
#print axioms RunsExpr.matchPure

private def nestedConstructor (value : Int) : Expr :=
  .enumValue 8 1 [.matchValue (someValue value) choiceArms]
private def outerArms : List (Pattern × Expr) :=
  [(.enumVariant 8 1 [.bind 18], .local 18), (.wildcard, .value (.signed .i32 0))]

-- The payload match allocates binding cells; neither constructor nor outer
-- match may pretend the intermediate state is exactly the original state.
theorem nestedConstructorReturns (program : Program) (state : State)
    (formed : state.CellsWellFormed) (value : Int) :
    ∃ after, RunsExpr program state (nestedConstructor value)
      (.enumeration 8 1 [.signed .i32 value]) after ∧ PureFrame state after := by core_pure_expr

theorem nestedMatchReturns (program : Program) (state : State)
    (formed : state.CellsWellFormed) (value : Int) :
    ∃ after, RunsExpr program state (.matchValue (nestedConstructor value) outerArms)
      (.signed .i32 value) after ∧ PureFrame state after := by core_pure_expr

example (value : Int) : ∃ after, RunsExpr {} (({} : State).bindLocal 17 (.signed .i32 91))
    (.matchValue (nestedConstructor value) outerArms) (.signed .i32 value) after ∧
    after.local? 17 = some (.signed .i32 91) := by
  obtain ⟨after, run, frame⟩ := nestedMatchReturns {} (({} : State).bindLocal 17 (.signed .i32 91))
    (by simp [State.CellsWellFormed, State.bindLocal, State.bindCell]) value
  exact ⟨after, run, frame.localFound (by apply State.bindLocal_local?; simp [State.CellsWellFormed])⟩

example (program : Program) (state : State) (formed : state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr program state (.matchValue (nestedConstructor 7) outerArms)
        (.signed .i32 8) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  trivial

example (program : Program) (state : State) (expression : Expr) (value : Value)
    (_unframed : ∃ after, RunsExpr program state expression value after) : True := by
  fail_if_success
    suffices erased : ∃ after, RunsExpr program state (.enumValue 8 1 [expression])
        (.enumeration 8 1 [value]) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  trivial

#print axioms RunsExpr.matchFramedPure
#print axioms RunsExpr.enumPure
#print axioms nestedMatchReturns

end Lanius.Semantics
