import Lanius.Extraction.CanonicalTokens.Dispatch.Branches

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The full table-driven body, including its checked end-minus-start local.
Its result is the first matching rule of the selected length or the fallback. -/
theorem executes_body (program : Program) (matcher fallback : Nat)
    (before : State) (sourceCell : CellId) (source : List Int) (start width : Nat) (groups : List Group)
    (found : program.function? matcher = some (Ascii.sourceFunction matcher))
    (valid : ∀ group ∈ groups, ∀ rule ∈ group.rules, ValidRule program group.width rule)
    (fallbackFound : program.constant? fallback = some {
      id := fallback, type := .scalar (.signed .i32), value := .signed .i32 (tag program fallback) })
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (startLocal : before.local? 1 = some (.signed .i32 start))
    (endLocal : before.local? 2 = some (.signed .i32 (start + width)))
    (capacity : start + width ≤ source.length) (bounded : source.length ≤ 2147483647) :
    ∃ after, Executes program before (body matcher fallback groups)
      (.returned (some (.signed .i32 (dispatched program source start width fallback groups)))) after ∧
      CellEffect CellSet.empty before after := by
  have startResult : Evaluates program before (.local 1) (.signed .i32 start) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ startLocal⟩
  have endResult : Evaluates program before (.local 2) (.signed .i32 (start + width)) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ endLocal⟩
  have difference : Evaluates program before (.binary .subtract (.local 2) (.local 1))
      (.signed .i32 width) before := by
    simpa only [Nat.add_sub_cancel_left, Int.ofNat_eq_natCast] using
      evaluatesNatI32Subtract endResult startResult (Nat.le_add_right _ _) (by omega)
  let entered := before.bindLocal 3 (.signed .i32 width)
  have enteredWF := bindLocal_preserves_well_formed before 3 (.signed .i32 width) wellFormed
  have enterEffect := bindLocal_effect before 3 (.signed .i32 width)
  have sourceOld := StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents
  have sourceReady : entered.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) } :=
    (enterEffect.oldCells sourceCell sourceOld (by simp [CellSet.empty])).trans sourceContents
  obtain ⟨completed, run, frame⟩ := executes_branches program matcher fallback entered sourceCell source
    start width groups found valid fallbackFound enteredWF
    ((bindLocal_preserves_other_local wellFormed (show 3 ≠ 0 by decide)).trans sourceLocal)
    sourceReady ((bindLocal_preserves_other_local wellFormed (show 3 ≠ 1 by decide)).trans startLocal)
    (bindLocal_finds_local before 3 (.signed .i32 width) wellFormed) capacity bounded
  have domain := enterEffect.domain.trans frame.domain
  refine ⟨restoreLocals before completed, executesLetLocal difference run, ?_⟩
  refine ⟨domain.restoreLocals_wellFormed wellFormed frame.wellFormed, rfl,
    frame.world.trans enterEffect.world, ?_, Nat.le_trans enterEffect.nextCell frame.nextCell,
    domain.restoreLocals⟩
  intro cell old _
  exact (frame.empty_preserves_cell cell (Nat.lt_of_lt_of_le old enterEffect.nextCell)).trans
    (enterEffect.oldCells cell old (by simp [CellSet.empty]))

end Lanius.Extraction.CanonicalTokens.Dispatch
