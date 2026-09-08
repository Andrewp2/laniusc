import Lanius.Extraction.Parser.Derivation.Reads

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- The source base expression uses signed i32 arithmetic at each stage.
    Its token-count guard bounds all intermediates, including the final
    multiplication by the checked CHART_WORDS constant. -/
theorem base_expression
    (tokenLocal : before.local? tokenCountId = some (.signed .i32 (Int.ofNat tokenCount)))
    (tokenBound : tokenCount ≤ maxTokenCount) :
    Evaluates verifiedParserCore before
      (.binary .multiply
        (.binary .add (.binary .multiply (.local tokenCountId) (.value (.signed .i32 2)))
          (.value (.signed .i32 1))) (.constant 24))
      (.signed .i32 (Int.ofNat (stateBase tokenCount))) before := by
  have bound : tokenCount ≤ 536870911 := tokenBound
  have tokenRead : Evaluates verifiedParserCore before (.local tokenCountId)
      (.signed .i32 (Int.ofNat tokenCount)) before :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore before tokenCountId _ tokenLocal⟩
  have doubled : Evaluates verifiedParserCore before
      (.binary .multiply (.local tokenCountId) (.value (.signed .i32 2)))
      (.signed .i32 ((tokenCount : Int) * 2)) before := by
    apply evaluatesEagerBinary (by decide) (by decide) tokenRead
      (show Evaluates verifiedParserCore before (.value (.signed .i32 2)) (.signed .i32 2) before from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative verifiedParserCore.target _
      (by change 0 ≤ (tokenCount : Int) * 2; omega)
      (by change (tokenCount : Int) * 2 ≤ 2147483647; omega)]
    rfl
  have chart : Evaluates verifiedParserCore before
      (.binary .add (.binary .multiply (.local tokenCountId) (.value (.signed .i32 2)))
        (.value (.signed .i32 1))) (.signed .i32 ((tokenCount : Int) * 2 + 1)) before := by
    apply evaluatesEagerBinary (by decide) (by decide) doubled
      (show Evaluates verifiedParserCore before (.value (.signed .i32 1)) (.signed .i32 1) before from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative verifiedParserCore.target _ (by omega) (by omega)]
    rfl
  have encoded : Int.ofNat (stateBase tokenCount) = ((tokenCount : Int) * 2 + 1) * 2 := by
    simp [stateBase, chartCount, finalPosition, chartWords, Int.natCast_add, Int.natCast_mul]
  rw [encoded]
  apply evaluatesEagerBinary (by decide) (by decide) chart
    (evaluatesConstant verifiedParser_workspace_constants.1)
  simp only [evalBinaryValue, evalSignedBinary]
  rw [wrapSigned_i32_of_nonnegative verifiedParserCore.target _ (by omega) (by omega)]
  rfl

/-- The workspace-capacity quotient uses truncating signed division in the
    source. With a nonnegative remaining span it is the ordinary quotient,
    and neither the subtraction nor division wraps or traps. -/
theorem state_capacity_expression
    (capacityRead : Evaluates verifiedParserCore before capacityExpression (.signed .i32 capacity) middle)
    (baseRead : Evaluates verifiedParserCore middle baseExpression (.signed .i32 base) after)
    (baseNonnegative : 0 ≤ base) (baseFits : base ≤ capacity) (capacityBound : capacity ≤ 2147483647) :
    Evaluates verifiedParserCore before
      (.binary .divide (.binary .subtract capacityExpression baseExpression) (.constant 27))
      (.signed .i32 ((capacity - base) / 9)) after := by
  have span : Evaluates verifiedParserCore before (.binary .subtract capacityExpression baseExpression)
      (.signed .i32 (capacity - base)) after := by
    apply evaluatesEagerBinary (by decide) (by decide) capacityRead baseRead
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative verifiedParserCore.target _ (by omega) (by omega)]
    rfl
  have division : truncDiv (capacity - base) 9 = (capacity - base) / 9 := by
    have nonnegative : 0 ≤ capacity - base := by omega
    generalize spanEq : capacity - base = amount at *
    cases amount with
    | ofNat n => simp [truncDiv]
    | negSucc n => omega
  apply evaluatesEagerBinary (by decide) (by decide) span
    (evaluatesConstant verifiedParser_workspace_constants.2)
  simp only [evalBinaryValue, evalSignedBinary]
  simp only [show ((9 : Int) == 0) = false from rfl,
    show ((9 : Int) == -1) = false from rfl, Bool.and_false, Bool.false_eq_true, if_false]
  rw [division, wrapSigned_i32_of_nonnegative verifiedParserCore.target _ (by omega) (by omega)]
  rfl

/-- A workspace large enough for the retained states passes the exact
    source rejection condition, including both logical negations. -/
theorem workspace_guard_false
    (capacityLocal : before.local? capacityId = some (.signed .i32 capacity))
    (baseLocal : before.local? baseId = some (.signed .i32 base))
    (countLocal : before.local? countId = some (.signed .i32 count))
    (baseNonnegative : 0 ≤ base) (baseFits : base ≤ capacity) (capacityBound : capacity ≤ 2147483647)
    (countFits : count ≤ (capacity - base) / 9) :
    Evaluates verifiedParserCore before
      (.binary .logicalOr
        (.unary .logicalNot (.binary .lessEqual (.local baseId) (.local capacityId)))
        (.unary .logicalNot (.binary .lessEqual (.local countId)
          (.binary .divide (.binary .subtract (.local capacityId) (.local baseId)) (.constant 27)))))
      (.boolean false) before := by
  have localRead {localId : VarId} {value : Value} (found : before.local? localId = some value) :
      Evaluates verifiedParserCore before (.local localId) value before :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore before localId value found⟩
  have baseAccepted : Evaluates verifiedParserCore before
      (.binary .lessEqual (.local baseId) (.local capacityId)) (.boolean true) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (localRead baseLocal) (localRead capacityLocal)
    simp [evalBinaryValue, evalSignedBinary, baseFits]
  have quotient := state_capacity_expression (localRead capacityLocal) (localRead baseLocal)
    baseNonnegative baseFits capacityBound
  have countAccepted : Evaluates verifiedParserCore before
      (.binary .lessEqual (.local countId)
        (.binary .divide (.binary .subtract (.local capacityId) (.local baseId)) (.constant 27)))
      (.boolean true) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (localRead countLocal) quotient
    simp [evalBinaryValue, evalSignedBinary, countFits]
  exact evaluatesLogicalOrFalse (evaluatesUnary baseAccepted (by rfl))
    (evaluatesUnary countAccepted (by rfl))

end Lanius.Extraction.ParserDerivation
