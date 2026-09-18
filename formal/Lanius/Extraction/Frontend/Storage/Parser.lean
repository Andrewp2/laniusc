import Lanius.Compiler.Parser.Envelope.Decode
import Lanius.Extraction.Entry.Grammar.Indexed
import Lanius.Extraction.Parse.Language.Artifact

namespace Lanius.Extraction.Frontend
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser

/-- A source-only, non-circular resource domain: lexical meaning plus a
finite closed envelope below the physical parser capacity. No source-parser
execution or successful result is assumed. -/
def SourceParserStorage (file : SourceFile) (workspaceWords : Nat) : Prop :=
  ∃ source tokens items, decodeBytes file.bytes = some source ∧
    lexCanonical source = .success tokens ∧
    items.length < stateCapacity tokens.length workspaceWords ∧
    ∀ grammar : IndexedGrammar, grammar.grammar = laniusGrammar →
      ChartClosed grammar (tokens.map (fun token => token.kind.gpuCode)) (Envelope.workspace items)

def SourcesParserStorage (sources : List SourceFile) (workspaceWords : Nat) : Prop :=
  ∀ file ∈ sources, SourceParserStorage file workspaceWords

theorem sourcesParserStorage_of_certificate (valid : TokenArtifactValid artifact)
    (certificate : Envelope.Checked Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind)
      (stateCapacity artifact.tokens.length workspaceWords)) :
    SourcesParserStorage artifact.sources workspaceWords := by
    intro file member
    obtain ⟨source, tokens, _, sourceDecoded, tokensDecoded, lexical, _⟩ := valid
    have codes := decodeTokens.kinds tokensDecoded
    have lengthEq : tokens.length = artifact.tokens.length := by
      simpa only [List.length_map] using congrArg List.length codes
    have closed (grammar : IndexedGrammar) (identity : grammar.grammar = laniusGrammar) :
        ChartClosed grammar (tokens.map (fun token => token.kind.gpuCode)) (Envelope.workspace certificate.items) := by
      rw [codes]
      apply Envelope.check_closed
      rw [Envelope.check_grammar_congr (right := Entry.Grammar.indexedLanius) identity]
      exact certificate.closed
    have fits : certificate.items.length < stateCapacity tokens.length workspaceWords := by
      rw [lengthEq]
      exact certificate.fits
    cases sources : artifact.sources with
    | nil => simp [sources] at member
    | cons head tail =>
      cases tail with
      | cons _ _ => simp [sources, decodeSingleSource] at sourceDecoded
      | nil =>
        have same : file = head := by simpa only [sources, List.mem_singleton] using member
        subst file
        exact ⟨source, tokens, certificate.items,
          by simpa only [sources, decodeSingleSource] using sourceDecoded,
          lexical, fits, closed⟩

def checkArtifactParserStorage? (artifact : Artifact) (valid : TokenArtifactValid artifact)
    (workspaceWords : Nat) (candidate : Envelope.Candidate) :
    Option (PLift (SourcesParserStorage artifact.sources workspaceWords)) := do
  if candidate.tokenCount != artifact.tokens.length then none else do
  let certificate ← Envelope.check? Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind)
    (stateCapacity artifact.tokens.length workspaceWords) candidate.items
  pure ⟨sourcesParserStorage_of_certificate valid certificate⟩

/-- Reuse accepted lexical evidence and check exactly one candidate per
unit. Neither missing nor surplus candidates can be silently ignored. -/
def checkUnitsParserStorage? (workspaceWords : Nat) :
    (artifacts : List Artifact) → (∀ artifact ∈ artifacts, TokenArtifactValid artifact) →
      List Envelope.Candidate →
      Option (PLift (SourcesParserStorage (artifacts.flatMap (·.sources)) workspaceWords))
  | [], _, [] => some ⟨by intro file member; cases member⟩
  | head :: tail, valid, first :: rest => do
    let headStorage ← checkArtifactParserStorage? head (valid head (by simp)) workspaceWords first
    let tailStorage ← checkUnitsParserStorage? workspaceWords tail
      (fun artifact member => valid artifact (by simp [member])) rest
    pure ⟨by
      intro file member
      simp only [List.flatMap_cons, List.mem_append] at member
      rcases member with here | later
      · exact headStorage.down file here
      · exact tailStorage.down file later⟩
  | _, _, _ => none

end Lanius.Extraction.Frontend
