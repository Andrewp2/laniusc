import Lanius.Extraction.SurfaceChecker

namespace Lanius.Extraction

/-! ## Provenance-producing reconstruction

The reconstruction result below carries compact paths from each semantic
owner to the parse node or token from which it was reconstructed.  Parent
tables are only an untrusted path-generation aid.  Authority comes from
checking every child slot in the resulting paths against `ArtifactView`.
-/

structure ParseNodePath where
  root : ParseNodeId
  edges : List Nat
  target : ParseNodeId
deriving BEq, Repr, Lean.ToExpr

structure ParseTokenPath where
  nodePath : ParseNodePath
  childSlot : Nat
  token : TokenId
deriving BEq, Repr, Lean.ToExpr

/-- Optional untrusted parent tables used only to generate candidate paths.
The generated paths carry no authority until `ParseNodePath.valid` or
`ParseTokenPath.valid` checks every direct edge. -/
structure OriginPathParents where
  nodeParents : Lanius.Data.SeqTree (Option ParseNodeId)
  tokenParents : Lanius.Data.SeqTree (Option ParseNodeId)
deriving Repr, Lean.ToExpr

theorem ParseNodeContainsTokenEvidence.ofNode
    {nodes : List ParseNode} {ancestor owner : ParseNodeId} {token : TokenId}
    (upper : ParseNodeContainsNodeEvidence nodes ancestor owner)
    (direct : ParseNodeContainsTokenEvidence nodes owner token) :
    ParseNodeContainsTokenEvidence nodes ancestor token := by
  induction upper with
  | refl _ => exact direct
  | nested lookup member child inductionHypothesis =>
      exact .nested lookup member (inductionHypothesis direct)

def followNodePath (view : ArtifactView artifact) :
    ParseNodeId → List Nat → Option ParseNodeId
  | current, [] => do
      let _ ← view.node? current
      pure current
  | current, childSlot :: edges => do
      let node ← view.node? current
      match node.children[childSlot]? with
      | some (.node child) => followNodePath view child edges
      | _ => none

def ParseNodePath.valid (view : ArtifactView artifact)
    (path : ParseNodePath) : Bool :=
  followNodePath view path.root path.edges == some path.target

theorem followNodePath_sound {artifact : Artifact}
    (view : ArtifactView artifact) {root target : ParseNodeId} {edges : List Nat}
    (accepted : followNodePath view root edges = some target) :
    ParseNodeContainsNodeEvidence artifact.parse_nodes root target := by
  induction edges generalizing root with
  | nil =>
      unfold followNodePath at accepted
      cases found : view.node? root with
      | none => simp [found] at accepted
      | some node =>
          simp [found] at accepted
          subst target
          exact .refl (by simpa [view.node?_eq] using found)
  | cons childSlot edges inductionHypothesis =>
      unfold followNodePath at accepted
      cases found : view.node? root with
      | none => simp [found] at accepted
      | some node =>
          cases childFound : node.children[childSlot]? with
          | none => simp [found, childFound] at accepted
          | some child =>
              cases child with
              | token token => simp [found, childFound] at accepted
              | node child =>
                  exact .nested (by simpa [view.node?_eq] using found)
                    (List.mem_of_getElem? childFound)
                    (inductionHypothesis
                      (by simpa [found, childFound] using accepted))

theorem ParseNodePath.valid_sound {artifact : Artifact}
    (view : ArtifactView artifact) {path : ParseNodePath}
    (accepted : path.valid view = true) :
    ParseNodeContainsNodeEvidence artifact.parse_nodes path.root path.target := by
  apply followNodePath_sound view
  exact eq_of_beq accepted

def ParseTokenPath.valid (view : ArtifactView artifact)
    (path : ParseTokenPath) : Bool :=
  path.nodePath.valid view &&
    match view.node? path.nodePath.target with
    | some node => node.children[path.childSlot]? == some (.token path.token)
    | none => false

theorem ParseTokenPath.valid_sound {artifact : Artifact}
    (view : ArtifactView artifact) {path : ParseTokenPath}
    (accepted : path.valid view = true) :
    ParseNodeContainsTokenEvidence artifact.parse_nodes
      path.nodePath.root path.token := by
  simp only [ParseTokenPath.valid, Bool.and_eq_true] at accepted
  have upper := path.nodePath.valid_sound view accepted.1
  cases found : view.node? path.nodePath.target with
  | none => simp [found] at accepted
  | some node =>
      have childFound : node.children[path.childSlot]? =
          some (.token path.token) := by
        exact eq_of_beq (by simpa [found] using accepted.2)
      exact ParseNodeContainsTokenEvidence.ofNode upper (.direct
        (by simpa [view.node?_eq] using found)
        (List.mem_of_getElem? childFound))

def findNodeChildSlot : List ParseChild → ParseNodeId → Nat → Option Nat
  | [], _, _ => none
  | .node child :: rest, target, slot =>
      if child = target then some slot
      else findNodeChildSlot rest target (slot + 1)
  | .token _ :: rest, target, slot =>
      findNodeChildSlot rest target (slot + 1)

def findTokenChildSlot : List ParseChild → TokenId → Nat → Option Nat
  | [], _, _ => none
  | .token child :: rest, target, slot =>
      if child = target then some slot
      else findTokenChildSlot rest target (slot + 1)
  | .node _ :: rest, target, slot =>
      findTokenChildSlot rest target (slot + 1)

def buildNodePathEdges (view : ArtifactView artifact)
    (parents : OriginPathParents) (root : ParseNodeId) :
    Nat → ParseNodeId → List Nat → Option (List Nat)
  | 0, _, _ => none
  | fuel + 1, current, edges =>
      if current = root then some edges else do
        let some parent ← parents.nodeParents.lookup current | none
        let parentNode ← view.node? parent
        let childSlot ← findNodeChildSlot parentNode.children current 0
        buildNodePathEdges view parents root fuel parent (childSlot :: edges)

def buildNodePath (artifact : Artifact) (view : ArtifactView artifact)
    (parents : OriginPathParents) (root target : ParseNodeId) :
    Option ParseNodePath := do
  let edges ← buildNodePathEdges view parents root
    (artifact.parse_nodes.length + 1) target []
  pure { root, edges, target }

def buildTokenPath (artifact : Artifact) (view : ArtifactView artifact)
    (parents : OriginPathParents) (root : ParseNodeId) (token : TokenId) :
    Option ParseTokenPath := do
  let some directOwner ← parents.tokenParents.lookup token | none
  let ownerNode ← view.node? directOwner
  let childSlot ← findTokenChildSlot ownerNode.children token 0
  let nodePath ← buildNodePath artifact view parents root directOwner
  pure { nodePath, childSlot, token }

structure SurfaceNodeOrigin where
  claim : SurfaceNodeClaim
  path : Option ParseNodePath
deriving BEq, Repr, Lean.ToExpr

structure SurfaceSpellingOrigin where
  claim : SpellingClaim
  path : ParseTokenPath
deriving BEq, Repr, Lean.ToExpr

structure SurfaceOrigins where
  claims : SurfaceClaims
  nodePaths : List (Option ParseNodePath)
  spellingPaths : List ParseTokenPath
deriving BEq, Repr, Lean.ToExpr

def buildNodeOrigin (artifact : Artifact) (view : ArtifactView artifact)
    (parents : OriginPathParents) (claim : SurfaceNodeClaim) :
    Option SurfaceNodeOrigin :=
  match claim.containingParseNode with
  | none => some { claim, path := none }
  | some root => do
      let path ← buildNodePath artifact view parents root claim.parseNode
      pure { claim, path := some path }

def buildSpellingOrigin (artifact : Artifact) (view : ArtifactView artifact)
    (parents : OriginPathParents) (claim : SpellingClaim) :
    Option SurfaceSpellingOrigin := do
  let path ← buildTokenPath artifact view parents claim.owner claim.token
  pure { claim, path }

def buildSurfaceOrigins (artifact : Artifact) (view : ArtifactView artifact)
    (parents : OriginPathParents) (claims : SurfaceClaims) :
    Option SurfaceOrigins := do
  pure {
    claims
    nodePaths := ← claims.nodes.mapM fun claim => do
      pure (← buildNodeOrigin artifact view parents claim).path
    spellingPaths := ← claims.spellings.mapM fun claim => do
      pure (← buildSpellingOrigin artifact view parents claim).path
  }

structure ProvenanceSurfaceReconstruction where
  reconstructed : SurfaceFile
  claims : SurfaceClaims
  origins : SurfaceOrigins
deriving Repr, Lean.ToExpr

def reconstructArtifactSurfaceWithProvenanceView (artifact : Artifact)
    (view : ArtifactView artifact) (origins : SurfaceOrigins) :
    Option ProvenanceSurfaceReconstruction := do
  let reconstructed ← reconstructArtifactSurfaceView artifact view
  let claims ← collectSurfaceClaimsFrom artifact reconstructed
  pure { reconstructed, claims, origins }

theorem reconstructArtifactSurfaceWithProvenanceView_components
    {artifact : Artifact} (view : ArtifactView artifact)
    (origins : SurfaceOrigins) {result : ProvenanceSurfaceReconstruction}
    (found : reconstructArtifactSurfaceWithProvenanceView artifact view origins =
      some result) :
    reconstructArtifactSurfaceView artifact view = some result.reconstructed ∧
      collectSurfaceClaimsFrom artifact result.reconstructed = some result.claims ∧
      result.origins = origins := by
  cases reconstructedFound : reconstructArtifactSurfaceView artifact view with
  | none =>
      simp [reconstructArtifactSurfaceWithProvenanceView,
        reconstructedFound] at found
  | some reconstructed =>
      cases claimsFound : collectSurfaceClaimsFrom artifact reconstructed with
      | none =>
          simp [reconstructArtifactSurfaceWithProvenanceView,
            reconstructedFound, claimsFound] at found
      | some claims =>
          simp [reconstructArtifactSurfaceWithProvenanceView,
            reconstructedFound, claimsFound] at found
          subst result
          exact ⟨by simp_all, by simp_all, rfl⟩

theorem reconstructArtifactSurfaceWithProvenanceView_of_components
    {artifact : Artifact} (view : ArtifactView artifact)
    (origins : SurfaceOrigins) (reconstructed : SurfaceFile)
    (claims : SurfaceClaims)
    (reconstructedFound : reconstructArtifactSurfaceView artifact view =
      some reconstructed)
    (claimsFound : collectSurfaceClaimsFrom artifact reconstructed = some claims) :
    reconstructArtifactSurfaceWithProvenanceView artifact view origins =
      some { reconstructed, claims, origins } := by
  simp [reconstructArtifactSurfaceWithProvenanceView, reconstructedFound,
    claimsFound]

def SurfaceNodeOrigin.valid (artifact : Artifact)
    (view : ArtifactView artifact) (origin : SurfaceNodeOrigin) : Bool :=
  match view.node? origin.claim.parseNode with
  | none => false
  | some node =>
      origin.claim.allowedProductions.contains node.production &&
        match origin.claim.containingParseNode, origin.path with
        | none, none => true
        | some root, some path =>
            path.root == root && path.target == origin.claim.parseNode &&
              path.valid view
        | _, _ => false

theorem SurfaceNodeOrigin.valid_sound {artifact : Artifact}
    (view : ArtifactView artifact) {origin : SurfaceNodeOrigin}
    (accepted : origin.valid artifact view = true) :
    SurfaceNodeClaimMatches artifact origin.claim := by
  unfold SurfaceNodeOrigin.valid at accepted
  cases found : view.node? origin.claim.parseNode with
  | none => simp [found] at accepted
  | some node =>
      simp only [found, Bool.and_eq_true] at accepted
      refine ⟨node, by simpa [view.node?_eq] using found, ?_, ?_⟩
      · exact of_decide_eq_true
          (by simpa only [List.contains_eq_mem] using accepted.1)
      · cases container : origin.claim.containingParseNode with
        | none => trivial
        | some root =>
            cases pathFound : origin.path with
            | none => simp [container, pathFound] at accepted
            | some path =>
                simp only [container, pathFound, Bool.and_eq_true] at accepted
                have rootEqual : path.root = root := eq_of_beq accepted.2.1.1
                have targetEqual : path.target = origin.claim.parseNode :=
                  eq_of_beq accepted.2.1.2
                have evidence := path.valid_sound view accepted.2.2
                simpa [rootEqual, targetEqual] using evidence

def SurfaceSpellingOrigin.valid (artifact : Artifact)
    (view : ArtifactView artifact) (origin : SurfaceSpellingOrigin) : Bool :=
  tokenTextEqWithView artifact view origin.claim.token origin.claim.text &&
    origin.path.nodePath.root == origin.claim.owner &&
    origin.path.token == origin.claim.token && origin.path.valid view

theorem SurfaceSpellingOrigin.valid_sound {artifact : Artifact}
    (view : ArtifactView artifact) {origin : SurfaceSpellingOrigin}
    (accepted : origin.valid artifact view = true) :
    SpellingClaimMatches artifact origin.claim := by
  simp only [SurfaceSpellingOrigin.valid, Bool.and_eq_true] at accepted
  have exactView := tokenTextEqWithView_sound view accepted.1.1.1
  rw [tokenTextWithView_eq] at exactView
  have rootEqual : origin.path.nodePath.root = origin.claim.owner :=
    eq_of_beq accepted.1.1.2
  have tokenEqual : origin.path.token = origin.claim.token :=
    eq_of_beq accepted.1.2
  have contained := origin.path.valid_sound view accepted.2
  exact {
    exactText := exactView
    contained := by simpa [rootEqual, tokenEqual] using contained
  }

def nodeOriginPathsValid (artifact : Artifact) (view : ArtifactView artifact) :
    List SurfaceNodeClaim → List (Option ParseNodePath) → Bool
  | [], [] => true
  | claim :: claims, path :: paths =>
      SurfaceNodeOrigin.valid artifact view { claim, path } &&
        nodeOriginPathsValid artifact view claims paths
  | _, _ => false

theorem nodeOriginPathsValid_append (artifact : Artifact)
    (view : ArtifactView artifact) (leftClaims rightClaims : List SurfaceNodeClaim)
    (leftPaths rightPaths : List (Option ParseNodePath))
    (sameLength : leftClaims.length = leftPaths.length) :
    nodeOriginPathsValid artifact view (leftClaims ++ rightClaims)
        (leftPaths ++ rightPaths) =
      (nodeOriginPathsValid artifact view leftClaims leftPaths &&
        nodeOriginPathsValid artifact view rightClaims rightPaths) := by
  induction leftClaims generalizing leftPaths with
  | nil =>
      have : leftPaths = [] := List.eq_nil_of_length_eq_zero sameLength.symm
      subst leftPaths
      rfl
  | cons claim claims inductionHypothesis =>
      cases leftPaths with
      | nil => simp at sameLength
      | cons path paths =>
          simp only [List.length_cons] at sameLength
          have tailLength : claims.length = paths.length :=
            Nat.add_right_cancel sameLength
          simp only [List.cons_append, nodeOriginPathsValid]
          rw [inductionHypothesis paths tailLength]
          cases SurfaceNodeOrigin.valid artifact view { claim, path } <;>
            simp

theorem nodeOriginPathsValid_sound {artifact : Artifact}
    (view : ArtifactView artifact) {claims : List SurfaceNodeClaim}
    {paths : List (Option ParseNodePath)}
    (accepted : nodeOriginPathsValid artifact view claims paths = true)
    {claim : SurfaceNodeClaim} (member : claim ∈ claims) :
    SurfaceNodeClaimMatches artifact claim := by
  induction claims generalizing paths with
  | nil => simp at member
  | cons head tail inductionHypothesis =>
      cases paths with
      | nil => simp [nodeOriginPathsValid] at accepted
      | cons path paths =>
          simp only [nodeOriginPathsValid, Bool.and_eq_true] at accepted
          simp only [List.mem_cons] at member
          rcases member with same | member
          · subst claim
            exact SurfaceNodeOrigin.valid_sound view accepted.1
          · exact inductionHypothesis accepted.2 member

def spellingOriginPathsValid (artifact : Artifact)
    (view : ArtifactView artifact) :
    List SpellingClaim → List ParseTokenPath → Bool
  | [], [] => true
  | claim :: claims, path :: paths =>
      SurfaceSpellingOrigin.valid artifact view { claim, path } &&
        spellingOriginPathsValid artifact view claims paths
  | _, _ => false

theorem spellingOriginPathsValid_sound {artifact : Artifact}
    (view : ArtifactView artifact) {claims : List SpellingClaim}
    {paths : List ParseTokenPath}
    (accepted : spellingOriginPathsValid artifact view claims paths = true)
    {claim : SpellingClaim} (member : claim ∈ claims) :
    SpellingClaimMatches artifact claim := by
  induction claims generalizing paths with
  | nil => simp at member
  | cons head tail inductionHypothesis =>
      cases paths with
      | nil => simp [spellingOriginPathsValid] at accepted
      | cons path paths =>
          simp only [spellingOriginPathsValid, Bool.and_eq_true] at accepted
          simp only [List.mem_cons] at member
          rcases member with same | member
          · subst claim
            exact SurfaceSpellingOrigin.valid_sound view accepted.1
          · exact inductionHypothesis accepted.2 member

def SurfaceOrigins.valid (artifact : Artifact) (view : ArtifactView artifact)
    (origins : SurfaceOrigins) : Bool :=
  origins.claims.nodes.map (·.id) ==
      List.range origins.claims.nodes.length &&
  nodeOriginPathsValid artifact view origins.claims.nodes origins.nodePaths &&
  spellingOriginPathsValid artifact view origins.claims.spellings
    origins.spellingPaths &&
  spellingCoverageValid artifact origins.claims

theorem SurfaceOrigins.valid_of_components {artifact : Artifact}
    (view : ArtifactView artifact) (origins : SurfaceOrigins)
    (idsDense : origins.claims.nodes.map (·.id) ==
      List.range origins.claims.nodes.length)
    (nodesChecked : nodeOriginPathsValid artifact view origins.claims.nodes
      origins.nodePaths = true)
    (spellingsChecked : spellingOriginPathsValid artifact view
      origins.claims.spellings origins.spellingPaths = true)
    (coverageChecked : spellingCoverageValid artifact origins.claims = true) :
    origins.valid artifact view = true := by
  simp [SurfaceOrigins.valid, idsDense, nodesChecked, spellingsChecked,
    coverageChecked]

theorem SurfaceOrigins.valid_sound {artifact : Artifact}
    (view : ArtifactView artifact) {origins : SurfaceOrigins}
    (accepted : origins.valid artifact view = true) :
    SurfaceClaimsMatch artifact origins.claims := by
  simp only [SurfaceOrigins.valid, Bool.and_eq_true] at accepted
  rcases accepted with ⟨⟨⟨denseIds, nodesAccepted⟩, spellingsAccepted⟩,
    spellingCoverage⟩
  exact {
    denseIds := eq_of_beq denseIds
    nodes := fun _ member => nodeOriginPathsValid_sound view nodesAccepted member
    spellings := fun _ member =>
      spellingOriginPathsValid_sound view spellingsAccepted member
    spellingCoverage := spellingCoverage
  }

def ProvenanceSurfaceReconstruction.valid (artifact : Artifact)
    (view : ArtifactView artifact)
    (result : ProvenanceSurfaceReconstruction) : Bool :=
  decide (result.origins.claims = result.claims) &&
    result.origins.valid artifact view

theorem ProvenanceSurfaceReconstruction.valid_sound {artifact : Artifact}
    (view : ArtifactView artifact) {result : ProvenanceSurfaceReconstruction}
    (accepted : result.valid artifact view = true) :
    SurfaceClaimsMatch artifact result.claims := by
  simp only [ProvenanceSurfaceReconstruction.valid, Bool.and_eq_true] at accepted
  have claimsEqual : result.origins.claims = result.claims :=
    of_decide_eq_true accepted.1
  rw [← claimsEqual]
  exact result.origins.valid_sound view accepted.2

end Lanius.Extraction
