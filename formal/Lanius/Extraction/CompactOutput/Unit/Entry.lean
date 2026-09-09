import Lanius.Extraction.CompactOutput.Unit.Word

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- Allocate the actual unit cursor after its initializer has executed. -/
def Memory.enter {outputCell : CellId} (wellFormed : StateWellFormed state) (position : Int)
    (backing : state.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values contents)) }) : Memory where
  base := state.bindLocal 19 (.signed .i32 position)
  outputCell := outputCell
  cursorCell := state.nextCell
  initialPosition := position
  initialContents := contents
  wellFormed := bindLocal_preserves_well_formed _ _ _ wellFormed
  cursor := bindLocal_owns_fresh _ _ _ wellFormed
  backing := ((bindLocal_effect state 19 (.signed .i32 position)).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  stable := by
    intro id different cell binding
    rw [bindLocal_preserves_other_cellId state 19 id (.signed .i32 position) different.symm] at binding
    exact Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell wellFormed binding)

/-- The first serializer call is evaluated using the incoming position, not
the not-yet-allocated `next`. All other parameters and input arrays survive
the call and cursor allocation. -/
theorem initialize_cursor (word : Word.Checked program byte digit) (pathLength capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before) (pathFit : pathLength ≤ 2147483647)
    (room : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (pathRead : before.local? 1 = some (.signed .i32 pathLength))
    (outputRead : before.local? 16 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 17 = some (.signed .i32 capacity))
    (positionRead : before.local? 18 = some (.signed .i32 position))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ written, ∃ memory : Memory,
      Evaluates program.core before (.call word.source.function.id [read 16, read 17, read 18, read 1])
        (.signed .i32 (appendAll capacity (hexDigits pathLength 8) position original).position) written ∧
      memory.base = written.bindLocal 19 (.signed .i32 memory.initialPosition) ∧
      memory.outputCell = outputCell ∧ memory.cursorCell = written.nextCell ∧
      memory.initialPosition = (appendAll capacity (hexDigits pathLength 8) position original).position ∧
      memory.initialContents = (appendAll capacity (hexDigits pathLength 8) position original).contents ∧
      CellEffect (CellSet.singleton outputCell) before written ∧
      (∀ id value, id ≠ 19 → before.local? id = some value →
        value ≠ .array (signedI32Values original) → memory.base.local? id = some value) ∧
      (∀ cell physicalCapacity values, I32Prefix before cell physicalCapacity values →
        outputCell ≠ cell → I32Prefix memory.base cell physicalCapacity values) := by
  obtain ⟨written, run, output, effect⟩ := word.write position capacity pathLength wellFormed
    room capacityFit pathFit backing
    (.cons (local_evaluates program.core outputRead) (.cons (local_evaluates program.core capacityRead)
      (.cons (local_evaluates program.core positionRead) (.cons (local_evaluates program.core pathRead) (.nil _ _)))))
  let memory := Memory.enter effect.wellFormed
    (appendAll capacity (hexDigits pathLength 8) position original).position output
  refine ⟨written, memory, run, rfl, rfl, rfl, rfl, rfl, effect, ?_, ?_⟩
  · intro id value different found notArray
    apply (bindLocal_preserves_other_local effect.wellFormed different.symm).trans
    apply effect.preserves_local wellFormed found
    intro cell binding changed
    exact local_cell_ne_of_distinct_value found backing notArray binding changed
  · intro cell physicalCapacity values input separate
    obtain ⟨unused, size, contents⟩ := input
    have preserved := effect.preserves_entry wellFormed contents
      (by simpa only [CellSet.singleton] using separate.symm)
    exact ⟨unused, size, ((bindLocal_effect written 19 (.signed .i32 memory.initialPosition)).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry effect.wellFormed preserved) (by simp [CellSet.empty])).trans preserved⟩

end Lanius.Extraction.CompactOutput.Unit
