# Compiler Algorithms

This document summarizes the algorithms currently implemented by the compiler.
It is intentionally implementation-facing: it names the phase owners and data
products that compiler authors must preserve.

## Lexing

The lexer is a parallel DFA pipeline.

Inputs:

- source bytes
- compact DFA transition tables from `tables/lexer_tables.bin`
- token map from DFA states to token kinds
- skip-token kinds for whitespace/comments

Algorithm:

1. mark source-file boundaries for source packs
2. run per-byte DFA local work
3. summarize DFA chunks and apply block prefixes
4. derive token boundary flags
5. run pair prefix scans for token positions
6. compact kept tokens and all tokens
7. build `GpuToken` rows and token file ids

The algorithm is designed to keep source bytes and token rows resident for later
phases. Host readback of tokens is optional and mainly for tests/debugging.

## Parsing

The parser combines LL production work, bracket/structure analysis, tree
recovery, and semantic HIR construction.
See [Parser and HIR](parser.md) for the parser boundary, resident buffer model,
status contract, HIR record families, and syntax-authoring checklist.

Inputs:

- resident `GpuToken` rows and token count
- parser token-kind conversion passes
- precomputed parse tables from `tables/parse_tables.bin`

Algorithm:

1. convert lexer token kinds to parser semantic token kinds
2. compute LL pair production streams
3. pack production streams and projected tree capacity
4. compute bracket layer histograms and pair structure
5. recover parent/subtree/span/previous-sibling tree records
6. classify semantic HIR nodes and compact them
7. build semantic navigation records
8. populate typed HIR arrays for language constructs

The parser does not produce a single pointer-rich AST. It produces parallel
record arrays keyed by tree/HIR node ids. Later GPU phases use those arrays
directly.

Important invariants:

- LL status must be checked before type checking.
- Tree capacity must be sized before HIR passes record.
- Parser scratch buffers may be reused after retained buffer wrappers clone the
  buffers needed by type checking or codegen.
- Token file ids must flow through HIR token position records for source-pack
  diagnostics.

## HIR Record Model

HIR is stored as multiple dense record families rather than enum objects.
See [Parser and HIR](parser.md) for the phase boundary and downstream ownership
rules for these record families.

Examples:

- `hir_kind` identifies each semantic HIR node.
- `hir_token_pos`, `hir_token_end`, and `hir_token_file_id` map nodes back to
  source.
- `hir_item_*` describes modules, imports, functions, structs, enums, traits,
  type aliases, visibility, namespaces, and path spans.
- `hir_type_*` describes type forms, type path leaves, type args, aliases, and
  return types.
- `hir_call_*`, `hir_method_*`, `hir_match_*`, `hir_array_*`, and
  `hir_struct_*` carry construct-specific rows.

When adding syntax, first decide whether it is a new HIR kind, a new field on an
existing record family, or a derived table that belongs in type checking. Do not
push semantic policy into parser passes only because the parser is already
visiting the node.

## Type Checking

The type checker is a staged relation-building pipeline over token, HIR, module,
name, type-instance, call, method, visible-declaration, and predicate records.
See [Resident type checker](type-checker.md) for the cache model, pass-family
ownership, status contract, and checklist for adding a relation.

Major algorithms:

### Name Collection

Name passes collect lexeme spans, radix-sort/deduplicate names, assign ids, and
materialize language names. Names become compact ids used by module, declaration,
method, and path keys.

Use `generated/reference.md` when changing pass fields or shader keys. The
algorithm sections explain phase intent; the generated reference lists the
current pass loader fields, record sites, shader load sites, and status-code
names.

### Module And Import Resolution

Module passes collect module/path/import/declaration records, build sortable
keys, validate duplicate modules/declarations, resolve imports, validate import
cycles, and build import-visible key tables.

Path resolution is split into local paths, imported paths, qualified paths, type
paths, value paths, call paths, enum-unit paths, and match-pattern paths. The
module path state owns sorted key tables, path ids, resolved declaration refs,
status rows, and dispatch args.

### Type Instances And Generics

Type-instance passes collect generic params, const params, type argument rows,
type expression refs, declaration refs, member receiver refs, struct-init field
refs, aggregate access refs, array result refs, and length metadata.

Generic/type argument data is represented as rows and refs rather than recursive
host structures. The current public stride for type-instance arg refs is
`TYPE_INSTANCE_ARG_REF_STRIDE = 4`, meaning the tag and payload ref arrays reserve
four `u32` slots per token-capacity row for later shader passes.

### Calls

Call passes collect callee/arg rows, resolve function calls, match arguments to
parameters, apply row-arg results, infer selected array generic cases, erase
generic params for backend-facing call metadata, and validate aggregate/array
results.

The call pipeline is intentionally revisited after module value-call consumption
and method resolution. Do not assume a single call collection pass is final.

### Methods

Method passes collect declarations, build method keys, resolve method calls, and
thread receiver/method metadata into call/type-instance rows. Receiver type
substitution and member result substitution are late consumers of type-instance
metadata.

### Visible Declarations

Visible declaration passes build structures for lexical/module visibility.
They use row-block sizing and key sorting rather than host maps so later passes
can query visibility on GPU.

### Predicates And Traits

Predicate passes collect trait/impl/method-contract rows and validate
obligations. Predicate status buffers are separate from the main type-check
status so errors can be reduced/applied at the right phase.

## Codegen

Backends consume parser HIR plus type-check retained metadata.
See [Codegen and backends](codegen.md) for the backend boundary, source-pack
planning model, and invariants for adding target behavior.

### x86_64

The x86 backend records ELF generation from HIR and type metadata. Before
recording full backend passes, it measures feature usage to size and select
backend work. It then lowers functions, expressions, calls, arrays, enums,
structs, type refs, visible declarations, and entrypoint information through
GPU passes.

Important inputs:

- parser HIR kind/topology/token records
- item/function/param/statement/expression/call records
- type-check function/call/type-instance metadata
- resolved value/type declarations and statuses
- visible declaration rows
- backend feature summary

### WASM

The WASM backend shares the same frontend and type-check boundary. It currently
fails closed at the backend boundary for unsupported output slices. Keep WASM
diagnostic mapping in sync with x86 where the frontend data path is shared. See
[WASM backend internals](wasm-backend.md) for the recording stages, retained
input groups, resident buffer cache, and status mapping.

## Source-Pack Planning And Execution

Source-pack support is split between planning data structures in `codegen::unit`
and execution APIs in `compiler/public_execution_api.rs` plus
`compiler/gpu_compiler/source_pack_executor.rs`.
See [Source packs, artifacts, and work queues](source-packs.md) for the
persisted preparation stages, artifact-store contract, work-queue records, and
validation boundaries.

The planning layer models frontend units, library units, codegen units, artifact
manifests, shards, batches, dependencies, and link jobs. The executor claims
ready work, validates dependency artifacts, runs frontend/type-check/codegen
operations, and writes artifacts.

For source-pack changes, keep these levels separate:

- source loading and manifest validation
- planning and dependency graph construction
- worker claiming/ready-state logic
- GPU frontend/codegen execution
- artifact writing/linking

## Common Parallel Patterns

These patterns recur throughout the compiler:

- local per-element marking
- block summaries
- prefix scans over block totals
- apply-prefix passes
- radix histogram/scatter/sort
- compact/scatter from flags
- key table construction
- equal-range queries over sorted keys
- indirect dispatch generated by prior GPU passes
- status reduction/application into phase status buffers

When adding a feature, prefer composing one of these patterns over writing a
shader that loops across arbitrary dynamic ranges. If a dynamic range is needed,
make the bound explicit and point status errors at source locations that explain
the user-facing limit. See [Capacity and limits](capacity-and-limits.md) for
the policy that separates storage strides, dispatch tiling, source-pack
chunking, and real language limits.

If the feature adds a new buffer family, status code, shader pass, or large
record struct, regenerate `docs/compiler/generated/reference.md`. That gives the
next compiler author an exact index into the current code rather than relying on
this narrative summary.
