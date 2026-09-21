import Lanius.Compiler.Lexer.ArtifactQuoted
import Lanius.Compiler.Lexer.ScannerCall

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

def quotedArgumentValues (cell : CellId) (source : List Byte) (start : Nat)
    (delimiter : Int) : List Value :=
  scannerArgumentValues cell source start ++ [.signed .i32 delimiter]

def quotedArgumentExpressions (cell : CellId) (source : List Byte) (start : Nat)
    (delimiter : Int) : List Expr :=
  scannerArgumentExpressions cell source start ++ [.value (.signed .i32 delimiter)]

def quotedBindings (cell : CellId) (source : List Byte) (start : Nat)
    (delimiter : Int) : List (VarId × Value) :=
  scannerBindings cell source start ++ [(3, .signed .i32 delimiter)]

def quotedCallee (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (delimiter : Int) : State :=
  (scannerCallee caller cell source start).bindLocal 3 (.signed .i32 delimiter)

theorem evalQuotedArguments
    (fuel : Nat) (program : Program) (state : State)
    (cell : CellId) (source : List Byte) (start : Nat) (delimiter : Int) :
    evalExprs fuel.succ.succ.succ.succ.succ program state
      (quotedArgumentExpressions cell source start delimiter) =
      .done (quotedArgumentValues cell source start delimiter) state := by
  change evalExprs fuel.succ.succ.succ.succ.succ program state
      [.value (sourceSliceValue cell source),
       .value (.signed .i32 (Int.ofNat source.length)),
       .value (.signed .i32 (Int.ofNat start)),
       .value (.signed .i32 delimiter)] = _
  repeat (rw [evalExprs.eq_def] <;> simp only [evalExpr_value])
  simp [quotedArgumentValues, scannerArgumentValues]

theorem scanQuotedEndFunction_bindParameters
    (cell : CellId) (source : List Byte) (start : Nat) (delimiter : Int) :
    bindParameters Artifact.scanQuotedEndFunction.parameters
      (quotedArgumentValues cell source start delimiter) =
      some (quotedBindings cell source start delimiter) := by
  rfl

theorem quotedCallee_frame
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (delimiter : Int) (formed : caller.CellsWellFormed) :
    CallerFrame caller (quotedCallee caller cell source start delimiter) := by
  simpa [quotedCallee] using (scannerCallee_frame caller cell source start formed).bindLocal 3 (.signed .i32 delimiter)

theorem quotedCallee_localFacts
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (delimiter : Int) (formed : caller.CellsWellFormed) :
    (quotedCallee caller cell source start delimiter).local? 0 =
        some (sourceSliceValue cell source) ∧
      (quotedCallee caller cell source start delimiter).local? 1 =
        some (.signed .i32 (Int.ofNat source.length)) ∧
      (quotedCallee caller cell source start delimiter).local? 2 =
        some (.signed .i32 (Int.ofNat start)) ∧
      (quotedCallee caller cell source start delimiter).local? 3 =
        some (.signed .i32 delimiter) := by
  exact ⟨by simpa [quotedCallee] using State.bindLocal_local?_of_ne (scannerCallee caller cell source start) (scannerCallee_frame caller cell source start formed).currentFormed 0 3 _ (.signed .i32 delimiter) (by decide) (scannerCallee_localFacts caller cell source start formed).1,
    by simpa [quotedCallee] using State.bindLocal_local?_of_ne (scannerCallee caller cell source start) (scannerCallee_frame caller cell source start formed).currentFormed 1 3 _ (.signed .i32 delimiter) (by decide) (scannerCallee_localFacts caller cell source start formed).2,
    by simpa [quotedCallee] using State.bindLocal_local?_of_ne (scannerCallee caller cell source start) (scannerCallee_frame caller cell source start formed).currentFormed 2 3 _ (.signed .i32 delimiter) (by decide) (scannerCallee_startLocal caller cell source start formed),
    by simpa [quotedCallee] using State.bindLocal_local? (scannerCallee caller cell source start) (scannerCallee_frame caller cell source start formed).currentFormed 3 (.signed .i32 delimiter)⟩

theorem quotedCallee_sourceSlice
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (delimiter : Int) (formed : caller.CellsWellFormed)
    (backing : SourceByteBacking caller cell source) :
    SourceSlice (quotedCallee caller cell source start delimiter) 0 cell
      (sourceI32Values source) := by
  exact SourceSlice.ofBacking 0 cell (sourceI32Values source)
    (by simpa [sourceSliceValue] using
      (quotedCallee_localFacts caller cell source start delimiter formed).1)
    (backing.afterCallerFrame (quotedCallee_frame caller cell source start delimiter formed))

end Lanius.Compiler.Lexer
