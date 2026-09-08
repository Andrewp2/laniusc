import Lanius.Extraction.Parser.Derivation.Transport
import Lanius.Extraction.VerifiedFrontend.Parser.Soundness
import Lanius.FunctionalViewCoreSimulation

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize
open Lanius.FunctionalView.Core

def readerValues (workspaceValues outputValues : List Int)
    (workspaceCell outputCell : CellId) (tokenCount stateCount stateId offset : Nat) : List Value :=
  [.slice parserI32Type workspaceCell [] 0 workspaceValues.length,
   .signed .i32 (Int.ofNat workspaceValues.length),
   .signed .i32 (Int.ofNat tokenCount), .signed .i32 (Int.ofNat stateCount),
   .signed .i32 (Int.ofNat stateId),
   .slice parserI32Type outputCell [] 0 outputValues.length,
   .signed .i32 (Int.ofNat outputValues.length), .signed .i32 (Int.ofNat offset)]

def readerBindings (workspaceValues outputValues : List Int)
    (workspaceCell outputCell : CellId) (tokenCount stateCount stateId offset : Nat) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 8 =>
    (readerValues workspaceValues outputValues workspaceCell outputCell tokenCount stateCount stateId offset).get index)

def readerCallee (caller : State) (workspaceValues outputValues : List Int)
    (workspaceCell outputCell : CellId) (tokenCount stateCount stateId offset : Nat) : State :=
  enterCall caller (readerBindings workspaceValues outputValues workspaceCell outputCell
    tokenCount stateCount stateId offset)

theorem reader_parameters (wellFormed : StateWellFormed caller) (index : Fin 8) :
    (readerCallee caller workspaceValues outputValues workspaceCell outputCell
      tokenCount stateCount stateId offset).local? index.val =
      some ((readerValues workspaceValues outputValues workspaceCell outputCell
        tokenCount stateCount stateId offset).get index) :=
  enterCall_parameterBindings_matches wellFormed index

/-- Construct the reader's physical entry from caller-owned arrays. Parameter
    cells are allocated by the call semantics; no private-local ownership is assumed. -/
theorem CheckedReader.enter (reader : CheckedReader program)
    (wellFormed : StateWellFormed caller)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell caller)
    (output : caller.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) }) :
    (reader.runtime layout workspace workspaceValues outputValues workspaceCell outputCell offset).Entry
      (readerCallee caller workspaceValues outputValues workspaceCell outputCell layout.tokenCount stateCount stateId offset) := by
  have parameters := reader_parameters (workspaceValues := workspaceValues) (outputValues := outputValues)
    (workspaceCell := workspaceCell) (outputCell := outputCell) (tokenCount := layout.tokenCount)
    (stateCount := stateCount) (stateId := stateId) (offset := offset) wellFormed
  have preserve {cell : CellId} {value : Value}
      (backing : caller.cellEntry? cell = some { id := cell, value := some value }) :
      (readerCallee caller workspaceValues outputValues workspaceCell outputCell layout.tokenCount
        stateCount stateId offset).cellEntry? cell = some { id := cell, value := some value } :=
    ((enterCall_effect caller _).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  refine ⟨enterCall_preserves_wellFormed wellFormed,
    ⟨artifact.workspaceLength, artifact.workspaceEncoded, preserve artifact.workspaceBacking⟩,
    ?_, ?_, parameters ⟨7, by decide⟩, parameters ⟨2, by decide⟩, preserve output⟩
  · change (readerCallee caller workspaceValues outputValues workspaceCell outputCell layout.tokenCount
      stateCount stateId offset).local? reader.stores.locals.output = _
    rw [reader.bufferParameters.2]
    exact parameters ⟨5, by decide⟩
  · change (readerCallee caller workspaceValues outputValues workspaceCell outputCell layout.tokenCount
      stateCount stateId offset).local? reader.stores.locals.workspace = _
    rw [reader.bufferParameters.1]
    exact parameters ⟨0, by decide⟩

private theorem output_partition (values : List Int)
    (fits : offset + 4 + count * 3 ≤ values.length) :
    ∃ leading a b c d pending trailing,
      values = leading ++ [a, b, c, d] ++ pending ++ trailing ∧
      leading.length = offset ∧ pending.length = count * 3 := by
  have prefixLength : (values.take offset).length = offset := by
    rw [List.length_take]; omega
  have available : 4 + count * 3 ≤ (values.drop offset).length := by
    rw [List.length_drop]; omega
  have split := (List.take_append_drop offset values).symm
  cases suffix : values.drop offset with
  | nil => simp [suffix] at available
  | cons a rest =>
    cases rest with
    | nil => simp [suffix] at available; omega
    | cons b rest =>
      cases rest with
      | nil => simp [suffix] at available; omega
      | cons c rest =>
        cases rest with
        | nil => simp [suffix] at available; omega
        | cons d rest =>
          refine ⟨values.take offset, a, b, c, d, rest.take (count * 3), rest.drop (count * 3), ?_, prefixLength, ?_⟩
          · simpa only [suffix, List.append_assoc, List.cons_append, List.nil_append,
              List.take_append_drop] using split
          · simp only [suffix, List.length_cons] at available
            rw [List.length_take]; omega

/-- Execute the complete reader for any resident state in a sound workspace.
    This covers recursive tree children as well as the selected whole-input root. -/
theorem CheckedReader.execute_state (reader : CheckedReader program)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (wellFormed : StateWellFormed caller)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell caller)
    (layoutTokens : layout.tokenCount = tokens.length)
    (output : caller.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (distinctBuffers : outputCell ≠ workspaceCell)
    (capacityBound : outputValues.length ≤ 2147483647)
    (fits : offset + 4 + state.dot * 3 ≤ outputValues.length) :
    ∃ children after, children.length = state.dot ∧
      derivationChildren? workspace (stateId + 1) stateId = some children ∧
      Executes verifiedParserCore
        (readerCallee caller workspaceValues outputValues workspaceCell outputCell
          layout.tokenCount workspace.states.length stateId offset)
        reader.standaloneBody (.returned (some (.signed .i32 (Int.ofNat state.dot)))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (outputValues.take offset ++ derivationRecordWords state children ++
            outputValues.drop (offset + 4 + state.dot * 3)))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      CellEffect (CellSet.singleton outputCell)
        (readerCallee caller workspaceValues outputValues workspaceCell outputCell
          layout.tokenCount workspace.states.length stateId offset) after := by
  have entry := reader.enter (offset := offset) (stateCount := workspace.states.length) (stateId := stateId) wellFormed artifact output
  have parameters := reader_parameters (workspaceValues := workspaceValues) (outputValues := outputValues)
    (workspaceCell := workspaceCell) (outputCell := outputCell) (tokenCount := layout.tokenCount)
    (stateCount := workspace.states.length) (stateId := stateId) (offset := offset) wellFormed
  obtain ⟨leading, a, b, c, d, pending, trailing, contents, offsetEq, pendingLength⟩ := output_partition outputValues fits
  have names := reader.namesDistinct
  have workspaceParameter := reader.bufferParameters.1
  have outputParameter := reader.bufferParameters.2
  simp only [readerLocals, List.nodup_cons] at names
  obtain ⟨children, after, length, computed, execution, written, retained, effect⟩ :=
    entry.execute (grammar := grammar) (tokens := tokens) (countId := 9) (productionId := 10) (originId := 11)
      rfl rfl sound found rfl
      (parameters ⟨1, by decide⟩) (parameters ⟨4, by decide⟩) (parameters ⟨3, by decide⟩)
      (getElem?_some_implies_bound found) artifact.workspaceEncoded.stateCountFits (parameters ⟨6, by decide⟩)
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, ReaderRuntime.readonlyLocals, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, ReaderRuntime.readonlyLocals, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, ReaderRuntime.readonlyLocals, ne_comm])
      layoutTokens distinctBuffers capacityBound
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, CheckedReader.standaloneTail, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, ReaderRuntime.readonlyLocals, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, CheckedReader.standaloneTail, ReaderRuntime.readonlyLocals, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, CheckedReader.standaloneTail, ne_comm])
      (by exact reader.slot_distinct)
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, CheckedReader.standaloneTail, ReaderRuntime.liveLocals, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, CheckedReader.standaloneTail, ReaderRuntime.liveLocals, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, CheckedReader.standaloneTail, ReaderRuntime.liveLocals, ne_comm])
      (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, CheckedReader.standaloneTail, ne_comm])
      contents offsetEq pendingLength
  have leadingEq : leading = outputValues.take offset := by
    rw [contents, ← offsetEq]; simp [List.append_assoc]
  have trailingEq : trailing = outputValues.drop (offset + 4 + state.dot * 3) := by
    have prefixLength : (leading ++ [a, b, c, d] ++ pending).length = offset + 4 + state.dot * 3 := by
      simp [offsetEq, pendingLength]; omega
    rw [contents, ← prefixLength, List.drop_left]
  refine ⟨children, after, length, computed, ?_, ?_, retained, effect⟩
  · rw [← reader.runtime_body (layout := layout) (workspace := workspace)
      (workspaceValues := workspaceValues) (outputValues := outputValues)
      (workspaceCell := workspaceCell) (outputCell := outputCell) (offset := offset)]
    exact execution
  · simpa only [CheckedReader.runtime, leadingEq, trailingEq] using written

/-- Consume the actual public recognizer result. The reader's root membership,
    backpointer soundness, state bounds, and unchanged output storage are all
    derived here; only the caller's original storage and output capacity remain. -/
theorem CheckedReader.read_recognizer_root (reader : CheckedReader program)
    (recognition : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout initialWorkspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments)
    (success : parseResultStatus? recognition.outcome.resultValue = some 0)
    (wellFormed : StateWellFormed afterArguments)
    (layoutTokens : workspaceLayout.tokenCount = tokens.length)
    (output : afterArguments.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (distinctBuffers : outputCell ≠ workspaceCell)
    (capacityBound : outputValues.length ≤ 2147483647)
    (fits : offset + 4 + (recognition.successRoot success).root.dot * 3 ≤ outputValues.length) :
    let root := recognition.successRoot success
    ∃ children after, children.length = root.root.dot ∧
      derivationChildren? recognition.finalWorkspace (root.rootState + 1) root.rootState = some children ∧
      Executes verifiedParserCore
        (readerCallee recognition.after recognition.finalWorkspaceValues outputValues workspaceCell outputCell
          workspaceLayout.tokenCount recognition.finalWorkspace.states.length root.rootState offset)
        reader.standaloneBody (.returned (some (.signed .i32 (Int.ofNat root.root.dot)))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (outputValues.take offset ++ derivationRecordWords root.root children ++
            outputValues.drop (offset + 4 + root.root.dot * 3)))) } ∧
      RecognizerWorkspaceArtifact workspaceLayout recognition.finalWorkspace
        recognition.finalWorkspaceValues workspaceCell after ∧
      CellEffect (CellSet.singleton outputCell)
        (readerCallee recognition.after recognition.finalWorkspaceValues outputValues workspaceCell outputCell
          workspaceLayout.tokenCount recognition.finalWorkspace.states.length root.rootState offset) after := by
  have unchanged := (recognition.effect.oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed output) distinctBuffers).trans output
  exact reader.execute_state (recognition.successRoot success).stored.backpointersSound
    (recognition.successRoot success).found
    (recognition.preservesWellFormed wellFormed) recognition.workspaceArtifact layoutTokens
    unchanged distinctBuffers capacityBound fits

end Lanius.Extraction.ParserDerivation
