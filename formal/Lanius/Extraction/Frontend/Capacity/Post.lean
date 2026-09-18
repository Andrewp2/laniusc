import Lanius.Extraction.Frontend.Capacity.Input

namespace Lanius.Extraction.Frontend
open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.FunctionalView.Core Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserTreeSource

theorem syntaxPost_expanded (config : Semantics.Capacity.Config)
    (recordsApart : recordsCell ≠ config.root) (offsetsApart : offsetsCell ≠ config.root)
    (post : syntaxPost outcome workspace records offsets recordsCell offsetsCell depth stage detail nodes words position after) :
    syntaxPost outcome workspace records offsets recordsCell offsetsCell depth stage detail nodes words position (Semantics.Capacity.state config after) := by
  rcases post with ⟨stageEq, failed, nodesEq, wordsEq, states, root, parsed, recordOutput, offsetOutput, absent⟩ |
    ⟨root, stageEq, positionEq, output, successWhenFits⟩
  · exact Or.inl ⟨stageEq, failed, nodesEq, wordsEq, states, root, parsed,
      Semantics.Capacity.cellEntry_plain config recordsApart (Semantics.Capacity.signedValues_plain _) recordOutput,
      Semantics.Capacity.cellEntry_plain config offsetsApart (Semantics.Capacity.signedValues_plain _) offsetOutput, absent⟩
  · refine Or.inr ⟨root, stageEq, positionEq, ?_, successWhenFits⟩
    rcases output with ⟨status, nodesStart, nodesBound, wordsStart, wordsBound, success⟩
    refine ⟨status, nodesStart, nodesBound, wordsStart, wordsBound, ?_⟩
    intro accepted
    obtain ⟨nodesExact, wordsExact, recordsExact, offsetsExact⟩ := success accepted
    exact ⟨nodesExact, wordsExact,
      Semantics.Capacity.cellEntry_plain config recordsApart (Semantics.Capacity.signedValues_plain _) (before := after) recordsExact,
      Semantics.Capacity.cellEntry_plain config offsetsApart (Semantics.Capacity.signedValues_plain _) (before := after) offsetsExact⟩

theorem SyntaxData.Post.expanded {data : SyntaxData} (config : Semantics.Capacity.Config)
    (sourceRoot : config.root = data.sourceCell) (valid : data.Valid)
    (post : data.Post stage detail count nodes words position before after) :
    data.Post stage detail count nodes words position (Semantics.Capacity.state config before) (Semantics.Capacity.state config after) := by
  have canonicalApart : data.canonicalCell ≠ config.root := by simpa only [sourceRoot] using valid.sourceCanonical.symm
  have kindsApart : data.kindsCell ≠ config.root := by simpa only [sourceRoot] using valid.sourceKinds.symm
  have workspaceApart : data.workspaceCell ≠ config.root := by simpa only [sourceRoot] using valid.sourceWorkspace.symm
  have recordsApart : data.recordsCell ≠ config.root := by
    simpa only [sourceRoot] using (valid.outputSeparation data.sourceCell (by simp)).1.symm
  have offsetsApart : data.offsetsCell ≠ config.root := by
    simpa only [sourceRoot] using (valid.outputSeparation data.sourceCell (by simp)).2.symm
  rcases post with ⟨early, countEq, nodesEq, wordsEq, effect⟩ |
    ⟨completed, capacity, countEq, canonical, storage | ⟨kindsFit, kinds, completion, outcome, workspace, values, parsed, artifact⟩⟩
  · exact Or.inl ⟨early, countEq, nodesEq, wordsEq, Semantics.Capacity.effect config effect⟩
  · obtain ⟨full, stageEq, detailEq, nodesEq, wordsEq, positionEq, effect⟩ := storage
    exact Or.inr ⟨completed, capacity, countEq,
      Semantics.Capacity.cellEntry_plain config canonicalApart (Semantics.Capacity.signedValues_plain _) canonical,
      Or.inl ⟨full, stageEq, detailEq, nodesEq, wordsEq, positionEq, Semantics.Capacity.effect config effect⟩⟩
  · exact Or.inr ⟨completed, capacity, countEq,
      Semantics.Capacity.cellEntry_plain config canonicalApart (Semantics.Capacity.signedValues_plain _) canonical,
      Or.inr ⟨kindsFit, Semantics.Capacity.cellEntry_plain config kindsApart (Semantics.Capacity.signedValues_plain _) kinds,
        completion, outcome, workspace, values, syntaxPost_expanded config recordsApart offsetsApart parsed,
        ⟨artifact.workspaceLength, artifact.workspaceEncoded,
          Semantics.Capacity.cellEntry_plain config workspaceApart (Semantics.Capacity.signedValues_plain _) artifact.workspaceBacking⟩⟩⟩

def SyntaxData.PaddedRawOutput (data : SyntaxData) (tail : List Int) (after : State) : Prop :=
  (ReadOnly.World.owns (ReadOnly.World.pair data.sourceCell
    (CanonicalTokens.CanonicalizeModel.sourceIntegers data.request.source ++ tail) data.rawCell
    (CanonicalTokens.CanonicalizeModel.encodeTokens data.raw ++ data.records.drop (3 * data.raw.length)))).holds after

theorem SyntaxData.PaddedOwns.raw_expanded {data : SyntaxData} (owned : data.PaddedOwns tail before)
    (valid : data.Valid) (wellFormed : StateWellFormed after) (raw : data.RawOutput after) :
    data.PaddedRawOutput tail (Semantics.Capacity.state owned.input.config after) := by
  have sourceFound := raw data.sourceCell _ (ReadOnly.World.pair_finds_first)
  have rawFound := raw data.rawCell _ (ReadOnly.World.pair_finds_second valid.sourceRaw.symm)
  have sourceOutput : (Semantics.Capacity.state owned.input.config after).cellEntry? data.sourceCell =
      some { id := data.sourceCell, value := some (.array (signedI32Values
        (CanonicalTokens.CanonicalizeModel.sourceIntegers data.request.source ++ tail))) } := by
    simp only [Semantics.Capacity.cellEntry, sourceFound, Option.map_some, Semantics.Capacity.cell,
      Semantics.Capacity.stored, Semantics.Capacity.Input.config, SyntaxData.PaddedOwns.input,
      ↓reduceIte, Semantics.Capacity.plains_fixed _ _ (Semantics.Capacity.signedValues_plain _)]
    simp only [signedI32Values, List.map_append]
  exact (ReadOnly.World.owns_iff_represents (Semantics.Capacity.state_wellFormed owned.input.config wellFormed)).mpr
    (ReadOnly.World.pair_represents (Semantics.Capacity.state_wellFormed owned.input.config wellFormed)
      valid.sourceRaw.symm sourceOutput
      (Semantics.Capacity.cellEntry_plain owned.input.config valid.sourceRaw.symm
        (Semantics.Capacity.signedValues_plain _) rawFound))

end Lanius.Extraction.Frontend
