import Lanius.Semantics.LocalEnv

namespace ProofInterfaceLocalTests

open Lanius Lanius.Core Lanius.Semantics

private def aliased (number : Int) : State := {
  locals := [(1, 0), (2, 0)]
  cells := [{ id := 0, value := some (.signed .i32 number) }]
  nextCell := 1 }

theorem actualAliasWrite :
    (aliased 0).assignLocal 1 (.signed .i32 9) = some (aliased 9) := by rfl

theorem otherAliasObservesWrite : (aliased 9).local? 2 = some (.signed .i32 9) := by rfl

-- The environment must not pretend that two names own separate mutable slots.
theorem rejectsAliasedSlots (base : State) (values : LocalValues)
    (left : values 1 = some (.signed .i32 0))
    (right : values 2 = some (.signed .i32 0)) : ¬LocalEnv base (aliased 0) values := by
  intro env
  have impossible : (1 : Nat) = 2 := env.separate left right rfl
  omega

private def cellNumber (entry : Option Cell) : Int := match entry with
  | some { value := some (.signed _ number), .. } => number
  | _ => -1

-- A call writing through an old alias cannot supply the required cell frame.
theorem rejectsAliasingCallFrame : ¬FreshCellFrame (aliased 0) (aliased 9) := by
  intro frame
  have retained := frame.cellEntryFound
    (show (aliased 0).cellEntry? 0 = some { id := 0, value := some (.signed .i32 0) } by rfl)
  have impossible := congrArg cellNumber retained
  change (9 : Int) = 0 at impossible
  omega

private def compound : Value :=
  .structure 42 [.reference .unit 0 [], .array [.signed .i32 7]]

-- Reference/aggregate VALUES are supported, with synchronization explicitly
-- discharged. This intentionally makes no claim about their referents.
theorem compoundAssignment {base current : State} {values : LocalValues} {id : VarId}
    {old : Value} {program : Program} (env : LocalEnv base current values)
    (found : values id = some old) (noViews : current.i32ArrayViews = []) :
    ∃ after, RunsExpr program current (.assign .set (.local id) (.value compound)) .unit after ∧
      LocalEnv base after (values.set id compound) := by
  obtain ⟨after, run, updated, _, _, _⟩ := env.assignSetAfter found env found
    (show RunsExpr program current (.value compound) compound current from .ofStable .value rfl)
    (Or.inr noViews)
  exact ⟨after, run, updated⟩

private def resultNumber (result : Except Trap Value) : Int := match result with
  | .ok (.signed _ number) => number
  | _ => -1

-- The assignI32 obligation rejects either a stale counter result or an actual
-- subtract body presented as increment. These are not message-text snapshots.
theorem rejectsWrongCounter :
    evalAssignValue Target.x86_64 .add (some (.signed .i32 4)) (.signed .i32 1) ≠
      .ok (.signed .i32 4) := by
  intro equality
  have impossible := congrArg resultNumber equality
  change (5 : Int) = 4 at impossible
  omega

theorem rejectsWrongBody :
    evalAssignValue Target.x86_64 .subtract (some (.signed .i32 4)) (.signed .i32 1) ≠
      .ok (.signed .i32 5) := by
  intro equality
  have impossible := congrArg resultNumber equality
  change (3 : Int) = 5 at impossible
  omega

#print axioms rejectsAliasedSlots
#print axioms rejectsAliasingCallFrame
#print axioms compoundAssignment
#print axioms rejectsWrongCounter
#print axioms rejectsWrongBody

end ProofInterfaceLocalTests
