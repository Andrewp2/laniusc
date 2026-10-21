import GeneratedDirectCore
import Lanius.Semantics.CallProof

namespace OutputCursorProof

open Lanius Lanius.Core Lanius.Semantics

def cursorType : TypeId :=
  match Extracted.«verified::lean_output».Functions.«cursor».core.returnType with
  | .structure id => id
  | _ => 0

/-- The real constructor only packages its inputs; it does not inspect
    storage, clamp offsets, or alter the caller's memory and variables. -/
theorem actualCall (output : Value) (capacity position : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«verified::lean_output».Functions.«cursor».core.id
          ([output, .signed .i32 capacity, .signed .i32 position].map Expr.value))
        (.structure cursorType [output, .signed .i32 capacity, .signed .i32 position]) after ∧
      PureFrame state after := by
  core_call Extracted.«verified::lean_output».Functions.«cursor».core
  core_stmt

#print axioms actualCall

end OutputCursorProof
