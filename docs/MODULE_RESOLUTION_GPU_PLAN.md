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
- Parser and type-checker coverage now exercises module/import metadata and
  namespaced paths through the resident GPU parser/type-check surfaces instead
  of a separate parser-tree fixture.
- The GPU parser/HIR path already classifies LL(1)-derived HIR nodes such as
  functions, params, types, lets, returns, consts, enums, structs, struct
  literals, and type aliases in `shaders/parser/hir_nodes.slang` and
  `src/parser/passes/hir_nodes.rs`.

What GPU syntax accepts and rejects today:

- Current GPU parser/type-checker tests require leading `module path;`
  declarations, leading path imports, and stdlib seed modules such as
  `stdlib/core/i32.lani`, `stdlib/core/bool.lani`, and
  `stdlib/test/assert.lani` to flow as source metadata.
- Current tests require duplicate modules, non-leading module declarations, and
  non-leading imports to reject while the supported module/import slice stays
  limited to leading source metadata plus GPU resolver records.
- Current tests require qualified value paths, including non-call paths such as
  `core::i32::MIN`, to pass syntax/HIR evidence. Semantic resolution remains a
  GPU type-checker responsibility.

What GPU HIR preserves today:

- `shaders/parser/hir_nodes.slang` and `src/parser/passes/hir_nodes.rs`
  now define `HIR_MODULE_ITEM`, `HIR_IMPORT_ITEM`, and `HIR_PATH_EXPR`.
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
  now resolve only against explicitly supplied source-pack modules;
  `--source-root` and `--stdlib-root` can load leading module-path imports into
  that source pack. User/package source roots are searched before the stdlib
  fallback, so a same-path user module does not pull in or conflict with the
  stdlib candidate. String imports still fail in the GPU resolver and are not
  host-included.
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
  consumers, while general qualified values remain blocked. Function return
  type edges are also available as parser-owned `hir_fn_return_type_node`
  records with source-pack file ids and spans, so later return-type consumers do
  not need to scan function bodies or re-read token spelling for the signature.
  Return statements publish `hir_stmt_record` entries that point at the
  parser-owned return expression and value token, so later type/codegen
  consumers can use statement records instead of rescanning body shape.
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
  hashes. Generic enum constructor expected-type lookup consumes
  parser-published `hir_call_context_stmt_node` rows instead of walking parent
  links in the consumer. Top-level qualified constants and one-segment
  constants made visible by path imports consume `resolved_value_decl` after
  declaration types are available. General qualified value paths still reject
  unless a dedicated HIR consumer clears the fail-closed status.
  Ordinary qualified call typing is still bounded by the four-slot call/type
  argument cache. The non-hacky replacement is to split the consumer into a
  count/scan/scatter argument-row pass, a bounded-depth type-ref leaf relation
  with explicit overflow rows, sorted joins/reductions for generic binding and
  mismatch status, and a final map pass that updates the existing call result
  arrays. That requires new state buffers and scheduler order beyond the
  current `10h` bind group.
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
- Imported public names are not resolved by first match: tests require same-name
  public type and value declarations imported from different modules to reject
  through the GPU imported-visibility tables, including a source/import-order
  permutation where a first-match implementation would still type-check.
  The readiness contract is module/import records, then sorted module and
  declaration lookups, then joined public import-visibility rows, then sorted
  imported visibility keys, then ambiguity validation before consumers read an
  imported name.
- Import cycles currently fail through GPU import-edge records only for direct
  self-imports and two-module cycles. Direct self-imports reject during import
  resolution, and sorted import-edge equal-range lookup rejects reverse-edge
  pairs. Longer directed cycles such as `A -> B -> C -> A` still need a real
  GPU topological/SCC checkpoint; do not claim that case as implemented or
  replace it with CPU graph traversal. The CPU loader may use recursion guards
  to avoid loading the same file forever, but it must not become the semantic
  cycle decision for source packs.
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
- The token-local visibility scatter stage has been removed. Struct/enum/function
  lookup helpers must consume HIR name, declaration, and scope records instead of
  reviving unqualified-text scans over earlier tokens.

## Production-Readiness Audit: May 2026

The module resolver is on the paper-aligned path where it uses flat GPU records,
interned names, sorted module keys, import visibility tables, declaration keys,
and parallel import-cycle peeling instead of recursive CPU resolver structures.
That is the right foundation for large source packs, but several current paths
must stay classified as scaffolding until they consume and produce durable GPU
records end to end.

Current pass-architecture violations and risks:

- Do not reintroduce token-neighborhood visibility. Compiler-facing visibility
  paths must resolve HIR names through sorted declaration and scope records
  rather than scanning earlier tokens by unqualified text.
- `src/compiler/source_pack/package_manifest.rs` and
  `src/compiler/source_pack/package_lock.rs` may discover files, validate path
  metadata, and persist replay metadata on CPU, but the lockfile import graph
  must not become semantic evidence. Gate: GPU module/import records revalidate
  module declarations, import edges, and cycles on every replay, including
  tampered or stale lockfile inputs.
  Package lockfiles may persist direct reverse import edges and longer directed
  import cycles as replay metadata; rejecting semantic import cycles is a GPU
  resolver responsibility, not a package metadata shape rule.
  Current bounded evidence also rejects stale package-name-shaped import graph
  edges when the live source no longer declares that import, and the diagnostic
  names the stale edge. Persisted import-graph endpoint module fields also
  reject package-name-as-module spellings when the source identity for that file
  declares a different module, so package names and persisted edges remain
  replay metadata, not a replacement for parser/GPU module-import records.
  Persisted input and source-identity rows must also be reachable from the
  package entry through import-graph edges; source roots are lookup candidates,
  not permission for a lockfile to upload unrelated root files as package
  inputs.
  Persisted import graph dependencies and edges must also be in canonical sorted
  order; replay rejects hand-edited edge order instead of treating CPU discovery
  order as semantic readiness evidence.
  Compact path-build manifests must also carry nonempty source-byte summaries
  even when source-file rows live in sidecar pages; source counts without byte
  provenance are replay metadata gaps, not package input evidence.
- Descriptor-mode package/source-root preparation is still rejected by the
  public API. That fail-closed behavior is correct, but it blocks a production
  package pipeline. Gate: descriptor/prepare mode writes a source-pack path
  manifest and artifact descriptors without compiling the package in memory.
- `src/compiler/gpu_compiler/source_pack_executor.rs` and
  `src/compiler/source_pack/execution/link.rs` currently stream work pages and
  write descriptor/count artifacts for codegen objects, partial links, and
  linked outputs. Linked-output descriptors now fail closed unless a
  non-runtime-bound output has exactly one target-byte record array, or a
  runtime-bound output has none while services remain unbound. X86 link
  execution summaries also fail closed when descriptor counts are not backed by
  explicit interface/object/section/symbol/relocation record contracts, or when
  object inputs have symbol/relocation contracts but no object-section contract.
  Completed reduce-link replay also rejects object descriptor summaries that are
  not carried by the consumed partial-link producer pages, so CPU-side
  descriptor metadata cannot stand in for GPU-produced object/link evidence.
  Relocations must attach to section rows rather than descriptor-only object
  evidence. That is CPU control-plane scheduling, not GPU linking. Gate: link
  stages consume GPU-produced interface/object/relocation records and emit real
  linked bytes.
- Import-cycle validation is not yet general: direct self-imports and
  two-module cycles are covered by GPU import-edge records, but longer cycles
  require an SCC/topological GPU checkpoint. Gate: add that checkpoint and a
  small repeatable scale check for 64/128/256 generated modules proving acyclic
  chains and one cycle produce bounded dispatch plans without running a huge
  workload by default.

Next verifiable gates:

1. `module-visible-name-id-gate`: replace unqualified visibility token scans
   with name/declaration/scope record lookup and keep behavior-facing fixtures
   for shadowing, same-leaf names in different modules, and imported values.
2. `package-replay-gpu-validation-gate`: replay a package lockfile with a
   tampered module path or import edge and prove the GPU resolver rejects the
   mismatch/cycle with the normal module diagnostic.
3. `descriptor-source-root-prepare-gate`: make descriptor/prepare source-root
   and package modes produce source-pack path manifests and artifact descriptors
   without invoking in-memory compile.
4. `module-cycle-scale-gate`: add a no-run or tiny CPU-only scale scaffold for
   64/128/256 generated module graphs plus one focused GPU fixture for cycle
   rejection.
5. `link-record-gate`: replace descriptor-only link artifacts with GPU
   interface/object/relocation records consumed by the hierarchical link plan.

## GPU-Resident Design

The implementation adds a module-resolution stage after LL(1) tree/HIR
construction and before the existing visible/type/call passes. The host may read
explicit source files, discover source-root candidate files from leading import
metadata, and allocate/copy source blobs, but it must not rewrite source,
perform semantic import expansion, decide declaration identity, decide
visibility, or make semantic path lookup decisions.

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
groundwork exposes package manifests only as control-plane loading metadata and
does not make package names part of semantic module identity or make general
qualified value paths pass. Package names are validated as dot-separated ASCII
control-plane identifiers whose segments start and end with an alphanumeric
byte, so external package metadata cannot persist empty or punctuation-only
name segments. Package replay also rejects a missing module-path import even
when the package name maps to the requested module path spelling, so package
control-plane identity cannot satisfy source-root module evidence.
`--source-root` and `--stdlib-root` are narrow
path-import source-pack loaders; user/package roots take precedence over the
stdlib fallback for same module-path candidates from user/package sources, while
imports discovered inside stdlib files resolve only within the stdlib root and
report `LNC0024` instead of crossing back into package/user roots. Persisted
package replay also rejects hand-edited user import edges that target a stdlib
module when a user source identity declares the same module path, so library
ids and stdlib fallback metadata cannot choose semantic module identity ahead
of GPU module/import records. Stale lockfile replay reports the same precedence
boundary when a newly added package/user module shadows a stdlib fallback that
the persisted graph used earlier. Generated package replay rejects same-path
module candidates from multiple package roots instead of allowing root order to
become semantic module identity; the GPU module records still validate
non-ambiguous source file declarations.
Package lockfiles persist canonical resolved paths in sorted source-root order,
input identity, source identities, import-graph metadata, and optional
produced-artifact identities with target, kind, unique canonical path, byte
length, and stable digest fields. Package
input and source-identity sections are persisted in canonical `(library_id,
path)` order rather than source traversal order, so replay safety does not
depend on CPU import discovery order. Quoted imports, import aliases, glob
imports, and non-leading imports remain unsupported. Package manifest check mode
leaves quoted imports to the GPU resolver diagnostic, but package source-root
replay and package lock generation reject unsupported source-root import forms
with stable unsupported-import diagnostics before writing a lockfile so a
persisted import graph cannot omit an unsupported or late source edge. Live
source-root discovery also rejects glob and alias imports before lookup, so
host-side loading cannot expand unsupported import forms or report them as
missing module candidates. Malformed leading import metadata, such as a missing
semicolon before later items, reports a source-spanned syntax diagnostic instead
of a raw package replay error. Package source-root replay also reports reserved
import path
segments and import globs as source-spanned `LNC0011` diagnostics, keeping
invalid metadata shapes explicit without letting CPU package metadata become
semantic module evidence. Path-shaped imports that use filesystem separators
such as `/` or `\`, or package-name separators such as `.`, now report
source-spanned `LNC0011` diagnostics before package replay can normalize them
into module paths. Module declarations with package-name or
filesystem separators likewise report source-spanned `LNC0016` syntax
diagnostics before package replay can reinterpret package metadata as semantic
module identity. Missing package imports now report source-spanned `LNC0001`
diagnostics at the importing declaration and name the searched source-root
candidate paths, so package names and lockfile roots remain control-plane
metadata rather than fallback module evidence. Over-depth import
metadata reports source-spanned `LNC0012` diagnostics before source-root replay
returns a path manifest or lockfile generation persists import graph metadata.
Over-depth module metadata discovered while producing package lockfiles reports
source-spanned `LNC0014` diagnostics, matching the GPU resolver depth contract
instead of surfacing a raw package replay error. Unterminated block comments and
malformed string/character literals discovered during package-lock replay now
report source-spanned `LNC0016` diagnostics, so malformed source cannot make
replay metadata silently omit later imports.
Package manifests remain
relocatable by requiring relative roots, stdlib roots, and entries that do not
contain parent-directory escapes and do not canonicalize through symlinks
outside the manifest directory. They also require `/` path separators so
manifest metadata has one portable spelling
  for each package-relative path; lockfiles own the canonical absolute path
  artifact. Package entries are also required to use the `.lani` source-file
extension so package state cannot name an arbitrary control-plane file as the
compilation entry while import discovery maps module paths to `.lani` files.
Package-manifest and package-lock CLI paths now reject a symlinked source root
that canonicalizes outside the manifest directory before writing lockfile or
target artifacts, keeping symlink canonicalization as package-boundary evidence
instead of semantic module evidence.
Entry/root mismatches report the resolved entry and the resolved declared source
roots, so CLI metadata diagnostics expose the package boundary that failed
without deriving semantic module identity from root order.
Their source-root-relative module path is bounded to the current eight-segment
GPU module-key slice during manifest resolution, so a package entry that cannot
be represented by the resident resolver fails before lockfile generation.
Direct public package-manifest serde deserialization and serialization now
enforce that same package-relative shape, so callers cannot bypass
`parse_json`/`load_json_file` and persist unchecked root or entry metadata.
Lockfile loading rejects unsorted
resolved roots and rejects persisted input, source-identity, or import-graph
paths whose library ids do not match the resolved user/stdlib roots. It also
requires those persisted source-file paths to remain canonical `.lani` files,
so a hand-edited lockfile or symlinked import candidate cannot replay an
arbitrary package file as source metadata. Import graph edges whose source or
target files are absent from the input/source-identity set are rejected before
replaying live source-root discovery. Import graph edges also persist the
source and target module paths declared by their endpoint source identities,
and public lockfile loading requires those endpoint module-path fields and
rejects missing or tampered endpoint module paths before replaying discovery.
Loaded lockfile objects retain the validated input/source-identity/import-graph
snapshot and revalidate it before source-pack replay or lockfile
reserialization, so a source tree mutation after `load_json_file` fails closed
instead of replaying from current roots with a stale lockfile object.
Replay also checks each import-graph endpoint module field directly against the
endpoint file's resolved source-root-relative module mapping before it trusts
the persisted source-identity table, so tampering both sections to a
package-name spelling still fails closed as control-plane metadata.
Persisted input and source-identity sections must
  explicitly cover the package entry source, so replay cannot treat the entry as
  implicit live-discovery state. A source-root import that resolves back to the
  same source file is rejected as an import graph self-cycle during package
  lockfile generation and replay, before the graph can be persisted as a valid
package contract. The persisted graph also rejects semantic self-cycles where a
source module imports its own module path, even if a hand-edited edge tampers
with the target file fields. Import-graph endpoint module fields are compared
to source identities before replay is accepted; if a hand-edited endpoint uses
the package name converted to module syntax for a different source file, the
lockfile reports the control-plane package metadata boundary instead of
treating that endpoint as semantic module evidence. The persisted graph also
rejects a single source file/import-path pair that names more than one target
file, so hand-edited lockfiles cannot encode an ambiguous import resolution
that the source-root replay would never produce. Package lockfile generation
also rejects repeated leading declarations for the same source/import path with
source-spanned `LNC0011` diagnostics that point at the duplicate and name the
first import line instead of deduplicating source-level import records into one
persisted edge. The duplicate check uses the normalized module path from the
parsed source tokens, so trivia around `::` cannot create a second persisted
edge for the same import path.
Persisted import graph endpoint module identities must also be one-to-one within
each library: if two edges claim the same `(library id, module path)` endpoint
for different source files, replay rejects the graph before source-root
discovery can treat inconsistent metadata as a valid package shape. The reverse
mapping is also fail-closed: one canonical source path may appear in many import
graph edges only with the same `(library id, module path)` endpoint identity, so
hand-edited lockfiles cannot make one file serve as two modules while dependency
resolution is reading replay metadata.
Longer directed import cycles are still replay metadata at this layer:
source-root and lockfile replay load each reachable source file once and
persist each declared edge, while semantic cycle rejection remains owned by the
GPU module/import resolver checkpoint.
Source files with no leading module declaration are
reported with the source-root-relative path and the module identity that path
maps to, so stale or incomplete package sources are diagnosable without making
the filesystem path semantic module identity. A module declaration that appears
only after earlier items now reports a source-spanned syntax diagnostic instead
of being collapsed into missing lockfile metadata. The import path itself must
match the target's declared module identity, so filesystem aliases or symlink
paths cannot turn a source-root path alias into a semantic module alias. Missing
or ambiguous source-root imports report the importing source file as well as the
requested module path and candidate/searched paths, so stale lockfile replay
failures identify the package source that owns the broken import. Hand-edited
lockfile edges that change only the persisted import path while leaving the
target module endpoint unchanged fail before replay can reinterpret a source
file as a renamed module. Stale lockfile
replay also distinguishes import graph identity changes, such as a source file
changing `import app::old;` to `import app::new;`, moving an unchanged import
target from one source module to another, or moving an unchanged source/import
edge to a different target source file even when other imports changed too. It
reports both the persisted edge and the live source-root replay edge before
asking the user to regenerate the lockfile. Lockfile source
identities now bind each file to its resolved source-root index and
root-relative source path, so package-boundary metadata can be replayed without
deriving semantic module identity from package paths. That persisted
source-root-relative path metadata must also use `/` separators, so hand-edited
lockfiles cannot introduce a second platform-specific spelling for the same
package source identity. Public lockfile replay checks the source-root index and
root-relative path for each source identity row before duplicate module metadata,
so a hand-edited row reports package-root ownership drift instead of masking it
as a semantic duplicate. Public lockfile replay rejects source identity rows that
omit source-root index, source-root-relative path, or module-path metadata before
import-graph metadata is considered, so an incomplete source identity cannot be
patched over by control-plane edges. They reject
source-root-relative paths deeper than the
current eight-segment GPU module-key slice, reject multiple leading module
declarations in one source file with source-spanned `LNC0016` diagnostics
because the persisted source identity would otherwise be ambiguous, and reject
non-leading module declarations before lockfile replay can treat package
metadata as valid. Module declarations that do not match their
source-root-relative file path now report source-spanned `LNC0015` diagnostics
before lockfile generation can persist mismatched file-to-module metadata.
Imported module paths use the same depth guard until the GPU module-key bound is
lifted.
Artifact identities are reproducibility metadata for produced files and do not
make output paths or package names semantic module identity. Lockfile validation
also rejects produced-artifact identities that point at the persisted source
input set, so a stale or tampered package artifact cannot be confused with a
source file while replaying package metadata. Loaded lockfile replay and
reserialization validate persisted source/import integrity before checking
optional produced artifact files, so a missing output cannot mask a stale source
graph. The artifact section also rejects multiple identities for the same
canonical produced path, so downstream package tools cannot interpret one output
file as two artifact records. Produced artifact `target` or `kind` labels also
cannot reuse source-pack link artifact or link-record evidence labels such as
`partial-link`, `object-section`, `export-symbol`, or `runtime-service`;
package artifacts are path/digest metadata and cannot claim GPU/link record
ownership by label.
Produced artifact identities must stay outside resolved package and stdlib
source roots regardless of file extension, so control-plane outputs cannot
occupy the source-root namespace while replay metadata is being validated. The
same source-root artifact boundary is enforced by public lockfile validation, not
only by lockfile serialization and replay.
Package lockfile writes use atomic replacement and may create missing
non-source output directories, but output identity is resolved through the
nearest existing ancestor first so `.lani` paths under package or stdlib roots
are rejected before any missing source directory is created. The same boundary
now rejects any lockfile output path inside package or stdlib source roots,
even when the output has a non-source extension such as `.json`. Loading an
existing package lockfile from inside a package or stdlib source root also
fails closed, so control-plane replay metadata cannot live in the uploaded
source namespace.
Persisted library-dependency metadata also rejects stdlib-to-user dependency
edges, matching the live source-root boundary that keeps stdlib imports inside
the stdlib root. Each persisted cross-library library dependency must also have
at least one matching import-graph edge, which keeps coarse schedule metadata
from outliving the source-level import relationship that justified it. Duplicate
dependency rows are rejected as lockfile replay metadata, so a hand-edited
artifact cannot strengthen one source-level import edge into multiple coarse
package dependencies. Package lockfile import graphs also reject library ids
outside the current replay universe of stdlib `0` and package/user `1`, so
hand-edited lockfiles cannot invent extra coarse libraries before package
linking has a real model for them.
The dependency evidence is the explicit source import edge plus validated source
identities; a coarse library dependency row is never evidence by itself. A
user/package source can depend on the stdlib fallback only after user/package
roots fail to provide that module path, while a stdlib source can never acquire
a dependency back into a user/package library through replay metadata.
Explicit source-pack manifests likewise reject duplicate coarse library
dependency edges before scheduling, so CPU planning metadata cannot encode a
stronger dependency graph than the source-pack/library boundary actually
declared.
Path-build manifests with inline source-file rows also require each non-link job
source range to match the source-row library ids, so a persisted job cannot
reinterpret a package/user source path as a stdlib path, or vice versa.
Library partition indexes and pages also reject empty or under-file-count
source-byte summaries before scheduling or link planning consumes them, so
replay metadata cannot defer concrete source provenance to later descriptor or
link artifact records.
Source-pack scheduling continues to use coarse library ordering: a library's
frontend work depends on complete frontend ranges for earlier dependency
libraries, not on fine-grained package-name or per-source import scans.
Persisted compact schedule pages are replay metadata for that library-by-library
work: chunked schedule and link-leaf preparation reject pages whose partition,
frontend range, codegen range, or link job no longer matches the schedule index
before publishing link-group evidence.
Retained artifact manifests also reject partial explicit link-job dependency
lists: an explicit link dependency set must cover exactly the codegen object
producer jobs, while the current empty dependency list remains the compact
implicit "all codegen objects" convention. Package/import metadata must not turn
link readiness into a subset of object producers. Positional dependency-range
sidecars are also all-or-nothing at the build-manifest boundary: a replayed
manifest may omit them entirely, but if present it must carry exactly one row
per job so stale trailing package/link dependency metadata cannot be ignored.
Inline link-batch rows must also carry at least one concrete artifact input,
matching the paged link-batch contract before package/link replay can publish
batch metadata as evidence.
Persisted library, job, job-batch, work-queue, artifact-range, and link-batch
metadata must be canonical: explicit ids are strictly ascending and range
records are stored in ascending non-overlapping order. This keeps replay and
resume paths aligned with the paper-style sort/range/scan model instead of
treating ad hoc per-job scans as semantic evidence.
Compact library partition indexes also fail closed when `partition_count`
exceeds `source_file_count`; every library partition must carry at least one
source file before artifact-shard, schedule, or link planning can consume the
index as replay evidence.
The final hierarchical link group must also cover exactly the plan index input
partition count before link execution can publish completion metadata, so a
stale final group cannot relabel a partial partition range as the package-scale
linked output.
Completed hierarchical link execution metadata must also be backed by the final
execution page record before replay can report resumable completion; the
completed index alone is only summary metadata and cannot imply a GPU-produced
linked output. If that final execution page records paged link inputs, replay
must also validate the corresponding input sidecar pages, so a completed index
cannot hide missing library-interface, codegen-object, or partial-link evidence.
Persisted link execution pages with source files must also carry nonempty
source-line evidence that is at least the source-file count, matching the
existing source-byte provenance rule; stale link artifacts cannot drop line
provenance while crossing package/source-pack replay boundaries.
Final execution pages also reject linked-output keys with empty `src-0-0`
ranges before page persistence, so a zeroed stale final-output summary cannot
stand in for concrete linked-output source coverage.
The artifact-ref index also rejects final linked-output keys whose producer job
or source range does not match the dense final artifact and source-file total,
so stale key metadata cannot stand in for the linked-output artifact contract.
Persisted build artifact manifests keep codegen objects as link-only inputs:
library-frontend and codegen jobs may consume library-interface artifacts, but
they cannot replay object artifacts as package/import evidence before the link
job owns them. Non-linked artifact rows must also match the producer job's
library id and source provenance, so a canonical-looking object key cannot
relabel one package/library's codegen output as another library's link input.
Non-link jobs also reject library-interface inputs whose producer job is not in
that job's scheduled dependency set, even when the artifact IO and use sidecars
are edited consistently. This keeps package/import replay from smuggling
interface evidence across libraries without a GPU-visible dependency edge.
Non-final sidecar pages must be full before a later sidecar page can satisfy a
completed index, so sparse page counts cannot stand in for contiguous link-input
records. Link sidecar pages also reject job slots before their dense group
index, so impossible first-link-job arithmetic cannot publish forged input
artifact evidence. Link descriptor summaries replay only when their explicit
record contracts exactly match the counts-derived contract sequence; reordered,
missing, or extra descriptor rows are metadata tampering and cannot stand in for
GPU link records. Partial-link input keys treat the eight-digit group/job fields
as a minimum width, and replay rejects widened job fields with extra leading
zeroes, so large dense link plans cannot fail their own canonical partial-link
keys or hide a padded producer job. Final and resumed leaf execution pages must
also be the single dense group `0` case before they can claim linked-output
evidence; nonzero final groups must consume prior partial-link outputs instead
of relabeling direct object inputs as a first-link-job-owned executable.
Final and resumed leaf execution pages must also consume the same dense codegen
object job identities as the current link group, so stale object artifacts
cannot imply link completion after the schedule has changed. Completed
reduce-link replay also revalidates each direct
partial-link producer execution page against its current link-group page before
accepting the final linked output, so stale direct or nested producers cannot
hide changed input records behind an otherwise matching final reduce page.
Direct public lockfile deserialization enforces those persisted sections as
well, so lockfiles cannot be downgraded into unchecked root metadata before
replaying discovery.
Top-level qualified constants are only accepted through the
resolver/const-consumer bridge when the declaring module is explicitly present
in the source pack. The normal compiler now uses the LL(1)
tree/HIR path, which receives the lexer-produced `token_file_id` sideband,
validates it during GPU syntax checking, and feeds it into LL(1) HIR ownership
metadata.

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
trait methods, module-qualified generic callees outside the bounded
scalar/literal inference slice, and general qualified values still reject.
Bounded module-qualified generic helpers such as `core::id::keep(1)` and
`core::option::unwrap_or(value, fallback)` can type-check when the HIR call
consumer infers the scalar return from literal or annotated local arguments
using GPU type-ref metadata; this is not full monomorphization or package
loading.
Bounded module-form inherent method calls can type-check when the receiver is
either an annotated concrete type ref or a GPU-resolved call result with a
concrete `fn_return_ref_*`, as in `core::range::range_i32(1, 4).start()`.

## First Real Resolver Slice Checklist

Goal: one source pack can contain multiple module-declared files, path imports,
qualified type paths, and qualified value paths for public top-level consts,
functions, structs, enums, enum variants, bounded inherent method calls, bounded
scalar type aliases, and bounded multi-hop scalar alias chains. No string
imports, import aliases, globs, traits, trait method lookup, broad type aliases,
or generics beyond existing parsed shape.

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
  `decl_parent_type_decl`, `decl_name_token`, `decl_token_start`, and
  `decl_token_end`. Enum-variant parent rows come from the parser-published
  `hir_variant_parent_enum` relation and are mapped through the declaration
  prefix; this scatter pass does not walk declaration ancestors.
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
  `import_module_id`, and `path_owner_module_id` to dense records. The legacy
  root-file fallback is allowed only when the source pack has no module
  declarations at all, so mixed source packs cannot attach an undeclared file to
  another file's module id. This is a GPU table bridge from file ownership to
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
- `type_check_modules_08c_mark_public_decl_keys.slang`: walk the compact
  type/value declaration tables and mark rows whose declaration visibility is
  public. GPU prefix scans over those public flags provide per-table public
  prefixes for import visibility counting.
- `type_check_modules_09_count_import_visibility.slang`: for each resolved path
  import, range-query the sorted `decl_type_key_to_decl_id` and
  `decl_value_key_to_decl_id` tables for the target module id and compute public
  declaration counts from the public-prefix tables. This writes per-import
  type/value counts for GPU prefix scans. It is not a source import expander and
  it does not resolve paths.
- `type_check_modules_09b_scatter_import_visibility.slang`: after GPU prefix
  scans over those counts, dispatch over compact imported-visibility output
  rows. Each row finds its owning import from the per-import visibility prefix,
  then finds the corresponding public declaration by binary search over the
  public-prefix table for the target module range. The output rows carry
  `(importer_module_id, name_id, decl_id)` for type and value namespaces. The
  implementation uses a bounded visibility-row capacity and writes a GPU
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
  HIR call-open marker after regular function return metadata exists. It uses
  parser-published expression-result roots and call-context statement rows for
  argument typing and contextual generic return inference, rather than
  resolving expression wrappers or walking let/return ancestors itself. For
  resolved HIR path expressions that target regular function declarations, it
  writes `call_fn_index` and `call_return_type` at the path head, then clears
  `module_value_path_status`. Return type token metadata remains owned by the
  regular call/method resolver rows rather than this module-path consumer. It
  does not inspect source bytes, hash token text, scan for `::`, perform
  unqualified lookup, or ask the CPU. It is still bounded by the four-slot
  call/type-instance argument cache; the next step is compact argument rows plus
  prefix-summed validation rows, not a wider shader loop.
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
- `type_check_modules_10l_consume_value_enum_calls.slang`,
  `type_check_modules_10l2_validate_value_enum_call_payloads.slang`, and
  `type_check_modules_10l3_finalize_value_enum_calls.slang`: consume resolved
  local and qualified enum-variant calls after contextual type-instance records
  exist. The first pass validates constructor shape, the second pass validates
  one payload slot per GPU thread, and the third pass clears
  `module_value_path_status` and publishes the parent enum `call_return_type`
  only when no payload row rejected the candidate. The current parser call and
  variant payload records are still bounded to four slots and fail closed beyond
  that until payload rows are compacted into an unbounded relation.
  Non-constructor symbolic generic returns, exhaustive match semantics, enum
  layout, and backend lowering remain separate checkpoints. The bounded
  stdlib-shaped match type-check slice consumes HIR match spans plus these
  resolver/type-instance arrays for enum payload arms and reads constructor
  results from the current callee-token/path-head `call_return_type` slot before
  the legacy adjacent-token fallback, but it is not package loading,
  exhaustiveness, layout, or codegen support.

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
  `decl_type_key_count_out`, `decl_value_key_count_out`, `decl_status`, and
  `decl_duplicate_of`. After declaration validation and namespace marking,
  `decl_status` and `decl_duplicate_of` are reused as public-prefix scratch for
  import visibility counting.
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
- Value call consumer projection: `call_fn_index` and `call_return_type` for
  resolved regular function calls, keyed by the HIR-produced
  `module_value_path_call_open` marker. `call_return_type_token` remains owned
  by the regular call/method resolver rows. General value lookup outputs such
  as `resolved_call_decl` and `visible_decl` are a later checkpoint.
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
  files or control-plane source-root candidate files, uploads source-pack
  buffers, and does not rewrite module names, precompute declarations, decide
  visibility, perform semantic path lookup, resolve quoted or glob imports, or
  allow stdlib imports to cross into package/user source roots.
- Package/source-root replay now rejects an `import` before the leading
  `module` declaration and rejects import globs and aliases with source-spanned
  `LNC0011` diagnostics. Persisted import graph edges are valid replay metadata
  only after the source file has a declared module identity and an explicit
  module-path import for the GPU resolver to own.
- Hierarchical linked-output artifact stores now validate the same canonical
  producer-job and source-range fields as retained linked-output artifact refs.
  The store boundary rejects malformed or noncanonical linked-output keys before
  publishing bytes, so link replay cannot treat a kind-only artifact path as
  durable linked-output evidence.
- Descriptor-mode package/source-root preparation is not implemented yet.
  Until it is, the CLI must reject `--package-manifest`, `--package-lockfile`,
  `--source-root`, or `--stdlib-root` when combined with descriptor, prepare,
  artifact-root, or contract-output flags. It must not route those inputs
  through the in-memory source-root compiler path while claiming descriptor
  output.

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

- No CPU source concatenation, semantic import expansion, alias expansion,
  generic substitution, semantic precheck, declaration lookup, or declaration
  visibility logic.
- CPU file/path handling is limited to reading explicitly supplied source-pack
  files or `--source-root`/`--stdlib-root` candidate files and uploading byte buffers plus
  file-span metadata. Module identity and import identity are computed from
  GPU-parsed declarations and import items.
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
