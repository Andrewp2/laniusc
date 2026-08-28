import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.EvidenceStructureChecker
import Lanius.Extraction.GlobalResolutionEvidenceChecker

namespace Lanius.Extraction.CompleteChecker

open Lanius.Extraction

abbrev Evidence := CoreTyping.Evidence

/-! ## Complete extraction-certificate boundary

The untrusted exporter may propose every layer, but acceptance is one dependent
value. A consumer cannot accidentally check only that Core is well typed while
omitting the verified source-to-Core correspondence.
-/

structure CheckedArtifact (artifact : Artifact)
    (scopedSurface : ScopedSurface.CheckedArtifact artifact) where
  surfaceValid : SurfaceArtifactValid artifact
  evidence : EvidenceStructureValid artifact
  typedCore : CoreTyping.CheckedCoreArtifact artifact
  /-- Located Surface, lexical scopes, exact resolution rows, module lookup,
      and source-to-Core elaboration are accepted as one dependent value. -/
  scopedResolution :
    GlobalResolutionEvidenceChecker.CheckedSingleArtifact artifact scopedSurface

def extendScopedArtifact? (artifact : Artifact)
    (scopedSurface : ScopedSurface.CheckedArtifact artifact) :
    Option (CheckedArtifact artifact scopedSurface) := do
  if surfaceAccepted : checkSurfaceArtifact artifact = true then
    if evidenceAccepted : checkEvidenceStructure artifact = true then
      let typedCore ← CoreTyping.decodeTypedCore artifact
      let scopedResolution ←
        GlobalResolutionEvidenceChecker.extendCheckedSurface? artifact scopedSurface
      pure {
        surfaceValid := checkSurfaceArtifact_sound surfaceAccepted
        evidence := checkEvidenceStructure_sound evidenceAccepted
        typedCore
        scopedResolution
      }
    else none
  else none

def checkArtifact? (artifact : Artifact) :
    Option (Sigma fun scopedSurface : ScopedSurface.CheckedArtifact artifact =>
      CheckedArtifact artifact scopedSurface) := do
  let scopedSurface ← ScopedSurface.checkArtifact? artifact
  let checked ← extendScopedArtifact? artifact scopedSurface
  pure ⟨scopedSurface, checked⟩

def checkUnitEvidenceStructure
    (surfaceNodeCounts : List Nat)
    (unitIndex : Nat)
    (artifact : Artifact) : Bool :=
  match collectSurfaceClaims artifact, artifact.core_program with
  | some claims, some _ =>
      surfaceNodeCounts[unitIndex]? == some claims.nodes.length &&
      resolutionRowsInUnits unitIndex surfaceNodeCounts artifact.resolutions &&
      typeRowsInSurface claims.nodes.length artifact.types &&
      loweringRowsInSurface claims.nodes.length artifact.lowering &&
      indexedReferencesEarlier (·.premises) artifact.types &&
      indexedReferencesEarlier (·.premises) artifact.lowering &&
      typedLoweringRowsHaveTypeEvidence artifact.types artifact.lowering &&
      typeRowsHaveLoweringEvidence artifact.lowering artifact.types
  | _, _ => false

def UnitEvidenceValid
    (surfaceNodeCounts : List Nat)
    (unitIndex : Nat)
    (artifact : Artifact) : Prop :=
  ∃ claims program,
    collectSurfaceClaims artifact = some claims ∧
    artifact.core_program = some program ∧
    surfaceNodeCounts[unitIndex]? = some claims.nodes.length ∧
    resolutionRowsInUnits unitIndex surfaceNodeCounts artifact.resolutions = true ∧
    typeRowsInSurface claims.nodes.length artifact.types = true ∧
    loweringRowsInSurface claims.nodes.length artifact.lowering = true ∧
    indexedReferencesEarlier (·.premises) artifact.types = true ∧
    indexedReferencesEarlier (·.premises) artifact.lowering = true ∧
    typedLoweringRowsHaveTypeEvidence artifact.types artifact.lowering = true ∧
    typeRowsHaveLoweringEvidence artifact.lowering artifact.types = true

theorem checkUnitEvidenceStructure_sound
    (accepted : checkUnitEvidenceStructure surfaceNodeCounts unitIndex artifact = true) :
    UnitEvidenceValid surfaceNodeCounts unitIndex artifact := by
  unfold checkUnitEvidenceStructure at accepted
  cases claimsFound : collectSurfaceClaims artifact with
  | none => simp [claimsFound] at accepted
  | some claims =>
      cases programFound : artifact.core_program with
      | none => simp [claimsFound, programFound] at accepted
      | some program =>
          simp only [claimsFound, programFound, Bool.and_eq_true] at accepted
          refine ⟨claims, program, claimsFound, programFound, ?_⟩
          simpa only [beq_iff_eq, and_assoc] using accepted

inductive UnitsEvidenceValid
    (surfaceNodeCounts : List Nat) : Nat → List Artifact → Prop where
  | nil (unitIndex : Nat) : UnitsEvidenceValid surfaceNodeCounts unitIndex []
  | cons
      (head : UnitEvidenceValid surfaceNodeCounts unitIndex artifact)
      (tail : UnitsEvidenceValid surfaceNodeCounts (unitIndex + 1) artifacts) :
      UnitsEvidenceValid surfaceNodeCounts unitIndex (artifact :: artifacts)

def checkUnitEvidence (surfaceNodeCounts : List Nat) :
    (unitIndex : Nat) → (artifacts : List Artifact) →
      Option (Evidence (UnitsEvidenceValid surfaceNodeCounts unitIndex artifacts))
  | unitIndex, [] => some ⟨.nil unitIndex⟩
  | unitIndex, head :: tail => do
      if accepted :
          checkUnitEvidenceStructure surfaceNodeCounts unitIndex head = true then
        let checkedTail ← checkUnitEvidence surfaceNodeCounts (unitIndex + 1) tail
        pure ⟨.cons (checkUnitEvidenceStructure_sound accepted)
          checkedTail.proof⟩
      else none

def collectSurfaceNodeCounts? (artifacts : List Artifact) : Option (List Nat) :=
  artifacts.mapM fun artifact => do
    let claims ← collectSurfaceClaims artifact
    pure claims.nodes.length

def packLoweringCoreNodeIds (pack : ArtifactPack) : List CoreNodeId :=
  pack.units.flatMap fun artifact => artifact.lowering.map (·.core_node)

def packLoweringCoversCore
    (pack : ArtifactPack) (wire : CoreProgram) : Bool :=
  (packLoweringCoreNodeIds pack).mergeSort ==
    List.range (coreProgramNodeIds wire).length

def PackEvidenceValid (pack : ArtifactPack) : Prop :=
  ∃ surfaceNodeCounts,
    collectSurfaceNodeCounts? pack.units = some surfaceNodeCounts ∧
    UnitsEvidenceValid surfaceNodeCounts 0 pack.units ∧
    ∃ wire,
      ArtifactPackChecker.mergeCorePrograms? pack.units = some wire ∧
      packLoweringCoversCore pack wire = true

def checkPackEvidence? (pack : ArtifactPack) :
    Option (Evidence (PackEvidenceValid pack)) := do
  match countsFound : collectSurfaceNodeCounts? pack.units with
  | none => none
  | some surfaceNodeCounts =>
      let units ← checkUnitEvidence surfaceNodeCounts 0 pack.units
      match merged : ArtifactPackChecker.mergeCorePrograms? pack.units with
      | none => none
      | some wire =>
          if covered : packLoweringCoversCore pack wire = true then
            pure ⟨⟨surfaceNodeCounts, countsFound, units.proof,
              wire, merged, covered⟩⟩
          else none

structure CheckedPack (pack : ArtifactPack) where
  semantics :
    ArtifactPackContextChecker.CheckedArtifactPackSemantics pack
  evidence : PackEvidenceValid pack
  scopedResolution :
    GlobalResolutionEvidenceChecker.CheckedPackResolution pack semantics.context

def checkPack? (pack : ArtifactPack) : Option (CheckedPack pack) := do
  let evidence ← checkPackEvidence? pack
  let semantics ← ArtifactPackContextChecker.checkArtifactPackSemantics? pack
  let scopedResolution ←
    GlobalResolutionEvidenceChecker.checkPackResolution? pack semantics.context
  pure ⟨semantics, evidence.proof, scopedResolution⟩

end Lanius.Extraction.CompleteChecker
