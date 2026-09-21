import Lanius.Extraction.Artifact
import Lanius.Extraction.CoreDecode
import Lean.Meta.LitValues

open Lean Elab Term

namespace Lanius.Extraction

/- Core values are the final output of the pack quotation path.  Core was
   historically only runtime data (and therefore derived `Repr`), while the
   extraction wire types carried `ToExpr` for JSON quotation.  Keep this
   bridge local to the quotation module: it lets the elaborator emit ordinary
   Core constructors without making every Core consumer pay for a quotation
   interface. -/
deriving instance Lean.ToExpr for Lanius.Core.PointerWidth
deriving instance Lean.ToExpr for Lanius.Core.Target
deriving instance Lean.ToExpr for Lanius.Core.SignedIntTy
deriving instance Lean.ToExpr for Lanius.Core.UnsignedIntTy
deriving instance Lean.ToExpr for Lanius.Core.ScalarTy
deriving instance Lean.ToExpr for Lanius.Core.Ty
deriving instance Lean.ToExpr for Lanius.Core.ValueProjection
deriving instance Lean.ToExpr for Lanius.Core.Value
deriving instance Lean.ToExpr for Lanius.Core.UnaryOp
deriving instance Lean.ToExpr for Lanius.Core.BinaryOp
deriving instance Lean.ToExpr for Lanius.Core.AssignOp
deriving instance Lean.ToExpr for Lanius.Core.HostService
deriving instance Lean.ToExpr for Lanius.Capability
deriving instance Lean.ToExpr for Lanius.Core.ExternalBehavior
deriving instance Lean.ToExpr for Lanius.Core.Intrinsic
deriving instance Lean.ToExpr for Lanius.Core.Pattern
deriving instance Lean.ToExpr for Lanius.Core.Expr
deriving instance Lean.ToExpr for Lanius.Core.Place
deriving instance Lean.ToExpr for Lanius.Core.Stmt
deriving instance Lean.ToExpr for Lanius.Core.StructDecl
deriving instance Lean.ToExpr for Lanius.Core.EnumDecl
deriving instance Lean.ToExpr for Lanius.Core.Function
deriving instance Lean.ToExpr for Lanius.Core.Constant
deriving instance Lean.ToExpr for Lanius.Core.Program


/-- Exact constructor expressions, scoped to the current Lean environment.
Sharing proof-only quotations retains the original checked definitions instead
of later asking unification to compare duplicate long constructor chains. -/
private initialize proofQuotationCache : EnvExtension (Std.HashMap Expr Expr) ←
  registerEnvExtension (pure {})

/-- Keep constructor data below the size where native-code specialization
repeatedly scans long constructor chains. Auxiliary definitions are ordinary
kernel-checked definitions, so the result remains definitionally equal to the
original quotation. No serialized data or proof is trusted by this step. -/
private partial def boundQuotation (value : Expr) (share : Bool) :
    StateRefT (Array Name) TermElabM (Expr × Nat) := do
  if !value.isApp then return (value, 1)
  let mut args := #[]
  let mut size := 1
  for arg in value.getAppArgs do
    let (arg, argSize) ← boundQuotation arg share
    args := args.push arg
    size := size + argSize
  let value := mkAppN value.getAppFn args
  if size < 2048 then return (value, size)
  let share := share && !value.hasFVar && !value.hasMVar && !value.hasLooseBVars
  if share then
    if let some checked := (proofQuotationCache.getState (← getEnv))[value]? then
      return (checked, 1)
  let name ← mkAuxDeclName `quotedData
  let checked ← Meta.mkAuxDefinitionFor name value (compile := false)
  if share then
    modifyEnv fun env => proofQuotationCache.modifyState env (·.insert value checked)
  modify fun names => names.push name
  return (checked, 1)

/-- Kernel-check the bounded data declarations. Proof-only consumers can skip
native code generation; this does not skip declaration or equality checking. -/
def quoteBounded [ToExpr α] (value : α) (compile : Bool := true) : TermElabM Expr := do
  let ((expression, _), declarations) ← (boundQuotation (toExpr value) (!compile)).run #[]
  if compile then compileDecls declarations
  return expression

-- One exact input, scoped to this process. The cached value is untrusted
-- decoded data; every quoted term and every certificate is still checked.
private initialize artifactPackInput : IO.Ref (Option (String × ArtifactPack)) ← IO.mkRef none
private initialize artifactInput : IO.Ref (Option (String × Artifact)) ← IO.mkRef none

/-- Share one decoded artifact across its field and function quotations.
Only exact input equality permits reuse; the cache grants no proof authority. -/
def decodeArtifactInput (encoded : String) : IO (Except String Artifact) := do
  if let some (previous, artifact) ← artifactInput.get then
    if previous == encoded then return .ok artifact
  let result := Json.parse encoded >>= fromJson?
  if let .ok artifact := result then
    artifactInput.set (some (encoded, artifact))
  return result

/-- Decode a pack once across quotation entry points. Exact string comparison
prevents path reuse or hash collisions from substituting a different input.
Only the last successful input is retained, bounding cache growth. -/
def decodeArtifactPackInput (encoded : String) : IO (Except String ArtifactPack) := do
  if let some (previous, pack) ← artifactPackInput.get then
    if previous == encoded then return .ok pack
  let result := Json.parse encoded >>= fromJson?
  if let .ok pack := result then
    artifactPackInput.set (some (encoded, pack))
  return result

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

private def reportQuotation (phase : String) : TermElabM Unit := do
  if (← getOptions).getBool `trace.profiler false then
    IO.eprintln s!"artifact quotation [{← IO.monoMsNow} ms]: {phase}"

private def elabArtifactLiteral (stx : Syntax) : TermElabM Artifact := do
  reportQuotation "read literal"
  let encoded ← elabStringLiteral stx
  reportQuotation "decode input"
  let decoded ← decodeArtifactInput encoded
  reportQuotation "decoded input"
  match decoded with
  | .ok artifact => pure artifact
  | .error message => throwError "invalid extraction artifact: {message}"

private def elabArtifactPackLiteral (stx : Syntax) : TermElabM ArtifactPack := do
  let encoded ← elabStringLiteral stx
  match ← decodeArtifactPackInput encoded with
  | .ok pack => pure pack
  | .error message => throwError "invalid extraction artifact pack: {message}"

private def elabArtifactPackUnitAt (json : Syntax) (expectedPath : String) : TermElabM Artifact := do
  let pack ← elabArtifactPackLiteral json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure artifact

private def elabArtifactPackUnit (json path : Syntax) : TermElabM (String × Artifact) := do
  let expectedPath ← elabStringLiteral path
  pure (expectedPath, ← elabArtifactPackUnitAt json expectedPath)

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
  reportQuotation s!"field {field.getId}"
  let artifact ← elabArtifactLiteral json
  match field.getId.toString with
  | "schema_version" => quoteBounded artifact.schema_version
  | "sources" => quoteBounded artifact.sources
  | "tokens" => quoteBounded artifact.tokens
  | "raw_tokens" => quoteBounded artifact.raw_tokens
  | "semantic_token_kinds" => quoteBounded artifact.semantic_token_kinds
  | "parse_nodes" => quoteBounded artifact.parse_nodes
  | "parse_root" => quoteBounded artifact.parse_root
  | "surface" => quoteBounded artifact.surface
  | "resolutions" => quoteBounded artifact.resolutions
  | "types" => quoteBounded artifact.types
  | "core_program" => quoteBounded artifact.core_program
  | "lowering" => quoteBounded artifact.lowering
  | name => throwError "artifact has no quotable field {name}"

/-- Quote one source file's bytes as a String. The byte-to-string conversion is
    performed while decoding the artifact; the resulting literal is still
    kernel-checked against any source literal used by a provenance theorem. -/
elab "artifact_source_text% " json:term ", " path:term : term => do
  let expectedPath ← elabStringLiteral path
  let artifact ← elabArtifactLiteral json
  let some source := artifact.sources.find? fun source => source.path == expectedPath
    | throwError "artifact has no source {expectedPath}"
  unless source.bytes.all (· < 256) do
    throwError "source {expectedPath} contains a non-byte value"
  let bytes := ByteArray.mk (source.bytes.toArray.map UInt8.ofNat)
  match String.fromUTF8? bytes with
  | some text => pure (toExpr text)
  | none => throwError "source {expectedPath} is not valid UTF-8"

/-- Quote one source file's bytes from a named unit in an artifact pack. -/
elab "artifact_pack_source_text% " json:term ", " path:term : term => do
  let expectedPath ← elabStringLiteral path
  let artifact ← elabArtifactPackUnitAt json expectedPath
  let some source := artifact.sources.find? fun source => source.path == expectedPath
    | throwError "artifact has no source {expectedPath}"
  unless source.bytes.all (· < 256) do
    throwError "source {expectedPath} contains a non-byte value"
  let bytes := ByteArray.mk (source.bytes.toArray.map UInt8.ofNat)
  match String.fromUTF8? bytes with
  | some text => pure (toExpr text)
  | none => throwError "source {expectedPath} is not valid UTF-8"

private def quoteSourceByte (source : String) (index : Nat) : TermElabM Expr := do
  let bytes := source.toUTF8
  let some byte := bytes[index]?
    | throwError "source byte index {index} is out of bounds"
  pure (toExpr byte.toNat)

/- A small byte quotation keeps a provenance check from normalizing an entire
   source string in the kernel.  The source is still read from the literal at
   elaboration time, while the resulting natural is ordinary checked data. -/
elab "source_byte% " source:term ", " index:term : term => do
  quoteSourceByte (← elabStringLiteral source) (← elabNatLiteral index)

elab "artifact_pack_source_byte% " json:term ", " path:term ", " index:term : term => do
  let expectedPath ← elabStringLiteral path
  let artifact ← elabArtifactPackUnitAt json expectedPath
  let some source := artifact.sources.find? fun source => source.path == expectedPath
    | throwError "artifact has no source {expectedPath}"
  unless source.bytes.all (· < 256) do
    throwError "source {expectedPath} contains a non-byte value"
  let bytes := ByteArray.mk (source.bytes.toArray.map UInt8.ofNat)
  let some byte := bytes[← elabNatLiteral index]?
    | throwError "source byte index is out of bounds"
  pure (toExpr byte.toNat)

/-- Quote one field of an artifact's Core program. Core function bodies can be
    much larger than the other program tables, so keeping these fields as
    separate declarations prevents a constant or type lookup from unfolding
    every function body. -/
elab "artifact_core_field% " json:term ", " field:ident : term => do
  reportQuotation s!"Core field {field.getId}"
  let artifact ← elabArtifactLiteral json
  let some program := artifact.core_program
    | throwError "extraction artifact has no Core program"
  match field.getId.toString with
  | "target" => quoteBounded program.target
  | "structures" => quoteBounded program.structures
  | "enumerations" => quoteBounded program.enumerations
  | "constants" => quoteBounded program.constants
  | "functions" => quoteBounded program.functions
  | name => throwError "artifact Core program has no quotable field {name}"

/-- Quote a checked slice of an artifact's parse-node table. Very large parse
    tables are emitted as several independently compiled constants and then
    concatenated, avoiding a monolithic LCNF compilation unit. -/
elab "artifact_parse_nodes% " json:term ", " start:term ", " count:term : term => do
  reportQuotation "parse-node range"
  let artifact ← elabArtifactLiteral json
  let start ← elabNatLiteral start
  let count ← elabNatLiteral count
  unless start + count ≤ artifact.parse_nodes.length do
    throwError "parse-node slice [{start}, {start + count}) exceeds table length {artifact.parse_nodes.length}"
  quoteBounded (artifact.parse_nodes.drop start |>.take count)

/-- Quote the decoded Core program from a standalone extraction artifact.
    Keeping JSON parsing in the elaborator makes later function lookup reduce
    over ordinary Core constructors instead of re-running the JSON decoder. -/
elab "artifact_core_program% " json:term : term => do
  let artifact ← elabArtifactLiteral json
  let some wire := artifact.core_program
    | throwError "extraction artifact has no Core program"
  pure (mkApp (mkConst ``CoreDecode.program) (toExpr wire))

elab "artifact_pack_core_program% " json:term : term => do
  let pack ← elabArtifactPackLiteral json
  let programs ← pack.units.mapM fun artifact => do
    let some wire := artifact.core_program
      | throwError "extraction artifact pack unit has no Core program"
    let quotedWire ← quoteBounded wire
    pure (mkApp (mkConst ``CoreDecode.program) quotedWire)
  let programList := programs.foldr
    (fun program tail => mkAppN (mkConst ``CoreDecode.consProgram) #[program, tail])
    (mkConst ``CoreDecode.emptyPrograms)
  pure (mkApp (mkConst ``CoreDecode.concatPrograms) programList)

/-- Decode and concatenate a pack while elaborating, then quote the resulting
    ordinary Core value.  Unlike `artifact_pack_core_program%`, the generated
    term contains no `CoreDecode.program` or list-fold machinery for the
    kernel to normalize: all wire translation and pack concatenation happen
    before the quotation is installed. -/
elab "artifact_pack_core_program_flat% " json:term : term => do
  reportQuotation "flat Core pack"
  let pack ← elabArtifactPackLiteral json
  let programs ← pack.units.mapM fun artifact => do
    let some wire := artifact.core_program
      | throwError "extraction artifact pack unit has no Core program"
    pure (CoreDecode.program wire)
  quoteBounded (CoreDecode.concatPrograms programs)

/-- Quote the Core programs for every pack unit except the named source.
    This is deliberately a quarantine operation: a unit whose source no
    longer matches the checkout must not remain available through the shared
    program merely because another unit still has a usable artifact. -/
elab "artifact_pack_core_program_except% " json:term ", " path:term : term => do
  let excludedPath ← elabStringLiteral path
  let pack ← elabArtifactPackLiteral json
  let programs ← pack.units.filterMapM fun artifact => do
    let excluded := artifact.sources.any fun source => source.path == excludedPath
    if excluded then
      pure none
    else
      let some wire := artifact.core_program
        | throwError "extraction artifact pack unit has no Core program"
      let quotedWire ← quoteBounded wire
      pure (some (mkApp (mkConst ``CoreDecode.program) quotedWire))
  let programList := programs.foldr
    (fun program tail => mkAppN (mkConst ``CoreDecode.consProgram) #[program, tail])
    (mkConst ``CoreDecode.emptyPrograms)
  pure (mkApp (mkConst ``CoreDecode.concatPrograms) programList)

/-- Elaborate a JSON artifact pack into ordinary constructor data. JSON is an
    interchange format only: proofs and definitional reduction consume the
    quoted `ArtifactPack`, so they do not repeatedly execute the JSON parser. -/
elab "artifact_pack% " json:term : term => do
  pure (toExpr (← elabArtifactPackLiteral json))

/-- Quote one source unit from a pack by its checked source path. Selecting by
    path avoids coupling proofs to incidental pack ordering. -/
elab "artifact_pack_unit% " json:term ", " path:term : term => do
  let (_, artifact) ← elabArtifactPackUnit json path
  -- Large raw traces are quoted separately at the one boundary that needs
  -- them.  Keeping them out of ordinary unit constants prevents unrelated
  -- function/body projections from inheriting thousands of token rows.
  pure (toExpr { artifact with raw_tokens := none })

/-- Quote one complete source unit from a pack.  This is used by independently
compiled unit modules: keeping the module boundary per source prevents a proof
about one unit from loading every artifact in the pack. -/
elab "artifact_pack_unit_full% " json:term ", " path:term : term => do
  let (_, artifact) ← elabArtifactPackUnit json path
  pure (toExpr artifact)

/-- Quote the other artifact fields once while reusing a supplied node list. -/
elab "artifact_pack_unit_reusing_nodes% " json:term ", " path:term ", " nodes:term : term => do
  let (_, artifact) ← elabArtifactPackUnit json path
  let nodesExpr ← elabTermEnsuringType nodes (mkApp (mkConst ``List [Level.zero]) (mkConst ``ParseNode))
  -- Reuse an explicit node expression instead of quoting a second copy. Like
  -- all artifact quotation, this supplies untrusted input to the checkers;
  -- callers must choose the matching unit's tree. No Lean code is evaluated.
  let quoted := toExpr { artifact with parse_nodes := [] }
  unless quoted.isAppOfArity ``Artifact.mk 12 do
    throwError "artifact constructor layout changed"
  pure (mkAppN quoted.getAppFn (quoted.getAppArgs.set! 5 nodesExpr))

/-- Quote only a unit's optional complete raw-token trace. -/
elab "artifact_pack_raw_tokens% " json:term ", " path:term : term => do
  let (_, artifact) ← elabArtifactPackUnit json path
  pure (toExpr artifact.raw_tokens)

/-- Quote one field of a named pack unit.  Large checked units are assembled
from opaque field constants so reducing one checker projection never unfolds
the unit's unrelated parse, Surface, evidence, or Core tables. -/
elab "artifact_pack_unit_field% " json:term ", " path:term ", " field:ident : term => do
  let (_, artifact) ← elabArtifactPackUnit json path
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
  let artifact ← elabArtifactPackUnitAt json expectedPath
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
  let artifact ← elabArtifactPackUnitAt json expectedPath
  quoteFunctionFromArtifact artifact expectedPath expectedName

/-- Quote one Core function from a standalone extraction artifact by its
    checked source path and reconstructed declaration name. -/
elab "artifact_function% " json:term ", " path:term ", " name:term : term => do
  let expectedPath ← elabStringLiteral path
  let expectedName ← elabStringLiteral name
  let artifact ← elabArtifactLiteral json
  quoteFunctionFromArtifact artifact expectedPath expectedName

end Lanius.Extraction
