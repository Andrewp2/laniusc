import Lanius.Extraction.SurfaceReconstructProvenance

namespace Lanius.Extraction

/-! Path witnesses certify the existing containment searches, not merely an
alternative notion of provenance. Their length and every traversed edge are
checked; parent tables used to propose paths carry no authority. -/

private def followPrunedPath (view : ArtifactView artifact) (target : Nat) :
    Nat → List Nat → Option Nat
  | current, [] => do
    let _ ← view.node? current
    pure current
  | current, slot :: edges => do
    let node ← view.node? current
    let some (.node child) := node.children[slot]? | none
    if Nat.ble target child then followPrunedPath view target child edges else none

private theorem followPrunedPath_checked (view : ArtifactView artifact)
    (target root fuel : Nat) (edges : List Nat)
    (room : edges.length < fuel)
    (accepted : followPrunedPath view target root edges = some target) :
    containsNodePruned view.node? target fuel root = true := by
  induction edges generalizing root fuel with
  | nil =>
    cases fuel with
    | zero => simp at room
    | succ fuel =>
      cases found : view.node? root with
      | none => simp [followPrunedPath, found] at accepted
      | some node =>
        have same : root = target := by simpa [followPrunedPath, found] using accepted
        subst root
        simp [containsNodePruned, found]
  | cons slot edges ih =>
    cases fuel with
    | zero => simp at room
    | succ fuel =>
      cases found : view.node? root with
      | none => simp [followPrunedPath, found] at accepted
      | some node =>
        cases childFound : node.children[slot]? with
        | none => simp [followPrunedPath, found, childFound] at accepted
        | some child =>
          cases child with
          | token token => simp [followPrunedPath, found, childFound] at accepted
          | node child =>
            simp [followPrunedPath, found, childFound] at accepted
            have tail := ih child fuel (by simpa using room) accepted.2
            simp only [containsNodePruned, found]
            split
            · rfl
            · apply List.any_eq_true.mpr
              exact ⟨.node child, List.mem_of_getElem? childFound,
                by simpa using And.intro accepted.1 tail⟩

def ParseNodePath.checkPruned (view : ArtifactView artifact) (path : ParseNodePath) : Bool :=
  Nat.ble path.edges.length view.nodeCount &&
    followPrunedPath view path.target path.root path.edges == some path.target

theorem ParseNodePath.checkPruned_sound (view : ArtifactView artifact) (path : ParseNodePath)
    (accepted : path.checkPruned view = true) :
    parseNodeContainsNodePruned artifact view path.root path.target = true := by
  simp only [checkPruned, Bool.and_eq_true, Nat.ble_eq, beq_iff_eq] at accepted
  apply followPrunedPath_checked view path.target path.root _ path.edges
  · rw [← view.nodeCount_eq]
    omega
  · exact accepted.2

private theorem followNodePath_token_checked (view : ArtifactView artifact)
    (root target token slot fuel : Nat) (edges : List Nat) (node : ParseNode)
    (room : edges.length < fuel)
    (accepted : followNodePath view root edges = some target)
    (found : view.node? target = some node)
    (direct : node.children[slot]? = some (.token token)) :
    containsToken view.node? token fuel root = true := by
  induction edges generalizing root fuel with
  | nil =>
    cases fuel with
    | zero => simp at room
    | succ fuel =>
      cases rootFound : view.node? root with
      | none => simp [followNodePath, rootFound] at accepted
      | some rootNode =>
        have same : root = target := by simpa [followNodePath, rootFound] using accepted
        subst root
        simp only [containsToken, found]
        exact List.any_eq_true.mpr ⟨.token token, List.mem_of_getElem? direct, by simp⟩
  | cons edge edges ih =>
    cases fuel with
    | zero => simp at room
    | succ fuel =>
      cases rootFound : view.node? root with
      | none => simp [followNodePath, rootFound] at accepted
      | some rootNode =>
        cases childFound : rootNode.children[edge]? with
        | none => simp [followNodePath, rootFound, childFound] at accepted
        | some child =>
          cases child with
          | token token => simp [followNodePath, rootFound, childFound] at accepted
          | node child =>
            have tail := ih child fuel (by simpa using room)
              (by simpa [followNodePath, rootFound, childFound] using accepted)
            simp only [containsToken, rootFound]
            exact List.any_eq_true.mpr ⟨.node child, List.mem_of_getElem? childFound, tail⟩

theorem ParseTokenPath.valid_checker (view : ArtifactView artifact) (path : ParseTokenPath)
    (room : path.nodePath.edges.length ≤ view.nodeCount)
    (accepted : path.valid view = true) :
    parseNodeContainsTokenView artifact view path.nodePath.root path.token = true := by
  simp only [valid, ParseNodePath.valid, Bool.and_eq_true, beq_iff_eq] at accepted
  cases found : view.node? path.nodePath.target with
  | none => simp [found] at accepted
  | some node =>
    apply followNodePath_token_checked view path.nodePath.root path.nodePath.target
      path.token path.childSlot _ path.nodePath.edges node
    · rw [← view.nodeCount_eq]
      omega
    · exact accepted.1
    · exact found
    · simpa [found] using accepted.2

private def nodeClaimViaPath (view : ArtifactView artifact) :
    SurfaceNodeClaim → Option ParseNodePath → Bool
  | ⟨_, parseNode, container, allowed⟩, path =>
    match view.node? parseNode with
    | none => false
    | some node =>
      allowed.contains node.production &&
        match container, path with
        | none, none => true
        | some root, some path =>
          path.root == root && path.target == parseNode && path.checkPruned view
        | _, _ => false

private theorem nodeClaimViaPath_sound (view : ArtifactView artifact)
    (claim : SurfaceNodeClaim) (path : Option ParseNodePath)
    (accepted : nodeClaimViaPath view claim path = true) :
    nodeClaimValidView artifact view claim = true := by
  rcases claim with ⟨id, parseNode, containing, allowed⟩
  cases found : view.node? parseNode with
  | none => simp [nodeClaimViaPath, found] at accepted
  | some node =>
    simp only [nodeClaimViaPath, nodeClaimValidView, nodeClaimValidWith, found, Bool.and_eq_true] at accepted ⊢
    refine ⟨accepted.1, ?_⟩
    cases container : containing with
    | none => simp
    | some root =>
      cases path with
      | none => simp [container] at accepted
      | some path =>
        simp only [container, Bool.and_eq_true, beq_iff_eq] at accepted
        have checked := path.checkPruned_sound view accepted.2.2
        simpa [parseNodeContainsNodePruned, accepted.2.1.1, accepted.2.1.2] using checked

private def spellingClaimViaPath (view : ArtifactView artifact) :
    SpellingClaim → ParseTokenPath → Bool
  | ⟨owner, token, text⟩, ⟨⟨root, edges, target⟩, slot, pathToken⟩ =>
    Nat.ble edges.length view.nodeCount &&
      (tokenTextEqWithView artifact view token text && root == owner &&
        pathToken == token && (ParseTokenPath.mk ⟨root, edges, target⟩ slot pathToken).valid view)

private theorem spellingClaimViaPath_sound (view : ArtifactView artifact)
    (claim : SpellingClaim) (path : ParseTokenPath)
    (accepted : spellingClaimViaPath view claim path = true) :
    spellingClaimValidView artifact view claim = true := by
  rcases claim with ⟨owner, token, text⟩
  rcases path with ⟨⟨root, edges, target⟩, slot, pathToken⟩
  simp only [spellingClaimViaPath, Bool.and_eq_true,
    Nat.ble_eq] at accepted
  have exactText := tokenTextEqWithView_sound view accepted.2.1.1.1
  have rootEq := eq_of_beq accepted.2.1.1.2
  have tokenEq := eq_of_beq accepted.2.1.2
  have contained := ParseTokenPath.valid_checker view ⟨⟨root, edges, target⟩, slot, pathToken⟩
    accepted.1 accepted.2.2
  simpa [spellingClaimValidView, exactText, rootEq, tokenEq] using contained

private theorem all_of_zip {left : List α} {right : List β}
    {check : α → β → Bool} {property : α → Bool}
    (count : left.length = right.length)
    (sound : ∀ a b, check a b = true → property a = true)
    (accepted : (left.zip right).all (fun (a, b) => check a b) = true) :
    left.all property = true := by
  rw [← List.map_fst_zip (l₁ := left) (l₂ := right) (by omega), List.all_map]
  exact List.all_eq_true.mpr fun (a, b) member =>
    sound a b (List.all_eq_true.mp accepted (a, b) member)

/-- Validate compact path witnesses and retain exactly the public claim-checker
result. Count checks prevent zip truncation from dropping any obligation. -/
def SurfaceOrigins.checkReference (view : ArtifactView artifact) (origins : SurfaceOrigins) : Bool :=
  origins.claims.nodes.map (·.id) == List.range origins.claims.nodes.length &&
  origins.claims.nodes.length == origins.nodePaths.length &&
  (origins.claims.nodes.zip origins.nodePaths).all (fun (claim, path) => nodeClaimViaPath view claim path) &&
  origins.claims.spellings.length == origins.spellingPaths.length &&
  (origins.claims.spellings.zip origins.spellingPaths).all (fun (claim, path) => spellingClaimViaPath view claim path) &&
  spellingCoverageValid artifact origins.claims

theorem SurfaceOrigins.checkReference_sound (view : ArtifactView artifact) (origins : SurfaceOrigins)
    (accepted : origins.checkReference view = true) :
    surfaceClaimsValidIndexed artifact origins.claims = true := by
  simp only [checkReference, Bool.and_eq_true] at accepted
  rcases accepted with ⟨⟨⟨⟨⟨dense, nodeCount⟩, nodes⟩, spellingCount⟩, spellings⟩, coverage⟩
  simp only [surfaceClaimsValidIndexed, nodeClaimsValidIndexed_eq view,
    spellingClaimsValidIndexed_eq view, Bool.and_eq_true]
  exact ⟨⟨⟨dense, all_of_zip (eq_of_beq nodeCount) (nodeClaimViaPath_sound view) nodes⟩,
    all_of_zip (eq_of_beq spellingCount) (spellingClaimViaPath_sound view) spellings⟩, coverage⟩

end Lanius.Extraction
