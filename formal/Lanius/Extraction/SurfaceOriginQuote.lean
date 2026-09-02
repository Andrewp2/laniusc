import Lanius.Extraction.ArtifactCacheQuote
import Lanius.Extraction.SurfaceReconstructProvenance
import Lean.Meta.LitValues

open Lean Elab Term

namespace Lanius.Extraction

private def originElabStringLiteral (stx : Syntax) : TermElabM String := do
  let expression ← elabTermEnsuringType stx (mkConst ``String)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value := Meta.getStringValue? expression
    | throwError "origin quotation requires a string literal"
  pure value

private def originElabPack (stx : Syntax) : TermElabM ArtifactPack := do
  let encoded ← originElabStringLiteral stx
  match Json.parse encoded >>= fromJson? with
  | .ok pack => pure pack
  | .error message => throwError "invalid extraction artifact pack: {message}"

private def quotedNodeSlot : List ParseChild → ParseNodeId → Nat → Option Nat
  | [], _, _ => none
  | .node child :: rest, target, slot =>
      if child = target then some slot
      else quotedNodeSlot rest target (slot + 1)
  | .token _ :: rest, target, slot =>
      quotedNodeSlot rest target (slot + 1)

private def quotedTokenSlot : List ParseChild → TokenId → Nat → Option Nat
  | [], _, _ => none
  | .token child :: rest, target, slot =>
      if child = target then some slot
      else quotedTokenSlot rest target (slot + 1)
  | .node _ :: rest, target, slot =>
      quotedTokenSlot rest target (slot + 1)

private def quotedNodePath (artifact : Artifact)
    (nodeParents : List (Option ParseNodeId))
    (root target : ParseNodeId) : Option ParseNodePath :=
  let rec ascend : Nat → ParseNodeId → List Nat → Option (List Nat)
    | 0, _, _ => none
    | fuel + 1, current, edges =>
        if current = root then some edges else do
          let some parent ← nodeParents[current]? | none
          let parentNode ← artifact.parse_nodes[parent]?
          let childSlot ← quotedNodeSlot parentNode.children current 0
          ascend fuel parent (childSlot :: edges)
  return {
    root
    edges := ← ascend (artifact.parse_nodes.length + 1) target []
    target
  }

private def quotedTokenPath (artifact : Artifact)
    (nodeParents : List (Option ParseNodeId))
    (tokenParents : List (Option ParseNodeId))
    (root : ParseNodeId) (token : TokenId) : Option ParseTokenPath := do
  let some directOwner ← tokenParents[token]? | none
  let ownerNode ← artifact.parse_nodes[directOwner]?
  let childSlot ← quotedTokenSlot ownerNode.children token 0
  let nodePath ← quotedNodePath artifact nodeParents root directOwner
  pure { nodePath, childSlot, token }

private def quoteSurfaceOrigins (artifact : Artifact)
    (claims : SurfaceClaims) : Option SurfaceOrigins := do
  let parents := buildParentTables artifact
  let nodePaths ← claims.nodes.mapM fun claim =>
    match claim.containingParseNode with
    | none => some none
    | some root => do
        let path ← quotedNodePath artifact parents.1 root claim.parseNode
        pure (some path)
  let spellingPaths ← claims.spellings.mapM fun claim =>
    quotedTokenPath artifact parents.1 parents.2 claim.owner claim.token
  pure { claims, nodePaths, spellingPaths }

/-- Quote compact candidate origin paths for the Surface proposal.  The
quotation code is untrusted: consumers must check every path with
`SurfaceOrigins.valid`. -/
elab "artifact_pack_unit_surface_origins% " json:term ", " path:term : term => do
  let expectedPath ← originElabStringLiteral path
  let pack ← originElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  let some surface := artifact.surface
    | throwError "source unit {expectedPath} has no Surface proposal"
  let some claims := collectSurfaceClaimsFrom artifact surface
    | throwError "source unit {expectedPath} has uncollectable Surface claims"
  let some origins := quoteSurfaceOrigins artifact claims
    | throwError "source unit {expectedPath} has no complete Surface origin paths"
  pure (toExpr origins)

end Lanius.Extraction
