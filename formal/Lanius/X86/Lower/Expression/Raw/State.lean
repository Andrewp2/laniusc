import Lanius.X86.Lower.Expression.Literal.State
import Lanius.Separation.LocalStore

namespace Lanius.X86.Lower.Expression.Raw

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.X86.Buffer

def cursorWrites (output work cursor : CellId) : CellSet :=
  CellSet.union (Literal.writes output work) (CellSet.singleton cursor)

/-- A source emitter updates the output array, then the assignment updates
its fresh cursor local. Neither operation can change the input bindings or
workspace. Physical-cell freshness, not unequal integer values, frames the
cursor update. -/
theorem update_cursor
    {id : VarId}
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (owned : (Assertion.localPointsTo id cursor (some (.signed .i32 previous))).holds before)
    (fresh : frontier ≤ cursor)
    (right : Evaluates program before expression (.signed .i32 next) middle)
    (effect : CellEffect (CellSet.singleton output) before middle)
    (written : middle.cellEntry? output =
      some { id := output, value := some (.array (signedI32Values emitted)) }) :
    ∃ after,
      Evaluates program before (.assign .set (.local id) expression) .unit after ∧
      Literal.Ready after bindings frontier input output work transport emitted workspace ∧
      (Assertion.localPointsTo id cursor (some (.signed .i32 next))).holds after ∧
      CellEffect (cursorWrites output work cursor) before after ∧
      HeapFrame middle after := by
  have cursorOutput : cursor ≠ output := local_cell_ne_of_distinct_value
    (Assertion.localPointsTo_local id cursor _ before owned) ready.outputBacking
    (by intro equal; cases equal) owned.1
  have nextReady := ready.frame (effect.weaken CellSet.subset_union_left) written
    (effect.preserves_entry ready.wellFormed ready.workBacking (Ne.symm ready.outputWork))
  have retained := effect.preserves_localPointsTo ready.wellFormed owned cursorOutput
  obtain ⟨after, run, updated, total, heap, assigned⟩ := evaluatesFramedLocalUpdate
    (op := .set) (replacement := .signed .i32 next)
    ready.wellFormed owned right effect cursorOutput (by simp [evalAssignValue, assignOpBinary?])
  have different (cell : CellId) (contents : List Int)
      (found : middle.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values contents)) }) :
      cell ≠ cursor :=
    Ne.symm (local_cell_ne_of_distinct_value
      (Assertion.localPointsTo_local id cursor _ middle retained) found
      (by intro equal; cases equal) retained.1)
  refine ⟨after, run, ?_, updated, total.weaken ?_, heap⟩
  · exact ⟨assigned.wellFormed, nextReady.locals.fresh nextReady.wellFormed assigned fresh,
      nextReady.plain,
      assigned.preserves_entry nextReady.wellFormed nextReady.inputBacking
        (different input transport nextReady.inputBacking),
      assigned.preserves_entry nextReady.wellFormed nextReady.outputBacking
        (different output emitted nextReady.outputBacking),
      assigned.preserves_entry nextReady.wellFormed nextReady.workBacking
        (different work workspace nextReady.workBacking),
      nextReady.inputOutput, nextReady.inputWork, nextReady.outputWork⟩
  · intro cell changed
    rcases changed with output | cursor
    · exact Or.inl (Or.inl output)
    · exact Or.inr cursor

end Lanius.X86.Lower.Expression.Raw
