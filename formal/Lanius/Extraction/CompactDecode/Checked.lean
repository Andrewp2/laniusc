import Lanius.Extraction.CompactArtifact
import Lanius.Extraction.CompactDecode.Unit
import Lanius.Extraction.CompactDecode.Acceptance.Tokens

namespace Lanius.Extraction.CompactDecode

/-- Check the retained typed tokens directly. Wire decoding is discharged by
the existing range and token-row lemmas instead of repeated concrete decoding. -/
def UnitData.checkTokens (data : UnitData) : Bool :=
  data.raw.all (fun token => token.start ≤ token.finish) &&
  data.tokens.all (fun token => token.start ≤ token.finish) &&
  checkRawTokenTrace (data.source.data.toList.map UInt8.toFin) data.raw &&
  canonicalizeTokensFromTrace (data.source.data.toList.map UInt8.toFin) data.raw == data.tokens

theorem UnitData.checkTokens_sound (data : UnitData)
    (accepted : data.checkTokens = true) : checkTokenArtifact data.artifact = true := by
  simp only [checkTokens, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at accepted
  have rawDecoded := decodeTokens_rows data.raw accepted.1.1.1
  have canonicalDecoded := decodeTokens_rows data.tokens accepted.1.1.2
  have sourceDecoded : decodeBytes (data.source.toList.map UInt8.toNat) =
      some (data.source.data.toList.map UInt8.toFin) := by
    rw [byteArray_toList]
    simpa only [List.map_map, Function.comp_def, UInt8.toFin_val] using
      decodeBytes_values (data.source.data.toList.map UInt8.toFin)
  simp only [checkTokenArtifact, UnitData.artifact, Artifact.empty,
    bne_self_eq_false, Bool.false_eq_true, ↓reduceIte, decodeSingleSource,
    sourceDecoded, rawDecoded, canonicalDecoded, accepted.1.2, accepted.2,
    Bool.and_self]

/-- Retain independently read bytes in their quoted representation until a
consumer needs the public source-file model. -/
def sourceFiles (inputs : List (String × ByteArray)) : List SourceFile :=
  inputs.map fun (path, bytes) => ⟨path, bytes.toList.map UInt8.toNat⟩

/-- Equality of the quoted byte arrays establishes exactly the same ordered
paths and natural-number bytes used by the existing source checker. This
avoids re-evaluating byte conversion during concrete authentication. -/
theorem sources_of_inputs {units : List UnitData} {inputs : List (String × ByteArray)}
    (represented : units.map (fun unit : UnitData => (unit.path, unit.source)) = inputs) :
    compactPackSources ⟨schemaVersion, units.map UnitData.artifact⟩ = sourceFiles inputs := by
  rw [← represented]
  simp [compactPackSources, sourceFiles, UnitData.artifact, List.flatMap_map,
    List.map_map, ← List.map_eq_flatMap, Function.comp_def]

/-- Specialize the source/Surface checker at an authenticated decoding result.
This proof-facing entry point skips only the already-proved reader operation;
its equivalence to the existing runtime checker is established below. -/
def checkSurfaceSources? (encoded : String) (expectedSources : List SourceFile)
    (pack : ArtifactPack) (decoded : decodeCompactArtifactPack? encoded = some pack) :
    Option (CheckedCompactSurfaceSourcePack encoded expectedSources) := do
  if schema : pack.schema_version = schemaVersion then
    if sources : compactPackSources pack = expectedSources then
      let surfaceData ← ArtifactPackChecker.checkUnitSurfacesCached pack.units
      pure { pack, decoded, schema, sources, surfaceData, surfaces := surfaceData.valid }
    else none
  else none

theorem checkSurfaceSources?_eq (encoded : String) (expectedSources : List SourceFile)
    (pack : ArtifactPack) (decoded : decodeCompactArtifactPack? encoded = some pack) :
    checkSurfaceSources? encoded expectedSources pack decoded =
      checkCompactSurfaceArtifactPackSources? encoded expectedSources := by
  unfold checkCompactSurfaceArtifactPackSources?
  split <;> rename_i found
  · simp [decoded] at found
  · cases Option.some.inj (decoded.symm.trans found)
    rfl

end Lanius.Extraction.CompactDecode
