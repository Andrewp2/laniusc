# Historical bootstrap syntax extraction

> **Historical record:** the Rust CPU exporter and the Python bootstrap,
> rendering, and pack-check launchers described by this document have been
> removed. The next supported workflow must be a checked-in Lanius extractor
> entrypoint that emits its complete proof input directly. Commands below were
> removed rather than leaving a stale path that silently reintroduced a second
> extractor outside Lanius.

This workflow targets an untrusted GPU-compiled x86-64 Linux ELF executable.
The Lanius lexer, parser, derivation materializer, and syntax emitter run natively;
the launcher only captures output and adds Lean proof commands. There is no
Wasm fallback. Lean must check the output before it is accepted.

**The native syntax bootstrap, exact source-closure self-extraction, and Lean
acceptance of the resulting logical pack are working.** Runtime-length slice indexing and
the raw `i32` array view now have executable x86 coverage. Native `[i32; N]`
storage is a coherent packed little-endian view: language indexing and host
reads or writes observe the same four-byte elements. The bootstrap commands
below produce an x86-64 ELF extractor and a Lean-checkable syntax artifact.
The embedded grammar is represented by one hexadecimal string token and
decoded by the Lanius entry at startup; it remains part of the source and proof
boundary without forcing the generic parser through thousands of array-literal
elements.

Direct native calls now support stack arguments beyond the six register slots,
including recursive calls and hidden aggregate-result pointers. External calls
still reject unsupported signatures. Logical `&&` and `||` now lower to
conditional control flow before optimization, with a synthetic Boolean local
holding the result. Native tests cover skipped calls and traps, required calls,
nested expressions, call arguments, array initializers, and loop conditions.
These changes repair the untrusted GPU bootstrap; they are not backend proofs.

Broader native checks still expose existing aggregate-call crashes, an integer/
Boolean match lowering failure, and instruction-selection assertions. These
failures were reproduced with the corresponding pre-change lowering; they have
not been fixed or removed from the tests.

It does **not** yet extract complete Surface/Core semantics, prove the extractor
algorithm correct for arbitrary supported inputs, or produce code through a
verified Lanius x86 backend. See `PLAN.md` for the full goal.

## Retired workflow

There is currently no supported bootstrap command. The former workflow was
removed because Python generated the Lanius entrypoint, interpreted and
rewrote the emitted artifact, and generated program-specific Lean proofs. A
replacement must keep those responsibilities in checked-in Lanius code or in
general Lean infrastructure before this document gains a new runnable section.

The generated file keeps one artifact definition. Separate theorems check its
tokens, semantic token assignments, parse nodes, and root. The node tactic checks
bounded groups with `Eq.refl` in Lean's kernel and composes them with proved
lemmas. It adds no extraction axioms and uses no native decision procedure.
The final declaration is `extractedValid : ParseArtifactValid extracted`.

On September 5, 2026 the native x86 bootstrap validated the Lanius-produced
artifact for `src/verified/output.lani` (1,366 source bytes, 2,111 parse nodes).
The standalone extractor ran in under 10 ms. With shared checker infrastructure
already built, the full check and `.olean` export took 149.86 seconds with a
peak RSS of 3,165,356 KiB. `#print axioms extractedValid` reported only `propext`,
`Classical.choice`, and `Quot.sound`. This certifies that component's syntax
artifact, not its behavior or the extractor algorithm. The source snapshot,
compiler command, and exact x86 executable hash are recorded in
`target/lanius-extractor-module/bootstrap.json`.

On the same date, a scale-64 bootstrap with a 1,048,576-word parser workspace
compiled the compact embedded-grammar entry to x86-64 and ran that executable
on its own generated entry source. The entry had 1,429 approximate lexical
items and 14,419 bytes; extraction completed in 0.56 seconds with about 3.5 MiB
RSS and emitted one 443,348-byte Lean artifact term. The executable SHA-256 was
`6bcec6ff9402e0465b8e091c783945fb0caac6de09a75a55d7aa531ad6acd729` for
that working-tree snapshot. This is single-entry syntax self-extraction, not a
source-closure embedding or an extractor correctness proof.

Wrapping the term directly produced a 444,833-byte monolithic Lean file. The
default 200,000 heartbeat limit stopped during elaboration after 20 seconds. A
retry with 2,000,000 heartbeats remained CPU-bound without diagnostics for
1,539 seconds and used roughly 7--8 GiB RSS before it was manually stopped.

The retired launcher presented that same logical artifact as balanced `SeqTree`
tables with 64-node leaves. Each leaf is checked independently; checked branch
theorems compose the leaves, and the singular `Artifact` uses the authenticated
tree's flattening rather than comparing a second copy of the node list. On
September 5, 2026 Lean accepted the resulting 851,003-byte self-entry file with
the default heartbeat limit in 120.95 seconds, peaking at 8,726,620 KiB RSS. It
produced a 69,373,512-byte `.olean`; `#print axioms extractedValid` reported only
`propext`, `Classical.choice`, and `Quot.sound`. The generated Lean source and
`.olean` SHA-256 values were respectively
`6d828f70dc830efa7f83a2483d425a75520e2957c3def44d0d27cbb66635b088`
and `45ab5a9bffa590f05a2e7779fa053ebd509a1c2adf1e064d753e38fd52b722e5`.
This completes kernel acceptance of the singular self-entry syntax embedding,
not source-closure extraction or the extractor's general correctness proof.

## Full source-closure result

The x86 extractor now accepts every source path in one invocation, reuses one
initialized grammar and workspace, and emits one logical `ArtifactPack`. The
bootstrap manifest records an ordered 24-file closure with a hash for every
source and an aggregate closure digest. The retired launcher authenticated those hashes and
the exact x86 executable before executing it. The import resolver that produced
the closure list is still untrusted bootstrap metadata; proving closure
completeness inside Lean remains part of extractor correctness.

On September 5, 2026 the current manifest-authenticated x86 executable emitted
and rendered its complete 24-file closure in 7.34 seconds with about 195 MiB
peak RSS. The closure contains approximately 154,037 parse nodes. Its identity
at this checkpoint is:

- executable SHA-256:
  `2d78f631d71e2603e133a697cb1d93e0d5988765bdbba61cf37e2c4acc033f84`;
- source-closure SHA-256:
  `d623578cb914ed975c9fbbc6a54cfaee01c6e103a8f6f48f3d6b34ef85b90ebf`;
- generated pack-assembly module SHA-256:
  `71e111b5727f63a92189a75005e9c83ebfcfd0c3c31bbb86553ed5e53bb64550`.

The generated layout has five substantive modules per source—`Data`, `View`,
`Nodes`, `Metadata`, and `Valid`—plus `Pack`, for 121 Lean files total. Source
bytes are decoded in 256-byte leaves and represented by a balanced authenticated
`SeqTree`. On the largest unit this reduced the source/view phase from 85.92
seconds and 11,688,748 KiB to 3.61 seconds and 1,760,004 KiB. It also made the
previously failing monolithic token check pass in 28.69 seconds at 7,909,916 KiB.

Lean accepted all 24 `ParseArtifactValid` theorems and the aggregate
`extractedPackValid` theorem under a 12,000 MiB per-process ceiling. The cold
work observed in this session was about 23 minutes including the separately
measured largest unit; generated `.olean` files occupy about 1.2 GB. Every final
theorem reports only `propext`, `Classical.choice`, and `Quot.sound`, with no
`sorryAx`. A subsequent freshness-authenticated incremental check completed in
0.12 seconds. That warm result is cache reuse, not the milestone-7 fresh-program
certificate target.

## Historical boundaries and limits

- `bootstrap.py` substitutes fixed grammar data and buffer capacities into the
  Lanius entry template, then invokes the GPU compiler. It does not parse or
  extract the input program. The generated entry belongs to the source that
  must eventually be proved correct.
- `run.py` launches an x86-64 ELF with the input path as argv, captures stdout,
  and changes the emitted term's presentation into independently checked
  balanced declarations before adding Lean proof commands. The native
  runtime and OS provide I/O; the launcher does not emulate services or sandbox
  the executable. The launcher remains untrusted: Lean validates the resulting
  artifact internally, while an exact source-to-artifact binding remains part
  of milestone 3.
  It writes no result on a nonzero extractor return. Discard partial output
  after any failure; an older destination file is not evidence of success.
- `bootstrap.json` records executable and bootstrap-compiler hashes plus the
  exact ordered source-closure claim. Each source is hashed and the ordered
  aggregate is hashed again. This is authenticated provenance, not yet a Lean
  theorem that the resolver found every import.
- Buffer capacities are fixed at build time, while storage is allocated at
  extractor startup. Failure stderr prints argument index, stage, detail, and
  token position on separate lines before the nonzero process exit. Stage
  4/detail 2 means parser workspace exhaustion. Use `--workspace-words` to
  increase that buffer independently.
- The grammar string is decoded through the native read-only `string_data_ptr`
  intrinsic. Focused x86 tests cover that pointer, rodata relocation at a
  function entry, and runtime-length raw slices.
- A monolithic kernel check of `output.lani` exceeded 12 GB. Bounded node
  checking addresses that memory failure, not the eventual seconds-scale
  trusted-extraction target. Do not present this bootstrap check as a proof
  of compiler correctness or as the final fast path.

## Surface extraction in progress

The Lanius Surface modules now extract literals, non-generic paths, unary and
binary operators, assignment, indexing, member access, calls, and array
literals. Calls and arrays share a list traversal; an arena records semantic
nodes in allocation order, and the serializer emits let-bound Lean terms so
children are not serialized repeatedly. Unsupported constructs fail explicitly.
These modules are not yet connected to the reusable entry template above.

The native `lanius_extractor_uses_full_language_grammar` integration test passed
in 25.39 seconds on September 5, 2026. The full-grammar test runs the
GPU-compiled Lanius extractor on nine programs and asks Lean's kernel to check
the actual emitted expressions against `reconstructExpr`, including node IDs,
parse origins, nested calls and arrays, trailing commas, and mixed postfix
chains. This is evidence for those inputs, not a general correctness proof.

This increment also exposed a bootstrap lexer bug: numeric-range repair
inserted `..` tokens from comments containing text such as `165..170`. The
repair now requires the lexical dot state. Focused examples and randomized
CPU/GPU comparisons pass for real ranges and range-like text inside comments
and strings. The compiler is still an untrusted bootstrap compiler.

Types, generic arguments, struct values, statements, declarations, complete
semantic lowering, exact closure completeness, and the general extractor proof
remain ahead. Syntax source-closure self-extraction and pack acceptance are now
established for the recorded 24-file snapshot.
No Lanius x86 backend or end-to-end compiler correctness theorem is established
by these tests.
