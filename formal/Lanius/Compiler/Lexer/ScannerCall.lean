import Lanius.Compiler.Lexer.ArtifactScanners
import Lanius.Semantics.Arithmetic
import Lanius.Semantics.Bindings
import Lanius.Semantics.Loop
import Lanius.Semantics.MutableLocal
import Lanius.Semantics.ReadOnlySlice

namespace Lanius.Compiler.Lexer

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

/-! Generic setup for the three arguments of an artifact scanner call.  This
    file stops at the callee entry state; scanner loops and predicate calls are
    separate contracts. -/

def scannerArgumentValues (cell : CellId) (source : List Byte) (start : Nat) : List Value :=
  [sourceSliceValue cell source,
    .signed .i32 (Int.ofNat source.length),
    .signed .i32 (Int.ofNat start)]

def scannerArgumentExpressions (cell : CellId) (source : List Byte) (start : Nat) : List Expr :=
  (scannerArgumentValues cell source start).map Expr.value

def scannerBindings (cell : CellId) (source : List Byte) (start : Nat) : List (VarId × Value) :=
  [(0, sourceSliceValue cell source),
   (1, .signed .i32 (Int.ofNat source.length)),
   (2, .signed .i32 (Int.ofNat start))]

def scannerCallee (caller : State) (cell : CellId) (source : List Byte) (start : Nat) : State :=
  ({ caller with locals := [] }).bindLocals (scannerBindings cell source start)

theorem scannerCallee_localFacts (caller : State) (cell : CellId) (source : List Byte)
    (start : Nat) (formed : caller.CellsWellFormed) :
    (scannerCallee caller cell source start).local? 0 =
        some (sourceSliceValue cell source) ∧
      (scannerCallee caller cell source start).local? 1 =
      some (.signed .i32 (Int.ofNat source.length)) := by
  exact ⟨by simpa [scannerCallee] using State.bindLocals_local?_get? ({ caller with locals := [] }) (scannerBindings cell source start) (fun item member => formed item member) (by simp [scannerBindings]) 0 (0, sourceSliceValue cell source) (by simp [scannerBindings]),
    by simpa [scannerCallee] using State.bindLocals_local?_get? ({ caller with locals := [] }) (scannerBindings cell source start) (fun item member => formed item member) (by simp [scannerBindings]) 1 (1, .signed .i32 (Int.ofNat source.length)) (by simp [scannerBindings])⟩

theorem scannerCallee_startLocal (caller : State) (cell : CellId) (source : List Byte)
    (start : Nat) (formed : caller.CellsWellFormed) :
    (scannerCallee caller cell source start).local? 2 =
      some (.signed .i32 (Int.ofNat start)) := by
  simpa [scannerCallee] using State.bindLocals_local?_get? ({ caller with locals := [] }) (scannerBindings cell source start) (fun item member => formed item member) (by simp [scannerBindings]) 2 (2, .signed .i32 (Int.ofNat start)) (by simp [scannerBindings])

theorem evalScannerInitializer
    (fuel : Nat) (program : Program) (state : State) (start : Nat)
    (localFound : state.local? 2 = some (.signed .i32 (Int.ofNat start)))
    (bound : start + 1 < 2 ^ 31) (enough : 2 ≤ fuel) :
    evalExpr fuel program state
      (.binary .add (.local 2) (.value (.signed .i32 1))) =
      .done (.signed .i32 (Int.ofNat (start + 1))) state := by
  exact evalExpr_i32LocalAddNat program state 2 start 1 localFound bound fuel enough

theorem evalScannerArguments
    (fuel : Nat) (program : Program) (state : State)
    (cell : CellId) (source : List Byte) (start : Nat) :
    evalExprs fuel.succ.succ.succ.succ program state
      (scannerArgumentExpressions cell source start) =
      .done (scannerArgumentValues cell source start) state := by
  simp [scannerArgumentExpressions, scannerArgumentValues, evalExprs.eq_def, evalExpr_value]

theorem scannerFunction_bindParameters
    (functionId predicateFunctionId : FunctionId)
    (cell : CellId) (source : List Byte) (start : Nat) :
    bindParameters (Artifact.scannerFunction functionId predicateFunctionId).parameters
      (scannerArgumentValues cell source start) =
      some (scannerBindings cell source start) := by
  simp [Artifact.scannerFunction, Artifact.scannerParameters, scannerArgumentValues, scannerBindings, bindParameters, sourceSliceValue, i32SliceValue]

theorem scannerCallee_frame
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (formed : caller.CellsWellFormed) :
    CallerFrame caller (scannerCallee caller cell source start) := by
  simpa [scannerCallee] using
    (show CallerFrame caller ({ caller with locals := [] }) from
      ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl, rfl⟩).bindLocals
      (scannerBindings cell source start)

theorem scannerCallee_sourceSlice
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (formed : caller.CellsWellFormed) (backing : SourceByteBacking caller cell source) :
    SourceSlice (scannerCallee caller cell source start) 0 cell
      (sourceI32Values source) := by
  exact SourceSlice.ofBacking 0 cell (sourceI32Values source)
    (by simpa [sourceSliceValue] using (scannerCallee_localFacts caller cell source start formed).1)
    (backing.afterCallerFrame (scannerCallee_frame caller cell source start formed))

theorem scannerCall_setup
    (fuel : Nat) (program : Program) (caller : State)
    (functionId predicateFunctionId : FunctionId)
    (cell : CellId) (source : List Byte) (start : Nat)
    (formed : caller.CellsWellFormed)
    (backing : SourceByteBacking caller cell source) :
    ∃ callee, evalExprs fuel.succ.succ.succ.succ program caller
        (scannerArgumentExpressions cell source start) =
          .done (scannerArgumentValues cell source start) caller ∧
      bindParameters (Artifact.scannerFunction functionId predicateFunctionId).parameters
        (scannerArgumentValues cell source start) =
          some (scannerBindings cell source start) ∧
      SourceSlice callee 0 cell (sourceI32Values source) ∧
      CallerFrame caller callee := by
  exact ⟨scannerCallee caller cell source start, evalScannerArguments fuel program caller cell source start,
    scannerFunction_bindParameters functionId predicateFunctionId cell source start,
    scannerCallee_sourceSlice caller cell source start formed backing, scannerCallee_frame caller
      cell source start formed⟩

end Lanius.Compiler.Lexer
