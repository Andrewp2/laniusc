import Lanius.Extraction.CompactOutput.Word.State

namespace Lanius.Extraction.CompactOutput.Word

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Evaluate the nibble, both nested calls, and the assignment to `next`.
The effectful RHS retains ownership of the local it will assign afterward. -/
theorem append (byte : CheckedByte program) (digit : CheckedDigit program)
    (owned : Owned memory (remaining + 1) position contents before) (bounded : remaining < 8) :
    ∃ after, Evaluates program.core before (assignment byte.source.function.id digit.source.function.id) .unit after ∧
      Owned memory (remaining + 1) (nextPosition memory.capacity position)
        (appended contents memory.capacity position (hexDigit (memory.value / 2 ^ (remaining * 4) % 16))) after ∧
      CellEffect memory.writes before after := by
  have shiftRead := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.shift)
  rw [bitPosition_succ] at shiftRead
  have nibble := nibble_evaluates memory.value (remaining * 4) memory.valueFit (by omega)
    (local_evaluates program.core owned.value) shiftRead
  obtain ⟨written, call, backing, writeEffect⟩ := append_digit byte digit position memory.capacity
    (memory.value / 2 ^ (remaining * 4) % 16) (by omega) owned.wellFormed owned.room memory.capacityFit
    owned.backing (local_evaluates program.core owned.output) (local_evaluates program.core owned.capacity)
    (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.cursor)) nibble
  have cursorStill := writeEffect.preserves_localPointsTo owned.wellFormed owned.cursor
    (by simpa only [CellSet.singleton] using Ne.symm owned.output_cursor)
  obtain ⟨after, assigned, cursor, combined, assignmentEffect⟩ := evaluatesOwnedLocalSet owned.cursor call writeEffect cursorStill
  have effect : CellEffect memory.writes before after := combined.weaken CellSet.subset_union_left
  have outputAfter := assignmentEffect.preserves_entry writeEffect.wellFormed backing
    (by simpa only [CellSet.singleton] using owned.output_cursor)
  have shiftAfter := combined.preserves_localPointsTo owned.wellFormed owned.shift (by
    intro changed
    rcases changed with output | cursor
    · exact owned.output_shift output.symm
    · exact memory.distinct cursor.symm)
  exact ⟨after, assigned, owned.transition effect appended_length outputAfter cursor shiftAfter, effect⟩

theorem Owned.decrement (owned : Owned memory (remaining + 1) position contents before) (bounded : remaining ≤ 8)
    (program : Program) :
    ∃ after, Evaluates program before decrement .unit after ∧ Owned memory remaining position contents after ∧
      CellEffect memory.writes before after := by
  obtain ⟨after, run, shift, effect⟩ := evaluatesOwnedLocalUpdate owned.wellFormed owned.shift
    (show Evaluates program before (number 4) (.signed .i32 4) before from ⟨1, rfl⟩)
    (decrement_value program.target remaining bounded)
  have cursor := effect.preserves_localPointsTo owned.wellFormed owned.cursor
    (by simpa only [CellSet.singleton] using memory.distinct)
  have output := effect.preserves_entry owned.wellFormed owned.backing
    (by simpa only [CellSet.singleton] using owned.output_shift)
  have combined : CellEffect memory.writes before after := effect.weaken CellSet.subset_union_right
  exact ⟨after, run, owned.transition combined rfl output cursor shift, combined⟩

theorem Owned.condition (owned : Owned memory remaining position contents state) (program : Program) :
    Evaluates program state condition (.boolean (decide (0 < remaining))) state := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned.shift))
    (show Evaluates program state (number 0) (.signed .i32 0) state from ⟨1, rfl⟩)
  simp [evalBinaryValue, evalSignedBinary, bitPosition]
  omega

theorem Owned.failureGuard (owned : Owned memory remaining position contents state) (program : Program) :
    Evaluates program state failureGuard (.boolean (decide (position < 0))) state := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned.cursor)) (negativeOne_evaluates program state)
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true, Except.ok.injEq,
    Value.boolean.injEq, decide_eq_decide]
  omega

end Lanius.Extraction.CompactOutput.Word
