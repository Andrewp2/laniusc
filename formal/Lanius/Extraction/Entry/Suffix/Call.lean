import Lanius.Extraction.Entry.Suffix.Source
import Lanius.Extraction.Allocation.Transport

namespace Lanius.Extraction.Entry.Suffix
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

/-- The saved-cursor check cannot mistake the error sentinel for a successful
677-byte append, even if the signed addition wraps. -/
theorem sum_ne_error (target : Target) (position : Nat) (bounded : position ≤ 2147483647) :
    wrapSigned target .i32 (Int.ofNat position + Int.ofNat bytes.length) ≠ -1 := by
  rw [bytes_length]
  have remainder : ((position : Int) + 677) % 4294967296 = (position : Int) + 677 :=
    Int.emod_eq_of_lt (by omega) (by omega)
  change (if ((position : Int) + 677) % 4294967296 ≥ 2147483648 then
    ((position : Int) + 677) % 4294967296 - 4294967296 else
    ((position : Int) + 677) % 4294967296) ≠ -1
  rw [remainder]
  intro equal
  split at equal <;> omega

/-- Execute the actual suffix call and guard on both capacity outcomes.
Success reaches the continuation with all 677 bytes; exhaustion returns 25
with only the fitting prefix and never executes the packing/stdout tail. -/
theorem Stage.executes (stage : Stage) (supported : Supported stage framing)
    (framingSupport : Framing.Supported framing) (text : Text.Checked program byte)
    (before : State) (earlier untouched : List Int)
    (registry : Allocation.Registry before)
    (outputRead : before.local? stage.output = some (.slice i32 outputCell [] 0 (earlier.length + untouched.length)))
    (positionRead : before.local? stage.position = some (.signed .i32 earlier.length))
    (suffixRead : before.local? stage.closing = some (.string framing.suffixText))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values (earlier ++ untouched))) })
    (positionBound : earlier.length ≤ stage.capacity)
    (capacity : stage.capacity ≤ earlier.length + untouched.length)
    (post : Scope.Post)
    (overflowPost : ∀ middle positionCell,
      stage.capacity < earlier.length + bytes.length →
      (Assertion.localPointsTo stage.position positionCell (some (.signed .i32 (-1)))).holds middle →
      middle.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (Input.copiedBuffer earlier untouched (Text.emitted bytes earlier.length stage.capacity)))) } →
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton positionCell))
        before (restoreLocals before middle) →
      Allocation.Registry middle →
      (∃ fresh, middle.i32ArrayViews = before.i32ArrayViews ++ fresh) →
      post (.returned (some (.signed .i32 25))) middle)
    (continuationRun : ∀ middle positionCell,
      earlier.length + bytes.length ≤ stage.capacity →
      (Assertion.localPointsTo stage.position positionCell
        (some (.signed .i32 (earlier.length + bytes.length : Nat)))).holds middle →
      middle.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (Input.copiedBuffer earlier untouched bytes))) } →
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton positionCell))
        before (restoreLocals before middle) →
      (∀ id, id ≠ stage.previous → middle.cellId? id = before.cellId? id) →
      Allocation.Registry middle →
      (∃ fresh, middle.i32ArrayViews = before.i32ArrayViews ++ fresh) →
      Prefix.Reaches program.core before (stage.statement text.source.function.id) middle stage.continuation →
      ∃ completion after, Executes program.core middle stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before (stage.statement text.source.function.id) completion after ∧
      post completion after := by
  obtain ⟨positionCell, ownedBefore⟩ := Assertion.exists_localPointsTo_of_local _ _ _ positionRead
  let ready := before.bindLocal stage.previous (.signed .i32 earlier.length)
  have readyRegistry := registry.bindLocal stage.previous (.signed .i32 earlier.length)
  have bound := bindLocal_effect before stage.previous (.signed .i32 earlier.length)
  have backingReady := (bound.oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry registry.wellFormed backing) (by simp [CellSet.empty])).trans backing
  have ownedReady : (Assertion.localPointsTo stage.position positionCell
      (some (.signed .i32 earlier.length))).holds ready :=
    ⟨(bindLocal_preserves_other_cellId before stage.previous stage.position _ supported.previousPosition).trans ownedBefore.1,
      (bound.oldCells positionCell (StateWellFormed.cell_lt_next_of_entry registry.wellFormed ownedBefore.2)
        (by simp [CellSet.empty])).trans ownedBefore.2⟩
  have outputReady := (bindLocal_preserves_other_local (value := Value.signed .i32 earlier.length)
    registry.wellFormed supported.previousOutput).trans outputRead
  have closingReady := (bindLocal_preserves_other_local (value := Value.signed .i32 earlier.length)
    registry.wellFormed supported.previousClosing).trans suffixRead
  have positionReady := Assertion.localPointsTo_local _ _ _ _ ownedReady
  have outputPosition : outputCell ≠ positionCell := by
    intro same
    rw [same, ownedBefore.2] at backing
    cases backing
  obtain ⟨written, call, output, effect, registered, views⟩ := text.append ready ready framing.suffixText bytes
    earlier untouched stage.capacity readyRegistry.wellFormed backingReady positionBound capacity
    (supported.capacity.symm ▸ framingSupport.capacityFit) (by rw [bytes_length]; decide)
    (by simpa only [bytes] using framingSupport.suffixPadded)
    (by simpa only [bytes] using framingSupport.suffixEmitted)
    (.cons (local_evaluates program.core outputReady)
      (.cons (show Evaluates program.core ready (number stage.capacity) (.signed .i32 stage.capacity) ready from evaluatesValue)
        (.cons (local_evaluates program.core positionReady)
          (.cons (local_evaluates program.core closingReady)
            (.cons (show Evaluates program.core ready (number bytes.length) (.signed .i32 bytes.length) ready from evaluatesValue)
              (.nil _ _))))))
  have stillOwned := effect.preserves_localPointsTo readyRegistry.wellFormed ownedReady
    (by simpa only [CellSet.singleton, eq_comm] using outputPosition)
  obtain ⟨middle, assigned, owned, combined, assignmentEffect, assignmentHeap, _⟩ :=
    evaluatesOwnedLocalSet ownedReady call effect stillOwned
  have outputMiddle := assignmentEffect.preserves_entry effect.wellFormed output outputPosition
  have writtenRegistry := registered readyRegistry
  have middleRegistry : Allocation.Registry middle := by
    apply writtenRegistry.transport assignmentEffect assignmentHeap
    intro view member changed
    exact False.elim (writtenRegistry.notScalar member (changed.symm ▸ stillOwned.2))
  have previousOwned := bindLocal_owns_fresh before stage.previous (.signed .i32 earlier.length) registry.wellFormed
  have previousRead := Assertion.localPointsTo_local _ _ _ _
    (combined.preserves_localPointsTo readyRegistry.wellFormed previousOwned (by
      intro changed
      rcases changed with output | position
      · exact (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry registry.wellFormed backing)) output.symm
      · exact (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry registry.wellFormed ownedBefore.2)) position.symm))
  have closed := CellEffect.closeLocal before stage.previous (.signed .i32 earlier.length)
    registry.wellFormed combined
  have extendedViews : ∃ fresh, middle.i32ArrayViews = before.i32ArrayViews ++ fresh := by
    obtain ⟨fresh, extended⟩ := views
    exact ⟨fresh, by simpa only [assignmentHeap.views, ready, State.bindLocal, State.bindCell] using extended⟩
  have capacityFit : stage.capacity ≤ 2147483647 := supported.capacity.symm ▸ framingSupport.capacityFit
  by_cases room : earlier.length + bytes.length ≤ stage.capacity
  · rw [Text.finalPosition_of_fits room] at owned
    rw [Text.emitted_of_fits room] at outputMiddle
    have sum := evaluatesNatI32Add (local_evaluates program.core previousRead)
      (show Evaluates program.core middle (number bytes.length) (.signed .i32 bytes.length) middle from evaluatesValue)
      (by omega)
    have guard : Evaluates program.core middle
        (binary .notEqual (read stage.position) (binary .add (read stage.previous) (number bytes.length)))
        (.boolean false) middle := by
      apply evaluatesEagerBinary (by decide) (by decide)
        (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned)) sum
      simp [evalBinaryValue, scalarEqual]
    have reached : Prefix.Reaches program.core before (stage.statement text.source.function.id) middle stage.continuation :=
      .letLocal (local_evaluates program.core positionRead)
        (.sequence (executesExpression assigned) (.sequence (executesIfFalse guard (executesSkip _ _)) .here))
    obtain ⟨completion, after, continued, satisfied⟩ := continuationRun middle positionCell room owned outputMiddle closed
      (fun id different => by
        change middle.cellId? id = before.cellId? id
        rw [show middle.cellId? id = ready.cellId? id from by simp only [State.cellId?, combined.locals]]
        exact bindLocal_preserves_other_cellId before stage.previous id _ (Ne.symm different))
      middleRegistry extendedViews reached
    exact ⟨completion, restoreLocals before after,
      executesLetLocal (local_evaluates program.core positionRead)
        (executesSequence (executesExpression assigned) (executesSequence (executesIfFalse guard (executesSkip _ _)) continued)),
      post.restore completion before after satisfied⟩
  · have overflow : stage.capacity < earlier.length + bytes.length := by omega
    rw [Text.finalPosition_of_full overflow] at owned
    have sum : Evaluates program.core middle (binary .add (read stage.previous) (number bytes.length))
        (.signed .i32 (wrapSigned program.core.target .i32
          (Int.ofNat earlier.length + Int.ofNat bytes.length))) middle := by
      apply evaluatesEagerBinary (by decide) (by decide)
        (local_evaluates program.core previousRead)
        (show Evaluates program.core middle (number bytes.length) (.signed .i32 bytes.length) middle from evaluatesValue)
      rfl
    have different := sum_ne_error program.core.target earlier.length (by omega)
    have guard : Evaluates program.core middle
        (binary .notEqual (read stage.position) (binary .add (read stage.previous) (number bytes.length)))
        (.boolean true) middle := by
      apply evaluatesEagerBinary (by decide) (by decide)
        (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned)) sum
      simp [evalBinaryValue, scalarEqual]
      exact Ne.symm different
    have failed := executesSequence (executesExpression assigned)
      (executesSequenceReturned (second := stage.continuation) (executesIfTrue (elseBranch := .skip) guard
        (executesSequenceReturned (second := .skip)
          (executesReturnValue (show Evaluates program.core middle (number 25) (.signed .i32 25) middle from evaluatesValue)))))
    exact ⟨_, restoreLocals before middle, executesLetLocal (local_evaluates program.core positionRead) failed,
      post.restore _ before middle
        (overflowPost middle positionCell overflow owned outputMiddle closed middleRegistry extendedViews)⟩

end Lanius.Extraction.Entry.Suffix
