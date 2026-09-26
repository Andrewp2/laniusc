import Lanius.Extraction.SyntaxCheck.Pack

namespace Lanius.Extraction.SyntaxCheck

/-! A structured Lean artifact can enter the same lexer, parse, and Surface
    checkers without first being encoded as a compact integer certificate. -/

structure CheckedTypedSourcePack (pack : ArtifactPack)
    (expectedSources : List SourceFile) where
  schema : pack.schema_version = schemaVersion
  sourceIdentity : compactPackSources pack = expectedSources
  units : CheckedUnits pack.units

inductive TypedPackCheckStage where
  | schema
  | sources
  | unit (stage : UnitCheckStage)
deriving DecidableEq, Repr

def checkTypedSourcePack (pack : ArtifactPack)
    (expectedSources : List SourceFile) :
    Except TypedPackCheckStage (CheckedTypedSourcePack pack expectedSources) :=
  if schema : pack.schema_version = schemaVersion then
    if sourceIdentity : compactPackSources pack = expectedSources then
      match checkUnits pack.units with
      | .error stage => .error (.unit stage)
      | .ok units => .ok { schema, sourceIdentity, units }
    else .error .sources
  else .error .schema

theorem checkTypedSourcePack_sound
    {pack : ArtifactPack} {expectedSources : List SourceFile}
    {checked : CheckedTypedSourcePack pack expectedSources}
    (_accepted : checkTypedSourcePack pack expectedSources = .ok checked) :
    pack.schema_version = schemaVersion ∧
      compactPackSources pack = expectedSources ∧ UnitsValid pack.units :=
  ⟨checked.schema, checked.sourceIdentity, checkedUnits_valid checked.units⟩

end Lanius.Extraction.SyntaxCheck
