import Lanius.Extraction.Artifact
import Lanius.Extraction.CoreDecode
import Lean.Meta.LitValues

open Lean Elab Term

namespace Lanius.Extraction

/-- Elaborate a compile-time string without executing arbitrary Lean code.
    `include_str` itself produces a string literal, so artifact quotation needs
    only structural literal extraction rather than `Meta.evalExpr`. -/
private def elabStringLiteral (stx : Syntax) : TermElabM String := do
  let expression ← elabTermEnsuringType stx (mkConst ``String)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value := Meta.getStringValue? expression
    | throwError "artifact quotation requires a compile-time string literal"
  pure value

private def elabNatLiteral (stx : Syntax) : TermElabM Nat := do
  let expression ← elabTermEnsuringType stx (mkConst ``Nat)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value ← Meta.getNatValue? expression
    | throwError "artifact quotation requires a compile-time natural literal"
  pure value

private def elabArtifactLiteral (stx : Syntax) : TermElabM Artifact := do
  let encoded ← elabStringLiteral stx
  match Json.parse encoded >>= fromJson? with
  | .ok artifact => pure artifact
  | .error message => throwError "invalid extraction artifact: {message}"

private def elabArtifactPackLiteral (stx : Syntax) : TermElabM ArtifactPack := do
  let encoded ← elabStringLiteral stx
  match Json.parse encoded >>= fromJson? with
  | .ok pack => pure pack
  | .error message => throwError "invalid extraction artifact pack: {message}"

private def quoteFunctionFromArtifact
    (artifact : Artifact) (expectedPath expectedName : String) : TermElabM Expr := do
  unless artifact.sources.any fun source => source.path == expectedPath do
    throwError "artifact has no source {expectedPath}"
  let some surface := artifact.surface
    | throwError "source unit {expectedPath} has no Surface tree"
  let some core := artifact.core_program
    | throwError "source unit {expectedPath} has no Core program"
  let sourceFunctions := surface.value.items.filterMap fun item =>
    match item.value with
    | .function function => some function.name.text
    | _ => none
  if sourceFunctions.length != core.functions.length then
    throwError "source unit {expectedPath} has mismatched Surface/Core function counts"
  let candidates := (sourceFunctions.zip core.functions).filter fun pair =>
    pair.1 == expectedName
  let [(_, function)] := candidates
    | throwError "source unit {expectedPath} must contain exactly one function named {expectedName}"
  pure (toExpr function)

/-- Elaborate one extraction artifact into ordinary constructor data. -/
elab "artifact% " json:term : term => do
  pure (toExpr (← elabArtifactLiteral json))

/-- Quote one field of an artifact as a separate constructor value. This lets
    large artifacts be assembled from independently compiled constants instead
    of forcing Lean's code generator to normalize one enormous record. -/
elab "artifact_field% " json:term ", " field:ident : term => do
  let artifact ← elabArtifactLiteral json
  match field.getId.toString with
  | "schema_version" => pure (toExpr artifact.schema_version)
  | "sources" => pure (toExpr artifact.sources)
  | "tokens" => pure (toExpr artifact.tokens)
  | "raw_tokens" => pure (toExpr artifact.raw_tokens)
  | "semantic_token_kinds" => pure (toExpr artifact.semantic_token_kinds)
  | "parse_nodes" => pure (toExpr artifact.parse_nodes)
  | "parse_root" => pure (toExpr artifact.parse_root)
  | "surface" => pure (toExpr artifact.surface)
  | "resolutions" => pure (toExpr artifact.resolutions)
  | "types" => pure (toExpr artifact.types)
  | "core_program" => pure (toExpr artifact.core_program)
  | "lowering" => pure (toExpr artifact.lowering)
  | name => throwError "artifact has no quotable field {name}"

/-- Quote one field of an artifact's Core program. Core function bodies can be
    much larger than the other program tables, so keeping these fields as
    separate declarations prevents a constant or type lookup from unfolding
    every function body. -/
elab "artifact_core_field% " json:term ", " field:ident : term => do
  let artifact ← elabArtifactLiteral json
  let some program := artifact.core_program
    | throwError "extraction artifact has no Core program"
  match field.getId.toString with
  | "target" => pure (toExpr program.target)
  | "structures" => pure (toExpr program.structures)
  | "enumerations" => pure (toExpr program.enumerations)
  | "constants" => pure (toExpr program.constants)
  | "functions" => pure (toExpr program.functions)
  | name => throwError "artifact Core program has no quotable field {name}"

/-- Quote a checked slice of an artifact's parse-node table. Very large parse
    tables are emitted as several independently compiled constants and then
    concatenated, avoiding a monolithic LCNF compilation unit. -/
elab "artifact_parse_nodes% " json:term ", " start:term ", " count:term : term => do
  let artifact ← elabArtifactLiteral json
  let start ← elabNatLiteral start
  let count ← elabNatLiteral count
  unless start + count ≤ artifact.parse_nodes.length do
    throwError "parse-node slice [{start}, {start + count}) exceeds table length {artifact.parse_nodes.length}"
  pure (toExpr (artifact.parse_nodes.drop start |>.take count))

/-- Quote the decoded Core program from a standalone extraction artifact.
    Keeping JSON parsing in the elaborator makes later function lookup reduce
    over ordinary Core constructors instead of re-running the JSON decoder. -/
elab "artifact_core_program% " json:term : term => do
  let artifact ← elabArtifactLiteral json
  let some wire := artifact.core_program
    | throwError "extraction artifact has no Core program"
  pure (mkApp (mkConst ``CoreDecode.program) (toExpr wire))

/-- Elaborate a JSON artifact pack into ordinary constructor data. JSON is an
    interchange format only: proofs and definitional reduction consume the
    quoted `ArtifactPack`, so they do not repeatedly execute the JSON parser. -/
elab "artifact_pack% " json:term : term => do
  pure (toExpr (← elabArtifactPackLiteral json))

/-- Quote one source unit from a pack by its checked source path. Selecting by
    path avoids coupling proofs to incidental pack ordering. -/
elab "artifact_pack_unit% " json:term ", " path:term : term => do
  let expectedPath ← elabStringLiteral path
  let pack ← elabArtifactPackLiteral json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  -- Large raw traces are quoted separately at the one boundary that needs
  -- them.  Keeping them out of ordinary unit constants prevents unrelated
  -- function/body projections from inheriting thousands of token rows.
  pure (toExpr { artifact with raw_tokens := none })

/-- Quote one complete source unit from a pack.  This is used by independently
compiled unit modules: keeping the module boundary per source prevents a proof
about one unit from loading every artifact in the pack. -/
elab "artifact_pack_unit_full% " json:term ", " path:term : term => do
  let expectedPath ← elabStringLiteral path
  let pack ← elabArtifactPackLiteral json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure (toExpr artifact)

/-- Quote only a unit's optional complete raw-token trace. -/
elab "artifact_pack_raw_tokens% " json:term ", " path:term : term => do
  let expectedPath ← elabStringLiteral path
  let pack ← elabArtifactPackLiteral json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure (toExpr artifact.raw_tokens)

/-- Quote one field of a named pack unit.  Large checked units are assembled
from opaque field constants so reducing one checker projection never unfolds
the unit's unrelated parse, Surface, evidence, or Core tables. -/
elab "artifact_pack_unit_field% " json:term ", " path:term ", " field:ident : term => do
  let expectedPath ← elabStringLiteral path
  let pack ← elabArtifactPackLiteral json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  match field.getId.toString with
  | "schema_version" => pure (toExpr artifact.schema_version)
  | "sources" => pure (toExpr artifact.sources)
  | "tokens" => pure (toExpr artifact.tokens)
  | "raw_tokens" => pure (toExpr artifact.raw_tokens)
  | "semantic_token_kinds" => pure (toExpr artifact.semantic_token_kinds)
  | "parse_nodes" => pure (toExpr artifact.parse_nodes)
  | "parse_root" => pure (toExpr artifact.parse_root)
  | "surface" => pure (toExpr artifact.surface)
  | "resolutions" => pure (toExpr artifact.resolutions)
  | "types" => pure (toExpr artifact.types)
  | "core_program" => pure (toExpr artifact.core_program)
  | "lowering" => pure (toExpr artifact.lowering)
  | name => throwError "artifact pack unit has no quotable field {name}"

/-- Quote a checked parse-node slice from one named pack unit. -/
elab "artifact_pack_unit_parse_nodes% " json:term ", " path:term ", "
    start:term ", " count:term : term => do
  let expectedPath ← elabStringLiteral path
  let start ← elabNatLiteral start
  let count ← elabNatLiteral count
  let pack ← elabArtifactPackLiteral json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  unless start + count ≤ artifact.parse_nodes.length do
    throwError "parse-node slice [{start}, {start + count}) exceeds table length {artifact.parse_nodes.length}"
  pure (toExpr (artifact.parse_nodes.drop start |>.take count))

/-- Quote one Core function from a source unit by its reconstructed source
    declaration name. The elaborator rejects missing/duplicate names and a
    Surface/Core arity mismatch; Lean separately proves that the containing
    artifact passes the verified pairing checker. Quoting only the selected
    wire row keeps downstream reduction independent of the artifact's size. -/
elab "artifact_pack_function% " json:term ", " path:term ", " name:term : term => do
  let expectedPath ← elabStringLiteral path
  let expectedName ← elabStringLiteral name
  let pack ← elabArtifactPackLiteral json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  quoteFunctionFromArtifact artifact expectedPath expectedName

/-- Quote one Core function from a standalone extraction artifact by its
    checked source path and reconstructed declaration name. -/
elab "artifact_function% " json:term ", " path:term ", " name:term : term => do
  let expectedPath ← elabStringLiteral path
  let expectedName ← elabStringLiteral name
  let artifact ← elabArtifactLiteral json
  quoteFunctionFromArtifact artifact expectedPath expectedName

end Lanius.Extraction
