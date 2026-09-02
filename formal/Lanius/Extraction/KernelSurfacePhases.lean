import Lanius.Extraction.SurfaceCheckerProvenance

namespace Lanius.Extraction

theorem option_eq_some_get {value : Option α} (present : value.isSome = true) :
    value = some (value.get present) := by
  cases value <;> simp_all

syntax "kernel_surface_parse " ident " for " term ", " term : command

macro_rules
  | `(kernel_surface_parse $parseChecked:ident for $artifact:term, $view:term) =>
      `(theorem $parseChecked :
          checkParseArtifactView $artifact $view = true := by
            with_unfolding_all rfl)

syntax "kernel_surface_reconstruction " ident ", " ident ", " ident
  " for " term ", " term : command

macro_rules
  | `(kernel_surface_reconstruction $reconstructedPresent:ident,
        $reconstructed:ident, $reconstructedFound:ident for
        $artifact:term, $view:term) =>
      `(section
        theorem $reconstructedPresent :
            (reconstructArtifactSurfaceView $artifact $view).isSome = true := by
          with_unfolding_all rfl
        def $reconstructed : SurfaceFile :=
          (reconstructArtifactSurfaceView $artifact $view).get $reconstructedPresent
        theorem $reconstructedFound :
            reconstructArtifactSurfaceView $artifact $view =
              some $reconstructed := by
          exact option_eq_some_get $reconstructedPresent
        end)

syntax "kernel_surface_parse_reconstruction " ident ", " ident ", " ident ", " ident
  " for " term ", " term : command

macro_rules
  | `(kernel_surface_parse_reconstruction $parseChecked:ident,
        $reconstructedPresent:ident, $reconstructed:ident,
        $reconstructedFound:ident for $artifact:term, $view:term) =>
      `(section
        theorem $parseChecked :
            checkParseArtifactView $artifact $view = true := by
          with_unfolding_all rfl
        theorem $reconstructedPresent :
            (reconstructArtifactSurfaceView $artifact $view).isSome = true := by
          with_unfolding_all rfl
        def $reconstructed : SurfaceFile :=
          (reconstructArtifactSurfaceView $artifact $view).get $reconstructedPresent
        theorem $reconstructedFound :
            reconstructArtifactSurfaceView $artifact $view =
              some $reconstructed := by
          exact option_eq_some_get $reconstructedPresent
        end)

syntax "kernel_surface_claims " ident ", " ident ", " ident " for " term ", " term : command

macro_rules
  | `(kernel_surface_claims $claimsPresent:ident, $claims:ident,
        $claimsFound:ident for $artifact:term, $reconstructed:term) =>
      `(section
        theorem $claimsPresent :
            (collectSurfaceClaimsFrom $artifact $reconstructed).isSome = true := by
          with_unfolding_all rfl
        def $claims : SurfaceClaims :=
          (collectSurfaceClaimsFrom $artifact $reconstructed).get $claimsPresent
        theorem $claimsFound :
            collectSurfaceClaimsFrom $artifact $reconstructed = some $claims := by
          exact option_eq_some_get $claimsPresent
        end)

syntax "kernel_surface_origins " ident ", " ident ", " ident ", " ident ", " ident
  ", " ident " for " term ", " term ", " term ", " term : command

macro_rules
  | `(kernel_surface_origins $claimsEqual:ident, $idsDense:ident,
        $nodesChecked:ident, $spellingsChecked:ident, $coverageChecked:ident,
        $checked:ident for $artifact:term, $view:term, $origins:term,
        $claims:term) =>
      `(section
        theorem $claimsEqual : ($origins).claims = $claims := by
          with_unfolding_all rfl
        theorem $idsDense :
            ($origins).claims.nodes.map (·.id) ==
              List.range ($origins).claims.nodes.length := by
          with_unfolding_all rfl
        theorem $nodesChecked :
            nodeOriginPathsValid $artifact $view ($origins).claims.nodes
              ($origins).nodePaths = true := by
          with_unfolding_all rfl
        theorem $spellingsChecked :
            spellingOriginPathsValid $artifact $view ($origins).claims.spellings
              ($origins).spellingPaths = true := by
          with_unfolding_all rfl
        theorem $coverageChecked :
            spellingCoverageValid $artifact ($origins).claims = true := by
          with_unfolding_all rfl
        theorem $checked : ($origins).valid $artifact $view = true := by
          exact SurfaceOrigins.valid_of_components $view $origins $idsDense
            $nodesChecked $spellingsChecked $coverageChecked
        end)

syntax "kernel_surface_assembly " ident ", " ident ", " ident ", " ident ", " ident
  ", " ident ", " ident " for " term ", " term ", " term ", " term ", " term
  ", " term ", " term ", " term ", " term ", " term : command

macro_rules
  | `(kernel_surface_assembly $reconstruction:ident,
        $reconstructionFound:ident, $surfacePresent:ident, $surface:ident,
        $surfaceFound:ident, $checked:ident, $valid:ident for
        $artifact:term, $view:term, $origins:term, $parseChecked:term,
        $reconstructed:term, $reconstructedFound:term, $claims:term,
        $claimsFound:term, $claimsEqual:term, $originsChecked:term) =>
      `(section
        def $reconstruction : ProvenanceSurfaceReconstruction := {
          reconstructed := $reconstructed
          claims := $claims
          origins := $origins
        }
        theorem $reconstructionFound :
            reconstructArtifactSurfaceWithProvenanceView $artifact $view $origins =
              some $reconstruction := by
          exact reconstructArtifactSurfaceWithProvenanceView_of_components
            $view $origins $reconstructed $claims $reconstructedFound $claimsFound
        theorem $surfacePresent :
            (decodeSurfaceFile ($artifact).parse_nodes.length.succ
              $reconstructed).isSome = true := by
          with_unfolding_all rfl
        def $surface :=
          (decodeSurfaceFile ($artifact).parse_nodes.length.succ
            $reconstructed).get $surfacePresent
        theorem $surfaceFound :
            decodeSurfaceFile ($artifact).parse_nodes.length.succ $reconstructed =
              some $surface := by
          exact option_eq_some_get $surfacePresent
        def $checked : CheckedSurfaceArtifact $artifact :=
          CheckedSurfaceArtifact.ofOrigins $view $origins $parseChecked
            $reconstruction $reconstructionFound $surface $surfaceFound
            $claimsEqual $originsChecked
        theorem $valid : SurfaceArtifactValid $artifact :=
          CheckedSurfaceArtifact.valid $checked
        end)

/-- Reduce the complete provenance-backed surface checker once, then retain
only the compact checked package.  Unlike the phase macros above, this does
not recompute reconstruction, claims, origins, and decoding in separate
concrete proofs. -/
syntax "kernel_surface_checked " ident ", " ident ", " ident
  " for " term ", " term ", " term : command

macro_rules
  | `(kernel_surface_checked $present:ident, $checked:ident, $valid:ident for
        $artifact:term, $view:term, $origins:term) =>
      `(section
        theorem $present :
            (checkSurfaceArtifactOriginsView? $artifact $view $origins).isSome =
              true := by
          with_unfolding_all rfl
        def $checked : CheckedSurfaceArtifact $artifact :=
          (checkSurfaceArtifactOriginsView? $artifact $view $origins).get $present
        theorem $valid : SurfaceArtifactValid $artifact :=
          CheckedSurfaceArtifact.valid $checked
        end)

syntax "kernel_surface_checked_from_parse " ident ", " ident ", " ident
  " for " term ", " term ", " term ", " term : command

macro_rules
  | `(kernel_surface_checked_from_parse $present:ident, $checked:ident,
        $valid:ident for $artifact:term, $view:term, $origins:term,
        $parseValid:term) =>
      `(section
        theorem $present :
            (checkSurfaceArtifactOriginsViewOfParse? $artifact $view $origins
              $parseValid).isSome = true := by
          with_unfolding_all rfl
        def $checked : CheckedSurfaceArtifact $artifact :=
          (checkSurfaceArtifactOriginsViewOfParse? $artifact $view $origins
            $parseValid).get $present
        theorem $valid : SurfaceArtifactValid $artifact :=
          CheckedSurfaceArtifact.valid $checked
        end)

end Lanius.Extraction
