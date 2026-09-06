import Lanius.Extraction.Reconstruction.Checked
import Lanius.Extraction.ParsePostorder
namespace Lanius.Extraction.Reconstruction.Validated

/-! Validate grammar nodes while linking the postorder forest. Success certifies
both the existing node predicate and the existing Surface reconstruction. -/
def linkFrom (grammar : Grammar) (view : ParseArtifactView artifact) :
    Nat → List ParseNode → List ParseTree → Option (List ParseTree)
  | _, [], stack => some stack
  | id, value :: rest, stack => do
    let (children, stack) ← ParseTree.consumeChildren value.children stack
    let entries := children.filterMap fun child => child.map fun tree => (tree.id, tree.value)
    if ParsePostorder.node grammar view id value entries then
      linkFrom grammar view (id + 1) rest (.node id value children :: stack)
    else none


theorem linkFrom_linked (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) (nodes : List ParseNode) (stack forest : List ParseTree)
    (accepted : linkFrom grammar view id nodes stack = some forest) :
    ParseTree.linkFrom id nodes stack = some forest := by
  induction nodes generalizing id stack with
  | nil => exact accepted
  | cons value rest ih =>
    cases next : ParseTree.consumeChildren value.children stack with
    | none => simp [linkFrom, next] at accepted
    | some result =>
      rcases result with ⟨children, tail⟩
      simp only [linkFrom, next] at accepted
      change (if ParsePostorder.node grammar view id value
          (children.filterMap fun child => child.map fun tree => (tree.id, tree.value))
        then linkFrom grammar view (id + 1) rest (.node id value children :: tail)
        else none) = some forest at accepted
      split at accepted
      · simpa [ParseTree.linkFrom, next] using ih (id + 1) _ accepted
      · simp at accepted

theorem childrenEntriesValid (view : ParseArtifactView artifact)
    (slots : List ParseChild) (children : List (Option ParseTree))
    (linked : ParseTree.ChildrenValid artifact.parse_nodes slots children) :
    ParsePostorder.EntriesValid view
      (children.filterMap fun child => child.map fun tree => (tree.id, tree.value)) := by
  induction slots generalizing children with
  | nil => cases linked; simp [ParsePostorder.EntriesValid]
  | cons slot slots ih =>
    cases linked with
    | token linked => simpa using ih _ linked
    | node same valid linked =>
      intro entry member
      simp only [List.filterMap_cons, Option.map_some, List.mem_cons] at member
      rcases member with rfl | member
      · simpa [ArtifactView.node?_eq] using valid.found
      · exact ih _ linked entry member

theorem linkFrom_nodes (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) (remaining : List ParseNode) (stack forest : List ParseTree)
    (remainingValid : ∀ offset value, remaining[offset]? = some value →
      artifact.parse_nodes[id + offset]? = some value)
    (stackValid : ParseTree.ForestValid artifact.parse_nodes stack)
    (accepted : linkFrom grammar view id remaining stack = some forest) :
    checkNodesFromParseView grammar artifact view id remaining = true := by
  induction remaining generalizing id stack with
  | nil => rfl
  | cons value rest ih =>
    cases next : ParseTree.consumeChildren value.children stack with
    | none => simp [linkFrom, next] at accepted
    | some result =>
      rcases result with ⟨children, tail⟩
      obtain ⟨linked, tailValid⟩ := ParseTree.consume_sound artifact.parse_nodes
        value.children stack children tail stackValid next
      simp only [linkFrom, next] at accepted
      change (if ParsePostorder.node grammar view id value
          (children.filterMap fun child => child.map fun tree => (tree.id, tree.value))
        then linkFrom grammar view (id + 1) rest (.node id value children :: tail)
        else none) = some forest at accepted
      split at accepted
      · rename_i nodeAccepted
        simp only [checkNodesFromParseView, Bool.and_eq_true]
        refine ⟨ParsePostorder.node_sound grammar view id value _
          (childrenEntriesValid view value.children children linked) nodeAccepted, ?_⟩
        apply ih (id + 1) (.node id value children :: tail)
        · intro offset child found
          have found' := remainingValid (offset + 1) child (by simpa using found)
          simpa [Nat.add_assoc, Nat.add_comm 1] using found'
        · intro entry member
          rcases List.mem_cons.mp member with rfl | member
          · exact .node (by simpa using remainingValid 0 value (by simp)) linked
          · exact tailValid entry member
        · exact accepted
      · simp at accepted
def checkedForest (grammar : Grammar) (view : ParseArtifactView artifact) :
    Option (List (ParseTree.Checked artifact.parse_nodes)) :=
  match accepted : linkFrom grammar view 0 artifact.parse_nodes [] with
  | none => none
  | some forest => some (forest.attach.map fun tree =>
    ⟨tree.val, ParseTree.link_sound artifact.parse_nodes forest
      (linkFrom_linked grammar view 0 artifact.parse_nodes [] forest accepted)
      tree.val tree.property⟩)

def checkedView (grammar : Grammar) (view : ParseArtifactView artifact) : Option SurfaceFile :=
  letI := ArtifactAccess.ofView view.artifactView
  do
    let forest ← checkedForest grammar view
    let rootId ← artifact.parse_root
    let root ← forest.find? (fun tree => tree.val.id == rootId)
    let (surface, _) ← (reconstructFile (view.artifactView.nodeCount + 1) artifact root).run 0
    pure surface

theorem checkedView_sound (grammar : Grammar) (view : ParseArtifactView artifact)
    (surface : SurfaceFile) (accepted : checkedView grammar view = some surface) :
    checkNodesFromParseView grammar artifact view 0 artifact.parse_nodes = true ∧
      reconstructArtifactSurfaceView artifact view.artifactView = some surface := by
  cases found : linkFrom grammar view 0 artifact.parse_nodes [] with
  | none =>
    have absent : checkedForest grammar view = none := by
      unfold checkedForest
      split <;> simp_all
    simp [checkedView, absent] at accepted
  | some forest =>
    have same : checkedForest grammar view = ParseTree.checkedForest artifact.parse_nodes := by
      have original : ParseTree.link artifact.parse_nodes = some forest :=
        linkFrom_linked grammar view 0 artifact.parse_nodes [] forest found
      unfold checkedForest ParseTree.checkedForest
      split <;> split <;> simp_all
      subst_vars
      rfl
    constructor
    · exact linkFrom_nodes grammar view 0 artifact.parse_nodes [] forest
        (fun offset value h => by simpa using h) (by simp [ParseTree.ForestValid]) found
    · apply Reconstruction.checkedView_sound view.artifactView
      simpa only [checkedView, Reconstruction.checkedView, Reconstruction.checkedRoot,
        same, bind_assoc] using accepted

end Lanius.Extraction.Reconstruction.Validated
