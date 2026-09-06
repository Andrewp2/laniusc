import Lanius.Extraction.ArtifactView
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.ArtifactViewTests
private def node : ParseNode := {
  production := 0, nonterminal := 0, position_start := 0, position_end := 0, children := []
}
private def cache : ArtifactCache := {
  leafCapacity := 64, parseNodes := .leaf [node], tokens := .leaf [],
  primarySourceBytes := .leaf []
}
private def artifact : Artifact := { Artifact.empty with parse_nodes := cache.parseNodes.flatten }

private def view : ArtifactView artifact :=
  ArtifactCache.ofMatches (cache := cache) (by kernel_rfl)

example : view.nodeCount = 1 := by kernel_rfl
example : view.nodeCount = artifact.parse_nodes.length := view.nodeCount_eq
example : view.tokenCount = 0 := by kernel_rfl
example : view.tokenCount = artifact.tokens.length := view.tokenCount_eq

example : cache.matches artifact = true :=
  cache.matches_of_sharedNodes artifact rfl (by kernel_rfl)

-- Skipping the comparison is not sufficient without the representation proof.
example : cache.matchesWithSharedNodes Artifact.empty = true := by kernel_rfl
example : cache.matches Artifact.empty = false := by kernel_rfl

-- Sharing values does not make forged metadata or other cache fields valid.
private def forged : ArtifactCache := { cache with
  parseNodes := .branch 999 2 (.leaf [node]) (.leaf [node]) }
example : forged.matchesWithSharedNodes
    { Artifact.empty with parse_nodes := forged.parseNodes.flatten } = false := by kernel_rfl
example : cache.matchesWithSharedNodes
    { artifact with tokens := [{ kind := 0, span := { file := 0, start := 0, finish := 1 } }] } = false := by kernel_rfl
example : cache.matchesWithSharedNodes
    { artifact with sources := [{ path := "test", bytes := [97] }] } = false := by kernel_rfl

#print axioms ArtifactCache.matches_of_sharedNodes
end Lanius.Extraction.ArtifactViewTests
