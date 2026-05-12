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
- `tests/parser_tree.rs` requires call-shaped qualified value paths to pass GPU
  syntax, while non-call qualified value paths such as `core::i32::MIN` still
  fail syntax. Semantic resolution remains a GPU type-checker responsibility.

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
  AST/HIR metadata. The sparse module/import metadata collector consumes these
  HIR item fields instead of rediscovering item spans from token neighborhoods;
  import path-vs-string target kind also comes from the parser import-tail
  production. The first resolver consumes those records for path-import target
  validation inside an already-uploaded source pack.
- The path evidence is span metadata only: tests assert that `HIR_PATH_EXPR`
  covers complete token ranges such as `core::numbers`, `core::i32`, and
  `core::i32::abs`, but no module id, import target, declaration id, visibility
  result, or callable target is produced from those spans yet.
- Direct HIR classifies module/import item heads and qualified value path heads
  as structured records, while suppressing extra value-path tail identifier
  uses. Qualified type-path tails remain visible to the existing type checker;
  a narrow same-source type path slice is handled in GPU module/type passes,
  while unsupported external paths still fail instead of becoming no-ops.

What GPU type checking accepts and rejects today:

- `tests/type_checker_modules.rs` requires same-source qualified type paths,
  such as `app::main::Point`, to be accepted when they match the leading
  `module app::main;` declaration and name a struct or enum declared in the
  same source. This covers function signature positions plus parameter-use flow
  through `visible_type`, such as `point.x` where `point:
  app::main::Point`, and returning such a parameter from a function with a
  qualified return type.
- `tests/type_checker_modules.rs` still requires unresolved external qualified
  type paths such as `core::option::Option<i32>` in a parameter type to fail
  with `CompileError::GpuTypeCheck`.
- `shaders/type_checker/type_check_modules_01_same_source_types.slang` performs a
  GPU precheck for `::` type paths against the leading module declaration and
  same-source struct/enum declarations.
- `shaders/type_checker/type_check_modules_02_patch_visible_types.slang` patches
  `visible_type` after scope analysis so qualified parameter declarations and
  their resolved uses carry the same struct/enum type code as unqualified names.
  Existing type checker passes still do not build a module table, import table,
  or cross-file path table.
- `shaders/type_checker/type_check_calls_03_resolve.slang` resolves the first
  same-source qualified function-call slice. Calls such as `app::helper()` and
  `app::main::helper()` type-check when the prefix matches the leading module
  declaration and the callee is a function declared in the same source. This is
  still not import or package resolution: imports, external qualified calls,
  qualified constants, and module-aware value lookup tables remain blocked.
- `shaders/type_checker/type_check_modules_00_clear.slang` and
  `shaders/type_checker/type_check_modules_00_collect.slang` now create a
  GPU-resident sparse metadata artifact for leading module/import HIR records:
  item kind, path token span, path hash, import target kind, and enclosing
  module token. `type_check_modules_00_collect_decls.slang` records sparse
  top-level declaration facts from parser-owned HIR item fields: item kind, name
  hash, name length, namespace, visibility, file id, and source HIR node.
  Collection is driven by parser-owned `hir_item_*` metadata, not by discovering
  semantic items from local token neighborhoods.
  `type_check_modules_00_resolve_imports.slang` consumes those records for the
  first bounded resolver slice: path imports in an already-uploaded source pack
  resolve to a matching module token, unresolved path imports reject, string
  imports reject, duplicate module paths reject, and resolved path-import
  metadata is written to `import_resolved_module_token`. Cross-file declaration
  visibility still does not exist.
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
tree/HIR and type-check passes against source-pack buffers. Already-supplied
multi-file source packs can flow through the resident GPU parser and type
checker when the files contain independent module metadata and supported
declarations. The type checker suppresses module/import headers through
parser-owned HIR item spans rather than token-neighborhood discovery. This
groundwork does not load imports, discover files from module declarations,
build module tables, resolve cross-file paths, or make declarations visible
across files. The normal compiler now uses the LL(1) tree/HIR path, which
receives the lexer-produced `token_file_id` sideband, validates it during GPU
syntax checking, and feeds it into LL(1) HIR ownership metadata. The older
direct-HIR helper still mirrors the same sideband, but it is not the semantic
path to extend.

### Interned Names And Path Spans

Add GPU buffers that convert token text into stable integer keys:

- `ident_hash[token]`: 64-bit or two-u32 hash over identifier token bytes.
- `ident_len[token]`: text length for collision checks.
- `path_start[path_id]`, `path_len[path_id]`: token span for every `path`.
- `path_segment_count[path_id]`.
- `path_segment_hash[path_segment_slot]`.
- `path_segment_token[path_segment_slot]`.
- `path_hash[path_id]`: ordered segment hash for radix sorting.

Build these with per-token maps, prefix scans over path-start flags, and scatter
from each path segment. Use byte equality only as a collision check after hash
matches; never repeatedly scan arbitrary source text inside every resolver.

### Modules

Create module declarations from `module path;` items:

- `module_decl_file[file_id]`: path id for the file's declaration, or an implicit
  root module path for root-only legacy inputs during transition.
- `module_record_id[file_id]`: dense module id from a prefix scan over valid
  declarations.
- `module_path_hash[module_id]`, `module_path_start[module_id]`,
  `module_path_len[module_id]`.
- `module_file_id[module_id]`.

Validate on GPU by sorting `(module_path_hash, module_id)`, comparing adjacent
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
- `decl_name_hash`, `decl_name_token`, `decl_name_len`.
- `decl_kind`: const, fn, extern fn, struct, enum, enum variant, type alias
  later, trait/impl later.
- `decl_visibility`: private or public.
- `decl_hir_node`, `decl_token_start`, `decl_token_end`.
- `decl_type_code` or `decl_type_record_id` for type declarations.

For enum variants, store both the variant declaration and the parent enum
declaration so qualified constructor lookup can resolve
`core::option::Some` to the variant and type checking can still know the enum.

Validate duplicates with radix sort over
`(decl_module_id, decl_namespace, decl_name_hash)` plus collision checks. Keep
type/value namespaces separate so a type and function can share a spelling if
the language permits it.

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
- `decl_type_key_to_decl_id`: sorted by `(module_id, name_hash)`.
- `import_visible_type_key`: sorted/scattered from each importing module's
  imports for unqualified imported lookup.

`type_code_for_type_expr` should stop scanning all tokens for struct/enum names
and instead call a path resolver that writes `resolved_type_decl[path_id]` and
`type_record[path_id]`. Existing primitive and generic parameter paths can remain
fast local cases, but the result must flow through the same `visible_type`
buffers.

### Qualified Value Paths

Qualified value paths should be HIR-visible, not blocked in syntax. Add
`HIR_PATH_EXPR` or encode `HIR_NAME_EXPR` with `path_id` metadata so `a::b::c`
is a single value-use record rather than three independent identifiers.

Resolution cases:

- One segment: existing lexical locals/params/consts, builtins, local module
  functions/consts/enum variants, then imported public values.
- Multiple segments: resolve prefix module path, then resolve final segment in
  that module's value namespace.

Outputs:

- `resolved_value_decl[path_id or use_id]`.
- `visible_decl[token]` for the head token of resolved value paths, so existing
  codegen consumers can continue reading declaration metadata.
- `call_fn_index[call_token]` and `call_return_type[call_token]` for qualified
  function calls.
- Enum constructor calls use the resolved enum-variant declaration instead of
  unqualified global variant scans.

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
   ambiguous imports by reducing status records into the existing type-check
   status buffer.
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
is built. Call-shaped qualified value paths can pass syntax, and GPU type
checking resolves same-source qualified function calls whose prefix matches the
leading module declaration. GPU type checking still rejects import items,
external qualified calls, unresolved module prefixes, missing qualified callees,
and qualified constants so syntax metadata cannot be mistaken for module/import
resolution.

## Minimal Resolver Implementation Slice

Goal: one source pack can contain multiple module-declared files, path imports,
qualified type paths, and qualified value paths for public top-level consts,
functions, structs, enums, and enum variants. No string imports, aliases, globs,
traits, impl method lookup, type aliases, or generics beyond existing parsed
shape.

Exact files to change:

- `shaders/parser/syntax_tokens.slang`: consume the existing module/import
  metadata and allow `::` in value path contexts when the token sequence is a
  valid path followed by call, struct-literal open, semicolon, comma, operator,
  return boundary, or match-pattern boundary.
- `shaders/parser/hir_nodes.slang` and
  `src/parser/gpu/passes/hir_nodes.rs`: add HIR constants for module item,
  import item, and path expression/type path.
- `src/parser/gpu/driver.rs` and parser buffer structs as needed: allocate and
  expose any new HIR path metadata buffers produced by the LL(1) tree/HIR path.
- `shaders/type_checker/type_check_modules_*.slang`: new passes for path
  extraction, module/import/declaration record scatter, key sort/join, duplicate
  validation, and path resolution. If a generic radix-sort helper is not already
  available, add the smallest reusable GPU sort helper under the existing GPU
  pass infrastructure.
- `src/type_checker/gpu.rs`: allocate module/path/declaration buffers, record
  the new module-resolution passes before visible declaration/type/call passes,
  and bind resolved outputs into existing passes.
- `shaders/type_checker/type_check_visible_02_scatter.slang`: consult resolved
  module value declarations before reporting unresolved global names; keep local
  lexical resolution for params and lets.
- `shaders/type_checker/type_check_scope.slang`,
  `shaders/type_checker/type_check_tokens.slang`, and
  `shaders/type_checker/type_check_calls_02_functions.slang`: replace
  unqualified struct/enum/function scans with resolved declaration/type buffers
  for module-aware declarations, while preserving existing unqualified behavior
  inside a module.
- `tests/parser_tree.rs`: keep leading module/import metadata accepted, keep
  non-call qualified value paths rejected, and broaden qualified value
  acceptance only as resolver buffers become real.
- `tests/type_checker_modules.rs`: replace the current qualified type rejection
  with positive GPU type-check tests for imported qualified types and values, and
  add negative tests for unresolved module, unresolved declaration, duplicate
  module, duplicate declaration, private cross-module use, and unsupported string
  import.

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
- Unsupported paths must fail as GPU syntax or GPU type-check errors with stable
  tests. Existing unqualified single-module names may continue to use the current
  token-scan implementation until module resolution reaches parity, but `::`
  paths must never be downgraded to unqualified lookup.
- Public/private checks must be done on GPU declaration records. The host must
  not filter declarations or precompute visibility.
- Any future package manifest can enumerate files, but cannot provide resolved
  import edges. Import edges are GPU outputs.
