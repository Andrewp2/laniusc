import Lanius.Extraction.CanonicalTokens.Dispatch.Reference
import Lanius.Extraction.CanonicalTokens.KeywordSpecification

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Compiler Lanius.Compiler.Lexer

/-- Keyword bytes are positive ASCII. Consequently a negative mathematical
i32 cannot become a matching keyword byte through `Int.toNat` truncation. -/
theorem positive_spelling_iff (query : List Int) (spelling : List Nat)
    (positive : ∀ byte ∈ spelling, 0 < byte) :
    query = spelling.map Int.ofNat ↔ query.map Int.toNat = spelling := by
  induction query generalizing spelling with
  | nil => cases spelling <;> simp
  | cons value rest ih =>
      cases spelling with
      | nil => simp
      | cons byte tail =>
          have first := positive byte (by simp)
          have remaining : ∀ byte ∈ tail, 0 < byte :=
            fun byte member => positive byte (List.mem_cons_of_mem _ member)
          simp only [List.map_cons, List.cons.injEq,
            KeywordSpecification.int_eq_ofNat_iff_toNat_eq value byte first, ih tail remaining]

theorem lookup_keywordRules (query : List Int) (rules : List KeywordRule)
    (positive : ∀ rule ∈ rules, ∀ byte ∈ rule.spelling, 0 < byte) :
    lookup query (rules.map fun rule => (rule.spelling.map Int.ofNat, Int.ofNat rule.kind.gpuCode)) 1 =
      Int.ofNat (match exactKeywordKind (query.map Int.toNat) rules with
        | some kind => kind.gpuCode
        | none => 1) := by
  induction rules with
  | nil => rfl
  | cons rule rest ih =>
      have agreement := positive_spelling_iff query rule.spelling (positive rule (by simp))
      have remaining : ∀ rule ∈ rest, ∀ byte ∈ rule.spelling, 0 < byte :=
        fun rule member => positive rule (List.mem_cons_of_mem _ member)
      by_cases same : query = rule.spelling.map Int.ofNat
      · have yes := agreement.mp same
        simp only [List.map_cons, lookup, if_pos same, exactKeywordKind, if_pos yes]
      · have no : query.map Int.toNat ≠ rule.spelling := fun equal => same (agreement.mpr equal)
        simpa only [List.map_cons, lookup, if_neg same, exactKeywordKind, if_neg no] using ih remaining

/-- The new table proof computes exactly the existing independent lexer's
keyword classification, including its treatment of non-byte integers. -/
theorem lookup_reference_lexer (query : List Int) :
    lookup query referenceRows 1 =
      Int.ofNat (match exactKeywordKind (query.map Int.toNat) keywordRules with
        | some kind => kind.gpuCode
        | none => TokenKind.identifier.gpuCode) := by
  have positive : ∀ rule ∈ keywordRules, ∀ byte ∈ rule.spelling, 0 < byte := by decide
  exact lookup_keywordRules query keywordRules positive

end Lanius.Extraction.CanonicalTokens.Dispatch
