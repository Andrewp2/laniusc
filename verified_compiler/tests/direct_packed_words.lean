import GeneratedDirectCore
import Lanius.Semantics.CallProof

namespace PackedWordsProof

open Lanius Lanius.Core Lanius.Semantics

def packedCall (length : Int) : Expr :=
  .call Extracted.«verified::host».Functions.«packed_words».core.id
    [.value (.signed .i32 length)]

/-- Exact ceiling division throughout the i32 domain, including empty input
    and rejection. No allocation or successful-execution premise is required. -/
theorem actualCall (length : Int) (fits : length < 2 ^ 31) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (packedCall length)
        (.signed .i32 (if length < 0 then -1 else ((length.toNat + 3) / 4 : Nat))) after ∧
      PureFrame state after := by
  core_call Extracted.«verified::host».Functions.«packed_words».core
  by_cases negative : length < 0
  · simp only [negative, ↓reduceIte]
    core_stmt
  · have natLength := Int.toNat_of_nonneg (Int.le_of_not_gt negative)
    generalize length.toNat = count at natLength
    subst length
    simp only [negative, ↓reduceIte]
    by_cases empty : count = 0
    · subst count; core_stmt
    · have positive : 0 < count := by omega
      have ceiling : (count + 3) / 4 = 1 + (count - 1) / 4 := by omega
      rw [ceiling]
      core_stmt

#print axioms actualCall

end PackedWordsProof
