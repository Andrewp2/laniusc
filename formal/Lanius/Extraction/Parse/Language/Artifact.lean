import Lanius.Extraction.Parse.Language.Nodes
import Lanius.Extraction.ArtifactPackChecker

namespace Lanius.Extraction
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser

private theorem kind_code (found : TokenKind.ofGpuCode code = some kind) : kind.gpuCode = code := by
  unfold TokenKind.ofGpuCode at found
  split at found <;> cases found <;> rfl

private theorem decoded_kind (found : decodeToken encoded = some token) : token.kind.gpuCode = encoded.kind := by
  rcases encoded with ⟨kind, ⟨file, start, finish⟩⟩
  simp only [decodeToken] at found
  by_cases wrongFile : file != 0
  · simp [wrongFile] at found
  simp only [wrongFile, Bool.false_eq_true, ↓reduceIte] at found
  by_cases backwards : start > finish
  · simp [backwards] at found
  simp only [backwards, ↓reduceIte] at found
  cases decoded : TokenKind.ofGpuCode kind with
  | none => simp [decoded] at found
  | some decodedKind =>
      have same : ({kind := decodedKind, start, finish} : RawToken) = token := by simpa [decoded] using found
      subst token
      exact kind_code decoded

theorem decodeTokens.kinds (decoded : decodeTokens encoded = some tokens) :
    tokens.map (fun token => token.kind.gpuCode) = encoded.map Token.kind := by
  induction encoded generalizing tokens with
  | nil =>
      have same : [] = tokens := Option.some.inj decoded
      subst tokens
      rfl
  | cons head tail ih =>
      simp only [decodeTokens, List.mapM_cons] at decoded
      cases first : decodeToken head with
      | none => simp [first] at decoded
      | some token =>
          cases rest : tail.mapM decodeToken with
          | none => simp [first, rest] at decoded
          | some decodedTail =>
              have same : token :: decodedTail = tokens := by simpa [first, rest] using decoded
              subst tokens
              simp only [List.map_cons, decoded_kind first, ih rest]

/-- The existing artifact certificate implies the parser's declarative
language for any indexing of the same formal grammar. -/
theorem ParseArtifactValid.recognizes
    (valid : ParseArtifactValid artifact) (identity : grammar.grammar = laniusGrammar)
    (decoded : decodeTokens artifact.tokens = some tokens) :
    RecognizesInput grammar (tokens.map (fun token => token.kind.gpuCode)) := by
  obtain ⟨rootId, _, root⟩ := valid.2.2.2
  have nodes : NodesMatchFrom grammar.grammar artifact.semantic_token_kinds artifact.parse_nodes 0 artifact.parse_nodes :=
    identity.symm ▸ valid.2.2.1
  have semantic : semanticKindsValid grammar.grammar artifact.tokens artifact.semantic_token_kinds = true :=
    identity.symm ▸ valid.2.1
  have recognized := (identity.symm ▸ root).recognizes nodes semantic
    (show grammar.grammar.split_token_kind ≠ grammar.grammar.split_component_kind from by rw [identity]; decide)
    (show grammar.grammar.start_nonterminal < grammar.grammar.n_nonterminals from by rw [identity]; decide)
  simpa only [decodeTokens.kinds decoded] using recognized

def SourceSyntax (file : SourceFile) : Prop :=
  ∃ source tokens, decodeBytes file.bytes = some source ∧ lexCanonical source = .success tokens ∧
    ∀ grammar : IndexedGrammar, grammar.grammar = laniusGrammar →
      RecognizesInput grammar (tokens.map (fun token => token.kind.gpuCode))

theorem ParseArtifactValid.sourceSyntax
    (valid : ParseArtifactValid artifact) (member : file ∈ artifact.sources) : SourceSyntax file := by
  obtain ⟨source, tokens, _, sourceDecoded, tokensDecoded, lexical, _⟩ := valid.1
  have recognized := fun grammar identity => valid.recognizes (grammar := grammar) identity tokensDecoded
  cases sources : artifact.sources with
  | nil => simp [sources] at member
  | cons head tail =>
      cases tail with
      | cons _ _ => simp [sources, decodeSingleSource] at sourceDecoded
      | nil =>
          have same : file = head := by simpa only [sources, List.mem_singleton] using member
          subst file
          exact ⟨source, tokens, by simpa only [sources, decodeSingleSource] using sourceDecoded, lexical, recognized⟩

theorem ArtifactPackChecker.CheckedUnitSurfaces.sourceSyntax :
    {artifacts : List Artifact} → ArtifactPackChecker.CheckedUnitSurfaces artifacts →
      ∀ file ∈ artifacts.flatMap (·.sources), SourceSyntax file
  | [], .nil, _, member => by cases member
  | _ :: _, .cons head tail, file, member => by
      simp only [List.flatMap_cons, List.mem_append] at member
      rcases member with here | later
      · exact head.valid.1.sourceSyntax here
      · exact tail.sourceSyntax file later

end Lanius.Extraction
