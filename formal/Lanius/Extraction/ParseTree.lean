import Lanius.Extraction.Artifact
import Init.Data.List.Sublist

namespace Lanius.Extraction

/-- A parse node with direct references in the original child-slot order.
Token slots contain `none`; their token IDs remain in the original node. -/
inductive ParseTree where
  | node (id : ParseNodeId) (value : ParseNode) (children : List (Option ParseTree))

namespace ParseTree

def id : ParseTree → ParseNodeId | .node id _ _ => id
def value : ParseTree → ParseNode | .node _ value _ => value
def children : ParseTree → List (Option ParseTree) | .node _ _ children => children

mutual
  /-- Every reference agrees with the canonical node list, recursively. -/
  inductive Valid (nodes : List ParseNode) : ParseTree → Prop where
    | node {id value children}
        (found : nodes[id]? = some value)
        (linked : ChildrenValid nodes value.children children) :
        Valid nodes (.node id value children)

  inductive ChildrenValid (nodes : List ParseNode) :
      List ParseChild → List (Option ParseTree) → Prop where
    | nil : ChildrenValid nodes [] []
    | token {token rest children}
        (linked : ChildrenValid nodes rest children) :
        ChildrenValid nodes (.token token :: rest) (none :: children)
    | node {id tree rest children}
        (sameId : tree.id = id)
        (valid : Valid nodes tree)
        (linked : ChildrenValid nodes rest children) :
        ChildrenValid nodes (.node id :: rest) (some tree :: children)
end

def ForestValid (nodes : List ParseNode) (forest : List ParseTree) : Prop :=
  ∀ tree ∈ forest, Valid nodes tree

/-- Consume completed children from the stack in reverse slot order, then
return them in grammar order with the untouched stack suffix. This fuses
counting, prefix extraction, reversal, and dropping into one traversal. -/
def consumeChildren : List ParseChild → List ParseTree →
    Option (List (Option ParseTree) × List ParseTree)
  | [], stack => some ([], stack)
  | .token _ :: rest, stack => do
    let (children, stack) ← consumeChildren rest stack
    pure (none :: children, stack)
  | .node id :: rest, stack => do
    let (children, stack) ← consumeChildren rest stack
    match stack with
    | entry :: stack =>
      if id == entry.id then some (some entry :: children, stack) else none
    | [] => none

theorem consume_sound (nodes : List ParseNode) (slots : List ParseChild)
    (stack : List ParseTree) (children : List (Option ParseTree)) (remaining : List ParseTree)
    (valid : ForestValid nodes stack)
    (accepted : consumeChildren slots stack = some (children, remaining)) :
    ChildrenValid nodes slots children ∧ ForestValid nodes remaining := by
  induction slots generalizing stack children remaining with
  | nil =>
    simp [consumeChildren] at accepted
    rcases accepted with ⟨rfl, rfl⟩
    exact ⟨.nil, valid⟩
  | cons slot slots ih =>
    cases next : consumeChildren slots stack with
    | none => cases slot <;> simp [consumeChildren, next] at accepted
    | some result =>
      rcases result with ⟨tail, rest⟩
      obtain ⟨linked, restValid⟩ := ih stack tail rest valid next
      cases slot with
      | token token =>
        simp [consumeChildren, next] at accepted
        rcases accepted with ⟨rfl, rfl⟩
        exact ⟨.token linked, restValid⟩
      | node id =>
        cases rest with
        | nil => simp [consumeChildren, next] at accepted
        | cons entry rest =>
          simp only [consumeChildren, next] at accepted
          change (if id == entry.id then some (some entry :: tail, rest) else none) =
            some (children, remaining) at accepted
          split at accepted
          · rename_i same
            simp only [Option.some.injEq, Prod.mk.injEq] at accepted
            rcases accepted with ⟨rfl, rfl⟩
            exact ⟨.node (eq_of_beq same).symm (restValid entry (by simp)) linked,
              fun tree member => restValid tree (by simp [member])⟩
          · simp at accepted

def linkFrom : Nat → List ParseNode → List ParseTree → Option (List ParseTree)
  | _, [], stack => some stack
  | id, value :: rest, stack => do
    let (children, stack) ← consumeChildren value.children stack
    linkFrom (id + 1) rest (.node id value children :: stack)

theorem linkFrom_sound (nodes : List ParseNode) (id : Nat)
    (remaining : List ParseNode) (stack forest : List ParseTree)
    (remainingValid : ∀ offset value, remaining[offset]? = some value →
      nodes[id + offset]? = some value)
    (stackValid : ForestValid nodes stack)
    (accepted : linkFrom id remaining stack = some forest) :
    ForestValid nodes forest := by
  induction remaining generalizing id stack with
  | nil =>
    simp [linkFrom] at accepted
    subst forest
    exact stackValid
  | cons value rest ih =>
    cases next : consumeChildren value.children stack with
    | none => simp [linkFrom, next] at accepted
    | some result =>
      rcases result with ⟨children, tail⟩
      obtain ⟨linked, tailValid⟩ := consume_sound nodes value.children stack children tail stackValid next
      apply ih (id + 1) (.node id value children :: tail)
      · intro offset child found
        have found' := remainingValid (offset + 1) child (by simpa using found)
        simpa [Nat.add_assoc, Nat.add_comm 1] using found'
      · intro entry member
        rcases List.mem_cons.mp member with rfl | member
        · exact .node (by simpa using remainingValid 0 value (by simp)) linked
        · exact tailValid entry member
      · simpa [linkFrom, next] using accepted

/-- Build references from a postorder list. Multiple completed roots are permitted. -/
def link (nodes : List ParseNode) : Option (List ParseTree) := linkFrom 0 nodes []

theorem link_sound (nodes : List ParseNode) (forest : List ParseTree)
    (accepted : link nodes = some forest) : ForestValid nodes forest := by
  apply linkFrom_sound nodes 0 nodes [] forest _ _ accepted
  · intro offset value found
    simpa using found
  · simp [ForestValid]

theorem Valid.found {nodes : List ParseNode} {tree : ParseTree}
    (valid : Valid nodes tree) : nodes[tree.id]? = some tree.value := by
  cases valid with
  | node found _ => exact found

theorem ChildrenValid.childId {nodes : List ParseNode}
    {original : List ParseChild} {children : List (Option ParseTree)}
    (linked : ChildrenValid nodes original children) (index : Nat) :
    ((children[index]?).join.map ParseTree.id) =
      ((original[index]?).bind fun child => match child with
        | .node id => some id
        | .token _ => none) := by
  induction index generalizing original children with
  | zero => cases linked <;> simp_all
  | succ index ih =>
    cases linked with
    | nil => simp
    | token linked => simpa using ih linked
    | node _ _ linked => simpa using ih linked

theorem ChildrenValid.childValid {nodes : List ParseNode}
    {original : List ParseChild} {children : List (Option ParseTree)}
    (linked : ChildrenValid nodes original children) (index : Nat) (child : ParseTree)
    (found : children[index]? = some (some child)) : Valid nodes child := by
  induction index generalizing original children with
  | zero => cases linked <;> simp_all
  | succ index ih =>
    cases linked with
    | nil => simp at found
    | token linked => exact ih linked (by simpa using found)
    | node _ _ linked => exact ih linked (by simpa using found)

theorem Valid.childValid {nodes : List ParseNode} {tree child : ParseTree}
    (valid : Valid nodes tree) (index : Nat)
    (found : tree.children[index]? = some (some child)) : Valid nodes child := by
  cases valid with
  | node _ linked => exact linked.childValid index child found

theorem Valid.childId {nodes : List ParseNode} {tree : ParseTree}
    (valid : Valid nodes tree) (index : Nat) :
    ((tree.children[index]?).join.map ParseTree.id) =
      ((tree.value.children[index]?).bind fun child => match child with
        | .node id => some id
        | .token _ => none) := by
  cases valid with
  | node _ linked => exact linked.childId index

/-- Proof-carrying references expose only trees tied to the original list. -/
abbrev Checked (nodes : List ParseNode) := { tree : ParseTree // Valid nodes tree }

def Checked.child? {nodes : List ParseNode} (tree : Checked nodes) (index : Nat) :
    Option (Checked nodes) :=
  match found : tree.val.children[index]? with
  | some (some child) => some ⟨child, tree.property.childValid index found⟩
  | _ => none

theorem Checked.childId {nodes : List ParseNode} (tree : Checked nodes) (index : Nat) :
    (tree.child? index).map (fun child => child.val.id) =
      ((tree.val.value.children[index]?).bind fun child => match child with
        | .node id => some id
        | .token _ => none) := by
  have agrees := tree.property.childId index
  unfold Checked.child?
  split
  · simp_all
  · rename_i missing
    cases found : tree.val.children[index]? with
    | none => simpa [found] using agrees
    | some child =>
      cases child with
      | none => simpa [found] using agrees
      | some child => exact False.elim (missing child found)

def checkedForest (nodes : List ParseNode) : Option (List (Checked nodes)) :=
  match accepted : link nodes with
  | none => none
  | some forest =>
    some (forest.attach.map fun tree =>
      ⟨tree.val, link_sound nodes forest accepted tree.val tree.property⟩)

end ParseTree
end Lanius.Extraction
