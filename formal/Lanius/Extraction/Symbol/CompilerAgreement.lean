import Lanius.Extraction.Symbol.MainCalls

namespace Lanius.Extraction.Symbol.CompilerAgreement

open Lanius
open Lanius.Compiler
open Lanius.Compiler.Lexer

def inputMatch (input : List Byte) : Behavior.Match :=
  Behavior.classify
    (input[0]?.map (fun byte => Int.ofNat byte.val) |>.getD (-1))
    (input[1]?.map (fun byte => Int.ofNat byte.val) |>.getD (-1))
    (input[2]?.map (fun byte => Int.ofNat byte.val) |>.getD (-1))

def behaviorValue (input : List Byte) : Core.Value :=
  let matched := inputMatch input
  Semantics.value matched.kind matched.length

def compilerValue (input : List Byte) : Option Core.Value :=
  (matchSymbolHead input).map fun rule =>
    Semantics.value (Int.ofNat rule.kind.gpuCode)
      (Int.ofNat rule.spelling.length)

theorem compilerValue_ignores_after_three
    (first second third : Byte) (rest : List Byte) :
    compilerValue (first :: second :: third :: rest) =
      compilerValue [first, second, third] := by
  simp [compilerValue, matchSymbolHead, bestMatching, symbolRules,
    SymbolRule.matches, startsWith, chooseLonger]

theorem behaviorValue_ignores_after_three
    (first second third : Byte) (rest : List Byte) :
    behaviorValue (first :: second :: third :: rest) =
      behaviorValue [first, second, third] := by
  rfl

private def symbolStartBytes : List Byte :=
  [40, 41, 43, 42, 61, 45, 47, 33, 91, 93, 123, 125,
    60, 62, 38, 124, 37, 94, 126, 44, 59, 58, 63, 46]

private def allBytes : List Byte :=
  List.ofFn (fun byte : Fin 256 => byte)

private def compilerPair (input : List Byte) : Option (Int × Int) :=
  (matchSymbolHead input).map fun rule =>
    (Int.ofNat rule.kind.gpuCode, Int.ofNat rule.spelling.length)

private def behaviorPair (input : List Byte) : Int × Int :=
  let matched := inputMatch input
  (matched.kind, matched.length)

private def agrees (input : List Byte) : Bool :=
  compilerPair input == some (behaviorPair input)

private def thirdRepresentative (byte : Byte) : Byte :=
  if byte.val = 61 then 61 else 0

private theorem bestMatching_congr (rules : List SymbolRule) (left right : List Nat)
    (same : ∀ rule ∈ rules, rule.matches left = rule.matches right) :
    bestMatching rules left = bestMatching rules right := by
  induction rules with
  | nil => rfl
  | cons rule rest induction =>
      simp only [bestMatching, same rule (by simp),
        induction (fun entry member => same entry (by simp [member]))]

private theorem compilerPair_third (first second third : Byte) :
    compilerPair [first, second, third] =
      compilerPair [first, second, thirdRepresentative third] := by
  apply congrArg (Option.map _)
  apply bestMatching_congr
  intro rule member
  simp only [symbolRules, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  all_goals by_cases equal : third.val = 61
  all_goals simp [SymbolRule.matches, startsWith, thirdRepresentative, equal,
    beq_iff_eq]
  all_goals first
    | solve | simp [(show (61 : Byte).val = 61 from rfl)]
    | exact fun _ _ same => equal same.symm

private theorem behaviorPair_third (first second third : Byte) :
    behaviorPair [first, second, third] =
      behaviorPair [first, second, thirdRepresentative third] := by
  by_cases equal : third.val = 61
  · have byteEq : third = 61 := Fin.ext equal
    subst third
    rfl
  · have intNe : (third.val : Int) ≠ 61 := by
      intro same
      exact equal (Int.ofNat.inj same)
    simp [behaviorPair, inputMatch, Behavior.classify, thirdRepresentative, equal, intNe]

private theorem agrees_third (first second third : Byte) :
    agrees [first, second, third] = agrees [first, second, thirdRepresentative third] := by
  unfold agrees
  rw [compilerPair_third, behaviorPair_third]

private theorem everyByte_mem (byte : Byte) : byte ∈ allBytes := by
  exact List.mem_ofFn.mpr ⟨byte, rfl⟩

private theorem oneByteAgreement :
    symbolStartBytes.all (fun first => agrees [first]) = true := by
  native_decide

private theorem twoByteAgreement :
    symbolStartBytes.all (fun first =>
      allBytes.all (fun second => agrees [first, second])) = true := by
  native_decide

private theorem threeByteAgreement :
    symbolStartBytes.all (fun first =>
      allBytes.all (fun second =>
        ([0, 61] : List Byte).all (fun third => agrees [first, second, third]))) = true := by
  native_decide

private theorem first_mem_symbolStartBytes
    {first : Byte} {rest : List Byte} {rule : SymbolRule}
    (selected : matchSymbolHead (first :: rest) = some rule) :
    first ∈ symbolStartBytes := by
  have specification := matchSymbolHead_spec selected
  have member := specification.1
  have didMatch := specification.2.1
  simp only [symbolRules, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  all_goals
    simp only [SymbolRule.matches, List.map, startsWith, Bool.and_eq_true,
      beq_iff_eq] at didMatch
    simp [symbolStartBytes, Fin.ext_iff]
    omega

theorem compilerValue_eq_behaviorValue
    {input : List Byte} {rule : SymbolRule}
    (selected : matchSymbolHead input = some rule) :
    compilerValue input = some (behaviorValue input) := by
  cases input with
  | nil =>
    simp [matchSymbolHead, bestMatching, symbolRules, SymbolRule.matches,
      startsWith] at selected
  | cons first rest =>
    have firstMember := first_mem_symbolStartBytes selected
    cases rest with
    | nil =>
      have checked := List.all_eq_true.mp oneByteAgreement first firstMember
      have pairEq : compilerPair [first] = some (behaviorPair [first]) :=
        beq_iff_eq.mp checked
      simpa [compilerPair, behaviorPair, compilerValue, behaviorValue,
        Semantics.value] using congrArg
          (Option.map fun pair => Semantics.value pair.1 pair.2) pairEq
    | cons second rest =>
      cases rest with
      | nil =>
        have checked := List.all_eq_true.mp
          (List.all_eq_true.mp twoByteAgreement first firstMember)
          second (everyByte_mem second)
        have pairEq : compilerPair [first, second] =
            some (behaviorPair [first, second]) := beq_iff_eq.mp checked
        simpa [compilerPair, behaviorPair, compilerValue, behaviorValue,
          Semantics.value] using congrArg
            (Option.map fun pair => Semantics.value pair.1 pair.2) pairEq
      | cons third rest =>
        rw [compilerValue_ignores_after_three,
          behaviorValue_ignores_after_three]
        have checked := List.all_eq_true.mp
          (List.all_eq_true.mp
            (List.all_eq_true.mp threeByteAgreement first firstMember)
            second (everyByte_mem second))
          (thirdRepresentative third) (by by_cases equal : third.val = 61 <;> simp [thirdRepresentative, equal])
        rw [← agrees_third first second third] at checked
        have pairEq : compilerPair [first, second, third] =
            some (behaviorPair [first, second, third]) := beq_iff_eq.mp checked
        simpa [compilerPair, behaviorPair, compilerValue, behaviorValue,
          Semantics.value] using congrArg
            (Option.map fun pair => Semantics.value pair.1 pair.2) pairEq

theorem behaviorValue_eq_selected
    {input : List Byte} {rule : SymbolRule}
    (selected : matchSymbolHead input = some rule) :
    behaviorValue input = Semantics.value (Int.ofNat rule.kind.gpuCode)
      (Int.ofNat rule.spelling.length) := by
  have agreed := compilerValue_eq_behaviorValue selected
  rw [compilerValue, selected] at agreed
  exact Option.some.inj agreed.symm

theorem encoded_eq_behaviorValue (source : List Byte) (start : Nat) :
    Model.encoded source start = behaviorValue (source.drop start) := by
  simp [Model.encoded, Model.logicalMatch, Model.sourceIntegers,
    behaviorValue, inputMatch, Semantics.value]

theorem encoded_eq_selected
    {source : List Byte} {start : Nat} {rule : SymbolRule}
    (selected : matchSymbolHead (source.drop start) = some rule) :
    Model.encoded source start =
      Semantics.value (Int.ofNat rule.kind.gpuCode)
        (Int.ofNat rule.spelling.length) := by
  rw [encoded_eq_behaviorValue]
  exact behaviorValue_eq_selected selected

end Lanius.Extraction.Symbol.CompilerAgreement
