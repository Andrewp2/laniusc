import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.Distinct

namespace Lanius.Extraction

/-- Use already authenticated tables as the artifact's stored data, instead
of recomputing decoded fields whenever downstream checks inspect a node. -/
def ParseArtifactView.materialized (view : ParseArtifactView artifact) : Artifact := {
  artifact with
  tokens := view.artifactView.cache.tokens.flatten
  parse_nodes := view.artifactView.cache.parseNodes.flatten
  semantic_token_kinds := view.semanticKinds.flatten }

theorem ParseArtifactView.materialized_eq (view : ParseArtifactView artifact) :
    view.materialized = artifact := by
  unfold materialized
  rw [view.artifactView.tokensRepresent, view.artifactView.parseNodesRepresent,
    view.semanticKindsRepresent]

/-- Transport the checked indexes without re-authenticating their contents. -/
def ParseArtifactView.materializedView (view : ParseArtifactView artifact) :
    ParseArtifactView view.materialized := {
  view with
  artifactView := {
    view.artifactView with
    parseNodesRepresent := rfl
    tokensRepresent := rfl
    sourceBytesRepresent := view.artifactView.sourceBytesRepresent }
  semanticKindsRepresent := rfl }

/-- Byte-array source data is already range-bounded. Retain that fact rather
than asking the kernel to validate each converted byte again. -/
theorem decodeBytes_uint8 (bytes : List UInt8) :
    decodeBytes (bytes.map UInt8.toNat) =
      some (bytes.map fun byte => (⟨byte.toNat, UInt8.toNat_lt byte⟩ : Fin 256)) := by
  induction bytes with
  | nil => rfl
  | cons byte bytes ih =>
      have head : decodeByte byte.toNat = some (byte.toFin) := by
        simp only [decodeByte, dif_pos (show byte.toNat < 256 from UInt8.toNat_lt byte)]
        rfl
      simp only [decodeBytes, List.map_cons, List.mapM_cons] at ih ⊢
      rw [head, ih]
      rfl

theorem ArtifactCache.ofArtifact_matches_of_source
    (artifact : Artifact) (source : SourceFile) (bytes : List (Fin 256))
    (sources : artifact.sources = [source]) (decoded : decodeBytes source.bytes = some bytes) :
    (ArtifactCache.ofArtifact artifact).matches artifact = true := by
  have nodesFit := Nat.le_max_left artifact.parse_nodes.length
    (Nat.max artifact.tokens.length bytes.length)
  have tokensFit := Nat.le_trans (Nat.le_max_left artifact.tokens.length bytes.length)
    (Nat.le_max_right artifact.parse_nodes.length (Nat.max artifact.tokens.length bytes.length))
  have bytesFit := Nat.le_trans (Nat.le_max_right artifact.tokens.length bytes.length)
    (Nat.le_max_right artifact.parse_nodes.length (Nat.max artifact.tokens.length bytes.length))
  simp [ArtifactCache.ofArtifact, ArtifactCache.matches, sources, decoded,
    Lanius.Data.SeqTree.wellFormed, Lanius.Data.SeqTree.flatten, nodesFit, tokensFit, bytesFit]

def ArtifactView.canonicalOfSource
    (artifact : Artifact) (source : SourceFile) (bytes : List (Fin 256))
    (sources : artifact.sources = [source]) (decoded : decodeBytes source.bytes = some bytes) :
    ArtifactView artifact :=
  ArtifactCache.ofMatches (ArtifactCache.ofArtifact_matches_of_source artifact source bytes sources decoded)

theorem ArtifactView.canonical?_of_source
    (artifact : Artifact) (source : SourceFile) (bytes : List (Fin 256))
    (sources : artifact.sources = [source]) (decoded : decodeBytes source.bytes = some bytes) :
    ArtifactView.canonical? artifact =
      some (ArtifactView.canonicalOfSource artifact source bytes sources decoded) := by
  unfold canonical? ArtifactCache.checked? canonicalOfSource
  rw [dif_pos (ArtifactCache.ofArtifact_matches_of_source artifact source bytes sources decoded)]

/-- Change only the authenticated lookup representation. All reconstructed
data and the exact artifact remain unchanged. -/
def CheckedSurfaceArtifact.rebase (checked : CheckedSurfaceArtifact artifact)
    (view : ArtifactView artifact) : CheckedSurfaceArtifact artifact := {
  checked with
  view
  reconstructedFound := by
    rw [reconstructArtifactSurfaceView_eq,
      ← reconstructArtifactSurfaceView_eq artifact checked.view]
    exact checked.reconstructedFound
  claimsFound := by
    rw [collectSurfaceClaimsView_eq, ← collectSurfaceClaimsView_eq artifact checked.view]
    exact checked.claimsFound
  surfaceFound := by
    rw [decodeReconstructedSurfaceView_eq,
      ← decodeReconstructedSurfaceView_eq artifact checked.view]
    exact checked.surfaceFound }

/-- Indexed validation can be transported to the reference checker's exact
result, not merely to a weaker validity proposition. -/
theorem checkSurfaceArtifactView?_rebase (artifact : Artifact)
    (left right : ArtifactView artifact) :
    (checkSurfaceArtifactView? artifact left).map (·.rebase right) =
      checkSurfaceArtifactView? artifact right := by
  unfold checkSurfaceArtifactView?
  repeat first
    | rfl
    | contradiction
    | simp_all (config := { failIfUnchanged := true })
        [checkParseArtifactView_eq, reconstructArtifactSurfaceView_eq, CheckedSurfaceArtifact.rebase]
    | split

theorem checkSurfaceArtifact?_of_view (view reference : ArtifactView artifact)
    (canonical : ArtifactView.canonical? artifact = some reference)
    (checked : CheckedSurfaceArtifact artifact)
    (accepted : checkSurfaceArtifactView? artifact view = some checked) :
    checkSurfaceArtifact? artifact = some (checked.rebase reference) := by
  unfold checkSurfaceArtifact?
  rw [canonical]
  change checkSurfaceArtifactView? artifact reference = some (checked.rebase reference)
  rw [← checkSurfaceArtifactView?_rebase artifact view reference, accepted]
  rfl

/-- Establish the original sorted-list coverage equation using the existing
kernel-reducible sorter. No duplicate or missing spelling can be hidden. -/
theorem spellingCoverageValid_of_multiset (artifact : Artifact) (claims : SurfaceClaims)
    (accepted : Distinct.sameMultiset (claims.spellings.map (·.token))
      (expectedSpellingTokens artifact) = true) : spellingCoverageValid artifact claims = true :=
  beq_iff_eq.mpr (Distinct.sameMultiset_mergeSort accepted)

/-- Assemble checked data from retained phase equations, without evaluating
the original checker again when a later consumer projects a syntax field. -/
def CheckedSurfaceArtifact.ofComponents (view : ArtifactView artifact)
    (reconstructed : SurfaceFile) (claims : SurfaceClaims) (surface : Lanius.Surface.File)
    (parsed : checkParseArtifactView artifact view = true)
    (rebuilt : reconstructArtifactSurfaceView artifact view = some reconstructed)
    (collected : collectSurfaceClaimsFrom artifact reconstructed = some claims)
    (decoded : decodeSurfaceFile (artifact.parse_nodes.length + 1) reconstructed = some surface)
    (validated : surfaceClaimsValidIndexed artifact claims = true) :
    CheckedSurfaceArtifact artifact := by
  have collectedView : collectSurfaceClaimsView artifact view = some claims := by
    simp [collectSurfaceClaimsView, rebuilt, collected]
  have decodedView : decodeReconstructedSurfaceView artifact view = some surface := by
    simp [decodeReconstructedSurfaceView, rebuilt, decoded]
  exact ⟨view, reconstructed, rebuilt, claims, collectedView, surface, decodedView,
    SurfaceArtifactValid.ofView view (checkParseArtifactView_sound view parsed)
      collectedView decodedView (surfaceClaimsValidIndexed_sound view validated)⟩

/-- The retained record is exactly the original checker's output. -/
theorem checkSurfaceArtifactView?_of_components (view : ArtifactView artifact)
    (reconstructed : SurfaceFile) (claims : SurfaceClaims) (surface : Lanius.Surface.File)
    (parsed : checkParseArtifactView artifact view = true)
    (rebuilt : reconstructArtifactSurfaceView artifact view = some reconstructed)
    (collected : collectSurfaceClaimsFrom artifact reconstructed = some claims)
    (decoded : decodeSurfaceFile (artifact.parse_nodes.length + 1) reconstructed = some surface)
    (validated : surfaceClaimsValidIndexed artifact claims = true) :
    checkSurfaceArtifactView? artifact view =
      some (CheckedSurfaceArtifact.ofComponents view reconstructed claims surface
        parsed rebuilt collected decoded validated) := by
  unfold checkSurfaceArtifactView?
  repeat first
    | rfl
    | contradiction
    | simp_all (config := { failIfUnchanged := true }) [CheckedSurfaceArtifact.ofComponents]
    | split

end Lanius.Extraction
