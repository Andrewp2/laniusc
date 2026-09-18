import Lanius.Extraction.ArtifactQuote
import Lanius.Data.SeqTree
import Lean.Meta.LitValues

open Lean Meta Elab Term

namespace Lanius.Extraction

universe u

private def cacheElabStringLiteral (stx : Syntax) : TermElabM String := do
  let expression ← elabTermEnsuringType stx (mkConst ``String)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value := Meta.getStringValue? expression
    | throwError "artifact cache quotation requires a string literal"
  pure value

private def cacheElabNatLiteral (stx : Syntax) : TermElabM Nat := do
  let expression ← elabTermEnsuringType stx (mkConst ``Nat)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value ← Meta.getNatValue? expression
    | throwError "artifact cache quotation requires a natural literal"
  pure value

private def cacheElabPack (stx : Syntax) : TermElabM ArtifactPack := do
  let encoded ← cacheElabStringLiteral stx
  match ← decodeArtifactPackInput encoded with
  | .ok pack => pure pack
  | .error message => throwError "invalid extraction artifact pack: {message}"

private def checkedByte (value : Nat) : Option (Fin 256) :=
  if inRange : value < 256 then some ⟨value, inRange⟩ else none

/-- Untrusted cache proposal shared by quotation consumers. Only the existing
`ArtifactCache`/`ArtifactView` checks give its sizes, balance, and contents authority. -/
partial def proposeSeqTree (leafSize : Nat) (values : List α) :
    Lanius.Data.SeqTree α :=
  if values.length ≤ leafSize || values.length ≤ 1 then .leaf values else
  let leftLength := values.length / 2
  let left := proposeSeqTree leafSize (values.take leftLength)
  let right := proposeSeqTree leafSize (values.drop leftLength)
  .branch values.length (Nat.max left.height right.height + 1) left right

private partial def retainedSpine (values : Expr)
    (heads tails : Array Expr := #[]) : MetaM (Array Expr × Array Expr) := do
  let values ← Meta.whnf values
  match values.getAppFn.constName? with
  | some ``List.nil => pure (heads, tails.push values)
  | some ``List.cons =>
    let args := values.getAppArgs
    retainedSpine args[2]! (heads.push args[1]!) (tails.push values)
  | _ => throwError "sequence quotation requires a known list spine"

private def checkedList (level : Level) (type : Expr) (values : List Expr) : Expr :=
  values.foldr (fun head tail =>
    mkApp3 (mkConst ``List.cons [level]) type head tail)
    (mkApp (mkConst ``List.nil [level]) type)

private def retainedTree (type : Expr) (level : Level) : Lanius.Data.SeqTree Expr → Expr
  | .leaf values =>
    mkApp2 (mkConst ``Lanius.Data.SeqTree.leaf [level]) type
      (checkedList level type values)
  | .branch count height left right =>
    mkApp5 (mkConst ``Lanius.Data.SeqTree.branch [level]) type (mkNatLit count)
      (mkNatLit height) (retainedTree type level left) (retainedTree type level right)

private theorem seqTreeCheckedBranch {α : Type u} (size height : Nat)
    (left right : Lanius.Data.SeqTree α)
    {leftTail middle tail : List α}
    (leftProof : left.flatten ++ middle = leftTail)
    (rightProof : right.flatten ++ tail = middle) :
    (Lanius.Data.SeqTree.branch size height left right).flatten ++ tail = leftTail := by
  simp only [Lanius.Data.SeqTree.flatten]
  rw [List.append_assoc, rightProof]
  exact leftProof

private structure CheckedTree where
  tree : Expr
  height : Nat
  proof : Expr

private partial def buildCheckedTree
    (level : Level) (type : Expr) (heads tails : Array Expr)
    (start length leafSize : Nat) : MetaM CheckedTree := do
  let finish := start + length
  if length ≤ leafSize || length ≤ 1 then
    let values := (heads.extract start finish).toList
    let values := checkedList level type values
    let tree := mkApp2 (mkConst ``Lanius.Data.SeqTree.leaf [level]) type values
    let proof ← mkEqRefl tails[start]!
    pure ⟨tree, 1, proof⟩
  else
    let leftLength := length / 2
    let left ← buildCheckedTree level type heads tails start leftLength leafSize
    let right ← buildCheckedTree level type heads tails
      (start + leftLength) (length - leftLength) leafSize
    let height := max left.height right.height + 1
    let tree := mkApp5 (mkConst ``Lanius.Data.SeqTree.branch [level]) type
      (mkNatLit length) (mkNatLit height) left.tree right.tree
    let proof ← mkAppM' (mkConst ``seqTreeCheckedBranch [level])
      #[mkNatLit length, mkNatLit height,
      left.tree, right.tree, left.proof, right.proof]
    pure ⟨tree, height, proof⟩

/-- Produce a balanced tree and a checked proof that it flattens to the exact
input list.  Callers still establish the tree's capacity and balance facts. -/
elab "seq_tree_checked% " input:term ", " leafSize:term : term => do
  let input ← elabTerm input none
  let type ← Meta.whnf (← Meta.inferType input)
  let .app (.const ``List [level]) element := type
    | throwError "checked sequence quotation requires a list"
  let leafSize ← cacheElabNatLiteral leafSize
  unless leafSize > 0 do throwError "sequence leaf capacity must be positive"
  let (heads, tails) ← retainedSpine input
  let data ← buildCheckedTree level element heads tails 0 heads.size leafSize
  let flatten ← mkAppM ``Lanius.Data.SeqTree.flatten #[data.tree]
  let nilEquality ← mkAppM ``List.append_nil #[flatten]
  let nilEquality ← mkAppM ``Eq.symm #[nilEquality]
  let proof ← mkAppM ``Eq.trans #[nilEquality, data.proof]
  let treeType := mkApp (mkConst ``Lanius.Data.SeqTree [level]) element
  let predicate ← withLocalDeclD `tree treeType fun tree => do
    let body ← mkAppM ``Lanius.Data.SeqTree.Represents #[tree, input]
    mkLambdaFVars #[tree] body
  let result := mkAppN (mkConst ``Subtype.mk [Level.succ level])
    #[treeType, predicate, data.tree, proof]
  if result.hasLooseBVars then
    throwError "checked sequence result has loose bound variables"
  pure result

/-- Propose a balanced table retaining the original element expressions.
Only the list spine is unfolded: authenticating `flatten = input` need not
decode and compare every field again. As with native proposals, callers must
prove representation and balance before constructing a checked view. -/
elab "seq_tree% " input:term ", " leafSize:term : term => do
  let input ← elabTerm input none
  let type ← Meta.whnf (← Meta.inferType input)
  let .app (.const ``List [level]) element := type
    | throwError "sequence quotation requires a list"
  let capacity ← cacheElabNatLiteral leafSize
  unless capacity > 0 do throwError "sequence leaf capacity must be positive"
  let (entries, _) ← retainedSpine input
  return retainedTree element level (proposeSeqTree capacity entries.toList)

def buildParentTables (artifact : Artifact) :
    List (Option ParseNodeId) × List (Option ParseNodeId) := Id.run do
  let mut nodeParents := Array.replicate artifact.parse_nodes.length none
  let mut tokenParents := Array.replicate artifact.tokens.length none
  for (node, parentId) in artifact.parse_nodes.zipIdx do
    for child in node.children do
      match child with
      | .node childId =>
          nodeParents := nodeParents.setIfInBounds childId (some parentId)
      | .token tokenId =>
          tokenParents := tokenParents.setIfInBounds tokenId (some parentId)
  return (nodeParents.toList, tokenParents.toList)

elab "artifact_pack_unit_token_tree% " json:term ", " path:term ", "
    leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure (toExpr (proposeSeqTree leafSize artifact.tokens))

elab "artifact_pack_unit_semantic_kind_tree% " json:term ", " path:term ", "
    leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure (toExpr (proposeSeqTree leafSize artifact.semantic_token_kinds))

elab "artifact_pack_unit_parse_node_tree% " json:term ", " path:term ", "
    leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure (toExpr (proposeSeqTree leafSize artifact.parse_nodes))

/-- Quote one balanced range of a unit's parse-node cache.  Large cache trees
are compiled from independently emitted subtrees and joined with checked
branch metadata, avoiding a monolithic generated-data module. -/
elab "artifact_pack_unit_parse_node_tree_range% " json:term ", " path:term ", "
    start:term ", " count:term ", " leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let start ← cacheElabNatLiteral start
  let count ← cacheElabNatLiteral count
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  unless start + count ≤ artifact.parse_nodes.length do
    throwError "parse-node tree range exceeds unit {expectedPath}"
  pure (toExpr (proposeSeqTree leafSize
    (artifact.parse_nodes.drop start |>.take count)))

elab "artifact_pack_unit_source_byte_tree% " json:term ", " path:term ", "
    sourceIndex:term ", " leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let sourceIndex ← cacheElabNatLiteral sourceIndex
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  let some source := artifact.sources[sourceIndex]?
    | throwError "source index is absent in unit {expectedPath}"
  let some bytes := source.bytes.mapM checkedByte
    | throwError "source contains an out-of-range byte"
  pure (toExpr (proposeSeqTree leafSize bytes))

/-- Quotes all three balanced artifact-view trees in one pass. -/
elab "artifact_pack_unit_cache_trees% " json:term ", " path:term ", "
    sourceIndex:term ", " leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let sourceIndex ← cacheElabNatLiteral sourceIndex
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  let some source := artifact.sources[sourceIndex]?
    | throwError "source index is absent in unit {expectedPath}"
  let some bytes := source.bytes.mapM checkedByte
    | throwError "source contains an out-of-range byte"
  pure (toExpr (
    proposeSeqTree leafSize artifact.parse_nodes,
    proposeSeqTree leafSize artifact.tokens,
    proposeSeqTree leafSize bytes))

end Lanius.Extraction
