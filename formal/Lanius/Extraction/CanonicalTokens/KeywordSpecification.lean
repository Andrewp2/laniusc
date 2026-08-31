import Lanius.Compiler.LexerCanonical

namespace Lanius.Extraction.CanonicalTokens.KeywordSpecification

open Lanius.Compiler.Lexer

/-- Keyword lookup may discard every rule whose spelling length differs from
the query before comparing bytes.  This makes each fixed-width proof depend
only on its same-width table instead of repeatedly normalizing all 25 rules. -/
theorem exactKeywordKind_filter_length
    (spelling : List Nat) (rules : List KeywordRule) :
    exactKeywordKind spelling rules =
      exactKeywordKind spelling
        (rules.filter (fun rule => rule.spelling.length == spelling.length)) := by
  induction rules with
  | nil => rfl
  | cons rule rest inductionHypothesis =>
      by_cases sameSpelling : spelling = rule.spelling
      · subst spelling
        simp [exactKeywordKind]
      · by_cases sameLength : rule.spelling.length = spelling.length
        · simp [exactKeywordKind, sameSpelling, sameLength,
            inductionHypothesis]
        · simp [exactKeywordKind, sameSpelling, sameLength,
            inductionHypothesis]

theorem exactKeywordKind_keywordRules_by_length (spelling : List Nat) :
    exactKeywordKind spelling keywordRules =
      exactKeywordKind spelling
        (keywordRules.filter
          (fun rule => rule.spelling.length == spelling.length)) :=
  exactKeywordKind_filter_length spelling keywordRules

theorem exactKeywordKind_none_of_unsupported_length (spelling : List Nat)
    (not2 : spelling.length ≠ 2) (not3 : spelling.length ≠ 3)
    (not4 : spelling.length ≠ 4) (not5 : spelling.length ≠ 5)
    (not6 : spelling.length ≠ 6) (not8 : spelling.length ≠ 8) :
    exactKeywordKind spelling keywordRules = none := by
  have two : 2 ≠ spelling.length := Ne.symm not2
  have three : 3 ≠ spelling.length := Ne.symm not3
  have four : 4 ≠ spelling.length := Ne.symm not4
  have five : 5 ≠ spelling.length := Ne.symm not5
  have six : 6 ≠ spelling.length := Ne.symm not6
  have eight : 8 ≠ spelling.length := Ne.symm not8
  rw [exactKeywordKind_keywordRules_by_length]
  simp [keywordRules, exactKeywordKind, two, three, four, five, six, eight]

/-- A positive byte value is represented faithfully by `Int.toNat`.  Keyword
tables contain only positive ASCII values, so this bridges the checked i32
comparisons and the independent natural-number spelling model. -/
theorem int_eq_ofNat_iff_toNat_eq (value : Int) (expected : Nat)
    (positive : 0 < expected) :
    value = Int.ofNat expected ↔ value.toNat = expected := by
  constructor
  · intro same
    subst value
    simp
  · intro same
    have nonnegative : 0 ≤ value := by
      by_cases nonnegative : 0 ≤ value
      · exact nonnegative
      · have zero := Int.toNat_of_nonpos (show value ≤ 0 by omega)
        omega
    calc
      value = Int.ofNat value.toNat := (Int.toNat_of_nonneg nonnegative).symm
      _ = Int.ofNat expected := congrArg Int.ofNat same

@[simp] theorem int_eq_ofNat_iff_toNat_eq_simp {value : Int} {expected : Nat}
    (positive : 0 < expected) :
    value = Int.ofNat expected ↔ value.toNat = expected :=
  int_eq_ofNat_iff_toNat_eq value expected positive

end Lanius.Extraction.CanonicalTokens.KeywordSpecification
