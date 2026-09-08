import Lanius.Extraction.Parser.Derivation.Runtime
import Lanius.Extraction.Parser.Derivation.Guards

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

private theorem compare_field {reader : ReaderRuntime}
    (held : reader.At stateId remaining before)
    (found : reader.workspace.state? stateId = some state) (fieldBound : field < stateWords)
    (selector : verifiedParserCore.constant? selectorId = some {
      id := selectorId, type := parserI32Type, value := .signed .i32 (Int.ofNat field) })
    (fieldValue : stateFieldValue reader.workspace stateId state field = expected)
    (expectedRead : ∀ runtime, CellEffect CellSet.empty before runtime →
      Evaluates verifiedParserCore runtime expectedExpression (.signed .i32 expected) runtime) :
    ∃ after, Evaluates verifiedParserCore before
      (.binary .notEqual (.call extractedParserStateValueFunction.id
        [.local reader.stores.workspace, .local reader.stores.base, .local reader.stores.current,
          .constant selectorId]) expectedExpression) (.boolean false) after ∧
      reader.At stateId remaining after ∧ CellEffect CellSet.empty before after := by
  obtain ⟨after, read, _, effect⟩ := held.artifact.read_field_locals held.wellFormed found fieldBound
    held.workspaceLocal held.baseLocal (Assertion.localPointsTo_local _ _ _ _ held.currentOwned) selector
  rw [fieldValue] at read
  exact ⟨after, evaluates_i32_mismatch_false read (expectedRead after effect), held.after_read effect, effect⟩

/-- The loop's seed metadata makes every comparison in the final rejection
    guard false, through all five real accessor calls. -/
theorem ReaderRuntime.At.exit_guard {reader : ReaderRuntime} {root : EarleyState}
    (held : reader.At stateId 0 before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (found : reader.workspace.state? stateId = some state)
    (dot : state.dot = 0) (production : state.production = root.production)
    (origin : state.origin = root.origin) (previous : state.previous = none) (child : state.child = .none)
    (productionLocal : before.local? productionId = some (.signed .i32 (Int.ofNat root.production)))
    (originLocal : before.local? originId = some (.signed .i32 (Int.ofNat root.origin))) :
    ∃ after, Evaluates verifiedParserCore before (readerExitCondition reader.stores productionId originId 28)
      (.boolean false) after ∧ reader.At stateId 0 after ∧ CellEffect CellSet.empty before after := by
  obtain ⟨afterDot, dotRead, heldDot, dotEffect⟩ := compare_field held found
    (field := 1) (selectorId := 29) (by decide) (by rfl)
    (by simp [stateFieldValue, dot])
    (show ∀ runtime, CellEffect CellSet.empty before runtime →
      Evaluates verifiedParserCore runtime (.value (.signed .i32 0)) (.signed .i32 0) runtime
      from fun _ _ => ⟨1, rfl⟩)
  obtain ⟨afterProduction, productionRead, heldProduction, productionEffect⟩ := compare_field heldDot found
    (field := 0) (selectorId := 28) (by decide) (by rfl)
    (show stateFieldValue reader.workspace stateId state 0 = Int.ofNat root.production by
      simp [stateFieldValue, production]) (by
      intro runtime effect
      exact ⟨1, evalLocal_of_local 0 verifiedParserCore runtime productionId _
        ((dotEffect.trans effect).empty_preserves_local held.wellFormed productionLocal)⟩)
  have firstTwo := dotEffect.trans productionEffect
  obtain ⟨afterOrigin, originRead, heldOrigin, originEffect⟩ := compare_field heldProduction found
    (field := 2) (selectorId := 30) (by decide) (by rfl)
    (show stateFieldValue reader.workspace stateId state 2 = Int.ofNat root.origin by
      simp [stateFieldValue, origin]) (by
      intro runtime effect
      exact ⟨1, evalLocal_of_local 0 verifiedParserCore runtime originId _
        ((firstTwo.trans effect).empty_preserves_local held.wellFormed originLocal)⟩)
  have firstThree := firstTwo.trans originEffect
  obtain ⟨afterTag, tagRead, heldTag, tagEffect⟩ := compare_field heldOrigin found
    (field := 6) (selectorId := 34) (by decide) (by rfl)
    (show stateFieldValue reader.workspace stateId state 6 = 0 by simp [stateFieldValue, child, childTag])
    (show ∀ runtime, CellEffect CellSet.empty afterOrigin runtime →
      Evaluates verifiedParserCore runtime (.constant 37) (.signed .i32 0) runtime from
      fun _ _ => evaluatesConstant (show verifiedParserCore.constant? 37 = some {
        id := 37, type := parserI32Type, value := .signed .i32 0 } from rfl))
  have firstFour := firstThree.trans tagEffect
  obtain ⟨afterPrevious, previousRead, heldPrevious, previousEffect⟩ := compare_field heldTag found
    (field := 5) (selectorId := 33) (by decide) (by rfl)
    (show stateFieldValue reader.workspace stateId state 5 = -1 by
      simp [stateFieldValue, previous, previousValue, encodeStateId]) (by
      intro runtime _
      apply evaluatesUnary (op := .negate)
        (show Evaluates verifiedParserCore runtime (.value (.signed .i32 1)) (.signed .i32 1) runtime from ⟨1, rfl⟩)
      simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, Core.SignedIntTy.bits])
  refine ⟨afterPrevious, ?_, heldPrevious, firstFour.trans previousEffect⟩
  simpa only [readerExitCondition, accessor] using
    evaluatesLogicalOrFalse (evaluatesLogicalOrFalse
      (evaluatesLogicalOrFalse (evaluatesLogicalOrFalse dotRead productionRead) originRead) tagRead) previousRead

/-- The final guard accepts and the reader returns its saved child count. -/
theorem ReaderRuntime.At.execute_exit {reader : ReaderRuntime} {root : EarleyState}
    (held : reader.At stateId 0 before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (found : reader.workspace.state? stateId = some state)
    (dot : state.dot = 0) (production : state.production = root.production)
    (origin : state.origin = root.origin) (previous : state.previous = none) (child : state.child = .none)
    (productionLocal : before.local? productionId = some (.signed .i32 (Int.ofNat root.production)))
    (originLocal : before.local? originId = some (.signed .i32 (Int.ofNat root.origin)))
    (countLocal : before.local? countId = some (.signed .i32 count)) :
    ∃ after, Executes verifiedParserCore before (readerExit reader.stores productionId originId countId 28)
      (.returned (some (.signed .i32 count))) after ∧
      reader.At stateId 0 after ∧ CellEffect CellSet.empty before after := by
  obtain ⟨after, guard, finalHeld, effect⟩ := held.exit_guard accessor found dot production origin previous child
    productionLocal originLocal
  have countRead : Evaluates verifiedParserCore after (.local countId) (.signed .i32 count) after :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore after countId _
      (effect.empty_preserves_local held.wellFormed countLocal)⟩
  exact ⟨after, executesSequence (executesIfFalse guard (executesSkip verifiedParserCore after))
    (executesSequenceNonNext (executesReturnValue countRead) (by simp)), finalHeld, effect⟩

end Lanius.Extraction.ParserDerivation
