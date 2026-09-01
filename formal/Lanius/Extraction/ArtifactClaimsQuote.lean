import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.SurfaceChecker
import Lean.Meta.LitValues

open Lean Elab Term

namespace Lanius.Extraction

private def claimsElabStringLiteral (stx : Syntax) : TermElabM String := do
  let expression ← elabTermEnsuringType stx (mkConst ``String)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value := Meta.getStringValue? expression
    | throwError "claim quotation requires a string literal"
  pure value

private def claimsElabPack (stx : Syntax) : TermElabM ArtifactPack := do
  let encoded ← claimsElabStringLiteral stx
  match Json.parse encoded >>= fromJson? with
  | .ok pack => pure pack
  | .error message => throwError "invalid extraction artifact pack: {message}"

/-- Materialize the claims computed from an exported Surface proposal.  This
is only a reduction cache: each consumer must prove it equal to claims
collected from the independently reconstructed Surface tree. -/
elab "artifact_pack_unit_surface_claims% " json:term ", " path:term : term => do
  let expectedPath ← claimsElabStringLiteral path
  let pack ← claimsElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  let some surface := artifact.surface
    | throwError "source unit {expectedPath} has no Surface proposal"
  let some claims := collectSurfaceClaimsFrom artifact surface
    | throwError "source unit {expectedPath} has uncollectable Surface claims"
  pure (toExpr claims)

end Lanius.Extraction
