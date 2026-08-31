import Lanius.Extraction.CanonicalTokens.KeywordSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordDecision6

open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens

theorem keywordKind_formula
    (first second third fourth fifth sixth : Int) :
    Model.keywordKind [first, second, third, fourth, fifth, sixth] 0 6 =
    if first.toNat = 114 ∧ second.toNat = 101 ∧ third.toNat = 116 ∧
        fourth.toNat = 117 ∧ fifth.toNat = 114 ∧ sixth.toNat = 110 then
      Int.ofNat TokenKind.returnKeyword.gpuCode
    else if first.toNat = 101 ∧ second.toNat = 120 ∧ third.toNat = 116 ∧
        fourth.toNat = 101 ∧ fifth.toNat = 114 ∧ sixth.toNat = 110 then
      Int.ofNat TokenKind.externKeyword.gpuCode
    else if first.toNat = 105 ∧ second.toNat = 109 ∧ third.toNat = 112 ∧
        fourth.toNat = 111 ∧ fifth.toNat = 114 ∧ sixth.toNat = 116 then
      Int.ofNat TokenKind.importKeyword.gpuCode
    else if first.toNat = 109 ∧ second.toNat = 111 ∧ third.toNat = 100 ∧
        fourth.toNat = 117 ∧ fifth.toNat = 108 ∧ sixth.toNat = 101 then
      Int.ofNat TokenKind.moduleKeyword.gpuCode
    else if first.toNat = 115 ∧ second.toNat = 116 ∧ third.toNat = 114 ∧
        fourth.toNat = 117 ∧ fifth.toNat = 99 ∧ sixth.toNat = 116 then
      Int.ofNat TokenKind.structKeyword.gpuCode
    else Int.ofNat TokenKind.identifier.gpuCode := by
  change Int.ofNat (match exactKeywordKind
      [first.toNat, second.toNat, third.toNat, fourth.toNat,
        fifth.toNat, sixth.toNat] keywordRules with
    | some kind => kind.gpuCode
    | none => TokenKind.identifier.gpuCode) = _
  rw [KeywordSpecification.exactKeywordKind_keywordRules_by_length]
  simp [keywordRules, exactKeywordKind]
  by_cases returnKeyword : first.toNat = 114 ∧ second.toNat = 101 ∧
      third.toNat = 116 ∧ fourth.toNat = 117 ∧ fifth.toNat = 114 ∧
      sixth.toNat = 110
  · simp [returnKeyword]
  by_cases externKeyword : first.toNat = 101 ∧ second.toNat = 120 ∧
      third.toNat = 116 ∧ fourth.toNat = 101 ∧ fifth.toNat = 114 ∧
      sixth.toNat = 110
  · simp [externKeyword]
  by_cases importKeyword : first.toNat = 105 ∧ second.toNat = 109 ∧
      third.toNat = 112 ∧ fourth.toNat = 111 ∧ fifth.toNat = 114 ∧
      sixth.toNat = 116
  · simp [importKeyword]
  by_cases moduleKeyword : first.toNat = 109 ∧ second.toNat = 111 ∧
      third.toNat = 100 ∧ fourth.toNat = 117 ∧ fifth.toNat = 108 ∧
      sixth.toNat = 101
  · simp [moduleKeyword]
  by_cases structKeyword : first.toNat = 115 ∧ second.toNat = 116 ∧
      third.toNat = 114 ∧ fourth.toNat = 117 ∧ fifth.toNat = 99 ∧
      sixth.toNat = 116
  · simp [structKeyword]
  simp [returnKeyword, externKeyword, importKeyword, moduleKeyword, structKeyword]

theorem firstMatching_formula
    (leading trailing : List Int)
    (first second third fourth fifth sixth : Int) :
    KeywordLengthSemantics.firstMatchingConstant
      (KeywordSemantics.loaded6Environment leading
        [first, second, third, fourth, fifth, sixth] trailing
        first second third fourth fifth sixth)
      KeywordCommand.length6Rules =
    if first = 114 ∧ second = 101 ∧ third = 116 ∧ fourth = 117 ∧
        fifth = 114 ∧ sixth = 110 then some 63
    else if first = 115 ∧ second = 116 ∧ third = 114 ∧ fourth = 117 ∧
        fifth = 99 ∧ sixth = 116 then some 74
    else if first = 101 ∧ second = 120 ∧ third = 116 ∧ fourth = 101 ∧
        fifth = 114 ∧ sixth = 110 then some 82
    else if first = 105 ∧ second = 109 ∧ third = 112 ∧ fourth = 111 ∧
        fifth = 114 ∧ sixth = 116 then some 76
    else if first = 109 ∧ second = 111 ∧ third = 100 ∧ fourth = 117 ∧
        fifth = 108 ∧ sixth = 101 then some 77
    else none := by
  simp only [KeywordLengthSemantics.firstMatchingConstant,
    KeywordLengthSemantics.ruleMatches, KeywordCommand.length6Rules,
    Bool.and_eq_true]
  rw [KeywordSemantics.loaded6Environment_at_four leading _ trailing
    first second third fourth fifth sixth _ (by rfl)]
  rw [KeywordSemantics.loaded6Environment_at_five leading _ trailing
    first second third fourth fifth sixth _ (by rfl)]
  rw [KeywordSemantics.loaded6Environment_at_six leading _ trailing
    first second third fourth fifth sixth _ (by rfl)]
  rw [KeywordSemantics.loaded6Environment_at_seven leading _ trailing
    first second third fourth fifth sixth _ (by rfl)]
  rw [KeywordSemantics.loaded6Environment_at_eight leading _ trailing
    first second third fourth fifth sixth _ (by rfl)]
  rw [KeywordSemantics.loaded6Environment_at_nine leading _ trailing
    first second third fourth fifth sixth _ (by rfl)]
  simp only [beq_iff_eq, and_true]

private theorem constantValue (id : Nat) (kind : TokenKind)
    (same : (id, kind) ∈ [
      (63, TokenKind.returnKeyword), (74, TokenKind.structKeyword),
      (82, TokenKind.externKeyword), (76, TokenKind.importKeyword),
      (77, TokenKind.moduleKeyword), (7, TokenKind.identifier)]) :
    ∃ declaration, verifiedFrontendCore.constant? id = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat kind.gpuCode) := by
  simp at same
  rcases same with same | same | same | same | same | same
  all_goals rcases same with ⟨rfl, rfl⟩
  all_goals exact ⟨_, rfl, rfl⟩

private theorem sixIntAgreement
    (a b c d e f : Int) (na nb nc nd ne nf : Nat)
    (pa : 0 < na) (pb : 0 < nb) (pc : 0 < nc)
    (pd : 0 < nd) (pe : 0 < ne) (pf : 0 < nf) :
    (a = Int.ofNat na ∧ b = Int.ofNat nb ∧ c = Int.ofNat nc ∧
      d = Int.ofNat nd ∧ e = Int.ofNat ne ∧ f = Int.ofNat nf) ↔
    (a.toNat = na ∧ b.toNat = nb ∧ c.toNat = nc ∧ d.toNat = nd ∧
      e.toNat = ne ∧ f.toNat = nf) := by
  rw [KeywordSpecification.int_eq_ofNat_iff_toNat_eq a na pa,
    KeywordSpecification.int_eq_ofNat_iff_toNat_eq b nb pb,
    KeywordSpecification.int_eq_ofNat_iff_toNat_eq c nc pc,
    KeywordSpecification.int_eq_ofNat_iff_toNat_eq d nd pd,
    KeywordSpecification.int_eq_ofNat_iff_toNat_eq e ne pe,
    KeywordSpecification.int_eq_ofNat_iff_toNat_eq f nf pf]

theorem decisionValue
    (leading trailing : List Int)
    (first second third fourth fifth sixth : Int) :
    KeywordSemantics.decisionValue
      (KeywordSemantics.loaded6Environment leading
        [first, second, third, fourth, fifth, sixth] trailing
        first second third fourth fifth sixth)
      KeywordCommand.length6Rules =
    some (.signed .i32
      (Model.keywordKind [first, second, third, fourth, fifth, sixth] 0 6)) := by
  rw [show KeywordSemantics.decisionValue _ KeywordCommand.length6Rules =
      (verifiedFrontendCore.constant?
        ((KeywordLengthSemantics.firstMatchingConstant _
          KeywordCommand.length6Rules).getD 7)).map
            (fun declaration => declaration.value) by rfl]
  rw [firstMatching_formula, keywordKind_formula]
  have returnAgreement :
      (first = 114 ∧ second = 101 ∧ third = 116 ∧ fourth = 117 ∧
        fifth = 114 ∧ sixth = 110) ↔
      (first.toNat = 114 ∧ second.toNat = 101 ∧ third.toNat = 116 ∧
        fourth.toNat = 117 ∧ fifth.toNat = 114 ∧ sixth.toNat = 110) := by
    simpa using sixIntAgreement first second third fourth fifth sixth
      114 101 116 117 114 110 (by decide) (by decide) (by decide)
      (by decide) (by decide) (by decide)
  have structAgreement :
      (first = 115 ∧ second = 116 ∧ third = 114 ∧ fourth = 117 ∧
        fifth = 99 ∧ sixth = 116) ↔
      (first.toNat = 115 ∧ second.toNat = 116 ∧ third.toNat = 114 ∧
        fourth.toNat = 117 ∧ fifth.toNat = 99 ∧ sixth.toNat = 116) := by
    simpa using sixIntAgreement first second third fourth fifth sixth
      115 116 114 117 99 116 (by decide) (by decide) (by decide)
      (by decide) (by decide) (by decide)
  have externAgreement :
      (first = 101 ∧ second = 120 ∧ third = 116 ∧ fourth = 101 ∧
        fifth = 114 ∧ sixth = 110) ↔
      (first.toNat = 101 ∧ second.toNat = 120 ∧ third.toNat = 116 ∧
        fourth.toNat = 101 ∧ fifth.toNat = 114 ∧ sixth.toNat = 110) := by
    simpa using sixIntAgreement first second third fourth fifth sixth
      101 120 116 101 114 110 (by decide) (by decide) (by decide)
      (by decide) (by decide) (by decide)
  have importAgreement :
      (first = 105 ∧ second = 109 ∧ third = 112 ∧ fourth = 111 ∧
        fifth = 114 ∧ sixth = 116) ↔
      (first.toNat = 105 ∧ second.toNat = 109 ∧ third.toNat = 112 ∧
        fourth.toNat = 111 ∧ fifth.toNat = 114 ∧ sixth.toNat = 116) := by
    simpa using sixIntAgreement first second third fourth fifth sixth
      105 109 112 111 114 116 (by decide) (by decide) (by decide)
      (by decide) (by decide) (by decide)
  have moduleAgreement :
      (first = 109 ∧ second = 111 ∧ third = 100 ∧ fourth = 117 ∧
        fifth = 108 ∧ sixth = 101) ↔
      (first.toNat = 109 ∧ second.toNat = 111 ∧ third.toNat = 100 ∧
        fourth.toNat = 117 ∧ fifth.toNat = 108 ∧ sixth.toNat = 101) := by
    simpa using sixIntAgreement first second third fourth fifth sixth
      109 111 100 117 108 101 (by decide) (by decide) (by decide)
      (by decide) (by decide) (by decide)
  simp only [returnAgreement, structAgreement, externAgreement, importAgreement,
    moduleAgreement]
  by_cases returnKeyword : first.toNat = 114 ∧ second.toNat = 101 ∧
      third.toNat = 116 ∧ fourth.toNat = 117 ∧ fifth.toNat = 114 ∧
      sixth.toNat = 110
  · simpa [returnKeyword] using constantValue 63 .returnKeyword (by simp)
  by_cases structKeyword : first.toNat = 115 ∧ second.toNat = 116 ∧
      third.toNat = 114 ∧ fourth.toNat = 117 ∧ fifth.toNat = 99 ∧
      sixth.toNat = 116
  · simpa [returnKeyword, structKeyword] using
      constantValue 74 .structKeyword (by simp)
  by_cases externKeyword : first.toNat = 101 ∧ second.toNat = 120 ∧
      third.toNat = 116 ∧ fourth.toNat = 101 ∧ fifth.toNat = 114 ∧
      sixth.toNat = 110
  · simpa [returnKeyword, structKeyword, externKeyword] using
      constantValue 82 .externKeyword (by simp)
  by_cases importKeyword : first.toNat = 105 ∧ second.toNat = 109 ∧
      third.toNat = 112 ∧ fourth.toNat = 111 ∧ fifth.toNat = 114 ∧
      sixth.toNat = 116
  · simpa [returnKeyword, structKeyword, externKeyword, importKeyword] using
      constantValue 76 .importKeyword (by simp)
  by_cases moduleKeyword : first.toNat = 109 ∧ second.toNat = 111 ∧
      third.toNat = 100 ∧ fourth.toNat = 117 ∧ fifth.toNat = 108 ∧
      sixth.toNat = 101
  · simpa [returnKeyword, structKeyword, externKeyword, importKeyword,
      moduleKeyword] using constantValue 77 .moduleKeyword (by simp)
  simpa [returnKeyword, structKeyword, externKeyword, importKeyword,
    moduleKeyword] using constantValue 7 .identifier (by simp)

end Lanius.Extraction.CanonicalTokens.KeywordDecision6
