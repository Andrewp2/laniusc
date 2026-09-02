import Lanius.Extraction.SurfaceReconstructProvenance

namespace Lanius.Extraction

/-! Surface reconstruction is paired with compact origin paths.  The paths are
untrusted data: acceptance checks every direct parse-node and token edge against
the canonical artifact view before constructing the public validity proof. -/

def checkSurfaceArtifactOriginsViewOfParse? (artifact : Artifact)
    (view : ArtifactView artifact) (origins : SurfaceOrigins)
    (parseValid : ParseArtifactValid artifact) :
    Option (CheckedSurfaceArtifact artifact) := do
  match reconstructionFound :
      reconstructArtifactSurfaceWithProvenanceView artifact view origins with
  | none => none
  | some reconstruction =>
      match surfaceFound : decodeSurfaceFile
          (artifact.parse_nodes.length + 1) reconstruction.reconstructed with
      | none => none
      | some surface =>
          if originsAccepted : reconstruction.valid artifact view = true then
            have components :=
              reconstructArtifactSurfaceWithProvenanceView_components
                view origins reconstructionFound
            have collected : collectSurfaceClaimsView artifact view =
                some reconstruction.claims := by
              simp [collectSurfaceClaimsView, components.1, components.2.1]
            have decoded : decodeReconstructedSurfaceView artifact view =
                some surface := by
              simp [decodeReconstructedSurfaceView, components.1, surfaceFound]
            pure {
              view
              reconstructed := reconstruction.reconstructed
              reconstructedFound := components.1
              claims := reconstruction.claims
              claimsFound := collected
              surface
              surfaceFound := decoded
              valid := SurfaceArtifactValid.ofView view parseValid collected decoded
                (reconstruction.valid_sound view originsAccepted)
            }
          else none

def checkSurfaceArtifactOriginsView? (artifact : Artifact)
    (view : ArtifactView artifact) (origins : SurfaceOrigins) :
    Option (CheckedSurfaceArtifact artifact) := do
  if parseAccepted : checkParseArtifactView artifact view = true then
    checkSurfaceArtifactOriginsViewOfParse? artifact view origins
      (checkParseArtifactView_sound view parseAccepted)
  else none

theorem checkSurfaceArtifactOriginsView?_sound {artifact : Artifact}
    (view : ArtifactView artifact) (origins : SurfaceOrigins)
    {checked : CheckedSurfaceArtifact artifact}
    (_accepted : checkSurfaceArtifactOriginsView? artifact view origins =
      some checked) : SurfaceArtifactValid artifact :=
  checked.valid

/-- Assemble the public checked-surface package from independently reduced
phase certificates. -/
def CheckedSurfaceArtifact.ofOrigins {artifact : Artifact}
    (view : ArtifactView artifact) (origins : SurfaceOrigins)
    (parseAccepted : checkParseArtifactView artifact view = true)
    (reconstruction : ProvenanceSurfaceReconstruction)
    (reconstructionFound :
      reconstructArtifactSurfaceWithProvenanceView artifact view origins =
        some reconstruction)
    (surface : Lanius.Surface.File)
    (surfaceFound : decodeSurfaceFile (artifact.parse_nodes.length + 1)
      reconstruction.reconstructed = some surface)
    (claimsEqual : reconstruction.origins.claims = reconstruction.claims)
    (originsAccepted : reconstruction.origins.valid artifact view = true) :
    CheckedSurfaceArtifact artifact := by
  have components := reconstructArtifactSurfaceWithProvenanceView_components
    view origins reconstructionFound
  have collected : collectSurfaceClaimsView artifact view =
      some reconstruction.claims := by
    simp [collectSurfaceClaimsView, components.1, components.2.1]
  have decoded : decodeReconstructedSurfaceView artifact view = some surface := by
    simp [decodeReconstructedSurfaceView, components.1, surfaceFound]
  have claimsMatch := reconstruction.origins.valid_sound view originsAccepted
  rw [claimsEqual] at claimsMatch
  exact {
    view
    reconstructed := reconstruction.reconstructed
    reconstructedFound := components.1
    claims := reconstruction.claims
    claimsFound := collected
    surface
    surfaceFound := decoded
    valid := SurfaceArtifactValid.ofView view
      (checkParseArtifactView_sound view parseAccepted)
      collected decoded claimsMatch
  }

/-- Assemble a checked surface from an existing declarative parse proof.  This
avoids reducing the complete parse Boolean again at the surface boundary. -/
def CheckedSurfaceArtifact.ofOriginsWithParse {artifact : Artifact}
    (view : ArtifactView artifact) (origins : SurfaceOrigins)
    (parseValid : ParseArtifactValid artifact)
    (reconstruction : ProvenanceSurfaceReconstruction)
    (reconstructionFound :
      reconstructArtifactSurfaceWithProvenanceView artifact view origins =
        some reconstruction)
    (surface : Lanius.Surface.File)
    (surfaceFound : decodeSurfaceFile (artifact.parse_nodes.length + 1)
      reconstruction.reconstructed = some surface)
    (claimsEqual : reconstruction.origins.claims = reconstruction.claims)
    (originsAccepted : reconstruction.origins.valid artifact view = true) :
    CheckedSurfaceArtifact artifact := by
  have components := reconstructArtifactSurfaceWithProvenanceView_components
    view origins reconstructionFound
  have collected : collectSurfaceClaimsView artifact view =
      some reconstruction.claims := by
    simp [collectSurfaceClaimsView, components.1, components.2.1]
  have decoded : decodeReconstructedSurfaceView artifact view = some surface := by
    simp [decodeReconstructedSurfaceView, components.1, surfaceFound]
  have claimsMatch := reconstruction.origins.valid_sound view originsAccepted
  rw [claimsEqual] at claimsMatch
  exact {
    view
    reconstructed := reconstruction.reconstructed
    reconstructedFound := components.1
    claims := reconstruction.claims
    claimsFound := collected
    surface
    surfaceFound := decoded
    valid := SurfaceArtifactValid.ofView view parseValid collected decoded claimsMatch
  }

end Lanius.Extraction
