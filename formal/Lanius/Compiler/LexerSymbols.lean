import Lanius.Compiler.Lexer
import Lanius.Compiler.Tokens

namespace Lanius.Compiler.Lexer

structure SymbolRule where
  spelling : List Nat
  kind : TokenKind
deriving DecidableEq, Repr

def startsWith : List Nat → List Nat → Bool
  | [], _ => true
  | _ :: _, [] => false
  | expected :: expectedRest, actual :: actualRest =>
      expected == actual && startsWith expectedRest actualRest

def SymbolRule.matches (rule : SymbolRule) (input : List Nat) : Bool :=
  startsWith rule.spelling input

def chooseLonger (candidate current : SymbolRule) : SymbolRule :=
  if current.spelling.length < candidate.spelling.length then candidate else current

def bestMatching : List SymbolRule → List Nat → Option SymbolRule
  | [], _ => none
  | rule :: rules, input =>
      let tailBest := bestMatching rules input
      if rule.matches input then
        match tailBest with
        | none => some rule
        | some current => some (chooseLonger rule current)
      else
        tailBest

def symbolRules : List SymbolRule :=
  [
    ⟨[60, 60, 61], .shiftLeftAssign⟩,
    ⟨[62, 62, 61], .shiftRightAssign⟩,
    ⟨[60, 60], .shiftLeft⟩,
    ⟨[60, 61], .lessEqual⟩,
    ⟨[60, 62], .angleGeneric⟩,
    ⟨[62, 62], .shiftRight⟩,
    ⟨[62, 61], .greaterEqual⟩,
    ⟨[43, 61], .plusAssign⟩,
    ⟨[43, 43], .increment⟩,
    ⟨[45, 61], .minusAssign⟩,
    ⟨[45, 45], .decrement⟩,
    ⟨[45, 62], .arrow⟩,
    ⟨[61, 61], .equal⟩,
    ⟨[61, 62], .matchArrow⟩,
    ⟨[47, 47], .lineComment⟩,
    ⟨[47, 42], .blockComment⟩,
    ⟨[47, 61], .slashAssign⟩,
    ⟨[38, 38], .logicalAnd⟩,
    ⟨[38, 61], .ampersandAssign⟩,
    ⟨[124, 124], .logicalOr⟩,
    ⟨[124, 61], .pipeAssign⟩,
    ⟨[33, 61], .notEqual⟩,
    ⟨[42, 61], .starAssign⟩,
    ⟨[37, 61], .percentAssign⟩,
    ⟨[94, 61], .caretAssign⟩,
    ⟨[46, 46], .dotDot⟩,
    ⟨[60], .less⟩,
    ⟨[62], .greater⟩,
    ⟨[43], .plus⟩,
    ⟨[45], .minus⟩,
    ⟨[61], .assign⟩,
    ⟨[47], .slash⟩,
    ⟨[38], .ampersand⟩,
    ⟨[124], .pipe⟩,
    ⟨[33], .not⟩,
    ⟨[42], .star⟩,
    ⟨[37], .percent⟩,
    ⟨[94], .caret⟩,
    ⟨[46], .dot⟩,
    ⟨[40], .leftParen⟩,
    ⟨[41], .rightParen⟩,
    ⟨[91], .leftBracket⟩,
    ⟨[93], .rightBracket⟩,
    ⟨[123], .leftBrace⟩,
    ⟨[125], .rightBrace⟩,
    ⟨[126], .tilde⟩,
    ⟨[44], .comma⟩,
    ⟨[59], .semicolon⟩,
    ⟨[58], .colon⟩,
    ⟨[63], .question⟩
  ]

def matchSymbolHead (input : List Byte) : Option SymbolRule :=
  bestMatching symbolRules (input.map Fin.val)

def IsLongestMatch
    (rules : List SymbolRule) (input : List Nat) (result : SymbolRule) : Prop :=
  result ∈ rules ∧ result.matches input = true ∧
    ∀ candidate, candidate ∈ rules → candidate.matches input = true →
      candidate.spelling.length ≤ result.spelling.length

theorem chooseLonger_candidate_length_le (candidate current : SymbolRule) :
    candidate.spelling.length ≤ (chooseLonger candidate current).spelling.length := by
  unfold chooseLonger
  by_cases longer : current.spelling.length < candidate.spelling.length
  · simp [longer]
  · simp [longer]
    omega

theorem chooseLonger_current_length_le (candidate current : SymbolRule) :
    current.spelling.length ≤ (chooseLonger candidate current).spelling.length := by
  unfold chooseLonger
  by_cases longer : current.spelling.length < candidate.spelling.length
  · simp [longer]
    omega
  · simp [longer]

theorem bestMatching_sound
    {rules : List SymbolRule} {input : List Nat} {result : SymbolRule}
    (selected : bestMatching rules input = some result) :
    result ∈ rules ∧ result.matches input = true := by
  induction rules generalizing result with
  | nil => simp [bestMatching] at selected
  | cons rule rules inductionHypothesis =>
      unfold bestMatching at selected
      by_cases ruleMatches : rule.matches input = true
      · rw [if_pos ruleMatches] at selected
        cases tailSelection : bestMatching rules input with
        | none =>
            simp [tailSelection] at selected
            subst result
            exact ⟨by simp, ruleMatches⟩
        | some tailResult =>
            simp [tailSelection] at selected
            subst result
            have tailSound := inductionHypothesis tailSelection
            unfold chooseLonger
            split
            · exact ⟨by simp, ruleMatches⟩
            · exact ⟨by simp [tailSound.1], tailSound.2⟩
      · rw [if_neg ruleMatches] at selected
        have tailSound := inductionHypothesis selected
        exact ⟨by simp [tailSound.1], tailSound.2⟩

theorem bestMatching_exists_of_match
    {rules : List SymbolRule} {input : List Nat} {candidate : SymbolRule}
    (member : candidate ∈ rules) (candidateMatches : candidate.matches input = true) :
    ∃ result, bestMatching rules input = some result := by
  induction rules with
  | nil => simp at member
  | cons rule rules inductionHypothesis =>
      simp only [List.mem_cons] at member
      by_cases ruleMatches : rule.matches input = true
      · unfold bestMatching
        rw [if_pos ruleMatches]
        cases bestMatching rules input with
        | none => exact ⟨rule, rfl⟩
        | some tailResult => exact ⟨chooseLonger rule tailResult, rfl⟩
      · rcases member with isCandidate | member
        · subst candidate
          exact False.elim (ruleMatches candidateMatches)
        · obtain ⟨result, selected⟩ := inductionHypothesis member
          exact ⟨result, by simp [bestMatching, ruleMatches, selected]⟩

theorem bestMatching_dominates
    {rules : List SymbolRule} {input : List Nat} {result : SymbolRule}
    (selected : bestMatching rules input = some result) :
    ∀ candidate, candidate ∈ rules → candidate.matches input = true →
      candidate.spelling.length ≤ result.spelling.length := by
  induction rules generalizing result with
  | nil => simp [bestMatching] at selected
  | cons rule rules inductionHypothesis =>
      unfold bestMatching at selected
      by_cases ruleMatches : rule.matches input = true
      · rw [if_pos ruleMatches] at selected
        cases tailSelection : bestMatching rules input with
        | none =>
            simp [tailSelection] at selected
            subst result
            intro candidate member candidateMatches
            simp only [List.mem_cons] at member
            rcases member with isRule | tailMember
            · subst candidate
              exact Nat.le_refl _
            · obtain ⟨tailResult, tailSelected⟩ :=
                bestMatching_exists_of_match tailMember candidateMatches
              rw [tailSelection] at tailSelected
              contradiction
        | some tailResult =>
            simp [tailSelection] at selected
            subst result
            intro candidate member candidateMatches
            simp only [List.mem_cons] at member
            rcases member with isRule | tailMember
            · subst candidate
              exact chooseLonger_candidate_length_le rule tailResult
            · exact Nat.le_trans
                (inductionHypothesis tailSelection candidate tailMember candidateMatches)
                (chooseLonger_current_length_le rule tailResult)
      · rw [if_neg ruleMatches] at selected
        intro candidate member candidateMatches
        simp only [List.mem_cons] at member
        rcases member with isRule | tailMember
        · subst candidate
          exact False.elim (ruleMatches candidateMatches)
        · exact inductionHypothesis selected candidate tailMember candidateMatches

theorem bestMatching_spec
    {rules : List SymbolRule} {input : List Nat} {result : SymbolRule}
    (selected : bestMatching rules input = some result) :
    IsLongestMatch rules input result := by
  have sound := bestMatching_sound selected
  exact ⟨sound.1, sound.2, bestMatching_dominates selected⟩

theorem matchSymbolHead_spec
    {input : List Byte} {result : SymbolRule}
    (selected : matchSymbolHead input = some result) :
    IsLongestMatch symbolRules (input.map Fin.val) result := by
  exact bestMatching_spec selected

theorem startsWith_equal_spelling
    {left right input : List Nat}
    (sameLength : left.length = right.length)
    (leftMatches : startsWith left input = true)
    (rightMatches : startsWith right input = true) :
    left = right := by
  induction left generalizing right input with
  | nil =>
      cases right <;> simp_all
  | cons leftHead leftTail inductionHypothesis =>
      cases right with
      | nil => simp at sameLength
      | cons rightHead rightTail =>
          cases input with
          | nil => simp [startsWith] at leftMatches
          | cons inputHead inputTail =>
              simp only [startsWith, Bool.and_eq_true, beq_iff_eq] at leftMatches rightMatches
              simp only [List.length_cons, Nat.succ.injEq] at sameLength
              have headsEqual : leftHead = rightHead :=
                leftMatches.1.trans rightMatches.1.symm
              subst rightHead
              exact congrArg (List.cons leftHead)
                (inductionHypothesis sameLength leftMatches.2 rightMatches.2)

theorem member_eq_of_unique_spelling
    {rules : List SymbolRule} {left right : SymbolRule}
    (uniqueSpellings : (rules.map SymbolRule.spelling).Nodup)
    (leftMember : left ∈ rules) (rightMember : right ∈ rules)
    (sameSpelling : left.spelling = right.spelling) :
    left = right := by
  induction rules generalizing left right with
  | nil => simp at leftMember
  | cons head tail inductionHypothesis =>
      simp only [List.map_cons, List.nodup_cons] at uniqueSpellings
      simp only [List.mem_cons] at leftMember rightMember
      rcases leftMember with leftIsHead | leftInTail
      · subst left
        rcases rightMember with rightIsHead | rightInTail
        · exact rightIsHead.symm
        · exfalso
          exact uniqueSpellings.1
            (List.mem_map.mpr ⟨right, rightInTail, sameSpelling.symm⟩)
      · rcases rightMember with rightIsHead | rightInTail
        · subst right
          exfalso
          exact uniqueSpellings.1
            (List.mem_map.mpr ⟨left, leftInTail, sameSpelling⟩)
        · exact inductionHypothesis uniqueSpellings.2 leftInTail rightInTail sameSpelling

theorem symbolRules_unique_spellings :
    (symbolRules.map SymbolRule.spelling).Nodup := by
  decide

theorem symbolRules_spelling_length_pos
    {rule : SymbolRule} (member : rule ∈ symbolRules) :
    0 < rule.spelling.length := by
  have allNonempty :
      symbolRules.all (fun candidate => decide (0 < candidate.spelling.length)) = true := by
    native_decide
  have selected := List.all_eq_true.mp allNonempty rule member
  exact of_decide_eq_true selected

theorem IsLongestMatch.functional
    {rules : List SymbolRule} {input : List Nat} {left right : SymbolRule}
    (uniqueSpellings : (rules.map SymbolRule.spelling).Nodup)
    (leftLongest : IsLongestMatch rules input left)
    (rightLongest : IsLongestMatch rules input right) :
    left = right := by
  have leftLengthLe := rightLongest.2.2 left leftLongest.1 leftLongest.2.1
  have rightLengthLe := leftLongest.2.2 right rightLongest.1 rightLongest.2.1
  have sameLength : left.spelling.length = right.spelling.length := by omega
  have sameSpelling := startsWith_equal_spelling sameLength
    leftLongest.2.1 rightLongest.2.1
  exact member_eq_of_unique_spelling uniqueSpellings
    leftLongest.1 rightLongest.1 sameSpelling

theorem matchSymbolHead_result_unique
    {input : List Byte} {left right : SymbolRule}
    (leftResult : matchSymbolHead input = some left)
    (rightResult : matchSymbolHead input = some right) :
    left = right := by
  exact IsLongestMatch.functional symbolRules_unique_spellings
    (matchSymbolHead_spec leftResult) (matchSymbolHead_spec rightResult)

end Lanius.Compiler.Lexer
