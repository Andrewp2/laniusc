# Self-hosted extraction and verified x86 compilation

The user goal is the complete seven-step pipeline below. The existing Rust
exporter is a bootstrap reference, not the intended extraction implementation.
The earlier self-extraction-only goal is superseded by this expanded scope.

All executables and execution tests in this workflow now target x86-64 Linux
ELF, including the untrusted GPU bootstrap. Do not use a Wasm fallback. The
existing Rust/GPU x86 backend is bootstrap machinery, not the verified backend
in Lanius required by milestone 4.

The first native tests exposed missing conditional-call lowering, runtime-length
array indexing, a six-slot argument ABI limit, and an incoherent raw-array
layout. Conditional lowering, direct-call stack arguments, checked fat-slice
access, and coherent packed `i32` arrays now pass focused native execution
tests. The standalone syntax extractor builds and runs as x86-64. It now emits
one logical `ArtifactPack` for the exact 24-file source closure recorded in its
bootstrap manifest. Lean has accepted every unit and the aggregate pack theorem.
This is milestone-2 completion for the current syntax extractor and substantial
milestone-3 evidence; Surface/Core completeness and the extractor's general
correctness theorem are still absent.

The generated extractor entry embeds the exact grammar as one hexadecimal
string token, decodes it in Lanius, and uses dynamically allocated native
pointer/length slices. The x86 executable extracts all closure files in one
process while reusing the initialized grammar and workspace. Balanced parse,
semantic, and source-byte trees prevent whole-table normalization. The full
pack is split into five proof phases per source so each expensive kernel check
starts with a fresh bounded heap. On September 5, 2026 the 121-module closure
passed under a 12,000 MiB per-process ceiling, and `extractedPackValid` had no
`sorryAx`. The still-untrusted import resolver, missing exact execution/output
relation, and absent general extractor correctness theorem keep milestone 3
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
- `crates/laniusc-formal-export` currently performs extraction in Rust.
- `stdlib/std/fs.lani` and `stdlib/std/io.lani` declare host interfaces. Their
  actual bootstrap bindings and proof contracts must be checked; declarations
  or capability constants are not sufficient evidence of executable support.
- The current Lanius syntax extractor emits and renders its full authenticated
  closure in 7.34 s. Cold Lean validation is still about 23 minutes; a warm
  freshness check is 0.12 s. Neither timing is yet the milestone-7 fresh
  per-program trusted-certificate path.

## Next work sequence

First prove the exact closure and extractor I/O contract now exercised by the
accepted self-pack. Then complete Surface/Core extraction and prove the Lanius
extractor implementation refines the Lean specification for every supported
input, including explicit failure behavior and memory bounds. Only after that
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
