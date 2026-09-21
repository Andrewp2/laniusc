import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer
import Lanius.Semantics.CallerFrame

namespace Lanius.Semantics

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
/-! A small bridge for read-only scanner inputs.

    `sourceI32Values` is the mathematical byte-to-i32 encoding used by the
    scanner callers.  `SourceSlice` records only the local and its backing
    array; it deliberately does not include any bounds or successful
    evaluation premise.  This keeps those obligations visible to the loop
    proofs that consume this API.
-/

def sourceI32Values (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

def i32ArrayValues (values : List Int) : List Value :=
  values.map fun value => .signed .i32 value

def i32SliceValue (cell : CellId) (values : List Int) : Value :=
  .slice (.scalar (.signed .i32)) cell [] 0 values.length

def sourceSliceValue (cell : CellId) (source : List Byte) : Value :=
  i32SliceValue cell (sourceI32Values source)

structure SourceBacking (state : State) (cell : CellId) (values : List Int) : Prop where
  backingFound : state.cellEntry? cell = some
    { id := cell, value := some (.array (i32ArrayValues values)) }

def SourceByteBacking (state : State) (cell : CellId) (source : List Byte) : Prop :=
  SourceBacking state cell (sourceI32Values source)

theorem FreshCellFrame.cellEntryFound
    {before after : State} (frame : FreshCellFrame before after)
    {cell : CellId} {entry : Cell}
    (found : before.cellEntry? cell = some entry) :
    after.cellEntry? cell = some entry := by
  rcases frame with ⟨extra, cells, _, _⟩
  unfold State.cellEntry? at found ⊢
  rw [cells, List.find?_append]
  simp only [found, Option.some_or]

theorem SourceBacking.afterFrame
    {before after : State} {cell : CellId} {values : List Int}
    (source : SourceBacking before cell values)
    (frame : FreshCellFrame before after) :
    SourceBacking after cell values :=
  ⟨frame.cellEntryFound source.backingFound⟩

theorem SourceBacking.afterCallerFrame
    {caller current : State} {cell : CellId} {values : List Int}
    (source : SourceBacking caller cell values)
    (frame : CallerFrame caller current) :
    SourceBacking current cell values :=
  source.afterFrame frame.cells

structure SourceSlice (state : State) (localId : VarId) (cell : CellId)
    (values : List Int) : Prop where
  localFound : state.local? localId = some (i32SliceValue cell values)
  backingFound : SourceBacking state cell values

def SourceBytes (state : State) (localId : VarId) (cell : CellId)
    (source : List Byte) : Prop :=
  SourceSlice state localId cell (sourceI32Values source)

theorem SourceSlice.afterFrame
    {before after : State} {localId : VarId} {cell : CellId} {values : List Int}
    (source : SourceSlice before localId cell values)
    (frame : FreshCellFrame before after)
    (locals : after.locals = before.locals) :
    SourceSlice after localId cell values := by
  exact ⟨frame.localFound locals localId _ source.localFound,
    source.backingFound.afterFrame frame⟩

theorem SourceSlice.ofBacking
    {state : State} (localId : VarId) (cell : CellId) (values : List Int)
    (localFound : state.local? localId = some (i32SliceValue cell values))
    (backing : SourceBacking state cell values) :
    SourceSlice state localId cell values :=
  { localFound, backingFound := backing }

theorem SourceSlice.afterPureFrame
    {before after : State} {localId : VarId} {cell : CellId} {values : List Int}
    (source : SourceSlice before localId cell values)
    (frame : PureFrame before after) :
    SourceSlice after localId cell values :=
  source.afterFrame frame.cells frame.locals

theorem SourceSlice.afterCallerFrame
    {caller current : State} {localId : VarId} {cell : CellId} {values : List Int}
    (source : SourceSlice caller localId cell values)
    (frame : CallerFrame caller current)
    (localFound : current.local? localId = some (i32SliceValue cell values)) :
    SourceSlice current localId cell values :=
  ⟨localFound, source.backingFound.afterCallerFrame frame⟩

theorem evalBinaryValue_i32_less
    (target : Target) (left right : Nat) :
    evalBinaryValue target .less
      (.signed .i32 (Int.ofNat left)) (.signed .i32 (Int.ofNat right)) =
      .ok (.boolean (decide (left < right))) := by
  simp [evalBinaryValue, evalSignedBinary]

theorem evalExpr_i32_slice_index
    (fuel : Nat) (program : Program) (state : State)
    (cell : CellId) (values : List Int) (position : Nat)
    (backing : state.cellEntry? cell = some
      { id := cell, value := some (.array (i32ArrayValues values)) })
    (inBounds : position < values.length) :
    evalExpr fuel.succ.succ program state
        (.index (.value (i32SliceValue cell values))
          (.value (.signed .i32 (Int.ofNat position)))) =
      .done (.signed .i32 (values.get ⟨position, inBounds⟩)) state := by
  rw [evalExpr.eq_def]
  simp only [evalExpr_value, i32SliceValue]
  have sliced : sliceValues state cell [] 0 values.length =
      .ok (i32ArrayValues values) := by
    simpa [sliceValues, readCellProjection, backing, projectedValue,
      i32ArrayValues] using (List.take_length (l := i32ArrayValues values))
  have nonnegative : ¬(Int.ofNat position < 0) :=
    Int.not_lt_of_ge (Int.natCast_nonneg position)
  simp only [integerIndex, nonnegative, if_false]
  rw [sliced] <;> simp_all [i32ArrayValues]

private theorem evalExpr_i32_slice_index_of_evaluations
    (fuel : Nat) (program : Program) (state : State)
    (sourceExpr cursorExpr : Expr) (cell : CellId) (values : List Int)
    (position : Nat)
    (sourceEval : evalExpr fuel.succ program state sourceExpr =
      .done (i32SliceValue cell values) state)
    (cursorEval : evalExpr fuel.succ program state cursorExpr =
      .done (.signed .i32 (Int.ofNat position)) state)
    (backing : state.cellEntry? cell = some
      { id := cell, value := some (.array (i32ArrayValues values)) })
    (inBounds : position < values.length) :
    evalExpr fuel.succ.succ program state (.index sourceExpr cursorExpr) =
      .done (.signed .i32 (values.get ⟨position, inBounds⟩)) state := by
  rw [evalExpr.eq_def]
  simp only [sourceEval, i32SliceValue, cursorEval]
  exact evalExpr_i32_slice_index fuel program state cell values position backing inBounds

theorem evalExpr_source_slice_index
    (fuel : Nat) (program : Program) (before after : State)
    (localId : VarId) (cell : CellId) (values : List Int) (position : Nat)
    (source : SourceSlice before localId cell values)
    (frame : FreshCellFrame before after)
    (locals : after.locals = before.locals)
    (inBounds : position < values.length) :
    SourceSlice after localId cell values ∧
      evalExpr fuel.succ.succ program after
          (.index (.local localId)
            (.value (.signed .i32 (Int.ofNat position)))) =
        .done (.signed .i32 (values.get ⟨position, inBounds⟩)) after := by
  refine ⟨source.afterFrame frame locals, ?_⟩
  exact evalExpr_i32_slice_index_of_evaluations fuel program after
    (.local localId) (.value (.signed .i32 (Int.ofNat position))) cell values position
    (evalExpr_local_of_local? fuel program after localId _
      (source.afterFrame frame locals).localFound)
    (evalExpr_value fuel program after _)
    (frame.cellEntryFound source.backingFound.backingFound) inBounds

theorem evalExpr_source_slice_index_of_locals
    (program : Program) (state : State) (sourceId cursorId : VarId)
    (cell : CellId) (values : List Int) (position : Nat)
    (source : SourceSlice state sourceId cell values)
    (cursorFound : state.local? cursorId =
      some (.signed .i32 (Int.ofNat position)))
    (inBounds : position < values.length) :
    ∀ fuel, 2 ≤ fuel → evalExpr fuel program state
      (.index (.local sourceId) (.local cursorId)) =
        .done (.signed .i32 (values.get ⟨position, inBounds⟩)) state := by
  intro fuel enough
  let base := fuel - 2
  have sourceEval := evalExpr_local_of_local? base program state sourceId
    (i32SliceValue cell values) source.localFound
  have cursorEval := evalExpr_local_of_local? base program state cursorId
    (.signed .i32 (Int.ofNat position)) cursorFound
  simpa only [show base.succ.succ = fuel by dsimp [base]; omega] using
    (evalExpr_i32_slice_index_of_evaluations base program state
      (.local sourceId) (.local cursorId) cell values position
      sourceEval cursorEval source.backingFound.backingFound inBounds)

end Lanius.Semantics
