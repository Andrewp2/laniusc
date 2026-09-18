import Lanius.Extraction.SurfaceReconstruct
import Lanius.Extraction.Reconstruction.Validated
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.Reconstruction.Contexts

/-- Detached trees are proposals, not authenticated artifact references. A
source certificate must still establish agreement with its original nodes. -/
instance : ParseReference ParseTree where
  id := ParseTree.id
  node? := fun _ tree => some tree.value
  child? := fun _ tree index => tree.children[index]?.join

/-- A binary precedence layer with no operator. Its two postorder nodes are
determined by the child; no per-occurrence production or span choices remain. -/
def nonterminal : ReconstructBinaryLayer → Nat
  | .logical_or => 72 | .logical_and => 2 | .bit_or => 14 | .bit_xor => 16
  | .bit_and => 12 | .equality => 43 | .comparison => 26 | .shift => 101
  | .additive => 0 | .multiplicative => 70

def inputNonterminal (layer : ReconstructBinaryLayer) : Nat :=
  match layer.next with
  | some next => nonterminal next
  | none => 131

private theorem rules (layer : ReconstructBinaryLayer) :
    laniusGrammar.production? layer.headProduction =
      some ⟨nonterminal layer, [191 + inputNonterminal layer, 191 + (nonterminal layer + 1)]⟩ ∧
    laniusGrammar.production? layer.endProduction = some ⟨nonterminal layer + 1, []⟩ ∧
    inputNonterminal layer < 136 ∧ nonterminal layer + 1 < 136 := by
  cases layer <;> decide +kernel

def emptyNode (layer : ReconstructBinaryLayer) (child : ParseTree) : ParseNode := {
    production := layer.endProduction
    nonterminal := nonterminal layer + 1
    position_start := child.value.position_end
    position_end := child.value.position_end
    children := [] }
def binaryNode (layer : ReconstructBinaryLayer) (child : ParseTree) : ParseNode := {
    production := layer.headProduction
    nonterminal := nonterminal layer
    position_start := child.value.position_start
    position_end := child.value.position_end
    children := [.node child.id, .node (child.id + 1)] }
def binary (layer : ReconstructBinaryLayer) (child : ParseTree) : ParseTree :=
  .node (child.id + 2) (binaryNode layer child)
    [some child, some (.node (child.id + 1) (emptyNode layer child) [])]

private theorem lift_some (value : α) :
    (liftM (some value) : SurfaceBuild α) = pure value := rfl

section
variable [ArtifactAccess]

/-- Equality of the complete state transformer, including failure. No output
value or successful child evaluation is assumed. -/
theorem binary_eq (fuel : Nat) (artifact : Artifact) (layer : ReconstructBinaryLayer)
    (child : ParseTree) :
    reconstructBinaryLayer (fuel + 2) artifact (binary layer child) layer =
      (match layer.next with
      | some next => reconstructBinaryLayer (fuel + 1) artifact child next
      | none => reconstructUnary (fuel + 1) artifact child) := by
  rw [reconstructBinaryLayer]
  simp only [binary, binaryNode, emptyNode, artifactExpectProduction, artifactProduction?, artifactNode?,
    artifactChildNode?, ParseReference.node?, ParseReference.child?, ParseTree.value,
    ParseTree.children, List.getElem?_cons_zero, List.getElem?_cons_succ,
    Option.join_some, bind_pure_comp]
  cases layer.next <;>
    simp [reconstructBinaryTail, artifactProduction?, artifactNode?, ParseReference.node?,
      ParseTree.value, lift_some]

def precedence (child : ParseTree) : ParseTree :=
  ([.logical_or, .logical_and, .bit_or, .bit_xor, .bit_and, .equality,
    .comparison, .shift, .additive, .multiplicative] : List ReconstructBinaryLayer).foldr binary child

/-- Twenty grammar nodes, with no per-occurrence execution of their semantic
actions. The subtree's own reconstruction remains an obligation. -/
theorem precedence_eq (fuel : Nat) (artifact : Artifact) (child : ParseTree) :
    reconstructBinaryLayer (fuel + 11) artifact (precedence child) .logical_or =
      reconstructUnary (fuel + 1) artifact child := by
  simp only [precedence, List.foldr_cons, List.foldr_nil, binary_eq,
    ReconstructBinaryLayer.next]

end

private theorem binary_check (view : ParseArtifactView artifact) (layer : ReconstructBinaryLayer)
    (child : ParseTree) (stack : List ParsePostorder.Entry) (rest : List ParseNode)
    (typed : child.value.nonterminal = inputNonterminal layer)
    (ordered : child.value.position_start ≤ child.value.position_end)
    (bounded : child.value.position_end ≤ view.semanticKinds.size * 2) :
    ParsePostorder.check laniusGrammar view (child.id + 1)
      ([emptyNode layer child, binaryNode layer child] ++ rest) ((child.id, child.value) :: stack) =
      ParsePostorder.check laniusGrammar view ((binary layer child).id + 1) rest
        (((binary layer child).id, (binary layer child).value) :: stack) := by
  rcases child with ⟨nodeId, value, children⟩
  simp only [ParseTree.value] at typed ordered bounded
  have idBound : ¬ nodeId + 1 + 1 ≤ nodeId :=
    Nat.not_le.mpr (Nat.lt_succ_of_lt (Nat.lt_succ_self nodeId))
  have endOk : value.position_end.ble (view.semanticKinds.size * 2) = true := Nat.ble_eq.mpr bounded
  have orderedOk : value.position_start.ble value.position_end = true := Nat.ble_eq.mpr ordered
  simp [ParsePostorder.check, ParsePostorder.childCount, binary, binaryNode, emptyNode,
    ParseTree.id, ParseTree.value, ParsePostorder.node, ParsePostorder.nodeWithLookup,
    ParsePostorder.children, (rules layer).1, (rules layer).2.1, typed, endOk, orderedOk, idBound,
    show laniusGrammar.n_kinds = 191 from rfl,
    show laniusGrammar.n_nonterminals = 136 from rfl,
    Nat.not_le.mpr (rules layer).2.2.1, Nat.not_le.mpr (rules layer).2.2.2,
    Nat.not_lt.mpr (Nat.le_add_right 191 (inputNonterminal layer)),
    Nat.not_lt.mpr (Nat.le_add_right 191 (nonterminal layer + 1)),
    Nat.ble_eq_true_of_le (Nat.le_refl value.position_end), Nat.add_assoc]

/-- The same context also discharges the original grammar validator and stack
linker. It cannot hide a wrong child nonterminal, reversed span, or past-EOF end. -/
theorem binary_link (view : ParseArtifactView artifact) (layer : ReconstructBinaryLayer)
    (child : ParseTree) (stack : List ParseTree)
    (typed : child.value.nonterminal = inputNonterminal layer)
    (ordered : child.value.position_start ≤ child.value.position_end)
    (bounded : child.value.position_end ≤ view.semanticKinds.size * 2) :
    Validated.linkFrom laniusGrammar view laniusGrammar.production? (child.id + 1)
      [emptyNode layer child, binaryNode layer child] (child :: stack) =
      some (binary layer child :: stack) := by
  rcases child with ⟨id, value, children⟩
  simp only [ParseTree.value] at typed ordered bounded
  have headRule := (rules layer).1
  have tailRule := (rules layer).2.1
  have inputBound := (rules layer).2.2.1
  have tailBound := (rules layer).2.2.2
  simp [Validated.linkFrom, ParseTree.consumeChildren, binary, binaryNode, emptyNode,
    ParseTree.id, ParseTree.value, ParsePostorder.nodeWithLookup, ParsePostorder.children,
    headRule, tailRule, typed, ordered, bounded,
    show laniusGrammar.n_kinds = 191 from rfl,
    show laniusGrammar.n_nonterminals = 136 from rfl,
    Nat.not_le.mpr inputBound, Nat.not_le.mpr tailBound]
  omega

theorem link_append (grammar : Grammar) (view : ParseArtifactView artifact)
    (lookup : Nat → Option Production) (left right : List ParseNode) (id : Nat)
    (stack : List ParseTree) :
    Validated.linkFrom grammar view lookup id (left ++ right) stack =
      (Validated.linkFrom grammar view lookup id left stack).bind
        (Validated.linkFrom grammar view lookup (id + left.length) right) := by
  induction left generalizing id stack with
  | nil => simp [Validated.linkFrom]
  | cons node rest ih =>
    cases consumed : ParseTree.consumeChildren node.children stack with
    | none => simp [Validated.linkFrom, consumed]
    | some pair =>
      rcases pair with ⟨children, remaining⟩
      by_cases ok : ParsePostorder.nodeWithLookup grammar view lookup id node
        (children.filterMap fun child => child.map fun tree => (tree.id, tree.value)) = true
      all_goals simp [Validated.linkFrom, consumed, ok, ih, Nat.add_assoc, Nat.add_comm 1]

def Compatible : Nat → List ReconstructBinaryLayer → Prop
  | _, [] => True
  | input, layer :: rest => input = inputNonterminal layer ∧ Compatible (nonterminal layer) rest

def nodes : List ReconstructBinaryLayer → ParseTree → List ParseNode
  | [], _ => []
  | layer :: rest, child =>
    [emptyNode layer child, binaryNode layer child] ++ nodes rest (binary layer child)

def root : List ReconstructBinaryLayer → ParseTree → ParseTree
  | [], child => child
  | layer :: rest, child => root rest (binary layer child)

theorem steps_link (view : ParseArtifactView artifact) (layers : List ReconstructBinaryLayer)
    (child : ParseTree) (stack : List ParseTree)
    (typed : Compatible child.value.nonterminal layers)
    (ordered : child.value.position_start ≤ child.value.position_end)
    (bounded : child.value.position_end ≤ view.semanticKinds.size * 2) :
    Validated.linkFrom laniusGrammar view laniusGrammar.production? (child.id + 1)
      (nodes layers child) (child :: stack) = some (root layers child :: stack) := by
  induction layers generalizing child with
  | nil => rfl
  | cons layer rest ih =>
    rw [nodes, link_append, binary_link view layer child stack typed.1 ordered bounded]
    exact ih (binary layer child) typed.2 ordered bounded

def levels : List ReconstructBinaryLayer :=
  [.multiplicative, .additive, .shift, .comparison, .equality,
    .bit_and, .bit_xor, .bit_or, .logical_and, .logical_or]

theorem steps_check (view : ParseArtifactView artifact) (layers : List ReconstructBinaryLayer)
    (child : ParseTree) (stack : List ParsePostorder.Entry)
    (typed : Compatible child.value.nonterminal layers)
    (ordered : child.value.position_start ≤ child.value.position_end)
    (bounded : child.value.position_end ≤ view.semanticKinds.size * 2) :
    ParsePostorder.check laniusGrammar view (child.id + 1)
      (nodes layers child) ((child.id, child.value) :: stack) = true := by
  induction layers generalizing child with
  | nil => rfl
  | cons layer rest ih =>
    rw [nodes, binary_check view layer child stack _ typed.1 ordered bounded]
    exact ih (binary layer child) typed.2 ordered bounded

theorem precedence_link (view : ParseArtifactView artifact) (child : ParseTree)
    (stack : List ParseTree) (typed : child.value.nonterminal = 131)
    (ordered : child.value.position_start ≤ child.value.position_end)
    (bounded : child.value.position_end ≤ view.semanticKinds.size * 2) :
    Validated.linkFrom laniusGrammar view laniusGrammar.production? (child.id + 1)
      (nodes levels child) (child :: stack) = some (precedence child :: stack) := by
  apply steps_link view levels child stack
  · exact ⟨typed, by simp [Compatible, inputNonterminal, nonterminal, ReconstructBinaryLayer.next]⟩
  · exact ordered
  · exact bounded

/-- Binding is separate from the reusable context proof and is never trusted. -/
def matchesSource (view : ArtifactView artifact) (child : ParseTree) : Bool :=
  view.node? child.id == some child.value &&
    (nodes levels child).zipIdx.all (fun (node, offset) =>
      view.node? (child.id + 1 + offset) == some node)

theorem matchesSource_of_range (view : ArtifactView artifact) (child : ParseTree)
    (accepted : view.cache.parseNodes.rangeEq child.id (child.value :: nodes levels child) = true) :
    matchesSource view child = true := by
  have equal := Lanius.Data.SeqTree.rangeEq_sound view.parseNodesWellFormed accepted
  rw [view.parseNodesRepresent] at equal
  have found (offset : Nat) (node : ParseNode)
      (present : (child.value :: nodes levels child)[offset]? = some node) :
      artifact.parse_nodes[child.id + offset]? = some node := by
    rw [← equal, List.getElem?_take] at present
    split at present
    · simpa using present
    · simp at present
  simp only [matchesSource, Bool.and_eq_true, beq_iff_eq, List.all_eq_true]
  constructor
  · exact (view.node?_eq child.id).trans (by simpa using found 0 child.value (by simp))
  · intro entry member
    apply (view.node?_eq _).trans
    have present := List.mem_zipIdx_iff_getElem?.mp member
    simpa [Nat.add_assoc, Nat.add_comm 1] using found (entry.2 + 1) entry.1 (by simpa using present)

/-- A proposed context implies the original indexed node predicate only after
every proposed node has been authenticated against the source artifact. -/
theorem source_checked (view : ParseArtifactView artifact) (child : ParseTree)
    (matched : matchesSource view.artifactView child = true)
    (typed : child.value.nonterminal = 131)
    (ordered : child.value.position_start ≤ child.value.position_end)
    (bounded : child.value.position_end ≤ view.semanticKinds.size * 2) :
    checkNodesFromParseView laniusGrammar artifact view (child.id + 1) (nodes levels child) = true := by
  simp only [matchesSource, Bool.and_eq_true, beq_iff_eq, List.all_eq_true] at matched
  apply ParsePostorder.check_sound laniusGrammar view (child.id + 1) (nodes levels child)
    [(child.id, child.value)]
  · intro offset value found
    exact matched.2 (value, offset) (List.mk_mem_zipIdx_iff_getElem?.mpr found)
  · intro entry member
    have same := List.mem_singleton.mp member
    subst entry
    exact matched.1
  · exact steps_check view levels child []
      ⟨typed, by simp [Compatible, inputNonterminal, nonterminal, ReconstructBinaryLayer.next]⟩
      ordered bounded

end Lanius.Extraction.Reconstruction.Contexts
