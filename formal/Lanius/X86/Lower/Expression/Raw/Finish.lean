import Lanius.X86.Source.Expression.Raw
import Lanius.X86.Lower.Expression.Literal.State
import Lanius.X86.Frame.Address

namespace Lanius.X86.Lower.Expression.Raw.Finish

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Store the descriptor length in its second word, then return the address
of its first word in RAX. The two instructions are emitted by the actual
source helpers; this definition only names their proved byte windows. -/
def bytes (slot : Nat) : List UInt8 :=
  Frame.Slot.bytes .save64 (slot - 1) 0 ++ Frame.Address.bytes slot 0

/-- Finish the real raw-slice branch after its signed-length guard. This
proves the source subtraction, both helper executions, and the returned
slice kind. Only CODE changes in the compiler workspace; descriptor writes
are emitted instructions, not writes to the compiler's own heap. -/
theorem emits {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (slot capacity cursor : Nat)
    (inputPrefix : 5 ≤ bindings.length)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (slotLocal : before.local? checked.locals.slot = some (.signed .i32 slot))
    (positive : 1 ≤ slot) (slotBound : slot ≤ 1048576)
    (current : workspace[1]? = some (cursor : Int))
    (room : cursor + (bytes slot).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted,
      Executes emitters.pack.program.core before
        (Source.Expression.Raw.finish literal checked.helpers.calls checked.locals)
        (.returned (some (.signed .i32 6))) after ∧
      Literal.Ready after bindings frontier input output work transport emitted
        (workspace.set 1 (cursor + (bytes slot).length : Nat)) ∧
      Emission values cursor (bytes slot) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have workEntry := ready.entry 2 (by omega) workLocal
  have outputEntry := ready.entry 3 (by omega) outputLocal
  have capacityEntry := ready.entry 4 (by omega) capacityLocal
  have within : 1 < workspace.length := by
    by_cases inside : 1 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  have previous := evaluatesNatI32Subtract (local_evaluates emitters.pack.program.core slotLocal)
    (show Evaluates emitters.pack.program.core before (number 1) (.signed .i32 (1 : Nat)) before from ⟨1, rfl⟩)
    positive (by omega)
  have rax := literal.constants.rax.evaluates (before := before)
  rw [literal.constants.values.2.2.2.2.2.1] at rax
  have saveArgs : ArgumentsEvaluateTo emitters.pack.program.core before
      [read 3, read 4, read 2, .binary .subtract (read checked.locals.slot) (number 1),
        .constant literal.constants.rax.id]
      (Frame.Slot.inputValues (.slice i32 output [] 0 values.length) capacity
        (.slice i32 work [] 0 workspace.length) (slot - 1) 0) before :=
    .cons (local_evaluates _ outputLocal) (.cons (local_evaluates _ capacityLocal)
      (.cons (local_evaluates _ workLocal) (.cons previous (.cons rax (.nil _ _)))))
  have saveRoom : cursor + (Frame.Slot.bytes .save64 (slot - 1) 0).length ≤ capacity := by
    simp only [bytes, List.length_append] at room
    omega
  obtain ⟨middle, middleValues, saveRun, middleOutput, middleWork, saveExact, _, saveLength,
      saveFrame, saveEffect, saveHeap⟩ :=
    Frame.Slot.emits checked.helpers.save (slot - 1) capacity cursor 0 ready.wellFormed
      (by omega) ready.outputWork ready.outputBacking ready.workBacking current saveRoom storage bounded saveArgs
  have middleReady := ready.frame saveEffect middleOutput middleWork
  have keptSlot := saveEffect.preserves_local ready.wellFormed slotLocal (by
    intro cell binding changed
    rcases changed with out | work
    · exact local_cell_ne_of_distinct_value slotLocal ready.outputBacking (by intro same; cases same) binding out
    · exact local_cell_ne_of_distinct_value slotLocal ready.workBacking (by intro same; cases same) binding work)
  have nextRax := literal.constants.rax.evaluates (before := middle)
  rw [literal.constants.values.2.2.2.2.2.1] at nextRax
  have addressArgs : ArgumentsEvaluateTo emitters.pack.program.core middle
      [read 3, read 4, read 2, read checked.locals.slot, .constant literal.constants.rax.id]
      (Frame.Slot.inputValues (.slice i32 output [] 0 middleValues.length) capacity
        (.slice i32 work [] 0 (workspace.set 1 (cursor + (Frame.Slot.bytes .save64 (slot - 1) 0).length : Nat)).length)
        slot 0) middle := by
    simp only [saveLength, List.length_set]
    exact .cons (local_evaluates _ (middleReady.read 3 outputEntry))
      (.cons (local_evaluates _ (middleReady.read 4 capacityEntry))
        (.cons (local_evaluates _ (middleReady.read 2 workEntry))
          (.cons (local_evaluates _ keptSlot) (.cons nextRax (.nil _ _)))))
  have addressRoom : cursor + (Frame.Slot.bytes .save64 (slot - 1) 0).length +
      (Frame.Address.bytes slot 0).length ≤ capacity := by
    simpa only [bytes, List.length_append, Nat.add_assoc] using room
  obtain ⟨after, emitted, addressRun, finalOutput, finalWork, addressExact, _, addressLength,
      addressFrame, addressEffect, addressHeap⟩ :=
    Frame.Address.emits checked.helpers.address slot capacity
      (cursor + (Frame.Slot.bytes .save64 (slot - 1) 0).length) 0 middleReady.wellFormed
      slotBound ready.outputWork middleReady.outputBacking middleReady.workBacking
      (List.getElem?_set_self within) addressRoom (by simpa only [saveLength] using storage) bounded addressArgs
  have finalReady := middleReady.frame addressEffect finalOutput finalWork
  have endReady : Literal.Ready after bindings frontier input output work transport emitted
      (workspace.set 1 (cursor + (bytes slot).length : Nat)) := by
    simpa only [bytes, List.length_append, List.set_set, Nat.add_assoc] using finalReady
  have firstWindow : Emission values cursor (Frame.Slot.bytes .save64 (slot - 1) 0) middleValues :=
    ⟨saveLength, saveExact, saveFrame⟩
  have lastWindow : Emission middleValues (cursor + (Frame.Slot.bytes .save64 (slot - 1) 0).length)
      (Frame.Address.bytes slot 0) emitted := ⟨addressLength, addressExact, addressFrame⟩
  have slice := literal.layout.slice.evaluates (before := after)
  rw [literal.layout.values.2.2.1] at slice
  exact ⟨after, emitted,
    executesSequence (executesExpression saveRun)
      (executesSequence (executesExpression addressRun) (executesSequenceReturned (executesReturnValue slice))),
    endReady, firstWindow.append lastWindow, saveEffect.trans addressEffect, saveHeap.trans addressHeap⟩

end Lanius.X86.Lower.Expression.Raw.Finish
