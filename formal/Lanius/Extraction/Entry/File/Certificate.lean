import Lanius.Extraction.Entry.File.Handoff
import Lanius.Extraction.CompactOutput.Outcome
import Lanius.Extraction.CompactDecode.Acceptance.Unit
import Lanius.Extraction.CompactDecode.Contracts
import Lanius.Extraction.CompactDecode.Grammar
import Lanius.Extraction.CompactDecode.Units

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens Lanius.Extraction.CompactOutput

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before ready collected after : State}
variable {input : Load.Input pipeline before} {data : SyntaxData}

/-- The successful file body has appended one complete, accepted syntax
unit for this exact path and file. Prefix and unused suffix are unchanged.
This is evidence produced by execution, not an assumed accepted certificate. -/
def Emitted (input : Load.Input pipeline before) (output : SavedBuffer input)
    (position : Int) (cursor : VarId) (after : State) : Prop :=
  ∃ unit : CompactDecode.UnitData,
    unit.Encodable ∧ unit.nodes ≠ [] ∧ checkParseArtifact unit.artifact = true ∧
    unit.artifact.sources = [{ path := input.path, bytes := input.file.bytes.map UInt8.toNat }] ∧
    0 ≤ position ∧ position.toNat + unit.encoding.length ≤ 16777216 ∧
    after.cellEntry? output.view.root = some { id := output.view.root, value := some (.array (signedI32Values
      (output.contents.take position.toNat ++ unit.encoding.map Int.ofNat ++
        output.contents.drop (position.toNat + unit.encoding.length)))) } ∧
    (restoreLocals before after).local? cursor = some (.signed .i32 (position.toNat + unit.encoding.length : Nat))

theorem Emitted.restore (emitted : Emitted input output position cursor after) (caller : State) :
    Emitted input output position cursor (restoreLocals caller after) := emitted

/-- Connect the actual frontend/collector result and emitter guard to the
accepted unit and the exact appended interval. The successful return derives
the interval bounds; no extra successful-serialization premise is introduced. -/
theorem certified_output {resultId cursor : VarId} {typeId : TypeId} {position : Int} {positionCell : CellId}
    (observed : FrontendReturn input data) (success : observed.status = 0)
    (buffers : Load.FrontendBuffers input data)
    (sameGrammar : data.grammar.grammar = laniusGrammar)
    (scopeEffect : CellEffect CellSet.empty (observed.bound resultId typeId)
      (restoreLocals (observed.bound resultId typeId) ready))
    (semantic output : SavedBuffer input)
    (result : FrontendResult data observed.count observed.nodes observed.words ready)
    (collection : CollectionRecords data.grammar (artifactTokens data.tokens) result.parse.tree 0 0)
    (storage : Unit.Storage (Emit.emission observed semantic output position) result collection collected)
    (wellFormed : StateWellFormed collected)
    (nonnegative : 0 ≤ (appendAll 16777216 ((Emit.emission observed semantic output position).encoding
      collection.assignments collection.records) position output.contents).position)
    (positionBinding : before.cellId? cursor = some positionCell)
    (positionOwned : (Assertion.localPointsTo cursor positionCell (some (.signed .i32
      (appendAll 16777216 ((Emit.emission observed semantic output position).encoding
        collection.assignments collection.records) position output.contents).position))).holds after)
    (contents : after.cellEntry? output.view.root = some { id := output.view.root, value := some (.array (signedI32Values
      (appendAll 16777216 ((Emit.emission observed semantic output position).encoding
        collection.assignments collection.records) position output.contents).contents)) }) :
    Emitted input output position cursor after := by
  let emission := Emit.emission observed semantic output position
  let unit := CompactDecode.emissionUnit emission input.path collection.assignments collection.records
  have pathBytes : input.path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val := by
    simp only [emission, Emit.emission, Lanius.World.utf8Bytes, List.map_map, Function.comp_def, UInt8.toFin_val]
    exact congrArg (List.map UInt8.toNat) (CompactDecode.byteArray_toList _)
  have encoding : unit.encoding = emission.encoding collection.assignments collection.records :=
    CompactDecode.emission_encoding emission input.path collection.assignments collection.records pathBytes
  have nonempty : unit.encoding ≠ [] := by
    intro empty
    have minimum := CompactDecode.unit_encoding_min_length unit
    rw [empty] at minimum
    simp only [List.length_nil] at minimum
    omega
  have bounds := appendAll_nonnegative_bounds unit.encoding nonempty
    (show 0 ≤ (appendAll 16777216 unit.encoding position output.contents).position by
      simpa only [encoding] using nonnegative)
  have cast : (position.toNat : Int) = position := Int.toNat_of_nonneg bounds.1
  have appended := appendAll_success 16777216 position.toNat unit.encoding output.contents bounds.2 storage.room
  rw [cast] at appended
  have actual : appendAll 16777216 (emission.encoding collection.assignments collection.records) position output.contents =
      .done (position.toNat + unit.encoding.length : Nat)
        (output.contents.take position.toNat ++ unit.encoding.map Int.ofNat ++
          output.contents.drop (position.toNat + unit.encoding.length)) := by
    rw [← encoding]
    exact appended
  refine ⟨unit,
    CompactDecode.storage_encodable storage wellFormed input.path pathBytes
      (CompactDecode.collection_productions result.parse collection sameGrammar),
    (by
      change collection.records ≠ []
      have positive := collection.nonempty result.parse
      intro empty
      rw [empty] at positive
      simp only [List.length_nil] at positive
      omega),
    CompactDecode.frontend_artifact_accepted emission result collection (observed.post_ready success scopeEffect)
      success sameGrammar storage.kindsFit input.path, ?_, bounds.1, bounds.2, ?_, ?_⟩
  · change ([{ path := input.path, bytes := (CompactDecode.sourceArray data.request.source).toList.map UInt8.toNat }] : List SourceFile) = _
    rw [CompactDecode.sourceArray_values, buffers.sourceBytes]
    simp only [List.map_map, Function.comp_def, UInt8.toFin_val]
  · change after.cellEntry? output.view.root = some { id := output.view.root, value := some (.array (signedI32Values
      (appendAll 16777216 (emission.encoding collection.assignments collection.records) position output.contents).contents)) } at contents
    simpa only [actual, AppendOutcome.contents] using contents
  · have owned : (Assertion.localPointsTo cursor positionCell
        (some (.signed .i32 (position.toNat + unit.encoding.length : Nat)))).holds after := by
      change (Assertion.localPointsTo cursor positionCell (some (.signed .i32
        (appendAll 16777216 (emission.encoding collection.assignments collection.records) position output.contents).position))).holds after at positionOwned
      simpa only [actual, AppendOutcome.position] using positionOwned
    exact Assertion.localPointsTo_local _ _ _ _ ⟨positionBinding, owned.2⟩

end Lanius.Extraction.Entry.File
