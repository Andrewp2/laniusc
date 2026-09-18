import Lanius.Extraction.CanonicalTokens.KeywordLengthSemantics
import Lanius.Extraction.CanonicalTokens.Dispatch.Lexer

namespace Lanius.Extraction.CanonicalTokens.KeywordTable

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.Extraction.CanonicalTokens

/-! The checked keyword decision list and the mathematical dispatch table have
the same first-match convention.  This bridge keeps the executable constant
lookup in the theorem: the value attached to a row is accepted only after
`constant?` returns the declaration whose value is `Dispatch.tag`. -/

abbrev Rule (arity : Nat) := List (Fin arity × Int) × ConstantId

def ruleQuery {arity : Nat} (rule : Rule arity) : List Int :=
  rule.1.map Prod.snd

def tableRows {arity : Nat}
    (rules : List (Rule arity)) : List Dispatch.Row :=
  rules.map fun rule => (ruleQuery rule, Dispatch.tag verifiedFrontendCore rule.2)

def Matches {arity : Nat} (environment : Env arity) (query : List Int)
    (rules : List (Rule arity)) : Prop :=
  ∀ bytes constant, (bytes, constant) ∈ rules →
    (KeywordLengthSemantics.ruleMatches environment bytes = true ↔
      query = bytes.map Prod.snd)

def Authentic (constant : ConstantId) : Prop :=
  ∃ declaration,
    verifiedFrontendCore.constant? constant = some declaration ∧
      declaration.value =
        .signed .i32 (Dispatch.tag verifiedFrontendCore constant)

theorem firstMatching_lookup
    {arity : Nat} (environment : Env arity) (query : List Int)
    (rules : List (Rule arity)) (fallback : ConstantId)
    (matchEquiv : Matches environment query rules)
    (auth : ∀ bytes constant, (bytes, constant) ∈ rules → Authentic constant)
    (fallbackAuth : Authentic fallback) :
    (verifiedFrontendCore.constant?
      ((KeywordLengthSemantics.firstMatchingConstant environment rules).getD fallback)).map
        (fun declaration => declaration.value) =
      some (.signed .i32
        (Dispatch.lookup query (tableRows rules)
          (Dispatch.tag verifiedFrontendCore fallback))) := by
  induction rules with
  | nil =>
      rcases fallbackAuth with ⟨declaration, found, value⟩
      simp [KeywordLengthSemantics.firstMatchingConstant, found, value,
        tableRows, Dispatch.lookup]
  | cons head tail inductionHypothesis =>
      obtain ⟨bytes, constant⟩ := head
      have headMatch : KeywordLengthSemantics.ruleMatches environment bytes = true ↔
          query = bytes.map Prod.snd :=
        matchEquiv bytes constant (by simp)
      by_cases queryHead : query = bytes.map Prod.snd
      · have matching : KeywordLengthSemantics.ruleMatches environment bytes = true :=
          headMatch.mpr queryHead
        obtain ⟨declaration, found, value⟩ := auth bytes constant (by simp)
        simp only [KeywordLengthSemantics.firstMatchingConstant, matching,
          ↓reduceIte, Option.getD_some, found, Option.map_some, value,
          tableRows, ruleQuery, List.map_cons, Dispatch.lookup, queryHead]
      · have notMatching : KeywordLengthSemantics.ruleMatches environment bytes = false :=
          Bool.eq_false_iff.mpr (fun matching => queryHead (headMatch.mp matching))
        have tailNoAssumption := inductionHypothesis
          (fun nextBytes nextConstant member =>
            matchEquiv nextBytes nextConstant
              (List.mem_cons_of_mem (bytes, constant) member))
          (fun nextBytes nextConstant member =>
            auth nextBytes nextConstant
              (List.mem_cons_of_mem (bytes, constant) member))
        simp only [KeywordLengthSemantics.firstMatchingConstant, notMatching,
          Bool.false_eq_true, ↓reduceIte, tableRows, ruleQuery, List.map_cons,
          Dispatch.lookup, if_neg queryHead]
        exact tailNoAssumption

theorem decision_reference
    {arity : Nat} (environment : Env arity) (query : List Int)
    (rules : List (Rule arity))
    (matchEquiv : Matches environment query rules)
    (auth : ∀ bytes constant, (bytes, constant) ∈ rules → Authentic constant)
    (reference : (tableRows rules).Perm
      (Dispatch.referenceRows.filter
        (fun row => row.1.length == query.length))) :
    (verifiedFrontendCore.constant?
      ((KeywordLengthSemantics.firstMatchingConstant environment rules).getD 7)).map
        (fun declaration => declaration.value) =
      some (.signed .i32 (Model.keywordKind query 0 query.length)) := by
  have referenceConsistent : Dispatch.Consistent
      (Dispatch.referenceRows.filter
        (fun row => row.1.length == query.length)) := by
    intro left leftMember right rightMember same
    exact Dispatch.reference_consistent left (List.mem_filter.mp leftMember).1
      right (List.mem_filter.mp rightMember).1 same
  have rowsConsistent : Dispatch.Consistent (tableRows rules) :=
    referenceConsistent.perm reference.symm
  have fallbackAuth : Authentic 7 := by
    exact ⟨_, rfl, rfl⟩
  rw [firstMatching_lookup environment query rules 7 matchEquiv auth fallbackAuth]
  rw [Dispatch.lookup_permutation query _ reference rowsConsistent]
  rw [Dispatch.lookup_filter_query_length]
  have identifier : Dispatch.tag verifiedFrontendCore 7 = 1 := rfl
  rw [identifier, Dispatch.lookup_reference_lexer]
  simp [Model.keywordKind, Model.keywordSpan] <;> rfl

end Lanius.Extraction.CanonicalTokens.KeywordTable
