# Self-hosted extraction and verified x86 compilation

The user goal is the complete seven-step pipeline below. The old Rust
exporter has been removed; the extraction implementation is in Lanius.
The earlier self-extraction-only goal is superseded by this expanded scope.

All executables and execution tests in this workflow target x86-64 Linux ELF,
including the untrusted GPU bootstrap. Do not use a Wasm fallback. The existing
GPU compiler is bootstrap machinery, not the verified compiler/backend in
Lanius required by milestone 4.

The first native tests exposed missing conditional-call lowering, runtime-length
array indexing, a six-slot argument ABI limit, and an incoherent raw-array
layout. Conditional lowering, direct-call stack arguments, checked fat-slice
access, and coherent packed `i32` arrays now pass focused native execution
tests. The checked-in Lanius syntax extractor builds and runs as a static
x86-64 ELF. It emits one compact logical `ArtifactPack` for the exact 18-file
source closure recorded in `source-closure.txt`. Lean decodes it through fixed
general infrastructure and returns proof-carrying syntax evidence plus an
independently reconstructed, origin-checked Surface program for every unit.
This completes milestone 2. The milestone-3 self-embedding now validates exact
sources, syntax, reconstructed Surface, proof-producing source-to-Core
lowering and whole-program x86 Core typing. A separate extractor-specific
checker links the declared source `main` to a well-formed Core executable
entrypoint and checks its return codes. General Core preservation proves memory
safety for every terminal execution of an entrypoint accepted by that checker.
Ordinary extracted programs need neither that entrypoint nor those return codes.
The extractor's exact success/failure I/O refinement theorem is still absent,
so milestone 3 remains incomplete.

The extractor embeds the exact grammar as one hexadecimal string token, decodes
it in Lanius, and uses dynamically allocated native pointer/length slices.
Chunked host I/O replaced the former one-syscall-per-byte bridge. Its output is
one compact hexadecimal string decoded by
`Lanius.Extraction.CompactArtifact`; malformed counts are bounded by the
remaining payload before allocation or iteration. This avoids both the old
121-file generated proof forest and millions of generated Lean constructor
syntax nodes. The process now assembles the entire module before its single
logical stdout write, so pre-write failures cannot expose a partial
certificate. The generated Lean checker then rereads its ordered input paths
and requires the decoded pack's source names and bytes to equal those
independent inputs. It then reconstructs Surface from the accepted parse
artifacts and checks all Surface-origin claims. Closure selection and bootstrap
invocation remain outside the proved Lanius execution semantics, while the
exact execution/output relation and general extractor correctness theorem keep
milestone 3 incomplete.

`Lanius.Extraction.ExtractorContract.Success` now fixes the execution theorem's
target: exact rendered stdout, exact ordered input files, accepted syntax
evidence, preserved source files and arguments, and no leaked file handles.
It intentionally does not require type correctness of the extracted input:
`AcceptedSuccess` adds that obligation only after the typed-Core checker
accepts. A type-error fixture guards this boundary.
The source-bound compact checker also retains independently reconstructed
Surface values with their validity proofs, so subsequent lowering can consume
them without reconstructing a second copy.

The output proof now covers signed-word byte serialization, the complete Core
packing loop (including termination, input preservation, and write footprint),
heap read-after-write, disjoint-view synchronization, and exact stdout for a
successful Core host call. The clearing loop is also proved and establishes
the zeroed-word precondition. A proof-producing structural check locates both
exact loops in the checked source `main`, without copying its body.
`stdout_after_packing` derives the packed buffer and its encoding from the
loop execution. It requires initial ownership, valid registered blocks, and
distinct view addresses; heap well-formedness then supplies non-overlap.
Pointer exposure preserves distinct addresses, while raw-slice construction
requires a fresh address. The enclosing source execution must still establish
these entry conditions and connect the phases in order.
These results do not yet prove the extractor's full execution contract.

The input proof covers the actual Core host read through heap synchronization
and scratch-word refresh. The complete unpacking loop is proved terminating;
it copies exactly the refreshed bytes while preserving earlier chunks, unused
output capacity, and the packed scratch buffer. `unpack_after_read` composes
these proofs, deriving the copied bytes from the file contents rather than
assuming a correct scratch encoding. The enclosing file-reader guards must
still establish its ownership and capacity preconditions. The source checker
links this exact loop to `verified::byte_io::read_file` in the self-embedding.
The read-preservation theorem also derives coherence for other in-range i32
buffers and proves they survive both synchronization passes unchanged. Raw
slice allocation preserves unique backing roots; exposing an existing slice
pointer preserves the registry. The capacity-probe branch is proved to compute
the bounded, positive request size and is linked to the checked source.
The outer reader loop, guard composition, and caller-side handle lifecycle
still need to be composed with these stage proofs.

Frontend proof reuse now has a proof-producing global-ID relocation checker.
Against the current self-embedding, all 18 old lexer functions, 6 token-scan
functions, and 20 parser functions match their relocated definitions; so do
49 constants and 5 structure layouts. Both sides use x86-64 Core. Type IDs use
an invertible permutation, not a non-surjective offset, so pre-existing caller
values can be transported too. This complete source/link check took 19.64 s.

The generic relocation lemmas cover scalar operations, nested assignments,
parameter binding and call state, enum matching, slices, i32 encoding, and
heap/view synchronization. Their focused regressions and axiom audit pass
(1.34 s with dependencies already built); production proofs use only Lean's
standard axioms, not native evaluation as a proof oracle. The full fuel
induction is now proved: `Semantics.Relocation.Execution.evaluates` and
`executes` preserve successful executions of internal modules in the larger
program. This covers expressions, calls, memory operations, statements, and
loops; the internal-call condition is checked with proof-producing evidence.
The complete transport build took 9.38 s. Checking its assumptions against the
three actual frontend modules and exact self-sources took 20.11 s. Its axiom
audit contains only `propext`, `Classical.choice`, and `Quot.sound`.
The merged nine-module frontend now has checked name-based cross-module
mappings. Of its 54 functions, 53 match exactly. The exception is the compact
string-based `keyword_kind`, which replaced numeric character comparisons;
its new helper also shifted two function IDs. The merged transport check
correctly rejects that changed body rather than treating it as equivalent.

The compact ASCII helper now has a kernel-checked proof of its complete Core
body: string exposure, exact raw-word borrowing, decoding, local bindings,
terminating byte comparison, and both return paths. It preserves caller cells,
locals, and the host world. The body proof checked in 0.49 s. The proof exposed
an actual source bug: ordinary strings do not guarantee readable word padding.
Keyword literals now include explicit zero padding, while comparison lengths
exclude it. No memory-model relaxation was needed. Execution tests cover all
keyword spellings, every mismatch position, and the source dispatcher against
the independent lexer table, including keyword prefixes and suffixes. The
updated full self-source check and execution regressions took 19.29 s.

The helper is now composed through keyword dispatch. The general proof covers
rule choices, length branches, the fallback return, and the end-minus-start
initializer. Exact-spelling lookup is proved equivalent to the independent
lexer's keyword classifier, including its handling of non-byte integers.
`Dispatch.Checked.executes` ties that theorem to an actual Core body after
checking its matcher, padding, constants, and complete reference-table
permutation. The updated self-source check accepted all six length groups in
20.85 s. New production proofs use only Lean's standard axioms.

`Kind.result_canonicalKind` connects the callable classifier to the independent
lexer specification. The actual `canonicalize_in_place` source now passes a
proof-producing whole-body check. Its first loop has a total-correctness proof
for filtering and keyword retagging; its second loop has a total-correctness
proof for inclusive-range marking, including empty and singleton streams.
These proofs account for the caller's spare buffer capacity and fresh helper
allocations. They prove each iteration from Core execution rules rather than
assuming an abstract iteration is correct. The loop declarations checked in
0.59 s and 0.65 s respectively; these are incremental proof-build times, not
whole-extractor checking times. Their axiom audit passed without `sorry` or
project-specific axioms. `Compaction.CheckedSource.evaluates_call` now composes
both loops with local initialization, scope cleanup, the return, and the actual
function call. It proves the canonical token count, the encoded output prefix,
and preservation of the rest of the caller's capacity. The function body and
call proof declarations checked in 0.51 s and 0.46 s. Regression execution of
the checked source covers empty input, singleton keywords, all-trivia input,
contiguous and separated range operators, and several spare-capacity sizes.

The old public lexer/parser contracts still need composition in the complete
extractor. Fresh borrowed storage means the new matcher preserves caller cells
and the host world, but not literal heap/view identity; `CellEffect` states
that distinction without claiming raw-memory preservation. No whole extractor
I/O refinement theorem follows from these results alone. Milestone 3 remains
incomplete.

## Milestones and acceptance evidence

1. **Lanius extractor.** Build on the current Lanius lexer/parser. Implement
   derivation materialization, semantic analysis and lowering required by the
   embedding, and serialization in Lanius. Support the complete extractor's
   source closure; reject unsupported inputs explicitly. Differential tests
   against the Rust exporter are useful but are not a correctness proof.
2. **GPU bootstrap.** Compile that source with the existing GPU compiler and
   execute the resulting untrusted program. Host services may supply memory
   and I/O, but must not perform parsing, lowering, or extraction on its behalf.
   Record the source closure, compilation command, and executable identity.
3. **Self-extraction and extractor correctness.** Run the Lanius executable on
   its own source closure, produce the deep Lean embedding, and validate the
   source-to-embedding connection. Then prove the extractor's general
   correctness for supported inputs. An accepted embedding alone does not
   establish that general theorem. Include memory safety, failure behavior,
   and exact input/output semantics in the stated contract.
4. **Verified Lanius x86 backend.** Implement a simple backend in Lanius and
   prove that emitted machine code preserves the input IR semantics. Specify
   instruction encodings, machine state, memory, calling convention, runtime
   boundary, and supported IR. It must support the extractor, not just a toy
   arithmetic example. State any limitations explicitly.
5. **Whole compiler correctness.** Compose the frontend, lowering, and backend
   theorems into a source-to-x86 result. Cover the supported language and the
   whole compiler/extractor source closure; no omitted pass may be silently
   assumed correct. Identify environmental assumptions separately.
6. **Extractor x86 executable.** Run the verified compiler to produce it.
   Establish the connection between the exact executable bytes and the
   compiled program in the correctness theorem. A proof about the compiler
   algorithm does not alone justify an arbitrary bootstrap executable.
7. **Fast trusted extraction.** Provide an explicit trusted extraction boundary
   that relies on the established compiler/extractor correctness. The user
   permits certificates, object-file integration, or explicit extraction
   axioms as appropriate. Keep these assumptions identifiable and separate
   from ordinary kernel-checked theorems; do not disguise trusted results as
   kernel reduction. Bind results to exact source, tool version, and output.
   Measure fresh per-program extraction, emission, loading, and checking with
   only general infrastructure prebuilt. Target a couple of seconds, not
   minutes; cached prior program certificates do not satisfy this target.

## Current checkpoint

- `src/verified/parser.lani` is a workspace-backed Earley recognizer. The
  extractor materializes its retained derivation without reparsing and
  serializes ordered parse nodes.
- All bootstrap artifacts used by this plan are x86-64 Linux ELF executables.
  Historical Wasm recognizer tests are not part of the bootstrap or trust path.
- The former Rust `laniusc-formal-export` extractor has been removed. The
  supported syntax-certificate producer is now `src/extractor.lani`; it does
  not yet emit complete Surface/Core semantics.
- `src/verified/host.lani` is the extractor's deliberately small host boundary.
  It replaces four unrelated general-stdlib files in the proof closure and
  contains only the allocator, filesystem, argument, output, and three raw-view
  operations the extractor calls. Core syntax, typing, executable semantics,
  artifact decoding/checking, and fuel stability now model
  `i32_slice_from_raw_parts`, `i32_slice_data_ptr`, and `string_data_ptr`.
  Connecting those operations through the complete program-elaboration and
  preservation proofs remains part of the extractor execution theorem.
- On September 6, 2026 the current x86 extractor emitted its exact 18-file,
  2,331-line, 105,021-byte closure in 1.22 seconds with about 39 MiB peak
  RSS. With shared Lean infrastructure built, compact decoding plus
  proof-producing exact-source, syntax, reconstructed-Surface, source-to-Core
  lowering and whole-program x86 Core typing took 18.97 seconds
  with about 1.65 GiB peak RSS. A pruned
  postorder-origin lookup avoids rescanning irrelevant parse subtrees. These
  are major representation improvements, but the full-closure check is not yet
  the milestone-7 couple-of-seconds target.
- The self-embedding check with extractor-specific entrypoint analysis and
  ordered count/clear/pack, input-unpacking, and capacity-probe source linkage
  took 19.70 seconds.
  The loop and memory proofs
  depend only on Lean's standard `propext`, `Classical.choice`, and `Quot.sound`;
  they introduce no project-specific axiom or `sorryAx`.
- The focused input/output proof and regression build took 6.42 seconds.
  Input-loop execution tests cover every byte value at every packed-word lane,
  empty input, partial final words, preceding chunks, and unused capacity.
  After the later preservation and capacity-probe additions, the incremental
  focused build took 2.35 seconds. A Core host-call regression covers a partial
  read followed by EOF, preserving an unrelated signed buffer and the unread
  scratch tail. The impacted relational adequacy module also checks.
- File reads reuse the existing scratch slice rather than registering an
  overlapping raw view for every file. The GPU compiler also now uses narrow
  moves for known narrow scalars; unclassified values retain full pointer
  width. This fixes a native failure where an i32 argument carried stale
  stack bytes in its upper half.
- The generic checker accepts both a library without `main` and a program
  returning `42`; extractor-specific entrypoint analysis is separate.
  `writeStdout_exact` and `writeStdout_invalidRange` prove the modeled host
  output boundary. They do not prove that the Lanius packing loop supplies the
  correct bytes, or that native OS writes cannot be short.

## Next work sequence

The complete x86 Core embedding is now synthesized from the checked Surface
values without introducing a second program copy, and it retains indexed
lowering evidence for internal functions plus checked extern construction.
Next prove the extractor I/O contract now exercised by the source-bound
self-pack and prove the Lanius extractor implementation refines
the Lean specification for every supported input, including explicit failure
behavior and memory bounds. Only after that
proof boundary is stable should the x86 backend semantics and implementation be
fixed around the actual IR required to compile the extractor.

Backend design must follow the semantics needed by the resulting extractor;
do not invent an incompatible IR just to obtain an easy backend proof.
No milestone is complete yet merely because this plan exists.

## Historical baseline

On September 5, 2026, `cargo test -j 1 --test verified_parser -- --nocapture`
passed: one GPU-compiled recognizer test, 3.27 s test execution after 25.47 s
incremental build. That historical Wasm route is not used by the current x86
bootstrap and establishes no part of the x86 trust chain.
