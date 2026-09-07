import Lanius.Extraction.OutputPacking.Body

namespace Lanius.Extraction.OutputPacking

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure LoopMemory where
  workspaceCell : CellId
  inputCell : CellId
  cursorCell : CellId
  bytes : List UInt8
  inputTail : List Int
  tail : List Int
  bounded : bytes.length ≤ 2147483647
  workspace_cursor : workspaceCell ≠ cursorCell
  input_workspace : inputCell ≠ workspaceCell
  input_cursor : inputCell ≠ cursorCell

def LoopMemory.words (memory : LoopMemory) := (memory.bytes.length + 3) / 4
def LoopMemory.writes (memory : LoopMemory) :=
  CellSet.union (CellSet.singleton memory.workspaceCell) (CellSet.singleton memory.cursorCell)
def LoopMemory.inputValues (memory : LoopMemory) : List Int :=
  memory.bytes.map (fun byte => (byte.toNat : Int)) ++ memory.inputTail

structure LoopInvariant (memory : LoopMemory) (locals : LoopLocals)
    (processed : List UInt8) (state : State) : Prop where
  wellFormed : StateWellFormed state
  workspaceLocal : state.local? locals.workspace = some
    (.slice (.scalar (.signed .i32)) memory.workspaceCell [] 0
      (memory.words + memory.tail.length))
  workspaceContents : state.cellEntry? memory.workspaceCell = some {
    id := memory.workspaceCell
    value := some (.array (workspace memory.words processed (signedI32Values memory.tail))) }
  inputLocal : state.local? locals.input = some
    (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length)
  inputContents : state.cellEntry? memory.inputCell = some {
    id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) }
  cursor : (Assertion.localPointsTo locals.cursor memory.cursorCell
    (some (.signed .i32 processed.length))).holds state
  limit : state.local? locals.length = some (.signed .i32 memory.bytes.length)
  stable : ∀ localId, localId ∈ [locals.workspace, locals.input, locals.length] →
    ∀ cell, state.cellId? localId = some cell → ¬ memory.writes cell

private theorem body_step (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    (processed remaining : List UInt8) (byte : UInt8) (before : State)
    (source : memory.bytes = processed ++ byte :: remaining)
    (invariant : LoopInvariant memory locals processed before) :
    ∃ after, Executes program before locals.body .next after ∧
      LoopInvariant memory locals (processed ++ [byte]) after ∧
      ModifiesOnly memory.writes before after := by
  have sourceLength : memory.bytes.length = processed.length + 1 + remaining.length := by
    simp [source]; omega
  have byteBound : processed.length < memory.inputValues.length := by
    simp only [LoopMemory.inputValues, List.length_append, List.length_map]
    omega
  have cursorBound : processed.length + 1 ≤ 2147483647 := by
    have := memory.bounded
    omega
  have room : (processed.length + 4) / 4 ≤ memory.words := by
    dsimp [LoopMemory.words]
    omega
  have packedBound : (pack processed).length ≤ memory.words := by
    rw [pack_length]
    omega
  obtain ⟨values, contents⟩ := workspace_as_i32_values memory.words processed memory.tail
  have valuesLength : values.length = memory.words + memory.tail.length := by
    have lengths := congrArg List.length contents
    rw [workspace_length _ _ _ packedBound] at lengths
    simpa [signedI32Values] using lengths
  have cursorResult : Evaluates program before (.local locals.cursor)
      (.signed .i32 processed.length) before :=
    ⟨1, evalLocal_of_local 0 program before locals.cursor _
      (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  have inputResult : Evaluates program before (.local locals.input)
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length) before := by
    refine ⟨1, evalLocal_of_local 0 program before locals.input _ ?_⟩
    simpa [LoopMemory.inputValues] using invariant.inputLocal
  have selected : memory.inputValues.get ⟨processed.length, byteBound⟩ = byte.toNat := by
    simp [LoopMemory.inputValues, source]
  have byteResult := evaluatesSignedI32SliceIndex program before before before
    memory.inputValues (.local locals.input) (.local locals.cursor)
    memory.inputCell processed.length byteBound inputResult cursorResult invariant.inputContents
  rw [selected] at byteResult
  obtain ⟨after, executed, afterWF, afterContents, afterCursor, effect⟩ :=
    executes_packing_body program before values locals memory.workspaceCell memory.cursorCell
      memory.words processed byte (signedI32Values memory.tail) room cursorBound
      memory.workspace_cursor invariant.wellFormed contents
      (by simpa [valuesLength] using invariant.workspaceLocal)
      (by simpa [contents] using invariant.workspaceContents)
      invariant.cursor byteResult
  refine ⟨after, executed, ?_, effect⟩
  refine ⟨afterWF, ?_, afterContents, ?_, ?_, ?_, ?_, ?_⟩
  · exact effect.preserves_local invariant.wellFormed invariant.workspaceLocal
      (invariant.stable _ (by simp))
  · exact effect.preserves_local invariant.wellFormed invariant.inputLocal
      (invariant.stable _ (by simp))
  · exact effect.preserves_entry invariant.wellFormed invariant.inputContents
      (by simp [CellSet.union, CellSet.singleton,
        memory.input_workspace, memory.input_cursor])
  · simpa using afterCursor
  · exact effect.preserves_local invariant.wellFormed invariant.limit
      (invariant.stable _ (by simp))
  · intro localId member cell found
    apply invariant.stable localId member cell
    simpa [State.cellId?, effect.locals] using found

private theorem condition_result (program : Program) (memory : LoopMemory)
    (locals : LoopLocals) (processed : List UInt8) (state : State)
    (invariant : LoopInvariant memory locals processed state) :
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

/-- Total correctness of the complete packing loop from any processed prefix.
The remaining input length is the termination measure. Every byte is read
from the preserved input cell; no per-iteration correctness assumptions remain.
The caller must establish the initial zeroed-workspace/ownership invariant. -/
theorem executes_packing_loop (program : Program) (memory : LoopMemory)
    (locals : LoopLocals) (processed remaining : List UInt8) (before : State)
    (source : memory.bytes = processed ++ remaining)
    (invariant : LoopInvariant memory locals processed before) :
    ∃ after, Executes program before locals.loop .next after ∧
      LoopInvariant memory locals memory.bytes after ∧
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
        have unequal : (Int.ofNat processed.length == Int.ofNat memory.bytes.length) = false :=
          beq_eq_false_iff_ne.mpr differentInt
        rw [unequal] at condition
        exact condition
      obtain ⟨middle, body, nextInvariant, bodyEffect⟩ :=
        body_step program memory locals processed rest byte before source invariant
      have nextSource : memory.bytes = (processed ++ [byte]) ++ rest := by
        simpa [List.append_assoc] using source
      obtain ⟨after, loop, complete, loopEffect⟩ :=
        executes_packing_loop program memory locals (processed ++ [byte]) rest middle
          nextSource nextInvariant
      exact ⟨after, executesWhileTrue conditionTrue body loop, complete,
        bodyEffect.trans_same loopEffect⟩
termination_by remaining.length

/-- The completed invariant is exactly the packed output plus the untouched
workspace tail. The clearing padding disappears when every byte is processed. -/
theorem LoopInvariant.complete_contents
    (invariant : LoopInvariant memory locals memory.bytes state) :
    state.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell
      value := some (.array (pack memory.bytes ++ signedI32Values memory.tail)) } := by
  simpa [workspace, pack_length, LoopMemory.words] using invariant.workspaceContents

/-- Soundness for any observed execution follows from total correctness and
the deterministic Core semantics; the caller need not use our chosen fuel. -/
theorem packing_loop_sound (program : Program) (memory : LoopMemory)
    (locals : LoopLocals) (processed remaining : List UInt8) (before after : State)
    (source : memory.bytes = processed ++ remaining)
    (invariant : LoopInvariant memory locals processed before)
    (actual : Executes program before locals.loop completion after) :
    completion = .next ∧ LoopInvariant memory locals memory.bytes after ∧
      ModifiesOnly memory.writes before after := by
  obtain ⟨expected, executed, complete, effect⟩ :=
    executes_packing_loop program memory locals processed remaining before source invariant
  obtain ⟨sameCompletion, sameState⟩ := Lanius.Fuel.executes_deterministic actual executed
  subst after
  exact ⟨sameCompletion, complete, effect⟩

end Lanius.Extraction.OutputPacking
