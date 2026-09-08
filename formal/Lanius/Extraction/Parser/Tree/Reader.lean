import Lanius.Extraction.Parser.Tree.Source
import Lanius.Extraction.Parser.Tree.Derivation
import Lanius.Extraction.Parser.Derivation.Recognition

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserDerivation
open Lanius.Extraction.ParserTreeDerivation

/-- Invoke the materializer's actual reader from the current caller state and
    retain the exact correspondence to its selected semantic children. The
    inverse type map handles unrelated caller values; no runtime state-shape
    or successful reader-execution premise is imposed. -/
theorem CheckedVisit.read_children {symbols : Core.Relocation.Symbols} (checked : CheckedVisit program)
    (linked : LinkedReader checked.reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType symbols.typeId)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (treeEnough : stateId < treeFuel)
    (materialized : materializeStatePrefix? grammar workspace treeFuel stateId = some trees)
    (wellFormed : StateWellFormed caller)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell caller)
    (layoutTokens : layout.tokenCount = tokens.length)
    (output : caller.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (distinctBuffers : outputCell ≠ workspaceCell)
    (capacityBound : outputValues.length ≤ 2147483647)
    (fits : offset + 4 + state.dot * 3 ≤ outputValues.length)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (readerValues workspaceValues outputValues workspaceCell outputCell layout.tokenCount
        workspace.states.length stateId offset) caller) :
    ∃ children after, children.length = state.dot ∧ trees.length = state.dot ∧
      derivationChildren? workspace (stateId + 1) stateId = some children ∧
      ChildrenExpansion grammar workspace children trees ∧
      Evaluates program.core caller (.call checked.symbols.reader arguments)
        (.signed .i32 (Int.ofNat state.dot)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (outputValues.take offset ++ derivationRecordWords state children ++
            outputValues.drop (offset + 4 + state.dot * 3)))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      CellEffect (CellSet.singleton outputCell) caller after := by
  let unrelocate : Core.Relocation.Symbols := ⟨inverseType, id, id⟩
  have restored : Semantics.Relocation.state symbols (Semantics.Relocation.state unrelocate caller) = caller :=
    Semantics.Relocation.state_leftInverse symbols unrelocate inverse caller
  have call := linked.call_state sound found
    (Semantics.Relocation.state_wellFormed unrelocate wellFormed)
    (relocate_workspace unrelocate artifact) layoutTokens (relocate_words unrelocate output)
    distinctBuffers capacityBound fits (by simpa only [restored] using argumentsResult)
  rw [restored] at call
  obtain ⟨children, after, length, computed, evaluation, written, retained, effect⟩ := call
  have matched := children_match sound found (Nat.lt_succ_self _) treeEnough computed materialized
  refine ⟨children, after, length, matched.length.symm.trans length, computed, matched, ?_, written, retained, effect⟩
  rw [checked.identities.2.1]
  exact evaluation

end Lanius.Extraction.ParserTreeSource
