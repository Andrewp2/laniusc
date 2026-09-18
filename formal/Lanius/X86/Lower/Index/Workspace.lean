import Lanius.X86.Lower.Index.State
import Lanius.X86.Encode.Indexed

namespace Lanius.X86.Lower.Index.Emission

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def slotBytes (slot : Nat) : List UInt8 := (Machine.Index.load 11 5 (Frame.displacement slot)).bytes
@[simp] theorem slotBytes_length : (slotBytes slot).length = 7 := rfl

/-- The saved descriptor load advances workspace CODE, but not the lexical
cursor. Both facts are needed by the following length-load assignment. -/
theorem load_slot (checked : Source.Index.Checked emitters)
    (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace)
    (start : Nat) (current : workspace[1]? = some (start : Int)) (slotBound : slot ≤ 1048576)
    (room : start + (slotBytes slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before
        (.expression (.call checked.helpers.calls.slot (Source.Index.slotArguments checked.constants))) .next after ∧
      Ready after output work temporary frontier capacity slot kind cursor emitted (workspace.set 1 (start + (slotBytes slot).length : Nat)) ∧
      Buffer.Emission values start (slotBytes slot) emitted ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  have r11 := checked.constants.r11.evaluates (before := before)
  rw [checked.constants.values.2.2.2.2.2.1] at r11
  have args : ArgumentsEvaluateTo emitters.pack.program.core before (Source.Index.slotArguments checked.constants)
      (Frame.Slot.inputValues (.slice i32 output [] 0 values.length) capacity
        (.slice i32 work [] 0 workspace.length) slot 11) before :=
    .cons (local_evaluates _ (ready.inputs.found ⟨0, by simp⟩))
      (.cons (local_evaluates _ (ready.inputs.found ⟨1, by simp⟩))
        (.cons (local_evaluates _ (ready.inputs.found ⟨2, by simp⟩))
          (.cons (local_evaluates _ (ready.inputs.found ⟨3, by simp⟩)) (.cons r11 (.nil _ _)))))
  obtain ⟨after, emitted, run, outputContents, workContents, bytes, _, length, frame, effect, heap⟩ := Frame.Slot.emits
    checked.helpers.slot slot capacity start 11 ready.wellFormed slotBound ready.distinct ready.outputBacking ready.workBacking
    current room storage bounded args
  have inputs := ready.inputs.frame ready.wellFormed effect (by
    intro index cell binding changed
    rcases changed with same | same
    · exact local_cell_ne_of_distinct_value (ready.inputs.found index) ready.outputBacking (inputs_not_array index _) binding same
    · exact local_cell_ne_of_distinct_value (ready.inputs.found index) ready.workBacking (inputs_not_array index _) binding same)
  have owned := effect.preserves_localPointsTo ready.wellFormed ready.position (by
    intro changed
    rcases changed with same | same
    · exact ready.next_ne_output same
    · exact ready.next_ne_work same)
  refine ⟨after, emitted, executesExpression run, ⟨effect.wellFormed, ?_, outputContents, workContents,
    owned, ready.fresh, ready.distinct⟩, ⟨length, bytes, frame⟩, effect, heap⟩
  simpa only [length, List.length_set] using inputs

/-- The final LEA call writes output and stores its returned cursor into
workspace, then the real return expression reads that updated field. -/
theorem finish (checked : Source.Index.Checked emitters)
    (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace)
    (within : 1 < workspace.length) (room : cursor + 8 ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before
        (Source.Index.finish checked.constants checked.helpers.calls)
        (.returned (some (.signed .i32 (cursor + 8 : Nat)))) after ∧
      Ready after output work temporary frontier capacity slot kind cursor emitted (workspace.set 1 (cursor + 8 : Nat)) ∧
      Buffer.Emission values cursor Machine.Index.address.bytes emitted ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  have rax := checked.constants.rax.evaluates (before := before)
  have r11 := checked.constants.r11.evaluates (before := before)
  rw [checked.constants.values.2.2.2.1] at rax
  rw [checked.constants.values.2.2.2.2.2.1] at r11
  have args : ArgumentsEvaluateTo emitters.pack.program.core before
      [read 0, read 1, Source.Index.next, .constant checked.constants.rax.id, .constant checked.constants.r11.id,
        .constant checked.constants.rax.id, number 2, number 0]
      (Encode.Indexed.sliceAddress.arguments (.slice i32 output [] 0 values.length) capacity cursor) before :=
    .cons (local_evaluates _ (ready.inputs.found ⟨0, by simp⟩))
      (.cons (local_evaluates _ (ready.inputs.found ⟨1, by simp⟩)) (.cons (local_evaluates _ ready.read)
        (.cons rax (.cons r11 (.cons rax (.cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.nil _ _))))))))
  obtain ⟨middle, emitted, run, contents, bytes, _, length, frame, effect, heap⟩ := Encode.Indexed.slice_address_emits
    checked.helpers.address capacity cursor ready.wellFormed room storage bounded ready.outputBacking args
  obtain ⟨after, update, afterReady, combined, combinedHeap⟩ := ready.code checked.constants within run effect heap contents length
  have returned := Frame.Slot.code_read checked.constants.code checked.constants.values.1
    (afterReady.inputs.found ⟨2, by simp⟩) afterReady.workBacking (List.getElem?_set_self within)
  exact ⟨after, emitted, executesSequence update (executesSequenceReturned (executesReturnValue returned)), afterReady,
    ⟨length, bytes, frame⟩, combined, combinedHeap⟩

end Lanius.X86.Lower.Index.Emission
