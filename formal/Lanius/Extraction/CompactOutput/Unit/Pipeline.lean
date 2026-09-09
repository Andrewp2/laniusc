import Lanius.Extraction.CompactOutput.Unit.Arguments
import Lanius.Extraction.SemanticTokens.Pipeline
import Lanius.Extraction.CompactDecode.Acceptance.Unit

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens
open Lanius.Extraction.CanonicalTokens.CanonicalizeModel

private theorem literal_arguments (program : Program) (state : State) (values : List Value) :
    ArgumentsEvaluateTo program state (values.map Expr.value) values state := by
  induction values with
  | nil => exact .nil _ _
  | cons value values ih => exact .cons ⟨1, rfl⟩ ih

/-- Consume the proved collector continuation and execute the real unit
emitter. The surrounding main/I/O control flow is a separate obligation. -/
theorem collection_then_emit (emission : Emission)
    (word : Word.Checked program byte digit)
    (bytes : Bytes.Checked program byte digit hex)
    (tokens : Tokens.Checked program byte digit word)
    (semantic : Assignments.Checked program byte digit word)
    (nodes : Nodes.Checked program byte digit word tokenTag stateTag)
    (checked : Checked program ⟨word.source.function.id, bytes.source.function.id,
      tokens.source.function.id, semantic.source.function.id, nodes.source.function.id⟩)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (continuation : CollectionContinuation program.core collectorId emission.data emission.count emission.nodes emission.words
      emission.semanticCell emission.semanticOriginal before extracted)
    (valid : emission.data.Valid) (kindsFit : emission.data.grammar.grammar.n_kinds ≤ 32768)
    (post : emission.data.Post stage detail emission.count emission.nodes emission.words position before extracted)
    (raw : emission.data.RawOutput extracted) (success : stage = 0)
    (wellFormed : StateWellFormed extracted)
    (path : I32Prefix extracted emission.pathCell emission.pathCapacity (sourceIntegers emission.path))
    (output : extracted.cellEntry? emission.outputCell = some {
      id := emission.outputCell, value := some (.array (signedI32Values emission.original)) })
    (collectorSeparate : ∀ cell ∈ [emission.pathCell, emission.data.sourceCell, emission.data.rawCell,
      emission.data.canonicalCell, emission.data.recordsCell, emission.data.offsetsCell], cell ≠ emission.semanticCell)
    (pathFit : emission.path.length ≤ 2147483647)
    (semanticFit : emission.semanticOriginal.length ≤ 2147483647)
    (semanticRoom : emission.count * 2 ≤ emission.semanticOriginal.length)
    (capacityFit : emission.capacity ≤ 2147483647) (room : emission.capacity ≤ emission.original.length)
    (separate : ∀ cell ∈ [emission.pathCell, emission.data.sourceCell, emission.data.rawCell,
      emission.data.canonicalCell, emission.semanticCell, emission.data.recordsCell, emission.data.offsetsCell],
      emission.outputCell ≠ cell) :
    ∃ result : FrontendResult emission.data emission.count emission.nodes emission.words extracted,
    ∃ collection : CollectionRecords emission.data.grammar (artifactTokens emission.data.tokens) result.parse.tree 0 0,
    ∃ collected emitted,
      Evaluates program.core extracted (.call collectorId
        ((collectorValues emission.data emission.count emission.nodes emission.words emission.semanticCell emission.semanticOriginal).map Expr.value))
        (.signed .i32 0) collected ∧
      Evaluates program.core collected (.call checked.source.function.id (emission.values.map Expr.value))
        (.signed .i32 (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
          emission.position emission.original).position) emitted ∧
      emitted.cellEntry? emission.outputCell = some {
        id := emission.outputCell, value := some (.array (signedI32Values
          (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
            emission.position emission.original).contents)) } ∧
      CellEffect (CellSet.union (CellSet.union emission.data.writes (CellSet.singleton emission.semanticCell))
        (CellSet.singleton emission.outputCell)) before emitted ∧
      ∀ path : String, path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val →
        emission.data.grammar.grammar = laniusGrammar →
        (CompactDecode.emissionUnit emission path collection.assignments collection.records).Encodable ∧
        checkParseArtifact (CompactDecode.emissionUnit emission path collection.assignments collection.records).artifact = true ∧
        ∀ (bytes : ByteArray) (position : Nat), emission.position = position →
          position + (emission.encoding collection.assignments collection.records).length ≤ emission.capacity →
          bytes.toList.map (fun b => Int.ofNat b.toNat) =
            (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
              emission.position emission.original).contents.take
              (position + (emission.encoding collection.assignments collection.records).length) →
          CompactDecode.readArtifact.run {bytes, offset := position} =
            some ((CompactDecode.emissionUnit emission path collection.assignments collection.records).artifact,
              {bytes, offset := position + (emission.encoding collection.assignments collection.records).length}) := by
  obtain ⟨result, collection, collected, _, _, _, collectorCall, contents, collectorEffect, frontendEffect⟩ := continuation
  have storage : Storage emission result collection collected := Storage.of_collection valid kindsFit post raw success
    wellFormed collectorEffect
    (fun cell member => collectorSeparate cell (List.mem_cons_of_mem _ member))
    (by simpa only [if_pos semanticRoom] using contents)
    (path.preserved wellFormed collectorEffect (collectorSeparate _ (by simp)))
    (collectorEffect.preserves_entry wellFormed output (separate _ (by simp)))
    pathFit semanticFit semanticRoom capacityFit room separate
  obtain ⟨emitted, emitterCall, output, emitterEffect⟩ := storage.write word bytes tokens semantic nodes checked
    tokenConstant stateConstant collectorEffect.wellFormed (literal_arguments program.core collected emission.values)
  refine ⟨result, collection, collected, emitted, by simpa only [if_pos semanticRoom] using collectorCall,
    emitterCall, output,
    (frontendEffect.weaken CellSet.subset_union_left).trans (emitterEffect.weaken CellSet.subset_union_right), ?_⟩
  intro path pathBytes sameGrammar
  refine ⟨CompactDecode.storage_encodable storage collectorEffect.wellFormed path pathBytes
      (CompactDecode.collection_productions result.parse collection sameGrammar),
    CompactDecode.frontend_artifact_accepted emission result collection post success sameGrammar kindsFit path, ?_⟩
  intro bytes position positionEq capacity backing
  exact CompactDecode.storage_decode_same_grammar storage collectorEffect.wellFormed path pathBytes sameGrammar
    position positionEq capacity backing

end Lanius.Extraction.CompactOutput.Unit
