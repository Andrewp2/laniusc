import Lanius.Extraction.SyntaxCheck.Pack
import Lanius.Extraction.SyntaxCheck.Derivation

namespace Lanius.Extraction.SyntaxCheck

open Lanius.Compiler
open Lanius.Compiler.Lexer

/-! The public source-pack boundary.  Every field below is obtained from an
    independently checked certificate; this layer only composes them. -/

structure UnitSound {artifact : Artifact} (checked : CheckedUnit artifact) : Prop where
  sourceIdentity : artifact.sources = [checked.source]
  rawIdentity : artifact.raw_tokens = some checked.raw
  bytesDecoded : decodeBytes checked.source.bytes = some checked.lexer.bytes
  rawDecoded : decodeTokens checked.raw = some checked.lexer.raw
  rawLexing : lexRaw checked.lexer.bytes = .success checked.lexer.raw
  canonicalDecoded : decodeTokens artifact.tokens = some checked.lexer.canonical
  canonicalLexing :
    canonicalizeTokens checked.lexer.bytes checked.lexer.raw = checked.lexer.canonical
  semanticWitness : SemanticWitness laniusGrammar checked.lexer.canonical
    artifact.semantic_token_kinds
  rootDerivation : Derivation laniusGrammar checked.lexer.canonical
    artifact.semantic_token_kinds artifact.parse_nodes checked.parse.root
    laniusGrammar.start_nonterminal 0
      (checked.lexer.canonical.length * 2)
  surfaceReconstructed :
    decodeReconstructedSurface artifact = some checked.surface.surface

def CheckedUnitsSound : {units : List Artifact} → CheckedUnits units → Prop
  | [], .nil => True
  | _ :: _, .cons head tail => UnitSound head ∧ CheckedUnitsSound tail

structure PackSound (encoded : String) (expectedSources : List SourceFile)
    (checked : CheckedSourcePack encoded expectedSources) : Prop where
  decoded : decodeCompactPack? encoded = some checked.compact.pack
  schema : checked.compact.pack.schema_version = schemaVersion
  sourceIdentity : compactPackSources checked.compact.pack = expectedSources
  units : CheckedUnitsSound checked.units

theorem checkedUnit_sound {artifact : Artifact} (checked : CheckedUnit artifact) :
    UnitSound checked := by
  obtain ⟨semanticWitness, rootDerivation⟩ :=
    checkedParseUnit_derivation checked.parse
  exact {
    sourceIdentity := checked.sourceFound
    rawIdentity := checked.rawFound
    bytesDecoded := checked.lexer.bytesDecoded
    rawDecoded := checked.lexer.rawDecoded
    rawLexing := checked.lexer.rawAccepted
    canonicalDecoded := checked.lexer.canonicalDecoded
    canonicalLexing := checked.lexer.canonicalAccepted
    semanticWitness
    rootDerivation
    surfaceReconstructed := checked.surface.reconstructed
  }

theorem checkedUnits_sound : ∀ {units : List Artifact} (checked : CheckedUnits units),
    CheckedUnitsSound checked
  | [], .nil => trivial
  | _ :: _, .cons head tail =>
      ⟨checkedUnit_sound head, checkedUnits_sound tail⟩

theorem checkCompactSourcePack_soundness
    {encoded : String} {expectedSources : List SourceFile}
    {checked : CheckedSourcePack encoded expectedSources}
    (_accepted : checkCompactSourcePack encoded expectedSources = .ok checked) :
    PackSound encoded expectedSources checked := by
  exact {
    decoded := checked.compact.decoded
    schema := checked.compact.schema
    sourceIdentity := checked.compact.sourceIdentity
    units := checkedUnits_sound checked.units
  }

end Lanius.Extraction.SyntaxCheck
