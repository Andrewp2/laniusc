import Lanius.Extraction.Parser.Derivation.Arithmetic

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser

private theorem read_local (found : before.local? localId = some value) :
    Evaluates program before (.local localId) value before :=
  ⟨1, evalLocal_of_local 0 program before localId value found⟩

theorem nonnegative_check_false
    (found : before.local? localId = some (.signed .i32 value)) (nonnegative : 0 ≤ value) :
    Evaluates program before
      (.binary .lessEqual (.local localId) (.unary .negate (.value (.signed .i32 1))))
      (.boolean false) before := by
  have negativeOne : Evaluates program before (.unary .negate (.value (.signed .i32 1)))
      (.signed .i32 (-1)) before := by
    apply evaluatesUnary
      (show Evaluates program before (.value (.signed .i32 1)) (.signed .i32 1) before from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, Core.SignedIntTy.bits]
  apply evaluatesEagerBinary (by decide) (by decide) (read_local found) negativeOne
  simp [evalBinaryValue, evalSignedBinary, show ¬ value ≤ -1 by omega]

/-- Shared source shape of the count/state-count and offset/output-length
    guards, including their negated upper-bound comparisons. -/
theorem range_guard_false
    (valueLocal : before.local? valueId = some (.signed .i32 value))
    (limitLocal : before.local? limitId = some (.signed .i32 limit))
    (nonnegative : 0 ≤ value) (bounded : value ≤ limit) :
    Evaluates program before
      (.binary .logicalOr
        (.binary .lessEqual (.local valueId) (.unary .negate (.value (.signed .i32 1))))
        (.unary .logicalNot (.binary .lessEqual (.local valueId) (.local limitId))))
      (.boolean false) before := by
  have upper : Evaluates program before (.binary .lessEqual (.local valueId) (.local limitId))
      (.boolean true) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (read_local valueLocal) (read_local limitLocal)
    simp [evalBinaryValue, evalSignedBinary, bounded]
  exact evaluatesLogicalOrFalse (nonnegative_check_false valueLocal nonnegative)
    (evaluatesUnary upper (by rfl))

/-- All six comparisons in the first metadata guard accept valid inputs. -/
theorem input_guard_false
    (tokenLocal : before.local? tokenId = some (.signed .i32 tokens))
    (workspaceLocal : before.local? workspaceId = some (.signed .i32 workspaceLength))
    (countLocal : before.local? countId = some (.signed .i32 stateCount))
    (stateLocal : before.local? stateId = some (.signed .i32 stateIndex))
    (tokensNonnegative : 0 ≤ tokens) (tokensBound : tokens < 536870912)
    (workspaceNonnegative : 0 ≤ workspaceLength)
    (stateNonnegative : 0 ≤ stateIndex) (stateBound : stateIndex < stateCount) :
    let negative := fun localId => Expr.binary .lessEqual (.local localId)
      (.unary .negate (.value (.signed .i32 1)))
    Evaluates program before
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .logicalOr
            (.binary .logicalOr
              (.binary .logicalOr (negative tokenId)
                (.binary .greaterEqual (.local tokenId) (.value (.signed .i32 536870912))))
              (negative workspaceId)) (negative countId)) (negative stateId))
        (.binary .greaterEqual (.local stateId) (.local countId))) (.boolean false) before := by
  have tokenUpper : Evaluates program before
      (.binary .greaterEqual (.local tokenId) (.value (.signed .i32 536870912))) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (read_local tokenLocal)
      (show Evaluates program before (.value (.signed .i32 536870912)) (.signed .i32 536870912) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary, show ¬ 536870912 ≤ tokens by omega]
  have stateUpper : Evaluates program before
      (.binary .greaterEqual (.local stateId) (.local countId)) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (read_local stateLocal) (read_local countLocal)
    simp [evalBinaryValue, evalSignedBinary, show ¬ stateCount ≤ stateIndex by omega]
  exact evaluatesLogicalOrFalse
    (evaluatesLogicalOrFalse
      (evaluatesLogicalOrFalse
        (evaluatesLogicalOrFalse
          (evaluatesLogicalOrFalse (nonnegative_check_false tokenLocal tokensNonnegative) tokenUpper)
          (nonnegative_check_false workspaceLocal workspaceNonnegative))
        (nonnegative_check_false countLocal (by omega)))
      (nonnegative_check_false stateLocal stateNonnegative)) stateUpper

/-- The final output-capacity guard accepts a complete record that fits.
    Both subtractions and the signed division are executed without wrapping. -/
theorem output_capacity_guard_false
    (capacityLocal : before.local? capacityId = some (.signed .i32 capacity))
    (offsetLocal : before.local? offsetId = some (.signed .i32 offset))
    (countLocal : before.local? countId = some (.signed .i32 count))
    (offsetNonnegative : 0 ≤ offset) (countNonnegative : 0 ≤ count)
    (fits : offset + 4 + count * 3 ≤ capacity) (capacityBound : capacity ≤ 2147483647) :
    Evaluates program before
      (.binary .logicalOr
        (.binary .lessEqual (.binary .subtract (.local capacityId) (.local offsetId)) (.value (.signed .i32 3)))
        (.unary .logicalNot (.binary .lessEqual (.local countId)
          (.binary .divide
            (.binary .subtract (.binary .subtract (.local capacityId) (.local offsetId)) (.value (.signed .i32 4)))
            (.value (.signed .i32 3)))))) (.boolean false) before := by
  have span : Evaluates program before (.binary .subtract (.local capacityId) (.local offsetId))
      (.signed .i32 (capacity - offset)) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (read_local capacityLocal) (read_local offsetLocal)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target _ (by omega) (by omega)]
    rfl
  have headerRoom : Evaluates program before
      (.binary .lessEqual (.binary .subtract (.local capacityId) (.local offsetId)) (.value (.signed .i32 3)))
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) span
      (show Evaluates program before (.value (.signed .i32 3)) (.signed .i32 3) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary, show ¬ capacity - offset ≤ 3 by omega]
  have quotient := output_capacity_expression (program := program) (read_local capacityLocal) (read_local offsetLocal)
    offsetNonnegative (by omega) capacityBound
  have enough : count ≤ (capacity - offset - 4) / 3 := by omega
  have countRoom : Evaluates program before
      (.binary .lessEqual (.local countId)
        (.binary .divide
          (.binary .subtract (.binary .subtract (.local capacityId) (.local offsetId)) (.value (.signed .i32 4)))
          (.value (.signed .i32 3)))) (.boolean true) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (read_local countLocal) quotient
    simp [evalBinaryValue, evalSignedBinary, enough]
  exact evaluatesLogicalOrFalse headerRoom (evaluatesUnary countRoom (by rfl))

/-- Capacity exhaustion is detected before any output store. When even the
    header cannot fit, short-circuiting avoids the negative quotient branch. -/
theorem output_capacity_guard_true
    (capacityLocal : before.local? capacityId = some (.signed .i32 capacity))
    (offsetLocal : before.local? offsetId = some (.signed .i32 offset))
    (countLocal : before.local? countId = some (.signed .i32 count))
    (offsetNonnegative : 0 ≤ offset) (offsetBound : offset ≤ capacity)
    (full : capacity < offset + 4 + count * 3) (capacityBound : capacity ≤ 2147483647) :
    Evaluates program before
      (.binary .logicalOr
        (.binary .lessEqual (.binary .subtract (.local capacityId) (.local offsetId)) (.value (.signed .i32 3)))
        (.unary .logicalNot (.binary .lessEqual (.local countId)
          (.binary .divide
            (.binary .subtract (.binary .subtract (.local capacityId) (.local offsetId)) (.value (.signed .i32 4)))
            (.value (.signed .i32 3)))))) (.boolean true) before := by
  have span : Evaluates program before (.binary .subtract (.local capacityId) (.local offsetId))
      (.signed .i32 (capacity - offset)) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (read_local capacityLocal) (read_local offsetLocal)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target _ (by omega) (by omega)]
    rfl
  by_cases short : capacity - offset ≤ 3
  · apply evaluatesLogicalOrTrue
    exact evaluatesEagerBinary (by decide) (by decide) span ⟨1, rfl⟩
      (by simp [evalBinaryValue, evalSignedBinary, short])
  · have headerRoom : Evaluates program before
        (.binary .lessEqual (.binary .subtract (.local capacityId) (.local offsetId)) (.value (.signed .i32 3)))
        (.boolean false) before :=
      evaluatesEagerBinary (by decide) (by decide) span ⟨1, rfl⟩
        (by simp [evalBinaryValue, evalSignedBinary, short])
    have quotient := output_capacity_expression (program := program) (read_local capacityLocal) (read_local offsetLocal)
      offsetNonnegative (by omega) capacityBound
    have tooMany : ¬ count ≤ (capacity - offset - 4) / 3 := by omega
    have countFull : Evaluates program before
        (.binary .lessEqual (.local countId)
          (.binary .divide
            (.binary .subtract (.binary .subtract (.local capacityId) (.local offsetId)) (.value (.signed .i32 4)))
            (.value (.signed .i32 3)))) (.boolean false) before :=
      evaluatesEagerBinary (by decide) (by decide) (read_local countLocal) quotient
        (by simp [evalBinaryValue, evalSignedBinary, tooMany])
    exact evaluatesLogicalOrFalse headerRoom (evaluatesUnary countFull rfl)

end Lanius.Extraction.ParserDerivation
