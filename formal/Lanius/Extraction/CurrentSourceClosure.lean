import Lanius.Extraction.SyntaxCheck.Pack

namespace Lanius.Extraction.CurrentSourceClosure

open Lanius.Extraction
open Lanius.Extraction.SyntaxCheck

/-! The compact checker authenticates the exact transitive source closure of
    both native entrypoints.  `compilerExtractorSources` is the union
    of the imports reachable from `compiler.lani` and `extractor.lani`; the
    two smaller lists remain the dedicated frontend/emitter boundaries used by
    the existing artifact-specific theorems.  The list is embedded from the
    checked tree at rebuild time so the runtime artifact and Lean boundary share
    source bytes. Lake does not track `include_str` targets as dependencies, so
    rebuild this module before checking a compact artifact after changing any
    embedded Lanius source; an older `.olean` authenticates older bytes. The
    checker executable also compares these bytes with the checkout before it
    reports acceptance, so a stale build fails closed. -/

def sourceFile (path content : String) : SourceFile :=
  { path, bytes := content.toUTF8.toList.map UInt8.toNat }

def frontendSources : List SourceFile := [
  sourceFile "verified_compiler/src/verified/lexer.lani"
    (include_str "../../../verified_compiler/src/verified/lexer.lani"),
  sourceFile "verified_compiler/src/verified/token_scan.lani"
    (include_str "../../../verified_compiler/src/verified/token_scan.lani"),
  sourceFile "verified_compiler/src/verified/digits.lani"
    (include_str "../../../verified_compiler/src/verified/digits.lani"),
  sourceFile "verified_compiler/src/verified/token.lani"
    (include_str "../../../verified_compiler/src/verified/token.lani"),
  sourceFile "verified_compiler/src/verified/canonical_tokens.lani"
    (include_str "../../../verified_compiler/src/verified/canonical_tokens.lani"),
  sourceFile "verified_compiler/src/verified/decimal.lani"
    (include_str "../../../verified_compiler/src/verified/decimal.lani"),
  sourceFile "verified_compiler/src/verified/number.lani"
    (include_str "../../../verified_compiler/src/verified/number.lani"),
  sourceFile "verified_compiler/src/verified/symbol.lani"
    (include_str "../../../verified_compiler/src/verified/symbol.lani"),
  sourceFile "verified_compiler/src/verified/raw_lexer.lani"
    (include_str "../../../verified_compiler/src/verified/raw_lexer.lani")
]

def emitterSources : List SourceFile := [
  sourceFile "verified_compiler/src/verified/output.lani"
    (include_str "../../../verified_compiler/src/verified/output.lani"),
  sourceFile "verified_compiler/src/verified/certificate_output.lani"
    (include_str "../../../verified_compiler/src/verified/certificate_output.lani"),
  sourceFile "verified_compiler/src/verified/host.lani"
    (include_str "../../../verified_compiler/src/verified/host.lani"),
  sourceFile "verified_compiler/src/backend/frame.lani"
    (include_str "../../../verified_compiler/src/backend/frame.lani"),
  sourceFile "verified_compiler/src/x86/register.lani"
    (include_str "../../../verified_compiler/src/x86/register.lani"),
  sourceFile "verified_compiler/src/x86/encode.lani"
    (include_str "../../../verified_compiler/src/x86/encode.lani"),
  sourceFile "verified_compiler/src/x86/buffer.lani"
    (include_str "../../../verified_compiler/src/x86/buffer.lani")
]

def compilerExtractorSources : List SourceFile := [
  sourceFile "verified_compiler/src/backend/body_reader.lani"
    (include_str "../../../verified_compiler/src/backend/body_reader.lani"),
  sourceFile "verified_compiler/src/backend/call.lani"
    (include_str "../../../verified_compiler/src/backend/call.lani"),
  sourceFile "verified_compiler/src/backend/compile.lani"
    (include_str "../../../verified_compiler/src/backend/compile.lani"),
  sourceFile "verified_compiler/src/backend/constant_index.lani"
    (include_str "../../../verified_compiler/src/backend/constant_index.lani"),
  sourceFile "verified_compiler/src/backend/frame.lani"
    (include_str "../../../verified_compiler/src/backend/frame.lani"),
  sourceFile "verified_compiler/src/backend/function_index.lani"
    (include_str "../../../verified_compiler/src/backend/function_index.lani"),
  sourceFile "verified_compiler/src/backend/image.lani"
    (include_str "../../../verified_compiler/src/backend/image.lani"),
  sourceFile "verified_compiler/src/backend/image_boundary.lani"
    (include_str "../../../verified_compiler/src/backend/image_boundary.lani"),
  sourceFile "verified_compiler/src/backend/index.lani"
    (include_str "../../../verified_compiler/src/backend/index.lani"),
  sourceFile "verified_compiler/src/backend/layout.lani"
    (include_str "../../../verified_compiler/src/backend/layout.lani"),
  sourceFile "verified_compiler/src/backend/layout_index.lani"
    (include_str "../../../verified_compiler/src/backend/layout_index.lani"),
  sourceFile "verified_compiler/src/backend/literal.lani"
    (include_str "../../../verified_compiler/src/backend/literal.lani"),
  sourceFile "verified_compiler/src/backend/local.lani"
    (include_str "../../../verified_compiler/src/backend/local.lani"),
  sourceFile "verified_compiler/src/backend/operation.lani"
    (include_str "../../../verified_compiler/src/backend/operation.lani"),
  sourceFile "verified_compiler/src/backend/parameter.lani"
    (include_str "../../../verified_compiler/src/backend/parameter.lani"),
  sourceFile "verified_compiler/src/backend/program.lani"
    (include_str "../../../verified_compiler/src/backend/program.lani"),
  sourceFile "verified_compiler/src/backend/syntax.lani"
    (include_str "../../../verified_compiler/src/backend/syntax.lani"),
  sourceFile "verified_compiler/src/backend/value.lani"
    (include_str "../../../verified_compiler/src/backend/value.lani"),
  sourceFile "verified_compiler/src/compiler.lani"
    (include_str "../../../verified_compiler/src/compiler.lani"),
  sourceFile "verified_compiler/src/driver/arguments.lani"
    (include_str "../../../verified_compiler/src/driver/arguments.lani"),
  sourceFile "verified_compiler/src/extractor.lani"
    (include_str "../../../verified_compiler/src/extractor.lani"),
  sourceFile "verified_compiler/src/ir/body_catalog.lani"
    (include_str "../../../verified_compiler/src/ir/body_catalog.lani"),
  sourceFile "verified_compiler/src/ir/body_tree.lani"
    (include_str "../../../verified_compiler/src/ir/body_tree.lani"),
  sourceFile "verified_compiler/src/ir/body_events.lani"
    (include_str "../../../verified_compiler/src/ir/body_events.lani"),
  sourceFile "verified_compiler/src/ir/constant_catalog.lani"
    (include_str "../../../verified_compiler/src/ir/constant_catalog.lani"),
  sourceFile "verified_compiler/src/ir/function_catalog.lani"
    (include_str "../../../verified_compiler/src/ir/function_catalog.lani"),
  sourceFile "verified_compiler/src/ir/program.lani"
    (include_str "../../../verified_compiler/src/ir/program.lani"),
  sourceFile "verified_compiler/src/ir/symbol_catalog.lani"
    (include_str "../../../verified_compiler/src/ir/symbol_catalog.lani"),
  sourceFile "verified_compiler/src/ir/type_catalog.lani"
    (include_str "../../../verified_compiler/src/ir/type_catalog.lani"),
  sourceFile "verified_compiler/src/ir/type_ref.lani"
    (include_str "../../../verified_compiler/src/ir/type_ref.lani"),
  sourceFile "verified_compiler/src/lowering/aliases.lani"
    (include_str "../../../verified_compiler/src/lowering/aliases.lani"),
  sourceFile "verified_compiler/src/lowering/allocation.lani"
    (include_str "../../../verified_compiler/src/lowering/allocation.lani"),
  sourceFile "verified_compiler/src/lowering/bodies.lani"
    (include_str "../../../verified_compiler/src/lowering/bodies.lani"),
  sourceFile "verified_compiler/src/lowering/body_context.lani"
    (include_str "../../../verified_compiler/src/lowering/body_context.lani"),
  sourceFile "verified_compiler/src/lowering/body_event_write.lani"
    (include_str "../../../verified_compiler/src/lowering/body_event_write.lani"),
  sourceFile "verified_compiler/src/lowering/body_expression.lani"
    (include_str "../../../verified_compiler/src/lowering/body_expression.lani"),
  sourceFile "verified_compiler/src/lowering/body_lookup.lani"
    (include_str "../../../verified_compiler/src/lowering/body_lookup.lani"),
  sourceFile "verified_compiler/src/lowering/body_statement.lani"
    (include_str "../../../verified_compiler/src/lowering/body_statement.lani"),
  sourceFile "verified_compiler/src/lowering/body_units.lani"
    (include_str "../../../verified_compiler/src/lowering/body_units.lani"),
  sourceFile "verified_compiler/src/lowering/builtin.lani"
    (include_str "../../../verified_compiler/src/lowering/builtin.lani"),
  sourceFile "verified_compiler/src/lowering/constant_catalog.lani"
    (include_str "../../../verified_compiler/src/lowering/constant_catalog.lani"),
  sourceFile "verified_compiler/src/lowering/constant_expression.lani"
    (include_str "../../../verified_compiler/src/lowering/constant_expression.lani"),
  sourceFile "verified_compiler/src/lowering/declarations.lani"
    (include_str "../../../verified_compiler/src/lowering/declarations.lani"),
  sourceFile "verified_compiler/src/lowering/error.lani"
    (include_str "../../../verified_compiler/src/lowering/error.lani"),
  sourceFile "verified_compiler/src/lowering/ir_catalogs.lani"
    (include_str "../../../verified_compiler/src/lowering/ir_catalogs.lani"),
  sourceFile "verified_compiler/src/lowering/ir_names.lani"
    (include_str "../../../verified_compiler/src/lowering/ir_names.lani"),
  sourceFile "verified_compiler/src/lowering/locals.lani"
    (include_str "../../../verified_compiler/src/lowering/locals.lani"),
  sourceFile "verified_compiler/src/lowering/modules.lani"
    (include_str "../../../verified_compiler/src/lowering/modules.lani"),
  sourceFile "verified_compiler/src/lowering/program_transport.lani"
    (include_str "../../../verified_compiler/src/lowering/program_transport.lani"),
  sourceFile "verified_compiler/src/lowering/resolution_catalog.lani"
    (include_str "../../../verified_compiler/src/lowering/resolution_catalog.lani"),
  sourceFile "verified_compiler/src/lowering/signature_index.lani"
    (include_str "../../../verified_compiler/src/lowering/signature_index.lani"),
  sourceFile "verified_compiler/src/lowering/signature_producer.lani"
    (include_str "../../../verified_compiler/src/lowering/signature_producer.lani"),
  sourceFile "verified_compiler/src/lowering/signature_validation.lani"
    (include_str "../../../verified_compiler/src/lowering/signature_validation.lani"),
  sourceFile "verified_compiler/src/lowering/signatures.lani"
    (include_str "../../../verified_compiler/src/lowering/signatures.lani"),
  sourceFile "verified_compiler/src/lowering/string_literal.lani"
    (include_str "../../../verified_compiler/src/lowering/string_literal.lani"),
  sourceFile "verified_compiler/src/lowering/token_names.lani"
    (include_str "../../../verified_compiler/src/lowering/token_names.lani"),
  sourceFile "verified_compiler/src/lowering/transport.lani"
    (include_str "../../../verified_compiler/src/lowering/transport.lani"),
  sourceFile "verified_compiler/src/lowering/types.lani"
    (include_str "../../../verified_compiler/src/lowering/types.lani"),
  sourceFile "verified_compiler/src/lowering/unit_context.lani"
    (include_str "../../../verified_compiler/src/lowering/unit_context.lani"),
  sourceFile "verified_compiler/src/lowering/unit_descriptor.lani"
    (include_str "../../../verified_compiler/src/lowering/unit_descriptor.lani"),
  sourceFile "verified_compiler/src/lowering/units.lani"
    (include_str "../../../verified_compiler/src/lowering/units.lani"),
  sourceFile "verified_compiler/src/lowering/value_catalog.lani"
    (include_str "../../../verified_compiler/src/lowering/value_catalog.lani"),
  sourceFile "verified_compiler/src/lowering/value_collection.lani"
    (include_str "../../../verified_compiler/src/lowering/value_collection.lani"),
  sourceFile "verified_compiler/src/runtime/arguments.lani"
    (include_str "../../../verified_compiler/src/runtime/arguments.lani"),
  sourceFile "verified_compiler/src/runtime/heap.lani"
    (include_str "../../../verified_compiler/src/runtime/heap.lani"),
  sourceFile "verified_compiler/src/runtime/io.lani"
    (include_str "../../../verified_compiler/src/runtime/io.lani"),
  sourceFile "verified_compiler/src/runtime/service.lani"
    (include_str "../../../verified_compiler/src/runtime/service.lani"),
  sourceFile "verified_compiler/src/runtime/string.lani"
    (include_str "../../../verified_compiler/src/runtime/string.lani"),
  sourceFile "verified_compiler/src/verified/ascii.lani"
    (include_str "../../../verified_compiler/src/verified/ascii.lani"),
  sourceFile "verified_compiler/src/verified/byte_io.lani"
    (include_str "../../../verified_compiler/src/verified/byte_io.lani"),
  sourceFile "verified_compiler/src/verified/canonical_tokens.lani"
    (include_str "../../../verified_compiler/src/verified/canonical_tokens.lani"),
  sourceFile "verified_compiler/src/verified/certificate_functions.lani"
    (include_str "../../../verified_compiler/src/verified/certificate_functions.lani"),
  sourceFile "verified_compiler/src/verified/certificate_functions_native.lani"
    (include_str "../../../verified_compiler/src/verified/certificate_functions_native.lani"),
  sourceFile "verified_compiler/src/verified/certificate_output.lani"
    (include_str "../../../verified_compiler/src/verified/certificate_output.lani"),
  sourceFile "verified_compiler/src/verified/certificate_output_native.lani"
    (include_str "../../../verified_compiler/src/verified/certificate_output_native.lani"),
  sourceFile "verified_compiler/src/verified/compact_artifact_output.lani"
    (include_str "../../../verified_compiler/src/verified/compact_artifact_output.lani"),
  sourceFile "verified_compiler/src/verified/core_body.lani"
    (include_str "../../../verified_compiler/src/verified/core_body.lani"),
  sourceFile "verified_compiler/src/verified/core_transport.lani"
    (include_str "../../../verified_compiler/src/verified/core_transport.lani"),
  sourceFile "verified_compiler/src/verified/decimal.lani"
    (include_str "../../../verified_compiler/src/verified/decimal.lani"),
  sourceFile "verified_compiler/src/verified/digits.lani"
    (include_str "../../../verified_compiler/src/verified/digits.lani"),
  sourceFile "verified_compiler/src/verified/extraction.lani"
    (include_str "../../../verified_compiler/src/verified/extraction.lani"),
  sourceFile "verified_compiler/src/verified/grammar.lani"
    (include_str "../../../verified_compiler/src/verified/grammar.lani"),
  sourceFile "verified_compiler/src/verified/host.lani"
    (include_str "../../../verified_compiler/src/verified/host.lani"),
  sourceFile "verified_compiler/src/verified/lexer.lani"
    (include_str "../../../verified_compiler/src/verified/lexer.lani"),
  sourceFile "verified_compiler/src/verified/lean_body.lani"
    (include_str "../../../verified_compiler/src/verified/lean_body.lani"),
  sourceFile "verified_compiler/src/verified/lean_frontend.lani"
    (include_str "../../../verified_compiler/src/verified/lean_frontend.lani"),
  sourceFile "verified_compiler/src/verified/lean_named_types.lani"
    (include_str "../../../verified_compiler/src/verified/lean_named_types.lani"),
  sourceFile "verified_compiler/src/verified/lean_output.lani"
    (include_str "../../../verified_compiler/src/verified/lean_output.lani"),
  sourceFile "verified_compiler/src/verified/lean_program.lani"
    (include_str "../../../verified_compiler/src/verified/lean_program.lani"),
  sourceFile "verified_compiler/src/verified/lean_syntax.lani"
    (include_str "../../../verified_compiler/src/verified/lean_syntax.lani"),
  sourceFile "verified_compiler/src/verified/lean_typed_body.lani"
    (include_str "../../../verified_compiler/src/verified/lean_typed_body.lani"),
  sourceFile "verified_compiler/src/verified/number.lani"
    (include_str "../../../verified_compiler/src/verified/number.lani"),
  sourceFile "verified_compiler/src/verified/output.lani"
    (include_str "../../../verified_compiler/src/verified/output.lani"),
  sourceFile "verified_compiler/src/verified/parse_tree.lani"
    (include_str "../../../verified_compiler/src/verified/parse_tree.lani"),
  sourceFile "verified_compiler/src/verified/parser.lani"
    (include_str "../../../verified_compiler/src/verified/parser.lani"),
  sourceFile "verified_compiler/src/verified/production.lani"
    (include_str "../../../verified_compiler/src/verified/production.lani"),
  sourceFile "verified_compiler/src/verified/raw_lexer.lani"
    (include_str "../../../verified_compiler/src/verified/raw_lexer.lani"),
  sourceFile "verified_compiler/src/verified/semantic_tokens.lani"
    (include_str "../../../verified_compiler/src/verified/semantic_tokens.lani"),
  sourceFile "verified_compiler/src/verified/surface_atoms.lani"
    (include_str "../../../verified_compiler/src/verified/surface_atoms.lani"),
  sourceFile "verified_compiler/src/verified/surface_declaration.lani"
    (include_str "../../../verified_compiler/src/verified/surface_declaration.lani"),
  sourceFile "verified_compiler/src/verified/surface_expr.lani"
    (include_str "../../../verified_compiler/src/verified/surface_expr.lani"),
  sourceFile "verified_compiler/src/verified/surface_path.lani"
    (include_str "../../../verified_compiler/src/verified/surface_path.lani"),
  sourceFile "verified_compiler/src/verified/surface_statement.lani"
    (include_str "../../../verified_compiler/src/verified/surface_statement.lani"),
  sourceFile "verified_compiler/src/verified/surface_type.lani"
    (include_str "../../../verified_compiler/src/verified/surface_type.lani"),
  sourceFile "verified_compiler/src/verified/symbol.lani"
    (include_str "../../../verified_compiler/src/verified/symbol.lani"),
  sourceFile "verified_compiler/src/verified/syntax_tree.lani"
    (include_str "../../../verified_compiler/src/verified/syntax_tree.lani"),
  sourceFile "verified_compiler/src/verified/token.lani"
    (include_str "../../../verified_compiler/src/verified/token.lani"),
  sourceFile "verified_compiler/src/verified/token_scan.lani"
    (include_str "../../../verified_compiler/src/verified/token_scan.lani"),
  sourceFile "verified_compiler/src/verified/utf8.lani"
    (include_str "../../../verified_compiler/src/verified/utf8.lani"),
  sourceFile "verified_compiler/src/x86/buffer.lani"
    (include_str "../../../verified_compiler/src/x86/buffer.lani"),
  sourceFile "verified_compiler/src/x86/control.lani"
    (include_str "../../../verified_compiler/src/x86/control.lani"),
  sourceFile "verified_compiler/src/x86/encode.lani"
    (include_str "../../../verified_compiler/src/x86/encode.lani"),
  sourceFile "verified_compiler/src/x86/register.lani"
    (include_str "../../../verified_compiler/src/x86/register.lani")
]

/-! Keep each entrypoint's exact transitive import closure in source order. -/
private def withoutPaths (excluded : List String) (files : List SourceFile) : List SourceFile :=
  files.filter (fun file => file.path ∉ excluded)

def compilerSources : List SourceFile :=
  withoutPaths [
    "verified_compiler/src/extractor.lani",
    "verified_compiler/src/verified/lean_body.lani",
    "verified_compiler/src/verified/lean_frontend.lani",
    "verified_compiler/src/verified/lean_named_types.lani",
    "verified_compiler/src/verified/lean_output.lani",
    "verified_compiler/src/verified/lean_program.lani",
    "verified_compiler/src/verified/lean_syntax.lani",
    "verified_compiler/src/verified/lean_typed_body.lani"
  ] compilerExtractorSources

def extractorSources : List SourceFile :=
  withoutPaths [
    "verified_compiler/src/backend/body_reader.lani",
    "verified_compiler/src/backend/call.lani",
    "verified_compiler/src/backend/compile.lani",
    "verified_compiler/src/backend/constant_index.lani",
    "verified_compiler/src/backend/function_index.lani",
    "verified_compiler/src/backend/image.lani",
    "verified_compiler/src/backend/image_boundary.lani",
    "verified_compiler/src/backend/index.lani",
    "verified_compiler/src/backend/frame.lani",
    "verified_compiler/src/backend/layout.lani",
    "verified_compiler/src/backend/layout_index.lani",
    "verified_compiler/src/backend/literal.lani",
    "verified_compiler/src/backend/local.lani",
    "verified_compiler/src/backend/operation.lani",
    "verified_compiler/src/backend/parameter.lani",
    "verified_compiler/src/backend/program.lani",
    "verified_compiler/src/backend/value.lani",
    "verified_compiler/src/compiler.lani",
    "verified_compiler/src/runtime/string.lani",
    "verified_compiler/src/verified/certificate_functions.lani",
    "verified_compiler/src/verified/certificate_functions_native.lani",
    "verified_compiler/src/verified/certificate_output.lani",
    "verified_compiler/src/verified/certificate_output_native.lani"
  ] compilerExtractorSources

/-! `sources` is the extractor-facing compatibility alias.  The union remains
    available above for callers that authenticate the combined source inventory. -/
def sources : List SourceFile := extractorSources

def checkCompiler (encoded : String) :
    Except PackCheckStage (CheckedSourcePack encoded compilerSources) :=
  checkCompactSourcePack encoded compilerSources

def checkExtractor (encoded : String) :
    Except PackCheckStage (CheckedSourcePack encoded extractorSources) :=
  checkCompactSourcePack encoded extractorSources

def check (encoded : String) :
    Except PackCheckStage (CheckedSourcePack encoded sources) :=
  checkExtractor encoded

def checkFrontend (encoded : String) :
    Except PackCheckStage (CheckedSourcePack encoded frontendSources) :=
  checkCompactSourcePack encoded frontendSources

theorem check_sound {encoded : String} {checked : CheckedSourcePack encoded sources}
    (accepted : check encoded = .ok checked) :
    decodeCompactPack? encoded = some checked.compact.pack ∧
      checked.compact.pack.schema_version = schemaVersion ∧
      compactPackSources checked.compact.pack = sources ∧
      UnitsValid checked.compact.pack.units := by
  exact SyntaxCheck.checkCompactSourcePack_sound accepted

theorem check_compiler_sound {encoded : String}
    {checked : CheckedSourcePack encoded compilerSources}
    (accepted : checkCompiler encoded = .ok checked) :
    decodeCompactPack? encoded = some checked.compact.pack ∧
      checked.compact.pack.schema_version = schemaVersion ∧
      compactPackSources checked.compact.pack = compilerSources ∧
      UnitsValid checked.compact.pack.units := by
  exact SyntaxCheck.checkCompactSourcePack_sound accepted

theorem check_extractor_sound {encoded : String}
    {checked : CheckedSourcePack encoded extractorSources}
    (accepted : checkExtractor encoded = .ok checked) :
    decodeCompactPack? encoded = some checked.compact.pack ∧
      checked.compact.pack.schema_version = schemaVersion ∧
      compactPackSources checked.compact.pack = extractorSources ∧
      UnitsValid checked.compact.pack.units := by
  exact SyntaxCheck.checkCompactSourcePack_sound accepted

theorem check_frontend_sound {encoded : String}
    {checked : CheckedSourcePack encoded frontendSources}
    (accepted : checkFrontend encoded = .ok checked) :
    decodeCompactPack? encoded = some checked.compact.pack ∧
      checked.compact.pack.schema_version = schemaVersion ∧
      compactPackSources checked.compact.pack = frontendSources ∧
      UnitsValid checked.compact.pack.units := by
  exact SyntaxCheck.checkCompactSourcePack_sound accepted

end Lanius.Extraction.CurrentSourceClosure
