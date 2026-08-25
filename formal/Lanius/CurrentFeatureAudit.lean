import Lanius.DeclarationFunctionality
import Lanius.RuntimeBindings

namespace Lanius.CurrentFeatureAudit

open Lanius

/-- Primitive declaration names materialized by the current compiler. This
    list is an audit snapshot of `type_checker/params.rs`, kept beside the
    semantics so a compiler-language-table change has an explicit review
    point. -/
def compilerPrimitiveTypeNames : List Surface.Name := [
  "bool", "i8", "i16", "i32", "i64", "isize",
  "u8", "u16", "u32", "u64", "usize",
  "f32", "f64", "char", "str", "ptr"
]

/-- Intrinsic spellings materialized by the current compiler. `print` and
    `print_i32` deliberately denote the same semantic operation. -/
def compilerIntrinsicNames : List (Surface.Name × SurfaceElaboration.BuiltinIntrinsic) := [
  ("assert", .assert),
  ("print", .printI32),
  ("print_i32", .printI32),
  ("i32_array_data_ptr", .i32ArrayDataPtr)
]

/-- Exact symbol table snapshot from `type_checker/params.rs`. Unlike the
    declaration table, this also contains external names, the wildcard marker,
    and the canonical range-path segments used by compiler passes. -/
def compilerLanguageSymbols : List Surface.Name := [
  "main", "assert", "print", "bool", "i8", "i16", "i32", "i64", "isize",
  "u8", "u16", "u32", "u64", "usize", "f32", "f64", "char", "str",
  "print_i32", "_", "open_read_path", "open_write_path", "read_i32",
  "write_text", "write_i32", "write_byte", "write_newline", "close_file",
  "i32_to_f32", "exit", "secure_u32", "alloc", "dealloc", "argc",
  "arg_len", "arg_read", "unix_seconds", "current_dir_read", "var_count",
  "var_key_len", "var_key_read", "var_len", "var_read", "close", "read",
  "write", "open_read", "open_write", "open_append", "write_stdout",
  "write_stderr", "read_stdin", "i32_array_data_ptr", "fill_secure_bytes",
  "remove_file", "create_dir", "remove_dir", "rename", "monotonic_read",
  "system_read", "sleep_ms_i32", "realloc", "alloc_failed", "core", "range",
  "Range", "RangeInclusive", "ptr"
]

def compilerStructuralSymbols : List Surface.Name :=
  ["_", "core", "range", "Range", "RangeInclusive"]

/-- Snapshot identity for the grammar audited by this formalization. Lean does
    not make the compiler grammar file its semantic definition; the digest and
    counts instead provide an explicit review point when that source changes. -/
def auditedGrammarSha256 : String :=
  "d9cc4b72b3dc8373ba5ea6d12f4bf0cd8baf5956b03010d76ebff1a1a6e06976"

def auditedGrammarProductionCount : Nat := 290
def auditedGrammarTaggedProductionCount : Nat := 276
def auditedGrammarNonterminalCount : Nat := 136

/-- The only untagged productions are structural forwarding boundaries. The
    expression entries correspond exactly to the indexed levels in
    `ConcreteSyntax`; `file` is owned by `ConcreteProgramSyntax`. -/
def auditedGrammarForwardingNonterminals : List String := [
  "file", "expr", "assign", "orexpr", "andexpr", "bit_or", "bit_xor",
  "bit_and", "equality", "compare", "shift", "add", "mul", "postfix"
]

/-- Canonical nominal types that the current semantic-artifact shader accepts
    as path-valued `for` iterables. This is an audit snapshot of
    `semantic/artifact/01b_array_index_refs.slang`; structural lookalikes are
    deliberately absent. -/
def compilerNamedRangeTypePaths : List Surface.Path := [
  SurfaceElaboration.coreRangeTypePath,
  SurfaceElaboration.coreRangeInclusiveTypePath
]

def builtinPath (name : Surface.Name) : Surface.Path := {
  segments := [.mk name []]
}

def primitiveTypesCovered? : Bool :=
  compilerPrimitiveTypeNames.all fun name =>
    (Elaboration.builtinScalar? name).isSome

def intrinsicNamesCovered? : Bool :=
  compilerIntrinsicNames.all fun entry =>
    decide (SurfaceElaboration.builtinIntrinsic? (builtinPath entry.1) =
      some entry.2)

def compilerLanguageSymbolCovered? (name : Surface.Name) : Bool :=
  decide (name = "main") ||
    compilerPrimitiveTypeNames.contains name ||
    (compilerIntrinsicNames.map (·.1)).contains name ||
    (RuntimeBindings.canonicalExternalBindings.map (·.name)).contains name ||
    compilerStructuralSymbols.contains name

def compilerLanguageSymbolsCovered? : Bool :=
  compilerLanguageSymbols.all compilerLanguageSymbolCovered?

def preMaterializedExternalSymbols : List Surface.Name :=
  compilerLanguageSymbols.filter fun name =>
    !(decide (name = "main") ||
      compilerPrimitiveTypeNames.contains name ||
      (compilerIntrinsicNames.map (·.1)).contains name ||
      compilerStructuralSymbols.contains name)

/-- Every name that the compiler eagerly materializes as an external symbol is
    in the canonical binding catalog. The converse is intentionally false:
    unavailable network/thread/GPU declarations remain ordinary stdlib source
    names and do not need daemon-global symbol slots. -/
def preMaterializedExternalSymbolsCanonical? : Bool :=
  preMaterializedExternalSymbols.all fun name =>
    (RuntimeBindings.canonicalExternalBindings.map (·.name)).contains name

theorem compiler_primitive_type_count :
    compilerPrimitiveTypeNames.length = 16 := by
  decide

theorem compiler_primitive_types_covered : primitiveTypesCovered? = true := by
  decide

theorem compiler_intrinsic_name_count : compilerIntrinsicNames.length = 4 := by
  decide

theorem compiler_intrinsic_names_covered : intrinsicNamesCovered? = true := by
  decide

theorem compiler_language_symbol_count : compilerLanguageSymbols.length = 68 := by
  decide

theorem compiler_language_symbols_distinct : compilerLanguageSymbols.Nodup := by
  decide

theorem compiler_language_symbols_covered :
    compilerLanguageSymbolsCovered? = true := by
  decide

theorem pre_materialized_external_symbols_canonical :
    preMaterializedExternalSymbolsCanonical? = true := by
  decide

theorem pre_materialized_external_symbol_count :
    preMaterializedExternalSymbols.length = 42 := by
  decide

theorem pre_materialized_external_symbols_distinct :
    preMaterializedExternalSymbols.Nodup := by
  decide

theorem audited_grammar_digest_length : auditedGrammarSha256.length = 64 := by
  decide

theorem audited_grammar_forwarding_count :
    auditedGrammarForwardingNonterminals.length = 14 := by
  decide

theorem audited_grammar_forwarding_distinct :
    auditedGrammarForwardingNonterminals.Nodup := by
  decide

theorem audited_grammar_production_partition :
    auditedGrammarTaggedProductionCount +
      auditedGrammarForwardingNonterminals.length =
      auditedGrammarProductionCount := by
  decide

theorem compiler_named_range_type_path_count :
    compilerNamedRangeTypePaths.length = 2 := by
  decide

theorem compiler_named_range_type_paths_exact :
    compilerNamedRangeTypePaths = [
      { segments := [.mk "core" [], .mk "range" [], .mk "Range" []] },
      { segments := [.mk "core" [], .mk "range" [], .mk "RangeInclusive" []] }
    ] := by
  rfl

/-- One entrypoint, four intrinsic spellings, and sixteen primitive types are
    the current compiler's 21 materialized language declarations. -/
theorem compiler_language_declaration_count :
    1 + compilerIntrinsicNames.length + compilerPrimitiveTypeNames.length = 21 := by
  decide

theorem canonical_external_binding_count :
    RuntimeBindings.canonicalExternalBindings.length = 66 := by
  decide

end Lanius.CurrentFeatureAudit
