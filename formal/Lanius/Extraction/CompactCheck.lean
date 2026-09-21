import Lanius.Extraction.CompactDecode.Reader

namespace Lanius.Extraction

/-! The first certificate boundary authenticates only the compact wire image.
    Syntax, Surface, and Core validity deliberately remain later stages. -/

def decodeCompactPack? (encoded : String) : Option ArtifactPack :=
  (CompactDecode.readPack.run { bytes := encoded.toUTF8, offset := 0 }).map Prod.fst

def compactPackSources (pack : ArtifactPack) : List SourceFile :=
  pack.units.flatMap (fun artifact => artifact.sources)

structure CheckedCompactSources (encoded : String)
    (expectedSources : List SourceFile) where
  pack : ArtifactPack
  decoded : decodeCompactPack? encoded = some pack
  schema : pack.schema_version = schemaVersion
  sourceIdentity : compactPackSources pack = expectedSources

inductive CompactCheckStage where
  | decode
  | schema
  | sources
deriving DecidableEq, Repr

def checkCompactSources (encoded : String)
    (expectedSources : List SourceFile) :
    Except CompactCheckStage (CheckedCompactSources encoded expectedSources) :=
  match decoded : decodeCompactPack? encoded with
  | none => .error .decode
  | some pack =>
      if schema : pack.schema_version = schemaVersion then
        if sources : compactPackSources pack = expectedSources then
          .ok {
            pack
            decoded
            schema
            sourceIdentity := sources
          }
        else .error .sources
      else .error .schema

theorem checkCompactSources_sound
    {encoded : String} {expectedSources : List SourceFile}
    {checked : CheckedCompactSources encoded expectedSources}
    (_accepted : checkCompactSources encoded expectedSources = .ok checked) :
    decodeCompactPack? encoded = some checked.pack ∧
      checked.pack.schema_version = schemaVersion ∧
      compactPackSources checked.pack = expectedSources := by
  exact ⟨checked.decoded, checked.schema, checked.sourceIdentity⟩

end Lanius.Extraction
