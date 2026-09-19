import Lanius.Extraction.Input.Buffer
import Lanius.Extraction.Input.Source
import Lanius.Separation

namespace Lanius.Extraction.Input

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- A direct destination index starts at zero. File chunks instead retain
the caller's accumulated offset local. -/
def UnpackLocals.Offset (locals : UnpackLocals) (state : State) (count : Nat) : Prop :=
  match locals.total with
  | none => count = 0
  | some total => state.local? total = some (.signed .i32 count)

theorem UnpackLocals.Offset.preserved {locals : UnpackLocals} {count : Nat}
    (offset : locals.Offset before count)
    (wellFormed : StateWellFormed before) (effect : ModifiesOnly writes before after)
    (stable : ∀ id ∈ locals.stableLocals, ∀ cell, before.cellId? id = some cell → ¬ writes cell) :
    locals.Offset after count := by
  cases selected : locals.total with
  | none => simpa only [UnpackLocals.Offset, selected] using offset
  | some total =>
      simp only [UnpackLocals.Offset, selected] at offset ⊢
      exact effect.preserves_local wellFormed offset (stable total (by simp [UnpackLocals.stableLocals, selected]))

/-- One actual unpacking iteration, including the cursor update. The copied
byte is derived from the scratch buffer's byte encoding, not assumed as an
evaluation result. Previously copied bytes and unused capacity are preserved. -/
theorem executes_unpacking_body
    (program : Program) (before : State) (locals : UnpackLocals)
    (outputCell packedCell cursorCell : CellId)
    (earlier untouched packedValues : List Int) (processed : List UInt8)
    (storage : List UInt8) (byte : UInt8)
    (room : processed.length < untouched.length)
    (bounded : earlier.length + untouched.length ≤ 2147483647)
    (distinct : outputCell ≠ cursorCell)
    (wellFormed : StateWellFormed before)
    (outputLocal : before.local? locals.output = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 (earlier.length + untouched.length)))
    (outputContents : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values (copiedBuffer earlier untouched processed))) })
    (packedLocal : before.local? locals.packed = some
      (.slice (.scalar (.signed .i32)) packedCell [] 0 packedValues.length))
    (packedContents : before.cellEntry? packedCell = some {
      id := packedCell, value := some (.array (signedI32Values packedValues)) })
    (encoded : encodeI32Array (signedI32Values packedValues) = .ok storage)
    (byteSelected : storage[processed.length]? = some byte)
    (total : locals.Offset before earlier.length)
    (cursor : (Assertion.localPointsTo locals.cursor cursorCell
      (some (.signed .i32 processed.length))).holds before) :
    ∃ after, Executes program before locals.body .next after ∧
      StateWellFormed after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array
          (signedI32Values (copiedBuffer earlier untouched (processed ++ [byte])))) } ∧
      (Assertion.localPointsTo locals.cursor cursorCell
        (some (.signed .i32 (processed.length + 1 : Nat)))).holds after ∧
      ModifiesOnly (CellSet.union (CellSet.singleton outputCell)
        (CellSet.singleton cursorCell)) before after := by
  have cursorResult : Evaluates program before (.local locals.cursor)
      (.signed .i32 processed.length) before :=
    Lanius.Semantics.evaluatesLocal (Assertion.localPointsTo_local _ _ _ _ cursor)
  have packedResult : Evaluates program before (.local locals.packed)
      (.slice (.scalar (.signed .i32)) packedCell [] 0 packedValues.length) before :=
    Lanius.Semantics.evaluatesLocal packedLocal
  have byteResult := evaluates_encoded_byte program before (.local locals.packed)
    (.local locals.cursor) packedCell packedValues storage processed.length byte
    (by omega) packedResult cursorResult packedContents encoded byteSelected
  have outputIndex : Evaluates program before locals.index
      (.signed .i32 (earlier.length + processed.length : Nat)) before := by
    cases selected : locals.total with
    | none =>
        have zero : earlier.length = 0 := by simpa only [UnpackLocals.Offset, selected] using total
        simpa only [UnpackLocals.index, selected, zero, Nat.zero_add] using cursorResult
    | some id =>
        have totalResult : Evaluates program before (.local id) (.signed .i32 earlier.length) before :=
          Lanius.Semantics.evaluatesLocal (by simpa only [UnpackLocals.Offset, selected] using total)
        simpa only [UnpackLocals.index, selected, Int.ofNat_eq_natCast] using
          evaluatesNatI32Add totalResult cursorResult (by omega)
  have outputLength := copiedBuffer_length earlier untouched processed (by omega)
  obtain ⟨copied, assignment, copiedWF, copiedContents, copyEffect⟩ :=
    evaluatesSetSignedI32SliceIndexFromEmpty program before before before
      (copiedBuffer earlier untouched processed) locals.output _ _ outputCell
      (earlier.length + processed.length) byte.toNat (by omega)
      (by simpa [outputLength] using outputLocal) outputIndex wellFormed
      (ModifiesOnly.refl before) byteResult wellFormed (ModifiesOnly.refl before) outputContents
  rw [copiedBuffer_step earlier untouched processed byte room] at copiedContents
  have cursorStill := copyEffect.preserves_localPointsTo wellFormed cursor
    (by simpa [CellSet.singleton, eq_comm] using distinct)
  obtain ⟨after, increment, afterWF, afterCursor, cursorEffect⟩ :=
    executesIncrementOwnedI32Local program copied locals.cursor cursorCell
      processed.length copiedWF cursorStill (by omega)
  exact ⟨after, executesSequence (executesExpression assignment) increment, afterWF,
    cursorEffect.preserves_entry copiedWF copiedContents
      (by simpa [CellSet.singleton] using distinct), afterCursor, copyEffect.trans cursorEffect⟩

end Lanius.Extraction.Input
