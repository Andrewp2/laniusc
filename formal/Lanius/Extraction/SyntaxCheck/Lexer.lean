import Lanius.Extraction.ArtifactView
import Lanius.Compiler.LexerCanonical

namespace Lanius.Extraction.SyntaxCheck

open Lanius.Compiler
open Lanius.Compiler.Lexer

/-! This boundary authenticates one source plus its two serialized lexer traces.
    It deliberately says nothing about parsing, Surface, or Core. -/

def decodeToken (token : Extraction.Token) : Option RawToken := do
  let kind ← TokenKind.ofGpuCode token.kind
  if token.span.file = 0 then
    pure { kind, start := token.span.start, finish := token.span.finish }
  else
    none

def decodeTokens (tokens : List Extraction.Token) : Option (List RawToken) :=
  tokens.mapM decodeToken

structure CheckedLexerUnit
    (source : SourceFile) (rawWire canonicalWire : List Extraction.Token) where
  bytes : List Byte
  bytesDecoded : decodeBytes source.bytes = some bytes
  raw : List RawToken
  rawDecoded : decodeTokens rawWire = some raw
  rawAccepted : lexRaw bytes = .success raw
  canonical : List RawToken
  canonicalDecoded : decodeTokens canonicalWire = some canonical
  canonicalAccepted : canonicalizeTokens bytes raw = canonical

inductive LexerCheckStage where
  | bytes
  | rawEncoding
  | rawTrace
  | canonicalEncoding
  | canonicalTrace
deriving DecidableEq, Repr

def checkLexerUnit (source : SourceFile)
    (rawWire canonicalWire : List Extraction.Token) :
    Except LexerCheckStage (CheckedLexerUnit source rawWire canonicalWire) :=
  match bytesDecoded : decodeBytes source.bytes with
  | none => .error .bytes
  | some bytes =>
      match rawDecoded : decodeTokens rawWire with
      | none => .error .rawEncoding
      | some raw =>
          if rawAccepted : lexRaw bytes = .success raw then
            match canonicalDecoded : decodeTokens canonicalWire with
            | none => .error .canonicalEncoding
            | some canonical =>
                if canonicalAccepted : canonicalizeTokens bytes raw = canonical then
                  .ok {
                    bytes
                    bytesDecoded
                    raw
                    rawDecoded
                    rawAccepted
                    canonical
                    canonicalDecoded
                    canonicalAccepted
                  }
                else
                  .error .canonicalTrace
          else
            .error .rawTrace

theorem checkLexerUnit_sound
    {source : SourceFile} {rawWire canonicalWire : List Extraction.Token}
    {checked : CheckedLexerUnit source rawWire canonicalWire}
    (_accepted : checkLexerUnit source rawWire canonicalWire = .ok checked) :
    decodeBytes source.bytes = some checked.bytes ∧
      decodeTokens rawWire = some checked.raw ∧
      lexRaw checked.bytes = .success checked.raw ∧
      decodeTokens canonicalWire = some checked.canonical ∧
      canonicalizeTokens checked.bytes checked.raw = checked.canonical := by
  exact ⟨checked.bytesDecoded, checked.rawDecoded, checked.rawAccepted,
    checked.canonicalDecoded, checked.canonicalAccepted⟩

end Lanius.Extraction.SyntaxCheck
