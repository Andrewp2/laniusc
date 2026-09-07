import Lanius.Extraction.CanonicalTokens.Compaction.Store

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The two slices visible to compaction, including their full capacities. -/
structure Storage (state : State) (sourceCell recordsCell : CellId) (source records : List Int) : Prop where
  wellFormed : StateWellFormed state
  sourceLocal : state.local? 0 = some (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length)
  recordsLocal : state.local? 1 = some (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length)
  sourceContents : state.cellEntry? sourceCell = some {
    id := sourceCell, value := some (.array (signedI32Values source)) }
  recordsContents : state.cellEntry? recordsCell = some {
    id := recordsCell, value := some (.array (signedI32Values records)) }
  sourceFits : source.length ≤ 2147483647
  recordsFit : records.length ≤ 2147483647

theorem Storage.preserved (storage : Storage before sourceCell recordsCell source records)
    (effect : CellEffect CellSet.empty before after) : Storage after sourceCell recordsCell source records :=
  ⟨effect.wellFormed,
    effect.empty_preserves_local storage.wellFormed storage.sourceLocal,
    effect.empty_preserves_local storage.wellFormed storage.recordsLocal,
    effect.empty_preserves_entry storage.wellFormed storage.sourceContents,
    effect.empty_preserves_entry storage.wellFormed storage.recordsContents,
    storage.sourceFits, storage.recordsFit⟩

theorem Storage.bind (storage : Storage before sourceCell recordsCell source records)
    (id : VarId) (value : Value) (notSource : id ≠ 0) (notRecords : id ≠ 1) :
    Storage (before.bindLocal id value) sourceCell recordsCell source records := by
  have effect := bindLocal_effect before id value
  refine ⟨bindLocal_preserves_well_formed before id value storage.wellFormed,
    (bindLocal_preserves_other_local storage.wellFormed notSource).trans storage.sourceLocal,
    (bindLocal_preserves_other_local storage.wellFormed notRecords).trans storage.recordsLocal,
    ?_, ?_, storage.sourceFits, storage.recordsFit⟩
  · exact (effect.oldCells sourceCell
      (StateWellFormed.cell_lt_next_of_entry storage.wellFormed storage.sourceContents)
      (by simp [CellSet.empty])).trans storage.sourceContents
  · exact (effect.oldCells recordsCell
      (StateWellFormed.cell_lt_next_of_entry storage.wellFormed storage.recordsContents)
      (by simp [CellSet.empty])).trans storage.recordsContents

theorem Storage.readIndex (storage : Storage before sourceCell recordsCell source records)
    (expression : Expr) (index : Nat) (value : Int)
    (indexResult : Evaluates program before expression (.signed .i32 (Int.ofNat index)) before)
    (bound : index < records.length) (selected : records[index]? = some value) :
    Evaluates program before (read expression) (.signed .i32 value) before := by
  have sliceResult : Evaluates program before (.local 1)
      (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length) before :=
    ⟨1, evalLocal_of_local 0 program before 1 _ storage.recordsLocal⟩
  have readResult := evaluatesSignedI32SliceIndex program before before before records (.local 1)
    expression recordsCell index bound sliceResult indexResult storage.recordsContents
  have actual : records.get ⟨index, bound⟩ = value := by
    simpa only [List.getElem?_eq_getElem bound, Option.some.injEq, List.get_eq_getElem] using selected
  simpa only [actual, Compaction.read] using readResult

theorem Storage.readLocal (storage : Storage before sourceCell recordsCell source records)
    (id : VarId)
    (base offset : Nat) (value : Int)
    (baseLocal : before.local? id = some (.signed .i32 base))
    (bound : base + offset < records.length)
    (selected : records[base + offset]? = some value) :
    Evaluates program before (read (add (.local id) (literal offset))) (.signed .i32 value) before := by
  have baseResult : Evaluates program before (.local id) (.signed .i32 base) before :=
    ⟨1, evalLocal_of_local 0 program before id _ baseLocal⟩
  have offsetResult : Evaluates program before (literal offset) (.signed .i32 offset) before := ⟨1, rfl⟩
  have indexResult := evaluatesNatI32Add baseResult offsetResult (by have := storage.recordsFit; omega)
  exact storage.readIndex _ _ _ indexResult bound selected

end Lanius.Extraction.CanonicalTokens.Compaction
