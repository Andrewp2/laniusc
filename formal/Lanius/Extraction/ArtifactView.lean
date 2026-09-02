import Lanius.Data.SeqTree
import Lanius.Extraction.TokenChecker

namespace Lanius.Extraction

open Lanius.Data

/-! ## Untrusted cache and checked view boundary

`Artifact` remains the canonical, serialized semantic input.  `ArtifactCache`
is an optional sidecar and carries no authority.  An `ArtifactView` can be
constructed only after the sidecar has been related to the artifact and its
sequence invariants have been established.
-/

structure ArtifactCache where
  leafCapacity : Nat
  parseNodes : SeqTree ParseNode
  tokens : SeqTree Token
  /-- Decoded bytes for the primary source.  The current extraction format
  checks token spellings only in source file zero. -/
  primarySourceBytes : SeqTree (Fin 256)
deriving Repr, Lean.ToExpr

def ArtifactCache.matches (cache : ArtifactCache) (artifact : Artifact) : Bool :=
  cache.parseNodes.wellFormed cache.leafCapacity &&
  cache.parseNodes.flatten == artifact.parse_nodes &&
  cache.tokens.wellFormed cache.leafCapacity &&
  cache.tokens.flatten == artifact.tokens &&
  cache.primarySourceBytes.wellFormed cache.leafCapacity &&
  match artifact.sources[0]? with
  | none => cache.primarySourceBytes.flatten.isEmpty
  | some source =>
      decodeBytes source.bytes == some cache.primarySourceBytes.flatten

structure ArtifactView (artifact : Artifact) where
  cache : ArtifactCache
  parseNodesWellFormed : cache.parseNodes.WellFormed cache.leafCapacity
  parseNodesRepresent : cache.parseNodes.Represents artifact.parse_nodes
  tokensWellFormed : cache.tokens.WellFormed cache.leafCapacity
  tokensRepresent : cache.tokens.Represents artifact.tokens
  sourceBytesWellFormed :
    cache.primarySourceBytes.WellFormed cache.leafCapacity
  sourceBytesRepresent : ∀ source, artifact.sources[0]? = some source →
    decodeBytes source.bytes = some cache.primarySourceBytes.flatten

def ArtifactCache.ofMatches {cache : ArtifactCache} {artifact : Artifact}
    (accepted : cache.matches artifact = true) : ArtifactView artifact := by
  refine {
    cache
    parseNodesWellFormed := SeqTree.wellFormed_sound ?_
    parseNodesRepresent := eq_of_beq ?_
    tokensWellFormed := SeqTree.wellFormed_sound ?_
    tokensRepresent := eq_of_beq ?_
    sourceBytesWellFormed := SeqTree.wellFormed_sound ?_
    sourceBytesRepresent := ?_
  }
  · unfold ArtifactCache.matches at accepted
    simp only [Bool.and_eq_true] at accepted
    exact accepted.1.1.1.1.1
  · unfold ArtifactCache.matches at accepted
    simp only [Bool.and_eq_true] at accepted
    exact accepted.1.1.1.1.2
  · unfold ArtifactCache.matches at accepted
    simp only [Bool.and_eq_true] at accepted
    exact accepted.1.1.1.2
  · unfold ArtifactCache.matches at accepted
    simp only [Bool.and_eq_true] at accepted
    exact accepted.1.1.2
  · unfold ArtifactCache.matches at accepted
    simp only [Bool.and_eq_true] at accepted
    exact accepted.1.2
  · intro source sourceFound
    unfold ArtifactCache.matches at accepted
    simp only [Bool.and_eq_true] at accepted
    have sourceMatch := accepted.2
    simp only [sourceFound] at sourceMatch
    exact eq_of_beq sourceMatch

def ArtifactCache.checked? (cache : ArtifactCache) (artifact : Artifact) :
    Option (ArtifactView artifact) :=
  if accepted : cache.matches artifact = true then
    some (cache.ofMatches accepted)
  else none

def ArtifactView.node? (view : ArtifactView artifact)
    (nodeId : ParseNodeId) : Option ParseNode :=
  view.cache.parseNodes.lookup nodeId

theorem ArtifactView.node?_eq (view : ArtifactView artifact)
    (nodeId : ParseNodeId) :
    view.node? nodeId = artifact.parse_nodes[nodeId]? := by
  unfold ArtifactView.node?
  rw [SeqTree.lookup_eq_flatten view.cache.parseNodes
    view.parseNodesWellFormed, view.parseNodesRepresent]

def ArtifactView.token? (view : ArtifactView artifact)
    (tokenId : TokenId) : Option Token :=
  view.cache.tokens.lookup tokenId

theorem ArtifactView.token?_eq (view : ArtifactView artifact)
    (tokenId : TokenId) :
    view.token? tokenId = artifact.tokens[tokenId]? := by
  unfold ArtifactView.token?
  rw [SeqTree.lookup_eq_flatten view.cache.tokens view.tokensWellFormed,
    view.tokensRepresent]

def ArtifactView.primarySourceRange (view : ArtifactView artifact)
    (start count : Nat) : Option (List (Fin 256)) := do
  let _source ← artifact.sources[0]?
  pure (view.cache.primarySourceBytes.rangeToList start count)

theorem ArtifactView.primarySourceRange_eq (view : ArtifactView artifact)
    (start count : Nat) :
    view.primarySourceRange start count = (do
      let source ← artifact.sources[0]?
      let bytes ← decodeBytes source.bytes
      pure ((bytes.drop start).take count)) := by
  cases sourceFound : artifact.sources[0]? with
  | none => simp [ArtifactView.primarySourceRange, sourceFound]
  | some source =>
      rw [ArtifactView.primarySourceRange, sourceFound]
      simp only [Option.bind_eq_bind, Option.bind_some]
      rw [view.sourceBytesRepresent source sourceFound]
      simp [SeqTree.rangeToList_eq_flatten view.cache.primarySourceBytes
        view.sourceBytesWellFormed]

def ArtifactCache.ofArtifact (artifact : Artifact) : ArtifactCache :=
  let sourceBytes := match artifact.sources[0]? with
    | none => []
    | some source => (decodeBytes source.bytes).getD []
  let capacity := Nat.max artifact.parse_nodes.length
    (Nat.max artifact.tokens.length sourceBytes.length)
  {
    leafCapacity := capacity
    parseNodes := .leaf artifact.parse_nodes
    tokens := .leaf artifact.tokens
    primarySourceBytes := .leaf sourceBytes
  }

/-- The reference backend.  It is checked through the exact same boundary as
optimized sidecars, which keeps malformed source bytes from being hidden by a
trusted constructor. -/
def ArtifactView.canonical? (artifact : Artifact) : Option (ArtifactView artifact) :=
  (ArtifactCache.ofArtifact artifact).checked? artifact

end Lanius.Extraction
