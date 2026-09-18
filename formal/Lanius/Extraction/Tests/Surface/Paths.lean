import Lanius.Extraction.Surface.Paths
import Lanius.Extraction.Surface.Views
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Surface.Paths

private def artifact : Artifact := {
  Artifact.empty with
  sources := [⟨"paths.lani", [97, 98]⟩]
  tokens := [⟨1, ⟨0, 0, 1⟩⟩, ⟨1, ⟨0, 1, 2⟩⟩]
  parse_nodes := [⟨7, 0, 0, 0, [.token 0]⟩, ⟨8, 0, 0, 0, [.token 1]⟩,
    ⟨9, 0, 0, 0, [.node 0]⟩, ⟨10, 0, 0, 0, [.node 1, .node 2]⟩] }

private def view : ArtifactView artifact :=
  (ArtifactView.canonical? artifact).get (by decide +kernel)

private def origins : SurfaceOrigins := {
  claims := {
    nodes := [⟨0, 0, some 3, [7]⟩, ⟨1, 1, some 3, [8]⟩]
    spellings := [⟨3, 0, "a"⟩, ⟨3, 1, "b"⟩] }
  nodePaths := [some ⟨3, [1, 0], 0⟩, some ⟨3, [0], 1⟩]
  spellingPaths := [⟨⟨3, [1, 0], 0⟩, 0, 0⟩, ⟨⟨3, [0], 1⟩, 0, 1⟩] }

private theorem checked : origins.checkReference view = true := by
  have coverage : spellingCoverageValid artifact origins.claims = true := by
    apply spellingCoverageValid_of_multiset
    decide +kernel
  unfold SurfaceOrigins.checkReference
  rw [coverage]
  decide +kernel

private theorem original_checked : surfaceClaimsValidIndexed artifact origins.claims = true :=
  origins.checkReference_sound view checked

private theorem malformed_rejected :
    ([{origins with nodePaths := []},
      {origins with nodePaths := origins.nodePaths ++ [none]},
      {origins with nodePaths := [some ⟨0, [], 0⟩, origins.nodePaths[1]!]},
      {origins with nodePaths := [some ⟨3, [1, 0], 1⟩, origins.nodePaths[1]!]},
      {origins with nodePaths := [some ⟨3, [0, 0], 0⟩, origins.nodePaths[1]!]},
      {origins with nodePaths := [some ⟨3, [2], 0⟩, origins.nodePaths[1]!]},
      {origins with spellingPaths := []},
      {origins with spellingPaths := origins.spellingPaths.reverse},
      {origins with claims := {origins.claims with spellings := [⟨3, 0, "z"⟩, ⟨3, 1, "b"⟩]}}].all
      fun proposed => !proposed.checkReference view) = true := by
  decide +kernel

-- Ordinary reachability does not imply acceptance of a pruned search.
private def nonpostorder : Artifact := { Artifact.empty with
  parse_nodes := [⟨0, 0, 0, 0, [.node 1]⟩, ⟨0, 0, 0, 0, [.node 3]⟩,
    ⟨0, 0, 0, 0, []⟩, ⟨0, 0, 0, 0, []⟩] }
private def nonpostorderView : ArtifactView nonpostorder :=
  (ArtifactView.canonical? nonpostorder).get (by decide +kernel)
private theorem pruning_checked :
    (ParseNodePath.mk 0 [0, 0] 3).valid nonpostorderView = true ∧
    (ParseNodePath.mk 0 [0, 0] 3).checkPruned nonpostorderView = false := by
  decide +kernel

-- A real path can exceed the original checker's available fuel.
private def cyclic : Artifact := { Artifact.empty with
  parse_nodes := [⟨0, 0, 0, 0, [.node 0]⟩] }
private def cyclicView : ArtifactView cyclic :=
  (ArtifactView.canonical? cyclic).get (by decide +kernel)
private theorem fuel_checked :
    (ParseNodePath.mk 0 [0, 0] 0).valid cyclicView = true ∧
    (ParseNodePath.mk 0 [0, 0] 0).checkPruned cyclicView = false := by
  decide +kernel

run_elab do
  for name in #[``ParseNodePath.checkPruned_sound, ``ParseTokenPath.valid_checker,
      ``SurfaceOrigins.checkReference_sound, ``checked, ``original_checked,
      ``malformed_rejected, ``pruning_checked, ``fuel_checked] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "path certificate {name} uses unexpected assumption {assumption}"

end Lanius.Extraction.Tests.Surface.Paths
