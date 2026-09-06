import Lanius.Extraction.ParseChecker
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.ParseRootTests
private def root : ParseNode := {
  production := 0, nonterminal := laniusGrammar.start_nonterminal,
  position_start := 0, position_end := 0, children := []
}
private def check (nodes : List ParseNode) (id : Nat) : Option Bool := do
  let artifact := { Artifact.empty with parse_nodes := nodes }
  let view ← ArtifactView.canonical? artifact
  pure (rootShapeValidView laniusGrammar view id)

example : check [root] 0 = some true := by kernel_rfl
example : check [] 0 = some false := by kernel_rfl
example : check [root] 1 = some false := by kernel_rfl
example : check [root, root] 0 = some false := by kernel_rfl
example : check [root, root] 1 = some true := by kernel_rfl
example : check [{ root with nonterminal := laniusGrammar.start_nonterminal + 1 }] 0 =
    some false := by kernel_rfl
example : check [{ root with position_start := 1 }] 0 = some false := by kernel_rfl
example : check [{ root with position_end := 2 }] 0 = some false := by kernel_rfl

-- Exact equivalence covers arbitrary grammars, views, and missing roots too.
example (grammar : Grammar) (view : ArtifactView artifact) (id : Nat) :
    rootShapeValidView grammar view id =
      rootShapeValid grammar artifact.tokens.length artifact.parse_nodes id :=
  rootShapeValidView_eq grammar view id

#print axioms rootShapeValidView_eq
#print axioms rootShapeValid_of_view
#print axioms checkParseArtifact_of_checks
end Lanius.Extraction.ParseRootTests
