# Lanius-native x86 bootstrap extraction

The Rust CPU exporter and Python bootstrap/rendering launchers have been
removed. The supported producer is the checked-in Lanius extractor; the shell
commands below only compile it, supply its recorded source paths, and invoke
Lean.

The production extractor now reserves 16 MiB of logical output (64 MiB of
i32-per-byte storage). This accommodates the expanded backend in one artifact;
the existing 16 MiB packed workspace is unchanged. Fresh backend source/Core
validation passed. The full extractor execution-proof connection and exact
current self-instance now pass too; the saved kernel self-certificate remains
open. See `MILESTONE3.md`. Earlier identity records below are historical.

This workflow targets an untrusted GPU-compiled x86-64 Linux ELF executable.
The Lanius lexer, parser, derivation materializer, and compact serializer run
natively. The executable itself emits the complete Lean module; there is no
renderer or program-specific proof generator. There is no Wasm fallback. Lean
must check the output before it is accepted.

**The native bootstrap, exact source-closure self-extraction, and Lean
acceptance through reconstructed Surface and synthesized x86 Core are working.** Runtime-length slice indexing and
the raw `i32` array view now have executable x86 coverage. Native `[i32; N]`
storage is a coherent packed little-endian view: language indexing and host
reads or writes observe the same four-byte elements. Chunked I/O uses explicit
`usize` host-call lengths. Known narrow scalars now use narrow alias/argument
moves in GPU x86 code generation, preventing stale upper bytes from leaking
out of four-byte spills. Unclassified values retain full width because they
can be aggregate pointers. File reads reuse the existing scratch slice rather
than registering an overlapping raw view per file.
The bootstrap commands below produce an x86-64 ELF extractor and a
Lean-checkable source, syntax, Surface, and x86 Core artifact.
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

The checked Core executable now has an exact execution/output proof on the
documented successful-input domain. Actual-main rejection also covers no
inputs, allocation exhaustion, invalid/missing paths after a loadable prefix
(including an empty prefix), and oversized files after any loadable prefix. The oversized-file
proof includes mandatory close and the actual diagnostic calls before code 6.
An earlier frontend or encoding error may return before a designated bad file.
The unified `CheckedExecution.hostSafe` theorem now gives finite termination,
soundness, and failure safety for every invocation in the explicit deterministic
host domain. It does not assume that files exist, fit, or parse. The active
whole-extractor checker now has zero nonstandard axioms; final concrete kernel
acceptance remains open. None of this proves the bootstrap executable's native
x86 behavior or produces code through a verified Lanius x86 backend. See `MILESTONE3.md` for the
current proof boundary and `PLAN.md` for the full goal.

The final source-to-execution interface is `Entry.checkSource`. It retains the
exact source-checker result, source-derived Core provenance, entrypoint, and
execution theorem in one certificate; the self-check consumes that result
without a second parse or synthesis. The latest [acceptance audit](AUDIT.md)
records the still-open trust boundaries. In particular, running the self-check
in IO is not a standalone kernel-checked proof of the concrete self-instance.

## Current workflow

There are now two bootstrap stages: the GPU compiler builds the Lanius backend,
and that backend produces a whole extractor ELF. Both are untrusted until the
compiler proof is complete. The earlier direct GPU-to-extractor route remains
the independent bootstrap comparison; it is not a second extractor implementation.

### Extractor executable emitted by the Lanius backend

With the existing GPU compiler executable and validated self-pack available,
run from the repository root (each command has a two-minute ceiling):

```sh
timeout --kill-after=1s 119s target/debug/laniusc --emit x86_64 \
  --source-root verified_compiler/src --stdlib-root stdlib \
  -o target/verified-compiler/lanius-backend verified_compiler/tools/backend.lani

mapfile -t self_sources < verified_compiler/source-closure.txt
timeout --kill-after=1s 119s lake -d formal env lean --run \
  formal/Lanius/X86/Tools/Transport.lean \
  target/verified-compiler/SelfCompactRequirements.lean \
  target/verified-compiler/extractor.core "${self_sources[@]}"

timeout --kill-after=1s 119s target/verified-compiler/lanius-backend \
  target/verified-compiler/extractor.core \
  > target/verified-compiler/extractor-lanius-x86
chmod u+x target/verified-compiler/extractor-lanius-x86

timeout --kill-after=1s 119s target/verified-compiler/extractor-lanius-x86 \
  "${self_sources[@]}" > target/verified-compiler/SelfLaniusX86.lean
cmp target/verified-compiler/SelfCompactRequirements.lean \
  target/verified-compiler/SelfLaniusX86.lean
```

The Lean tool authenticates sources and serializes structural Core syntax;
source-to-Core synthesis is still Lean code. Lanius owns machine lowering,
linking, runtime bodies, ELF headers and startup. The backend CLI emits ELF by
default; use `--raw INPUT.core` only for linked-code ABI tests. GNU as/ld appear
in focused test harnesses, not the production emission path.

The resulting extractor currently self-extracts in 2.12 seconds. This measures
execution, **not verification**. See `BACKEND.md` for exact evidence and remaining
runtime/storage/proof obligations. The output needs the same validation as the
earlier bootstrap; no trust shortcut is enabled by these engineering results.

### Direct GPU bootstrap and singular extraction

Build the untrusted x86 bootstrap executable with the existing GPU compiler:

```sh
cargo run -q --bin laniusc -- --emit x86_64 \
  --source-root verified_compiler/src --stdlib-root stdlib \
  -o target/verified-compiler/lanius-extractor \
  verified_compiler/src/extractor.lani
```

Self-extract the exact recorded closure into one compact Lean module:

```sh
xargs target/verified-compiler/lanius-extractor \
  < verified_compiler/source-closure.txt \
  > target/verified-compiler/SelfCompactRequirements.lean
```

Build the fixed decoder/checker once, then validate the embedding:

```sh
lake -d formal build Lanius.Extraction.CoreSynthesis.Program
xargs lake -d formal env lean --run \
  target/verified-compiler/SelfCompactRequirements.lean \
  < verified_compiler/source-closure.txt
```

The extractor and compact serializer are Lanius. The generated file contains
one inert hexadecimal string and a call to fixed Lean infrastructure; it does
not contain generated proof scripts or expanded constructor forests. Its Lean
entry point rereads the same ordered paths and checks that the decoded source
names and bytes equal those files before constructing syntax-validity evidence,
reconstructing Surface from the accepted parse artifacts, checking all
Surface-origin claims, synthesizing Core with retained source-lowering
evidence, and checking the complete x86 Core program's typing derivation.
This is the generic program checker: libraries need no `main`, and programs
may return values outside the extractor's own exit-code set.
`checkExtractorCoreSourcePack` separately links `app::main::main` to a
well-formed executable and checks extractor-specific return codes. The
generated module deliberately does not impose that policy on its inputs.

## Parser and tree resource certificates

The milestone-3 self-check also requires a finite parser envelope for each
source file. `tools/envelope.lani` proposes these by calling the existing
Lanius lexer/parser. It is untrusted bootstrap tooling, not another extractor
or a second parser. Lean independently checks seed, prediction, scanning, and
completion closure against the already authenticated grammar and tokens, then
proves the candidate fits the source call's workspace capacity. It also
calculates and independently checks resource budgets on those chart items,
covering the node count, record words, and depth of every recognized tree.
This does not add another parser or change the envelope payload.

Prepare the grammar, compile the proposer to x86, and generate the ordered
candidates. Each pipeline operation is bounded to two minutes:

```sh
LAKE="$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake"
timeout --kill-after=1s 119s "$LAKE" -d formal env lean --run \
  formal/Lanius/Extraction/Tests/Parser/Prepare.lean \
  target/verified-compiler/envelope-grammar.bin
timeout --kill-after=1s 119s cargo run -q --bin laniusc -- --emit x86_64 \
  --source-root verified_compiler/src --stdlib-root stdlib \
  -o target/verified-compiler/envelope verified_compiler/tools/envelope.lani
timeout --kill-after=1s 119s xargs target/verified-compiler/envelope \
  target/verified-compiler/envelope-grammar.bin \
  < verified_compiler/source-closure.txt > target/verified-compiler/self-envelopes.bin
```

Check the singular embedding and resource candidates together from the repository
root. Lake builds the required proof modules, source validator and general
resource checker, loads their native libraries in dependency order, and runs
the built self driver against `source-closure.txt`. It reads and validates the
input anew; only unchanged driver code and shared infrastructure are reused:

```sh
timeout --kill-after=1s 119s "$LAKE" -d formal run check-self \
  target/verified-compiler/SelfCompactRequirements.lean \
  target/verified-compiler/self-envelopes.bin
```

The September 12 measurement, with shared proof/native imports built, was 44.36 seconds;
the same driver under the interpreter took 87.91 seconds. Parser/tree resources
take 1.18 seconds versus 37.78 seconds. The first native helper build took
19.85 seconds separately. These are executable-validation timings, not kernel
self-certificate timings. The September 17 indexed-checker/shared-runner changes
are verified on the backend closure, but the extractor-wide attempt hit the
119-second limit while rebuilding frontend dependencies before validation.
There is no updated self-check timing yet. No `native_decide` or trust assumption was added.
See `self-source-lake-native.log` and `parser-resource-native-build.log` in
`target/verified-compiler`.

The internal self-check takes both artifact paths. The current saved embedding
is `SelfCompactRequirements.lean` (identical to `SelfLaniusX86.lean`, SHA-256
`bc11dd2187755d63eb1ad4f8de4ac547c4e753f44c5142fc15f64113e62a675e`).
The older `SelfCompactExtracted.lean` is a different source instance; its saved
88.78-second integration result does not accept the current 16 MiB instance.
Regenerate or revalidate envelope candidates when the source closure changes;
an old candidate may still pass if its authenticated token/grammar structure
is unchanged. The current instance passes executable validation; its saved kernel
certificate remains pending.

This driver constructs `Entry.CheckedSource` inside IO. It does not persist a
closed kernel declaration of that type. Compiling the generated IO program to
an `.olean` alone would not prove that its concrete check succeeded. Milestone 3
still needs a saved certificate for the exact encoded artifact and independent
ordered source bytes, retaining the successful source-to-Core construction
equation. The combined checker's inherited nonstandard axioms are now gone. Concrete successful
self-extraction also needs its loading and success-domain evidence.

### Fresh encoding/source-binding kernel certificate

With the shared imports built, run this from the repository root:

```sh
timeout --kill-after=1s 119s "$LAKE" -d formal env lean \
  verified_compiler/proofs/Encoding.lean \
  -o target/verified-compiler/SelfEncoding.olean
```

This always reads the current emitted module and ordered source closure; do
not substitute a cached Lake target when the external inputs change. The saved
`.olean` contains the frozen structured data and the closed `encodable`,
`decoded`, and `source_bound` theorems. It does not merely run an IO checker.
The complete fresh invocation passed in 58.52 seconds, down from 75.51,
including output, with 6,814,944 KB peak RSS. Typed scalar fields reuse generic
bounds proofs; collection sizes/counts remain checked. Bounds/decoder checking
took 21.13 seconds and source binding/final audit took 4.80 seconds.
Phase diagnostics are in `target/verified-compiler/self-encoding-phases.log`.

This is a partial certificate: it proves compact encodability, the public
decoder round trip, and exact ordered source binding. It uses quoted structured
data as the embedding, not a kernel equality to the bootstrap's transport
literal. Surface/Core checking and the concrete execution/resource certificate
remain open. The strict audit allows only standard Lean axioms. Loading and
auditing the saved result is measured separately in `AUDIT.md`; that is not a
fresh-check timing. The matching focused regression target is
`Lanius.Extraction.Tests.Compact.Bounded`.

### Representative Surface kernel certificate

With `SelfEncoding.olean` saved, run from the repository root. The runner
builds the shared certificate dependencies and the existing native compact
reader before invoking the kernel-checked recipe. The certificate process uses
four Lean workers and a 7,000 MB Lean memory limit; these are resource bounds,
not a promise of parallel kernel checking or a performance improvement:

```sh
timeout --kill-after=1s 119s \
  "$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake" -d formal run certify \
  verified_compiler/proofs/Surface.lean target/verified-compiler/SelfSurface.olean
```

This checks units 17, 14, and 2 (`host`, `token_scan`, and `byte_io`) against
the frozen source-bound embedding and saves the original checker's acceptance.
Native code only proposes data. Kernel equations authenticate each proposal,
and the strict audit rejects nonstandard axioms. With shared imports and the
native reader built, the September 17 complete invocation/output took 53.66
seconds and 3,954,216 KB peak RSS; the preceding fresh measurement was 47.79
seconds. The executable validation speedups do not establish a kernel speedup.
It uses authenticated grammar/root indexes, checked path witnesses, and a
single-pass context plan, retaining the original checker's exact result.
Phase diagnostics are in `self-surface-phases.log`; the whole-command log is
`scanner-spelling-kernel-fresh.log`. The recipe separates cache/token checks,
linking/reconstruction, spelling coverage, origin validation, final proof
assembly, and the strict audit. It stops when a retained phase declaration
fails its axiom audit. See the current `PLAN.md` analysis.
Native reader preparation took 0.89 seconds separately with other dependencies
built. These are not cold whole-infrastructure timings.

Reload and audit the frozen certificate with:

```sh
timeout --kill-after=1s 119s \
  "$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake" -d formal run certify \
  verified_compiler/proofs/LoadSurface.lean target/verified-compiler/LoadSurface.olean
```

That invocation took 1.62 seconds, including dependency freshness checks and
output. It is reuse, not a fresh verification of current source files.

These are three representative units, not whole-pack Surface acceptance. Rebuild
the encoding certificate for changed external inputs; an old `.olean` proves
facts about its frozen data, not the current filesystem. A changed or malformed
proposal cannot bypass the exact equations.

To profile overlapping kernel computations on the frozen byte-I/O fixture:

```sh
timeout --kill-after=1s 59s \
  "$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake" -d formal run certify \
  verified_compiler/proofs/ProfileSurface.lean target/verified-compiler/ProfileSurface.olean
```

This rechecks the diagnostic equalities, but reuses the saved input and caches.
Do not add its phase times or present them as fresh whole-program verification.
The September 13 investigation and rejected alternatives are recorded in `PLAN.md`.

### Full Core typing kernel certificate

Run from the repository root after self-extraction. `certify` builds the shared
proof and native proposal dependencies before invoking the recipe:

```sh
timeout --kill-after=2s 115s \
  "$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake" -d formal run certify \
  verified_compiler/proofs/Core.lean target/verified-compiler/SelfCore.olean
```

This freezes the complete proposed Core program and proves `wellTyped`,
`target`, and `function_count` with only standard Lean axioms. All 125 functions
are checked, not just the reachable executable closure. A fresh invocation with
shared dependencies built takes 15.08 seconds, including proposals, quotation,
proof checks, audit, and output. Typing/audit is 4.52 seconds of that; phase
diagnostics are in `target/verified-compiler/self-core-phases.log`.

The native proposal checks the source bytes and synthesizes Core, but this
certificate **does not prove source correspondence**, extractor behavior, or
x86 preservation. It cannot replace `Entry.CheckedSource`. That source-bound
certificate must eventually connect this same frozen Core to the authenticated
Surface pack. Typing alone also does not prove runtime memory safety or that
external services behave correctly.

Reload and audit the frozen typing/target certificate with:

```sh
timeout --kill-after=2s 115s \
  "$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake" -d formal run certify \
  verified_compiler/proofs/LoadCore.lean target/verified-compiler/LoadCore.olean
```

This takes 1.19 seconds and is reuse, not fresh verification of current files.
For checker regressions, build `Lanius.Extraction.Tests.Typing`,
`Lanius.Extraction.Tests.Reification`, `Lanius.Extraction.Tests.Lowering`, and
`Lanius.Extraction.CoreSynthesisTests`. Core quotation is shared in
`Lanius.Core.Quote`; the temporary probe is not retained as another recipe.

### Complete Surface-to-Core lowering certificate

With the same `SelfCore.olean` available, run one complete fresh lowering check:

```sh
timeout --kill-after=2s 115s \
  "$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake" -d formal run certify \
  verified_compiler/proofs/Lowering.lean target/verified-compiler/SelfLowering.olean
```

This proposes and quotes all 18 Surface units, authenticates preparation and
each module's lowering, and composes the original whole-program checker
equation for the existing 125-function Core. Constants, layouts, function order,
target, and external policy are included. No saved lowering subproofs are used.
The complete invocation takes 84.77 seconds and 3,397,912 KB peak RSS, with
shared dependencies and the Core candidate available. Shared support refresh
took 38.02 seconds separately. Phases and output are recorded in
`self-lowering-phases.log` and `self-lowering-fresh-final.log`.

Reload and audit the lowering, typing, and target certificates with:

```sh
timeout --kill-after=2s 115s \
  "$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake" -d formal run certify \
  verified_compiler/proofs/LoadLowering.lean target/verified-compiler/LoadLowering.olean
```

That takes 1.54 seconds and is reuse, not a fresh check. These certificates
still do not authenticate all Surface inputs against their source bytes:
source-to-Surface acceptance is three of 18 units. They do not establish the
closed extractor instance or general compiler/x86 semantic preservation.
Rebuild candidates and certificates when inputs change; see `AUDIT.md` for
artifact identities and `PLAN.md` for the remaining work and performance gap.

### Historical resource evidence

Historically, all 18 files of the earlier instance passed the source-bound
parser and tree resource checks. Parser and tree resource obligations are
closed on the checked domain, and
the source-linked frontend succeeds on the checked input domains. Semantic
collection already derives its capacity bound after frontend success. The
source-only full-module output bound was checked as well: 7,967,185 bytes
against that instance's 8,388,608-byte allocation. The current allocation is
16,777,216 bytes and requires its own refreshed acceptance. The bound covers every recognized tree
and uses retained raw-token evidence without another lexer or parser pass.
The public `CheckedExecution.run_complete` theorem now proves successful
termination and exact certified output on the source-only syntax/resource
domain and explicit loading conditions. The self-source driver checks these
conditions for the actual 18-file process world and instantiates the theorem.
The actual checked main also rejects no-input invocations with code 1, without
allocation or file access. Its public rejection proof and six actual-source
cases cover pre-existing output, files, handles, and invalid handle counters.
All 13 allocations now guard the raw pointer before constructing a slice.
The public allocation-failure theorem covers every position and proves normal
code-3 rejection with preserved external inputs, handles, and output. Four
actual-main finite-budget cases and 25 small sequence budgets exercise this
behavior. The scoped-pointer source and all source-linked proofs are checked;
the old post-allocation guard and unsafe checker form have been removed.
The actual-main oversized-first-file proof now covers read termination,
mandatory close, both diagnostic calls, and code-6 rejection with unchanged
stdout. Five external-domain worlds instantiate it in the self check; nine
domain mutations and four diagnostic-source mutations are rejected.
Oversized files after a nonempty prefix are now covered by the same file-loop
proof. An exhaustive host-input partition connects all covered loading and
rejection branches to one public safety/termination theorem. Its assumptions
are numeric host bounds, handle freshness, an initially empty unlimited-budget
heap, and deterministic host I/O. Finite allocation exhaustion has a separate
proof; real OS I/O errors and short writes are not modeled here.
Final acceptance, inherited trust obligations, and the
verified x86 backend remain open. The latest combined check took 69.02 seconds
with shared dependencies built, including 38.191 seconds for parser/tree
resources, 441 microseconds for output bounds, and 16.309 milliseconds to bind
the successful-input domain to the exact process inputs. This is one-time
validation, not the eventual trusted fast path. Broad dependency rebuilds have
hit the 119-second cutoff; the incremental timing does not establish a fast
cold rebuild.

## Earlier bootstrap checkpoints

The Lanius process constructs the prefix, complete compact pack, and suffix in
one output buffer, packs it into the no-longer-needed parser workspace, and
calls the modeled host stdout service only after every unit has been extracted
and encoded. Thus all earlier deliberate failures leave stdout untouched, and
a zero return follows one final write of the complete module.

The September 6, 2026 checkpoint has these reproducible measurements and
identities:

- exact 18-file, 2,332-line, 105,171-byte closure extraction: 1.26
  seconds, about 39 MiB peak RSS;
- proof-producing Lean exact-source, syntax, reconstructed-Surface,
  source-to-Core lowering and whole-program x86 Core typing with shared
  infrastructure built: 18.97 seconds,
  about 1.65 GiB
  peak RSS;
- x86 extractor SHA-256:
  `9608971d94f2cfc2d1622785f0546628c527db5c834e16c9a9ddc63e34977c55`;
- compact self-embedding SHA-256:
  `ef7858063a60a986a437b999e2da435d70c69baa806929db32591f9261272049`;
- SHA-256 of the ordered `sha256sum` closure manifest:
  `7dc2dcd4b191e1c19e74ce311b95715668a52595b08bd95b3d6cb69a224c6119`;
- SHA-256 of `source-closure.txt` itself:
  `079059b1eb54011de70900c1c5a9f7d411a027c7166728a95b55aef461a77bf3`.

After explicit padding fixed out-of-bounds word reads in short keyword
literals, the x86 bootstrap build took 11.92 s. The updated self-source check,
including exact I/O-loop linkage and execution tests of the compact matcher
and keyword dispatcher, took 19.29 s (about 1.70 GiB peak RSS). The earlier
18.97 s measurement above is the typed acceptance check before that change.

The formal target now distinguishes `Success` and classified `Failure`, and
states `RunSound`, `RunFailureSafe`, and `RunComplete` over an actual
`Lanius.Semantics.Outcome`. Exit code zero must imply exact module output,
exact ordered source binding and proof-carrying syntax,
unchanged source files, no leaked file handle, and a structurally safe heap and
raw-view set.
Nonzero output remains untrusted and must be discarded. The current Lanius
implementation has not yet been proved to satisfy that execution contract.

`AcceptedSuccess` is separate: it adds Surface reconstruction, source-to-Core
lowering, and x86 Core typing only after the emitted checker accepts. This
distinction matters for syntactically valid, ill-typed input such as
`fn main() -> i32 { return true; }`. The extractor currently emits its syntax
successfully, while the typed-Core checker correctly rejects it.

`writeStdout_exact` proves that the modeled stdout service appends exactly the
loaded bytes, records one call, and preserves the heap and all other world
fields. `writeStdout_invalidRange` proves that a failed load traps without
changing output or memory. `OutputPacking` proves signed-i32 byte round trips,
Core shift/OR packing arithmetic, and exact prefixes despite padding and an
unused workspace tail. Heap read-after-write and disjoint-view synchronization
proofs connect that representation to the host buffer. Finally,
`packed_stdout_call_sound` proves exact output for an observed successful Core
host call, deriving synchronization success from the execution itself.
`executes_clear_loop` proves that clearing terminates, zeroes exactly the
required words, and preserves the remaining workspace. `executes_packing_loop`
proves the complete Core packing loop terminates and
establishes the exact packed cell, preserving its input buffer and all cells
outside the workspace/cursor footprint. `findPackingLoop?` returns evidence
that this exact loop occurs in the checked `main`; it rejects mismatched
cursor updates and extra loop effects. `findClearLoop?` shares the same source
traversal and locates the clearing loop. `stdout_after_packing` derives the
packed buffer and its encoding from the observed loop execution. Valid blocks
at distinct addresses are proved non-overlapping; pointer exposure preserves
address uniqueness, and raw-slice construction requires a fresh address. The
enclosing source execution still must establish initial ownership, fresh raw
registrations, and phase ordering. Earlier extraction stages must establish
syntax validity.
The model writes all bytes; a short native OS write still
returns failure, and callers must discard that partial output.

On input, `read_call_words` derives the refreshed scratch words and exact file
bytes through both heap synchronization passes. `executes_unpacking_loop`
proves termination and exact copying into the source buffer, preserving earlier
chunks, unused capacity, and scratch contents. `unpack_after_read` composes
the host call and loop; it does not assume a correctly encoded scratch buffer.
Its entry ownership and capacity facts must still be established by the
enclosing file-reader execution. These are stage proofs, not the missing
whole-extractor success/failure theorem.
`read_preserves_view` proves that a disjoint registered buffer of valid i32
values survives the read unchanged, deriving its encoding/refresh coherence.
Fresh raw slices have distinct backing cells; repeated pointer exposure reuses
the registry. The request-adjustment branch is proved to compute a positive,
scratch-bounded capacity probe. Outer-loop and caller-side composition remain.

Focused regression fixtures `tests/extract_library.lani` and
`tests/extract_return_code.lani` both pass extraction and the generated checker.
They guard against applying extractor-specific entrypoint policy to arbitrary
programs. `tests/extract_type_error.lani` additionally requires syntax acceptance
and Core rejection. `formal/Lanius/Extraction/Tests/Emission.lean` checks both
stages and rejects modified source bytes; the three-fixture run took 4.43 seconds.

`formal/Lanius/Extraction/Tests/Self.lean` checks the self-embedding and its
ordered count/clear/pack, input-unpacking, and capacity-probe source linkage in
one pass (19.70 seconds with shared infrastructure built). `Tests/Packing.lean` and
`Tests/Input.lean` exercise rejected loop mutations and actual Core executions.
The input tests cover all byte values at every lane, empty input, partial words,
and preservation of surrounding buffer contents. The focused input/output
proof and regression build took 6.42 seconds; the later incremental build with
preservation and capacity-probe checks took 2.35 seconds. The Core host-call
regression also checks a partial read followed by EOF with another registered
buffer containing signed i32 extremes.
`Tests/Assurance.lean` reports the proof dependencies: only Lean's
standard axioms, with no project-specific axiom or `sorryAx`.

The extractor imports `src/verified/host.lani`, a narrow Lanius declaration
module, rather than the large allocator/filesystem/I/O/process standard-library
surfaces. No general standard-library source is in the exact closure.
The native x86 runtime returns byte count `1` for successful `write_byte` and
`write_newline`; the formal world now models the same result instead of zero.

## Retired workflow

The former workflow was removed because Python generated the Lanius entrypoint,
interpreted and rewrote the emitted artifact, and generated program-specific
Lean proofs. The current workflow keeps production in checked-in Lanius and
decoding/checking in general Lean infrastructure.

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

- The retired Python bootstrap and launcher are not part of the repository or
  current workflow. `src/extractor.lani` emits the complete Lean module itself;
  ordinary shell invocation only redirects its stdout. Discard partial output
  after any nonzero return; an older destination file is not evidence of
  success.
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
