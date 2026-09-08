import Lanius.Compiler.ParserDerivation
import Lanius.Semantics
import Lanius.ExecutionRules
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.ParserDerivation

open Lanius.Semantics Lanius.Compiler.Parser

/-- After the header-space guard, the source's truncating division agrees
    with the mathematical quotient used by the record-capacity proof. -/
theorem output_quotient (capacity offset : Int)
    (headerFits : offset + 4 ≤ capacity) :
    truncDiv (capacity - offset - 4) 3 = (capacity - offset - 4) / 3 := by
  have nonnegative : 0 ≤ capacity - offset - 4 := by omega
  generalize amountEq : capacity - offset - 4 = amount at *
  cases amount with
  | ofNat n => simp [truncDiv]
  | negSucc n => omega

theorem output_guard_truncating (offset capacity count : Int)
    (countNonnegative : 0 ≤ count) (headerFits : offset + 4 ≤ capacity) :
    (¬ offset ≤ -1 ∧ offset ≤ capacity ∧ ¬ capacity - offset ≤ 3 ∧
      count ≤ truncDiv (capacity - offset - 4) 3) ↔
    (0 ≤ offset ∧ offset + 4 + count * 3 ≤ capacity) := by
  rw [output_quotient capacity offset headerFits]
  exact derivation_output_guard offset capacity count countNonnegative

/-- The actual Core division returns the mathematical capacity quotient:
    neither division traps nor signed wrapping occurs on the guarded path. -/
theorem output_division_evaluates (target : Lanius.Core.Target) (capacity offset : Int)
    (offsetNonnegative : 0 ≤ offset) (headerFits : offset + 4 ≤ capacity)
    (capacityI32 : capacity ≤ 2147483647) :
    evalSignedBinary target .divide .i32 (capacity - offset - 4) 3 =
      .ok (.signed .i32 ((capacity - offset - 4) / 3)) := by
  have quotientNonnegative : 0 ≤ (capacity - offset - 4) / 3 := by omega
  have quotientBound : (capacity - offset - 4) / 3 ≤ 2147483647 := by omega
  simp only [evalSignedBinary]
  simp only [show ((3 : Int) == 0) = false from rfl,
    show ((3 : Int) == -1) = false from rfl, Bool.and_false, Bool.false_eq_true, if_false]
  rw [output_quotient capacity offset headerFits,
    wrapSigned_i32_of_nonnegative target _ quotientNonnegative quotientBound]

/-- Execute the complete source expression `(capacity - offset - 4) / 3`,
    retaining the language's left-to-right operand effects. -/
theorem output_capacity_expression
    (capacityRead : Evaluates program before capacityExpr (.signed .i32 capacity) middle)
    (offsetRead : Evaluates program middle offsetExpr (.signed .i32 offset) after)
    (offsetNonnegative : 0 ≤ offset) (headerFits : offset + 4 ≤ capacity)
    (capacityI32 : capacity ≤ 2147483647) :
    Evaluates program before
      (.binary .divide (.binary .subtract (.binary .subtract capacityExpr offsetExpr)
        (.value (.signed .i32 4))) (.value (.signed .i32 3)))
      (.signed .i32 ((capacity - offset - 4) / 3)) after := by
  have difference : Evaluates program before (.binary .subtract capacityExpr offsetExpr)
      (.signed .i32 (capacity - offset)) after := by
    apply evaluatesEagerBinary (by decide) (by decide) capacityRead offsetRead
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target _ (by omega) (by omega)]
    rfl
  have available : Evaluates program before
      (.binary .subtract (.binary .subtract capacityExpr offsetExpr)
        (.value (.signed .i32 4))) (.signed .i32 (capacity - offset - 4)) after := by
    apply evaluatesEagerBinary (by decide) (by decide) difference
      (show Evaluates program after (.value (.signed .i32 4)) (.signed .i32 4) after from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target _ (by omega) (by omega)]
    rfl
  apply evaluatesEagerBinary (by decide) (by decide) available
    (show Evaluates program after (.value (.signed .i32 3)) (.signed .i32 3) after from ⟨1, rfl⟩)
  exact output_division_evaluates program.target capacity offset offsetNonnegative headerFits capacityI32

open Lanius.Properties Lanius.Separation

/-- Output stores cannot overwrite a signed local's cell: the output backing
    cell contains an array, so the two cells are necessarily distinct. -/
theorem output_local_operand
    (wellFormed : StateWellFormed before)
    (localValue : before.local? localId = some (.signed .i32 value))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) })
    (effect : CellEffect (CellSet.singleton outputCell) before runtime) :
    Evaluates program runtime (.local localId) (.signed .i32 value) runtime := by
  have preserved := effect.preserves_local_of_distinct_value wellFormed localValue backing
    (by simp)
  exact ⟨1, evalLocal_of_local 0 program runtime localId (.signed .i32 value) preserved⟩

/-- The three output indices have the source shape `slot`, `slot + 1`,
    `slot + 2`, and remain valid after earlier stores in the same triple. -/
theorem output_index_operand
    (wellFormed : StateWellFormed before)
    (slotLocal : before.local? slotId = some (.signed .i32 (Int.ofNat slot)))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) })
    (effect : CellEffect (CellSet.singleton outputCell) before runtime)
    (offset : Nat) (offsetBound : offset < 3) (slotBound : slot + 2 ≤ 2147483647) :
    Evaluates program runtime
      (if offset = 0 then .local slotId else
        .binary .add (.local slotId) (.value (.signed .i32 (Int.ofNat offset))))
      (.signed .i32 (Int.ofNat (slot + offset))) runtime := by
  have read := output_local_operand (program := program) wellFormed slotLocal backing effect
  by_cases zero : offset = 0
  · subst offset
    simpa using read
  · simp only [if_neg zero]
    have sum : Int.ofNat (slot + offset) = Int.ofNat slot + Int.ofNat offset := Int.natCast_add slot offset
    rw [sum]
    apply evaluatesEagerBinary (by decide) (by decide) read
      (show Evaluates program runtime (.value (.signed .i32 (Int.ofNat offset)))
        (.signed .i32 (Int.ofNat offset)) runtime from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target _
      (by change 0 ≤ (slot : Int) + (offset : Int); omega)
      (by change (slot : Int) + (offset : Int) ≤ 2147483647; omega)]
    rfl

/-- Execute the slot initializer with the source's left-to-right order.
    The record-capacity invariant bounds every intermediate signed result. -/
theorem output_slot_expression
    (offsetRead : Evaluates program before offsetExpression (.signed .i32 offset) middle)
    (remainingRead : Evaluates program middle remainingExpression (.signed .i32 remaining) after)
    (offsetNonnegative : 0 ≤ offset) (fits : offset + 4 + count * 3 ≤ capacity)
    (capacityI32 : capacity ≤ 2147483647)
    (remainingPositive : 0 < remaining) (remainingBound : remaining ≤ count) :
    Evaluates program before
      (.binary .add (.binary .add offsetExpression (.value (.signed .i32 4)))
        (.binary .multiply (.binary .subtract remainingExpression (.value (.signed .i32 1)))
          (.value (.signed .i32 3))))
      (.signed .i32 (offset + 4 + (remaining - 1) * 3)) after := by
  have header : Evaluates program before
      (.binary .add offsetExpression (.value (.signed .i32 4))) (.signed .i32 (offset + 4)) middle := by
    apply evaluatesEagerBinary (by decide) (by decide) offsetRead
      (show Evaluates program middle (.value (.signed .i32 4)) (.signed .i32 4) middle from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target _ (by omega) (by omega)]
    rfl
  have predecessor : Evaluates program middle
      (.binary .subtract remainingExpression (.value (.signed .i32 1)))
      (.signed .i32 (remaining - 1)) after := by
    apply evaluatesEagerBinary (by decide) (by decide) remainingRead
      (show Evaluates program after (.value (.signed .i32 1)) (.signed .i32 1) after from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target _ (by omega) (by omega)]
    rfl
  have bounds := derivation_child_slot_bounds offset capacity count remaining
    offsetNonnegative fits capacityI32 remainingPositive remainingBound
  have displacement : Evaluates program middle
      (.binary .multiply (.binary .subtract remainingExpression (.value (.signed .i32 1)))
        (.value (.signed .i32 3))) (.signed .i32 ((remaining - 1) * 3)) after := by
    apply evaluatesEagerBinary (by decide) (by decide) predecessor
      (show Evaluates program after (.value (.signed .i32 3)) (.signed .i32 3) after from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target _ bounds.1 bounds.2.1]
    rfl
  apply evaluatesEagerBinary (by decide) (by decide) header displacement
  simp only [evalBinaryValue, evalSignedBinary]
  rw [wrapSigned_i32_of_nonnegative program.target _ bounds.2.2.1 (by omega)]
  rfl

end Lanius.Extraction.ParserDerivation
