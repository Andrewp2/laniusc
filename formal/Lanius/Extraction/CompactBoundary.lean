import Lanius.Compiler.Phase
import Lanius.Extraction.SyntaxCheck.Pack

namespace Lanius.Extraction

/-! Pure boundary for the raw-data runner.  IO transport and output bytes are
    intentionally outside this relation; a success exposes only certificates
    constructed by `checkCompactSourcePack`. -/

structure RawPackInput where
  encoded : String
  expectedSources : List SourceFile

abbrev RawPackWitness :=
  Σ encoded : String, Σ expectedSources : List SourceFile,
    SyntaxCheck.CheckedSourcePack encoded expectedSources

def checkRawPack (input : RawPackInput) : Option RawPackWitness :=
  match SyntaxCheck.checkCompactSourcePack input.encoded input.expectedSources with
  | .ok checked => some ⟨input.encoded, input.expectedSources, checked⟩
  | .error _ => none

def RawPackEvidence (input : RawPackInput) (witness : RawPackWitness) : Prop :=
  witness.1 = input.encoded ∧
    witness.2.1 = input.expectedSources ∧
    decodeCompactPack? witness.1 = some witness.2.2.compact.pack ∧
    witness.2.2.compact.pack.schema_version = schemaVersion ∧
    compactPackSources witness.2.2.compact.pack = witness.2.1 ∧
    SyntaxCheck.UnitsValid witness.2.2.compact.pack.units

theorem checkRawPack_refines :
    Compiler.Phase.Refines RawPackEvidence checkRawPack := by
  intro input witness accepted
  unfold checkRawPack at accepted
  cases checkedResult :
      SyntaxCheck.checkCompactSourcePack input.encoded input.expectedSources with
  | error stage => simp [checkedResult] at accepted
  | ok checked =>
      have witnessEq : witness =
          ⟨input.encoded, input.expectedSources, checked⟩ := by
        simpa [checkedResult] using accepted.symm
      subst witness
      have sound := SyntaxCheck.checkCompactSourcePack_sound checkedResult
      exact ⟨rfl, rfl, sound.1, sound.2.1, sound.2.2.1, sound.2.2.2⟩

def runnerStatus (input : RawPackInput) : UInt32 :=
  match SyntaxCheck.checkCompactSourcePack input.encoded input.expectedSources with
  | .ok _ => 0
  | .error _ => 1

def runnerPublishes (input : RawPackInput) : Prop := runnerStatus input = 0

theorem checkRawPack_failure_safe :
    Compiler.Phase.FailureSafe runnerPublishes checkRawPack := by
  intro input failed published
  cases result :
      SyntaxCheck.checkCompactSourcePack input.encoded input.expectedSources with
  | error stage => simp [runnerPublishes, runnerStatus, result] at published
  | ok checked => simp [checkRawPack, result] at failed

end Lanius.Extraction
