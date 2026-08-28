import Lanius.Compiler.LexerCanonical
import Lanius.Extraction.Artifact

namespace Lanius.Extraction

open Lanius.Compiler
open Lanius.Compiler.Lexer

def decodeByte (value : Nat) : Option Byte :=
  if inRange : value < 256 then some ⟨value, inRange⟩ else none

def decodeBytes (values : List Nat) : Option (List Byte) :=
  values.mapM decodeByte

def decodeSingleSource : List SourceFile → Option (List Byte)
  | [source] => decodeBytes source.bytes
  | _ => none

def decodeToken (token : Token) : Option RawToken := do
  if token.span.file != 0 then none else
  if token.span.start > token.span.finish then none else
  let kind ← TokenKind.ofGpuCode token.kind
  pure ⟨kind, token.span.start, token.span.finish⟩

def decodeTokens (tokens : List Token) : Option (List RawToken) :=
  tokens.mapM decodeToken

/-- The semantic statement certified by the first extraction checker: the
    artifact's exact bytes have exactly the claimed canonical token stream. -/
def TokenArtifactValid (artifact : Artifact) : Prop :=
  ∃ source tokens,
    artifact.schema_version = schemaVersion ∧
    decodeSingleSource artifact.sources = some source ∧
    decodeTokens artifact.tokens = some tokens ∧
    lexCanonical source = .success tokens

/-- Executable checker for the source/token portion of an extraction artifact. -/
def checkTokenArtifact (artifact : Artifact) : Bool :=
  if artifact.schema_version != schemaVersion then false
  else match decodeSingleSource artifact.sources, decodeTokens artifact.tokens with
    | some source, some tokens => lexCanonical source == .success tokens
    | _, _ => false

theorem checkTokenArtifact_sound {artifact : Artifact}
    (accepted : checkTokenArtifact artifact = true) :
    TokenArtifactValid artifact := by
  unfold checkTokenArtifact at accepted
  split at accepted
  · simp at accepted
  · rename_i versionMatches
    have versionEqual : artifact.schema_version = schemaVersion := by
      simpa using versionMatches
    split at accepted
    · rename_i source tokens sourceDecoded tokensDecoded
      have canonical : lexCanonical source = .success tokens := by
        simpa using accepted
      exact ⟨source, tokens, versionEqual, sourceDecoded, tokensDecoded, canonical⟩
    · simp at accepted

private def emptyArtifact (sourceBytes : List Nat) (tokens : List Token) : Artifact :=
  {
    schema_version := schemaVersion
    sources := [{ path := "test.lani", bytes := sourceBytes }]
    tokens := tokens
    semantic_token_kinds := []
    parse_nodes := []
    parse_root := none
    surface := none
    resolutions := []
    types := []
    core_program := none
    lowering := []
  }

private def letArtifact : Artifact :=
  emptyArtifact [108, 101, 116, 32, 120, 32, 61, 32, 49, 50, 59] [
    ⟨68, ⟨0, 0, 3⟩⟩,
    ⟨1, ⟨0, 4, 5⟩⟩,
    ⟨8, ⟨0, 6, 7⟩⟩,
    ⟨2, ⟨0, 8, 10⟩⟩,
    ⟨37, ⟨0, 10, 11⟩⟩
  ]

example : checkTokenArtifact letArtifact = true := by native_decide

example :
    checkTokenArtifact
      (emptyArtifact [108, 101, 116] [⟨1, ⟨0, 0, 3⟩⟩]) = false := by
  native_decide

end Lanius.Extraction
