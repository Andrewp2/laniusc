import Lanius.Extraction.ArtifactQuote
import Lanius.Data.SeqTree
import Lean.Meta.LitValues

open Lean Elab Term

namespace Lanius.Extraction

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
  match Json.parse encoded >>= fromJson? with
  | .ok pack => pure pack
  | .error message => throwError "invalid extraction artifact pack: {message}"

private def checkedByte (value : Nat) : Option (Fin 256) :=
  if inRange : value < 256 then some ⟨value, inRange⟩ else none

private partial def buildSeqTree (leafSize : Nat) (values : List α) :
    Lanius.Data.SeqTree α :=
  if values.length ≤ leafSize || values.length ≤ 1 then .leaf values else
  let leftLength := values.length / 2
  let left := buildSeqTree leafSize (values.take leftLength)
  let right := buildSeqTree leafSize (values.drop leftLength)
  .branch values.length (Nat.max left.height right.height + 1) left right

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
  pure (toExpr (buildSeqTree leafSize artifact.tokens))

elab "artifact_pack_unit_semantic_kind_tree% " json:term ", " path:term ", "
    leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure (toExpr (buildSeqTree leafSize artifact.semantic_token_kinds))

elab "artifact_pack_unit_parse_node_tree% " json:term ", " path:term ", "
    leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure (toExpr (buildSeqTree leafSize artifact.parse_nodes))

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
  pure (toExpr (buildSeqTree leafSize
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
  pure (toExpr (buildSeqTree leafSize bytes))

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
    buildSeqTree leafSize artifact.parse_nodes,
    buildSeqTree leafSize artifact.tokens,
    buildSeqTree leafSize bytes))

end Lanius.Extraction
