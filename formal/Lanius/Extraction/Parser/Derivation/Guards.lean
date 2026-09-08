import Lanius.Compiler.ParserDerivation
import Lanius.ExecutionRules
import Lanius.Extraction.Parser.Derivation.Reads

namespace Lanius.Extraction.ParserDerivation

open Lanius.Semantics Lanius.Compiler.Parser

theorem evaluates_i32_mismatch_false
    (leftRead : Evaluates program before left (.signed .i32 value) middle)
    (rightRead : Evaluates program middle right (.signed .i32 value) after) :
    Evaluates program before (.binary .notEqual left right) (.boolean false) after := by
  apply evaluatesEagerBinary (by decide) (by decide) leftRead rightRead
  simp [evalBinaryValue, scalarEqual]

/-- Cursor metadata makes all three rejection comparisons false. Accessor
    and local reads retain their actual sequential effects. -/
theorem metadata_guard_false
    (cursor : DerivationCursor workspace root state fuel current remaining suffix children)
    (dotRead : Evaluates program before dotExpression (.signed .i32 (Int.ofNat state.dot)) afterDot)
    (remainingRead : Evaluates program afterDot remainingExpression (.signed .i32 (Int.ofNat remaining)) afterRemaining)
    (productionRead : Evaluates program afterRemaining productionExpression
      (.signed .i32 (Int.ofNat state.production)) afterProduction)
    (rootProductionRead : Evaluates program afterProduction rootProductionExpression
      (.signed .i32 (Int.ofNat root.production)) afterRootProduction)
    (originRead : Evaluates program afterRootProduction originExpression
      (.signed .i32 (Int.ofNat state.origin)) afterOrigin)
    (rootOriginRead : Evaluates program afterOrigin rootOriginExpression
      (.signed .i32 (Int.ofNat root.origin)) after) :
    Evaluates program before
      (.binary .logicalOr
        (.binary .logicalOr (.binary .notEqual dotExpression remainingExpression)
          (.binary .notEqual productionExpression rootProductionExpression))
        (.binary .notEqual originExpression rootOriginExpression)) (.boolean false) after := by
  have dot := evaluates_i32_mismatch_false
    (by simpa only [cursor.dot] using dotRead) remainingRead
  have production := evaluates_i32_mismatch_false
    (by simpa only [cursor.production] using productionRead) rootProductionRead
  have origin := evaluates_i32_mismatch_false
    (by simpa only [cursor.origin] using originRead) rootOriginRead
  exact evaluatesLogicalOrFalse (evaluatesLogicalOrFalse dot production) origin

open Lanius.Properties Lanius.Separation Lanius.Extraction.ParserRecognize

/-- A concrete accessor/local comparison, including the accessor's allocation
    effect and the preserved caller-local read. No read executions are assumed. -/
theorem field_guard_false
    (artifact : RecognizerWorkspaceArtifact layout workspace values workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state) (fieldBound : field < stateWords)
    (workspaceLocal : before.local? workspaceId = some
      (.slice parserI32Type workspaceCell [] 0 values.length))
    (baseLocal : before.local? baseId = some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (currentLocal : before.local? currentId = some (.signed .i32 (Int.ofNat stateId)))
    (selector : verifiedParserCore.constant? selectorId = some {
      id := selectorId, type := parserI32Type, value := .signed .i32 (Int.ofNat field) })
    (expectedLocal : before.local? expectedId = some (.signed .i32 expected))
    (same : stateFieldValue workspace stateId state field = expected) :
    ∃ after, Evaluates verifiedParserCore before
      (.binary .notEqual (.call extractedParserStateValueFunction.id
        [.local workspaceId, .local baseId, .local currentId, .constant selectorId])
        (.local expectedId)) (.boolean false) after ∧
      RecognizerWorkspaceArtifact layout workspace values workspaceCell after ∧
      CellEffect CellSet.empty before after := by
  obtain ⟨after, read, preserved, effect⟩ := artifact.read_field_locals wellFormed found fieldBound
    workspaceLocal baseLocal currentLocal selector
  have expectedStill := effect.empty_preserves_local wellFormed expectedLocal
  have expectedRead : Evaluates verifiedParserCore after (.local expectedId) (.signed .i32 expected) after :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore after expectedId _ expectedStill⟩
  rw [same] at read
  exact ⟨after, evaluates_i32_mismatch_false read expectedRead, preserved, effect⟩

/-- Execute the complete metadata rejection condition from the invariant and
    caller locals, proving all three accessor calls and selector lookups. -/
theorem metadata_guard_executes
    (cursor : DerivationCursor workspace root state fuel current remaining suffix children)
    (artifact : RecognizerWorkspaceArtifact layout workspace values workspaceCell before)
    (wellFormed : StateWellFormed before)
    (workspaceLocal : before.local? workspaceId = some
      (.slice parserI32Type workspaceCell [] 0 values.length))
    (baseLocal : before.local? baseId = some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (currentLocal : before.local? currentId = some (.signed .i32 (Int.ofNat current)))
    (remainingLocal : before.local? remainingId = some (.signed .i32 (Int.ofNat remaining)))
    (productionLocal : before.local? productionId = some (.signed .i32 (Int.ofNat root.production)))
    (originLocal : before.local? originId = some (.signed .i32 (Int.ofNat root.origin))) :
    let mismatch := fun selector expected => Lanius.Core.Expr.binary .notEqual
      (.call extractedParserStateValueFunction.id
        [.local workspaceId, .local baseId, .local currentId, .constant selector]) (.local expected)
    ∃ after, Evaluates verifiedParserCore before
      (.binary .logicalOr (.binary .logicalOr (mismatch 29 remainingId)
        (mismatch 28 productionId)) (mismatch 30 originId)) (.boolean false) after ∧
      RecognizerWorkspaceArtifact layout workspace values workspaceCell after ∧
      CellEffect CellSet.empty before after := by
  obtain ⟨afterDot, dot, artifactDot, effectDot⟩ := field_guard_false
    (field := 1) (selectorId := 29) artifact wellFormed cursor.found (by decide)
    workspaceLocal baseLocal currentLocal (by rfl) remainingLocal
    (by simp only [stateFieldValue, cursor.dot])
  obtain ⟨afterProduction, production, artifactProduction, effectProduction⟩ := field_guard_false
    (field := 0) (selectorId := 28) artifactDot effectDot.wellFormed cursor.found (by decide)
    (effectDot.empty_preserves_local wellFormed workspaceLocal)
    (effectDot.empty_preserves_local wellFormed baseLocal)
    (effectDot.empty_preserves_local wellFormed currentLocal) (by rfl)
    (effectDot.empty_preserves_local wellFormed productionLocal)
    (by simp only [stateFieldValue, cursor.production])
  have combined := effectDot.trans effectProduction
  obtain ⟨afterOrigin, origin, artifactOrigin, effectOrigin⟩ := field_guard_false
    (field := 2) (selectorId := 30) artifactProduction combined.wellFormed cursor.found (by decide)
    (combined.empty_preserves_local wellFormed workspaceLocal)
    (combined.empty_preserves_local wellFormed baseLocal)
    (combined.empty_preserves_local wellFormed currentLocal) (by rfl)
    (combined.empty_preserves_local wellFormed originLocal)
    (by simp only [stateFieldValue, cursor.origin])
  exact ⟨afterOrigin, evaluatesLogicalOrFalse (evaluatesLogicalOrFalse dot production) origin,
    artifactOrigin, combined.trans effectOrigin⟩

/-- The source's predecessor/payload rejection condition is false on the
    valid backpointer path. Negative one retains its unary-expression shape. -/
theorem predecessor_guard_executes
    (previousLocal : before.local? previousId = some (.signed .i32 previous))
    (currentLocal : before.local? currentId = some (.signed .i32 current))
    (payloadLocal : before.local? payloadId = some (.signed .i32 payload))
    (previousNonnegative : 0 ≤ previous) (earlier : previous < current)
    (payloadNonnegative : 0 ≤ payload) :
    Evaluates program before
      (.binary .logicalOr (.binary .logicalOr
        (.binary .lessEqual (.local previousId) (.unary .negate (.value (.signed .i32 1))))
        (.binary .greaterEqual (.local previousId) (.local currentId)))
        (.binary .lessEqual (.local payloadId) (.unary .negate (.value (.signed .i32 1)))))
      (.boolean false) before := by
  have localRead {localId : Lanius.VarId} {value : Lanius.Core.Value}
      (found : before.local? localId = some value) :
      Evaluates program before (.local localId) value before :=
    ⟨1, evalLocal_of_local 0 program before localId value found⟩
  have negativeOne : Evaluates program before (.unary .negate (.value (.signed .i32 1)))
      (.signed .i32 (-1)) before := by
    apply evaluatesUnary
      (show Evaluates program before (.value (.signed .i32 1)) (.signed .i32 1) before from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, Lanius.Core.SignedIntTy.bits]
  have previousCheck : Evaluates program before
      (.binary .lessEqual (.local previousId) (.unary .negate (.value (.signed .i32 1))))
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (localRead previousLocal) negativeOne
    simp [evalBinaryValue, evalSignedBinary, show ¬ previous ≤ -1 by omega]
  have earlierCheck : Evaluates program before
      (.binary .greaterEqual (.local previousId) (.local currentId)) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (localRead previousLocal) (localRead currentLocal)
    simp [evalBinaryValue, evalSignedBinary, show ¬ current ≤ previous by omega]
  have payloadCheck : Evaluates program before
      (.binary .lessEqual (.local payloadId) (.unary .negate (.value (.signed .i32 1))))
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (localRead payloadLocal) negativeOne
    simp [evalBinaryValue, evalSignedBinary, show ¬ payload ≤ -1 by omega]
  exact evaluatesLogicalOrFalse (evaluatesLogicalOrFalse previousCheck earlierCheck) payloadCheck

/-- Execute the token-versus-state validation branch without taking either
    rejection path. The premise is supplied by `reader_child_guard`. -/
theorem child_branch_executes
    (tagLocal : before.local? tagId = some (.signed .i32 tag))
    (payloadLocal : before.local? payloadId = some (.signed .i32 payload))
    (tokenCountLocal : before.local? tokenCountId = some (.signed .i32 tokenCount))
    (currentLocal : before.local? currentId = some (.signed .i32 current))
    (valid : if tag = 1 then payload < tokenCount else tag = 2 ∧ payload < current)
    (reject : Lanius.Core.Stmt) :
    Executes verifiedParserCore before
      (.ifThenElse (.binary .equal (.local tagId) (.constant 38))
        (.sequence (.ifThenElse (.binary .greaterEqual (.local payloadId) (.local tokenCountId))
          reject .skip) .skip)
        (.sequence (.ifThenElse (.binary .logicalOr
          (.binary .notEqual (.local tagId) (.constant 39))
          (.binary .greaterEqual (.local payloadId) (.local currentId))) reject .skip) .skip))
      .next before := by
  have localRead {localId : Lanius.VarId} {value : Lanius.Core.Value}
      (found : before.local? localId = some value) :
      Evaluates verifiedParserCore before (.local localId) value before :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore before localId value found⟩
  have tokenRead : Evaluates verifiedParserCore before (.constant 38) (.signed .i32 1) before :=
    evaluatesConstant (show verifiedParserCore.constant? 38 = some {
      id := 38, type := parserI32Type, value := .signed .i32 1 } from rfl)
  have stateRead : Evaluates verifiedParserCore before (.constant 39) (.signed .i32 2) before :=
    evaluatesConstant (show verifiedParserCore.constant? 39 = some {
      id := 39, type := parserI32Type, value := .signed .i32 2 } from rfl)
  by_cases token : tag = 1
  · have bound : payload < tokenCount := by simpa only [if_pos token] using valid
    have selected : Evaluates verifiedParserCore before
        (.binary .equal (.local tagId) (.constant 38)) (.boolean true) before := by
      apply evaluatesEagerBinary (by decide) (by decide) (localRead tagLocal) tokenRead
      simp [evalBinaryValue, scalarEqual, token]
    have accepted : Evaluates verifiedParserCore before
        (.binary .greaterEqual (.local payloadId) (.local tokenCountId)) (.boolean false) before := by
      apply evaluatesEagerBinary (by decide) (by decide) (localRead payloadLocal) (localRead tokenCountLocal)
      simp [evalBinaryValue, evalSignedBinary, show ¬ tokenCount ≤ payload by omega]
    exact executesIfTrue selected (executesSequence
      (executesIfFalse accepted (executesSkip verifiedParserCore before)) (executesSkip verifiedParserCore before))
  · obtain ⟨stateTag, bound⟩ := (show tag = 2 ∧ payload < current by simpa only [if_neg token] using valid)
    have selected : Evaluates verifiedParserCore before
        (.binary .equal (.local tagId) (.constant 38)) (.boolean false) before := by
      apply evaluatesEagerBinary (by decide) (by decide) (localRead tagLocal) tokenRead
      simp [evalBinaryValue, scalarEqual, stateTag]
    have tagged := evaluates_i32_mismatch_false
      (show Evaluates verifiedParserCore before (.local tagId) (.signed .i32 2) before by
        simpa only [stateTag] using localRead tagLocal) stateRead
    have accepted : Evaluates verifiedParserCore before
        (.binary .greaterEqual (.local payloadId) (.local currentId)) (.boolean false) before := by
      apply evaluatesEagerBinary (by decide) (by decide) (localRead payloadLocal) (localRead currentLocal)
      simp [evalBinaryValue, evalSignedBinary, show ¬ current ≤ payload by omega]
    exact executesIfFalse selected (executesSequence
      (executesIfFalse (evaluatesLogicalOrFalse tagged accepted) (executesSkip verifiedParserCore before))
      (executesSkip verifiedParserCore before))

end Lanius.Extraction.ParserDerivation
