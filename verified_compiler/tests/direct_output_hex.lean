import GeneratedDirectCore
import Lanius.Semantics.CallProof

namespace OutputHexProof

open Lanius Lanius.Core Lanius.Semantics

def digitCode (digit : Nat) : Nat := if digit < 10 then 48 + digit else 87 + digit

theorem digitCode_bound (digit : Fin 16) : digitCode digit.val < 256 := by
  have bound := digit.isLt
  unfold digitCode; split <;> omega

def digitCall (digit : Nat) : Expr :=
  .call Extracted.«verified::lean_output».Functions.«hex_digit».core.id [.value (.signed .i32 digit)]

/-- The actual formatter emits lowercase ASCII for every nibble, without
    assuming a successful call or repeating its body at each use. -/
theorem actualCall (digit : Fin 16) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (digitCall digit.val)
      (.signed .i32 (digitCode digit.val)) after ∧ PureFrame state after := by
  core_call Extracted.«verified::lean_output».Functions.«hex_digit».core
  simp only [digitCode, show 87 + digit.val = 97 + digit.val - 10 by omega]
  split <;> core_stmt_forward

#print axioms actualCall

-- Exact alphabet, not just a byte-range check.
example : (List.range 16).map digitCode =
    [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102] := by decide

end OutputHexProof
