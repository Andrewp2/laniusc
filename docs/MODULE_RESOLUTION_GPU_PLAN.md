# GPU Module Resolution Plan

This plan advances `stdlib/PLAN.md` by making `module`, `import`, and `::`
resolution a GPU-resident compiler feature instead of a CPU source expansion
feature.

## Current Evidence

`stdlib/PLAN.md` and `stdlib/LANGUAGE_REQUIREMENTS.md` set the current boundary:
stdlib module files are source seeds, imports are explicit in the desired model,
and the old CPU parser/import/type-alias/precheck path has been removed from the
normal compiler pipeline. `src/compiler.rs` now keeps `prepare_source_for_gpu*`
as pass-through source loading; it does not expand imports, aliases, modules, or
generic calls before GPU lexing, parsing, type checking, or WASM codegen.

What parses today:

- `grammar/lanius.bnf` has grammar productions for `module path;`,
  `import path;`, `import "path";`, `path` as `path_segment (:: path_segment)*`,
  qualified type expressions, qualified primary expressions, qualified patterns,
  generic type arguments, structs, enums, traits, impls, constants, and type
  aliases.
- `tests/parser_tree.rs` has LL(1) table acceptance for
  `module core::numbers; import core::i32; import "stdlib/bool.lani";`.
- `tests/parser_tree.rs` has LL(1) table acceptance for namespaced paths in type
  positions, value-call positions, struct literal heads, and match patterns:
  `core::option::Option<i32>`, `core::math::add_one(1)`,
  `core::point::Point { ... }`, and `core::option::Some(inner)`.
- The GPU parser/HIR path already classifies current direct-HIR nodes such as
  functions, params, types, lets, returns, consts, enums, structs, struct
  literals, and type aliases in `shaders/parser/direct_hir.slang`,
  `shaders/parser/hir_nodes.slang`, and `src/parser/gpu/passes/hir_nodes.rs`.

What GPU syntax accepts and rejects today:

- `tests/parser_tree.rs` requires `check_tokens_on_gpu` to accept one leading
  `module path;` declaration as source metadata.
- `tests/parser_tree.rs` requires `check_tokens_on_gpu` to accept leading
  `import path;` and `import "path";` declarations after the optional module
  declaration as syntax metadata only.
- `tests/parser_tree.rs` requires stdlib module seed files such as
  `stdlib/core/i32.lani`, `stdlib/core/bool.lani`, and
  `stdlib/test/assert.lani` to accept that leading module metadata.
- `tests/parser_tree.rs` requires `check_tokens_on_gpu` to reject duplicate
  module declarations, non-leading module declarations, and non-leading imports
  until GPU module resolution exists.
- `tests/parser_tree.rs` requires qualified value paths, including non-call
  paths such as `core::i32::MIN`, to pass GPU syntax as HIR evidence. Semantic
  resolution remains a GPU type-checker responsibility.

What GPU HIR preserves today:

- `shaders/parser/direct_hir.slang`, `shaders/parser/hir_nodes.slang`, and
  `src/parser/gpu/passes/hir_nodes.rs` now define `HIR_MODULE_ITEM`,
  `HIR_IMPORT_ITEM`, and `HIR_PATH_EXPR`.
- LL(1) parser tests preserve module/import/path evidence for
  `module core::numbers; import core::i32;` and a qualified value path head
  without making imports resolve or making external qualified value paths pass
  type checking.
- The LL(1) parser tree path now derives a parser-owned HIR item-field metadata
  slice from production ids plus parent/grandparent ancestry. It records
  top-level module, import, const, fn, extern fn, struct, enum, and type-alias
  item kind, name/path tokens, namespace, visibility, and file id, while
  excluding reused `fn_item` productions inside impl methods. This is structural
  AST/HIR metadata. The current type-checker module/import foundation consumes
  it only to build GPU-resident path/module/import/declaration records, sorted
  module keys, duplicate-module status, and import-target module ids. The
  earlier scan-based resolver and the later hash/prefix-scan metadata slice
  were both deleted because neither implemented the paper-style
  sort/deduplicate/lookup strategy for semantic names. Import path-vs-string
  target kind still comes from the parser import-tail production. Path imports
  now resolve only against explicitly supplied source-pack modules; string
  imports still fail in the GPU resolver because host-driven import loading is
  not implemented.
- The path evidence is span metadata only: tests assert that `HIR_PATH_EXPR`
  covers complete token ranges such as `core::numbers`, `core::i32`, and
  `core::i32::abs`. Module declarations and import paths can now flow through a
  sorted module-key lookup to produce import-target module ids, and through a
  per-namespace GPU path-resolution checkpoint that writes declaration id and
  status arrays. The first consumer bridge projects resolved type declarations
  into `module_type_path_type`, so same-module qualified struct/enum type paths
  can pass through the existing type-expression code without a token-level
  qualified-path shortcut. A fail-closed value-path status bridge now marks HIR
  value-path heads through parse-tree relationships and projects
  `resolved_value_status` into `module_value_path_status`; regular function
  calls and top-level consts now have declaration-consuming HIR value
  consumers, while general qualified values remain blocked.
- `type_check_modules_00_mark_records.slang` and
  `type_check_modules_01_scatter_paths.slang` now exist as pre-resolution GPU
  metadata shaders and are scheduled by the resident type checker after name id
  assignment. They mark parser-owned module, import, declaration, and path
  candidates, prefix-scan path flags, then scatter compact path spans and path
  segment name ids from `name_id_by_token`. They deliberately do not perform
  module lookup, import resolution, declaration lookup, visibility checks,
  same-source shortcuts, or hash-only lookup.
- The resident type checker now schedules the name extraction and bounded radix
  checkpoint: mark lexemes, prefix-scan, scatter compact name spans, run stable
  byte-radix scatter passes, deduplicate adjacent sorted spans by byte equality,
  scan run heads, and assign prefix-derived name ids. Module/import record
  extraction, module-key sorting, duplicate validation, import path lookup,
  namespace-specific declaration lookup, and the type-path projection consume
  those ids now. This is still incomplete: it rejects names beyond the current
  radix byte/block bounds and only connects regular qualified function calls and
  top-level constants through HIR value consumers; general qualified value paths
  remain blocked.
- Direct HIR classifies module/import item heads and qualified value path heads
  as structured records, while suppressing extra value-path tail identifier
  uses. `HIR_PATH_EXPR` segment records feed sorted module/import/declaration
  tables; same-module qualified type paths can now project back to struct/enum
  type codes. Regular qualified function calls are consumed from
  `resolved_value_decl` by a HIR call-context consumer that writes the existing
  call result arrays at the path head without inspecting source text or token
  hashes. Top-level qualified constants and one-segment constants made visible
  by path imports consume `resolved_value_decl` after declaration types are
  available. General qualified value paths still reject unless a dedicated HIR
  consumer clears the fail-closed status.
  The older token-segment `::` special-case rejection was deleted so it cannot
  be mistaken for a resolver.

What GPU type checking accepts and rejects today:

- `tests/type_checker_modules.rs` requires leading `module path;` metadata to
  pass GPU type checking as metadata, and requires path imports to resolve only
  through the GPU module-key lookup when the imported module is explicitly present
  in the source pack.
- `tests/type_checker_modules.rs` requires same-module qualified struct/enum type
  paths such as `app::main::Point`, regular qualified function calls such as
  `app::helper()`, and top-level qualified constants such as `app::LIMIT` to
  pass through resolver arrays, while wrong-module, unresolved, non-function,
  and general qualified value paths still fail with `CompileError::GpuTypeCheck`.
- Deleted Misleading Slice: `type_check_names_00_hash.slang`,
  `type_check_modules_00_clear.slang`, `type_check_modules_01_dense_scan.slang`,
  `type_check_modules_02_dense_scatter.slang`,
  `type_check_modules_02b_dense_scatter_imports.slang`,
  `type_check_modules_02c_dense_scatter_decls.slang`, and
  `type_check_modules_03_attach_ids.slang` are intentionally absent. They were
  not a resolver: they assigned dense records and path hashes without sorting,
  deduplicating lexemes into stable name ids, validating duplicates, resolving
  imports by lookup, or producing declaration visibility. Keeping them made the
  type checker look more complete than it was.
- Existing value visibility is token-local: `type_check_visible_02_scatter.slang`
  walks earlier tokens in scope, compares identifier text, encodes
  `visible_decl`, and later passes decode `visible_type`. Struct/enum/function
  lookup helpers scan all tokens by unqualified text. This is useful evidence for
  current semantics, but it is not an acceptable module implementation shape.

## GPU-Resident Design

The implementation should add a module-resolution stage after LL(1) tree/HIR
construction and before the existing visible/type/call passes. The host may read source
files and allocate/copy source blobs, but it must not parse, expand imports,
resolve paths, or decide declarations.

### Source Pack Input

Represent the compilation input as a source pack:

- `source_bytes`: concatenated bytes for every loaded source file.
- `source_file_start`, `source_file_len`: one record per file.
- `source_file_path_hash` and optional path byte spans: debug identity only, not
  semantic module identity.
- `token_file_id`: emitted by GPU lexing or by a GPU post-pass when lexing is
  initially per file.
- `token_global_index`: compacted token index across the whole source pack.

The CPU can discover candidate files from an explicit package/root list or a
fixed stdlib manifest, then upload bytes. It cannot implement import closure by
source rewriting. The semantic module identity comes from GPU-parsed
`module a::b;` declarations, not from host path names.

Current groundwork: the GPU lexer path now exposes `source_file_count`,
`source_file_start`, `source_file_len`, and `token_file_id` buffers. The normal
single-source path uploads one file. The explicit source-pack lexer path can
upload multiple already-supplied source strings, resets the DFA at GPU-visible
file starts, clamps token starts to the containing file after skipped trivia, and
writes `token_file_id` on GPU. The parser syntax checker consumes that sideband
to validate leading `module` and `import` metadata per file. The compiler now
also exposes explicit source-pack type checking that records the resident LL(1)
tree/HIR and type-check passes against source-pack buffers. Module headers now
pass as GPU metadata, path imports resolve only against explicitly supplied
source-pack modules, and the resolver foundation uses paper-style name
interning, sorting, deduplication, module-key lookup, import-to-module lookup,
type-path projection, and regular qualified function-call consumption. This
groundwork does not load imports, discover files from module declarations, or
make general qualified value paths pass. Top-level qualified constants are only
accepted through the resolver/const-consumer bridge when the declaring module is
explicitly present in the source pack. The normal compiler now uses the LL(1)
tree/HIR path, which
receives the lexer-produced `token_file_id` sideband, validates it during GPU
syntax checking, and feeds it into LL(1) HIR ownership metadata. The older
direct-HIR helper still mirrors the same sideband, but it is not the semantic
path to extend.

### Interned Names And Path Spans

Add GPU buffers that convert token text into stable integer keys:

- `name_id[token]`: dense identifier id assigned by sorting identifier/string
  lexemes and deduplicating equal byte spans, following the semantic-analysis
  paper's name extraction strategy.
- `name_hash[token]` and `name_len[token]`: optional sort/lookup accelerators;
  hash equality is never sufficient without byte collision checks.
- `path_start[path_id]`, `path_len[path_id]`: token span for every `path`.
- `path_segment_count[path_id]`.
- `path_segment_name_id[path_segment_slot]`.
- `path_segment_token[path_segment_slot]`.
- `path_key[path_id]`: ordered segment-key record for radix sorting.

Build these with stable partitioning, GPU-friendly radix sort, adjacent
deduplication, prefix sums, and scatter/gather over parser-owned AST/HIR path
spans. Use byte equality only as a collision check after candidate matches;
never repeatedly scan arbitrary source text inside every resolver.

### Modules

Create module declarations from `module path;` items:

- `module_decl_file[file_id]`: path id for the file's declaration, or an implicit
  root module path for root-only legacy inputs during transition.
- `module_record_id[file_id]`: dense module id from a prefix scan over valid
  declarations.
- packed module records containing path hash, path span, and file id.

Validate on GPU by sorting `(module path hash, module_id)`, comparing adjacent
records with segment-by-segment collision checks, and rejecting duplicate module
paths. A file can have at most one `module` declaration; the declaration must be
before non-import items in the same file.

### Imports

Create import records from `import path;`:

- `import_module_id[import_id]`: enclosing module.
- `import_path_id[import_id]`.
- `import_kind[import_id]`: whole-module import in the first slice; alias/glob
  can be separate later.
- `import_target_module_id[import_id]`: resolved by sorted lookup against module
  path keys.
- `import_status[import_id]`: ok, duplicate, unresolved, self-cycle, unsupported
  string import.

Path imports should not splice source into the caller. They make exported
declarations from the target module visible to the importing module. String
imports should stay rejected in the first slice unless they are defined as a
package-source lookup whose target file is already in the uploaded source pack
and whose module declaration resolves normally.

### Declarations

Extract top-level declarations into a declaration table:

- `decl_id`: dense id from top-level declaration flags.
- `decl_module_id`.
- declaration name id, declaration name token, and declaration name length.
- `decl_kind`: const, fn, extern fn, struct, enum, enum variant, type alias
  later, trait/impl later.
- declaration visibility: private or public.
- declaration HIR node, token start, and token end.
- `decl_type_code` or `decl_type_record_id` for type declarations.

For enum variants, store both the variant declaration and the parent enum
declaration so qualified constructor lookup can resolve
`core::option::Some` to the variant and type checking can still know the enum.

Validate duplicates with radix sort over
`(decl_module_id, decl_namespace, decl_name_id)`. The name ids already come
from byte-equality-checked GPU name interning, so declaration-key equality can
compare integer ids directly. Keep type/value namespaces separate so a type and
function can share a spelling if the language permits it.

### Qualified Type Paths

Represent every type path as a path id. Resolution cases:

- One segment: primitive, generic parameter, local module type declaration, then
  imported public type declaration.
- Multiple segments: split at the last segment. Resolve the prefix path as a
  module path, either absolute from package root or imported/visible according to
  the chosen import rule. Resolve the final segment in that module's type
  namespace.

Implementation should use sorted lookup tables:

- `module_key_to_module_id`: sorted by full module path.
- `decl_type_key_to_decl_id`: sorted by `(module_id, name_id)`.
- `import_visible_type_key`: sorted/scattered from each importing module's
  imports for unqualified imported lookup.

`type_code_for_type_expr` should stop scanning all tokens for struct/enum names
and instead consume resolver outputs. The current path-resolution checkpoint
writes `resolved_type_decl[path_id]` and `resolved_type_status[path_id]` from
sorted module keys, `decl_type_key_to_decl_id`, and
`import_visible_type_key_to_decl_id`. A narrow GPU projection now writes
`module_type_path_type[token]` and `module_type_path_status[token]` from those
arrays so existing type-expression consumers can accept same-module qualified
struct/enum type paths and reject unresolved qualified type paths without
inventing token-level `::` cases. Existing primitive and generic parameter
paths can remain fast local cases while the remaining consumers migrate.

### Qualified Value Paths

Qualified value paths should be HIR-visible, not blocked in syntax. Add
`HIR_PATH_EXPR` or encode `HIR_NAME_EXPR` with `path_id` metadata so `a::b::c`
is a single value-use record rather than three independent identifiers.

Resolution cases:

- One segment: existing lexical locals/params/consts, builtins, local module
  functions/consts/enum variants, then imported public values.
- Multiple segments: resolve prefix module path, then resolve final segment in
  that module's value namespace.

First array checkpoint outputs:

- `resolved_value_decl[path_id or use_id]`.
- `resolved_value_status[path_id or use_id]`.

This value namespace checkpoint reads sorted module keys,
`decl_value_key_to_decl_id`, and `import_visible_value_key_to_decl_id`. It does
not write `resolved_call_decl`, `visible_decl`, `call_fn_index`, or
`call_return_type`; qualified value paths remain fail-closed until downstream
visible/type/call consumers use the arrays. The current HIR value consumers
handle resolved regular function calls, top-level constants, and local or
qualified unit enum variants. Unit variants use the enum-variant declaration plus
`decl_parent_type_decl` so type checking can publish the parent enum type without
looking at token text. Payload and generic enum constructors should use the
resolved enum-variant declaration too, but remain blocked until variant payload
metadata is available as a GPU declaration artifact.

Member access (`value.field`) stays separate from module paths (`module::name`).
Do not lower `::` to `.` or reuse struct field lookup for modules.

### Pass Shape

The new pass family should be array-oriented:

1. Mark module/import/path/declaration/use candidates from HIR/token arrays.
2. Prefix-scan candidate flags to allocate dense records.
3. Scatter records into module, import, declaration, path, and use buffers.
4. Radix-sort lookup keys.
5. Resolve module paths and declaration paths with parallel binary search or
   sort-merge joins.
6. Validate duplicates, unresolved imports, private cross-module use, and
   ambiguous imports in the consumer namespace that needs that status, rather
   than globally reducing both type and value path namespaces.
7. Feed resolved declaration/type outputs into the existing visible/type/call
   passes, then remove the old unqualified all-token scans once parity exists.

This matches the extracted paper text in
`docs/ParallelLexingParsingSemanticAnalysis.md`: semantic features should be GPU
arrays, scans, scatters, sorts, and lookup tables over inverted trees/HIR, not
ad hoc recursive CPU structures or source rewrites.

## Current Syntax-Metadata Slice

The GPU syntax path now accepts one leading `module path;` declaration followed
by leading `import path;` or `import "path";` declarations. These records are
metadata only: no file is loaded, no source is spliced, no cross-file namespace
is built by the host. Qualified value paths, including non-call paths such as
`core::i32::MIN`, can pass syntax as HIR evidence. GPU type checking accepts
regular qualified function calls, top-level qualified constants, local or
qualified unit enum variants, and bounded contextual local or qualified generic
enum constructors when the GPU module/import resolver produces an OK declaration
and the matching HIR consumer identifies that declaration in its use context.
Unresolved module prefixes, missing qualified callees/constants/variants,
non-function call targets, non-constructor symbolic generic enum returns,
trait methods, broad generic callees, and general qualified values still reject.
Bounded module-qualified generic helpers such as `core::option::unwrap_or(value,
fallback)` can type-check when the HIR call consumer infers the scalar return
from literal or annotated local arguments using GPU type-ref metadata; this is
not full monomorphization or package loading.
Bounded module-form inherent method calls can type-check when the receiver is
either an annotated concrete type ref or a GPU-resolved call result with a
concrete `fn_return_ref_*`, as in `core::range::range_i32(1, 4).start()`.

## First Real Resolver Slice Checklist

Goal: one source pack can contain multiple module-declared files, path imports,
qualified type paths, and qualified value paths for public top-level consts,
functions, structs, enums, enum variants, bounded inherent method calls, and
bounded scalar type aliases. No string imports, import aliases, globs, traits,
trait method lookup, broad type aliases, or generics beyond existing parsed
shape.

This slice starts from parser/HIR arrays. It must not resurrect the deleted
resolver slice, and it must not treat source text rewriting, CPU import
expansion, hash-only lookup, or a same-source qualified shortcut as module
resolution. The paper-aligned flow is:

1. Extract name and path evidence from parser/HIR arrays.
2. Assign stable name ids by GPU radix sort, adjacent byte equality
   deduplication, and prefix-sum ids.
3. Scatter dense module, import, declaration, and use records from prefix scans.
4. Build sorted lookup tables for modules, declarations, imports, and qualified
   uses.
5. Validate duplicates and unsupported imports with sorted-adjacent comparison
   plus byte equality collision checks.
6. Write per-namespace `resolved_type_decl`, `resolved_value_decl`,
   `resolved_type_status`, and `resolved_value_status` arrays.
7. In a later consumer bridge, feed resolved declaration/type outputs into the
   existing visible/type/call passes and reduce user-facing status records.

Concrete pass names for the first implementation:

- `type_check_names_00_mark_lexemes.slang`: read token/HIR ownership buffers
  and mark identifier/string lexemes that can participate in semantic names.
- `type_check_names_scan_00_local.slang`,
  `type_check_names_scan_01_blocks.slang`, and
  `type_check_names_scan_02_apply.slang`: reusable GPU exclusive-prefix scan
  helpers used for lexeme scatter, run-head id assignment, and later compact
  module/import/declaration record allocation.
- `type_check_names_01_scatter_lexemes.slang`: prefix-scan lexeme flags and
  scatter `name_lexeme_token`, `name_lexeme_file_id`, `name_lexeme_start`,
  `name_lexeme_len`, `name_lexeme_hash`, `name_lexeme_original_index`, and a
  GPU-written compact `name_count_out`.
- `type_check_names_radix_00_histogram.slang`: for one byte offset, build
  per-block radix bucket counts over compact name spans, clamped by the
  GPU-written `name_count_in` buffer rather than a host-read count.
- `type_check_names_radix_00b_bucket_prefix.slang`: scan per-bucket block
  histogram counts on the GPU to produce exclusive block prefixes for stable
  scatter. The first helper has a 256 histogram-block scheduling bound and is
  not a CPU fallback.
- `type_check_names_radix_00c_bucket_bases.slang`: scan bucket totals on the
  GPU to produce global radix bucket bases.
- `type_check_names_radix_01_scatter.slang`: consume GPU-scanned bucket counts
  and perform a stable radix scatter while carrying name span ids.
- `type_check_names_radix_02_adjacent_dedup.slang`: compare adjacent sorted
  lexemes by byte equality over `source_bytes`; hash equality is only a
  candidate filter.
- `type_check_names_radix_03_assign_ids.slang`: consume an exclusive prefix sum
  over unique-name run heads and write `name_id_by_token[token]` plus
  `name_id_by_input[name_span_id]`.
- `type_check_modules_00_mark_records.slang`: mark module declarations, imports,
  top-level declarations, type paths, value paths, and call paths from parser
  HIR arrays such as item kind, item path span, visibility, namespace, file id,
  path expression spans, and type-expression spans.
- `type_check_modules_01_scatter_paths.slang`: prefix-scan path flags and
  scatter compact `path_start`, `path_len`, `path_segment_base`,
  `path_owner_hir`, `path_owner_token`, and `path_kind` records.
- `type_check_modules_01b_scatter_path_segments.slang`: scatter
  `path_segment_count`, `path_segment_name_id`, and `path_segment_token` from
  compact path spans and `name_id_by_token`.
- `type_check_modules_02_scatter_module_records.slang`,
  `type_check_modules_02b_scatter_import_records.slang`,
  `type_check_modules_02c_scatter_decl_core_records.slang`, and
  `type_check_modules_02d_scatter_decl_span_records.slang`: after separate
  GPU prefix scans over module/import/declaration flags, scatter
  `module_file_id`, `module_path_id`, `import_module_file_id`,
  `import_path_id`, `import_kind`, `decl_module_file_id`, `decl_name_id`,
  `decl_kind`, `decl_namespace`, `decl_visibility`, `decl_hir_node`,
  `decl_name_token`, `decl_token_start`, and `decl_token_end`.
- `type_check_modules_02e_build_module_keys.slang`: copy each module record's
  path segment-name ids into fixed-width `module_key_segment_count`,
  `module_key_segment_base`, and `module_key_segment_name_id` rows, plus
  `module_key_to_module_id`, so a later GPU radix sort can order full module
  paths. This is key construction only, not lookup or sorting.
- `type_check_modules_03_sort_module_keys_histogram.slang` and
  `type_check_modules_03b_sort_module_keys_scatter.slang`: perform a stable GPU
  radix sort over bounded `module_key_to_module_id` rows. The first slice sorts
  up to eight path segments and `type_check_modules_02e_build_module_keys.slang`
  rejects deeper module declarations until the bound is lifted.
- `type_check_modules_04_validate_modules.slang`: compare adjacent sorted module
  keys segment by segment without hashes and write duplicate-module status.
- `type_check_modules_05_resolve_imports.slang`: resolve import path ids with
  sorted lookup against `module_key_to_module_id`, then write
  `import_target_module_id` and `import_status`.
- `type_check_modules_05b_clear_file_module_map.slang`,
  `type_check_modules_05c_build_file_module_map.slang`, and
  `type_check_modules_05d_attach_record_modules.slang`: clear a GPU
  `module_id_by_file_id` table, scatter module ids into that table from
  parser-owned module file ids, and attach `decl_module_id`,
  `import_module_id`, and `path_owner_module_id` to dense records. This is a
  GPU table bridge from file ownership to
  module ownership; it is not declaration lookup or visibility.
- `type_check_modules_06a_seed_decl_key_order.slang`,
  `type_check_modules_06_sort_decl_keys.slang`, and
  `type_check_modules_06b_sort_decl_keys_scatter.slang`: seed and radix-sort
  dense declaration key rows keyed by `(module_id, namespace, name_id)`.
- `type_check_modules_07_validate_decls.slang`: compare adjacent declaration
  keys and write duplicate/invalid declaration status per namespace.
- `type_check_modules_08_mark_decl_namespace_keys.slang`: walk the sorted
  declaration key order and mark validated type/value declarations by namespace
  with `decl_type_key_flag` and `decl_value_key_flag`. This is table
  materialization setup only, not declaration lookup or visibility.
- `type_check_modules_08b_scatter_decl_namespace_keys.slang`: after GPU prefix
  scans over those namespace flags, scatter `decl_type_key_to_decl_id` and
  `decl_value_key_to_decl_id`. Because the input order is the declaration-key
  radix order, filtering one namespace preserves sorted `(module_id, name_id)`
  lookup order for each table. These tables are still not consumed by path
  resolution yet.
- `type_check_modules_09_count_import_visibility.slang`: for each resolved path
  import, range-query the sorted `decl_type_key_to_decl_id` and
  `decl_value_key_to_decl_id` tables for the target module id and count only
  public declarations. This writes per-import type/value counts for GPU prefix
  scans. It is not a source import expander and it does not resolve paths.
- `type_check_modules_09b_scatter_import_visibility.slang`: after GPU prefix
  scans over those counts, scatter imported-public rows carrying
  `(importer_module_id, name_id, decl_id)` for type and value namespaces. The
  first implementation uses a bounded visibility-row capacity and writes a GPU
  `NameLimit` status if the expansion would overflow instead of silently
  truncating.
- `type_check_modules_09c_sort_import_visible_keys.slang` and
  `type_check_modules_09d_sort_import_visible_keys_scatter.slang`: stable-radix
  sort imported visibility rows by `(importer_module_id, name_id)` in separate
  type/value tables.
- `type_check_modules_09e_build_import_visible_key_tables.slang`: materialize
  final sorted imported lookup tables:
  `import_visible_type_key_module_id`, `import_visible_type_key_name_id`,
  `import_visible_type_key_to_decl_id`, `import_visible_value_key_module_id`,
  `import_visible_value_key_name_id`, and
  `import_visible_value_key_to_decl_id`.
- `type_check_modules_09f_validate_import_visible_keys.slang`: compare adjacent
  sorted imported visibility keys and write ambiguous/invalid row statuses.
  Later namespace-aware consumers decide whether duplicate imports are legal
  re-imports or user-facing ambiguous names; this pass prevents first-match
  lookup from being mistaken for resolution.
- `type_check_modules_10_resolve_local_paths.slang`: initialize one namespace's
  `resolved_decl`/`resolved_status` arrays and resolve one-segment HIR path
  expressions against declarations in the owner module by binary searching the
  sorted declaration namespace table.
- `type_check_modules_10b_resolve_imported_paths.slang`: resolve still
  unresolved one-segment HIR path expressions against sorted imported-public
  declaration tables for the owner module. Ambiguous imported rows produce
  status instead of first-match lookup.
- `type_check_modules_10c_resolve_qualified_paths.slang`: resolve
  multi-segment HIR path expressions by looking up the prefix in sorted module
  keys and the leaf in the selected declaration namespace table. It writes only
  `resolved_type_decl`, `resolved_type_status`, `resolved_value_decl`, and
  `resolved_value_status` through per-namespace bind groups; it does not patch
  `visible_decl`, `visible_type`, `resolved_call_decl`, `call_fn_index`, or
  `call_return_type`.
- `type_check_modules_10d_clear_type_path_types.slang`: clear the
  token-indexed `module_type_path_type`, `module_type_path_status`,
  `module_value_path_expr_head`, `module_value_path_call_head`, and
  `module_value_path_status` bridges before the current run projects path
  results.
- `type_check_modules_10e_project_type_paths.slang`: consume
  `resolved_type_decl`, `resolved_type_status`, `decl_namespace`,
  `decl_kind`, and the parser-derived `decl_name_token` to project resolved
  struct/enum type paths into `module_type_path_type` and type-path failures
  into `module_type_path_status`. It does not inspect source bytes, hash tokens,
  scan for `::`, patch visibility, patch call outputs, or globally reduce
  value-namespace failures.
- `type_check_modules_10f_mark_value_call_paths.slang`: consume parser HIR
  `parent` and `next_sibling` arrays to mark qualified path heads whose
  enclosing `HIR_NAME_EXPR` is in value-expression context, while separately
  marking the subset followed by a sibling `HIR_CALL_EXPR`. This identifies
  value path use sites and call-shaped value path use sites without token text
  scans.
- `type_check_modules_10g_project_value_paths.slang`: consume
  `resolved_value_status` and the HIR value-expression marker to project
  value-namespace path status into `module_value_path_status`. It keeps
  qualified value paths fail-closed unless a later consumer clears the status
  after reading `resolved_value_decl`; it does not patch call outputs or accept
  qualified values by itself.
- `type_check_modules_10h_consume_value_calls.slang`: consume
  `resolved_value_decl`, `resolved_value_status`, declaration metadata, and the
  HIR call-open marker after regular function return metadata exists. For
  resolved HIR path expressions that target regular function declarations, it
  writes `call_fn_index`, `call_return_type`, and `call_return_type_token` at
  the path head, then clears `module_value_path_status`. It does not inspect
  source bytes, hash token text, scan for `::`, perform unqualified lookup, or
  ask the CPU.
- `type_check_modules_10i_consume_value_consts.slang`: consume
  `resolved_value_decl`, `resolved_value_status`, declaration metadata, and the
  existing declaration `visible_type` output after scope typing has populated
  const declarations. For resolved non-call HIR path expressions that target
  top-level const declarations, it writes `visible_decl` and `visible_type` at
  the path head, then clears `module_value_path_status`. It does not inspect
  source bytes, hash token text, scan for `::`, perform unqualified lookup, or
  ask the CPU.
- `type_check_modules_10j_consume_value_enum_units.slang`: consume
  `resolved_value_decl`, `resolved_value_status`, declaration metadata, and
  `decl_parent_type_decl`. For resolved non-call HIR path expressions that
  target unit enum variant declarations, it writes `visible_decl` and the parent
  enum `visible_type` at the path head, then clears `module_value_path_status`.
  It does not inspect source bytes, hash token text, scan for `::`, perform
  unqualified lookup, or ask the CPU.
- `type_check_modules_10k_project_type_instances.slang`: consume resolved local
  and qualified type paths plus path segment tokens and project generic type
  heads such as `Option<i32>` and `core::option::Option<i32>` onto the existing
  `TYPE_REF_INSTANCE` metadata. It binds the leaf instance to the resolver's
  declaration token and copies argument refs without token text comparison.
- `type_check_modules_10l_consume_value_enum_calls.slang`: consume resolved
  local and qualified enum-variant calls after
  `type_check_type_instances_06_enum_ctors` validates contextual generic
  payloads. It clears `module_value_path_status` and publishes the parent enum
  `call_return_type` only when the resolver names an enum variant and generic
  constructor validation has produced `GENERIC_ENUM_CTOR_OK` when needed.
  One-segment generic constructors keep the validator sentinel at the leaf token
  instead of replacing it with the parent enum type, because the token checker
  consumes that sentinel for bounded contextual generic constructor validation.
  Non-constructor symbolic generic returns, exhaustive match semantics, enum
  layout, and backend lowering remain separate checkpoints. The bounded
  stdlib-shaped match type-check slice consumes HIR match spans plus these
  resolver/type-instance arrays for enum payload arms, but it is not package
  loading, exhaustiveness, layout, or codegen support.

Required data buffers for the first implementation:

- Name interning: `name_lexeme_token`, `name_lexeme_start`,
  `name_lexeme_len`, `name_lexeme_hash`, `name_lexeme_original_index`,
  `name_count_out`, `name_count_in`, `name_sorted_lexeme`,
  `name_unique_flag`, `name_unique_prefix`, `interned_name_start`,
  `interned_name_len`, `name_id_by_token`, and `name_id_by_lexeme`.
- Paths: `path_start`, `path_len`, `path_segment_count`,
  `path_segment_name_id`, `path_segment_token`, `path_owner_hir`, and
  `path_owner_token`.
- Modules: `module_decl_file`, `module_record_id`, `module_file_id`,
  `module_path_id`, `module_key_to_module_id`, `module_id_by_file_id`, and
  `module_status`.
- Imports: `import_module_id`, `import_path_id`, `import_kind`,
  `import_target_module_id`, `import_status`, `import_visible_type_count`,
  `import_visible_value_count`, `import_visible_type_prefix`,
  `import_visible_value_prefix`, `import_visible_type_count_out`,
  `import_visible_value_count_out`, `import_visible_type_module_id`,
  `import_visible_type_name_id`, `import_visible_type_decl_id`,
  `import_visible_type_key_order`, `import_visible_type_key_to_decl_id`,
  `import_visible_type_status`, `import_visible_value_module_id`,
  `import_visible_value_name_id`, `import_visible_value_decl_id`,
  `import_visible_value_key_order`, `import_visible_value_key_to_decl_id`, and
  `import_visible_value_status`.
- Declarations: `decl_module_id`, `decl_name_id`, `decl_kind`,
  `decl_namespace`, `decl_visibility`, `decl_hir_node`, `decl_name_token`,
  `decl_token_start`, `decl_token_end`, `decl_parent_type_decl`, `decl_key_to_decl_id`,
  `decl_type_key_to_decl_id`, `decl_value_key_to_decl_id`, `decl_type_key_flag`,
  `decl_value_key_flag`, `decl_type_key_prefix`, `decl_value_key_prefix`,
  `decl_type_key_count_out`, `decl_value_key_count_out`, `decl_status`,
  and `decl_duplicate_of`.
- Resolution arrays: `resolved_type_decl`, `resolved_type_status`,
  `resolved_value_decl`, and `resolved_value_status`.
- Type path projection: `module_type_path_type` and
  `module_type_path_status`, token-indexed bridges from resolver path ids to the
  current struct/enum type-code representation and type-context status checks.
- Type instance projection: `type_expr_ref_tag`, `type_expr_ref_payload`,
  `type_instance_decl_token`, `type_instance_arg_start`,
  `type_instance_arg_ref_tag`, `type_instance_arg_ref_payload`, and
  `type_instance_state` for local and module-qualified generic type heads.
- Value path status projection: `module_value_path_expr_head`,
  `module_value_path_call_head`, and `module_value_path_status`, token-indexed
  bridges from HIR value-path ids to value-context status checks.
- Value call consumer projection: `call_fn_index`, `call_return_type`, and
  `call_return_type_token` for resolved regular function calls, keyed by the
  HIR-produced `module_value_path_call_open` marker. General value lookup
  outputs such as `resolved_call_decl` and `visible_decl` are a later checkpoint.
- Value const consumer projection: `visible_decl` and `visible_type` for
  resolved top-level constants, including one-segment constants made visible by
  sorted import visibility tables.
- Value unit enum projection: `decl_parent_type_decl`, `visible_decl`, and
  `visible_type` for resolved local and qualified unit enum variants.
- Value enum constructor projection: `decl_parent_type_decl` and
  `call_return_type` for resolved local and qualified enum constructor calls
  whose payloads have already passed the bounded GPU constructor validator.

Implementation checkpoints:

- The name interning checkpoint is complete only when equal identifier/string
  bytes share one id, unequal bytes never share an id after byte equality
  collision checks, and ids come from prefix-sum ids over unique sorted names.
  The current runtime wiring is a bounded fail-closed checkpoint, not the final
  unbounded name interner.
- The module/import checkpoint is complete only when module path lookup is a
  sorted lookup table over path segment name ids and duplicate validation is
  performed on GPU.
- The declaration checkpoint is complete only when declaration keys are sorted
  by module id, namespace, and name id, duplicate validation is separate for
  value and type namespaces, and namespace-specific declaration lookup tables
  are materialized from the sorted order. The current runtime reaches this
  table-materialization checkpoint.
- The import visibility checkpoint is complete only when resolved path imports
  expand public target declarations into GPU-scanned rows, those rows are
  stable-radix-sorted by importer module and name id, final type/value imported
  lookup tables are materialized, visibility expansion overflows fail closed on
  GPU, and adjacent duplicate imported names are recorded as row statuses. The
  current runtime reaches this table-materialization checkpoint.
- The path resolution array checkpoint is complete only when per-namespace GPU
  passes resolve local, imported, and qualified type/value path ids from sorted
  module keys, declaration tables, and `import_visible` tables, then write
  `resolved_type_decl`, `resolved_type_status`, `resolved_value_decl`, and
  `resolved_value_status`.
- The type-path projection checkpoint is complete only when same-module
  qualified struct/enum type annotations consume `resolved_type_decl` through
  `module_type_path_type` and still fail unresolved, ambiguous, or wrong-module
  type paths without a same-source shortcut. It does not make qualified value
  paths or calls pass by itself; those require value/call consumers to read
  `resolved_value_decl` in their use context.
- The value-path status checkpoint is complete only when qualified value paths
  are identified from HIR/tree relationships and feed `resolved_value_status`
  into a consumer-context status buffer, with call-shaped paths marked as a
  subset for call consumers. It is intentionally fail-closed and must not be
  replaced by a global type/value status reducer.
- The regular qualified-call checkpoint is complete only when the consumer reads
  `resolved_value_decl` in HIR path context, verifies the resolved declaration
  is a value-namespace function, and writes call result arrays without any
  token-text qualified-call bridge. It does not imply enum constructors,
  methods, generic call inference, or general value lookup.
- The qualified-constant checkpoint is complete only when the consumer reads
  `resolved_value_decl` in non-call HIR path context, verifies the resolved
  declaration is a value-namespace const, reuses the declaration type computed
  by scope typing, and writes `visible_decl`/`visible_type` at the path head
  without any token-text bridge. It does not imply enum constructors, methods,
  generic values, or general value lookup.
- The qualified-unit-enum-variant checkpoint is complete only when the consumer
  reads `resolved_value_decl` in non-call HIR path context, verifies the resolved
  declaration is a value-namespace enum variant, reads `decl_parent_type_decl`,
  and writes `visible_decl`/`visible_type` for the parent enum without token-text
  lookup. It does not imply constructor calls, methods, or general value lookup.
- The qualified-enum-constructor checkpoint is complete only when qualified
  generic type heads are projected into type-instance metadata, the existing GPU
  enum-constructor validator accepts contextual concrete payloads, and the
  enum-call consumer clears the value-path status from resolver arrays. It does
  not imply non-constructor symbolic generic returns, exhaustive match
  semantics, enum layout, backend lowering, methods, or general value lookup.
  The current bounded match consumer is limited to HIR-spanned arm result typing
  and enum tuple payload binding.
- The host checkpoint is complete only when the CPU reads explicitly supplied
  files, uploads source-pack buffers, and does not parse imports, expand import
  closure, rewrite module names, precompute declarations, or decide
  visibility.

Forbidden legacy resolver shapes:

- Do not recreate `type_check_names_00_hash.slang`,
  `type_check_modules_00_collect.slang`,
  `type_check_modules_00_collect_decls.slang`,
  `type_check_modules_00_resolve_imports.slang`,
  `type_check_modules_00_clear.slang`,
  `type_check_modules_01_dense_scan.slang`,
  `type_check_modules_01_same_source_types.slang`,
  `type_check_modules_02_dense_scatter.slang`,
  `type_check_modules_02b_dense_scatter_imports.slang`,
  `type_check_modules_02c_dense_scatter_decls.slang`,
  `type_check_modules_02_patch_visible_types.slang`, or
  `type_check_modules_03_attach_ids.slang`.
- Do not reintroduce the earlier hash-prefix-scan slice: path hashes, dense
  counts, module records, import records, and declaration records are not enough
  unless they flow through radix sort, byte equality deduplication, prefix-sum
  ids, sorted lookup tables, duplicate validation, and resolution arrays.
- Do not implement a same-source qualified shortcut. Same-source qualified
  names must exercise the same module/import/declaration lookup path as
  cross-file qualified names.
- Do not implement source rewriting, CPU import expansion, CPU path lookup,
  CPU declaration visibility, `lstd_` namespace rewriting, or hash-only lookup.

First positive fixtures:

```lani
module core::math;
pub const ONE: i32 = 1;
pub fn add_one(value: i32) -> i32 { return value + ONE; }

module app::main;
import core::math;
fn main() -> i32 {
    let value: i32 = core::math::add_one(core::math::ONE);
    return value;
}
```

```lani
module core::option;
pub enum OptionI32 { Some(i32), None }

module app::main;
import core::option;
fn take(value: core::option::OptionI32) { return; }
fn main() { take(core::option::Some(7)); return; }
```

Keep this slice intentionally nongeneric. `core::option::Option<i32>` should
remain rejected until generic type substitution has a GPU implementation; use a
non-generic fixture such as `OptionI32` for the first module-resolution tests.

## No-CPU-Fallback Guardrails

- No CPU source concatenation, import expansion, alias expansion, generic
  substitution, semantic precheck, path lookup, or declaration visibility logic.
- CPU file/path handling is limited to reading explicitly supplied source-pack
  files and uploading byte buffers plus file-span metadata. Module identity and
  import identity are computed from GPU-parsed declarations and import items.
- Do not accept a feature by rewriting source into old flat `lstd_` names.
- Do not make string imports perform host-side includes. Reject them until they
  resolve to an already-uploaded source-pack file through GPU-visible metadata.
- Do not treat parser-table acceptance as feature support. A module feature is
  supported only when GPU syntax accepts it, GPU type checking resolves it, and
  backend consumers receive GPU-resolved declaration/type/call buffers.
- Do not treat the path resolution array checkpoint as feature support by
  itself. It may write declaration/status arrays while qualified paths still
  fail closed in existing consumers.
- Unsupported paths must fail as GPU syntax or GPU type-check errors with stable
  tests. Existing unqualified single-module names may continue to use the current
  token-scan implementation until module resolution reaches parity, but `::`
  paths must never be downgraded to unqualified lookup.
- Public/private checks must be done on GPU declaration records. The host must
  not filter declarations or precompute visibility.
- Any future package manifest can enumerate files, but cannot provide resolved
  import edges. Import edges are GPU outputs.
