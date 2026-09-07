import Lanius.Extraction.CompactArtifact

namespace Lanius.Extraction

example : decodeCompactArtifactPack? "" = none := by native_decide

example : decodeCompactArtifactPack? "not-hex" = none := by native_decide

example :
    decodeCompactArtifactPack? "0000000100000000" = none := by
  native_decide

example :
    decodeCompactArtifactPack? "0000000100000001ffffffff" = none := by
  native_decide

example :
    decodeCompactArtifactPack? "000000010000000100000000" = none := by
  native_decide

example : checkCompactSyntaxArtifactPackSources? "" [] = none := by
  native_decide

example (encoded : String) (expected : List SourceFile)
    (accepted :
      (checkCompactSyntaxArtifactPackSources? encoded expected).isSome = true) :
    ∃ pack,
      decodeCompactArtifactPack? encoded = some pack ∧
      pack.schema_version = schemaVersion ∧
      compactPackSources pack = expected ∧
      CompactSyntaxUnitsValid pack.units :=
  checkCompactSyntaxArtifactPackSources?_sound accepted

example : checkCompactSurfaceArtifactPackSources? "" [] = none := by
  native_decide

end Lanius.Extraction
