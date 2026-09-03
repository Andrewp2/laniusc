import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.Evidence.StructureChecker
import Lean.Meta.LitValues

open Lean Elab Term

namespace Lanius.Extraction

private def evidenceElabStringLiteral (stx : Syntax) : TermElabM String := do
  let expression ← elabTermEnsuringType stx (mkConst ``String)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value := Meta.getStringValue? expression
    | throwError "evidence quotation requires a string literal"
  pure value

private def evidenceElabNatLiteral (stx : Syntax) : TermElabM Nat := do
  let expression ← elabTermEnsuringType stx (mkConst ``Nat)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value ← Meta.getNatValue? expression
    | throwError "evidence quotation requires a natural literal"
  pure value

private def evidenceElabPack (stx : Syntax) : TermElabM ArtifactPack := do
  let encoded ← evidenceElabStringLiteral stx
  match Json.parse encoded >>= fromJson? with
  | .ok pack => pure pack
  | .error message => throwError "invalid extraction artifact pack: {message}"

private def evidenceUnit (json path : Syntax) : TermElabM Artifact := do
  let expectedPath ← evidenceElabStringLiteral path
  let pack ← evidenceElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure artifact

private partial def buildEvidenceSeqTree (leafSize : Nat) (values : List α) :
    Lanius.Data.SeqTree α :=
  if values.length ≤ leafSize || values.length ≤ 1 then .leaf values else
  let leftLength := values.length / 2
  let left := buildEvidenceSeqTree leafSize (values.take leftLength)
  let right := buildEvidenceSeqTree leafSize (values.drop leftLength)
  .branch values.length (Nat.max left.height right.height + 1) left right

private def firstIndex? (predicate : α → Bool) : List α → Nat → Option Nat
  | [], _ => none
  | value :: values, index =>
      if predicate value then some index else firstIndex? predicate values (index + 1)

private def firstSurfaceIndex? (surfaceNode : Nat) (rows : List α)
    (node : α → Nat) : Option Nat :=
  firstIndex? (fun row => node row == surfaceNode) rows 0

private def loweringTypeRefs (artifact : Artifact) : List Nat :=
  artifact.lowering.map fun row =>
    if typedLoweringRule row.rule then
      (firstSurfaceIndex? row.surface_node artifact.types (·.surface_node)).getD
        artifact.types.length
    else 0

private def typeLoweringRefs (artifact : Artifact) : List Nat :=
  artifact.types.map fun row =>
    (firstSurfaceIndex? row.surface_node artifact.lowering (·.surface_node)).getD
      artifact.lowering.length

elab "artifact_pack_unit_evidence_type_tree% " json:term ", " path:term ", "
    leafSize:term : term => do
  let artifact ← evidenceUnit json path
  let leafSize ← evidenceElabNatLiteral leafSize
  pure (toExpr (buildEvidenceSeqTree leafSize artifact.types))

elab "artifact_pack_unit_evidence_lowering_tree% " json:term ", " path:term ", "
    leafSize:term : term => do
  let artifact ← evidenceUnit json path
  let leafSize ← evidenceElabNatLiteral leafSize
  pure (toExpr (buildEvidenceSeqTree leafSize artifact.lowering))

elab "artifact_pack_unit_lowering_type_refs% " json:term ", " path:term : term => do
  let artifact ← evidenceUnit json path
  pure (toExpr (loweringTypeRefs artifact))

elab "artifact_pack_unit_type_lowering_refs% " json:term ", " path:term : term => do
  let artifact ← evidenceUnit json path
  pure (toExpr (typeLoweringRefs artifact))

end Lanius.Extraction
