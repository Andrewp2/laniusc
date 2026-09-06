import Lanius.Extraction.ParsePostorder
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.ParsePostorderTests

-- The former projection-based predicate is a reference model, not a second
-- production checker. Equivalence includes invalid inputs and arbitrary stacks.
private def referenceNode (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) (value : ParseNode) (entries : List ParsePostorder.Entry) : Bool :=
  match grammar.production? value.production with
  | none => false
  | some production =>
    value.nonterminal = production.lhs &&
    value.position_start ≤ value.position_end &&
    value.position_end ≤ view.semanticKinds.size * 2 &&
    ParsePostorder.children grammar view id production.rhs value.children
      value.position_start entries = some value.position_end

theorem node_eq_reference (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) (value : ParseNode) (entries : List ParsePostorder.Entry) :
    ParsePostorder.node grammar view id value entries = referenceNode grammar view id value entries := by
  cases value
  rfl

private def referenceCheck (grammar : Grammar) (view : ParseArtifactView artifact) :
    Nat → List ParseNode → List ParsePostorder.Entry → Bool
  | _, [], _ => true
  | id, value :: rest, stack =>
    let count := ParsePostorder.childCount value
    referenceNode grammar view id value (stack.take count).reverse &&
      referenceCheck grammar view (id + 1) rest ((id, value) :: stack.drop count)

theorem check_eq_reference (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) (values : List ParseNode) (stack : List ParsePostorder.Entry) :
    ParsePostorder.check grammar view id values stack = referenceCheck grammar view id values stack := by
  induction values generalizing id stack with
  | nil => rfl
  | cons value values ih => simp only [ParsePostorder.check, referenceCheck, node_eq_reference, ih]

private def view : ParseArtifactView Artifact.empty := {
  artifactView := ArtifactCache.ofMatches (cache := {
    leafCapacity := 8, parseNodes := .leaf [], tokens := .leaf [], primarySourceBytes := .leaf []
  }) (by kernel_rfl)
  leafCapacity := 8, semanticKinds := .leaf []
  semanticKindsWellFormed := Nat.zero_le 8
  semanticKindsRepresent := rfl
}
private def grammar : Grammar := {
  n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0,
  split_token_kind := 0, split_component_kind := 0,
  canonical_kinds := [0], productions := [⟨0, []⟩]
}
private def valid : ParseNode := ⟨0, 0, 0, 0, []⟩
private def casesPass : Bool :=
  ParsePostorder.node grammar view 0 valid [] &&
  ([{ valid with production := 1 }, { valid with nonterminal := 1 },
    { valid with position_start := 1 }, { valid with position_end := 1 },
    { valid with children := [.token 0] }]).all fun value =>
      !ParsePostorder.node grammar view 0 value []
example : casesPass = true := by kernel_rfl
#guard casesPass
#print axioms node_eq_reference
#print axioms check_eq_reference
#print axioms ParsePostorder.check_all_sound
end Lanius.Extraction.ParsePostorderTests
