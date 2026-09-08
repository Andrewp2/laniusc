import Lanius.Extraction.Parser.Derivation.Writes
import Lanius.Semantics.Sequence

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser

/-- The four stores replace only the header words at the requested offset. -/
theorem header_words_store (leading trailing : List Int) (oldProduction oldOrigin oldPosition oldCount : Int)
    (state : EarleyState) :
    ((((leading ++ [oldProduction, oldOrigin, oldPosition, oldCount] ++ trailing).set leading.length
      (Int.ofNat state.production)).set (leading.length + 1) (Int.ofNat state.origin)).set
      (leading.length + 2) (Int.ofNat state.position)).set (leading.length + 3) (Int.ofNat state.dot) =
      leading ++ [Int.ofNat state.production, Int.ofNat state.origin, Int.ofNat state.position,
        Int.ofNat state.dot] ++ trailing := by
  induction leading with
  | nil => simp
  | cons word leading ih => simpa [Nat.add_assoc] using congrArg (List.cons word) ih

/-- The count stored from the root DOT is the record's child count, once
    the logical reader has established the returned list length. -/
theorem header_children_record (state : EarleyState) (children : List Child)
    (length : children.length = state.dot) :
    [Int.ofNat state.production, Int.ofNat state.origin, Int.ofNat state.position,
      Int.ofNat state.dot] ++ children.flatMap derivationChildWords = derivationRecordWords state children := by
  simp only [derivationRecordWords, length]

/-- Execute the source's four header stores. Position is fetched from the
    retained workspace after the first two writes; every operand is derived
    from the entry locals and the output-only frame. -/
theorem RecognizerWorkspaceArtifact.store_header
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state)
    (distinct : outputCell ≠ workspaceCell)
    (room : slot + 3 < values.length) (slotBound : slot + 3 ≤ 2147483647)
    (outputLocal : before.local? outputId = some (.slice parserI32Type outputCell [] 0 values.length))
    (workspaceLocal : before.local? workspaceId = some
      (.slice parserI32Type workspaceCell [] 0 workspaceValues.length))
    (baseLocal : before.local? baseId = some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (slotLocal : before.local? slotId = some (.signed .i32 (Int.ofNat slot)))
    (productionLocal : before.local? productionId = some (.signed .i32 (Int.ofNat state.production)))
    (originLocal : before.local? originId = some (.signed .i32 (Int.ofNat state.origin)))
    (countLocal : before.local? countId = some (.signed .i32 (Int.ofNat state.dot)))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) }) :
    let index := fun offset : Nat => if offset = 0 then Expr.local slotId else
      .binary .add (.local slotId) (.value (.signed .i32 (Int.ofNat offset)))
    let right := fun offset : Nat => if offset = 0 then Expr.local productionId else
      if offset = 1 then .local originId else if offset = 2 then
        .call extractedParserStateValueFunction.id
          [.local workspaceId, .local baseId, .local stateIdLocal, .constant 31]
      else .local countId
    let store := fun offset => Stmt.expression (.assign .set (.index (.local outputId) (index offset)) (right offset))
    ∃ after, Executes verifiedParserCore before
      (.sequence (store 0) (.sequence (store 1) (.sequence (store 2) (store 3)))) .next after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          ((((values.set slot (Int.ofNat state.production)).set (slot + 1) (Int.ofNat state.origin)).set
            (slot + 2) (Int.ofNat state.position)).set (slot + 3) (Int.ofNat state.dot)))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.local? outputId = some (.slice parserI32Type outputCell [] 0 values.length) ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  dsimp only
  let index := fun offset : Nat => if offset = 0 then Expr.local slotId else
    .binary .add (.local slotId) (.value (.signed .i32 (Int.ofNat offset)))
  let right := fun offset : Nat => if offset = 0 then Expr.local productionId else
    if offset = 1 then .local originId else if offset = 2 then
      .call extractedParserStateValueFunction.id
        [.local workspaceId, .local baseId, .local stateIdLocal, .constant 31]
    else .local countId
  let word := fun offset : Nat => if offset = 0 then Int.ofNat state.production else
    if offset = 1 then Int.ofNat state.origin else Int.ofNat state.position
  have operands : ∀ offset, offset < 3 → ∀ runtime,
      CellEffect (CellSet.singleton outputCell) before runtime →
      Evaluates verifiedParserCore runtime (index offset) (.signed .i32 (Int.ofNat (slot + offset))) runtime ∧
      ∃ afterRight, Evaluates verifiedParserCore runtime (right offset) (.signed .i32 (word offset)) afterRight ∧
        CellEffect CellSet.empty runtime afterRight := by
    intro offset bound runtime effect
    refine ⟨ParserDerivation.output_index_operand wellFormed slotLocal backing effect offset bound (by omega), ?_⟩
    have alternatives : offset = 0 ∨ offset = 1 ∨ offset = 2 := by omega
    rcases alternatives with rfl | rfl | rfl
    · exact ⟨runtime, ParserDerivation.output_local_operand wellFormed productionLocal backing effect,
        CellEffect.refl effect.wellFormed⟩
    · exact ⟨runtime, ParserDerivation.output_local_operand wellFormed originLocal backing effect,
        CellEffect.refl effect.wellFormed⟩
    · exact artifact.read_field_after_output wellFormed found (show 3 < stateWords by decide)
        distinct workspaceLocal baseLocal stateLocal backing effect
        (evaluatesConstant (show verifiedParserCore.constant? 31 = some {
          id := 31, type := parserI32Type, value := .signed .i32 3 } from rfl))
  obtain ⟨middle, triple, middleBacking, middleArtifact, middleLocal, effect⟩ :=
    artifact.store_output_three wellFormed distinct (by omega) outputLocal backing index right word operands
  have lastIndex : Evaluates verifiedParserCore middle (index 3) (.signed .i32 (Int.ofNat (slot + 3))) middle := by
    have sum : Int.ofNat (slot + 3) = Int.ofNat slot + 3 := by simp [Int.natCast_add]
    rw [sum]
    apply evaluatesEagerBinary (by decide) (by decide)
      (ParserDerivation.output_local_operand wellFormed slotLocal backing effect)
      (show Evaluates verifiedParserCore middle (.value (.signed .i32 3)) (.signed .i32 3) middle from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative verifiedParserCore.target _
      (by change 0 ≤ (slot : Int) + 3; omega) (by change (slot : Int) + 3 ≤ 2147483647; omega)]
    rfl
  obtain ⟨after, lastStore, finalBacking, finalArtifact, finalLocal, lastEffect⟩ :=
    middleArtifact.store_output effect.wellFormed distinct
      (by simpa only [List.length_set] using room)
      (by simpa only [List.length_set] using middleLocal) lastIndex
      (ParserDerivation.output_local_operand wellFormed countLocal backing effect)
      (CellEffect.refl effect.wellFormed) middleBacking
  obtain ⟨first, firstStore, rest⟩ := executesSequenceNext_inv triple
  refine ⟨after, executesSequence firstStore (executesSequence_continue rest (executesExpression lastStore)),
    finalBacking, finalArtifact, ?_, effect.trans lastEffect⟩
  simpa only [List.length_set, parserI32Type] using finalLocal

end Lanius.Extraction.ParserRecognize
