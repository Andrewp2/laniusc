import Lanius.Extraction.ArtifactView
import Lanius.Extraction.ParseTree

namespace Lanius.Extraction

/-- Primitive reads used by reconstruction.  The grammar-directed algorithm
below is parametric in this interface, so list and checked-tree execution share
one implementation. -/
@[ext] class ArtifactAccess where
  node? : Artifact → ParseNodeId → Option ParseNode
  token? : Artifact → TokenId → Option Token
  primarySourceRange? : Artifact → Nat → Nat → Option (List (Fin 256))

@[instance_reducible] def ArtifactAccess.canonical : ArtifactAccess where
  node? := fun artifact nodeId => artifact.parse_nodes[nodeId]?
  token? := fun artifact tokenId => artifact.tokens[tokenId]?
  primarySourceRange? := fun artifact start count => do
    let source ← artifact.sources[0]?
    let bytes ← decodeBytes source.bytes
    pure ((bytes.drop start).take count)

instance : ArtifactAccess := ArtifactAccess.canonical

@[instance_reducible] def ArtifactAccess.canonicalFor
    (artifact : Artifact) : ArtifactAccess where
  node? := fun _ nodeId => artifact.parse_nodes[nodeId]?
  token? := fun _ tokenId => artifact.tokens[tokenId]?
  primarySourceRange? := fun _ start count => do
    let source ← artifact.sources[0]?
    let bytes ← decodeBytes source.bytes
    pure ((bytes.drop start).take count)

@[instance_reducible] def ArtifactAccess.ofView {artifact : Artifact}
    (view : ArtifactView artifact) : ArtifactAccess where
  node? := fun _ nodeId => view.node? nodeId
  token? := fun _ tokenId => view.token? tokenId
  primarySourceRange? := fun _ start count => view.primarySourceRange start count

theorem ArtifactAccess.ofView_eq_canonicalFor {artifact : Artifact}
    (view : ArtifactView artifact) :
    ArtifactAccess.ofView view = ArtifactAccess.canonicalFor artifact := by
  apply ArtifactAccess.ext
  · funext _ nodeId
    exact view.node?_eq nodeId
  · funext _ tokenId
    exact view.token?_eq tokenId
  · funext _ start count
    exact view.primarySourceRange_eq start count

/-- A parse reference controls navigation, independently of token/source access.
The indexed interpretation is the specification; checked trees avoid repeated
index lookup while carrying proofs about the same artifact. -/
class ParseReference (Ref : Type) where
  id : Ref → ParseNodeId
  node? : Artifact → Ref → Option ParseNode
  child? : Artifact → Ref → Nat → Option Ref

instance ParseReference.indexed [ArtifactAccess] : ParseReference ParseNodeId where
  id := fun nodeId => nodeId
  node? := ArtifactAccess.node?
  child? := fun artifact nodeId index => do
    let child ← (← ArtifactAccess.node? artifact nodeId).children[index]?
    match child with
    | .node child => some child
    | .token _ => none

instance ParseReference.checked {nodes : List ParseNode} : ParseReference (ParseTree.Checked nodes) where
  id := fun tree => tree.val.id
  node? := fun _ tree => some tree.val.value
  child? := fun _ tree index => tree.child? index

@[simp] theorem ParseReference.indexed_id [ArtifactAccess] (nodeId : ParseNodeId) :
    ParseReference.id nodeId = nodeId := rfl

/-- Navigation agrees with the indexed interpretation for this artifact.
This is a success-only contract: no completeness claim about linking arbitrary
graphs is needed to transport a checked reconstruction result. -/
structure ParseReference.Agrees [ArtifactAccess] {Ref : Type} [ParseReference Ref]
    (artifact : Artifact) : Prop where
  node_eq : ∀ ref : Ref, ParseReference.node? artifact (ParseReference.id ref) =
    ParseReference.node? artifact ref
  child_eq : ∀ (ref : Ref) index,
    ParseReference.child? artifact (ParseReference.id ref) index =
      (ParseReference.child? artifact ref index).map ParseReference.id

theorem ParseReference.checked_agrees [ArtifactAccess] (artifact : Artifact)
    (reads : ∀ nodeId, ArtifactAccess.node? artifact nodeId = artifact.parse_nodes[nodeId]?) :
    ParseReference.Agrees (Ref := ParseTree.Checked artifact.parse_nodes) artifact := by
  constructor
  · intro ref
    change ArtifactAccess.node? artifact ref.val.id = some ref.val.value
    rw [reads]
    exact ref.property.found
  · intro ref index
    change ((ArtifactAccess.node? artifact ref.val.id).bind fun node =>
      node.children[index]?.bind fun child => match child with
        | .node id => some id
        | .token _ => none) = (ref.child? index).map (fun child => child.val.id)
    rw [reads, ref.property.found]
    exact (ref.childId index).symm

end Lanius.Extraction
