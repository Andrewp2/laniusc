import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks

namespace Lanius.Extraction.ArtifactPackContextChecker

def DecodedPackUnits.prepend
    (nextModule : ModuleId) (artifact : Artifact) (tail : List Artifact)
    (checkedSurface : CheckedSurfaceArtifact artifact)
    (modulePath : Names.ModulePath)
    (moduleFound : declaredModulePath? checkedSurface.surface = some modulePath)
    (core : Core.Program)
    (coreFound : artifact.core_program.map CoreDecode.program = some core)
    (rest : DecodedPackUnits tail) : DecodedPackUnits (artifact :: tail) := {
  units := {
    artifact
    moduleId := nextModule
    modulePath
    surface := checkedSurface.surface
    surfaceDecoded := by
      rw [← decodeReconstructedSurfaceView_eq artifact checkedSurface.view]
      exact checkedSurface.surfaceFound
    moduleDeclared := moduleFound
    core
    coreDecoded := coreFound
  } :: rest.units
  artifactsMatch := by simp [rest.artifactsMatch]
}

theorem decodePackUnitsFromCached_cons_of
    (nextModule : ModuleId) (artifact : Artifact) (tail : List Artifact)
    (checkedSurface : CheckedSurfaceArtifact artifact)
    (checkedTail : ArtifactPackChecker.CheckedUnitSurfaces tail)
    (modulePath : Names.ModulePath)
    (moduleFound : declaredModulePath? checkedSurface.surface = some modulePath)
    (core : Core.Program)
    (coreFound : artifact.core_program.map CoreDecode.program = some core)
    (rest : DecodedPackUnits tail)
    (restFound : decodePackUnitsFromCached (nextModule + 1) tail checkedTail =
      some rest) :
    decodePackUnitsFromCached nextModule (artifact :: tail)
      (.cons checkedSurface checkedTail) =
        some (DecodedPackUnits.prepend nextModule artifact tail checkedSurface
          modulePath moduleFound core coreFound rest) := by
  simp only [decodePackUnitsFromCached]
  split
  · rename_i absent
    rw [moduleFound] at absent
    contradiction
  · rename_i foundModule moduleFound'
    have sameModule : foundModule = modulePath := by
      rw [moduleFound] at moduleFound'
      exact Option.some.inj moduleFound'.symm
    subst foundModule
    split
    · rename_i absent
      rw [coreFound] at absent
      contradiction
    · rename_i foundCore coreFound'
      have sameCore : foundCore = core := by
        rw [coreFound] at coreFound'
        exact Option.some.inj coreFound'.symm
      subst foundCore
      rw [restFound]
      rfl

theorem decodePackUnitsFromCached_cons_isSome
    (nextModule : ModuleId) (artifact : Artifact) (tail : List Artifact)
    (checkedSurface : CheckedSurfaceArtifact artifact)
    (checkedTail : ArtifactPackChecker.CheckedUnitSurfaces tail)
    (modulePresent : (declaredModulePath? checkedSurface.surface).isSome = true)
    (corePresent : (artifact.core_program.map CoreDecode.program).isSome = true)
    (tailPresent :
      (decodePackUnitsFromCached (nextModule + 1) tail checkedTail).isSome = true) :
    (decodePackUnitsFromCached nextModule (artifact :: tail)
      (.cons checkedSurface checkedTail)).isSome = true := by
  unfold decodePackUnitsFromCached
  simp only [decodePackUnitsFromCached]
  split
  · simp_all
  · split
    · simp_all
    · have restFound := parseOptionEqSomeGet tailPresent
      rw [restFound]
      rfl

end Lanius.Extraction.ArtifactPackContextChecker
