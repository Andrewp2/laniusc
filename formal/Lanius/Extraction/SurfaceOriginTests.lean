import Lanius.Extraction.SurfaceReconstructProvenance
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.SurfaceOriginTests

private def reference (artifact : Artifact) (view : ArtifactView artifact)
    (origin : SurfaceNodeOrigin) : Bool :=
  match view.node? origin.claim.parseNode with
  | none => false
  | some node =>
    origin.claim.allowedProductions.contains node.production &&
      match origin.claim.containingParseNode, origin.path with
      | none, none => true
      | some root, some path =>
        path.root == root && path.target == origin.claim.parseNode && path.valid view
      | _, _ => false

theorem valid_eq_reference (artifact : Artifact) (view : ArtifactView artifact)
    (origin : SurfaceNodeOrigin) : origin.valid artifact view = reference artifact view origin := by
  rcases origin with ⟨⟨id, parseNode, containing, allowed⟩, path⟩
  cases found : view.node? parseNode <;> simp [SurfaceNodeOrigin.valid, reference, found]
  cases containing <;> cases path <;> simp [ParseNodePath.valid]

private def referencePaths (artifact : Artifact) (view : ArtifactView artifact) :
    List SurfaceNodeClaim → List (Option ParseNodePath) → Bool
  | [], [] => true
  | claim :: claims, path :: paths =>
    reference artifact view ⟨claim, path⟩ && referencePaths artifact view claims paths
  | _, _ => false

theorem paths_eq_reference (artifact : Artifact) (view : ArtifactView artifact)
    (claims : List SurfaceNodeClaim) (paths : List (Option ParseNodePath)) :
    nodeOriginPathsValid artifact view claims paths = referencePaths artifact view claims paths := by
  induction claims generalizing paths with
  | nil => cases paths <;> rfl
  | cons claim claims ih =>
    cases paths <;> simp [nodeOriginPathsValid, referencePaths, valid_eq_reference, ih]

private def check (origin : SurfaceNodeOrigin) : Option Bool := do
  let artifact := { Artifact.empty with parse_nodes :=
    [⟨7, 0, 0, 0, []⟩, ⟨8, 0, 0, 0, [.node 0, .token 0]⟩] }
  let view ← ArtifactView.canonical? artifact
  pure (origin.valid artifact view)

private def casesPass : Bool :=
  -- Uncontained and reflexive/one-edge contained origins.
  check ⟨⟨0, 0, none, [7]⟩, none⟩ == some true &&
  check ⟨⟨0, 0, some 0, [7]⟩, some ⟨0, [], 0⟩⟩ == some true &&
  check ⟨⟨0, 0, some 1, [7]⟩, some ⟨1, [0], 0⟩⟩ == some true &&
  -- Missing node, disallowed production, and mismatched optional path.
  check ⟨⟨0, 9, none, [7]⟩, none⟩ == some false &&
  check ⟨⟨0, 0, none, [8]⟩, none⟩ == some false &&
  check ⟨⟨0, 0, some 1, [7]⟩, none⟩ == some false &&
  check ⟨⟨0, 0, none, [7]⟩, some ⟨0, [], 0⟩⟩ == some false &&
  -- Wrong root/target, token edge, absent slot, and missing path root.
  check ⟨⟨0, 0, some 1, [7]⟩, some ⟨0, [], 0⟩⟩ == some false &&
  check ⟨⟨0, 0, some 1, [7]⟩, some ⟨1, [], 1⟩⟩ == some false &&
  check ⟨⟨0, 0, some 1, [7]⟩, some ⟨1, [1], 0⟩⟩ == some false &&
  check ⟨⟨0, 0, some 1, [7]⟩, some ⟨1, [2], 0⟩⟩ == some false &&
  check ⟨⟨0, 0, some 9, [7]⟩, some ⟨9, [], 0⟩⟩ == some false

example : casesPass = true := by kernel_rfl
#guard casesPass
#print axioms valid_eq_reference
#print axioms paths_eq_reference
#print axioms SurfaceNodeOrigin.valid_sound
end Lanius.Extraction.SurfaceOriginTests
