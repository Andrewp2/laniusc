# Surface proof profile — September 4, 2026

The largest assembly cost is avoidable kernel reduction in the final wrapper
theorem. It is not slow tactic search, import overhead, or the item-by-item
composition itself. A diagnostic rewrite of that wrapper reduced a complete
CanonicalTokens assembly module from 26–29 seconds to 1.57 seconds.

These are direct Lean module checks with dependencies already built, not
end-to-end frontend rebuild times. Runs were sequential, with `Elab.async=false`,
on the current workstation using Lean 4.33.1 and warm filesystem caches. No
production proof or checker implementation was changed during this profile.

## Measured costs

| CanonicalTokens module | Wall time | Kernel checking | Imports | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Reconstruction assembly | 28.95 s | 27.8 s | 0.743 s | 6.95 GiB |
| Reconstruction item 3 | 19.52 s | 18.6 s | 0.702 s | 5.71 GiB |
| Origin nodes | 12.21 s | 11.4 s | 0.675 s | 4.31 GiB |
| Parse nodes, chunk 0 (1,000 nodes) | 3.74 s | 3.02 s | 0.559 s | 2.16 GiB |

The item run included CPU sampling. These rows are separate measurements;
they are not a breakdown of a single complete build. Shared dependency import
costs recur between rows. Profiler category times are exclusive; nested trace
times must not be added to them.

The assembly run spent only 0.149 s executing tactics. A named trace localized
the slow final declaration to
`verifiedFrontendCanonicalTokens_reconstructed_trace_kernel`, in
`Lanius/Extraction/VerifiedFrontend/Surface/CanonicalTokens/Reconstruction.lean`.
In that repeat, checking the final theorem took 23.72 s, while constructing its
proof took 0.82 s, mostly a kernel check of the parse-node count. The whole
module took 25.82 s. Other repeats took 28.33 and 28.95 s.

## Controlled experiments

### Compose the final wrapper symbolically

The existing wrapper unfolds the concrete reconstruction entry point, rewrites
the root and fuel, then uses `simp` with the already-proved file result. Its
generated proof is small, but kernel definitional equality is expensive.

Instead, a scratch copy first proved this lemma over symbolic inputs:

```lean
theorem profileSurfaceFromFile [ArtifactAccess] (artifact : Artifact)
    (root fuel finish : Nat) (surface : SurfaceFile)
    (rootFound : artifact.parse_root = some root)
    (fuelFound : artifact.parse_nodes.length + 1 = fuel)
    (fileFound : (reconstructFile fuel artifact root).run 0 =
      some (surface, finish)) :
    reconstructArtifactSurfaceWithAccess artifact = some surface := by
  unfold reconstructArtifactSurfaceWithAccess
  simp [rootFound, fuelFound, fileFound]
```

The concrete wrapper applies that lemma to its existing root, fuel, and file
proofs. Nothing changes about the theorem statement, artifact, reconstructed
output, or item proofs. Complete copied assembly modules produced:

| Unit | Wall time | Kernel checking | Peak RSS |
| --- | ---: | ---: | ---: |
| CanonicalTokens | 1.57 s | 0.555 s | 1.72 GiB |
| Lexer | 2.05 s | 0.385 s | 1.61 GiB |
| Symbol | 1.35 s | 0.275 s | 1.62 GiB |

All three copied modules passed. Their final theorem axiom audits report only
`propext`, `Classical.choice`, and `Quot.sound`. The copies import the original
item proofs, but not their own original assembly modules. This avoids mistaking
reuse of the original final theorem for a faster proof of it.

This isolates the avoidable cost to the concrete wrapper's proof shape. The
likely mechanism is eager reduction during kernel conversion of the rewritten
monadic expression. The profile does not count which reconstruction functions
are reevaluated inside that conversion.

### Reduce reconstruction fuel

The item-3 equality also passed with fuel 128 instead of 10,308, preserving the
same output and final state. Kernel time was 18.4 s instead of 18.6 s; wall time
was 19.30 s instead of 19.52 s. This is not a meaningful improvement. Excess fuel
is not the explanation for that item's cost.

### Sample the large item proof

At 99 Hz, `perf` attributed 18.13% of sampled cycles to `lean_dec_ref_cold` and
8.02% to `mi_free`. Expression substitution (`replace_rec_fn::apply`) accounted
for 7.68%, with substantial additional hash-table/cache work. These are sampled
native implementation costs, not exact per-Lanius-function timings. Linux
kernel symbols were restricted, but Lean userspace symbols were available.

This supports expression-management overhead as a major cost. It does not yet
separate artifact lookup, source-text decoding, recursive reconstruction, and
output comparison within the item proof. The same limitation applies to the
11.4-second origins check; it needs its own controlled sub-check profile.

## Reproduction

From `formal/`, for each selected module:

```sh
/usr/bin/time -f 'WALL %e USER %U SYS %S RSS_KB %M' \
  lake env lean -Dprofiler=true -Dprofiler.threshold=50 \
  -DElab.async=false \
  Lanius/Extraction/VerifiedFrontend/Surface/CanonicalTokens/Reconstruction.lean
```

For declaration-level timing, replace the profiler flags with
`-Dtrace.profiler=true -Dtrace.profiler.threshold=100`. For Firefox-compatible
trace output, also pass `-Dtrace.profiler.output=/tmp/assembly.json`; add
`-Dtrace.profiler.output.pp=true` to retain formatted declaration details.

For CPU samples:

```sh
perf record -q -F 99 --call-graph dwarf,16384 -o /tmp/item.perf -- \
  lake env lean -DElab.async=false \
  Lanius/Extraction/VerifiedFrontend/Surface/CanonicalTokens/Reconstruction/Item3.lean
perf report --stdio --no-children -i /tmp/item.perf
```

Diagnostic copies and raw logs from this run are in `/tmp/LaniusProfile*.lean`
and `/tmp/lanius-*.log`; these temporary files are not required by the build.

## Complete program-specific baseline and implemented follow-up

A subsequent fresh sequential check took **985.67 s (16 min 26 s)**. Reusable
Lean/checker infrastructure was prebuilt; no `VerifiedFrontend` outputs were
reused. All 349 program-specific modules passed. Artifact/data/cache modules
took 238.48 s, pack assembly 1.60 s, and Surface modules 745.53 s. These times
include process startup, imports, checking, and writing Lean object files,
but not compiling native executables.

Run `python3 formal/benchmark-surface.py` from the repository root to repeat
that measurement. It uses an isolated output directory, leaves the normal
Lake cache unchanged, and emits per-module and total timings as JSON lines.
`--list` prints the exact program-specific module set without compiling.

The symbolic-wrapper experiment has now been applied to all four affected
production modules through `reconstructArtifactSurfaceWithAccess_of_file` in
`SurfaceReconstructTrace.lean`. Production builds passed at 1.5 s for Lexer,
1.6 s for CanonicalTokens, 1.3 s for Symbol, and 1.2 s for RawLexer, versus
20.23, 25.68, 20.37, and 15.64 s in the fresh baseline. The combined Surface
certificate also passed. This removes roughly 76 s of measured assembly work;
the full end-to-end total has not yet been rerun after that change.

The next profile separated artifact quotation from executable-code generation.
The Lexer artifact module took 22.96 s: compiler passes consumed about 16 s,
quotation interpretation 3.12 s, and kernel checking only 0.089 s. With
`compiler.extract_closed=false`, the same module took 12.66 s (11.06 s in a
second run that wrote its object file). Symbol's artifact took 8.19 s versus
19.64 s in the fresh baseline; Lexer's cache took 5.15 s versus 11.25 s.

That option is now scoped to the 15 monolithic artifact/cache quotation modules.
It disables an optional executable-code optimization, not kernel checking,
code generation itself, or data caching in the benchmark. Focused executable
checks of the Lexer artifact passed before and after, at 1.06 and 0.82 s.
No quotation cache was added: the profile showed that JSON decoding was not
the main cost in these modules.

## Next steps supported by the evidence

1. Keep final-wrapper composition symbolic; this is now implemented and checked
   across all four affected units.
2. Profile the large item reduction and origin-path validation separately,
   isolating lookup, text handling, recursion, and output checking before
   choosing a new algorithm.
3. Use the complete fresh-check benchmark when assessing further changes.
   Faster individual modules do not establish a three-second end-to-end result.

## Single-process measurement

`python3 formal/benchmark-surface.py --batch` checks the same fresh frontend
module set in one Lean process. It loads shared import data once, then uses
Lean's module loader to construct a separate environment for each source file.
Program object files are written to a fresh temporary directory and can be
imported only after their source has passed in the current run. The normal Lake
cache is not changed. Temporary batch objects are removed when the run exits.

The runner reports import, elaboration/checking, export, and import-cache times
for each module. The checking category includes quotation and Lean code
generation, not just kernel reduction. Total process wall time also includes
loading and compiling the runner itself. Native executable linking is excluded.
The 12,000 MB Lean memory limit is not an operating-system RSS cap.

An earlier pilot shared the whole elaboration environment between files. That
approach failed on repeated private names and is not used by this runner. The
focused tests in `test-batch-check.py` exercise private file boundaries, fresh
diamond dependencies, visibility of unimported declarations, and rejection of
false proofs, admitted final proofs, unprocessed source, missing final theorems,
duplicate modules, and prebuilt frontend imports. The final theorem's axiom
audit permits only `propext`, `Classical.choice`, and `Quot.sound`.

### Complete result, September 4, 2026

The fresh batch check passed all **349 modules in 721.31 s (12 min 1 s)**,
including the final axiom audit. Shared infrastructure was already built; no
frontend object files were reused from an earlier run. Peak RSS was
10,251,824 KiB (9.78 GiB). The final theorem used only the three permitted axioms.

This is **26.8% faster** than the 985.67-second baseline. That comparison includes
the wrapper and quotation-code-generation improvements as well as batching; it
does not measure batching alone. The separate-process benchmark has not been
rerun on the same revised sources.

| Work | Seconds |
| --- | ---: |
| Elaboration/checking, including quotation and code generation | 614.63 |
| Per-module import-environment construction | 88.97 |
| Object export | 13.53 |
| Fresh-object import-cache updates | 0.05 |
| Runner startup, initial shared imports, final audit, and other overhead | 4.13 |
| Total command wall time | 721.31 |

Grouping the 614.63 seconds of elaboration/checking by module responsibility:
parse nodes/metadata/composition took 155.43 s, reconstruction 122.26 s,
artifact/cache data 111.46 s, token validation 101.20 s, origins 77.60 s,
view authentication 32.83 s, and claims/assembly/decoding/pack 13.86 s.
These are module-group timings, not samples of individual checker functions.

The largest individual checking times were Symbol reconstruction item 6
(21.11 s), CanonicalTokens reconstruction item 3 (19.87 s), CanonicalTokens
origin nodes (12.24 s), and RawLexer reconstruction item 16 (10.64 s).
Removing all measured per-module import overhead would still leave more than
ten minutes. The next substantial improvement therefore needs to reduce proof
evaluation or generated-data work, not only module-loading overhead.

Raw measurements from this run are in `/tmp/lanius-batch-full-timing.jsonl`.
This is one warm-filesystem measurement, not a claim about cold disk caches or
run-to-run variance. The seconds-scale target remains unmet.

## Postorder node validation

`ParsePostorder.lean` replaces repeated global node-index lookups with a stack
of completed nodes. It validates children in forward grammar order. The
shared `check_all_sound` theorem proves that acceptance implies the existing
`checkNodesFromParseView` predicate on the original artifact. The proof carries
node identity through the stack and the remaining input list; the concrete
check does not build or authenticate another sidecar.

All nine frontend units now use this checker. Their 43 node-check chunk files
and chunk-composition proofs are removed. The fresh frontend graph therefore
contains 306 modules instead of 349. The old general checker remains the
specification and still supports non-postorder DAG layouts.

The initial CanonicalTokens experiment checked all 10,311 nodes in 14.8 s of
kernel time (16.01 s command wall time), and derived the original predicate
using only `propext` and `Quot.sound`. Separate-process checks of the nine
production node modules all passed in 69.40 s combined. These focused times
are not the full frontend time and use a different runner from the preceding
batch measurement.

### Full postorder result

The fresh batch run passed all **306 modules in 661.45 s (11 min 1 s)**,
including the final theorem and axiom audit. Peak RSS was 10,193,868 KiB
(9.72 GiB). Only `propext`, `Classical.choice`, and `Quot.sound` appeared in
the final theorem's axiom dependencies.

This run is **8.3% faster** than the preceding 721.31-second batch run and
**32.9% faster** than the original 985.67-second baseline. All frontend data
and proofs were fresh; shared infrastructure, including the generic postorder
soundness proof, was already built.

| Work | Seconds |
| --- | ---: |
| Elaboration/checking | 562.33 |
| Per-module imports | 80.43 |
| Object export | 14.49 |
| Fresh-object import-cache updates | 0.04 |
| Startup, initial imports, audit, and other overhead | 4.15 |
| Total command wall time | 661.45 |

The old 52 node-validation modules took 155.42 s combined. The nine replacements
took 76.81 s in the same batch benchmark mode, a 50.6% reduction. Other modules
took 18.72 s longer in this run; that difference has not been attributed, so
the full improvement is 59.86 s, not the 78.60-second node-phase saving.

Reconstruction now accounts for 127.33 s of elaboration/checking, artifact/cache
data for 115.81 s, token validation for 100.93 s, parse validation and metadata
for 87.89 s, origins for 83.10 s, and view authentication for 33.33 s. These
remain module-group measurements rather than isolated function costs.

The next profiling target is reconstruction, now the largest group. The full
seconds-scale goal remains unmet. Raw results are in
`/tmp/lanius-postorder-full-timing.jsonl`.

## Reconstruction: forcing, recursion, and primitive reads

The next controlled experiments used Symbol item 6, starting at Surface ID 67
and ending at ID 999. All final-value experiments proved equality to the same
proposed Surface item through the kernel. Production reconstruction was not
changed by these experiments; **661.45 s remains the latest full-check time**.

### Output forcing is not the main cost

With the same reconstruction and access view, proving only that reconstruction
succeeds took 19.67 s of kernel time. Proving the final counter took 20.66 s;
proving the complete output equality took 22.31 s. These are separate checks,
not stages of one execution. Avoiding the full tree comparison therefore does
not remove most of the cost.

### Structural recursion gives a modest gain

Lean compiled several mutually recursive reconstruction groups using
well-founded recursion. An isolated copy with explicit structural recursion
on fuel compiled with unchanged function bodies and proved the expected item
in 18.5 s. A matching copy without those annotations took 20.2 s. This small
experiment does not establish an end-to-end gain or justify a second permanent
implementation. The pilot and control remain outside the repository.

### Distinct node reads are a stronger lead

An instrumented native execution recorded 16,500 node reads for 7,956 distinct
node IDs, plus 380 token reads and 380 byte-range reads. These are native
execution counts, not counts of kernel reduction steps.

Replaying the node requests in a closed kernel check took 11.7 s. Replaying
only the distinct IDs took 11.4 s. Traversing the full request list with a
constant-true predicate took 0.336 s. Duplicated requests added little cost in
this workload; the experiment is consistent with effective reuse of repeated
reductions, but does not identify the kernel mechanism responsible.

An isolated rewrite that read each current node once into a local variable
and used direct helpers for its production, children, and name took 20.2 s,
the same as its matching control. It was not applied to production.

The replay times are not an additive decomposition of reconstruction: its
calling context and forcing differ. They nevertheless identify distinct
global node lookups as a better next target than output comparison or local
read hoisting. The next experiment should test direct child references while
including the cost of constructing and authenticating them. A faster executor
alone would not establish a faster fresh check, and duplicating the artifact
or keeping two reconstruction implementations could erase the benefit.

Raw diagnostics are `/tmp/lanius-reconstruction-forcing.log`,
`/tmp/lanius-reconstruction-reads.log`,
`/tmp/lanius-reconstruction-lookups.log`,
`/tmp/lanius-reconstruction-unique-lookups.log`,
`/tmp/lanius-structural-reconstruction.log`,
`/tmp/lanius-reconstruction-control.log`, and
`/tmp/lanius-reconstruction-hoisted.log`.

## Checked direct-reference prototype

A smaller-leaf experiment first compared 64-element and 8-element parse-node
cache layouts on Symbol. Quotation, tree authentication, and item reconstruction
together took 26.44 s and 24.29 s respectively. Reconstruction improved from
19.58 s to 16.37 s, but authentication became slower. The production cache
layout was not changed.

Direct child references gave a larger improvement. A raw-link pilot constructed
the required tree prefix from the original postorder list and reconstructed
Symbol item 6 in one closed kernel equality check: 11.0 s, versus 20.2 s for
the earlier matching indexed control. No linked-tree quotation or prebuilt
program-specific link cache was used.

`ParseTree.lean` now supplies a shared, kernel-checked link builder. Its
`link_sound` theorem ties every node to its original list index and every
nonterminal child slot to a valid child with the original ID. Token slots retain
their position and token IDs. `Checked` references carry this evidence;
`Checked.child?` preserves it, and `Checked.childId` relates the result to the
original node's child slot. The builder's axiom audit reports only `propext`
and `Quot.sound`; the audited child-access lemmas use only `propext`.

Eleven focused kernel tests in `ParseTreeTests.lean` passed. They cover child
identity, token-slot and out-of-range behavior, empty and independent forests,
and rejection of future, missing, duplicate, and reordered child references.
Run them with `lake build Lanius.Extraction.ParseTreeTests` from `formal/`.

A second pilot used this checked-reference library to construct all 8,244
Symbol nodes and reconstruct the entire file. It proved the same proposed
`SurfaceFile` and final counter in **12.9 s of kernel time**, versus **21.9 s**
for the existing indexed whole-file reconstruction. Command wall times were
15.32 s and 22.91 s; the linked command also compiled its temporary interpreter
copy. Both final equalities used only the three permitted standard axioms.

This is a roughly 41% reduction for that reconstruction check, not for the full
frontend. At that prototype checkpoint, the production interpreter and
certificates were unchanged. The integration described below supersedes that
state; these prototype times are not full fresh-check measurements.

The integration boundary is now concrete:

1. Generalize the existing interpreter over node references, retaining one
   grammar-directed implementation. Keep emitted parse-node IDs as ordinary
   IDs, including the intermediate type-path data.
2. Supply indexed-ID and checked-tree readers. Prove that the interpreter gives
   the same result when primitive reads and child IDs agree.
3. Use successful linking and root-ID selection to transport the linked result
   to the existing certificate contract. Then measure all units fresh, including
   artifact generation and every other validation phase.

The temporary interpreter copies must not become a second maintained grammar
implementation. Logs are `/tmp/lanius-cache-layout64.log`,
`/tmp/lanius-cache-layout8.log`, `/tmp/lanius-linked-reconstruction.log`,
`/tmp/lanius-checked-linked-reconstruction.log`, and
`/tmp/lanius-whole-reconstruction-control.log`.

## Checked-reference integration

The production interpreter now supports indexed and checked references through
one grammar implementation. `Reconstruction/Transport.lean` proves exact
agreement for all reconstruction functions, including failure and arbitrary
fuel/state counters. `Reconstruction/Checked.lean` proves that successful
linking, declared-root selection, and reconstruction certify the existing
indexed predicate. Its axiom audit contains only the three standard axioms.

The integrated Symbol check took **12.5 s kernel time, 13.30 s wall**, with
4,267,900 KiB peak RSS. This includes linking the original artifact nodes and
transporting the result to `reconstructArtifactSurfaceView`. It does not compile
a copied interpreter. The earlier indexed whole-unit control took 21.9 s kernel
and 22.91 s wall. Imports were built in both isolated checks; these are not
fresh artifact-generation or full frontend totals.

The other large units also passed isolated checks through the shared entry point:

| Unit | Kernel seconds | Wall seconds | Peak RSS, KiB |
|---|---:|---:|---:|
| Lexer | 10.5 | 11.31 | 4,020,680 |
| CanonicalTokens | 14.3 | 15.16 | 4,932,600 |
| RawLexer | 10.0 | 10.78 | 3,948,452 |

All nine production certificates now use this entry point. The 43 old
reconstruction shard files and the unused composition helper are removed, not
replaced with forwarding imports. The fresh frontend graph has 263 modules.
`Reconstruction/Tests.lean` checks root selection, absent/missing roots, empty
input, wrong productions, token/node confusion, dangling children, exact output,
arbitrary counters, and exhausted fuel. It and `ParseTreeTests.lean` pass.

The completed full fresh run took **599.71 s (9 min 59.7 s)** for all **263
modules**, versus **661.45 s** for the previous 306-module graph: **61.74 s
saved (9.3%)**. The final theorem
`Lanius.Extraction.verifiedFrontendPack_surface_data_checked_kernel` passed its
axiom audit with only `propext`, `Classical.choice`, and `Quot.sound`.
Peak RSS was **8,968,152 KiB (8.55 GiB)**, down from 10,193,868 KiB (9.72 GiB).

| Full-run component | Before, seconds | After, seconds |
|---|---:|---:|
| Checking/elaboration, including quotation and code generation | 562.334 | 512.150 |
| Imports | 80.429 | 68.728 |
| Object export | 14.494 | 14.585 |
| Import-cache update | 0.041 | 0.032 |
| Other command overhead | 4.152 | 4.215 |
| Total wall | 661.450 | 599.710 |

Reconstruction checking fell from **127.333 s to 73.440 s (42.3%)**. Removing
the shard module boundaries also reduced aggregate import time by 11.701 s.
Unchanged phases varied between runs, so the total saving is not exactly the
sum of those two reductions.

| Current checking/elaboration category | Seconds |
|---|---:|
| Artifact/data/cache generation | 120.771 |
| Token validation | 104.445 |
| Parse validation and assembly | 86.874 |
| Origins | 79.135 |
| Reconstruction | 73.440 |
| View authentication | 33.949 |
| Claims | 6.037 |
| Final assembly | 3.694 |
| Decoding | 3.253 |
| Pack assembly | 0.552 |

The three-second goal remains unmet. Artifact/data generation and token
validation were the two largest checking categories at this checkpoint. One
unmeasured follow-up was repeated artifact-pack JSON decoding: the quotation entry points
decode the same whole pack independently for fields and cache trees. Profiling
must separate that cost from constructor quotation and code generation before
changing the cache boundary.

Repeat the full run with `python3 formal/benchmark-surface.py --batch` after
building shared infrastructure. Its fresh objects do not update the normal
Lake cache. Full log: `/tmp/lanius-linked-full-timing.jsonl`.
Isolated logs: `/tmp/lanius-integrated-linked-reconstruction.log` and
`/tmp/lanius-linked-{Lexer,CanonicalTokens,RawLexer}.log`.

## Process-local artifact-input reuse

The next profile measured the 7,189,442-byte pack's JSON parsing at 96–102 ms
and typed decoding at 238–257 ms per call, over five repetitions. The frontend
sources contain over a hundred pack-quotation calls; previously each decoded
the entire nine-unit pack independently, even when quoting one field.

`ArtifactQuote.decodeArtifactPackInput` now retains one successful decoded
input for reuse by artifact, cache-tree, and origin quotation. It compares the
complete input string, not a path or hash. Changed input is decoded again;
malformed input returns the original decoder error. The process starts with an
empty cache and retains only the last successful input. It stores no theorem,
kernel result, or quoted expression, and does not bypass code generation.

On the real pack, the first cached call took 334 ms and the next four rounded
to 0 ms. The isolated Lexer artifact check took 8.81 s wall, with quotation
interpretation at 0.532 s and kernel checking at 0.108 s; compiler passes
remain the larger cost in that module.

`ArtifactQuoteTests.lean` passed 196 differential decoding checks across
repeated inputs, replacements, equivalent encodings, malformed JSON, and
well-formed invalid data. It compares complete constructor expressions or
exact decoder errors against uncached decoding. Three kernel `rfl` examples
also check quotation results across input changes.

The full fresh run passed all **263 modules in 569.25 s (9 min 29.3 s)**,
down from 599.71 s: **30.46 s saved (5.1%)**. The final theorem and its axiom
audit passed with only `propext`, `Classical.choice`, and `Quot.sound`.
Peak RSS fell from 8,968,152 to **8,569,720 KiB (8.17 GiB)**.

Artifact/data/cache generation fell from **120.771 to 90.797 s**, accounting
for nearly all the saving. The other checker phases and imports were unchanged
in scope and varied modestly between runs. No native-code generation or kernel
check was disabled.

| Current full-run component | Seconds |
|---|---:|
| Checking/elaboration, including quotation and code generation | 481.887 |
| Imports | 68.630 |
| Object export | 14.645 |
| Import-cache update | 0.026 |
| Other command overhead | 4.062 |
| Total wall | 569.250 |

Within checking/elaboration, token validation is now largest at **105.009 s**,
followed by artifact/data generation (90.797 s), parse validation/assembly
(85.861 s), origins (80.113 s), and reconstruction (72.432 s). The three-second
goal remains unmet. The next profile should separate source/token decoding,
raw scanning, and canonical retagging within token validation rather than
assuming which one dominates.

Logs: `/tmp/lanius-quote-profile.log`, `/tmp/lanius-cached-quote-profile.log`,
`/tmp/lanius-cached-lexer-artifact.log`, and the full-run log
`/tmp/lanius-cached-input-full-timing.jsonl`.

## Raw-token segmentation cleanup

Isolated kernel profiles of Symbol, each in a separate Lean process, measured:

| Diagnostic check | Kernel seconds |
|---|---:|
| Source decoding to a materialized byte list | 0.302 |
| Raw-token decoding to a materialized token list | 1.130 |
| Canonical-token decoding to a materialized token list | 0.864 |
| Raw scanning on materialized inputs | 4.440 |
| Canonical retagging on materialized inputs | 1.810 |
| Existing combined canonical-token checker | 3.620 |

These are separate workloads, not additive pieces of one timed command.
The fixture data was already built; its generation is not included in these
diagnostic kernel timings. The initial multi-theorem profile reported cumulative
times, so only the separate-process logs support this table.

The larger avoidable cost was raw-scan segmentation. In the preceding full
run, Symbol's eight-module raw chain took 18.087 s of checking/elaboration;
CanonicalTokens' ten-module chain took 27.138 s. The segment proofs repeatedly
used computed decoded inputs and certified intermediate remaining-source lists.

Direct proofs of the unchanged `checkTokenArtifactRawTrace` predicate passed
in 5.76 s kernel/6.55 s wall for Symbol and 6.91 s kernel/7.71 s wall for
CanonicalTokens. Peak RSS was 2,955,536 and 3,234,388 KiB respectively. Both
certificates used only `propext` and `Quot.sound`; no new scanner algorithm,
native axiom, or unchecked input was introduced.

All nine units now use whole raw-trace checks. The two split chains' 16 data,
segment, split, and assembly files are removed without forwarding modules.
The fresh frontend graph has 247 modules. The full fresh run passed in
**522.79 s (8 min 42.8 s)**, down from 569.25 s: **46.46 s saved (8.2%)**.
The aggregate theorem and axiom audit passed with only `propext`,
`Classical.choice`, and `Quot.sound`. Peak RSS was 8,748,812 KiB (8.34 GiB),
slightly above the preceding run's 8.17 GiB.

In the full run, the new Symbol and CanonicalTokens raw checks took 6.138 s
and 7.109 s of checking/elaboration. Their combined reduction was 31.978 s.
Aggregate token validation fell from **105.009 to 70.510 s**. Import time also
fell, and unchanged phases varied between runs; the full saving should not be
attributed solely to the two raw checks.

| Current full-run component | Seconds |
|---|---:|
| Checking/elaboration, including quotation and code generation | 442.128 |
| Imports | 62.400 |
| Object export | 13.996 |
| Import-cache update | 0.029 |
| Other command overhead | 4.237 |
| Total wall | 522.790 |

The remaining checking/elaboration costs are now distributed across artifact
generation (88.160 s), parse validation/assembly (85.151 s), origins (81.179 s),
token validation (70.510 s), reconstruction (70.462 s), and view authentication
(33.426 s). Claims, decoding, pack assembly, and final assembly total 13.240 s.
The three-second goal remains unmet; no single remaining category accounts for
most of the time.

Logs: `/tmp/lanius-token-{source,raw_decode,canonical_decode,scan,retag,combined}.log`,
`/tmp/lanius-raw-whole-{Symbol,CanonicalTokens}.log`, and the full-run log
`/tmp/lanius-whole-raw-full-timing.jsonl`.

## Subtree-interval experiment (not in the production graph)

The experimental `Origins/Intervals.lean` proves that an authenticated postorder subtree
interval implies the existing `ParseNodeContainsNodeEvidence` relation.
`nodesValid_sound` preserves `SurfaceNodeClaimMatches`, including the production
constraint. The untrusted `artifact_pack_unit_subtree_starts%` quotation proposes
one start per node; kernel reduction checks the table before using it.

The focused tests cover self/descendant membership, separate roots, missing
roots, malformed table metadata, forged bounds, gaps, duplicate children,
future references, reversed children, and shared-child DAG rejection. Tests
also check proposals from the generator on valid and invalid topology. Both
soundness theorems use only `propext`, `Classical.choice`, and `Quot.sound`.

Sequential direct Lean checks with existing artifact/view/origin dependencies
built gave these wall times (12,000 MB memory limit):

| Unit | Existing node-path check | Interval quotation + authentication + node claims |
|---|---:|---:|
| Symbol | 10.27 s | 8.62 s; repeat 9.22 s |
| CanonicalTokens | 12.37 s | 11.41 s |

The Symbol repeat disabled closed-term extraction for the proposed table, so
it is not a controlled timing repeat of identical compiler options. These few
runs establish only a modest candidate saving, not a stable speedup estimate.
The interval runs also derive and audit the declarative claim theorem. They
include table generation, but reuse the existing SurfaceOrigins quotation;
they do not measure removing its now-unneeded node paths. Peak RSS fell from
3.88 to about 2.5 GiB for Symbol and from 4.39 to 2.82 GiB for CanonicalTokens.

No production unit uses this route. The latest full fresh measurement
remains **522.79 seconds**. The extra authentication traversal limits the
benefit. The accepted interval checker is intentionally stricter than the general
ancestry relation; it cannot certify arbitrary DAGs or validate arbitrary old
path strings. Integration must construct the existing declarative claims
contract directly, not assert that the old path Boolean passed.

### Broader experiments reject the current interval design

A fused traversal was proved equivalent to the conjunction of the original
postorder parse check and interval authentication. For Symbol, including table
quotation and node claims, it took **21.00 s**, versus **21.32 s** for separate
passes in one process. This is not a meaningful measured gain. A single-stack
performance prototype took **19.72 s**, but had no soundness theorem and was
not used as a validity certificate.

A second experiment reused the authenticated intervals for spelling origins
as well. Its soundness theorem preserves both exact token text and declarative
token containment. Tests reject wrong text, sibling ownership, missing tokens,
invalid owners, wrong slots, node edges in token slots, and mismatched witness
counts. The original intermediate paths are unused: only proposed direct-owner
and slot endpoints are checked. The theorem's axioms remain the standard three.

With both node and spelling checks in one process, Symbol took **13.05 s** with
intervals (including quotation and authentication), versus **12.66 s** with
the existing paths. Both reuse the original artifact/view/origin data. The
earlier standalone node-check timings therefore do not establish a useful
combined-origin speedup. Reusing the interval table did not repay its cost.

The experimental modules and quotation helper have been removed from the
repository, not left as unused shared infrastructure. Source snapshots are in
`/tmp/lanius-interval-experiment/Lanius/Extraction/`, including the quotation
helper and focused tests. Fixtures are `/tmp/Interval{Combined,Separate,Stack,AllOrigins}.lean`,
`/tmp/PathAllOrigins.lean`, `/tmp/LaniusIntervalPilot.lean`, and
`/tmp/LaniusIntervalCanonical.lean`. Reproduction requires building the saved
experimental modules in a scratch Lean workspace against the repository's
shared dependencies before running those fixtures with `lean -M 12000`.
No production certificates changed during these experiments.

## Whole origin certificates: 210 modules, 504.457 seconds

After rejecting interval authentication, the existing complete
`SurfaceOrigins.valid` predicate was checked directly for each unit. This
removes independent module imports and composition, without replacing the
validator. Dense IDs, node productions and ancestry, spelling text and token
ancestry, and coverage are all still checked. Lexer retains the separate
claims-equality proof in its origin module; other units retain it in Claims.

The eight split chains and their 37 files were removed, including Lexer's
four node-origin chunks. TokenScan already had a whole certificate. No
forwarding modules or old-path imports remain.

The full fresh benchmark passed in **504.457 s (8 min 24.5 s)**, down from
522.790 s: **18.333 s saved (3.5%)**. It checked all **210 frontend-specific
modules**, the aggregate theorem, and the standard three-axiom audit.
Peak RSS increased to **9,281,808 KiB (8.85 GiB)** from 8.34 GiB. This remains
under the configured 12,000 MB Lean limit but is a real memory tradeoff.

| Full-run component | Seconds |
|---|---:|
| Checking/elaboration | 434.100 |
| Imports | 53.413 |
| Object export | 14.593 |
| Import-cache update | 0.022 |
| Other command overhead | 2.329 |
| Total | 504.457 |

Origins checking/elaboration fell from **81.179 to 71.400 s**. Including
module import/export overhead, the origin phase fell from **92.825 to
73.737 s**. Lexer alone fell from 18.319 s across ten modules to 13.521 s in
one module; CanonicalTokens fell from 19.443 to 17.053 s. Unchanged phases
varied, so these local savings should not be added to the full-run saving.

The benchmark's outer process took 506.007 s; `/usr/bin/time` reported
506.17 s including the Python launcher. The comparable internal check time
above includes every fresh frontend artifact, cache, proof, and final audit,
with only shared non-program infrastructure prebuilt.

Log: `/tmp/lanius-whole-origins-full-timing.jsonl`.

## Shared parse-node data experiment and unused Lexer quotations

A Symbol prototype quotes the artifact's eleven other fields and obtains
`parse_nodes` from the already-quoted parse-node cache tree. A kernel proof
establishes exact equality of the resulting artifact with the original,
including raw tokens and evidence; it uses no axioms. This is still only a
scratch prototype, not a production representation change.

The prototype also tested an accumulator-based linear tree flattening function.
Its generic theorem proves equality with the existing semantic `flatten` for
every tree, independently of cached metadata. It did not materially improve
the measured parse check, so it has not been added to shared infrastructure.

| Symbol workload, separate processes | Original | Shared tree, linear flatten |
|---|---:|---:|
| Artifact quotation and export | 8.06 s | 3.76 s |
| Parse-node checker | 13.87 s | 15.01 s |
| Reconstruction and full origins | 25.06 s | 25.68 s |

The ordinary-flatten prototype quoted/exported in 3.43 s and checked parse
nodes in 15.18 s. Its checked view took 0.78 s and its exact artifact equality
audit took 1.72 s. All downstream soundness audits passed with the existing
axiom sets. These isolated timings reuse the tree and other dependencies;
they do not count as full fresh frontend measurements. Their savings and
regressions suggest a modest candidate improvement, not a large speedup.
Migration would also have to reverse artifact/cache dependencies without
cycles and count all cache-tree generation fresh. No such migration is claimed.

While tracing those dependencies, seven unused Lexer parse-node slice
declarations were found in `Artifact/Lexer/Artifact.lean`. They duplicated the
entire 6,991-node table after its original consumers had been removed. A
repository-wide reference search found no consumers. They are now deleted;
the complete artifact definition is unchanged. No other artifact `def` in
the same scan lacked references outside its defining file.

The trimmed Lexer artifact module checked, compiled, and exported in **7.48 s**
with peak RSS **2,076,092 KiB**. Its last full-run module time was 10.514 s,
but that is not a controlled repeat or a new full-run result. The latest full
fresh check remains **504.457 s / 210 modules**; the slice deletion does not
change the module count.

Scratch sources: `/tmp/Shared{Artifact,View,Audit,Parse}.lean`,
`/tmp/Fast{Flatten,Artifact,View,Parse,Downstream}.lean`, and
`/tmp/Original{Parse,Downstream}.lean`. Scratch imports use `/tmp` in `LEAN_PATH`;
all timed Lean processes use the 12,000 MB limit. No scratch sources were
installed in the repository or used as production proof dependencies.

## Shared CanonicalTokens node data: 198 modules, 485.476 seconds

CanonicalTokens now quotes its 10,311 parse nodes once, into the existing
balanced tree. Its artifact uses that tree's `flatten`, and the checked view
uses the same tree. The representation proof is `rfl`; tree well-formedness,
parse validation, reconstruction, and all origin checks remain in force.
The tree is program-specific and built fresh inside the measured graph.

The eight tree-quotation modules no longer import the artifact they now feed.
The eleven duplicate node-list quotation modules and their assembly module
are removed; no aliases or forwarding files remain. Every other artifact
field is unchanged. Before migration, a kernel theorem proved the candidate
artifact exactly equal to the previous artifact, with no axioms.

The full fresh run passed in **485.476 s (8 min 5.5 s)**, versus 504.457 s:
**18.981 s saved (3.8%)**. All **198 modules**, the final aggregate theorem,
and its `propext`/`Classical.choice`/`Quot.sound` audit passed. Peak RSS fell
from **8.85 to 8.41 GiB** (8,820,544 KiB).

| Full-run component | Seconds |
|---|---:|
| Checking/elaboration | 421.523 |
| Imports | 49.454 |
| Object export | 12.119 |
| Import-cache update | 0.022 |
| Other command overhead | 2.358 |
| Total | 485.476 |

All CanonicalTokens modules together fell from **119.634 to 108.680 s**,
despite its node checker increasing from 17.592 to 18.457 s. Lexer artifact
generation also fell from **10.514 to 7.072 s**, following removal of the
unused slices in the preceding turn. Other phases varied; the entire 18.981 s
saving should not be attributed solely to shared CanonicalTokens data.

The outer process took 487.054 s; `/usr/bin/time` including the launcher
reported 487.23 s. The comparable internal time above includes all fresh
frontend data, caches, certificates, and the final audit.

Log: `/tmp/lanius-shared-canonical-full-timing.jsonl`.

After rebuilding the changed artifact dependencies in the normal Lake cache,
`/tmp/CanonicalSharedCurrentAudit.lean` also passed: a kernel theorem proves
the current artifact exactly equal to the full JSON quotation with no axioms,
and native evaluation compares every artifact field against freshly decoded
JSON. These are separate correctness audits, not inputs reused by the full
benchmark. A missing lambda type annotation in the scratch native audit was
corrected before that audit passed; the production proofs were unaffected.

## Shared node data across all units: total time essentially flat

The other eight units now share their quoted node tree between artifact and
view. `artifact_pack_unit_reusing_nodes%` quotes the remaining eleven fields
in one call and embeds an explicit node expression. An initial per-field
prototype added overhead for small units and was replaced before measurement.
Cache quotations no longer import the artifacts they feed; views import
their artifacts explicitly where needed. All native code generation remains.

Lexer and Symbol use reflexive representation proofs. Compact-cache units
use `ArtifactCache.matches_of_sharedNodes`, which derives the original full
`matches` result from structural representation and the remaining checks.
Metadata, tokens, and source bytes are still checked. Focused tests passed
for mismatched nodes (showing the representation premise is necessary),
forged metadata, wrong tokens, and wrong source bytes.

All eight changed artifacts passed kernel equality with the full JSON
quotation and native comparisons of every field against freshly decoded JSON.
Lexer and Symbol's equality proofs used no axioms; the six compact-cache
units used only `propext`. The quotation helper's tests check non-node field
preservation and correct node-field substitution. Audit sources are in
`/tmp/shared-node-audit/`.

The full fresh run passed **198 modules**, the aggregate theorem, and the
standard three-axiom audit in **484.393 s (8 min 4.4 s)**. The preceding run
took 485.476 s: a **1.083 s difference (0.2%)**, too small to establish a
meaningful speedup. Peak RSS increased from 8.41 to **8.53 GiB** (8,943,000 KiB).

| Full-run component | Seconds |
|---|---:|
| Checking/elaboration | 422.522 |
| Imports | 49.435 |
| Object export | 10.234 |
| Import-cache update | 0.016 |
| Other command overhead | 2.186 |
| Total | 484.393 |

Artifact-family checking/elaboration fell from **77.412 to 62.288 s**; view
checking fell from **31.217 to 21.347 s**. Other checking costs offset those
savings. Decode checking rose from **3.980 to 7.082 s**. The unchanged
CanonicalTokens node check also varied from 18.457 to 19.907 s wall, so not
every timing change can be attributed to the representation change.

Repeated `artifact.parse_nodes.length` evaluations are a concrete next
profiling target: reconstruction and decoding use the computed list's length
as fuel even though its authenticated tree stores the count. This is a
hypothesis to measure, not a completed attribution of the regressions.

Shared infrastructure was rebuilt before timing. Every program-specific
tree, artifact, view, and certificate was then built fresh. Outer process
time was 486.019 s; the launcher reported 486.19 s.
Log: `/tmp/lanius-shared-all-nodes-full-timing.jsonl`.

## Authenticated node counts: 474.821 seconds

`ArtifactView.nodeCount` reads the tree's stored size. Its generic equality
proof uses tree well-formedness and representation to establish exactly
`artifact.parse_nodes.length`; it does not trust an unchecked cached number.
`Reconstruction.checkedView` now uses that count for fuel. `checkedView_eq`
proves equality with the original computation for all authenticated views,
not merely successful examples. Focused reconstruction and view tests passed.

All nine units also decode with cached-count fuel. The eight Decode modules
and Lexer's assembly macro keep their published decoding-found statements
in terms of the original list length, using `decodeSurfaceFile_of_nodeCount`
to transport the result symbolically. The decoded value and fuel budget are
unchanged; no compatibility wrappers or program-specific count certificates
were introduced.

The complete fresh check passed in **474.821 s (7 min 54.8 s)**, down from
484.393 s: **9.572 s saved (2.0%)**. All **198 modules**, the final theorem,
and the standard three-axiom audit passed. Peak RSS fell from 8.53 to
**8.36 GiB** (8,765,000 KiB).

| Full-run component | Seconds |
|---|---:|
| Checking/elaboration | 414.096 |
| Imports | 48.765 |
| Object export | 9.787 |
| Import-cache update | 0.025 |
| Other command overhead | 2.148 |
| Total | 474.821 |

The eight standalone Decode modules fell from **7.082 to 1.842 s** of
checking/elaboration. Symbol alone fell from 1.564 to 0.278 s. Reconstruction
fell from **76.934 to 73.880 s**. These measurements support a decoding
benefit, but not a uniform improvement in every unit: Lexer's assembly,
which includes its decoding proof, rose from **3.777 to 5.966 s**. Its
assembly/fuel conversion is worth inspecting separately. Unchanged phases
also varied, so local deltas must not be added to the full-run saving.

Shared infrastructure was rebuilt before the benchmark. All frontend-specific
data and proofs were then checked fresh. Outer process time was 476.364 s;
the launcher reported 476.53 s.
Log: `/tmp/lanius-cached-node-count-full-timing.jsonl`.

## Indexed root-shape checks: 469.157 seconds

`rootShapeValidView` reads the root through the authenticated node tree and
uses authenticated node/token counts. Its generic equality theorem proves
exact agreement with `rootShapeValid`, preserving the final-node requirement,
start nonterminal, zero start position, full token-span end position, and
missing-root rejection. No data or condition was removed from the contract.

All nine units use this checker to derive the original root-shape predicate.
The eight `kernel_parse_root` callers now supply their views explicitly;
Lexer's direct proof uses the same soundness lemma. Focused tests passed for
empty/missing roots, nonfinal roots, wrong nonterminals, and incorrect spans,
along with the general equivalence theorem and token-count tests.

The full fresh benchmark passed **198 modules**, the final theorem, and the
standard three-axiom audit in **469.157 s (7 min 49.2 s)**, versus 474.821 s:
**5.664 s saved (1.2%)**. Peak RSS increased from 8.36 to **8.63 GiB**
(9,047,948 KiB).

| Full-run component | Seconds |
|---|---:|
| Checking/elaboration | 407.110 |
| Imports | 50.496 |
| Object export | 9.213 |
| Import-cache update | 0.029 |
| Other command overhead | 2.309 |
| Total | 469.157 |

Metadata checking/elaboration fell from **19.226 to 8.882 s**. Lexer fell
from 8.463 to 3.730 s, CanonicalTokens from 2.688 to 1.125 s, and Symbol from
2.202 to 0.877 s. The metadata reduction is larger than the end-to-end saving;
other phases varied and offset part of it. These are measurements from one
full run on each side, not a statistically stable speedup estimate.

Shared infrastructure was rebuilt before timing; all frontend data and
certificates were fresh during the run. Outer process time was 470.726 s;
the launcher reported 470.89 s.
Log: `/tmp/lanius-indexed-root-full-timing.jsonl`.

## Lexer proof glue: focused reductions after the 469.157-second run

Two remaining costs came from connecting proofs, not validating more input.
Lexer metadata now uses `kernel_parse_root`, as the other eight units do.
This replaces its concrete `cbv` root-presence proof and concrete option
case analysis with `kernel_rfl` and the shared `parseOptionEqSomeGet` lemma.
The four declarations retain their names and statement types.

The assembly macro now spells the decode fuel as `length + 1`, matching
`decodeSurfaceFile_of_nodeCount` and `CheckedSurfaceArtifact.ofOrigins`.
The previous `length.succ` is definitionally equal, but incurred expensive
conversion when applying the helper and constructing the checked package.
No checker, fuel value, or proof obligation changed.

Focused Lean profiles used `-M 12000 -DElab.async=false -Dprofiler=true
-Dprofiler.threshold=1`, with current lexer dependencies already built:

| Profile category | Before | After |
|---|---:|---:|
| Metadata tactic execution | 968 ms | 0.292 ms |
| Metadata kernel type checking | 1.44 s | 550 ms |
| Assembly tactic execution | 2.54 s | 1.1 ms |
| Assembly kernel type checking | 1.74 s | 92.5 ms |
| Assembly elaboration | 1.93 s | 289 ms |

These are profiler categories, not additive end-to-end timing claims. The
metadata comparison was repeated after rebuilding stale local dependencies;
the original proof was reproduced in `/tmp/LaniusLexerMetadataBefore.lean`.
Logs are `/tmp/lanius-metadata-glue-{before,after}.log` and
`/tmp/lanius-assembly-fuel-{before,after}.log`.

The lexer dependency build passed through `Surface.Lexer.Assembly` (55 local
modules), and its final certificate's axiom audit passed with only `propext`,
`Classical.choice`, and `Quot.sound`. The assembly macro has only this one
production caller. No full fresh frontend benchmark was run after these two
changes; **469.157 seconds remains the latest measured full-run result**.

## Shared parse-check assembly: full fresh check in 461.470 seconds

`checkParseArtifact_of_checks` now combines the token, semantic-kind, node,
root-presence, and root-shape certificates over an arbitrary artifact.
Lexer applies this shared theorem instead of rewriting its concrete checker.
Every condition remains required. Focused profiling reduced parse assembly's
tactic execution from 2.57 s to 0.8 ms and kernel type checking from 1.21 s
to 0.307 ms. The generic theorem compiled, and the root-test axiom audit passed.

After rebuilding shared infrastructure, the full fresh run passed **198
frontend-specific modules** and
`verifiedFrontendPack_surface_data_checked_kernel`, with only `propext`,
`Classical.choice`, and `Quot.sound`. It took **461.470 s (7 min 41.5 s)**,
down **7.687 s (1.6%)** from 469.157 s. This includes the two preceding lexer
proof-glue changes as well as the shared parse-check assembly theorem.

| Full-run checking/elaboration | Before | After |
|---|---:|---:|
| Lexer metadata | 3.730 s | 0.931 s |
| Lexer parse assembly | 3.991 s | 0.177 s |
| Lexer surface assembly | 5.944 s | 0.492 s |
| These three modules | 13.665 s | 1.600 s |

The local reduction of 12.065 s exceeds the total reduction; unchanged work
varied and offset some savings. This is one full run on each side, not a
statistically stable estimate. Total checking/elaboration was 399.281 s,
imports 50.914 s, exports 8.987 s, import-cache updates 0.025 s, and other
overhead 2.263 s. Peak RSS was **8.69 GiB** (9,106,752 KiB), slightly above
the preceding 8.63 GiB. Outer process time was 463.123 s (launcher 463.30 s).

Command: `python3 formal/benchmark-surface.py --batch` under `/usr/bin/time`.
Log: `/tmp/lanius-proof-glue-full-timing.jsonl`.
All program data, caches, and certificates were checked fresh; normal Lake
frontend objects were not reused. The multi-second node, reconstruction,
and origin checks remain the larger optimization targets.

## Node-kernel sampling and rejected micro-optimizations

The lexer node module's focused profile assigns **11.5 s to kernel type
checking**, versus 2.07 ms to tactics and 1.96 ms to elaboration. This differs
from the preceding assembly hotspots: replacing concrete proof glue is not
enough here.

Sampling the unchanged checker with `perf record -e cycles:u -F 99
--call-graph dwarf,8192` collected 1,275 samples without lost samples. The
report's self percentages included:

| Symbol family | Sampled cycles |
|---|---:|
| Expression-to-expression hash-map lookup | 19.87% |
| `lean_dec_ref_cold` | 13.42% |
| `replace_rec_fn::apply` | 4.61% |
| `get_app_num_args` | 4.29% |
| Structural expression equality | 3.41% |

These are samples across the process, not a full allocation profile or an
attribution to individual Lean definitions. They suggest substantial
expression-management costs, but do not establish which source change will
reduce them. The recording is `/tmp/lanius-node-kernel.perf`; inspect with
`perf report --stdio --no-children --sort symbol -g none`.

A separate run with `-Ddiagnostics=true -Ddiagnostics.threshold=1000` reported
945,073 unfoldings each of the list-indexing helper and its two match helpers,
973,022 `Nat.casesOn` unfoldings, 59,199 `decide` unfoldings, and 6,991 calls
to `Grammar.production?` and `ParsePostorder.node`. These are counts, not
time percentages. Log: `/tmp/lanius-node-kernel-diagnostics.log`.

Two scratch experiments preserved the checker exactly but did not improve
the measured lexer check:

- An eight-element-leaf `SeqTree` for grammar productions proved its
  representation, well-formedness, lookup equivalence for every index, and
  whole-check equivalence for arbitrary node lists/stacks under the Lanius
  grammar. Its concrete check took 11.8 s, versus 11.5 s for the original.
- Direct `Nat.ble`/Boolean equality in the node predicate proved whole-check
  equivalence for arbitrary grammars, artifacts, views, node lists, and
  stacks. The concrete check still took 11.5 s.

Both final scratch proofs passed with only `propext` and `Quot.sound`.
Initial proof-script errors were corrected before those audits; neither
prototype is a production dependency. Files are
`/tmp/LaniusGrammarLookupPilot.lean` and `/tmp/LaniusNativeComparePilot.lean`;
logs are `/tmp/lanius-grammar-lookup-pilot.log` and
`/tmp/lanius-native-compare-pilot.log`. These are single-run measurements,
enough to reject a claimed clear win, not to rank small differences reliably.

The [Lean 4.33.1 kernel implementation](https://github.com/leanprover/lean4/blob/v4.33.1/src/kernel/type_checker.cpp)
confirms that reduction uses expression-keyed caches and expression
instantiation. A next hypothesis is to reduce the arguments and intermediate
expressions carried through recursive validation, while proving exact
equivalence. This has not yet been tested. Production source and the latest
full-run result, **461.470 seconds**, are unchanged by these experiments.

## Recursive-context and explicit-recursion experiments

Passing only the semantic-kind tree through node/child checking, rather than
the dependent `ParseArtifactView`, did not help: the scratch checker took
12.1 s in kernel type checking, versus the preceding 11.5 s baseline.
`/tmp/LaniusSmallContextPilot.lean` proves exact agreement for arbitrary
grammars, authenticated views, positions, node lists, and stacks. Its final
equivalence and concrete acceptance audits use only `propext` and `Quot.sound`.
Log: `/tmp/lanius-small-context-pilot.log`.

Two explicit-recursion experiments then separated recursion machinery from
the validation predicates:

- `List.rec` for the outer node traversal took 11.2 s. Its whole-check
  equality is proved for arbitrary inputs (only `propext`). This small
  single-run difference is not enough to justify changing production.
  File/log: `/tmp/LaniusDirectRecPilot.lean`, `/tmp/lanius-direct-rec-pilot.log`.
- `SeqTree.rec` for grammar-tree lookup took 10.7 s, then 10.4 s in a repeat;
  the unchanged checker took 11.7 s immediately before the repeat. This
  extends the preceding grammar-tree prototype, whose ordinary recursive
  lookup took 11.8 s. The direct lookup is proved equal to ordinary lookup
  for every tree and index; whole-check equivalence and concrete acceptance
  still pass with only `propext` and `Quot.sound`.

The latter prototype now lives in `/tmp/LaniusGrammarLookupPilot.lean`.
Logs: `/tmp/lanius-direct-lookup-pilot.log`,
`/tmp/lanius-rec-control-repeat.log`, and
`/tmp/lanius-direct-lookup-repeat.log`. These are focused kernel timings,
not full-check improvements or a statistically stable speedup estimate.

Lean's native code generator rejects these raw recursor definitions without
a compiled implementation, so the scratch versions are `noncomputable`.
That does not prevent kernel reduction or weaken the proofs, but it is not
an acceptable replacement for the currently executable shared checker by
itself. Initial scratch elaboration errors were corrected before the final
audits. No production source changed. The next test is a proved-equivalent
lookup with an executable implementation, followed by measurements on the
existing token/node/origin lookup consumers. The full-run baseline remains
**461.470 seconds**.

## Executable direct tree lookup: 453.829-second full fresh check

`SeqTree.lookup` now uses an explicit recursor for kernel reduction. A private
ordinary recursive implementation supplies compiled execution through a
proved `@[csimp]` equality. This equality covers all trees and indices,
including malformed metadata, not only well-formed trees. The existing
`lookup_eq_flatten` theorem still requires authenticated metadata. No new
axiom, unchecked evaluator, public alias, or frontend-specific cache was added.

`SeqTreeTests` checks both kernel reduction and compiled `#guard` evaluation
at branch boundaries, leaf ends, out-of-range indices, and empty trees. It
also checks that forged cached sizes remain rejected by `wellFormed`.
These tests and `ArtifactViewTests` passed. The 41-module shared-infrastructure
build passed before timing, and the complete fresh frontend check passed
all 198 modules and `verifiedFrontendPack_surface_data_checked_kernel` with
only `propext`, `Classical.choice`, and `Quot.sound`.

The full run took **453.829 s (7 min 33.8 s)**, compared with 461.470 s:
**7.641 s saved (1.7%)**. Peak RSS fell from 9,106,752 KiB (8.69 GiB) to
**8,412,472 KiB (8.02 GiB)**, a 7.6% reduction. The elapsed-time gain is
modest; the memory reduction is also useful. These remain single full-run
comparisons rather than statistically stable estimates.

| Checking/elaboration family | Before | After |
|---|---:|---:|
| Origins | 70.771 s | 63.992 s |
| Parse nodes | 77.253 s | 77.712 s |
| Reconstruction | 75.054 s | 75.243 s |

The reduction comes mainly from origins, not a broad improvement to every
checker. A focused lexer-origin profile changed from 12.5 s to 12.2 s of
kernel type checking. The earlier grammar-tree prototype is still not used
by the production node checker.

Full-run phases: checking/elaboration 391.755 s, imports 50.685 s, export
8.964 s, import-cache update 0.021 s, other overhead 2.404 s. Outer process
time was 455.354 s; the launcher reported 455.52 s. All program-specific
objects were generated fresh.

Logs: `/tmp/lanius-direct-seqtree-full-timing.jsonl`,
`/tmp/lanius-seqtree-origins-before.log`, and
`/tmp/lanius-seqtree-origins-after.log`.

## Unpack nodes once: 427.474-second full fresh check

`ParsePostorder.node` now pattern-matches the node constructor once and uses
its fields directly, instead of repeatedly passing field projections to
lookup and comparison functions. The predicates and grammar lookup remain
unchanged. The soundness proof was adjusted to unpack the node as well.
There is still one production node checker and no new grammar index.

An attempted grammar index led to this change. With projection-based node
access, its focused lexer check took 11.1 s. Unpacking nodes reduced that
to 7.63 s with the index and 7.75 s with the original list lookup in the same
comparison. The index's small remaining advantage did not justify retaining
it: both new index files and all nine caller changes were removed, and the
tree builder stayed private. The retained change is confined to the node
predicate and its soundness proof, plus focused tests.

`ParsePostorderTests` proves exact node and whole-check equality to the former
projection-based implementation for arbitrary grammars, views, node lists,
positions, and stacks. These equality proofs depend only on `propext`.
Kernel and compiled tests cover valid empty productions and rejection of
missing productions, wrong nonterminals, invalid spans, and unexpected
children. A test-fixture well-formedness proof initially failed to elaborate;
it was corrected before the final tests passed. The shared-infrastructure
and focused-test build passed 42 local modules before timing.

The complete fresh check passed **198 frontend-specific modules**, the final
theorem, and the standard three-axiom audit in **427.474 s (7 min 7.5 s)**.
That is **26.355 s (5.8%)** less than 453.829 s. Peak RSS increased to
**8.40 GiB** (8,804,804 KiB), from 8.02 GiB. These are single full-run
measurements, not a statistically stable speedup estimate.

| Checking/elaboration family | Before | After |
|---|---:|---:|
| Parse nodes | 77.712 s | 54.031 s |
| Reconstruction | 75.243 s | 74.251 s |
| Origins | 63.992 s | 64.901 s |

Lexer nodes fell from 11.650 to 7.906 s; CanonicalTokens nodes fell from
19.190 to 12.254 s. The node-family reduction of 23.681 s accounts for most
of the total reduction. Other unchanged phases varied.

Kernel diagnostics now report 33,323 list-indexing helper unfoldings and
61,272 `Nat.casesOn` unfoldings, compared with 945,073 and 973,022 in the
earlier projection-based diagnostic run. The earlier diagnostic predates
the shared explicit-recursion lookup change as well; these counts are not
an isolated timing attribution. The focused unpacked-node diagnostic check
took 7.99 s. The results support exposing constructor fields before repeated
lookup as a useful way to improve kernel result reuse.

Full-run phases: checking/elaboration 366.297 s, imports 50.182 s, export
8.682 s, import-cache updates 0.025 s, other overhead 2.288 s. Outer process
time was 429.001 s; the launcher reported 429.17 s. All program data, caches,
and certificates were fresh; shared infrastructure was already built.

Logs: `/tmp/lanius-unpacked-node-full-timing.jsonl`,
`/tmp/lanius-unpacked-node-diagnostics.log`,
`/tmp/lanius-grammar-index-lexer.log`, and
`/tmp/lanius-destruct-node-comparison.log`.

## Token unpacking after the 427.474-second run

Unpacking child-stack entries did not produce a reliable improvement. The
scratch checker in `/tmp/LaniusUnpackedChildren.lean` proved exact child,
node, and whole-check agreement, but its final lexer measurement was 8.01 s
after an initial 7.31 s result. That is not a clear improvement over the
current approximately 8-second node check, so it was not installed.
Log: `/tmp/lanius-unpacked-children-pilot.log`. The final equivalence and
acceptance audits used only `propext` and `Quot.sound`; an initial unfinished
proof was fixed before that audit.

`TokenChecker.decodeToken` now unpacks the token and its span once. It retains
the same source-file, span-order, and token-kind checks and returns the same
raw token. In a focused sequential profile, lexer header kernel checking
fell from **1.55 s to 0.657 s**. Import time was 0.643 s and 0.622 s respectively,
and is excluded from those kernel figures. This is a single comparison, not
a statistically stable estimate.

`TokenCheckerTests` proves equality to the previous decoder for every token
and token list. Kernel and compiled checks cover valid/empty spans, nonzero
source IDs, reversed spans, and unknown kinds. An additional 1,600 compiled
comparisons cover 200 kind codes, two source IDs, and four span shapes.
The tests passed, as did fresh source checks of Lexer's header, raw-token,
and canonical-token certificates. The latter two measured 5.02 s and 2.51 s
of kernel checking; no paired baseline was recorded for them in this turn.

Logs: `/tmp/lanius-token-unpack-before.log`,
`/tmp/lanius-token-unpack-after.log`,
`/tmp/lanius-token-unpack-raw-after.log`, and
`/tmp/lanius-token-unpack-canonical-after.log`.
No new full fresh benchmark has been run since this decoder change;
**427.474 seconds remains the latest measured full-run result**.

## Reconstruction controls and origin-validation breakdown

Reconstruction experiments did not establish a reliable improvement, so none
were installed. Lexer reconstruction kernel checking measured 10.9 s initially,
11.3 s with token-span unpacking, 11.3 s with production/child-field unpacking,
and 11.6 s with byte-payload unpacking. The restored control then took 12.2 s.
This drift prevents interpreting these small differences as regressions or wins.
A raw-tree-reference pilot took 10.8 s, without proving generic transport to the
checked-reference interpreter. That is insufficient reason to rewrite the
reference/provenance proof infrastructure. An exactly equivalent link-input
unpacking pilot measured 3.98 s versus 3.79 s for a concrete `isSome` check;
that partial evaluation cannot be subtracted from full reconstruction time.

Logs: `/tmp/lanius-reconstruction-restored-control.log`,
`/tmp/lanius-text-unpack-{before,after}.log`,
`/tmp/lanius-reconstruction-fields-after.log`,
`/tmp/lanius-reconstruction-bytes-after.log`,
`/tmp/lanius-raw-tree-pilot.log`, and `/tmp/lanius-link-unpack-pilot.log`.

A fresh Lexer origins diagnostic profile measured 1.14 s for claim equality
and 10.3 s for origin validation (11.5 s cumulative kernel checking). Validation
unfolded the list-indexing helper 214,841 times and `followNodePath._f` 11,784
times. These are reduction counts, not a per-function time attribution.

Separate concrete component proofs in `/tmp/LaniusOriginComponents.lean` gave:

| Origin-validation component | Kernel checking |
|---|---:|
| Dense node IDs | 0.143 s |
| Node-origin paths | 7.47 s |
| Spelling origins | 2.45 s |
| Spelling coverage | 0.202 s |

These isolated checks identify node-origin paths as the next target. Their
sum need not equal the combined check because kernel reuse can differ.
Logs: `/tmp/lanius-origins-current-diagnostics.log` and
`/tmp/lanius-origin-components.log`.

The scratch `/tmp/LaniusOriginUnpack.lean` unpacks node-origin claims and paths
before validating them. It proves exact equality for arbitrary origins and
arbitrary claim/path lists. A successful sequential comparison measured the
current checker at **7.47 s** and the candidate at **6.27 s**. The equivalence
and concrete acceptance theorems use only `propext` and `Quot.sound`.
An earlier run measured 7.80 s and 6.74 s, but had a redundant proof tactic
error; that error was removed before the successful run and axiom audit.
This is a promising pilot, not an installed optimization or a full-run result.
Next, reverse the comparison order to check order bias before changing the
shared checker. Log: `/tmp/lanius-origin-unpack.log`.

## Installing node-origin unpacking

The reverse-order comparison also favored unpacking: candidate **6.29 s**,
then current checker **7.23 s**. Log:
`/tmp/lanius-origin-unpack-reverse.log`.

`SurfaceNodeOrigin.valid` now unpacks the claim and path once before checking
the same production, root, target, and direct-edge conditions. Its existing
soundness theorem was updated and rebuilt. No additional trusted axiom or
alternative production checker was introduced.

`SurfaceOriginTests` proves agreement with the previous checker for every
origin and every claim/path list. Kernel and compiled cases cover uncontained,
reflexive, and one-edge origins, missing nodes, disallowed productions,
mismatched optional paths, wrong roots/targets, token edges, absent child slots,
and missing path roots. The focused build passed (25 local dependencies).
The full fresh benchmark also includes the preceding token-decoder unpacking;
its overall delta will not isolate the origin change alone.

The full fresh run passed all **198 program-specific modules** and the final
`verifiedFrontendPack_surface_data_checked_kernel` theorem in **408.142 s
(6 min 48.1 s)**. This is **19.332 s (4.5%)** less than 427.474 s. The final
axioms remain exactly `propext`, `Classical.choice`, and `Quot.sound`.
Peak RSS was **8.04 GiB** (8,429,684 KiB), versus 8.40 GiB previously.
Shared infrastructure was built before timing; all program-specific outputs
were checked fresh. These are single full-run observations, not stable
statistical estimates.

| Checking/elaboration family | Previous run | Current run |
|---|---:|---:|
| Token certificates | 71.939 s | 56.525 s |
| Origins | 64.901 s | 57.630 s |
| Parse nodes | 54.031 s | 55.554 s |
| Reconstruction | 74.251 s | 75.359 s |

Lexer origins measured 11.297 → 10.699 s, and CanonicalTokens origins
15.624 → 12.871 s. The token-family improvement includes the earlier
decoder-unpacking change. Unchanged phases varied, so the overall reduction
must not be attributed solely to origin unpacking.

Full-run phases: checking/elaboration 346.265 s, imports 50.684 s, exports
8.788 s, import-cache updates 0.030 s, other overhead 2.375 s. Outer process
time was 409.709 s; the launcher reported 409.88 s. Log:
`/tmp/lanius-origin-unpack-full-timing.jsonl`.

## Fusing parse-tree linking: reconstruction pilot

A fresh Lexer reconstruction diagnostic check took 11.3 s. It unfolded
`List.take.match_1` 41,576 times, `List.drop._f` 24,887 times, and
`List.countP.go._f` 15,050 times. Counts are not time attribution, but they
motivate testing the linker's multiple passes over child slots and stack
prefixes. Log: `/tmp/lanius-reconstruction-current-diagnostics.log`.

The scratch `/tmp/LaniusFusedLinkPilot.lean` tests two fused approaches:

- Consume reversed child slots and pop the completed stack while accumulating
  children: full raw-tree reconstruction measured 10.3 s versus 10.7 s for the
  original linker. This difference is too small to justify adoption alone.
- Recurse through child slots first, then pop the stack while returning from
  that recursion. This avoids counting, taking, reversing, and dropping the
  stack prefix, and avoids reversing the child slots. It measured **9.27 s
  versus 10.9 s** (candidate first), then **9.82 s versus 11.1 s** (original
  first).

Both variants proved concrete equality of the entire linked lexer forest to
the original, not just `isSome`. The concrete forest equality checks took
11.8 s and 11.6 s respectively; those are validation costs of the pilot, not
part of the measured reconstruction theorem. Full reconstruction produced the
same quoted Surface output. The forest equality used only `propext`; the
Surface result used the standard three axioms.

The pilot uses raw-tree references for both alternatives so the interpreter
is held constant. It has **not** proved generic linker equivalence or soundness
for arbitrary node lists and stacks, and has not been installed. The next step
is to prove the fused consumer's child-order and remaining-stack invariants,
then measure it through the checked-reference production path. No production
source changed in this experiment. The latest full-run measurement remains
**408.142 s**.

Logs: `/tmp/lanius-fused-link-pilot.log`,
`/tmp/lanius-fused-link-recursive-pilot.log`, and
`/tmp/lanius-fused-link-recursive-repeat.log`. The scratch file currently
contains the second variant and the repeated timing pair; the earlier
concrete forest equality check is recorded in the first two logs.

## Fused-linker soundness and checked-reference pilot

`/tmp/LaniusFusedLinkProof.lean` now proves two general invariants for the
no-reversal consumer (with its unused accumulator removed):

- Given a valid initial forest, successful consumption produces
  `ChildrenValid` in the original slot order and leaves a valid remaining
  forest.
- Given valid original-node lookups and a valid initial stack, successful
  fused `linkFrom` produces a valid forest.

Both theorems check with only `propext` and `Quot.sound`. These prove
soundness, **not yet exact agreement with the previous linker on all inputs**.
An initial namespace ambiguity and a bind-reduction proof step were fixed
before the successful axiom audit; no unfinished proof remains in the scratch
file.

The candidate now packages the result as `ParseTree.Checked` references using
its general soundness theorem. Through the same checked-reference interpreter
as production, it measured **9.69 s versus 11.0 s** for lexer reconstruction.
The concrete Surface equality used exactly the standard three axioms.
Log: `/tmp/lanius-fused-link-checked-pilot.log`.

A compiled differential check also passed all **13,640** combinations of
child-slot lists of length at most four over one token and three node IDs,
and leaf stacks of length at most three over those node IDs. It compared
acceptance, linked child IDs including token slots, and leftover stack IDs
against the original count/take/reverse/drop algorithm. Leaves with a given
ID are identical in these fixtures, so observing IDs loses no tree distinction
within this test space. This is finite evidence, not general equivalence.
Missing, duplicate, and reordered references occur in the enumerated inputs.
Type-inference errors in the first test draft were fixed before the passing
run. That run repeated checked reconstruction at **10.1 s versus 11.4 s**.
Log: `/tmp/lanius-fused-link-checked-tests.log`.

The candidate remains outside production pending the all-input equivalence
proof, including failure cases. No new full benchmark was run; **408.142 s**
remains the latest full measurement.

## Installing the exactly equivalent fused linker

The all-input equivalence proof is complete. Its key steps characterize
successful consumption as a linked prefix in grammar order, reversed onto
the front of the untouched remaining stack, and show that this prefix has
exactly the count used by the previous implementation. Equality of the two
`Option` results then covers both successes and failures. Induction extends
that equality to every starting ID, node list, and initial stack, without
assuming validity. The scratch proof was developed in
`/tmp/LaniusFusedLinkEquivalence.lean`.

Production `ParseTree.linkFrom` now uses `consumeChildren`. The old
`linkChildren` implementation and count/take/reverse/drop loop live only as
private reference functions in `ParseTreeEquivalenceTests`; they are not a
second production path. The production soundness proof uses the direct
consumer invariant. Both consumer and whole-linker equivalence theorems use
only `propext` and `Quot.sound`.

Focused checks passed for `ParseTreeTests`, `ParseTreeEquivalenceTests`, and
`Reconstruction.Tests` (27 local dependencies), including all 13,640 compiled
consumer comparisons. Proof-script issues around generated match expressions
and bind association were corrected before the passing build. These changes
preserve child identity/order, leftover stack contents, and rejection behavior.

The full fresh run passed **198 program-specific modules**, the final combined
theorem, and its standard three-axiom audit in **400.414 s (6 min 40.4 s)**.
That is **7.728 s (1.9%)** less than 408.142 s. Peak RSS fell from 8.04 to
**7.69 GiB** (8,064,444 KiB). Shared infrastructure was built before timing;
all program-specific data and certificates were checked fresh. These remain
single full-run measurements rather than statistical estimates.

| Checking/elaboration family | Previous | Fused linker |
|---|---:|---:|
| Reconstruction | 75.359 s | 65.664 s |
| Origins | 57.630 s | 56.614 s |
| Parse nodes | 55.554 s | 55.298 s |

Lexer reconstruction measured 12.096 → 9.873 s; CanonicalTokens measured
17.512 → 13.849 s. The 9.695-second reconstruction-family reduction exceeds
the total reduction because other phases varied.

Full-run phases: checking/elaboration 338.558 s, imports 50.512 s, exports
8.926 s, import-cache updates 0.023 s, other overhead 2.395 s. Outer process
time was 402.005 s; the launcher reported 402.17 s. Log:
`/tmp/lanius-fused-link-full-timing.jsonl`.

## Raw-token checker experiments: order effects dominate

Two scratch experiments after the 400.414-second run did not establish a
reliable gain and were not installed.

`/tmp/LaniusRawScanUnpack.lean` unpacks the scanner's relative token once
before comparison, dropping consumed bytes, and updating the offset. It
proves exact checker equality for every source, offset, and raw-token list,
plus whole-artifact equality. The first timing pair was current 4.99 s,
candidate 4.37 s. Reversing the order gave candidate **4.78 s**, current
**4.43 s**. The initial whole-artifact proof needed a final `rfl`; the
reverse-order run passed with only `propext` and `Quot.sound` in its audits.

`/tmp/LaniusStreamingRawCheck.lean` instead decodes and checks raw-token rows
in one pass, avoiding the intermediate decoded list. It proves equality to
the original decode-then-check result for every source, offset, and token-row
list, including decode and scan failures. Its first pair was current 4.97 s,
candidate 4.37 s; after fixing the general proof's tail-decoding rewrite,
the successful reverse-order run gave candidate **4.96 s**, current **4.40 s**.
The general theorem and concrete acceptance use only `propext` and
`Quot.sound`.

In both experiments, the second theorem was faster regardless of which
algorithm ran first. This is evidence of an order effect, not an optimization;
the precise source of the effect was not measured. Future small raw-checker
changes need separate-process or controlled repeated comparisons before
adoption. The current production code remains unchanged, and **400.414 s**
remains the latest full-check measurement.

Logs: `/tmp/lanius-raw-scan-unpack.log`,
`/tmp/lanius-raw-scan-unpack-reverse.log`,
`/tmp/lanius-streaming-raw-check.log`, and
`/tmp/lanius-streaming-raw-check-reverse.log`.

## Bounded reuse of pristine import environments

Reading Lean 4.33.1's `finalizeImport` implementation identified two repeated
tasks: rebuilding constant/module maps and initializing persistent extensions.
A focused shared-only profile over 2,350 imported modules measured 94–101 ms
without extension initialization and 211–228 ms with it. Disabling extensions
is diagnostic only: elaboration requires them. Scratch:
`/tmp/LaniusImportProfile.lean`.

Many program modules have identical ordered import lists. `SurfaceBatch`
now retains up to four untouched import environments, keyed by exact `Import`
arrays including flags. Hits reuse only that dependency environment; every
module still gets a new command state and its own main-module name. The cache
never stores an environment after processing module commands. Import dependency
availability checks, fresh object generation, full-source processing checks,
and the final theorem/axiom audit remain in place. No proof algorithm changed.

`python3 formal/test-surface-batch.py` passed two focused integration tests:
separate modules with the same private helper name produce distinct values,
prior declarations do not leak on cache hits, imported syntax/macros work on
both misses and hits, and an untrusted axiom introduced on a cache-hit path is
still rejected by the final audit. Tests assert that the intended cache hits
actually occur. The cache is bounded to limit retained constant-map memory.

The full fresh run passed **198 program-specific modules** and the final
combined theorem with exactly the standard three axioms in **374.888 s
(6 min 14.9 s)**. This is **25.526 s (6.4%)** less than 400.414 s. There were
**53 import-environment cache hits**. Import setup fell from **50.512 s to
36.401 s**. Checking/elaboration also varied (338.558 → 327.464 s), so the
entire total reduction must not be attributed solely to avoided import setup.
These are single full-run observations, not statistical estimates.

Peak RSS increased from 7.69 to **8.13 GiB** (8,529,640 KiB). Full-run phases:
checking/elaboration 327.464 s, imports 36.401 s, exports 8.337 s, import-state
updates 0.024 s, other overhead 2.662 s. Outer process time was 376.523 s;
the launcher reported 376.69 s. Shared infrastructure was built beforehand,
and all program-specific outputs were checked fresh. Log:
`/tmp/lanius-import-env-cache-full-timing.jsonl`.

## Whole token certificates

Separate-process lexer profiles compared the existing header/raw/canonical
phases with a single `checkTokenArtifact` theorem. The first comparison was
0.655 + 5.040 + 2.570 = **8.265 s**, versus **6.340 s** combined. Repeating
in reverse process order gave 0.520 + 4.540 + 2.530 = **7.590 s**, versus
**6.680 s** combined. These exclude imports and use separate Lean processes
to avoid the within-process order effect observed above. All concrete
certificates passed their axiom audits. Scratch files:
`/tmp/LaniusTokenPhase{Header,Raw,Canonical,Combined}.lean`; logs:
`/tmp/lanius-token-phase-*.log` and `/tmp/lanius-token-phase-repeat-*.log`.

The eight split units now prove their existing public token theorem directly
with `kernel_rfl`. TokenScan already used a whole-token certificate and is
unchanged. This preserves the same `checkTokenArtifact = true` contract while
allowing one reduction boundary to reuse decoded input across checks. The
24 phase-only certificate files were deleted, not replaced with wrappers;
the now-unused phase predicates, composition theorem, and macros were removed.
The fresh module graph shrank from **198 to 174 modules**. The executable
`checkTokenArtifact` and its semantic soundness theorem are unchanged.

The token-decoder tests and shared checker build passed, and a source search
found no references to the retired phase APIs. Shared infrastructure was
rebuilt before the full timed check.

The full fresh check passed all **174 program-specific modules** and the
final combined theorem with exactly `propext`, `Classical.choice`, and
`Quot.sound` in **357.654 s (5 min 57.7 s)**. That is **17.234 s (4.6%)** less
than 374.888 s. Token-certificate checking fell from **55.533 to 43.507 s**;
imports fell from 36.401 to 33.686 s. Lexer token modules measured 8.850 →
6.372 s. Peak RSS was essentially unchanged at **8.13 GiB** (8,529,948 KiB).
As before, these are single full-run observations, not statistical estimates.

Full-run phases: checking/elaboration 313.276 s, imports 33.686 s, exports
8.150 s, import-state updates 0.020 s, other overhead 2.522 s. There were
37 import-environment cache hits, fewer because many of the repeated-import
phase modules were removed. Outer process time was 359.282 s; the launcher
reported 359.45 s. All remaining program-specific modules were checked fresh;
no program-specific proof was moved into the prebuilt shared set. Log:
`/tmp/lanius-whole-token-full-timing.jsonl`.

## Validating while linking: combined traversal pilot

`/tmp/LaniusValidatedLinkPilot.lean` combines postorder grammar validation and
tree linking. For each node it consumes the completed children once, derives
the validator's entries from those linked children in grammar order, checks
`ParsePostorder.node`, and pushes the resulting tree. The existing Surface
interpreter then reconstructs from that forest. This avoids maintaining two
independent postorder stacks and the validator's count/take/reverse/drop pass.

Separate-process lexer profiles measured:

| Checking work | First run | Reverse-order repeat |
|---|---:|---:|
| Existing node validation | 8.20 s | 7.52 s |
| Existing linking plus reconstruction | 9.34 s | 10.40 s |
| Sum of separate passes | 17.54 s | 17.92 s |
| Combined validation/linking/reconstruction | 14.90 s | 15.10 s |

Both reconstruction variants use raw-tree references so the interpreter is
held constant. The candidate's result equals the same quoted artifact Surface
output, and the concrete theorem uses exactly the standard three axioms.
It has **not** yet proved general soundness/equivalence or been installed.
The all-input proof must connect successful combined traversal to both the
original node-validation predicate and the original linked forest, including
child identity/order and stack invariants. A checked-reference measurement
is then needed before production adoption. The latest full check remains
**357.654 s**; no production source changed in this experiment.

Scratch measurement files: `/tmp/LaniusValidatedLink{Nodes,Reconstruction,Fused}.lean`.
Logs: `/tmp/lanius-validated-link-{Nodes,Reconstruction,Fused}.log` and
`/tmp/lanius-validated-link-repeat-{Nodes,Reconstruction,Fused}.log`.

## General proof for combined validation/linking

`/tmp/LaniusValidatedLinkProof.lean` now proves that a successful combined
traversal returns exactly the forest returned by `ParseTree.linkFrom`.
Given canonical remaining-node lookups and a valid initial forest, it also
proves the original `checkNodesFromParseView` predicate. The proof obtains
valid validator entries from `ChildrenValid` and preserves the stack
invariant through each consumed node. These are general theorems, not facts
limited to the lexer fixture.

The candidate now constructs `ParseTree.Checked` references. Its
`checkedView_sound` theorem derives both original node validity and original
surface reconstruction from one accepted combined check. Its axiom audit is
exactly `propext`, `Classical.choice`, and `Quot.sound`; the forest-result
theorem uses only `propext`. Dependent-match and bind-association proof steps
were repaired before these successful audits. Exact agreement on all failure
cases has not been proved.

Separate-process profiles of this proof-carrying path, including derivation
of both public certificates, measured **15.8 s combined versus 7.53 + 9.16 =
16.69 s separately**. The reverse-order repeat measured **15.2 s versus
8.18 + 10.2 = 18.38 s**. Peak RSS in that repeat was 5,040,352 KiB (**4.81 GiB**)
combined, versus 3,352,180 KiB for node validation and 3,812,624 KiB (**3.64 GiB**)
for reconstruction. These standalone peaks are not predictions of full-batch
memory. The combined time gain persists, but it comes with greater temporary
memory use; a full-batch memory check is required before adoption.

No production code changed in this round. The candidate is not installed,
and **357.654 s** remains the latest full-check measurement. Scratch files:
`/tmp/LaniusValidatedChecked{Nodes,Reconstruction,Combined}.lean`. Logs:
`/tmp/lanius-validated-checked-{Nodes,Reconstruction,Combined}.log` and
`/tmp/lanius-validated-checked-repeat-{Nodes,Reconstruction,Combined}.log`.

## Largest-unit check of combined traversal

The same proof-carrying prototype was measured on CanonicalTokens in three
separate, sequential Lean processes with `-M 12000` and asynchronous
elaboration disabled:

| Check | Kernel time | Peak RSS |
|---|---:|---:|
| Existing node validation | 12.7 s | 4,230,688 KiB (4.03 GiB) |
| Existing reconstruction | 12.6 s | 4,586,868 KiB (4.37 GiB) |
| Combined traversal and both derived certificates | 21.7 s | 6,433,620 KiB (6.14 GiB) |

The separate kernel times total 25.3 s, so this single comparison saves
3.6 s (14.2%) at a cost of about 1.76 GiB of additional standalone peak
memory. Both derived public certificates passed with the standard three
axioms. The result supports trying the larger-unit optimization, but does
not establish a full-batch speed or memory bound. Batch retention of prior
modules and import environments makes its memory behavior different.

The next gate is a sequential full-batch trial under the existing 12,000 MB
Lean limit. Do not increase that limit or run a second heavy job alongside
the trial to force the candidate through. The candidate remains outside
production; **357.654 s** remains the latest verified full-check time.
Scratch files: `/tmp/LaniusValidatedCanonical{Nodes,Reconstruction,Combined}.lean`.
Logs: `/tmp/lanius-validated-canonical-{Nodes,Reconstruction,Combined}.log`.

## Full combined-validation trial

The combined traversal is now integrated across all nine units. A fresh full
batch passed in **348.859 s**, versus 357.654 s previously: **8.795 s (2.46%)**
faster in this comparison. Shared infrastructure was already built; all
**174 program-specific modules** were checked fresh. Launcher wall time was
350.60 s. The final theorem's axioms remain exactly `propext`,
`Classical.choice`, and `Quot.sound`.

| Measured phase | Separate traversal | Combined traversal |
|---|---:|---:|
| Node validation plus reconstruction checking | 119.763 s | 108.439 s |
| Token checking | 43.507 s | 46.073 s |
| Origin modules, including artifact construction | 66.207 s | 68.190 s |
| All module checking | 313.276 s | 304.795 s |
| Imports | 33.686 s | 33.568 s |
| Exports | 8.150 s | 7.917 s |
| Peak RSS | 8.13 GiB | 9.55 GiB |

This is a single full-batch comparison, not a repeated-run confidence
interval. Unchanged token and origin checks were slower, so the total delta
must not be treated as a precise isolated algorithm speedup. The combined
check saves a traversal but retains more state: peak RSS increased by
1,483,132 KiB (1.41 GiB, 17.4%). The run stayed below the unchanged
12,000 MB Lean limit and ran without another heavy proof job. The integrated
candidate is retained for now; do not raise the cap to accommodate it.

`Reconstruction.Validated.checkedView_sound` derives the original node
predicate and exact original surface reconstruction from acceptance. The
public certificates retain their meaning. Reconstruction imports the view;
node proofs consume the combined certificate; assembly explicitly imports
the node proof. There are no old-signature forwarding modules. Focused
tests cover valid forests, ordering, duplicate and future references,
token/node mismatches, malformed metadata, and 1,464 small differential
inputs. General soundness does not claim equivalence on every failure case.

Proof evaluation remains the main cost: 304.795 s of the 348.859 s run.
Even eliminating imports and exports would leave roughly five minutes.
The largest individual checks are CanonicalTokens reconstruction (23.543 s),
Symbol reconstruction (20.026 s), Lexer reconstruction (15.682 s), and
RawLexer reconstruction (15.619 s). Those now include node validation.
Further work should measure repeated reduction inside these checks, rather
than infer that fewer modules or cheaper imports alone can reach seconds.

Full log: `/tmp/lanius-validated-full-timing.jsonl`.

## Combined lexer reduction profile

A fresh isolated lexer certificate using the installed combined checker
reported **15.9 s kernel checking**, versus 0.249 ms tactic execution, with
kernel diagnostics enabled. Peak RSS was 5,027,684 KiB. Diagnostics counted
310,029 `List.rec` unfolds, 32,781 tree-ID matcher unfolds, 15,050 calls to
the recursive child-consumption helper, 15,050 calls to the recursive grammar
children helper, and 6,991 node validations. These are unfold counts, not
time samples; a large count alone does not establish a bottleneck.

A scratch variant extracts each child tree's ID and node value with one
constructor match instead of two accessor calls. The first candidate's
general proof needed an explicit constructor case; it was repaired before
the successful soundness audit. The repaired candidate measured **15.5 s**
kernel time and 5,054,440 KiB peak RSS, versus **15.3 s** and 5,027,900 KiB
for the uninstrumented installed control. Both successful certificates and
the candidate's general soundness theorem use only the standard three
axioms. This comparison gives no evidence of a speedup, so the variant was
not installed. The latest full measurement remains **348.859 s**.

The counters show separate child linking, entry extraction, grammar-child
validation, and reconstruction work remains after combining the outer node
pass. Reducing one accessor is insufficient; further candidates should
target those traversals and validate the whole resulting certificate.

Scratch files: `/tmp/LaniusCombinedDiagnostics.lean`,
`/tmp/LaniusCombinedControl.lean`, `/tmp/LaniusCombinedUnpack.lean`.
Logs: `/tmp/lanius-combined-diagnostics.log`,
`/tmp/lanius-combined-control.log`, `/tmp/lanius-combined-unpack-fixed.log`.

## Proof-representation comparison

The reproducible experiment in `experiments/representation/` compares the
installed computational certificate with explicit per-node composition and
proof-producing `cbv`. All completed variants establish the same original
node predicate and exact surface-reconstruction conjunction. Common artifact
data and authenticated views are prebuilt for these isolated measurements;
this is not the full shared-only-prebuilt benchmark.

| Unit | Nodes | Current, including export | Explicit, including export | Explicit generation |
|---|---:|---:|---:|---:|
| TokenScan | 651 | 3.15 s | 17.83 s | 0.22 s |
| Digits | 2,333 | 7.09 s | Stopped at 60 s | 0.25 s |

TokenScan `cbv` also failed to finish within 60 s. The explicit TokenScan
module was 11,858,328 bytes versus 18,712 bytes for the current module;
these are compiled module sizes, not isolated proof-term sizes. Its kernel
checking increased to 4.86 s from 2.29 s, alongside 5.67 s elaboration and
additional data-definition compilation. Named-tree reconstruction alone
took 0.865 s, but the cost of establishing and composing intermediate facts
outweighed that saving. The prototype is hybrid: it generates explicit
validation/linking proofs but retains computational reconstruction.

The successful final conjunctions use exactly the standard three axioms.
A deliberately corrupted production ID was rejected by the kernel. Neither
alternative is adopted. This evidence rejects the straightforward
declaration-heavy encoding, not every possible explicit proof representation.
The latest full production measurement remains **348.859 s**. See the
experiment README for commands, memory, limits, and raw-log locations.

## Recurring certificate-production baseline

The user-facing target is compilation plus certificate emission plus checking,
with only program-independent infrastructure prebuilt. The existing pipeline
does not yet measure that target end to end: `laniusc-formal-export` is a
separate CPU producer. It invokes CPU lexing, its own chart parser, Surface
reconstruction, and Core lowering. It does not currently capture the GPU
compiler's transformations as they happen. The GPU parser exposes resident
HIR/tree readbacks, but those are not wired into this exporter.

`crates/laniusc-formal-export/src/bin/profile-extraction.rs` now measures this
producer's stages and emits JSON timing records on stderr. It writes a pack
to a caller-selected path, then separately runs the existing production
exporter and requires byte-for-byte equality. That duplicate audit is
explicitly outside `producer_total`; it is test overhead, not a required
production stage. The total includes stage-reporting overhead and file writes
but not process startup, executable building, or the equality audit. Writes
are ordinary buffered filesystem writes, not an fsync durability benchmark.

The first nine-unit run used the unoptimized debug executable:

| Stage | Seconds |
|---|---:|
| Source reads | 0.00284 |
| Lexing and token emission | 0.01091 |
| Parsing and node emission | 0.97888 |
| Surface reconstruction and emission | 0.00434 |
| Core lowering and evidence emission | 0.00526 |
| JSON serialization | 0.30339 |
| File write | 0.00803 |
| Producer total | 1.31636 |

The 7,189,442-byte result exactly matches both the production exporter and
the checked-in `Artifacts/frontend_pack.json` (`cmp` exit 0). It represents
36,507 source bytes, 43,645 parse nodes, and nine units. This is a single
debug-build observation, not a release-speed claim or a GPU compilation
measurement. The exporter includes Core evidence whereas the 348.859 s
fresh Lean benchmark ends at the Surface-data theorem; do not label their
ratio a complete verified-compiler slowdown.

Compact JSON field payloads occupy 4,638,118 bytes for parse nodes,
630,094 for raw tokens, 470,274 for Surface, and 403,984 for canonical
tokens. Parse nodes account for roughly 64.5% of the file. JSON size alone
does not establish Lean reduction cost, but it identifies the largest
representation to examine. Compressing transport bytes and then expanding
the same Lean terms would not address the measured kernel bottleneck.

Reproduce from the repository root (build time is infrastructure cost):

```bash
cargo build -j 1 -p laniusc-formal-export --bin profile-extraction
mapfile -t sources < <(jq -r '.units[].sources[0].path' formal/Lanius/Extraction/Artifacts/frontend_pack.json)
target/debug/profile-extraction /tmp/lanius-profiled-frontend-pack.json "${sources[@]}" \
  2> /tmp/lanius-cpu-producer-timing.jsonl
cmp /tmp/lanius-profiled-frontend-pack.json formal/Lanius/Extraction/Artifacts/frontend_pack.json
```

The next design question is whether a compact derivation emitted by the
compiler can be checked directly, without recreating all these redundant
node records and global indexes inside Lean. Any candidate must retain exact
source/output binding and account for evidence emission, transfer, loading,
and fresh verification. Neither this probe nor the current exporter is yet
the requested GPU-integrated certificate pipeline.
