import Lanius.Semantics.Typing.Assignment

namespace Lanius.Semantics.StoreTests

open Lanius Lanius.Core Lanius.Typing

private def program : Program := {}
private def arrayType : Ty := .array (.scalar .bool) 2
private def array (left right : Bool) : Value := .array [.boolean left, .boolean right]
private def types : CellTypes := fun cell =>
  if cell = 0 then some arrayType else if cell = 1 then some (.scalar .bool) else none
private def state (contents : Option Value) : State := {
  locals := [(7, 0), (8, 0), (9, 1)]
  cells := [{ id := 0, value := contents }, { id := 1, value := none }]
  nextCell := 2 }
private def before : State := state (some (array false false))
private def place (index : Nat) : ResolvedPlace := {
  root := 0, projections := [.index index], value := some (.boolean false) }

private theorem arrayTyped (left right : Bool) : ValueHasType program (array left right) arrayType :=
  .array _ (.scalar .bool) rfl (.cons (.boolean left) (.cons (.boolean right) .nil))
private theorem storeTyped (contents : Option Value)
    (typed : match contents with | none => True | some value => ValueHasType program value arrayType) :
    (state contents).CellsHaveTypes program types := by
  intro cell type declared
  simp only [types] at declared
  split at declared
  · next same => subst cell; cases declared; exact ⟨contents, rfl, typed⟩
  · split at declared
    · next same => subst cell; cases declared; exact ⟨none, rfl, trivial⟩
    · cases declared
private theorem placeTyped (index : Nat) (bounded : index < 2) :
    CellPlaceHasType program types (place index) (.scalar .bool) :=
  ⟨arrayType, rfl, .index bounded .root, rfl⟩

-- Allocation extends the map, both for initialized and uninitialized slots.
example (contents : Option Value)
    (typed : match contents with | none => True | some value => ValueHasType program value arrayType) :
    (before.bindCell 10 contents).CellsHaveTypes program
      (fun cell => if cell = 2 then some arrayType else types cell) :=
  (storeTyped _ (arrayTyped false false)).bindCell
    (by simp [State.CellsWellFormed, state]) typed

-- Both aliases refer to one root; their cached values may already be stale.
theorem twoWrites (left right : Bool) :
    (state (some (array left right))).CellsHaveTypes program types ∧
    readCellProjection (state (some (array left right))) 0 [.index 0] = .ok (.boolean left) ∧
    readCellProjection (state (some (array left right))) 0 [.index 1] = .ok (.boolean right) := by
  have first := (storeTyped (some (array false false)) (arrayTyped false false)).write
    (placeTyped 0 (by decide)) (.boolean left)
  change (state (some (array left false))).CellsHaveTypes program types ∧ _ at first
  have second := first.1.write (placeTyped 1 (by decide)) (.boolean right)
  change (state (some (array left right))).CellsHaveTypes program types ∧ _ at second
  exact ⟨second.1, rfl, second.2⟩

example (left right : Bool) : ∃ value,
    readCellProjection (state (some (array left right))) 0 [.index 0] = .ok value ∧
    ValueHasType program value (.scalar .bool) :=
  (twoWrites left right).1.read (placeTyped 0 (by decide)) (by simp [State.cell?, State.cellEntry?, state, place])

-- Root assignment initializes an uninitialized aggregate, retaining the other
-- declared uninitialized cell. Nested assignment must instead report its trap.
example (left right : Bool) :
    match writeResolvedPlaceNative program (state none)
      { root := 0, projections := [], value := none } (array left right) with
    | .ok after => after.CellsHaveTypes program types ∧ after.local? 8 = some (array left right)
    | .error _ => False := by
  have written := (storeTyped none trivial).write
    (show CellPlaceHasType program types { root := 0, projections := [], value := none } arrayType from
      ⟨arrayType, rfl, .root, rfl⟩) (arrayTyped left right)
  change (state (some (array left right))).CellsHaveTypes program types ∧ _ at written ⊢
  exact ⟨written.1, rfl⟩
example : writeResolvedPlaceNative program (state none) (place 0) (.boolean true) =
    .error .uninitializedLocal := rfl
example : (place 0).projections ≠ [] :=
  ((storeTyped none trivial).write (placeTyped 0 (by decide)) (.boolean true)).2

-- A full assignment evaluator contract, not just a primitive store equation.
theorem assignmentAliases (left right : Bool) : ∃ after,
    RunsExpr program before (.assign .set (.local 7) (.value (array left right))) .unit after ∧
    after.CellsHaveTypes program types ∧ after.local? 8 = some (array left right) := by
  obtain ⟨after, run, typed, found⟩ := RunsExpr.assignLocalTyped
    (storeTyped (some (array false false)) (arrayTyped false false)) (cell := 0) rfl (arrayTyped left right)
    (localId := 7) rfl (RunsExpr.ofStable StableExpr.value rfl)
    (storeTyped (some (array false false)) (arrayTyped false false)) rfl
  have aliases : after.local? 8 = after.local? 7 := by
    unfold State.local? State.cellId?
    rw [run.choose_spec.2]
    rfl
  exact ⟨after, run, typed, aliases.trans found⟩

-- Initialization is proved through the complete evaluator, not just the
-- primitive writer. No initialized old-local premise is needed.
theorem initializedAssignment (left right : Bool) : ∃ after,
    RunsExpr program (state none) (.assign .set (.local 7) (.value (array left right))) .unit after ∧
      after.CellsHaveTypes program types ∧ after.local? 8 = some (array left right) := by
  obtain ⟨after, run, typed, found⟩ := RunsExpr.assignLocalTyped (storeTyped none trivial)
    (cell := 0) rfl (arrayTyped left right) (localId := 7) rfl
    (RunsExpr.ofEval (expression := .value (array left right)) (fuel := 1) rfl)
    (storeTyped none trivial) rfl
  have aliases : after.local? 8 = after.local? 7 := by
    unfold State.local? State.cellId?
    rw [run.choose_spec.2]
    rfl
  exact ⟨after, run, typed, aliases.trans found⟩

-- The RHS changes the destination root before yielding its final replacement.
-- Its resulting typed store, not preservation of old cell values, is composed.
theorem mutatingAssignment (flag : Bool) : ∃ after,
    RunsExpr program before (.assign .set (.local 7)
      (.matchValue (.assign .set (.local 8) (.value (array flag false)))
        [(.wildcard, .value (array false flag))])) .unit after ∧
      after.CellsHaveTypes program types ∧ after.local? 8 = some (array false flag) := by
  have right : RunsExpr program before
      (.matchValue (.assign .set (.local 8) (.value (array flag false)))
        [(.wildcard, .value (array false flag))]) (array false flag) (state (some (array flag false))) :=
    RunsExpr.ofEval (fuel := 4) rfl
  obtain ⟨after, run, typed, found⟩ := RunsExpr.assignLocalTyped
    (storeTyped (some (array false false)) (arrayTyped false false)) (cell := 0) rfl (arrayTyped false flag)
    (localId := 7) rfl right (storeTyped (some (array flag false)) (arrayTyped flag false)) rfl
  have aliases : after.local? 8 = after.local? 7 := by
    unfold State.local? State.cellId?
    rw [run.choose_spec.2]
    rfl
  exact ⟨after, run, typed, aliases.trans found⟩

-- A match binding allocates a temporary during the right-hand computation.
-- The typed assignment rule carries the old store through that allocation.
theorem allocatingAssignment (flag : Bool) : ∃ after,
    RunsExpr program before (.assign .set (.local 7)
      (.matchValue (.value (.boolean flag)) [(.bind 99, .value (array flag false))])) .unit after ∧
    after.CellsHaveTypes program types ∧ after.local? 8 = some (array flag false) := by
  let ready := restoreLocals before (before.bindLocal 99 (.boolean flag))
  have right : RunsExpr program before
      (.matchValue (.value (.boolean flag)) [(.bind 99, .value (array flag false))]) (array flag false) ready :=
    RunsExpr.ofEval (fuel := 3) rfl
  obtain ⟨after, run, typed, found⟩ := RunsExpr.assignLocalTyped
    (storeTyped _ (arrayTyped false false)) (cell := 0) rfl (arrayTyped flag false)
    (localId := 7) rfl right
    ((storeTyped _ (arrayTyped false false)).retained (FreshCellFrame.bindLocal before 99 (.boolean flag)).restoreLocals) rfl
  have aliases : after.local? 8 = after.local? 7 := by
    unfold State.local? State.cellId?
    rw [run.choose_spec.2]
    rfl
  exact ⟨after, run, typed, aliases.trans found⟩

-- Runtime writes do not check types. Dropping the type premise really does
-- break the store invariant, even though the physical write succeeds.
private def bad : State := state (some (.string "wrong"))
example : writeResolvedPlaceNative program before
    { root := 0, projections := [], value := none } (.string "wrong") = .ok bad := rfl
example : ¬ bad.CellsHaveTypes program types := by
  intro valid
  obtain ⟨contents, present, typed⟩ := valid 0 arrayType rfl
  have same : contents = some (.string "wrong") := by
    have entry := Option.some.inj (present.symm.trans (show bad.cellEntry? 0 = _ from rfl))
    exact congrArg Cell.value entry
  subst contents
  cases typed

-- Shape-typed references do not establish live storage or valid paths.
example : ValueHasType program (.reference arrayType 44 []) (.reference arrayType) := .reference _ _ _
example : readCellProjection before 44 [] = .error .invalidPointer := rfl
example : ¬ CellPlaceHasType program types { root := 44, projections := [], value := none } arrayType := by
  rintro ⟨rootType, declared, _, _⟩
  cases declared
example : ¬ ProjectionHasType program arrayType [.index 2] (.scalar .bool) := by
  intro path
  cases path with
  | index bounded rest => omega

-- Reusing an existing identity cannot extend a store with a different type.
private def badFrontier : State := { before with nextCell := 0 }
example : ¬ (badFrontier.bindCell 10 none).CellsHaveTypes program
    (fun cell => if cell = 0 then some (.scalar .bool) else types cell) := by
  intro valid
  obtain ⟨contents, present, typed⟩ := valid 0 (.scalar .bool) rfl
  have same : contents = some (array false false) := by
    have entry := Option.some.inj
      (present.symm.trans (show (badFrontier.bindCell 10 none).cellEntry? 0 = _ from rfl))
    exact congrArg Cell.value entry
  subst contents
  cases typed

-- Typed cells alone do not validate registered native views. The evaluator can
-- trap during synchronization after a primitive typed write has succeeded.
private def viewed : State := { before with
  i32ArrayViews := [{ address := 0, root := 0, projections := [], length := 2 }] }
example : evalExpr 2 program viewed (.assign .set (.local 7) (.value (array true false))) =
    .trapped .typeMismatch { viewed with cells := replaceCell viewed.cells 0 (array true false) } := rfl

#print axioms twoWrites
#print axioms assignmentAliases
#print axioms allocatingAssignment
#print axioms initializedAssignment
#print axioms mutatingAssignment

end Lanius.Semantics.StoreTests
