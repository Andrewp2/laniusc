import Lanius.Extraction.Frontend.Source
import Lanius.Extraction.Source.Projection
import Lanius.Extraction.CanonicalTokens.Trivia

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- The storage guard tests whole triples, not raw word capacity. Its Boolean
result covers both branches, including zero, exact fit, and spare words. -/
theorem capacity_condition_evaluates (program : Program) (before : State)
    (countId capacityId : VarId) (count words : Nat)
    (countLocal : before.local? countId = some (.signed .i32 count))
    (capacityLocal : before.local? capacityId = some (.signed .i32 words))
    (wordsFit : words ≤ 2147483647) :
    Evaluates program before (capacityCondition countId capacityId)
      (.boolean (!decide (count ≤ words / 3))) before := by
  have quotient := evaluatesNatI32Divide
    (show Evaluates program before (.local capacityId) (.signed .i32 words) before from
      ⟨1, evalLocal_of_local 0 _ _ _ _ capacityLocal⟩)
    (show Evaluates program before (.value (.signed .i32 3)) (.signed .i32 3) before from ⟨1, rfl⟩)
    (by decide) (Nat.le_trans (Nat.div_le_self _ _) wordsFit)
  have compared : Evaluates program before
      (.binary .lessEqual (.local countId) (.binary .divide (.local capacityId) (.value (.signed .i32 3))))
      (.boolean (decide (count ≤ words / 3))) before := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (show Evaluates program before (.local countId) (.signed .i32 count) before from
        ⟨1, evalLocal_of_local 0 _ _ _ _ countLocal⟩) quotient
    change (Except.ok (Value.boolean (decide ((count : Int) ≤ ((words / 3 : Nat) : Int)))) : Except Trap Value) =
      Except.ok (Value.boolean (decide (count ≤ words / 3)))
    simp only [Int.ofNat_le]
  exact evaluatesUnary compared rfl

theorem kinds_capacity_evaluates (program : Program) (before : State) (count capacity : Nat)
    (countLocal : before.local? 20 = some (.signed .i32 count))
    (capacityLocal : before.local? 9 = some (.signed .i32 capacity)) :
    Evaluates program before kindsCapacityCondition (.boolean (!decide (count ≤ capacity))) before := by
  have compared : Evaluates program before (.binary .lessEqual (.local 20) (.local 9))
      (.boolean (decide (count ≤ capacity))) before := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (show Evaluates program before (.local 20) (.signed .i32 count) before from
        ⟨1, evalLocal_of_local 0 _ _ _ _ countLocal⟩)
      (show Evaluates program before (.local 9) (.signed .i32 capacity) before from
        ⟨1, evalLocal_of_local 0 _ _ _ _ capacityLocal⟩)
    change (Except.ok (Value.boolean (decide ((count : Int) ≤ (capacity : Int)))) : Except Trap Value) =
      Except.ok (Value.boolean (decide (count ≤ capacity)))
    simp only [Int.ofNat_le]
  exact evaluatesUnary compared rfl

/-- Successful lexing and sufficient canonical capacity execute both actual
guards. The accessor's fresh allocations are hidden by its empty caller frame;
no guard evaluation or preserved-buffer premise is required. -/
theorem AfterLexer.pass (region : AfterLexer)
    (status : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_status" resultType 0)
    (statusId : region.statusFunction = status.source.function.id)
    (success : CanonicalTokens.Trivia.ConstantAt program.core region.successId 0)
    (before : State) (count words : Nat)
    (wellFormed : StateWellFormed before)
    (resultLocal : before.local? region.lexedId = some
      (.structure resultType [.signed .i32 0, .signed .i32 count, .signed .i32 0]))
    (countLocal : before.local? region.countId = some (.signed .i32 count))
    (capacityLocal : before.local? region.capacityId = some (.signed .i32 words))
    (wordsFit : words ≤ 2147483647) (capacity : 3 * count ≤ words) :
    ∃ after, (∀ lexicalFailure storageFailure rest completion final,
        Executes program.core after rest completion final →
        Executes program.core before ({ region with lexicalFailure, storageFailure, rest }).body completion final) ∧
      CellEffect CellSet.empty before after := by
  obtain ⟨after, statusCall, effect⟩ := status.call wellFormed
    (.singleton (show Evaluates program.core before (.local region.lexedId)
      (.structure resultType [.signed .i32 0, .signed .i32 count, .signed .i32 0]) before from
      ⟨1, evalLocal_of_local 0 _ _ _ _ resultLocal⟩)) rfl
  have statusFalse : Evaluates program.core before region.statusCondition (.boolean false) after := by
    rw [AfterLexer.statusCondition, statusId]
    exact evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant success) rfl
  have divided : count ≤ words / 3 := by omega
  have capacityFalse := capacity_condition_evaluates program.core after region.countId region.capacityId count words
    (effect.empty_preserves_local wellFormed countLocal)
    (effect.empty_preserves_local wellFormed capacityLocal) wordsFit
  simp only [divided, decide_true, Bool.not_true] at capacityFalse
  refine ⟨after, ?_, effect⟩
  intro lexicalFailure storageFailure rest completion final continuation
  exact executesSequence (executesIfFalse statusFalse (executesSkip _ _))
    (executesSequence (executesIfFalse capacityFalse (executesSkip _ _)) continuation)

end Lanius.Extraction.Frontend
