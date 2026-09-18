import Lanius.Extraction.ParseChecker
import Lanius.Compiler.ParserLanguage

namespace Lanius.Extraction
open Lanius.Compiler.Parser

theorem semanticKindsValid.lookup
    {index : Nat}
    (valid : semanticKindsValid grammar tokens kinds = true)
    (found : kinds[index]? = some code) :
    ∃ token, tokens[index]? = some token ∧ semanticKindMatchesToken grammar token code = true := by
  have checked : tokens.length = kinds.length ∧
      (tokens.zip kinds).all (fun pair => semanticKindMatchesToken grammar pair.1 pair.2) = true := by
    simpa [semanticKindsValid] using valid
  obtain ⟨length, checks⟩ := checked
  have inside := (List.getElem?_eq_some_iff.mp found).1
  have tokenInside : index < tokens.length := by omega
  let token := tokens[index]
  refine ⟨token, List.getElem?_eq_getElem tokenInside, ?_⟩
  have pair : (tokens.zip kinds)[index]? = some (token, code) := by
    exact List.getElem?_zip_eq_some.mpr ⟨List.getElem?_eq_getElem tokenInside, found⟩
  exact List.all_eq_true.mp checks _ (List.mem_of_getElem? pair)

/-- A certified semantic terminal has the same transition in the parser's
physical-token lattice. Split tokens require two distinct physical kinds. -/
theorem advanceTerminal.scanTerminal
    (valid : semanticKindsValid grammar.grammar tokens kinds = true)
    (different : grammar.grammar.split_token_kind ≠ grammar.grammar.split_component_kind)
    (advanced : advanceTerminal kinds position expected = some finish) :
    scanTerminal grammar (tokens.map Token.kind) position expected = some finish := by
  unfold advanceTerminal at advanced
  cases found : kinds[position / 2]? with
  | none => simp [found] at advanced
  | some code =>
      obtain ⟨token, tokenFound, compatible⟩ := semanticKindsValid.lookup valid found
      simp only [found] at advanced
      simp only [bind, Option.bind] at advanced
      simp only [Lanius.Compiler.Parser.scanTerminal, List.getElem?_map, tokenFound, Option.map_some]
      by_cases packed : isPackedSemanticKind code = true
      · simp only [packed, ↓reduceIte] at advanced
        simp only [semanticKindMatchesToken, packed, ↓reduceIte, Bool.and_eq_true, decide_eq_true_eq] at compatible
        obtain ⟨⟨raw, inner⟩, outer⟩ := compatible
        by_cases even : position % 2 = 0
        · simp only [even, ↓reduceIte] at advanced
          split at advanced
          next same =>
            have next := Option.some.inj advanced
            subst finish
            rw [← same]
            simp only [Grammar.canonicalKind?] at inner
            rw [inner]
            simp [scanTerminalStep, raw, even, different]
          next => contradiction
        · simp only [even, ↓reduceIte] at advanced
          split at advanced
          next same =>
            have next := Option.some.inj advanced
            subst finish
            rw [← same]
            simp only [Grammar.canonicalKind?] at outer
            rw [outer]
            have odd : position % 2 = 1 := by omega
            simp [scanTerminalStep, raw, odd]
          next => contradiction
      · simp only [packed, Bool.false_eq_true, ↓reduceIte] at advanced
        simp only [semanticKindMatchesToken, packed, Bool.false_eq_true, ↓reduceIte, Bool.and_eq_true, decide_eq_true_eq] at compatible
        split at advanced
        next yes =>
          have facts : position % 2 = 0 ∧ code = expected := by simpa using yes
          obtain ⟨even, rfl⟩ := facts
          have next := Option.some.inj advanced
          subst finish
          simp only [Grammar.canonicalKind?] at compatible
          rw [compatible.2]
          simp [scanTerminalStep, even]
        next => contradiction

end Lanius.Extraction
