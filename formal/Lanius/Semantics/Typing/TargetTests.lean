import Lanius.Semantics.Typing.Reference
import Lanius.Semantics.Typing.Slice
import Lanius.Semantics.Typing.Assignment

namespace Lanius.Semantics.TargetTests

open Lanius Lanius.Core Lanius.Typing

private def program : Program := {}
private def arrayType : Ty := .array (.scalar .bool) 3
private def array (left right : Bool) : Value := .array [.boolean left, .boolean false, .boolean right]
private def types : CellTypes := fun cell => if cell = 0 then some arrayType else none
private def state (contents : Option Value) : State := {
  locals := [(10, 0), (11, 0)], cells := [{ id := 0, value := contents }], nextCell := 1 }
private def before (left right : Bool) : State := state (some (array left right))
private def reference : Value := .reference (.scalar .bool) 0 [.index 2]
private def slice : Value := .slice (.scalar .bool) 0 [] 1 2

private theorem arrayTyped (left right : Bool) : ValueHasType program (array left right) arrayType :=
  .array _ _ rfl (.cons (.boolean left) (.cons (.boolean false) (.cons (.boolean right) .nil)))
private theorem storeTyped (left right : Bool) : (before left right).CellsHaveTypes program types := by
  intro cell type declared
  simp only [types] at declared
  split at declared
  · next same => subst cell; cases declared; exact ⟨some (array left right), rfl, arrayTyped left right⟩
  · cases declared
private theorem rootTarget (left right : Bool) : CellTargetValid program types (before left right) 0 [] arrayType :=
  ⟨arrayType, rfl, .root, by simp [State.cell?, State.cellEntry?, before, state]⟩
private theorem referenceValid (left right : Bool) : CellReferenceValid program types (before left right) reference (.scalar .bool) :=
  .reference ⟨arrayType, rfl, .index (by decide) .root, (rootTarget left right).choose_spec.2.2⟩
private theorem sliceValid (left right : Bool) : CellSliceValid program types (before left right) slice (.scalar .bool) :=
  .slice (rootTarget left right) (by decide)

-- Construction and reading compose through the actual borrow/array conversion.
theorem borrowRead (left right : Bool) : ∃ value,
    RunsExpr program (before left right) (.dereference (.borrow arrayType (.local 10))) value (before left right) ∧
      ValueHasType program value arrayType := by
  obtain ⟨borrow, valid⟩ := (rootTarget left right).borrowLocal (localId := 10) rfl
  exact borrow.dereferenceTyped (storeTyped left right) valid

theorem arraySliceRead (left right : Bool) (position : Nat) (bound : position < 3) : ∃ value,
    RunsExpr program (before left right)
      (.index (.arrayToSlice (.scalar .bool) (.local 11)) (.value (.signed .i32 position))) value (before left right) ∧
      ValueHasType program value (.scalar .bool) := by
  obtain ⟨base, valid⟩ := (rootTarget left right).arrayToSliceLocal (storeTyped left right) (localId := 11) rfl
  exact base.cellSliceIndexTyped (RunsExpr.ofEval (fuel := 1) rfl) (storeTyped left right) valid bound

-- Sub-slices retain exact length, including the empty slice at the array end.
example (left right : Bool) : ∃ values,
    sliceValues (before left right) 0 [] 1 2 = .ok values ∧ values.length = 2 ∧
      ValuesHaveTypes program values (List.replicate 2 (.scalar .bool)) :=
  (sliceValid left right).read (storeTyped left right)
example (left right : Bool) : ∃ values,
    sliceValues (before left right) 0 [] 3 0 = .ok values ∧ values.length = 0 ∧
      ValuesHaveTypes program values [] :=
  (show CellSliceValid program types (before left right) (.slice (.scalar .bool) 0 [] 3 0) (.scalar .bool) from
    .slice (rootTarget left right) (by decide)).read (storeTyped left right)

-- A previously created reference and slice follow current values after a
-- write through an alias, rather than retaining a creation-time snapshot.
theorem aliasWrite (left right : Bool) :
    CellReferenceValid program types (before left right) reference (.scalar .bool) ∧
    dereferenceValue (before left right) reference = .ok (.boolean right) ∧
    CellSliceValid program types (before left right) slice (.scalar .bool) := by
  have effect : CellEffect (before false false) (before left right) 0 (array left right) :=
    assignCell_effect (by rfl)
  have store := (storeTyped false false).cellEffect effect rfl (arrayTyped left right)
  have ref := (referenceValid false false).cellEffect effect
  have descriptor := (sliceValid false false).cellEffect effect
  have _ := ref.read store
  exact ⟨ref, rfl, descriptor⟩

-- Shadowing a variable does not retarget an existing cell reference.
example (left right : Bool) : ∃ value,
    dereferenceValue ((before left right).bindLocal 10 (.string "shadow")) reference = .ok value ∧
      ValueHasType program value (.scalar .bool) := by
  have frame := FreshCellFrame.bindLocal (before left right) 10 (.string "shadow")
  exact ((referenceValid left right).retained frame).read ((storeTyped left right).retained frame)

private def changingIndex (flag : Bool) : Expr :=
  .matchValue (.assign .set (.local 10) (.value (array flag false))) [(.wildcard, .value (.signed .i32 0))]

-- Index evaluation mutates the backing array after the base descriptor has
-- been created. The full evaluator and composition rule both see that write.
theorem effectfulIndex (flag : Bool) :
    RunsExpr program (before false false)
      (.index (.arrayToSlice (.scalar .bool) (.local 10)) (changingIndex flag)) (.boolean flag) (before flag false) := by
  obtain ⟨base, valid⟩ := (rootTarget false false).arrayToSliceLocal (storeTyped false false) (localId := 10) rfl
  have effect : CellEffect (before false false) (before flag false) 0 (array flag false) := assignCell_effect (by rfl)
  have index : RunsExpr program (before false false) (changingIndex flag) (.signed .i32 0) (before flag false) :=
    RunsExpr.ofEval (fuel := 4) rfl
  obtain ⟨value, run, typed⟩ := base.cellSliceIndexTyped index
    ((storeTyped false false).cellEffect effect rfl (arrayTyped flag false)) (valid.cellEffect effect) (by decide)
  have actual : RunsExpr program (before false false)
      (.index (.arrayToSlice (.scalar .bool) (.local 10)) (changingIndex flag)) (.boolean flag) (before flag false) :=
    RunsExpr.ofEval (fuel := 5) rfl
  have same := (run.agree actual).1
  simpa only [same] using run

-- Shape typing is insufficient: missing, uninitialized and out-of-range
-- targets are genuine failures, and cannot inhabit the new validity predicates.
example : ValueHasType program (.reference arrayType 44 []) (.reference arrayType) := .reference _ _ _
example : ¬ CellReferenceValid program types (before false false) (.reference arrayType 44 []) arrayType := by
  intro valid
  cases valid with
  | reference target => obtain ⟨root, declared, _, _⟩ := target; cases declared
example : dereferenceValue (before false false) (.reference arrayType 44 []) = .error .invalidPointer := rfl
example : ¬ CellReferenceValid program types (state none) (.reference arrayType 0 []) arrayType := by
  intro valid
  cases valid with
  | reference target => exact target.choose_spec.2.2 rfl
example : evalExpr 2 program (state none) (.borrow arrayType (.local 10)) = .trapped .uninitializedLocal (state none) := rfl
example : sliceValues (before false false) 0 [] 3 1 = .error .arrayBounds := rfl
example : ¬ CellSliceValid program types (before false false) (.slice (.scalar .bool) 0 [] 3 1) (.scalar .bool) := by
  intro valid
  cases valid with
  | slice target bounds =>
    obtain ⟨rootType, declared, path, _⟩ := target
    have same : rootType = arrayType := Option.some.inj declared.symm
    subst rootType
    cases path
    omega

-- Unchecked mutation can retain a descriptor's identity but invalidate its
-- promised backing type. The typed-store premise must not be omitted.
example : dereferenceValue (state (some (.boolean true))) reference = .error .typeMismatch := rfl
example : ¬ (state (some (.boolean true))).CellsHaveTypes program types := by
  intro store
  obtain ⟨contents, found, typed⟩ := store 0 arrayType rfl
  have entry := Option.some.inj (found.symm.trans (show (state (some (.boolean true))).cellEntry? 0 = _ from rfl))
  have same := congrArg Cell.value entry
  simp only at same
  subst contents
  cases typed

#print axioms borrowRead
#print axioms arraySliceRead
#print axioms aliasWrite
#print axioms effectfulIndex

end Lanius.Semantics.TargetTests
