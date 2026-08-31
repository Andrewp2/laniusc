import Lanius.Extraction.CanonicalTokens.KeywordSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordDecision8

open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens

theorem keywordKind_formula
    (first second third fourth fifth sixth seventh eighth : Int) :
    Model.keywordKind
      [first, second, third, fourth, fifth, sixth, seventh, eighth] 0 8 =
    if first.toNat = 99 ∧ second.toNat = 111 ∧ third.toNat = 110 ∧
        fourth.toNat = 116 ∧ fifth.toNat = 105 ∧ sixth.toNat = 110 ∧
        seventh.toNat = 117 ∧ eighth.toNat = 101 then
      Int.ofNat TokenKind.continueKeyword.gpuCode
    else Int.ofNat TokenKind.identifier.gpuCode := by
  change Int.ofNat (match exactKeywordKind
      [first.toNat, second.toNat, third.toNat, fourth.toNat,
        fifth.toNat, sixth.toNat, seventh.toNat, eighth.toNat]
      keywordRules with
    | some kind => kind.gpuCode
    | none => TokenKind.identifier.gpuCode) = _
  rw [KeywordSpecification.exactKeywordKind_keywordRules_by_length]
  simp [keywordRules, exactKeywordKind]
  by_cases continueKeyword : first.toNat = 99 ∧ second.toNat = 111 ∧
      third.toNat = 110 ∧ fourth.toNat = 116 ∧ fifth.toNat = 105 ∧
      sixth.toNat = 110 ∧ seventh.toNat = 117 ∧ eighth.toNat = 101
  · simp [continueKeyword]
  · simp [continueKeyword]

theorem firstMatching_formula
    (leading trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int) :
    KeywordLengthSemantics.firstMatchingConstant
      (KeywordSemantics.loaded8Environment leading
        [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
        first second third fourth fifth sixth seventh eighth)
      KeywordCommand.length8Rules =
    if first = 99 ∧ second = 111 ∧ third = 110 ∧ fourth = 116 ∧
        fifth = 105 ∧ sixth = 110 ∧ seventh = 117 ∧ eighth = 101 then
      some 68
    else none := by
  simp only [KeywordLengthSemantics.firstMatchingConstant,
    KeywordLengthSemantics.ruleMatches, KeywordCommand.length8Rules,
    Bool.and_eq_true]
  rw [KeywordSemantics.loaded8Environment_at_four leading _ trailing
    first second third fourth fifth sixth seventh eighth _ (by rfl)]
  rw [KeywordSemantics.loaded8Environment_at_five leading _ trailing
    first second third fourth fifth sixth seventh eighth _ (by rfl)]
  rw [KeywordSemantics.loaded8Environment_at_six leading _ trailing
    first second third fourth fifth sixth seventh eighth _ (by rfl)]
  rw [KeywordSemantics.loaded8Environment_at_seven leading _ trailing
    first second third fourth fifth sixth seventh eighth _ (by rfl)]
  rw [KeywordSemantics.loaded8Environment_at_eight leading _ trailing
    first second third fourth fifth sixth seventh eighth _ (by rfl)]
  rw [KeywordSemantics.loaded8Environment_at_nine leading _ trailing
    first second third fourth fifth sixth seventh eighth _ (by rfl)]
  rw [KeywordSemantics.loaded8Environment_at_ten leading _ trailing
    first second third fourth fifth sixth seventh eighth _ (by rfl)]
  rw [KeywordSemantics.loaded8Environment_at_eleven leading _ trailing
    first second third fourth fifth sixth seventh eighth _ (by rfl)]
  simp only [beq_iff_eq, and_true]

private theorem constant68 : ∃ declaration,
    verifiedFrontendCore.constant? 68 = some declaration ∧
      declaration.value =
        .signed .i32 (Int.ofNat TokenKind.continueKeyword.gpuCode) := by
  exact ⟨_, rfl, rfl⟩

private theorem constant7 : ∃ declaration,
    verifiedFrontendCore.constant? 7 = some declaration ∧
      declaration.value =
        .signed .i32 (Int.ofNat TokenKind.identifier.gpuCode) := by
  exact ⟨_, rfl, rfl⟩

theorem decisionValue
    (leading trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int) :
    KeywordSemantics.decisionValue
      (KeywordSemantics.loaded8Environment leading
        [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
        first second third fourth fifth sixth seventh eighth)
      KeywordCommand.length8Rules =
    some (.signed .i32 (Model.keywordKind
      [first, second, third, fourth, fifth, sixth, seventh, eighth] 0 8)) := by
  rw [show KeywordSemantics.decisionValue _ KeywordCommand.length8Rules =
      (verifiedFrontendCore.constant?
        ((KeywordLengthSemantics.firstMatchingConstant _
          KeywordCommand.length8Rules).getD 7)).map
            (fun declaration => declaration.value) by rfl]
  rw [firstMatching_formula, keywordKind_formula]
  by_cases continueKeyword : first = 99 ∧ second = 111 ∧ third = 110 ∧
      fourth = 116 ∧ fifth = 105 ∧ sixth = 110 ∧ seventh = 117 ∧ eighth = 101
  · rcases continueKeyword with ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
    simpa using constant68
  have continueKeywordNat : ¬(first.toNat = 99 ∧ second.toNat = 111 ∧
      third.toNat = 110 ∧ fourth.toNat = 116 ∧ fifth.toNat = 105 ∧
      sixth.toNat = 110 ∧ seventh.toNat = 117 ∧ eighth.toNat = 101) := by
    rintro ⟨h0, h1, h2, h3, h4, h5, h6, h7⟩
    apply continueKeyword
    exact ⟨(KeywordSpecification.int_eq_ofNat_iff_toNat_eq first 99
        (by decide)).mpr h0,
      (KeywordSpecification.int_eq_ofNat_iff_toNat_eq second 111
        (by decide)).mpr h1,
      (KeywordSpecification.int_eq_ofNat_iff_toNat_eq third 110
        (by decide)).mpr h2,
      (KeywordSpecification.int_eq_ofNat_iff_toNat_eq fourth 116
        (by decide)).mpr h3,
      (KeywordSpecification.int_eq_ofNat_iff_toNat_eq fifth 105
        (by decide)).mpr h4,
      (KeywordSpecification.int_eq_ofNat_iff_toNat_eq sixth 110
        (by decide)).mpr h5,
      (KeywordSpecification.int_eq_ofNat_iff_toNat_eq seventh 117
        (by decide)).mpr h6,
      (KeywordSpecification.int_eq_ofNat_iff_toNat_eq eighth 101
        (by decide)).mpr h7⟩
  simpa [continueKeyword, continueKeywordNat] using constant7

end Lanius.Extraction.CanonicalTokens.KeywordDecision8
