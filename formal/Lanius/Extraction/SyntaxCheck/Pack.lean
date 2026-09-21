import Lanius.Extraction.CompactCheck
import Lanius.Extraction.SurfaceCheck
import Lanius.Extraction.SyntaxCheck.Parse

namespace Lanius.Extraction.SyntaxCheck

/-! The source-to-Surface boundary composes independent certificates.  Core
    synthesis and typing are intentionally not part of this result. -/

structure CheckedUnit (artifact : Artifact) where
  source : SourceFile
  sourceFound : artifact.sources = [source]
  raw : List Token
  rawFound : artifact.raw_tokens = some raw
  lexer : CheckedLexerUnit source raw artifact.tokens
  lexerAccepted : checkLexerUnit source raw artifact.tokens = .ok lexer
  parse : CheckedParseUnit lexer laniusGrammar artifact.semantic_token_kinds
    artifact.parse_nodes artifact.parse_root
  parseAccepted : checkParseUnit lexer laniusGrammar artifact.semantic_token_kinds
    artifact.parse_nodes artifact.parse_root = .ok parse
  surface : CheckedSurface artifact
  surfaceAccepted : checkSurface artifact = some surface

def UnitValid (artifact : Artifact) : Prop :=
  ∃ source raw,
    artifact.sources = [source] ∧ artifact.raw_tokens = some raw ∧
    ∃ lexer : CheckedLexerUnit source raw artifact.tokens,
      checkLexerUnit source raw artifact.tokens = .ok lexer ∧
      ∃ parse : CheckedParseUnit lexer laniusGrammar artifact.semantic_token_kinds
          artifact.parse_nodes artifact.parse_root,
        checkParseUnit lexer laniusGrammar artifact.semantic_token_kinds
            artifact.parse_nodes artifact.parse_root = .ok parse ∧
        ∃ surface : CheckedSurface artifact, checkSurface artifact = some surface

theorem CheckedUnit.unitValid {artifact : Artifact} (checked : CheckedUnit artifact) :
    UnitValid artifact :=
  ⟨checked.source, checked.raw, checked.sourceFound, checked.rawFound,
    checked.lexer, checked.lexerAccepted, checked.parse, checked.parseAccepted,
    checked.surface, checked.surfaceAccepted⟩

inductive UnitCheckStage where
  | sourceCount
  | rawTrace
  | lexer
  | parse
  | surface
deriving DecidableEq, Repr

def checkUnit (artifact : Artifact) : Except UnitCheckStage (CheckedUnit artifact) :=
  match sourceFound : artifact.sources with
  | [source] =>
      match rawFound : artifact.raw_tokens with
      | some raw =>
          match lexerAccepted : checkLexerUnit source raw artifact.tokens with
          | .error _ => .error .lexer
          | .ok lexer =>
              match parseAccepted : checkParseUnit lexer laniusGrammar
                  artifact.semantic_token_kinds artifact.parse_nodes artifact.parse_root with
              | .error _ => .error .parse
              | .ok parse =>
                  match surfaceAccepted : checkSurface artifact with
                  | none => .error .surface
                  | some surface => .ok {
                      source
                      sourceFound := by simpa using sourceFound
                      raw
                      rawFound := by simpa using rawFound
                      lexer
                      lexerAccepted
                      parse
                      parseAccepted
                      surface
                      surfaceAccepted
                    }
      | none => .error .rawTrace
  | _ => .error .sourceCount

theorem checkUnit_sound {artifact : Artifact} {checked : CheckedUnit artifact}
    (_accepted : checkUnit artifact = .ok checked) : UnitValid artifact :=
  checked.unitValid

inductive CheckedUnits : List Artifact → Type
  | nil : CheckedUnits []
  | cons {artifact : Artifact} {rest : List Artifact}
      (head : CheckedUnit artifact) (tail : CheckedUnits rest) :
      CheckedUnits (artifact :: rest)

def checkUnits : (units : List Artifact) → Except UnitCheckStage (CheckedUnits units)
  | [] => .ok .nil
  | artifact :: rest => do
      let head ← checkUnit artifact
      let tail ← checkUnits rest
      pure (.cons head tail)

def UnitsValid : List Artifact → Prop
  | [] => True
  | artifact :: rest => UnitValid artifact ∧ UnitsValid rest

theorem checkedUnits_valid : ∀ {units : List Artifact}, CheckedUnits units → UnitsValid units
  | [], .nil => trivial
  | _ :: _, .cons head tail => ⟨head.unitValid, checkedUnits_valid tail⟩

inductive PackCheckStage where
  | compact
  | unit (stage : UnitCheckStage)
deriving DecidableEq, Repr

structure CheckedSourcePack (encoded : String) (expectedSources : List SourceFile) where
  compact : CheckedCompactSources encoded expectedSources
  units : CheckedUnits compact.pack.units

def checkCompactSourcePack (encoded : String)
    (expectedSources : List SourceFile) :
    Except PackCheckStage (CheckedSourcePack encoded expectedSources) :=
  match checkCompactSources encoded expectedSources with
  | .error _ => .error .compact
  | .ok compact =>
      match checkUnits compact.pack.units with
      | .error stage => .error (.unit stage)
      | .ok units => .ok { compact, units }

theorem checkCompactSourcePack_sound
    {encoded : String} {expectedSources : List SourceFile}
    {checked : CheckedSourcePack encoded expectedSources}
    (_accepted : checkCompactSourcePack encoded expectedSources = .ok checked) :
    decodeCompactPack? encoded = some checked.compact.pack ∧
      checked.compact.pack.schema_version = schemaVersion ∧
      compactPackSources checked.compact.pack = expectedSources ∧
      UnitsValid checked.compact.pack.units := by
  exact ⟨checked.compact.decoded, checked.compact.schema,
    checked.compact.sourceIdentity, checkedUnits_valid checked.units⟩

end Lanius.Extraction.SyntaxCheck
