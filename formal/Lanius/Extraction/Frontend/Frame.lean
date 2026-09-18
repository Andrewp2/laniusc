import Lanius.Extraction.Frontend.Capacity.Post

namespace Lanius.Extraction.Frontend
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.ParserTreeSource Lanius.Extraction.ParserRecognize

theorem SyntaxData.grammar_untouched {data : SyntaxData} (valid : data.Valid) : ¬ data.writes data.grammarCell := by
  intro changed
  rcases changed with ((raw | canonical) | (kinds | workspace)) | (records | offsets)
  · exact valid.grammarRaw raw
  · exact valid.grammarCanonical canonical
  · exact valid.grammarKinds kinds
  · exact valid.grammarWorkspace workspace
  · exact (valid.outputSeparation data.grammarCell (by simp)).1 records
  · exact (valid.outputSeparation data.grammarCell (by simp)).2 offsets

theorem SyntaxData.writes_in_roots {data : SyntaxData} (written : data.writes cell) : cell ∈ data.bufferRoots := by
  rcases written with ((rfl | rfl) | (rfl | rfl)) | (rfl | rfl) <;>
    simp [SyntaxData.bufferRoots, SyntaxData.buffers]

/-- Every caller cell the frontend can change is an owned array backing.
A scalar, pointer, or slice local cannot alias one of those array values. -/
theorem SyntaxData.PaddedOwns.written_array {data : SyntaxData} {tail : List Int}
    (owned : data.PaddedOwns tail before) (written : data.writes cell) :
    ∃ words : List Int, before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values words)) } := by
  rcases written with ((rfl | rfl) | (rfl | rfl)) | (rfl | rfl)
  · exact ⟨_, owned (data.rawCell, data.records) (by simp [SyntaxData.buffers])⟩
  · exact ⟨_, owned (data.canonicalCell, data.canonical) (by simp [SyntaxData.buffers])⟩
  · exact ⟨_, owned (data.kindsCell, data.kinds) (by simp [SyntaxData.buffers])⟩
  · exact ⟨_, owned (data.workspaceCell, data.workspaceValues) (by simp [SyntaxData.buffers])⟩
  · exact ⟨_, owned (data.recordsCell, data.treeRecords) (by simp [SyntaxData.buffers])⟩
  · exact ⟨_, owned (data.offsetsCell, data.treeOffsets) (by simp [SyntaxData.buffers])⟩

theorem SyntaxData.PaddedOwns.preserves_local {data : SyntaxData} {tail : List Int} {id : VarId}
    (owned : data.PaddedOwns tail before) (wellFormed : StateWellFormed before)
    (effect : CellEffect data.writes before after) (found : before.local? id = some value)
    (notArray : ∀ elements, value ≠ .array elements) : after.local? id = some value := by
  apply effect.preserves_local wellFormed found
  intro cell binding written
  obtain ⟨words, stored⟩ := owned.written_array written
  exact local_cell_ne_of_distinct_value found stored (notArray _) binding rfl

theorem syntaxPost_preserved
    (post : syntaxPost outcome workspace records offsets recordsCell offsetsCell depth stage detail nodes words position before)
    (wellFormed : StateWellFormed before) (effect : CellEffect CellSet.empty before (restoreLocals before after)) :
    syntaxPost outcome workspace records offsets recordsCell offsetsCell depth stage detail nodes words position after := by
  rcases post with ⟨stageEq, failed, nodesEq, wordsEq, states, root, parsed, recordOutput, offsetOutput, absent⟩ |
    ⟨root, stageEq, positionEq, output, successWhenFits⟩
  · exact Or.inl ⟨stageEq, failed, nodesEq, wordsEq, states, root, parsed,
      effect.empty_preserves_entry wellFormed recordOutput, effect.empty_preserves_entry wellFormed offsetOutput, absent⟩
  · exact Or.inr ⟨root, stageEq, positionEq,
      output.preserved (after := restoreLocals before after) wellFormed effect (by simp [CellSet.empty]) (by simp [CellSet.empty]), successWhenFits⟩

/-- Successful frontend facts depend on the retained buffers, not the new
local mappings introduced by result accessors and caller bindings. -/
theorem SyntaxData.Post.preserved_success {data : SyntaxData}
    (post : data.Post stage detail count nodes words position initial before) (success : stage = 0)
    (wellFormed : StateWellFormed before) (effect : CellEffect CellSet.empty before (restoreLocals before after)) :
    data.Post stage detail count nodes words position initial after := by
  rcases post with early | ⟨completed, capacity, countEq, canonical, storage |
    ⟨kindsFit, kinds, completion, outcome, workspace, values, parsed, artifact⟩⟩
  · rcases early.1.stage with failed | failed <;> omega
  · have failed := storage.2.1
    omega
  · exact Or.inr ⟨completed, capacity, countEq, effect.empty_preserves_entry wellFormed canonical,
      Or.inr ⟨kindsFit, effect.empty_preserves_entry wellFormed kinds, completion, outcome, workspace, values,
        syntaxPost_preserved parsed wellFormed effect,
        ⟨artifact.workspaceLength, artifact.workspaceEncoded, effect.empty_preserves_entry wellFormed artifact.workspaceBacking⟩⟩⟩

theorem SyntaxData.PaddedRawOutput.preserved {data : SyntaxData} {tail : List Int}
    (raw : data.PaddedRawOutput tail before) (wellFormed : StateWellFormed before)
    (effect : CellEffect CellSet.empty before (restoreLocals before after)) : data.PaddedRawOutput tail after := by
  intro cell words found
  exact effect.empty_preserves_entry wellFormed (raw cell words found)

end Lanius.Extraction.Frontend
