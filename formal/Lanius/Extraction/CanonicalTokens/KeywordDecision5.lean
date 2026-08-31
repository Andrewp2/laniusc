import Lanius.Extraction.CanonicalTokens.KeywordSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordDecision5

open Lanius.Compiler.Lexer
open Lanius.Compiler
open Lanius.Extraction.CanonicalTokens

/-- The independent logical keyword specification restricted to five-byte
spellings.  Filtering by length before reducing the table keeps this proof
small and makes the correspondence with the checked decision list explicit. -/
theorem keywordKind_formula (first second third fourth fifth : Int) :
    Model.keywordKind [first, second, third, fourth, fifth] 0 5 =
      if first.toNat = 119 ∧ second.toNat = 104 ∧ third.toNat = 105 ∧
          fourth.toNat = 108 ∧ fifth.toNat = 101 then
        Int.ofNat TokenKind.whileKeyword.gpuCode
      else if first.toNat = 98 ∧ second.toNat = 114 ∧ third.toNat = 101 ∧
          fourth.toNat = 97 ∧ fifth.toNat = 107 then
        Int.ofNat TokenKind.breakKeyword.gpuCode
      else if first.toNat = 102 ∧ second.toNat = 97 ∧ third.toNat = 108 ∧
          fourth.toNat = 115 ∧ fifth.toNat = 101 then
        Int.ofNat TokenKind.falseKeyword.gpuCode
      else if first.toNat = 99 ∧ second.toNat = 111 ∧ third.toNat = 110 ∧
          fourth.toNat = 115 ∧ fifth.toNat = 116 then
        Int.ofNat TokenKind.constKeyword.gpuCode
      else if first.toNat = 109 ∧ second.toNat = 97 ∧ third.toNat = 116 ∧
          fourth.toNat = 99 ∧ fifth.toNat = 104 then
        Int.ofNat TokenKind.matchKeyword.gpuCode
      else if first.toNat = 116 ∧ second.toNat = 114 ∧ third.toNat = 97 ∧
          fourth.toNat = 105 ∧ fifth.toNat = 116 then
        Int.ofNat TokenKind.traitKeyword.gpuCode
      else if first.toNat = 119 ∧ second.toNat = 104 ∧ third.toNat = 101 ∧
          fourth.toNat = 114 ∧ fifth.toNat = 101 then
        Int.ofNat TokenKind.whereKeyword.gpuCode
      else Int.ofNat TokenKind.identifier.gpuCode := by
  change Int.ofNat (match exactKeywordKind
      [first.toNat, second.toNat, third.toNat, fourth.toNat, fifth.toNat]
      keywordRules with
    | some kind => kind.gpuCode
    | none => TokenKind.identifier.gpuCode) = _
  rw [KeywordSpecification.exactKeywordKind_keywordRules_by_length]
  simp [keywordRules, exactKeywordKind]
  by_cases whileKeyword : first.toNat = 119 ∧ second.toNat = 104 ∧
      third.toNat = 105 ∧ fourth.toNat = 108 ∧ fifth.toNat = 101
  · simp [whileKeyword]
  by_cases breakKeyword : first.toNat = 98 ∧ second.toNat = 114 ∧
      third.toNat = 101 ∧ fourth.toNat = 97 ∧ fifth.toNat = 107
  · simp [whileKeyword, breakKeyword]
  by_cases falseKeyword : first.toNat = 102 ∧ second.toNat = 97 ∧
      third.toNat = 108 ∧ fourth.toNat = 115 ∧ fifth.toNat = 101
  · simp [whileKeyword, breakKeyword, falseKeyword]
  by_cases constKeyword : first.toNat = 99 ∧ second.toNat = 111 ∧
      third.toNat = 110 ∧ fourth.toNat = 115 ∧ fifth.toNat = 116
  · simp [whileKeyword, breakKeyword, falseKeyword, constKeyword]
  by_cases matchKeyword : first.toNat = 109 ∧ second.toNat = 97 ∧
      third.toNat = 116 ∧ fourth.toNat = 99 ∧ fifth.toNat = 104
  · simp [whileKeyword, breakKeyword, falseKeyword, constKeyword, matchKeyword]
  by_cases traitKeyword : first.toNat = 116 ∧ second.toNat = 114 ∧
      third.toNat = 97 ∧ fourth.toNat = 105 ∧ fifth.toNat = 116
  · simp [whileKeyword, breakKeyword, falseKeyword, constKeyword, matchKeyword,
      traitKeyword]
  by_cases whereKeyword : first.toNat = 119 ∧ second.toNat = 104 ∧
      third.toNat = 101 ∧ fourth.toNat = 114 ∧ fifth.toNat = 101
  · simp [whileKeyword, breakKeyword, falseKeyword, constKeyword, matchKeyword,
      traitKeyword, whereKeyword]
  simp [whileKeyword, breakKeyword, falseKeyword, constKeyword, matchKeyword,
    traitKeyword, whereKeyword]

theorem firstMatching_formula
    (leading trailing : List Int) (first second third fourth fifth : Int) :
    KeywordLengthSemantics.firstMatchingConstant
      (KeywordSemantics.loaded5Environment leading
        [first, second, third, fourth, fifth] trailing
        first second third fourth fifth)
      KeywordCommand.length5Rules =
    if first = 102 ∧ second = 97 ∧ third = 108 ∧ fourth = 115 ∧ fifth = 101 then
      some 71
    else if first = 99 ∧ second = 111 ∧ third = 110 ∧ fourth = 115 ∧ fifth = 116 then
      some 72
    else if first = 109 ∧ second = 97 ∧ third = 116 ∧ fourth = 99 ∧ fifth = 104 then
      some 75
    else if first = 116 ∧ second = 114 ∧ third = 97 ∧ fourth = 105 ∧ fifth = 116 then
      some 79
    else if first = 119 ∧ second = 104 ∧ third = 101 ∧ fourth = 114 ∧ fifth = 101 then
      some 84
    else if first = 119 ∧ second = 104 ∧ third = 105 ∧ fourth = 108 ∧ fifth = 101 then
      some 66
    else if first = 98 ∧ second = 114 ∧ third = 101 ∧ fourth = 97 ∧ fifth = 107 then
      some 67
    else none := by
  simp only [KeywordLengthSemantics.firstMatchingConstant,
    KeywordLengthSemantics.ruleMatches, KeywordCommand.length5Rules,
    Bool.and_eq_true]
  rw [KeywordSemantics.loaded5Environment_at_four leading
    [first, second, third, fourth, fifth] trailing
    first second third fourth fifth _ (by rfl)]
  rw [KeywordSemantics.loaded5Environment_at_five leading
    [first, second, third, fourth, fifth] trailing
    first second third fourth fifth _ (by rfl)]
  rw [KeywordSemantics.loaded5Environment_at_six leading
    [first, second, third, fourth, fifth] trailing
    first second third fourth fifth _ (by rfl)]
  rw [KeywordSemantics.loaded5Environment_at_seven leading
    [first, second, third, fourth, fifth] trailing
    first second third fourth fifth _ (by rfl)]
  rw [KeywordSemantics.loaded5Environment_at_eight leading
    [first, second, third, fourth, fifth] trailing
    first second third fourth fifth _ (by rfl)]
  simp only [beq_iff_eq, and_true]

private theorem constantValue (id : Nat) (kind : TokenKind)
    (same : (id, kind) ∈ [
      (71, TokenKind.falseKeyword), (72, TokenKind.constKeyword),
      (75, TokenKind.matchKeyword), (79, TokenKind.traitKeyword),
      (84, TokenKind.whereKeyword), (66, TokenKind.whileKeyword),
      (67, TokenKind.breakKeyword), (7, TokenKind.identifier)]) :
    ∃ declaration, verifiedFrontendCore.constant? id = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat kind.gpuCode) := by
  simp at same
  rcases same with same | same | same | same | same | same | same | same
  all_goals rcases same with ⟨rfl, rfl⟩
  all_goals exact ⟨_, rfl, rfl⟩

private theorem int_eq_of_toNat_eq_positive (value : Int) (expected : Nat)
    (positive : 0 < expected) (same : value.toNat = expected) :
    value = Int.ofNat expected := by
  have nonnegative : 0 ≤ value := by
    by_cases nonnegative : 0 ≤ value
    · exact nonnegative
    · have zero := Int.toNat_of_nonpos (show value ≤ 0 by omega)
      omega
  calc
    value = Int.ofNat value.toNat := (Int.toNat_of_nonneg nonnegative).symm
    _ = Int.ofNat expected := congrArg Int.ofNat same

theorem decisionValue
    (leading trailing : List Int) (first second third fourth fifth : Int) :
    KeywordSemantics.decisionValue
      (KeywordSemantics.loaded5Environment leading
        [first, second, third, fourth, fifth] trailing
        first second third fourth fifth)
      KeywordCommand.length5Rules =
    some (.signed .i32
      (Model.keywordKind [first, second, third, fourth, fifth] 0 5)) := by
  rw [show KeywordSemantics.decisionValue
      (KeywordSemantics.loaded5Environment leading
        [first, second, third, fourth, fifth] trailing
        first second third fourth fifth)
      KeywordCommand.length5Rules =
      (verifiedFrontendCore.constant?
        ((KeywordLengthSemantics.firstMatchingConstant
          (KeywordSemantics.loaded5Environment leading
            [first, second, third, fourth, fifth] trailing
            first second third fourth fifth)
          KeywordCommand.length5Rules).getD 7)).map
            (fun declaration => declaration.value) by rfl]
  rw [firstMatching_formula, keywordKind_formula]
  by_cases falseKeyword : first = 102 ∧ second = 97 ∧ third = 108 ∧
      fourth = 115 ∧ fifth = 101
  · rcases falseKeyword with ⟨rfl, rfl, rfl, rfl, rfl⟩
    simpa using constantValue 71 .falseKeyword (by simp)
  by_cases constKeyword : first = 99 ∧ second = 111 ∧ third = 110 ∧
      fourth = 115 ∧ fifth = 116
  · rcases constKeyword with ⟨rfl, rfl, rfl, rfl, rfl⟩
    simpa using constantValue 72 .constKeyword (by simp)
  by_cases matchKeyword : first = 109 ∧ second = 97 ∧ third = 116 ∧
      fourth = 99 ∧ fifth = 104
  · rcases matchKeyword with ⟨rfl, rfl, rfl, rfl, rfl⟩
    simpa using constantValue 75 .matchKeyword (by simp)
  by_cases traitKeyword : first = 116 ∧ second = 114 ∧ third = 97 ∧
      fourth = 105 ∧ fifth = 116
  · rcases traitKeyword with ⟨rfl, rfl, rfl, rfl, rfl⟩
    simpa using constantValue 79 .traitKeyword (by simp)
  by_cases whereKeyword : first = 119 ∧ second = 104 ∧ third = 101 ∧
      fourth = 114 ∧ fifth = 101
  · rcases whereKeyword with ⟨rfl, rfl, rfl, rfl, rfl⟩
    simpa using constantValue 84 .whereKeyword (by simp)
  by_cases whileKeyword : first = 119 ∧ second = 104 ∧ third = 105 ∧
      fourth = 108 ∧ fifth = 101
  · rcases whileKeyword with ⟨rfl, rfl, rfl, rfl, rfl⟩
    simpa using constantValue 66 .whileKeyword (by simp)
  by_cases breakKeyword : first = 98 ∧ second = 114 ∧ third = 101 ∧
      fourth = 97 ∧ fifth = 107
  · rcases breakKeyword with ⟨rfl, rfl, rfl, rfl, rfl⟩
    simpa using constantValue 67 .breakKeyword (by simp)
  have falseKeywordNat : ¬(first.toNat = 102 ∧ second.toNat = 97 ∧
      third.toNat = 108 ∧ fourth.toNat = 115 ∧ fifth.toNat = 101) := by
    rintro ⟨h0, h1, h2, h3, h4⟩
    apply falseKeyword
    exact ⟨int_eq_of_toNat_eq_positive first 102 (by decide) h0,
      int_eq_of_toNat_eq_positive second 97 (by decide) h1,
      int_eq_of_toNat_eq_positive third 108 (by decide) h2,
      int_eq_of_toNat_eq_positive fourth 115 (by decide) h3,
      int_eq_of_toNat_eq_positive fifth 101 (by decide) h4⟩
  have constKeywordNat : ¬(first.toNat = 99 ∧ second.toNat = 111 ∧
      third.toNat = 110 ∧ fourth.toNat = 115 ∧ fifth.toNat = 116) := by
    rintro ⟨h0, h1, h2, h3, h4⟩
    apply constKeyword
    exact ⟨int_eq_of_toNat_eq_positive first 99 (by decide) h0,
      int_eq_of_toNat_eq_positive second 111 (by decide) h1,
      int_eq_of_toNat_eq_positive third 110 (by decide) h2,
      int_eq_of_toNat_eq_positive fourth 115 (by decide) h3,
      int_eq_of_toNat_eq_positive fifth 116 (by decide) h4⟩
  have matchKeywordNat : ¬(first.toNat = 109 ∧ second.toNat = 97 ∧
      third.toNat = 116 ∧ fourth.toNat = 99 ∧ fifth.toNat = 104) := by
    rintro ⟨h0, h1, h2, h3, h4⟩
    apply matchKeyword
    exact ⟨int_eq_of_toNat_eq_positive first 109 (by decide) h0,
      int_eq_of_toNat_eq_positive second 97 (by decide) h1,
      int_eq_of_toNat_eq_positive third 116 (by decide) h2,
      int_eq_of_toNat_eq_positive fourth 99 (by decide) h3,
      int_eq_of_toNat_eq_positive fifth 104 (by decide) h4⟩
  have traitKeywordNat : ¬(first.toNat = 116 ∧ second.toNat = 114 ∧
      third.toNat = 97 ∧ fourth.toNat = 105 ∧ fifth.toNat = 116) := by
    rintro ⟨h0, h1, h2, h3, h4⟩
    apply traitKeyword
    exact ⟨int_eq_of_toNat_eq_positive first 116 (by decide) h0,
      int_eq_of_toNat_eq_positive second 114 (by decide) h1,
      int_eq_of_toNat_eq_positive third 97 (by decide) h2,
      int_eq_of_toNat_eq_positive fourth 105 (by decide) h3,
      int_eq_of_toNat_eq_positive fifth 116 (by decide) h4⟩
  have whereKeywordNat : ¬(first.toNat = 119 ∧ second.toNat = 104 ∧
      third.toNat = 101 ∧ fourth.toNat = 114 ∧ fifth.toNat = 101) := by
    rintro ⟨h0, h1, h2, h3, h4⟩
    apply whereKeyword
    exact ⟨int_eq_of_toNat_eq_positive first 119 (by decide) h0,
      int_eq_of_toNat_eq_positive second 104 (by decide) h1,
      int_eq_of_toNat_eq_positive third 101 (by decide) h2,
      int_eq_of_toNat_eq_positive fourth 114 (by decide) h3,
      int_eq_of_toNat_eq_positive fifth 101 (by decide) h4⟩
  have whileKeywordNat : ¬(first.toNat = 119 ∧ second.toNat = 104 ∧
      third.toNat = 105 ∧ fourth.toNat = 108 ∧ fifth.toNat = 101) := by
    rintro ⟨h0, h1, h2, h3, h4⟩
    apply whileKeyword
    exact ⟨int_eq_of_toNat_eq_positive first 119 (by decide) h0,
      int_eq_of_toNat_eq_positive second 104 (by decide) h1,
      int_eq_of_toNat_eq_positive third 105 (by decide) h2,
      int_eq_of_toNat_eq_positive fourth 108 (by decide) h3,
      int_eq_of_toNat_eq_positive fifth 101 (by decide) h4⟩
  have breakKeywordNat : ¬(first.toNat = 98 ∧ second.toNat = 114 ∧
      third.toNat = 101 ∧ fourth.toNat = 97 ∧ fifth.toNat = 107) := by
    rintro ⟨h0, h1, h2, h3, h4⟩
    apply breakKeyword
    exact ⟨int_eq_of_toNat_eq_positive first 98 (by decide) h0,
      int_eq_of_toNat_eq_positive second 114 (by decide) h1,
      int_eq_of_toNat_eq_positive third 101 (by decide) h2,
      int_eq_of_toNat_eq_positive fourth 97 (by decide) h3,
      int_eq_of_toNat_eq_positive fifth 107 (by decide) h4⟩
  simpa [falseKeyword, constKeyword, matchKeyword, traitKeyword, whereKeyword,
    whileKeyword, breakKeyword, falseKeywordNat, constKeywordNat,
    matchKeywordNat, traitKeywordNat, whereKeywordNat, whileKeywordNat,
    breakKeywordNat] using constantValue 7 .identifier (by simp)

end Lanius.Extraction.CanonicalTokens.KeywordDecision5
