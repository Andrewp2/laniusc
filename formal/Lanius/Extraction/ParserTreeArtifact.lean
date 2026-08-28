import Lanius.Compiler.ParserTree
import Lanius.Extraction.Artifact

namespace Lanius.Extraction

open Lanius.Compiler.Parser

/-! # Canonical parser-tree artifacts

The verified recognizer materializes a representation-independent `ParseTree`.
The existing Surface reconstruction code consumes the compact postorder
`ParseNode` format exported by the production compiler. This module is the
single bridge between those representations: it assigns node IDs
deterministically, keeps terminals as token children, and emits every child
node before its parent.

No production-specific syntax knowledge belongs here. Production numbers are
interpreted only by `SurfaceReconstruct`, which remains the authoritative
grammar-directed decoder.
-/

mutual

  /-- Serialize one tree with node IDs beginning at `base`. Terminal leaves do
      not allocate parse nodes; nonterminals allocate one node after all of
      their children. -/
  def serializeParseTreeFrom (base : Nat) :
      ParseTree → List ParseNode × ParseChild
    | .terminal tokenIndex _ => ([], .token tokenIndex)
    | .nonterminal productionId nonterminal start finish children =>
        let serializedChildren := serializeParseTreesFrom base children
        let nodes := serializedChildren.1
        let childReferences := serializedChildren.2
        let nodeId := base + nodes.length
        (nodes ++ [{
          production := productionId
          nonterminal := nonterminal
          position_start := start
          position_end := finish
          children := childReferences
        }], .node nodeId)

  /-- Serialize siblings left-to-right. The base for each suffix advances by
      exactly the number of nodes emitted by the preceding sibling. -/
  def serializeParseTreesFrom (base : Nat) :
      List ParseTree → List ParseNode × List ParseChild
    | [] => ([], [])
    | tree :: trees =>
        let serializedTree := serializeParseTreeFrom base tree
        let serializedTrees := serializeParseTreesFrom
          (base + serializedTree.1.length) trees
        (serializedTree.1 ++ serializedTrees.1,
          serializedTree.2 :: serializedTrees.2)
end

/-- Canonical zero-based serialization. A terminal root has no parse-node
    root; a checked materialized parse can never take that branch. -/
def serializeParseTree (tree : ParseTree) : List ParseNode × Option ParseNodeId :=
  let serialized := serializeParseTreeFrom 0 tree
  match serialized.2 with
  | .token _ => (serialized.1, none)
  | .node root => (serialized.1, some root)

structure MaterializedParseArtifact
    (grammar : IndexedGrammar) (tokens : List Nat) where
  parse : MaterializedParse grammar tokens
  nodes : List ParseNode
  root : ParseNodeId
  serialized : serializeParseTree parse.tree = (nodes, some root)

def materializedParseNodes
    (parse : MaterializedParse grammar tokens) : List ParseNode :=
  (serializeParseTree parse.tree).1

def materializedParseRoot
    (parse : MaterializedParse grammar tokens) : ParseNodeId :=
  (serializeParseTree parse.tree).2.getD 0

/-- A checked parse always serializes to a nonterminal root. The theorem lives
    in `Prop`, so the executable artifact constructor below does not eliminate
    proof evidence to obtain data. -/
theorem materializedParse_serialization_has_root
    (parse : MaterializedParse grammar tokens) :
    serializeParseTree parse.tree =
      (materializedParseNodes parse, some (materializedParseRoot parse)) := by
  cases parse with
  | mk tree recognizes =>
      cases tree with
      | terminal tokenIndex semanticKind =>
          cases recognizes with
          | terminal tokenIndexEq kindBound scanned => omega
      | nonterminal productionId nonterminal start finish children =>
          simp [serializeParseTree, serializeParseTreeFrom,
            materializedParseNodes, materializedParseRoot]

/-- A checked parse always serializes to a nonterminal root. -/
def MaterializedParse.toArtifact
    (parse : MaterializedParse grammar tokens) :
    MaterializedParseArtifact grammar tokens := {
  parse := parse
  nodes := materializedParseNodes parse
  root := materializedParseRoot parse
  serialized := materializedParse_serialization_has_root parse
}

/-- Every serialized nonterminal root is the final node in its zero-based
    postorder array. -/
theorem serializeParseTree_root_last
    (serialized : serializeParseTree tree = (nodes, some root)) :
    root + 1 = nodes.length := by
  cases tree with
  | terminal tokenIndex semanticKind =>
      simp [serializeParseTree, serializeParseTreeFrom] at serialized
  | nonterminal productionId nonterminal start finish children =>
      simp [serializeParseTree, serializeParseTreeFrom] at serialized
      rcases serialized with ⟨rfl, rfl⟩
      simp

theorem MaterializedParseArtifact.root_last
    (artifact : MaterializedParseArtifact grammar tokens) :
    artifact.root + 1 = artifact.nodes.length :=
  serializeParseTree_root_last artifact.serialized

/-- The final node retains the exact production, nonterminal, lattice span,
    and source-order child references of the materialized root. -/
theorem serializeParseTree_root_lookup
    (serialized : serializeParseTree
      (.nonterminal productionId nonterminal start finish children) =
        (nodes, some root)) :
    nodes[root]? = some {
      production := productionId
      nonterminal := nonterminal
      position_start := start
      position_end := finish
      children := (serializeParseTreesFrom 0 children).2
    } := by
  simp [serializeParseTree, serializeParseTreeFrom] at serialized
  rcases serialized with ⟨rfl, rfl⟩
  simp

def ParseChildNodeBefore (limit : Nat) : ParseChild → Prop
  | .token _ => True
  | .node nodeId => nodeId < limit

theorem ParseChildNodeBefore.mono
    (before : ParseChildNodeBefore smaller child)
    (bound : smaller ≤ larger) : ParseChildNodeBefore larger child := by
  cases child with
  | token tokenId => trivial
  | node nodeId =>
      simp [ParseChildNodeBefore] at before ⊢
      exact Nat.lt_of_lt_of_le before bound

theorem serializeParseTreeFrom_reference_before
    (base : Nat) (tree : ParseTree) :
    let serialized := serializeParseTreeFrom base tree
    ParseChildNodeBefore (base + serialized.1.length) serialized.2 := by
  cases tree <;> simp [serializeParseTreeFrom, ParseChildNodeBefore]

/-- Every nonterminal reference emitted for a sibling forest points inside
    the forest's postorder prefix. This is the local fact a parent needs to
    establish that all of its node children precede it. -/
theorem serializeParseTreesFrom_references_before
    (base : Nat) (trees : List ParseTree) :
    let serialized := serializeParseTreesFrom base trees
    ∀ child, child ∈ serialized.2 →
      ParseChildNodeBefore (base + serialized.1.length) child := by
  induction trees generalizing base with
  | nil => simp [serializeParseTreesFrom]
  | cons tree trees ih =>
      let serializedTree := serializeParseTreeFrom base tree
      let serializedTrees := serializeParseTreesFrom
        (base + serializedTree.1.length) trees
      change ∀ child, child ∈ serializedTree.2 :: serializedTrees.2 →
        ParseChildNodeBefore
          (base + (serializedTree.1 ++ serializedTrees.1).length) child
      intro child listed
      rcases List.mem_cons.mp listed with rfl | inTail
      · have before := serializeParseTreeFrom_reference_before base tree
        dsimp only at before
        exact ParseChildNodeBefore.mono before (by
          simp [serializedTree, serializedTrees, List.length_append])
      · have before := ih
          (base := base + serializedTree.1.length) child inTail
        simpa [serializedTrees, List.length_append, Nat.add_assoc] using before

theorem serializeParseTree_root_children_before
    (serialized : serializeParseTree
      (.nonterminal productionId nonterminal start finish children) =
        (nodes, some root)) :
    ∀ child, child ∈ (serializeParseTreesFrom 0 children).2 →
      ParseChildNodeBefore root child := by
  simp [serializeParseTree, serializeParseTreeFrom] at serialized
  rcases serialized with ⟨rfl, rfl⟩
  simpa using serializeParseTreesFrom_references_before 0 children


end Lanius.Extraction
