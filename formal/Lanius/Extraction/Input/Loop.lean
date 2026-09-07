import Lanius.Extraction.Input.Body

namespace Lanius.Extraction.Input

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure UnpackMemory where
  outputCell : CellId
  packedCell : CellId
  cursorCell : CellId
  earlier : List Int
  untouched : List Int
  packedValues : List Int
  storage : List UInt8
  bytes : List UInt8
  encoded : encodeI32Array (signedI32Values packedValues) = .ok storage
  sourceBytes : storage.take bytes.length = bytes
  capacity : bytes.length ≤ untouched.length
  bounded : earlier.length + untouched.length ≤ 2147483647
  output_cursor : outputCell ≠ cursorCell
  packed_output : packedCell ≠ outputCell
  packed_cursor : packedCell ≠ cursorCell

def UnpackMemory.writes (memory : UnpackMemory) :=
  CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell)

structure UnpackInvariant (memory : UnpackMemory) (locals : UnpackLocals)
    (processed : List UInt8) (state : State) : Prop where
  wellFormed : StateWellFormed state
  outputLocal : state.local? locals.output = some
    (.slice (.scalar (.signed .i32)) memory.outputCell [] 0
      (memory.earlier.length + memory.untouched.length))
  outputContents : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array
      (signedI32Values (copiedBuffer memory.earlier memory.untouched processed))) }
  packedLocal : state.local? locals.packed = some
    (.slice (.scalar (.signed .i32)) memory.packedCell [] 0 memory.packedValues.length)
  packedContents : state.cellEntry? memory.packedCell = some {
    id := memory.packedCell, value := some (.array (signedI32Values memory.packedValues)) }
  cursor : (Assertion.localPointsTo locals.cursor memory.cursorCell
    (some (.signed .i32 processed.length))).holds state
  total : state.local? locals.total = some (.signed .i32 memory.earlier.length)
  limit : state.local? locals.length = some (.signed .i32 memory.bytes.length)
  stable : ∀ localId, localId ∈ [locals.output, locals.packed, locals.total, locals.length] →
    ∀ cell, state.cellId? localId = some cell → ¬ memory.writes cell

private theorem body_step (program : Program) (memory : UnpackMemory) (locals : UnpackLocals)
    (processed remaining : List UInt8) (byte : UInt8) (before : State)
    (source : memory.bytes = processed ++ byte :: remaining)
    (invariant : UnpackInvariant memory locals processed before) :
    ∃ after, Executes program before locals.body .next after ∧
      UnpackInvariant memory locals (processed ++ [byte]) after ∧
      ModifiesOnly memory.writes before after := by
  have sourceLength : memory.bytes.length = processed.length + 1 + remaining.length := by
    simp [source]; omega
  have room : processed.length < memory.untouched.length := by
    have := memory.capacity
    omega
  have byteSelected : memory.storage[processed.length]? = some byte := by
    have atByte := congrArg (fun bytes : List UInt8 => bytes[processed.length]?) memory.sourceBytes
    have bound : processed.length < memory.bytes.length := by omega
    simpa [List.getElem?_take, bound, source] using atByte
  obtain ⟨after, executed, afterWF, afterContents, afterCursor, effect⟩ :=
    executes_unpacking_body program before locals memory.outputCell memory.packedCell
      memory.cursorCell memory.earlier memory.untouched memory.packedValues processed
      memory.storage byte room memory.bounded memory.output_cursor invariant.wellFormed
      invariant.outputLocal invariant.outputContents invariant.packedLocal invariant.packedContents
      memory.encoded byteSelected invariant.total invariant.cursor
  refine ⟨after, executed, ?_, effect⟩
  refine ⟨afterWF, ?_, afterContents, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · exact effect.preserves_local invariant.wellFormed invariant.outputLocal
      (invariant.stable _ (by simp))
  · exact effect.preserves_local invariant.wellFormed invariant.packedLocal
      (invariant.stable _ (by simp))
  · exact effect.preserves_entry invariant.wellFormed invariant.packedContents
      (by simp [CellSet.union, CellSet.singleton, memory.packed_output, memory.packed_cursor])
  · simpa using afterCursor
  · exact effect.preserves_local invariant.wellFormed invariant.total
      (invariant.stable _ (by simp))
  · exact effect.preserves_local invariant.wellFormed invariant.limit
      (invariant.stable _ (by simp))
  · intro localId member cell found
    apply invariant.stable localId member cell
    simpa [State.cellId?, effect.locals] using found

private theorem condition_result (program : Program) (memory : UnpackMemory)
    (locals : UnpackLocals) (processed : List UInt8) (state : State)
    (invariant : UnpackInvariant memory locals processed state) :
    Evaluates program state
      (.binary .notEqual (.local locals.cursor) (.local locals.length))
      (.boolean (!(Int.ofNat processed.length == Int.ofNat memory.bytes.length))) state := by
  have cursorResult : Evaluates program state (.local locals.cursor)
      (.signed .i32 processed.length) state :=
    ⟨1, evalLocal_of_local 0 program state locals.cursor _
      (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  have lengthResult : Evaluates program state (.local locals.length)
      (.signed .i32 memory.bytes.length) state :=
    ⟨1, evalLocal_of_local 0 program state locals.length _ invariant.limit⟩
  apply evaluatesEagerBinary (by decide) (by decide) cursorResult lengthResult
  simp [evalBinaryValue, scalarEqual]

/-- Total correctness of the actual input-unpacking loop. All byte reads and
array updates are derived from the invariant; the unprocessed byte count is
the termination measure. No correctness assumption is made for an iteration. -/
theorem executes_unpacking_loop (program : Program) (memory : UnpackMemory)
    (locals : UnpackLocals) (processed remaining : List UInt8) (before : State)
    (source : memory.bytes = processed ++ remaining)
    (invariant : UnpackInvariant memory locals processed before) :
    ∃ after, Executes program before locals.loop .next after ∧
      UnpackInvariant memory locals memory.bytes after ∧
      ModifiesOnly memory.writes before after := by
  have condition := condition_result program memory locals processed before invariant
  cases remaining with
  | nil =>
      have complete : memory.bytes = processed := by simpa using source
      refine ⟨before, executesWhileFalse ?_, ?_, ModifiesOnly.reflAny _ _⟩
      · simpa [complete] using condition
      · simpa [complete] using invariant
  | cons byte rest =>
      have different : processed.length ≠ memory.bytes.length := by
        simp only [source, List.length_append, List.length_cons]
        omega
      have conditionTrue : Evaluates program before
          (.binary .notEqual (.local locals.cursor) (.local locals.length))
          (.boolean true) before := by
        have differentInt : Int.ofNat processed.length ≠ Int.ofNat memory.bytes.length := by
          intro equal
          exact different (Int.ofNat.inj equal)
        rw [beq_eq_false_iff_ne.mpr differentInt] at condition
        exact condition
      obtain ⟨middle, body, nextInvariant, bodyEffect⟩ :=
        body_step program memory locals processed rest byte before source invariant
      have nextSource : memory.bytes = (processed ++ [byte]) ++ rest := by
        simpa [List.append_assoc] using source
      obtain ⟨after, loop, complete, loopEffect⟩ :=
        executes_unpacking_loop program memory locals (processed ++ [byte]) rest middle
          nextSource nextInvariant
      exact ⟨after, executesWhileTrue conditionTrue body loop, complete,
        bodyEffect.trans_same loopEffect⟩
termination_by remaining.length

/-- Soundness for any observed execution, independently of the chosen fuel. -/
theorem unpacking_loop_sound (program : Program) (memory : UnpackMemory)
    (locals : UnpackLocals) (processed remaining : List UInt8) (before after : State)
    (source : memory.bytes = processed ++ remaining)
    (invariant : UnpackInvariant memory locals processed before)
    (actual : Executes program before locals.loop completion after) :
    completion = .next ∧ UnpackInvariant memory locals memory.bytes after ∧
      ModifiesOnly memory.writes before after := by
  obtain ⟨expected, executed, complete, effect⟩ :=
    executes_unpacking_loop program memory locals processed remaining before source invariant
  obtain ⟨sameCompletion, sameState⟩ := Lanius.Fuel.executes_deterministic actual executed
  subst after
  exact ⟨sameCompletion, complete, effect⟩

end Lanius.Extraction.Input
