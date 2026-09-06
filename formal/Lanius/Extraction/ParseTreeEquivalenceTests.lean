import Lanius.Extraction.ParseTree

namespace Lanius.Extraction.ParseTreeEquivalenceTests

-- The previous implementation is a test oracle, not a production fallback.
private def referenceChildren :
    List ParseChild → List ParseTree → Option (List (Option ParseTree))
  | [], [] => some []
  | .token _ :: rest, entries => (none :: ·) <$> referenceChildren rest entries
  | .node id :: rest, entry :: entries =>
    if id == entry.id then (some entry :: ·) <$> referenceChildren rest entries else none
  | _, _ => none

private def referenceLinkFrom : Nat → List ParseNode → List ParseTree → Option (List ParseTree)
  | _, [], stack => some stack
  | id, value :: rest, stack => do
    let count := value.children.countP fun child => match child with
      | .node _ => true
      | .token _ => false
    let children ← referenceChildren value.children (stack.take count).reverse
    referenceLinkFrom (id + 1) rest (.node id value children :: stack.drop count)


theorem consume_decompose (slots : List ParseChild) (stack : List ParseTree)
    (children : List (Option ParseTree)) (remaining : List ParseTree)
    (accepted : ParseTree.consumeChildren slots stack = some (children, remaining)) :
    ∃ entries, referenceChildren slots entries = some children ∧
      stack = entries.reverse ++ remaining := by
  induction slots generalizing stack children remaining with
  | nil =>
    simp [ParseTree.consumeChildren] at accepted
    rcases accepted with ⟨rfl, rfl⟩
    exact ⟨[], rfl, by simp⟩
  | cons slot slots ih =>
    cases next : ParseTree.consumeChildren slots stack with
    | none => cases slot <;> simp [ParseTree.consumeChildren, next] at accepted
    | some result =>
      rcases result with ⟨tail, rest⟩
      obtain ⟨entries, linked, shape⟩ := ih stack tail rest next
      cases slot with
      | token token =>
        simp [ParseTree.consumeChildren, next] at accepted
        rcases accepted with ⟨rfl, rfl⟩
        exact ⟨entries, by simp [referenceChildren, linked], shape⟩
      | node id =>
        cases rest with
        | nil => simp [ParseTree.consumeChildren, next] at accepted
        | cons entry rest =>
          simp only [ParseTree.consumeChildren, next] at accepted
          change (if id == entry.id then some (some entry :: tail, rest) else none) =
            some (children, remaining) at accepted
          split at accepted
          · rename_i same
            simp only [Option.some.injEq, Prod.mk.injEq] at accepted
            rcases accepted with ⟨rfl, rfl⟩
            refine ⟨entry :: entries, by simp [referenceChildren, same, linked], ?_⟩
            simpa [List.reverse_cons, List.append_assoc] using shape
          · simp at accepted

theorem consume_of_linked (slots : List ParseChild) (entries : List ParseTree)
    (children : List (Option ParseTree))
    (accepted : referenceChildren slots entries = some children)
    (remaining : List ParseTree) :
    ParseTree.consumeChildren slots (entries.reverse ++ remaining) = some (children, remaining) := by
  induction slots generalizing entries children remaining with
  | nil =>
    cases entries <;> simp [referenceChildren] at accepted
    subst children
    rfl
  | cons slot slots ih =>
    cases slot with
    | token token =>
      cases next : referenceChildren slots entries with
      | none => simp [referenceChildren, next] at accepted
      | some tail =>
        simp [referenceChildren, next] at accepted
        subst children
        simp [ParseTree.consumeChildren, ih entries tail next remaining]
    | node id =>
      cases entries with
      | nil => simp [referenceChildren] at accepted
      | cons entry entries =>
        simp only [referenceChildren] at accepted
        split at accepted
        · rename_i same
          cases next : referenceChildren slots entries with
          | none => simp [next] at accepted
          | some tail =>
            simp [next] at accepted
            subst children
            simp only [ParseTree.consumeChildren, List.reverse_cons, List.append_assoc,
              List.singleton_append]
            rw [ih entries tail next (entry :: remaining)]
            simp [eq_of_beq same]
        · simp at accepted
def nodeCount (slots : List ParseChild) : Nat :=
  slots.countP fun child => match child with | .node _ => true | .token _ => false

theorem linked_count (slots : List ParseChild) (entries : List ParseTree)
    (children : List (Option ParseTree))
    (accepted : referenceChildren slots entries = some children) :
    entries.length = nodeCount slots := by
  induction slots generalizing entries children with
  | nil => cases entries <;> simp_all [referenceChildren, nodeCount]
  | cons slot slots ih =>
    cases slot with
    | token token =>
      cases next : referenceChildren slots entries with
      | none => simp [referenceChildren, next] at accepted
      | some tail => simpa [nodeCount] using ih entries tail next
    | node id =>
      cases entries with
      | nil => simp [referenceChildren] at accepted
      | cons entry entries =>
        simp only [referenceChildren] at accepted
        split at accepted
        · cases next : referenceChildren slots entries with
          | none => simp [next] at accepted
          | some tail => simpa [nodeCount] using congrArg Nat.succ (ih entries tail next)
        · simp at accepted

def reference (slots : List ParseChild) (stack : List ParseTree) :
    Option (List (Option ParseTree) × List ParseTree) := do
  let children ← referenceChildren slots (stack.take (nodeCount slots)).reverse
  pure (children, stack.drop (nodeCount slots))

theorem consume_eq_reference (slots : List ParseChild) (stack : List ParseTree) :
    ParseTree.consumeChildren slots stack = reference slots stack := by
  apply Option.ext
  intro result
  rcases result with ⟨children, remaining⟩
  constructor
  · intro accepted
    obtain ⟨entries, linked, rfl⟩ := consume_decompose slots stack children remaining accepted
    have count := linked_count slots entries children linked
    simp [reference, ← count, linked]
  · intro accepted
    unfold reference at accepted
    cases found : referenceChildren slots (stack.take (nodeCount slots)).reverse with
    | none => simp [found] at accepted
    | some children' =>
      simp [found] at accepted
      rcases accepted with ⟨rfl, rfl⟩
      simpa using consume_of_linked slots (stack.take (nodeCount slots)).reverse
        children' found (stack.drop (nodeCount slots))

theorem linkFrom_eq (id : Nat) (nodes : List ParseNode) (stack : List ParseTree) :
    ParseTree.linkFrom id nodes stack = referenceLinkFrom id nodes stack := by
  induction nodes generalizing id stack with
  | nil => rfl
  | cons value rest ih =>
    simp only [ParseTree.linkFrom, consume_eq_reference, reference, referenceLinkFrom, nodeCount]
    simp only [ih]
    simp only [bind_assoc, pure_bind]


private def listsUpTo (values : List α) : Nat → List (List α)
  | 0 => [[]]
  | n + 1 => [] :: (values.flatMap fun value => (listsUpTo values n).map (value :: ·))

private def observe (result : Option (List (Option ParseTree) × List ParseTree)) :=
  result.map fun (children, stack) =>
    (children.map (fun child => Option.map ParseTree.id child), stack.map ParseTree.id)

-- Compiled differential coverage supplements the all-input kernel theorem.
-- Leaves with a given ID are identical, so IDs distinguish these fixtures.
#guard (listsUpTo [.token 7, .node 0, .node 1, .node 2] 4).all fun slots =>
  (listsUpTo [0, 1, 2] 3).all fun ids =>
    let stack := ids.map fun id => ParseTree.node id ⟨0, 0, 0, 0, []⟩ []
    observe (ParseTree.consumeChildren slots stack) == observe (reference slots stack)

#print axioms consume_eq_reference
#print axioms linkFrom_eq
end Lanius.Extraction.ParseTreeEquivalenceTests
