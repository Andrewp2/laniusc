import Lanius.Separation.SliceStore

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- Copy one i32 between caller-owned slices. The source is read before the
destination is changed; distinct backing cells guarantee source preservation.
Indices are independent, so this also covers extracting token-kind columns. -/
theorem evaluatesSliceCopy (program : Program) (before : State)
    (source destination : List Int) (sourceId destinationId : VarId)
    (sourceCell destinationCell : CellId) (sourceIndex destinationIndex : Nat)
    (sourceExpression destinationExpression : Expr)
    (wellFormed : StateWellFormed before)
    (distinct : sourceCell ≠ destinationCell)
    (sourceBound : sourceIndex < source.length)
    (destinationBound : destinationIndex < destination.length)
    (sourceLocal : before.local? sourceId = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (destinationLocal : before.local? destinationId = some
      (.slice (.scalar (.signed .i32)) destinationCell [] 0 destination.length))
    (sourceResult : Evaluates program before sourceExpression
      (.signed .i32 sourceIndex) before)
    (destinationResult : Evaluates program before destinationExpression
      (.signed .i32 destinationIndex) before)
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (destinationContents : before.cellEntry? destinationCell = some {
      id := destinationCell, value := some (.array (signedI32Values destination)) }) :
    ∃ after, Evaluates program before
        (.assign .set (.index (.local destinationId) destinationExpression)
          (.index (.local sourceId) sourceExpression)) .unit after ∧
      after.cellEntry? destinationCell = some {
        id := destinationCell,
        value := some (.array (signedI32Values
          (destination.set destinationIndex (source.get ⟨sourceIndex, sourceBound⟩)))) } ∧
      after.cellEntry? sourceCell = some {
        id := sourceCell,
        value := some (.array (signedI32Values source)) } ∧
      CellEffect (CellSet.singleton destinationCell) before after := by
  have sourceEvaluation : Evaluates program before (.local sourceId)
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length) before :=
    ⟨1, evalLocal_of_local 0 program before sourceId _ sourceLocal⟩
  have read := evaluatesSignedI32SliceIndex program before before before source
    (.local sourceId) sourceExpression sourceCell sourceIndex sourceBound
    sourceEvaluation sourceResult sourceContents
  obtain ⟨after, copied, contents, effect⟩ := evaluatesSliceStore program before before
    destination destinationId destinationExpression (.index (.local sourceId) sourceExpression)
    destinationCell destinationIndex (source.get ⟨sourceIndex, sourceBound⟩)
    wellFormed destinationBound destinationLocal destinationResult read
    (CellEffect.refl wellFormed) destinationContents
  exact ⟨after, copied, contents,
    effect.preserves_entry wellFormed sourceContents distinct, effect⟩

end Lanius.Separation
