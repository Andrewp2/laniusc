import Lanius.Extraction.Reconstruction.Contexts

namespace Lanius.Extraction.Reconstruction.Plan

deriving instance Lean.ToExpr for ReconstructBinaryLayer

/-- Untrusted hints over the original postorder input, not replacement nodes. -/
inductive Segment where
  | ordinary (count : Nat)
  | context (layers : List ReconstructBinaryLayer)
deriving Lean.ToExpr

/-- Consume a bounded ordinary range without constructing or rescanning a prefix. -/
def ordinary (view : ParseArtifactView artifact) (lookup : Nat → Option Production) :
    Nat → Nat → List ParseNode → List ParseTree → Option (Nat × List ParseNode × List ParseTree)
  | 0, id, nodes, stack => some (id, nodes, stack)
  | _ + 1, id, [], stack => some (id, [], stack)
  | count + 1, id, value :: rest, stack => do
    let (children, stack) ← ParseTree.consumeChildren value.children stack
    let entries := children.filterMap fun child => child.map fun tree => (tree.id, tree.value)
    if ParsePostorder.nodeWithLookup laniusGrammar view lookup id value entries then
      ordinary view lookup count (id + 1) rest (.node id value children :: stack)
    else none

theorem ordinary_sound (view : ParseArtifactView artifact) (lookup : Nat → Option Production)
    (count id : Nat) (nodes : List ParseNode) (stack : List ParseTree)
    (result : Nat × List ParseNode × List ParseTree)
    (accepted : ordinary view lookup count id nodes stack = some result) :
    Validated.linkFrom laniusGrammar view lookup id nodes stack =
      Validated.linkFrom laniusGrammar view lookup result.1 result.2.1 result.2.2 := by
  induction count generalizing id nodes stack with
  | zero => cases Option.some.inj accepted; rfl
  | succ count ih =>
    cases nodes with
    | nil => cases Option.some.inj accepted; rfl
    | cons node rest =>
      cases consumed : ParseTree.consumeChildren node.children stack with
      | none => simp [ordinary, consumed] at accepted
      | some pair =>
        rcases pair with ⟨children, tail⟩
        simp only [ordinary, consumed] at accepted
        change (if ParsePostorder.nodeWithLookup laniusGrammar view lookup id node
            (children.filterMap fun child => child.map fun tree => (tree.id, tree.value)) then
          ordinary view lookup count (id + 1) rest (.node id node children :: tail)
          else none) = some result at accepted
        split at accepted
        · rename_i valid
          simpa [Validated.linkFrom, consumed, valid] using ih _ _ _ accepted
        · simp at accepted

/-- Authenticate each context pair as it is consumed, keeping the real child. -/
def context : List ReconstructBinaryLayer → ParseTree → List ParseNode →
    Option (ParseTree × List ParseNode)
  | [], child, remaining => some (child, remaining)
  | layer :: rest, child, empty :: head :: remaining =>
    if child.value.nonterminal == Contexts.inputNonterminal layer &&
        empty == Contexts.emptyNode layer child && head == Contexts.binaryNode layer child then
      context rest (Contexts.binary layer child) remaining
    else none
  | _ :: _, _, _ => none

theorem context_sound (view : ParseArtifactView artifact) (layers : List ReconstructBinaryLayer)
    (child : ParseTree) (nodes : List ParseNode) (stack : List ParseTree)
    (result : ParseTree × List ParseNode)
    (ordered : child.value.position_start ≤ child.value.position_end)
    (bounded : child.value.position_end ≤ view.semanticKinds.size * 2)
    (accepted : context layers child nodes = some result) :
    Validated.linkFrom laniusGrammar view laniusGrammar.production? (child.id + 1) nodes (child :: stack) =
      Validated.linkFrom laniusGrammar view laniusGrammar.production?
        (result.1.id + 1) result.2 (result.1 :: stack) := by
  induction layers generalizing child nodes with
  | nil => cases Option.some.inj accepted; rfl
  | cons layer layers ih =>
    cases nodes with
    | nil => simp [context] at accepted
    | cons empty nodes =>
      cases nodes with
      | nil => simp [context] at accepted
      | cons head rest =>
        simp only [context] at accepted
        split at accepted
        · rename_i matched
          simp only [Bool.and_eq_true, beq_iff_eq] at matched
          obtain ⟨⟨typed, rfl⟩, rfl⟩ := matched
          change Validated.linkFrom _ _ _ _
            ([Contexts.emptyNode layer child, Contexts.binaryNode layer child] ++ rest) _ = _
          rw [Contexts.link_append, Contexts.binary_link view layer child stack typed ordered bounded]
          exact ih (Contexts.binary layer child) rest ordered bounded accepted
        · simp at accepted

def run (view : ParseArtifactView artifact) (lookup : Nat → Option Production) :
    List Segment → Nat → List ParseNode → List ParseTree → Option (List ParseTree)
  | [], _, remaining, stack => if remaining.isEmpty then some stack else none
  | .ordinary count :: plan, id, remaining, stack => do
    let (nextId, remaining, stack) ← ordinary view lookup count id remaining stack
    run view lookup plan nextId remaining stack
  | .context _ :: _, _, _, [] => none
  | .context layers :: plan, id, remaining, child :: stack =>
    if id == child.id + 1 &&
        decide (child.value.position_start ≤ child.value.position_end ∧
          child.value.position_end ≤ view.semanticKinds.size * 2) then do
      let (root, remaining) ← context layers child remaining
      run view lookup plan (root.id + 1) remaining (root :: stack)
    else none

/-- No successful plan can omit, reorder, or change input nodes. Its exact
forest is also the result of the original grammar-checking linker. -/
theorem run_sound (view : ParseArtifactView artifact) (lookup : Nat → Option Production)
    (lookup_eq : lookup = laniusGrammar.production?) (plan : List Segment)
    (id : Nat) (remaining : List ParseNode) (stack forest : List ParseTree)
    (accepted : run view lookup plan id remaining stack = some forest) :
    Validated.linkFrom laniusGrammar view lookup id remaining stack = some forest := by
  subst lookup
  induction plan generalizing id remaining stack with
  | nil =>
    cases remaining <;> simpa [run, Validated.linkFrom] using accepted
  | cons segment plan ih =>
    cases segment with
    | ordinary count =>
      cases linked : ordinary view laniusGrammar.production? count id remaining stack with
      | none => simp [run, linked] at accepted
      | some next =>
        rw [ordinary_sound view laniusGrammar.production? count id remaining stack next linked]
        exact ih _ _ _ (by simpa [run, linked] using accepted)
    | context layers =>
      cases stack with
      | nil => simp [run] at accepted
      | cons child stack =>
        simp only [run] at accepted
        split at accepted
        · rename_i valid
          simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at valid
          obtain ⟨sameId, ordered, bounded⟩ := valid
          subst id
          cases consumed : context layers child remaining with
          | none => simp [consumed] at accepted
          | some next =>
            rw [context_sound view layers child remaining stack next ordered bounded consumed]
            exact ih _ _ _ (by simpa [consumed] using accepted)
        · simp at accepted

def checkedForest (view : ParseArtifactView artifact) (lookup : Nat → Option Production)
    (lookup_eq : lookup = laniusGrammar.production?) (plan : List Segment) :
    Option (List (ParseTree.Checked artifact.parse_nodes)) :=
  match accepted : run view lookup plan 0 artifact.parse_nodes [] with
  | none => none
  | some forest => some (forest.attach.map fun tree =>
    ⟨tree.val, ParseTree.link_sound artifact.parse_nodes forest
      (Validated.linkFrom_linked laniusGrammar view lookup 0 artifact.parse_nodes [] forest
        (run_sound view lookup lookup_eq plan 0 artifact.parse_nodes [] forest accepted))
      tree.val tree.property⟩)

def checkedView (view : ParseArtifactView artifact) (lookup : Nat → Option Production)
    (lookup_eq : lookup = laniusGrammar.production?) (plan : List Segment) : Option SurfaceFile :=
  letI := ArtifactAccess.ofView view.artifactView
  do
    let forest ← checkedForest view lookup lookup_eq plan
    let rootId ← artifact.parse_root
    let root ← forest.find? (fun tree => tree.val.id == rootId)
    let (surface, _) ← (reconstructFile (view.artifactView.nodeCount + 1) artifact root).run 0
    pure surface

theorem checkedView_sound (view : ParseArtifactView artifact) (lookup : Nat → Option Production)
    (lookup_eq : lookup = laniusGrammar.production?) (plan : List Segment)
    (surface : SurfaceFile) (accepted : checkedView view lookup lookup_eq plan = some surface) :
    Validated.checkedView laniusGrammar view lookup = some surface := by
  subst lookup
  cases found : run view laniusGrammar.production? plan 0 artifact.parse_nodes [] with
  | none =>
    have absent : checkedForest view laniusGrammar.production? rfl plan = none := by
      unfold checkedForest
      split <;> simp_all
    simp [checkedView, absent] at accepted
  | some forest =>
    have linked := run_sound view laniusGrammar.production? rfl plan 0 artifact.parse_nodes [] forest found
    have same : checkedForest view laniusGrammar.production? rfl plan =
        Validated.checkedForest laniusGrammar view laniusGrammar.production? := by
      unfold checkedForest Validated.checkedForest
      split <;> split <;> simp_all
      subst_vars
      rfl
    simpa only [checkedView, Validated.checkedView, same] using accepted

/-- Proposal only: the kernel checks the plan against the original node list. -/
partial def propose (input : List ParseNode) (minimum : Nat) : List Segment := Id.run do
  let table := input.toArray
  let mut cursor := 0
  let mut ordinary := 0
  let mut result := []
  while cursor < table.size do
    let mut layers := []
    let mut next := cursor
    if cursor > 0 then
      let mut child := ParseTree.node (cursor - 1) (table[cursor - 1]?.getD ⟨0, 0, 0, 0, []⟩) []
      for layer in Contexts.levels do
        if child.value.nonterminal == Contexts.inputNonterminal layer &&
            table[next]? == some (Contexts.emptyNode layer child) &&
            table[next + 1]? == some (Contexts.binaryNode layer child) then
          layers := layer :: layers
          next := next + 2
          child := Contexts.binary layer child
    if layers.length ≥ minimum && !layers.isEmpty then
      if ordinary > 0 then result := .ordinary ordinary :: result
      result := .context layers.reverse :: result
      ordinary := 0
      cursor := next
    else
      ordinary := ordinary + 1
      cursor := cursor + 1
  if ordinary > 0 then result := .ordinary ordinary :: result
  return result.reverse


end Lanius.Extraction.Reconstruction.Plan
