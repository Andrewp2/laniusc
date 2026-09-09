import Lanius.Extraction.ArtifactPackChecker
import Lanius.Extraction.CompactDecode.Reader

namespace Lanius.Extraction

/-! A compact, fixed-width wire format for per-program syntax certificates.

The producer is untrusted. Decoding yields only ordinary `Artifact` data, and
the existing verified checkers establish every invariant before downstream
proofs may use it. Keeping the wire payload in one string literal avoids
elaborating millions of generated Lean syntax nodes.
-/


def decodeCompactArtifactPack? (encoded : String) : Option ArtifactPack :=
  (CompactDecode.readPack.run { bytes := encoded.toUTF8, offset := 0 }).map (·.1)

inductive CompactSyntaxUnitsValid : List Artifact → Prop where
  | nil : CompactSyntaxUnitsValid []
  | cons
      (head : ParseArtifactValid artifact)
      (tail : CompactSyntaxUnitsValid artifacts) :
      CompactSyntaxUnitsValid (artifact :: artifacts)

private def checkCompactSyntaxUnits :
    (artifacts : List Artifact) →
      Option (ArtifactPackChecker.Evidence
        (CompactSyntaxUnitsValid artifacts))
  | [] => some ⟨.nil⟩
  | head :: tail => do
      if accepted : checkParseArtifact head = true then
        let checkedTail ← checkCompactSyntaxUnits tail
        pure ⟨.cons (checkParseArtifact_sound accepted) checkedTail.proof⟩
      else
        none

structure CheckedCompactSyntaxPack (encoded : String) where
  pack : ArtifactPack
  decoded : decodeCompactArtifactPack? encoded = some pack
  schema : pack.schema_version = schemaVersion
  units : CompactSyntaxUnitsValid pack.units

def compactPackSources (pack : ArtifactPack) : List SourceFile :=
  pack.units.flatMap (fun artifact => artifact.sources)

/-- A syntax certificate whose ordered source names and bytes have also been
checked against an independently supplied input list. -/
structure CheckedCompactSyntaxSourcePack
    (encoded : String) (expectedSources : List SourceFile) where
  checked : CheckedCompactSyntaxPack encoded
  sources : compactPackSources checked.pack = expectedSources

def checkCompactSyntaxArtifactPack?
    (encoded : String) : Option (CheckedCompactSyntaxPack encoded) := do
  match decoded : decodeCompactArtifactPack? encoded with
  | none => none
  | some pack => do
      if schema : pack.schema_version = schemaVersion then
        let units ← checkCompactSyntaxUnits pack.units
        pure { pack, decoded, schema, units := units.proof }
      else
        none

def checkCompactSyntaxArtifactPackSources?
    (encoded : String) (expectedSources : List SourceFile) :
    Option (CheckedCompactSyntaxSourcePack encoded expectedSources) := do
  match decoded : decodeCompactArtifactPack? encoded with
  | none => none
  | some pack => do
      if schema : pack.schema_version = schemaVersion then
        if sources : compactPackSources pack = expectedSources then
          let units ← checkCompactSyntaxUnits pack.units
          pure {
            checked := { pack, decoded, schema, units := units.proof }
            sources
          }
        else
          none
      else
        none

/-- The proposition exposed to execution and bootstrap proofs. Acceptance
cannot be used without recovering the exact decoded pack, its source binding,
and the validity proof for every syntax unit. -/
theorem checkCompactSyntaxArtifactPackSources?_sound
    {encoded : String} {expectedSources : List SourceFile}
    (accepted :
      (checkCompactSyntaxArtifactPackSources? encoded expectedSources).isSome =
        true) :
    ∃ pack,
      decodeCompactArtifactPack? encoded = some pack ∧
      pack.schema_version = schemaVersion ∧
      compactPackSources pack = expectedSources ∧
      CompactSyntaxUnitsValid pack.units := by
  cases found : checkCompactSyntaxArtifactPackSources? encoded expectedSources with
  | none => simp [found] at accepted
  | some checked =>
      exact ⟨checked.checked.pack, checked.checked.decoded,
        checked.checked.schema, checked.sources, checked.checked.units⟩

structure CheckedCompactSurfaceSourcePack
    (encoded : String) (expectedSources : List SourceFile) where
  pack : ArtifactPack
  decoded : decodeCompactArtifactPack? encoded = some pack
  schema : pack.schema_version = schemaVersion
  sources : compactPackSources pack = expectedSources
  surfaceData : ArtifactPackChecker.CheckedUnitSurfaces pack.units
  surfaces : ArtifactPackChecker.UnitsSurfaceValid pack.units

def checkCompactSurfaceArtifactPackSources?
    (encoded : String) (expectedSources : List SourceFile) :
    Option (CheckedCompactSurfaceSourcePack encoded expectedSources) := do
  match decoded : decodeCompactArtifactPack? encoded with
  | none => none
  | some pack => do
      if schema : pack.schema_version = schemaVersion then
        if sources : compactPackSources pack = expectedSources then
          let surfaceData ← ArtifactPackChecker.checkUnitSurfacesCached pack.units
          pure {
            pack, decoded, schema, sources, surfaceData
            surfaces := surfaceData.valid
          }
        else
          none
      else
        none

theorem checkCompactSurfaceArtifactPackSources?_sound
    {encoded : String} {expectedSources : List SourceFile}
    (accepted :
      (checkCompactSurfaceArtifactPackSources? encoded expectedSources).isSome =
        true) :
    ∃ pack,
      decodeCompactArtifactPack? encoded = some pack ∧
      pack.schema_version = schemaVersion ∧
      compactPackSources pack = expectedSources ∧
      ArtifactPackChecker.UnitsSurfaceValid pack.units := by
  cases found : checkCompactSurfaceArtifactPackSources? encoded expectedSources with
  | none => simp [found] at accepted
  | some checked =>
      exact ⟨checked.pack, checked.decoded, checked.schema, checked.sources,
        checked.surfaces⟩

end Lanius.Extraction
