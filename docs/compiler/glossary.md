# Compiler Glossary

This glossary defines project-specific terms used across the compiler
internals docs. It is intentionally narrative. Use `generated/reference.md` for
the current extracted lists of functions, shader load sites, pass loader fields,
status codes, buffer carrier structs, and large structs.

## Terms

### Active HIR

The subset of semantic HIR rows selected for a pass family. Many type-check and
backend passes record indirect dispatches from active-row count buffers instead
of dispatching over all capacity.

### Artifact

A persisted output or intermediate produced by source-pack planning or
execution. Artifacts include library interfaces, codegen object data, linked
outputs, and manifest records that describe where those bytes live.

### Artifact Descriptor

A JSON contract for a source-pack artifact. Descriptors record the artifact
target, stage, source coverage, dependency counts, record arrays, semantic
record rows, and runtime-service requirements without requiring consumers to
interpret backend-specific bytes.

### Artifact Root

The filesystem directory owned by a source-pack build. It contains manifests,
pages, shards, progress files, target-specific artifact paths, and work-queue
state. Compiler code should access it through store helpers rather than
constructing paths by hand.

### Artifact Shard

A bounded persisted slice of artifact execution metadata. Shards let workers
claim and execute source-pack work without loading the whole build graph.

### Backend Boundary

The phase boundary after parser and type-check status have both succeeded.
Backends consume parser HIR plus retained type-check metadata and report
target-specific status or bytes.

### Backend Feature Measurement

The x86 prepass that counts active backend features before full lowering. It
sizes optional backend buffers and selects pass work; it must not decide
language semantics.

### Bind Group

A wgpu resource binding set created from Slang reflection and Rust resource
maps. Reflection removes most hand-written binding indices, but Rust and Slang
still share a resource-name contract.

### Bind Group Cache

A cache of reflected bind groups for resident phases. It is valid only while the
buffer identities and capacities used to create those bind groups remain valid.
If a pass depends on a new buffer, the resident fingerprint must include it.

### Buffer Carrier Struct

A Rust struct whose fields carry many buffers or bind groups across a phase
boundary. Use the generated reference to find current carrier structs before
editing retention, bind models, or backend inputs.

### Capacity

Allocated logical space for a row family, scratch table, dispatch domain, or
persisted page. Capacity is not the same as active count and is not a language
limit unless the owning phase deliberately reports exhaustion as a
source-addressed diagnostic. See [Capacity and limits](capacity-and-limits.md).

### Codegen Metadata

Type-check-owned semantic data exposed to backends, such as resolved
declarations, call rows, type-instance rows, visible declarations, function
context, and method metadata.

### Codegen Unit

A bounded source-pack unit that produces backend object data. `codegen::unit`
plans codegen units independently from the backend implementation that lowers
one unit to bytes.

### Command Encoder Boundary

A host-side recording boundary where the compiler stops adding GPU work,
submits a command buffer, and reads only the status, count, or output data
needed for the next phase.

### CompileError::Diagnostic

The user-facing diagnostic result used by compiler APIs. GPU status words are
transport records; the compiler boundary turns them into `CompileError` values
with stable diagnostic codes and source labels.

### Compute Pass

One reflected GPU shader invocation recorded by Rust. Passes belong to the
phase that owns their inputs and output contract, not necessarily the phase with
the most convenient buffer.

### Compiler Orchestration

The host-side `GpuCompiler` layer that sequences resident lexer, parser,
type-checker, backend, descriptor-worker, diagnostic, and timing boundaries.
It coordinates phase owners; it does not own language semantics.

### Descriptor Work Queue

A persisted source-pack execution mode where workers claim ready descriptor
items from the artifact store, execute bounded work, write artifacts, and update
progress.

### Diagnostic Registry

The CLI/compiler registry for stable diagnostic codes, messages, notes, help,
categories, and output formatting. It is separate from compact GPU status
codes.

### Dispatch Arguments

GPU buffers that describe how much work a later pass should record. They are
often produced by earlier count/scan passes and consumed through indirect
dispatch.

### Execution Batch

A bounded group of ready source-pack jobs that can be claimed by a worker.
Batches preserve dependency constraints while limiting how much state one worker
must load.

### Execution Wave

A topological layer in the source-pack job schedule. Jobs in the same wave can
run once their earlier dependency waves have produced required artifacts.

### Fingerprint

The resident type-check cache key component that captures buffer identities and
other reuse-sensitive facts. Stale fingerprints can reuse invalid bind groups
and cause correctness bugs.

### Formatter

The lexical source formatter used by `laniusc fmt` and LSP full-document
formatting. It preserves non-whitespace token text and token order while
rewriting whitespace, newlines, and indentation; it does not parse, type check,
resolve imports, create a GPU device, or rewrite semantics.

### Frontend Unit

A bounded source-pack unit that runs lexer, parser, and type checking for a
library interface slice. Frontend units produce interface artifacts consumed by
later codegen or link jobs.

### Generated Reference

`docs/compiler/generated/reference.md`, produced by
`tools/compiler_inventory.py`. It owns volatile tables extracted from Rust and
Slang sources.

### Rustdoc Coverage

The generated-reference heuristic that counts public, crate-public, and
scoped-public Rust items under `crates/laniusc-compiler/src` and reports whether
they have nearby Rustdoc comments. It is freshness evidence, not proof that the
comments explain the right contract. See [API docs and Rustdoc](api-docs.md).

### Generated Table

A checked-in compiler input derived from Rust or grammar sources, such as
`tables/lexer_tables.bin`, `tables/parse_tables.bin`, generated token
constants, or generated production constants. Generated tables must be
regenerated from their owning source instead of edited by hand. See
[Grammar and generated tables](grammar-and-tables.md).

### Grammar

`grammar/lanius.bnf`, the BNF-with-tags source file used by
`parse_gen_tables` to build parser tables, parse-table metadata, and generated
production constants.

### Maintainer Tool

A command or script used by compiler authors for generated inputs, local
debugging, fuzzing, benchmarking, acceptance planning, generated references, or
repo maps. Its output is evidence only for the claim that the tool is designed
to prove.

### GPU-Resident Pipeline

The compiler architecture where source facts are transformed by GPU passes and
kept in GPU buffers across phases. The host orchestrates phase boundaries,
capacity selection, diagnostics, and output readback instead of walking a full
AST during normal compilation.

### GpuCompiler

The main live compiler object. It owns the GPU device reference, phase drivers,
parse tables, resident type checker, optional backend generators, and the
resident pipeline lock.

### HIR

High-level intermediate representation. In this compiler, HIR is not a
pointer-rich host AST; it is a collection of dense GPU record arrays keyed by
semantic node ids and construct-specific row ids.

### HIR Node

A semantic node row produced by parser HIR construction. HIR nodes carry source
token spans and connect syntax-owned shape to type-check and backend consumers.

### HIR Validator

A parser-owned or phase-owned check over resident record rows after readback.
Parser HIR validators prove that row families such as items, types, parameters,
calls, arrays, matches, structs, statements, and source addresses are internally
consistent before downstream phases rely on them.

### Indirect Dispatch

A GPU dispatch whose workgroup counts are read from a buffer produced by earlier
passes. It is used when active records are counted on GPU.

### Interface Artifact

The source-pack artifact produced by frontend/library work. It records enough
checked library information for dependent jobs to proceed.

### Package Lockfile

Resolved package replay metadata. It stores canonical roots, input identities,
source identities, import graph edges, and optional produced-artifact evidence
so package/source-root loading can reject stale metadata before compiling.

### Package Manifest

Relocatable package metadata. It stores a package name, package-relative source
roots, optional stdlib root, and entry source path. Semantic module identity
still comes from source `module` and `import` declarations.

### Parse Table

The checked-in parser table data stored in `tables/parse_tables.bin` and loaded
as `PrecomputedParseTables`. It carries pair-projected stack/production streams,
production arity, LL(1) prediction cells, production RHS streams, and start
nonterminal metadata.

### Production Tag

The optional `[tag]` on a grammar production. Tags are converted into generated
`PROD_*` constants consumed by parser and HIR shader code, so renaming one is a
shader/Rust contract change.

### TokenKind

The Rust enum that owns the compiler's numeric token namespace. Grammar
terminals resolve through `TokenKind::from_name`, and
`shaders/generated_token_ids.slang` must match its discriminants.

### LaniusBuffer<T>

The owner-facing typed wrapper around `wgpu::Buffer`. It preserves logical
element count, allocated byte size, and element type at ownership boundaries.
Borrow raw `wgpu::Buffer` only at low-level wgpu call sites or externally owned
buffer boundaries.

### Library

A source-pack grouping of source files with dependency edges to other
libraries. Source-pack schedules are built from library order and dependencies.

### LL Status

The parser's compact status record for LL/parser acceptance and rejection. It is
decoded by host mapping code into syntax diagnostics.

### LSP Surface

The `laniusc lsp` tooling boundary. It includes no-run capability metadata, a
minimal stdio JSON-RPC server, full-document open-document state, formatting,
pull diagnostics, and LSP-specific error-data contracts.

### Manifest

A serialized description of source-pack planning or execution state. Manifests
name jobs, artifacts, batches, shards, dependency ranges, target paths, and
progress checkpoints depending on the stage.

### Module Path State

The type-checker submodule state that owns module, import, declaration, path,
visibility, and projection relations. It connects source-pack/library structure
to semantic name resolution.

### Owned Retained Wrapper

A Rust struct that owns cloned buffer handles after an earlier resident phase is
released. Backends and later phases should consume retained wrappers instead of
borrowing dead scratch or cache-owned buffers.

### Page

A bounded persisted record file in the source-pack store. Pages let preparation
and validation work on fixed-size slices instead of loading all records at once.

### PassData

The reusable GPU pass descriptor built from SPIR-V and Slang reflection. It
contains the compute pipeline, reflected bind group layouts, shader id,
thread-group size, and parsed reflection.

### Pipeline Cache

wgpu pipeline-cache data stored under the configured cache directory. Cache
identity includes adapter/build/toolchain/shader facts so stale cache blobs can
be discarded.

### Public Compiler API

The Rust call surface under `compiler`: `GpuCompiler`, process-global compile
helpers, source-pack planning and execution APIs, descriptor workers, diagnostics
types, and re-exported source-pack records.

### Readback

Copying GPU buffer data to a map-readable buffer and waiting for the host to
inspect it. Readback is required for status and output boundaries but can
dominate runtime when used broadly for debugging.

### Reflection

Parsed Slang reflection JSON used to build wgpu bind group layouts, find shader
resource parameters, and read compute thread-group sizes.

### Resident Buffer

A buffer owned by a phase driver or resident state and reused across compile
operations while the cache key remains valid. Resident buffers are a performance
feature with lifetime and correctness rules.

### Resident Pipeline Lock

The `GpuCompiler` lock that serializes public operations using resident
frontend, type-check, and backend state. It prevents concurrent operations from
observing incompatible cached buffers or transient bind groups.

### Resident State

Long-lived phase-owned storage that can be reused across operations. The type
checker's resident state contains relation buffers, scratch buffers, bind
groups, and cache metadata.

### Retained Buffer

A buffer handle intentionally preserved for a later phase. Retained buffers are
the safe way to cross phase lifetimes, especially from parser to type checker
and from parser/type checker to codegen.

### Row

A dense GPU-table entry. Rows are usually indexed by a compact id rather than by
host pointers. A row id is not automatically source-mappable; diagnostics should
carry or recover a token, HIR node, or source-file id.

### Runtime-Service Requirement

A descriptor row stating that an artifact needs a host/runtime service such as
allocation, filesystem, stdio, clock, or process access. Requirements are
contract-only until a runtime binding exists, so runtime-bound descriptors must
not claim executable target bytes.

### Semantic Metadata

Type-check output that describes language meaning after parser HIR is built:
resolved declarations, type refs, value refs, call/method rows, predicate facts,
visibility, and backend-facing summaries.

### Shader Artifact

A generated shader output, usually `{shader-key}.spv` plus
`{shader-key}.reflect.json`. Debug native builds load artifacts from disk;
other builds use the same artifact path helper.

### Shader ABI

The contract between Slang source, generated artifacts, reflection JSON, and
Rust pass construction. It includes artifact keys, reflected parameter names,
binding types, dynamic offsets, thread-group size, and phase-owned buffer
lifetimes.

### Shader Key

The extensionless path used by Rust to load a shader artifact, for example
`parser/hir/nodes` or a type-checker pass key. Shader keys are listed in the
generated reference.

### Source File Id

The source-pack file index carried through lexer token file ids and HIR token
metadata. Diagnostics use it to map packed token positions back to original
paths.

### Source Pack

A library-aware collection of sources, dependencies, planning records, and
optional persisted artifacts. Source packs are not just a multi-file wrapper;
they introduce units, jobs, manifests, work queues, and resumable execution.

### Source Span

The byte range and file identity used for diagnostics. A useful status payload
should map to a source span through a token, HIR node, source-file id, or
retained metadata.

### Standard Library Root

A directory passed through `--stdlib-root`, package `stdlib_root`, or public
`*_with_stdlib` APIs. It supplies ordinary `.lani` source files for stdlib
module-path imports; it does not auto-import modules or imply host runtime
service execution.

### Status Buffer

A compact GPU buffer used to report phase acceptance or a rejection payload.
Status buffers are decoded by phase drivers and then mapped to user-facing
diagnostics at compiler boundaries.

### Token

The lexer's compact source record containing kind, start, length, and
source-file metadata. Parser, type-checker, and backend diagnostics rely on
tokens to recover user source locations.

### Type Instance

The type-checker record family for generic/type argument relationships, type
refs, member receiver refs, aggregate refs, and related substitutions. These
records are represented as rows and refs rather than recursive host structures.

### Validation Scope

A wgpu error scope around selected GPU work. Validation scopes are a debugging
tool for resource and submission mistakes, not a substitute for phase-owned
status diagnostics.

### Visible Declarations

Type-checker records describing lexical/module visibility for declarations.
They support name lookup, method/call resolution, and backend metadata.

### Work Queue

Persisted source-pack state for claimable, dependency-aware execution. Workers
claim ready items, execute bounded work, store artifacts, and mark completion so
other workers can continue.

### WASM Backend

The target backend that records GPU passes for WASM output. It shares the
frontend and type-check metadata shape with x86 but currently has a narrower
support surface and must fail closed for unsupported source shapes.

### x86 Backend

The GPU backend that lowers parser HIR plus retained type-check metadata to
x86_64 ELF/object bytes. It owns backend capacity planning, recording passes,
status readback, and backend diagnostic mapping, but not language semantics.

### Worker Claim

A persisted reservation for one or more ready work-queue items. Claims protect
bounded source-pack execution from duplicate workers and include progress or
lease state used for resumption.

## Update Rule

Update this glossary when a compiler change introduces a new shared term,
changes the meaning of an existing term, or moves a concept across phase
boundaries. Do not add volatile inventories here; add or extend generated
reference extraction when the useful fact is a current list of names or files.
