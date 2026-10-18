# GPU compiler performance: stdlib fixes

## Startup and shader caches (2026-10-15)

A warm start creates about 570 compute pipelines from two caches. The first
is the NVIDIA driver's shader disk cache. The second is the wgpu pipeline
cache file in `LANIUS_PIPELINE_CACHE_DIR`. A cold start compiles every
pipeline and takes 70–190 s on the development laptop. A warm start takes
about 1 s.

**Driver cache, shared shard (the default).** Without a name, NVIDIA keys its
shader cache by the executable's path. Every new binary path then started
cold: pins, worktrees, renamed test binaries. Touching or rewriting a binary
in place did not invalidate its entry. laniusc now sets
`__GL_SHADER_DISK_CACHE_APP_NAME=laniusc` unless the variable is already set,
so every laniusc binary shares one shard, `laniusc<n>.bin`/`.toc`. An upgrade
compiles only the kernels that changed.

Unless one of the `__GL_SHADER_DISK_CACHE*` variables is set, the cache lives
in `<LANIUS_PIPELINE_CACHE_DIR>/nvidia`. The driver's default, `~/.cache/nvidia`,
is shared with every application and capped at 1 GiB. Once full it evicts:
one 1.6 s start took 236 s.

The daemon's ready event reports `driver_shader_cache` (`hit`, `miss`, `off`,
`not-nvidia` or `unknown`) with the pipeline creation time. With
`LANIUS_GPU_COMPILE_HOST_TIMING=1` it is also printed on stderr.

**Concurrent processes.** While one process holds `laniusc0`, the driver gives
a second concurrent process the next shard, `laniusc1`, and so on. Each
shard pays one cold start per kernel change, after which it stays warm. A
`laniusc check` run beside a daemon took 71.4 s the first time: it compiled
563 pipelines into a fresh 20 MB `laniusc1`. The next concurrent check took
0.8 s.

**Pipeline cache file only (`LANIUS_DRIVER_SHADER_CACHE=0`).** This turns the
driver cache off. It applies only when none of the four `__GL_SHADER_DISK_CACHE*`
variables is set, since laniusc never overrides the user's driver settings.
Pipelines then come from the wgpu pipeline cache file
`…_set-<kernel digest>`. The file is keyed by the kernel set, not by the
executable. When the kernel set changes, the new file is seeded from the
newest existing set file of at most 64 MiB, so only changed pipelines
compile.

laniusc also falls back to this mode by itself on a driver that ignored the
shard name before; the `nvidia-app-name-ignored` marker records that.

Each process writes the file through its own temporary file, then renames it
into place. Temporary files older than ten minutes are pruned. A start whose
pipelines were all cache hits does not rewrite the file.

Measured on 2026-10-15 (pin `89341837`, tip `d81d20d5`):

| | daemon start | `laniusc check` |
|---|---|---|
| driver cache (default) | 1.27 s | 0.84–1.02 s |
| pipeline cache file only | 1.09–1.97 s | 1.28–1.39 s |

- The set file was 39.9 MB and took 92–136 ms to read and create.
- A daemon and three checks, two of them concurrent, were all warm.
- An upgrade compiled 44 of 569 pipelines.

The driver cache stays the default because the file-only mode is slower to
start.

**The 100 MB VkPipelineCache cap.** NVIDIA's VkPipelineCache data stops
growing near 100 MB. A set file seeded from a full one never gains new
pipelines, so every start recompiled its misses (about 110 s) and saved the
same bytes. Seeds are therefore limited to 64 MiB
(`LANIUS_PIPELINE_CACHE_SEED_MAX_BYTES`). A seeded set still carries its
seed's stale pipelines forward, so a long chain of kernel changes eventually
needs a fresh set and one cold start.

## Generic trait method startup and cache identity (2026-10-11)

The Stage A direct-method integration has focused correctness evidence and no
refreshed compiler-throughput comparison. Its ordinary strict-interface test
binary exceeded an 85-second initialization watchdog. The log records about
34.137 seconds creating the parser pipeline and 19.043 seconds creating the
application-field expansion pipeline, with zero GPU-lock wait.

A hardlink of that same module-test binary, invoked under the native test's
basename, opened the same NVIDIA cache leaf as the native tests. The single
traced strict case passed in 2.812 seconds; the four-case strict group then passed
in 2.568 seconds. The binary hash is unchanged. These elapsed test times describe
a cache-identity workaround, not source-compilation throughput or a resolved
cold-start cost. The original timeout, successful runs, and file-open provenance
are retained in `tests/fixtures/stdlib_compiler_state/generic-trait-methods/`.

Later semantic replay/layout checks also used per-build hardlinks of the exact
compiler-library test binaries under that basename. Their provenance records
retain the original binary hashes; these runs do not include new driver-cache
file-open traces. Evidence is in
`tests/fixtures/stdlib_compiler_state/semantic-replay-layouts/`.

The existing large-workload and cross-compiler performance acceptance remains
open. Older measurements below belong to their recorded compiler versions.

## Implementation proof pipeline preparation (2026-10-11)

This integration has focused correctness evidence, but no refreshed large-workload
or cross-compiler performance acceptance. The measurements below concern creating
individual GPU pipelines. They are not source-compilation throughput measurements.
Native execution tests ran after pipeline preparation populated the driver cache.

The combined 32-case matcher test exceeded its 100-second preparation limit.
Splitting it by operation family preserves the same cases and sequences:

| Matcher test pipeline | SPIR-V bytes | Pipeline creation |
| --- | ---: | ---: |
| One-way matching | 79,372 | 0.801 s |
| Fixed checks with inference setup | 95,144 | 32.154 s |
| Two-sided overlap | 82,436 | 14.319 s |
| Parameter coverage | 66,296 | 0.409 s |

All four artifacts pass SPIR-V validation and the existing 512 KiB size limit.
All 32 cases pass on the physical GPU after preparation. The split concerns test
pipelines and does not establish faster production compilation.

Production proof admission was also split by proof kind while retaining a shared
pending wave and final commit gate. Individual pipeline creation measured
78.457 seconds for implementation proofs and 65.101 seconds for assumption
proofs. Those cold costs remain a performance concern; successful preparation
within separate bounded commands does not establish acceptable cold end-to-end
latency. Every recorded command completed or timed out below two minutes.

Exact artifacts, probe results, and test snapshots are under
`tests/fixtures/stdlib_compiler_state/generic-implementation-proofs/`.
The older warm results below apply to their recorded compiler versions.

## Structural receivers and native storage (2026-10-11)

The existing `stdlib_gpu_perf` harness compared the preserved sibling-method
checkpoint with the structural receiver/storage integration. Both workloads ran
baseline/current/current/baseline, with three warmups and ten measured entry
recompiles per run. Each binary used its matching shader artifacts. All eight
runs verified the emitted program's output.

| Workload | Previous checkpoint | Structural storage | Difference |
| --- | ---: | ---: | ---: |
| 32 independent trait operands | 80.098 ms | 82.189 ms | +2.6% |
| Ordinary 32-parameter program | 273.302 ms | 279.758 ms | +2.4% |

These are pooled medians of twenty samples per version. Both current run medians
exceed both baseline run medians on each workload. The small observed regressions
include the complete integration; no profile isolates an individual change's
cost. Compiler sources and each version's shader artifacts remained unchanged
during measurement.

The canonical `tools/lanius_perf.py run-lanius --preset single-file-1mb` workload
also completed twenty distinct programs in `daemon_warm_workspace` mode. Median
compiler time was **38.474 ms**, and median wall time was **41.380 ms**. All twenty
executables passed their generated output contracts. No matching preserved CLI
baseline was available for this measurement, so it does not establish the change
in 1 MB performance.

The canonical command returned an error after writing its completed result:
cataloging encountered a JSON array and raised `AttributeError`. The result and
all executable validations are preserved. The document validator now rejects
non-object inputs with `ValueError`, which the catalog records as an invalid
result; two focused host checks pass. The compilations were not rerun for this
reporting-only repair.

Evidence, commands, samples, source/shader hashes, and output checks are in
`tests/fixtures/stdlib_compiler_state/structural-native-places/`. These warm
measurements exclude controlled cold preparation and do not establish generic
graph scaling or the cross-compiler 10x target.

## Selected generic body emission (2026-10-11)

The existing `stdlib_gpu_perf` harness compared the native caller-evidence
checkpoint with the sibling-method emission change. Each workload ran
baseline/current/current/baseline, with three warmups and ten measured entry
recompiles per run. All eight runs verified the emitted executable's output.

| Workload | Previous checkpoint | Selected body emission | Difference |
| --- | ---: | ---: | ---: |
| 32 independent trait operands | 93.138 ms | 90.812 ms | -2.5% |
| Ordinary 32-parameter program | 335.532 ms | 287.863 ms | -14.2% |

These are pooled medians of 20 samples per version. Trait baseline run medians
were 96.025 and 90.482 ms, so its small difference includes baseline drift.
The ordinary comparison improved in both run pairs. The change omits unrelated
generic bodies during specialization and adds no GPU dispatch or readback fence;
these measurements do not isolate the cost of each change.

Evidence is in `tests/fixtures/stdlib_compiler_state/program-native-replay/`
under `performance-sibling-contracts` and `performance-sibling-ordinary`.
Each version uses a preserved binary and matching shaders. This comparison
precedes the behavior-preserving extraction of the private emission validator
for host fault tests. Warm timings exclude cold preparation and do not establish
the canonical 1 MB workload, generic graph scaling, or the cross-compiler 10x target.

## Native caller evidence (2026-10-11)

The existing `stdlib_gpu_perf` harness compared the immediately preceding binary
and shader set with the integrated native program gate. Each workload ran
baseline/current/current/baseline, with three warmups and ten measured entry
recompiles per run. Every run checked the emitted executable's exit and output.

| Workload | Before integration | Native program gate | Difference |
| --- | ---: | ---: | ---: |
| 32 independent trait operands | 85.926 ms | 92.649 ms | +7.8% |
| Ordinary 32-parameter program | 316.723 ms | 340.276 ms | +7.4% |

These are pooled medians of 20 samples per version. The cost includes catalog,
original-call, replay-context, and fresh-call checking where required. Its exact
distribution has not been profiled. The comparisons establish a regression on
these warm workloads; they exclude cold preparation and do not establish the
canonical 1 MB workload or the cross-compiler 10x target.

Evidence: `tests/fixtures/stdlib_compiler_state/program-native-replay/performance-*`,
with exact binary hashes, separate shader hashes, commands, per-run samples,
comparisons, and output checks. Preserved binaries and shaders remain under
`target/program-native-before` and `target/program-native-integrated`.

## Complete callable ownership (2026-10-10)

The 25-check ownership checkpoint compares the exact completed graph-interface
binary and shaders with the new binary and shaders. The existing `stdlib_gpu_perf`
harness forces entry recompilation and checks the emitted executable. Each
workload ran baseline/current/current/baseline, with three warmups and ten measured
recompiles per run. All eight executable checks pass; 3,981 frozen source files
remained unchanged.

| Workload | Previous checkpoint | Complete ownership | Difference |
| --- | ---: | ---: | ---: |
| 32 independent trait operands | 73.505 ms | 77.310 ms | +5.2% |
| Ordinary 32-parameter program | 262.403 ms | 265.510 ms | +1.2% |

These pooled medians contain 20 samples per version. Trait baseline run medians
were 75.777 and 72.069 ms; current medians were 76.964 and 77.562 ms. Ordinary
baseline medians were 257.677 and 263.626 ms; current medians were 266.481 and
265.510 ms. The observed overhead is recorded, with variation that limits causal
attribution. The change adds no GPU dispatch or readback fence; callable metadata
joins existing transfers. Warm timings exclude cold driver preparation and do
not establish the canonical 1 MB or cross-compiler 10x target.

Evidence: `tests/fixtures/stdlib_compiler_state/complete-callable-owners/`, including
verification, comparisons, binary/source/shader hashes, and runners. The first
build used a wrong relative target path and failed. One initial test assertion
incorrectly equated a function body address with the startup wrapper; the corrected
suite passes. Both attempts are preserved separately from accepted results.

## Parameter identity in shared graph operations (2026-10-10)

The 18-check graph migration uses the same preserved `stdlib_gpu_perf` Rust
binary for both versions, loading either the exact completed contract-snapshot
shaders or the new shaders. Each workload ran baseline/current/current/baseline,
with three warmups and ten measured entry rebuilds per run. All eight emitted
executable checks pass; the 3,968 frozen source files remained unchanged.

| Workload | Previous checkpoint | New graph interface | Difference |
| --- | ---: | ---: | ---: |
| 32 independent trait operands | 72.397 ms | 71.322 ms | -1.5% |
| Ordinary 32-parameter program | 380.246 ms | 265.803 ms | -30.1% |

These are pooled medians from 20 samples per version. The ordinary workload's
baseline run medians were 381.021 and 371.268 ms; current medians were 269.024 and
258.031 ms. The improvement is observed on this workload; its cause has not been
isolated to a particular shader. These warm results exclude driver preparation
and do not establish the canonical 1 MB or cross-compiler 10x target.

Initial checks timed out while creating cold pipelines. The existing per-shader
probe prepared the changed kernels in bounded commands, after which all selected
checks completed. The slow match-payload kernel took 57.5 seconds cold; historical
records show roughly 47–52 seconds, without a matched cold comparison. The first
attempt also overlapped a build that was stopped; it is excluded from accepted
verification. No source change was made to resolve these startup timeouts.

Evidence: `tests/fixtures/stdlib_compiler_state/parameter-scoped-graphs/`, including
`verification.json`, both `performance-*/comparison.json` files, frozen source
and shader hashes, preparation logs, and the verification/measurement runners.

## Owned definition and caller contracts (2026-10-10)

The existing `stdlib_gpu_perf` harness forces entry recompilation and validates
the emitted executable. Each final workload ran in baseline/current/current/
baseline order, with three warmups and ten measured recompiles per run. All eight
final executable checks pass on frozen source and shader inputs.

| Workload | Preserved baseline | Final contract reader | Difference |
| --- | ---: | ---: | ---: |
| 32 independent trait operands | 65.017 ms | 71.651 ms | +10.2% |
| Ordinary 32-parameter program | 369.476 ms | 383.376 ms | +3.8% |

The trait workload initially took 163.391 ms against 64.395 ms (+153.7%).
Reachable type metadata and operand spans now transfer in batches; predicate
facts and ranges share the existing call metadata transfer. Profiled readbacks
fell from 271 to 101, compared with 89 in the preserved baseline, over one warmup
and one measured recompile. Instrumentation changes timing, so these counts
explain synchronization cost rather than supplying latency comparisons.

The remaining trait overhead is recorded rather than treated as eliminated.
The ordinary workload's baseline run medians drifted from 359.557 to 378.080 ms;
its pooled +3.8% result does not isolate a causal slowdown. The preceding batching
version measured -0.6% on that workload. Both observations remain in the evidence.

The preserved comparison binary predates the final imported structural-edge
scheduling repair and capacity diagnostic from the borrowed-enum checkpoint;
it is not an exact immediate pre-snapshot baseline. The completed snapshot's
binary and shaders are now preserved separately for the next comparison.
The canonical 1 MB corpus and other compilers were not rerun. These measurements
do not establish the cross-compiler 10x target.

Evidence: `tests/fixtures/stdlib_compiler_state/caller-contract-snapshots/`,
including `verification.json`, `performance-final/comparison.json`,
`performance-contracts-final/comparison.json`, `profile-contracts-final/comparison.json`,
and `completed-baseline.json`. Earlier failed and intermediate results are retained.

## Retained symbolic call graphs (2026-10-10)

The existing 32-parameter entry benchmark compares the preserved implementation
export binary with the reader that retains complete symbolic call graphs. Each
version ran twice in baseline/current/current/baseline order, with three warmups
and ten entry recompiles per run. All four final ELF output checks pass.

| Measurement | Preserved baseline | Retained graphs |
| --- | ---: | ---: |
| Pooled median, 20 measured recompiles per version | 358.441 ms | 358.918 ms |
| Profiled readbacks, one warmup and one recompile | 325 | 325 |

The measured difference is **+0.13%**. The first reader introduced 76 additional
readbacks and a repeatable 10–12% slowdown. Batching parameter substitutions alone
did not help. Active declaration headers and sparse ownership metadata now share
the existing call readback batches; validated nominal identities use an owned
cache. This removes the extra synchronization while preserving ownership checks.

The paired runs use unchanged source and shader inputs. The harness forces entry
cache misses and validates the final executable from each run. These results
cover this generic workload; the canonical 1 MB corpus and other compilers were
not rerun, so this does not establish the cross-compiler 10x target.

Evidence: `tests/fixtures/stdlib_compiler_state/caller-proof-retention/`, especially
`performance-optimized/comparison.json`, `profile-final/comparison.json`, and
`optimized-sources.json`. Earlier failed attempts remain in the same directory.

## Portable implementation evidence (2026-10-10)

Both existing workloads produce correct outputs on the schema 12 implementation
export checkpoint, which passes 79 selected correctness checks.

| Existing workload | Callable predicates | Implementation evidence |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 39.160 ms | 35.083 ms |
| Canonical 1 MB wall time | 42.460 ms | 37.913 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 357.730 ms | 356.554 ms |

These sequential, unpaired observations show no measured regression on these
workloads; they do not establish a causal speedup or the cross-compiler 10x
target. Tracked storage is 1,668,354,171 bytes, up 72 bytes; allocation count is
277, up one. Dispatches remain 1,469 and compute passes 98. Five raw buffers
remain outside that accounting. There are seven new exporter kernels, for 740
total; the largest SPV remains 504,704 bytes under the unchanged size guard.

All 20 canonical ELF outputs and the generic driver's final output validate.
The canonical inputs retain the same source hashes, 1,000,000-byte sizes, and
seeds 20–39. Timed cache hits and resource creations are zero. All 3,901 recorded
source hashes and 1,480 shader payload hashes remain unchanged through measurement.

The existing runner saved its report before its catalogue `list.get` exception;
independent schema, frozen-input, and executable validation passed. Evidence:
`benchmark_artifacts/performance/stdlib-gpu-20261010-implementation-evidence/`.

## Portable callable predicates (2026-10-10)

Both existing workloads produce correct outputs on the schema 11 callable-bound
checkpoint. The correctness checkpoint passes 67 selected checks; see the
[compiler notes](compiler-generic-types.md#portable-callable-bounds-2026-10-10).

| Existing workload | Preceding sized-header checkpoint | Callable predicates |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 41.158 ms | 39.160 ms |
| Canonical 1 MB wall time | 44.419 ms | 42.460 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 359.273 ms | 357.730 ms |

These sequential, unpaired observations do not establish a causal speedup or
the cross-compiler 10x target. Tracked storage is 1,668,354,099 bytes, an increase
of 56 bytes for the enlarged dependency-page headers. Allocation count remains
276; dispatches remain 1,469 and compute passes 98. Five raw buffers remain
outside that accounting. There are three new exporter kernels, for 733 total;
the largest SPV remains 504,704 bytes under the unchanged size guard.

All 20 canonical ELF outputs and the generic driver's final output validate.
Inputs remain 1,000,000 bytes with the same source hashes and seeds 20–39.
Timed cache hits and resource creations are zero. All 3,859 recorded source
hashes and 1,466 shader payload hashes remain unchanged through measurement.
The source manifest was captured during the runner's CLI build, before timed
samples, after correcting filename decoding in the capture command.

The existing runner saved its report before its catalogue `list.get` exception;
independent schema, input, frozen-source, and executable validation passed.
Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261010-callable-predicates/`.

## Imported trait references and method contracts (2026-10-10)

Both existing workloads pass their output contracts on the verified imported-trait
snapshot. The initial implementation allocated four header words for every path,
even in units without predicates. Header capacity now follows the conservative
predicate feature gate; shader writers honor the table's logical dimensions.

| Existing workload | Previous method-results checkpoint | Initial imported traits | Sized header |
| --- | ---: | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 35.031 ms | 37.907 ms | 41.158 ms |
| Canonical 1 MB wall time | 37.736 ms | 40.924 ms | 44.419 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 354.334 ms | 367.087 ms | 359.273 ms |

These are sequential, unpaired observations. The final compiler medians are
17.5% and 1.4% above the preceding checkpoint. This does not establish a causal
regression or a speedup from the allocation change. The cross-compiler 10x target
has not been demonstrated by these runs.

Tracked storage is 1,668,354,043 bytes in 276 allocations, versus 1,670,811,643
bytes in 275 allocations for the initial imported-trait implementation. Graph
coloring changes the allocation mix: the measured reduction is 2,457,600 bytes,
although the logical header shrinks by more. The final snapshot remains 2,457,600
bytes and two allocations above the preceding checkpoint. Dispatches remain
1,469, compute passes 98, and five raw buffers are outside the accounting.

All 20 canonical ELF outputs and the generic driver's final output are correct.
Canonical inputs retain the same 1,000,000-byte source hashes and seeds 20–39;
timed cache hits and resource creations are zero. All 3,824 recorded source hashes
and 1,460 shader payload hashes stayed fixed through measurement. The existing
runner saved its report before the catalogue `list.get` exception; independent
schema, input, and executable validation passed.

Final evidence: `benchmark_artifacts/performance/stdlib-gpu-20261010-imported-traits-sized-header/`.
The initial measurement is retained separately under
`stdlib-gpu-20261010-imported-trait-resolution/`. Correctness and remaining caller
evidence work are described in the [compiler checkpoint](compiler-generic-types.md#imported-trait-references-and-method-contracts-2026-10-10).

## Late method results and logical buffer bounds (2026-10-10)

This checkpoint passes 276 selected checks. Local methods discovered during
inference retain complete result types; graph-backed GPU tables now expose their
declared byte ranges even when scratch coloring assigns a larger physical slot.
Storage reuse remains enabled. Kernel count remains 729.

| Existing workload | Trait-graph checkpoint | Current observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 36.449 ms | 35.031 ms |
| Canonical 1 MB wall time | 39.356 ms | 37.736 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 358.767 ms | 354.334 ms |

The compiler medians are 3.9% and 1.2% lower in these sequential, unpaired runs.
They do not establish a causal speedup or the cross-compiler 10x target.
All 21 output contracts pass: 20 canonical executables and the generic driver's
final executable. Canonical seeds 20–39 retain the preceding source hashes and
exact 1,000,000-byte inputs. Timed cache hits and resource creations are zero.

Dispatches remain 1,469 and compute passes 98. Tracked storage remains
1,665,896,443 bytes in 274 allocations; five raw buffers remain excluded. The
preceding checkpoint's five-allocation increase is still present; this correction
adds no further tracked storage or dispatch cost.

All 3,759 recorded source hashes and 1,458 shader payload hashes remain fixed
through measurement. Twenty-six SPVs and one reflection payload differ from the
preceding checkpoint. Shader digest is `d4d2886dfe943a93`; maximum SPV size remains
504,704 bytes under the unchanged 524,288-byte guard. The canonical runner rebuilt
the CLI without changing frozen sources or shader payloads. Binary transitions
are retained. A comment-only clarification after correctness tests is recorded
in `method-result-contract/post-test-comment-cleanup.json`.

The existing runner saved its report before the catalogue `list.get` exception.
Independent report-schema, frozen-input, and executable validation passes.
Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261010-method-results/`,
including `canonical-1mb.json`, `generic-32.log`, `checkpoint-metadata.json`,
`frozen-inputs.json`, and `validate_checkpoint.py`. See the
[compiler checkpoint](compiler-generic-types.md#late-method-results-and-logical-buffer-bounds-2026-10-10)
for correctness coverage and remaining dependencies.

## Complete trait type graphs (2026-10-10)

This checkpoint passes 176 selected checks. Trait predicates consume complete
checked graphs, method signatures compare substituted types, and concrete body
replay enforces obligations. One obsolete method comparison kernel is removed
and one body obligation kernel is added. The total remains 729 kernels.

| Existing workload | Bound-slice checkpoint | Current observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 36.380 ms | 36.449 ms |
| Canonical 1 MB wall time | 39.298 ms | 39.356 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 357.416 ms | 358.767 ms |

The compiler medians are 0.2% and 0.4% higher in these sequential, unpaired runs.
They do not establish a causal performance change, the cross-compiler 10x target,
or controlled cold-start performance.

All 21 output contracts pass: the 20 canonical executables and the generic
driver's final executable. Canonical seeds 20–39 preserve the preceding source
hashes and exact 1,000,000-byte inputs. Timed cache hits and resource creations
are zero. Dispatches fall from 1,470 to 1,469; compute passes remain 98.
Tracked storage rises from 1,638,862,651 to 1,665,896,443 bytes, and allocations
from 269 to 274. This is 27,033,792 additional bytes, about 1.65%. Five raw buffers
remain excluded. The allocation increase is retained as a measured cost; its
exact allocation ownership has not been isolated in this checkpoint.

An initial measurement exposed a lexical feature mistake: every bitwise `&`
enabled reference processing. That run recorded 1,493 dispatches. The lexer now
excludes proven binary positions, while reference-only headers keep their
required storage passes. The corrected run has 24 fewer dispatches than that
initial run, but the five extra allocations remain. The initial measurement is
retained under `initial-reference-overapproximation/` and is not the final result.

All 3,709 recorded source hashes and 1,458 shader payload hashes remain fixed
through measurement. This freeze includes a wider source inventory than the
preceding checkpoint, including benchmark helpers and repository configuration.
Fourteen SPVs and eight reflection payloads differ from the preceding checkpoint;
the deleted kernel's two payloads are absent. Shader digest is `197ba36f35fefdc5`,
with maximum SPV size 504,704 bytes under the unchanged 524,288-byte guard.
The canonical runner rebuilt the CLI without changing frozen sources or shader
payloads; before/after binary identities are retained.

The runner saved its report before the existing catalogue `list.get` exception.
Independent schema, frozen-input, and executable validation passes. Evidence:
`benchmark_artifacts/performance/stdlib-gpu-20261010-trait-type-graphs/`, including
`checkpoint-metadata.json`, both workload logs, `canonical-1mb.validation.json`,
and `validate_checkpoint.py`. Correctness evidence and remaining reproductions
are under `tests/fixtures/stdlib_compiler_state/trait-type-graphs/`.

## Bound slice arguments and enum payloads (2026-10-10)

This checkpoint passes 61 selected checks. Explicit generic slice bindings
preserve borrowing, and enum payload construction uses the full view descriptor.
An existing native pass consumes the existing checked passing-mode buffer. No
kernel, allocation, ABI, or private format is added.

| Existing workload | Qualified alias replay checkpoint | Current observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 38.887 ms | 36.380 ms |
| Canonical 1 MB wall time | 41.838 ms | 39.298 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 368.493 ms | 357.416 ms |

The compiler medians are 6.4% and 3.0% lower in these sequential, unpaired runs.
They do not establish a causal speedup, the cross-compiler 10x target, or
controlled cold-start performance.

All 21 output contracts pass: the 20 canonical executables and the generic
driver's final executable. Canonical seeds 20–39 keep the preceding source hashes
and exact 1,000,000-byte inputs. Timed cache hits and resource creations are zero.
Dispatches (1,470), compute passes (98), tracked bytes (1,638,862,651), and tracked
allocations (269) are unchanged. Five raw buffers remain outside the accounting.

All 3,268 recorded source hashes and 1,458 shader payload hashes remain fixed
through measurement. Five SPVs and two reflection payloads change. There are
729 kernels, digest `73c6324caccf98df`, and maximum SPV size 504,704 bytes under
the unchanged 524,288-byte guard.

The runner saved its report before the existing catalogue `list.get` exception.
Independent schema, frozen-input, and executable validation passes. Evidence:
`benchmark_artifacts/performance/stdlib-gpu-20261010-explicit-slice-borrow/`,
including the reports, logs, and validator. Correctness logs and reproductions
are under `tests/fixtures/stdlib_compiler_state/explicit-slice-borrow/`.

## Qualified alias body replay (2026-10-10)

This checkpoint passes 49 selected checks. The existing specialization producer
updates both anchors of a qualified type occurrence. No pass, buffer, ABI, or
private format is added.

| Existing workload | Imported member checkpoint | Current observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 37.285 ms | 38.887 ms |
| Canonical 1 MB wall time | 40.295 ms | 41.838 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 368.927 ms | 368.493 ms |

The canonical median is 4.3% higher; the 32-parameter median is essentially
unchanged. These are sequential, unpaired observations and do not isolate the
change's cost. The cross-compiler 10x target and controlled cold-start performance
were not measured.

All 21 output contracts pass: the 20 canonical executables and the generic
driver's final executable. Canonical seeds 20–39 retain the previous source
hashes and exact 1,000,000-byte inputs. Timed cache hits and resource creations
are zero. Dispatches (1,470), compute passes (98), tracked bytes (1,638,862,651),
and tracked allocations (269) are unchanged. Five raw buffers remain untracked.

All 3,253 source and 1,458 shader payload hashes remain fixed through measurement.
Only the specialization shader's SPV and reflection payload change. There are
729 kernels, digest `babd255e8a62a8c7`, and maximum SPV size 504,704 bytes under
the unchanged 524,288-byte guard.

The canonical runner saved its report before the existing catalogue `list.get`
exception. Independent schema, frozen-input, and executable validation passes.
Evidence and the reproducible validator are in
`benchmark_artifacts/performance/stdlib-gpu-20261010-qualified-alias-replay/`.
Correctness logs are in `tests/fixtures/stdlib_compiler_state/angle-close-probes/`
as `symbolic-replay-final-{generic,interface,contracts}.log`.

## Imported alias members (2026-10-10)

This checkpoint passes 68 selected checks. Qualified constructors and associated
methods consume complete normalized parents. Binding validation also runs for
concrete imported aliases with no written type arguments. Three kernels provide
member indexing, lookup, and late value metadata; the index reuses the existing
visibility workspace.

| Existing workload | Previous checkpoint | Current observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 36.424 ms | 37.285 ms |
| Canonical 1 MB wall time | 39.302 ms | 40.295 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 354.024 ms | 368.927 ms |

Compiler medians are 2.4% and 4.2% higher in these sequential, unpaired runs.
The concrete imported-alias constructor probe measures 30.500 ms; the equivalent
direct enum qualifier measures 28.902 ms. Each uses three warmups and ten forced
entry recompiles. These observations do not isolate the changes' cost. The
cross-compiler 10x target, controlled cold-start performance, and large imported
alias scaling were not measured.

All 23 output contracts pass: 20 canonical programs and the three focused
drivers' final programs. Canonical seeds 20–39 have the preceding checkpoint's
source hashes and exact 1,000,000-byte inputs. Timed unit-cache hits and resource
creations are zero. The canonical workload records 1,470 dispatches, four more
than before, and 98 compute passes. Tracked storage is unchanged at 1,638,862,651
bytes across 269 allocations; five raw buffers remain outside this accounting.

All 3,228 source and 1,458 shader payload hashes remain fixed through measurement.
There are 729 kernels; ten SPVs and six reflection payloads differ from the
preceding checkpoint. Shader digest is `99723a4571001baa`; maximum SPV remains
504,704 bytes under the unchanged 524,288-byte guard. No ABI or private format
change in this checkpoint.

The runner saved its report before the existing catalogue `list.get` exception.
Independent schema, frozen-input, and executable validation passes. Evidence:
`benchmark_artifacts/performance/stdlib-gpu-20261010-imported-members/`, including
`checkpoint-metadata.json`, `focused-member-comparison.json`, retained inputs,
logs, and the validator. Test evidence is
`tests/fixtures/stdlib_compiler_state/imported-member-final-{generic,interface,contracts}.log`.

## Imported aliases and checked export (2026-10-10)

This checkpoint passes 58 selected checks. Imported aliases materialize their
complete targets, export traverses checked types, and concrete body replay
retains the template interface. Seven obsolete export kernels are removed and
one imported-target materializer is added.

| Existing workload | Prior constructor checkpoint | Current observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 37.797 ms (repeat; first 42.050 ms) | 36.424 ms |
| Canonical 1 MB wall time | 40.699 ms (repeat; first 45.172 ms) | 39.302 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 402.744 ms | 354.024 ms |

The imported reordered-alias probe measures 22.978 ms; its equivalent direct
record type measures 23.048 ms. Both use three warmups and ten forced entry
recompiles. These sequential, unpaired observations show no slowdown in the
measured workloads; they do not isolate the changes' cost or establish a causal
speedup. The cross-compiler 10x target, controlled cold-start performance, and
large imported-alias scaling were not measured.

All 23 outputs pass exit, stdout, and stderr validation: 20 canonical programs
and the three focused drivers' final programs. Canonical seeds 20–39 preserve
the preceding source hashes and exact 1,000,000-byte inputs. Timed unit-cache hits
and resource creations are zero. The first generic-driver attempt incorrectly
requested empty stdout; it is retained separately and excluded. The accepted
run uses the preceding checkpoint's expected Unicode output file.

The canonical workload records 1,466 dispatches and 98 compute passes. Tracked
live storage is 1,638,862,651 bytes across 269 allocations, 6,144,128 fewer bytes
and one fewer allocation than the preceding checkpoint. Five raw buffers remain
outside this accounting.

All 3,220 source and 1,452 shader payload hashes remain fixed through measurement.
There are 726 kernels; nine SPVs and eight reflection payloads differ from the
preceding checkpoint. Shader digest is `d227661a00cbeb8c`; maximum SPV remains
504,704 bytes under the unchanged 524,288-byte guard. The new materializer uses
the existing complex-kernel optimization setting after its default build
exceeded the guard. No ABI or private-format change in this checkpoint.

The performance runner saved its report before the existing catalogue `list.get`
exception. Independent schema, frozen-input, and executable validation passes.
Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261010-imported-aliases/`,
including `checkpoint-metadata.json`, `focused-alias-comparison.json`, and the
retained inputs, logs, and validator. Test evidence is
`tests/fixtures/stdlib_compiler_state/checked-export-final-{generic,interface,contracts}.log`.

## Normalized alias constructors (2026-10-10)

This checkpoint passes 34 execution/rejection checks and both compiler contract
checks. Explicit call bindings use checked rows instead of repeated source-HIR
scans. A post-normalization member resolver is added; the existing call binder
produces the rows. Body replay specializes their type references and constant
arguments on generated nominal nodes. Imported generic aliases remain open.

| Existing workload | Prior alias-type checkpoint | First observation | Identical repeat |
| --- | ---: | ---: | ---: |
| Canonical 1 MB compiler, 20 programs | 36.339 ms | 42.050 ms | 37.797 ms |
| Canonical 1 MB wall time | 39.181 ms | 45.172 ms | 40.699 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 395.587 ms | 402.744 ms | — |

The first 1 MB observation was 15.7% above the preceding checkpoint; the repeat
was 4.0% above it with identical source, shader, and workload hashes. The generic
observation was 1.8% higher. These unpaired runs show variability and do not
establish either a causal regression or a speedup. A controlled comparison is
still needed to attribute the difference; the cross-compiler 10x target is not
measured here. Cold-start performance was not measured under controlled caches.

Both canonical reports pass schema validation, identical seeds 20–39 and source
hash checks, exact 1,000,000-byte inputs, and zero timed unit-cache hits/resource
creations. All 40 canonical output checks and the focused driver's final ELF
pass exact stdout, empty stderr, and exit-zero checks. Both reports are retained;
the repeat does not replace the first observation.

The canonical workload retains 1,462 dispatches and 98 compute passes. Tracked
live storage is 1,645,006,779 bytes across 270 allocations: 23,347,328 more bytes
and two more allocations than the preceding checkpoint; five raw buffers remain
excluded. Binding storage is bounded by a 16-byte descriptor and eight 8-byte
rows per source-token capacity, plus a counter. This workload does not establish
memory scaling for large imported alias graphs.

All 3,218 source and 1,464 shader payload hashes remain fixed during measurement.
There are 732 kernels; 21 current SPVs and 20 reflection payloads changed. Digest
is `50eb15902905d5b2`; maximum SPV remains 504,704 bytes under the unchanged
524,288-byte guard. ABI and private formats are unchanged. The performance tool's
existing catalogue `list.get` exception occurs after report publication;
independent report, frozen-input, and executable validation succeeds.

Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261010-alias-members/`,
including both canonical reports, their output validation, the generic log,
source/shader/binary identities, and `checkpoint-metadata.json`. Test evidence:
`tests/fixtures/stdlib_compiler_state/alias-member-final-{generic,contracts}.log`.

## Complete local alias types (2026-10-10)

The alias checkpoint passes 74 focused checks. Alias normalization now publishes
complete checked references; aggregate comparisons and constant body replay also
consume generated nodes. Stable parent binding fixes a local/imported method
identity regression. Fifteen obsolete kernels are removed and one normalizer is
added, reducing the kernel count from 745 to 731.

| Workload | Current median | Preceding field checkpoint |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 36.339 ms | 37.860 ms |
| Canonical 1 MB wall time | 39.181 ms | 40.690 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 395.587 ms | 399.658 ms |

The alias-specific measurement uses a 64-link chain that repeatedly swaps two
parameters and forwards an owned array. It measures 75.619 ms; the equivalent
program using the direct record type measures 79.767 ms. Both use three warmups
and ten forced entry recompiles, and both emitted programs pass their copy/value
checks. These sequential, unpaired measurements show the observed costs; they do
not isolate normalization cost or establish the cross-compiler 10x target.

All 23 checked outputs pass exact stdout, empty stderr, and exit-zero checks:
20 canonical ELFs and the final ELF from each of the three focused drivers.
The canonical inputs preserve seeds 20–39, prior source hashes, and exactly
1,000,000 bytes each. Timed cache hits and resource creations are zero. The
canonical workload records 1,462 dispatches, 98 compute passes, and 1,621,659,451
tracked live bytes across 268 allocations. That is 2,457,612 fewer tracked bytes
and three fewer allocations; five raw buffers remain outside this accounting.

All 3,191 source and 1,462 shader payload identities remain fixed throughout
measurement. Nineteen current SPVs and 13 reflection payloads differ from the
preceding checkpoint; 30 obsolete payload files are gone. Shader digest is
`0ae6f4d4aaa54a11`. Maximum SPV remains 504,704 bytes under the unchanged
524,288-byte guard. ABI and private formats are unchanged. Cold-start performance
and imported-alias/page scaling were not measured.

The existing performance runner saves its report before the catalogue's
`list.get` exception. Independent schema, frozen-input, and executable validation
pass. Evidence is `benchmark_artifacts/performance/stdlib-gpu-20261010-alias-types/`;
`checkpoint-metadata.json` records binary identities, workload results, and the
CLI rebuild transition. Focused test evidence is
`tests/fixtures/stdlib_compiler_state/alias-types-manifest.json`.

## Retained record fields (2026-10-10)

Field lookup, nested constructor contexts, and native field offsets now use
retained field metadata rather than dependency-page rows. All 33 selected checks
pass, including nine ordinary/local-generic/imported-generic executions across
three page layouts and six field/type rejections. The full generic inventory
was not repeated.

| Existing workload | Current median | Preceding page checkpoint |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 37.860 ms | 37.180 ms |
| Canonical 1 MB wall time | 40.690 ms | 39.961 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 399.658 ms | 401.120 ms |

The compiler observation is 1.8% higher and the generic observation 0.4% lower.
These unpaired warm runs do not isolate a causal difference or establish the
cross-compiler 10x target. All 21 emitted programs pass exact stdout, empty stderr,
and exit-zero checks. The canonical corpus retains seeds 20–39, identical source
hashes, and exact 1,000,000-byte inputs. Timed cache hits and resource creations
are zero. Its 1,462 dispatches, 98 compute passes, and 1,624,117,063 tracked live
bytes across 271 allocations remain unchanged; five raw buffers are excluded.
One bounded field-name buffer is added to imported-field storage. These live
memory observations on the canonical workload do not measure its cost for large
imported record graphs.

All 3,186 source and 1,490 shader payload identities stayed fixed. Seven SPVs and
seven reflection payloads changed from the preceding page checkpoint. There are
745 kernels, digest `7e9e66cda813d6f6`; maximum SPV is 504,704 bytes under the
unchanged 524,288-byte guard. No kernel or ABI is added. The canonical runner's
existing catalogue exception occurs after report publication; independent schema
and executable validation pass. No cold-start or multi-page scaling run was made.

Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261010-retained-fields/`,
including frozen source/shader/binary identities, the CLI rebuild transition,
both workload logs, output validation, and `checkpoint-metadata.json`. Test
selection and results are in `tests/fixtures/stdlib_compiler_state/page-fields-manifest.json`.
The initial page checkpoint below is retained as historical evidence.

## Dependency pages and retained value layouts (2026-10-10)

Checked type identities, qualifier scope, and native layout inputs survive page
replacement. Parameter-pattern readers run on the owning page, and submission
flushes deferred GPU work before page storage is reused. All 85 selected checks
pass; the three dependency-page tests also pass with compute batching disabled.
The full 287-test generic inventory was not repeated.

| Existing workload | Current median | Previous observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 37.180 ms | 37.627 ms |
| Canonical 1 MB wall time | 39.961 ms | 40.456 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 401.120 ms | 400.409 ms |

The compiler observation is about 1.2% lower and the generic observation about
0.2% higher. These unpaired warm runs do not isolate the changes' cost or establish
a cross-compiler 10x ratio. The canonical runner uses the existing
`single-file-1mb` preset, x86_64 target, and `daemon_warm_workspace` mode. The
generic driver recompiles its entry while imports remain warm. All 20 canonical
ELFs and the generic driver's final ELF pass exact stdout, empty stderr, and
exit-zero checks. Seeds 20–39 retain the prior hashes and exact 1,000,000-byte sizes.
Timed compiled-unit cache hits and resource creations are zero.

All 3,186 frozen source identities and 1,490 shader payload identities remained
unchanged through the measurements. The record includes binary hashes and the
canonical runner's CLI rebuild transition. There are 745 shaders; 18 SPVs and
15 reflection payloads changed from the preceding checkpoint. Shader digest is
`9a9322506f77915d`; the maximum SPV remains 504,704 bytes under the unchanged
524,288-byte guard. No kernel is added. The canonical workload still records
1,462 dispatches and 98 compute passes. Tracked live storage is 1,624,117,063 bytes
across 271 allocations, excluding five raw buffers: 3,686,400 bytes and three
allocations above the preceding observation. Cold-start cost and multi-page
generic scaling were not measured.

The canonical runner saved its report before the existing catalogue `list.get`
exception; independent schema and executable validation pass. The first generic
invocation mistakenly requested empty stdout. Its log is retained separately;
the accepted run uses the fixture's existing Unicode/empty-line output contract.
No source or compiler change separates those two invocations.

Evidence is in `benchmark_artifacts/performance/stdlib-gpu-20261010-dependency-pages/`:
frozen identities, `checkpoint-metadata.json`, `canonical-1mb.json`, all output
validation records, `generic-32.log`, and `validate_checkpoint.py`. Test selections
and results are in `tests/fixtures/stdlib_compiler_state/page-manifest.json`.
Private interface version 9, native object version 3, and three-word slices are
unchanged. Every command completed within two minutes. Remaining compiler work
is listed in the [generics checkpoint](compiler-generic-types.md#remaining-work).

## Qualified enum variants and method parameter rows (2026-10-10)

The compiler retains variant parent scopes and binds explicit parent applications
through existing nominal/call machinery. A source constant cache preserves lexical
identity through body replay. Source parameter rows retain implicit `self`, fixing
an argument-validation omission independently reproduced on the prior checkpoint.
There are 107 passing execution/rejection checks and two passing compiler contract
checks. The full 286-test generic inventory was not repeated.

| Existing workload | Current median | Previous observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 37.627 ms | 38.929 ms |
| Canonical 1 MB wall time | 40.456 ms | 41.521 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 400.409 ms | 399.502 ms |

The canonical observation is about 3.3% lower and the generic observation about
0.2% higher. These unpaired warm runs do not isolate a causal difference or
establish a cross-compiler 10x ratio. The canonical runner uses the existing
`single-file-1mb` preset, x86_64 target, and `daemon_warm_workspace` mode; the
32-parameter driver recompiles its entry with imports warm. All 20 canonical
ELFs and the generic driver's final ELF pass exact stdout, empty stderr, and
exit-zero checks. Canonical seeds 20–39 retain their prior hashes and exact
1,000,000-byte sizes. Timed compiled-unit cache hits and resource creations are
zero. The runner saved its report before the existing catalogue `list.get`
exception; independent schema and executable validation passed.

All 3,173 frozen source identities and 1,490 shader payload identities stayed
unchanged through the final gate and measurements. Actual binary hashes and the
CLI rebuild transition are recorded. There are 745 shaders; 24 SPVs and 16
reflection payloads changed. Digest: `dd4f54922ea6dabe`. The maximum SPV remains
504,704 bytes under the enforced 524,288-byte guard; the expanded unit consumer
is 489,152 bytes. No kernel was added. The new qualifier column costs one u32
per path-capacity row. The canonical workload retains 1,462 dispatches and 98
compute passes, with 1,620,430,663 tracked live bytes across 268 allocations,
excluding five raw buffers. This is 1,228,928 bytes above the preceding observation.
No paired cold-start measurement was performed.

Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261010-qualified-variants/`,
including `checkpoint-metadata.json`, frozen source/shader/binary identities,
`canonical-1mb.json`, executable validation records, and `generic-32.log`.
Focused test logs are under `tests/fixtures/stdlib_compiler_state/variant-ownership-*`.
Private interface version 9, native object version 3, and the three-word slice
ABI are unchanged. Every command completed within two minutes.

## Imported and local unit values (2026-10-10)

Local/imported bare unit values share complete checked type publication.
Nongeneric imported annotations become zero-operand nominal applications.
The existing unit consumer runs for imported-only jobs as well as local enums;
no kernel or buffer is added. Parser angle candidates now retain statement and
container ownership. Eighty execution/rejection tests, six parser checks, and
both resource/lowering contract checks pass; the full 278-test generic inventory
was not repeated.

| Existing workload | Current median | Previous observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 38.929 ms | 37.408 ms |
| Canonical 1 MB wall time | 41.521 ms | 40.334 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 399.502 ms | 399.528 ms |

The canonical compiler observation is about 4.1% higher; the generic observation
is effectively unchanged. These unpaired runs do not isolate a speed difference
or establish a cross-compiler 10x ratio. All 20 canonical ELFs and the generic
driver's final ELF pass exact output, empty stderr, and exit-zero checks.
Canonical seeds 20–39 retain their prior hashes and exact 1,000,000-byte sizes.
Timed compiled-unit cache hits and resource creations are zero. The canonical
runner saves its report before encountering the existing catalogue `list.get`
exception; independent schema and executable validation both pass.

All 3,173 frozen source identities and 1,490 SPV/reflection identities remain
unchanged through the final runtime gate and measurements. The record includes
the CLI rebuild transition and hashes of the actual executed test binaries.
There are 745 shader artifacts; nine SPVs and five reflection payloads change
from the preceding checkpoint. The digest is `8f4a50fa1a32eb07`; the maximum SPV
remains 504,704 bytes under the enforced 524,288-byte guard.

An initial duplicated call to the complete unit reader exceeded the guard at
731,304 bytes. Both value paths now use one call site, producing 373,836 bytes
without an optimization exemption. The delimiter ownership check uses one joint
search of existing hierarchies. Token classification is 152,092 bytes and bracket
classification is 392,748 bytes. No additional kernel or buffer is introduced.
The canonical workload retains 1,462 dispatches and 98 compute passes. Tracked
live GPU storage is 1,619,201,735 bytes across 268 allocations, excluding five
raw buffers—1,228,800 bytes less than the prior observation.

**Cold startup remains costly.** Two initial 35-second test runs timed out.
A bounded timing run then completed and executed the comparison program; the
final parser gate measured 31.569 seconds creating token classification and
1.062 seconds creating bracket classification. There is no paired pre-change
cold baseline. Warm benchmark medians do not establish cold-start performance.
An accidentally selected older parser test binary was stopped; the final gate
uses the newly built executable identified in the metadata.

Private interface version 9, native object format version 3, and the three-word
slice ABI are unchanged. Every command finishes within two minutes. Evidence:
`benchmark_artifacts/performance/stdlib-gpu-20261010-unit-values/`, including
`frozen-inputs.json`, `source-delta.json`, `checkpoint-metadata.json`,
`canonical-1mb.json`, `canonical-1mb.validation.json`, validation logs, and
`generic-32.log`. Test and timing evidence is under
`tests/fixtures/stdlib_compiler_state/unit-values-*`.

## Inference from record fields (2026-10-09)

Local/imported record literals infer complete applications from named fields
through the shared type/constant matchers and materializer. Parameter contexts
are published and indexed before field inference. The existing closed-type
indexer runs once more per relevant inference round; no new kernel or binding
buffer is introduced. Seventy-nine distinct execution/rejection tests and both
resource/lowering contract checks pass. The full 272-test inventory was not
repeated.

| Existing workload | Current median | Previous observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 37.408 ms | 37.564 ms |
| Canonical 1 MB wall time | 40.334 ms | 40.179 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 399.528 ms | 398.680 ms |

These unpaired warm measurements are close; they do not establish a precise
speed difference or a cross-compiler 10x ratio. All 20 canonical ELFs and the
generic driver's final ELF pass exact stdout, empty stderr, and exit-zero
checks. Canonical seeds 20–39 retain their prior hashes and exact 1,000,000-byte
sizes. Timed compiled-unit cache hits and resource creations are zero. The
canonical runner saves its report, then encounters the existing catalogue
`list.get` exception; independent schema and executable validation pass.

All 3,164 frozen source identities remain unchanged through the final gate and
measurements; all 1,490 SPV/reflection identities remain unchanged through the
measurements. Metadata records the CLI rebuild
transition and identifies inherited parser/export binaries that were not run
at this checkpoint. Five SPVs and three reflection payloads change from the
preceding checkpoint; the shader digest is `474eb3bef5b2d2d3`, with 745 artifacts.
The record-context kernel uses the existing minimum-optimization policy and is
188,756 bytes. The maximum SPV remains 504,704 bytes under the enforced
524,288-byte guard.

The canonical workload retains 1,462 dispatches and 98 compute passes; the
additional indexing applies to jobs requiring record inference. Tracked live
GPU storage remains 1,620,430,535 bytes across 268 allocations, excluding five
raw buffers. Private semantic-interface version 9 and native object version 3
are unchanged by this follow-up. Every command finishes within two minutes.

Cold startup is separate evidence. The initial probe timed out after 30 seconds;
the next traced command completed under its 90-second bound and executed the
program. That trace records 23.153 seconds creating the field-expansion pipeline,
4.658 seconds for the shared materializer, and 2.096 seconds for record contexts.
It predates the final scheduling/diagnostic adjustments and has no paired cold
baseline. The warm medians above do not establish cold-start performance.

Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261009-record-field-inference/`,
including `frozen-inputs.json`, `source-delta.json`, `checkpoint-metadata.json`,
`canonical-1mb.json`, `canonical-1mb.validation.json`, validation logs, and
`generic-32.log`. Runtime and cold-trace evidence is under
`tests/fixtures/stdlib_compiler_state/record-inference-*`.

## Constructor signatures and unit values (2026-10-09)

Local/imported constructors now share callable signatures and inference. The
separate enum payload validator is removed; the existing unit-value resolver
participates in inference and finalization. Seventy distinct execution/rejection
tests, eight interface exports, five parser checks, and six contract/serialization
checks pass. The earlier full execution matrix was not repeated.

| Existing workload | Current median | Previous observation |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 37.564 ms | 37.490 ms |
| Canonical 1 MB wall time | 40.179 ms | 40.159 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 398.680 ms | 385.116 ms |

The generic observation is about 3.5% higher. These unpaired runs do not isolate
that difference or establish unchanged performance or a cross-compiler 10x ratio.
All 20 canonical ELFs and the generic driver's final ELF pass exact stdout, empty
stderr, and exit-zero checks. Canonical seeds 20–39 retain their prior hashes and
exact 1,000,000-byte sizes. Timed compiled-unit cache hits and resource creations
are zero. The canonical runner saves its report, then encounters the existing
catalogue `list.get` exception; independent schema and executable validation pass.

All 3,161 frozen source identities and 1,490 SPV/reflection identities remain
unchanged through the measurements. The record includes the CLI rebuild binary
transition. There are 745 shader artifacts, one fewer than before; 31 SPVs and
21 reflection payloads change. The shader digest is `df624332f7d66f64`. The maximum
SPV remains 504,704 bytes under the enforced 524,288-byte guard.

The canonical workload records the same 1,462 dispatches and 98 compute passes.
Tracked live GPU storage is 1,620,430,535 bytes across 268 allocations, excluding
five raw buffers: 1,228,800 bytes more than the prior observation. Removed kernels
and changed resource lifetimes do not imply lower retained memory. The private
interface export workspace also has room for complete nominal declaration
signatures; that format is now version 9. Every command finishes within two minutes.

Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261009-constructor-signatures/`,
including `frozen-inputs.json`, `source-delta.json`, `checkpoint-metadata.json`,
`canonical-1mb.json`, `canonical-1mb.validation.json`, validation logs, and
`generic-32.log`. Runtime evidence is in
`tests/fixtures/stdlib_compiler_state/constructor-signatures-manifest.json`.

## Nominal declaration identity (2026-10-09)

Bare records/enums now use declaration-owned zero-argument nodes in the checked
graph, and unit-variant arguments consume their complete checked references.
Seven focused execution/rejection tests, 58 affected runtime controls, all eight
interface-export checks, and both compiler contract checks pass. The earlier
full runtime matrix was not repeated.

| Existing workload | Current median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 37.490 ms |
| Canonical 1 MB wall time | 40.159 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 385.116 ms |

The preceding observations were 38.719 ms and 370.521 ms. These unpaired runs
do not isolate the cost of normalization or establish performance preservation
or a cross-compiler 10x ratio. All 20 canonical ELFs and the generic driver's
final ELF pass exact stdout, empty stderr, and exit-zero checks. Canonical seeds
20–39 retain their previous source hashes and exact 1,000,000-byte sizes.
Timed compiled-unit cache hits and resource creations are zero. Independent
schema and executable validation pass after the canonical runner saves its
report and encounters the existing catalogue `list.get` exception.

All 3,146 frozen source identities and 1,492 SPV/reflection identities remain
unchanged through measurement. The metadata retains the CLI rebuild transition
and measured binary identities. This follow-up changes six shader sources,
seven SPVs, and four reflection payloads. Production Rust is unchanged. It adds
no kernel, dispatch, or buffer; the existing nominal collection pass owns the
bare declaration nodes. Tracked live bytes remain 1,619,201,735, excluding five
raw buffers. Shader digest is `bf93973a0a13b92e`, with 746 artifacts. The maximum
SPV remains 504,704 bytes under the enforced 524,288-byte guard. Every command
completed within two minutes.

Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261009-nominal-identities/`,
including `frozen-inputs.json`, `source-delta.json`, `checkpoint-metadata.json`,
`canonical-1mb.json`, `canonical-1mb.validation.json`, validation logs, and
`generic-32.log`.

## Local enum and nominal contracts (2026-10-09)

The local enum receiving-context, match-array role, and bare nominal layout
contracts pass six focused execution/rejection tests, 38 affected runtime
controls, twelve parser checks, and both compiler contract checks. The earlier
full runtime matrix was not repeated.

| Existing workload | Current median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 38.719 ms |
| Canonical 1 MB wall time | 41.483 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 370.521 ms |

The preceding observations were 38.247 ms and 389.031 ms. These are unpaired
measurements; they do not establish performance preservation or a cross-compiler
10x ratio. All 20 canonical ELFs and the generic driver's final ELF pass exact
stdout, empty stderr, and exit-zero checks. Canonical seeds 20–39 have unchanged
source hashes and exact 1,000,000-byte sizes. Timed compiled-unit cache hits and
resource creations are zero. The canonical runner saves the report, then fails
in the existing catalogue `list.get` call. Independent schema and executable
validation pass.

All 3,141 frozen source identities and 1,492 SPV/reflection identities remain
unchanged through measurement. This source inventory additionally includes the
Cargo manifests and retained reduction inputs. The metadata records the final
CPU-test build and canonical CLI rebuild transitions, plus measured binary
identities. Tracked live bytes remain 1,619,201,735, excluding five raw buffers.

Eight SPVs and three reflection payloads change from the composition checkpoint.
Local enum inference reuses its existing consumer kernel and buffers, adding a
dispatch within each required inference round. The array-index artifact now uses
the existing minimum-optimization policy for complex shaders; its SPV is
125,064 bytes. The guard is still enforced at 524,288 bytes, and the largest
artifact is 504,704 bytes. Shader digest is `bec80d63e6e5f5b0`, with 746 artifacts.
The shared nominal layout walker has one call site; pipeline creation measured
2.714 seconds in the retained focused trace, after removing a duplicated walker.
Every command stayed below two minutes.

Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261009-local-enum-contracts/`,
including `frozen-inputs.json`, `source-delta.json`, `checkpoint-metadata.json`,
`canonical-1mb.json`, `canonical-1mb.validation.json`, validation logs, and
`generic-32.log`.

## Composition contracts (2026-10-09)

Qualified generic array elements, symbolic imported constructor wrappers, and
direct borrowed-method arguments now use complete checked types. Five new
execution/rejection tests, 35 affected controls, eleven parser checks, and both
compiler contract checks pass. The earlier full execution gate was not repeated.

| Existing workload | Current median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 38.247 ms |
| Canonical 1 MB wall time | 40.918 ms |
| 32-parameter entry, 3 warmups and 10 recompiles | 389.031 ms |

The preceding measurements were 45.824 ms and 414.383 ms. These are unpaired
observations; they do not establish performance preservation or a cross-compiler
10x ratio. All 20 canonical ELFs and the generic driver's final ELF pass exact
stdout, empty stderr, and exit-zero checks. Canonical seeds 20–39 retain their
previous source hashes and exact 1,000,000-byte sizes. Timed compiled-unit cache
hits and resource creations are zero.

All 3,098 frozen source identities and 1,492 SPV/reflection identities remain
unchanged through measurement. The canonical runner rebuilt the CLI before
starting its samples; the metadata retains its before/after hashes and the
measured binaries. The runner saved its report before the existing catalogue
`list.get` exception. Independent schema and executable validation pass.

Three production shader sources and four SPVs changed from the preceding
checkpoint. Reflection layouts and production Rust sources are unchanged.
Tracked live bytes remain 1,619,201,735, excluding five raw buffers. Shader digest
is `5692d9103b166159`; the maximum SPV is 522,440 bytes under the enforced
524,288-byte guard. Commands completed within two minutes.

Evidence: `benchmark_artifacts/performance/stdlib-gpu-20261009-composition-contracts/`,
including `frozen-inputs.json`, `checkpoint-metadata.json`, `canonical-1mb.json`,
`canonical-1mb.validation.json`, validation logs, and `generic-32.log`.

## Assignment result contexts (2026-10-09)

The shared receiving-context resolver now handles assignment destinations,
including fields and indexed elements. Duplicate imported-result validation and
the separate array-only assignment helper are removed. Three focused tests,
29 affected controls, and two resource/semantic-lowering contract checks pass.
The earlier full execution gate was not repeated.

| Workload | Current median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 45.824 ms |
| Canonical 1 MB wall time | 48.772 ms |
| Existing 32-parameter entry, 3 warmups and 10 recompiles | 414.383 ms |

The preceding canonical measurement was 46.696 ms; the last generic measurement
was 384.358 ms. These are unpaired observations. The slower generic result
remains a performance concern; neither performance preservation nor a current
cross-compiler 10x ratio is established.

The existing `single-file-1mb` preset uses x86_64 and `daemon_warm_workspace`.
Seeds 20–39 retain the preceding source hashes and exact 1,000,000-byte sizes.
All 20 emitted ELFs and the generic driver's final ELF pass exact output and
exit checks. Schema validation passes. Timed compiled-unit cache hits and
resource creations are zero. The canonical runner again saves its report
before the existing catalogue `list.get` exception; it does not exit successfully.

All 3,096 frozen source identities and 1,492 SPV/reflection payload identities
remain unchanged through measurement. This expanded source inventory includes
`sample_programs`. Tracked live bytes remain 1,619,201,735, excluding five raw
buffers. Shader digest is `caaa3abf58dc0753`, with 746 artifacts. Maximum SPV is
522,440 bytes in `semantic/artifact/01b_array_index_refs`, below the enforced
524,288-byte guard. All commands stay below two minutes.

Evidence is in `benchmark_artifacts/performance/stdlib-gpu-20261009-assignment-contexts/`:
`frozen-inputs.json`, `checkpoint-metadata.json`, `canonical-1mb.json`,
`canonical-1mb.validation.json`, `canonical-validation.log`, `canonical-run.log`,
and `generic-32.log`.

## Slice body closure follow-up (2026-10-09)

The subsequent fix removes a body-eligibility exception for symbolic slice
types. Three focused and 32 affected execution checks pass. It changes one
production shader source and its SPV; reflection layouts and production Rust
sources are unchanged. The previous complete 246-test gate was not rerun.

The existing 32-parameter driver measures **384.358 ms**, with three warmups,
ten entry recompiles, and a successful exact-output check. The preceding
measurement was 414.562 ms; the earlier caller-reference baseline was 373.936 ms.
These unpaired observations do not establish performance preservation. The 1 MB
measurement below predates this one-shader correction and was not repeated.

Shader digest is `5332457d5170a876`. Maximum SPV is still 504,704 bytes under the
enforced 524,288-byte guard. Source/payload differences and verification scope
are retained in `tests/fixtures/stdlib_compiler_state/slice-body-closure-checkpoint.json`;
the performance log is `slice-body-closure-generic-32.log` in the artifact directory
below.

## Slice stride and explicit dotted methods (2026-10-09)

This checkpoint includes explicit dotted-method binding and the authorized
three-word native slice ABI. All 246 execution/rejection checks pass, including
both original array-borrow failures, with no exclusions. All 25 contract checks
and eight GPU interface-export checks pass.

| Workload | Preceding measurement | Current measurement |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 37.587 ms | 46.696 ms |
| Canonical 1 MB wall time | 40.365 ms | 49.474 ms |
| Existing 32-parameter entry, 3 warmups and 10 recompiles | 373.936 ms | 414.562 ms |

The compiler medians are 24.2% and 10.9% higher. These are unpaired runs; the
measurements do not isolate the cost of either change. Performance preservation
and a current cross-compiler 10x ratio are not established.

The canonical runner uses the existing `single-file-1mb` preset, x86_64, and
`daemon_warm_workspace`. Seeds 20–39 have the same source hashes as the preceding
checkpoint, with exactly 1,000,000 bytes each. All 20 emitted programs pass exact
stdout, empty stderr, and exit checks. Report-schema validation passes. Every
timed job has zero compiled-unit cache hits and zero resource creations. The
runner saves the report before the existing catalogue `list.get` exception;
the runner's exit is not successful. The generic driver's final ELF also passes
its exact output check.

All 2,984 frozen source identities and 1,492 SPV/reflection payload identities
remain unchanged through measurement. The canonical CLI rebuild's dependency
fingerprint transition is retained separately. Tracked live bytes are
1,619,201,735, up 16,372 bytes, with five raw buffers excluded. The shader digest
is `3575f9b83b5465e4`, with 746 artifacts. Maximum SPV size is 504,704 bytes;
the 524,288-byte guard remains enforced. Every command stays below two minutes.

Evidence is in `benchmark_artifacts/performance/stdlib-gpu-20261009-slice-stride/`:
`frozen-inputs.json`, `binary-identities-{before,measured}.json`,
`checkpoint-metadata.json`, `canonical-1mb.json`, `canonical-validation.log`,
`canonical-1mb.validation.json`, `canonical-run.log`, and `generic-32.log`.

## Caller-reference retention (2026-10-09)

Validated caller-side applications retain their checked references without
another structural lookup or duplicate allocation. Field traversal stops once
it finds an already visited instance. Full graph validation and structural
comparison for different instances remain in place.

| Workload | Before | After |
| --- | ---: | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 38.062 ms | 37.587 ms |
| Canonical 1 MB wall time | 40.811 ms | 40.365 ms |
| Existing 32-parameter entry, 3 warmups and 10 recompiles | 406.174 ms | 373.936 ms |

The generic median is 7.9% lower in this sequential comparison. It remains above
the earlier unpaired 289.685–326.879 ms observations, so these results do not
establish preserved performance or a cross-compiler speed ratio.

The existing canonical runner and generic driver use the same inputs and modes
as the baseline below. All 20 canonical ELFs and the generic ELF execute with
exact expected output. Schema validation passes; canonical source hashes match
the baseline, each source is exactly 1,000,000 bytes, and timed cache hits and
resource creations are zero. The canonical runner again saves its report before
the existing catalogue `list.get` exception; its exit is not successful.

All 239 selected execution/rejection checks pass, with the two unresolved borrow
tests excluded. Eight GPU interface-export checks also pass. Two source files
and five SPV payloads differ from the baseline; reflection layouts and host
contracts are unchanged. All 2,980 frozen source identities and 1,492 shader
payload identities remain unchanged through measurement. The CLI rebuild's
dependency-fingerprint transition is recorded separately.

Tracked live bytes remain 1,619,185,363, excluding five raw buffers. The shader
digest is `20909c5e2a13e561`, with 746 artifacts and maximum 522,460 bytes under
the enforced 524,288-byte guard. Every command stays below two minutes.

Evidence is in `benchmark_artifacts/performance/stdlib-gpu-20261009-retain-caller/`:
`frozen-inputs.json`, `checkpoint-metadata.json`, `canonical-1mb.json`,
`canonical-validation.log`, `canonical-1mb.validation.json`, `canonical-run.log`,
and `generic-32.log`. Execution partitions and logs are the
`mixed-nominal-constant-optimized-*` files under `tests/fixtures/stdlib_compiler_state/`.

## Mixed nominal constants baseline (2026-10-09)

The [verified compiler baseline](compiler-generic-types.md#mixed-nominal-constants-verified-baseline-2026-10-09)
passes 239 selected execution/rejection checks, 25 interface/specialization/layout
contract checks, and eight GPU interface-export checks. The two parked inline-array
borrow cases were excluded and remain unresolved. The optimized checkpoint above
supersedes this measured baseline.

| Workload | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 38.062 ms |
| Canonical 1 MB wall time | 40.811 ms |
| Existing 32-parameter entry, 3 warmups and 10 recompiles | 406.174 ms |

The canonical measurement uses the existing `tools/lanius_perf.py`
`single-file-1mb` preset, x86_64, and `daemon_warm_workspace`. Seeds 20–39 match
the previous checkpoint's source hashes and the exact 1,000,000-byte manifests.
Every timed job has zero compiled-unit cache hits and zero resource creations.
All 20 emitted ELFs execute with exact stdout, empty stderr, and exit zero; schema
validation also passes. The runner saves its report before its existing catalogue
`list.get` exception. This exception is not a successful runner exit.

The generic entry uses `examples/stdlib_gpu_perf.rs`, with entry invalidation
outside the timer. Its final ELF also executes with exact expected output.
Compared with the previous unpaired observations, the canonical compiler median
falls from 47.642 ms, while the generic median rises from 289.685–326.879 ms.
These measurements do not establish performance preservation or a cross-compiler
10x ratio.

An instrumented one-warmup/two-sample run sees 16 inference closures, each ending
after two rounds. In a representative specialization, application field expansion
takes about 10 ms on each of three invocations. This identifies substantial
repeated work; instrumented elapsed times are not the table's benchmark samples.

Tracked live allocations total 1,619,185,363 bytes, 34,472,100 bytes above the
previous measured checkpoint; five raw buffers with unavailable sizes remain
excluded. The enforced 524,288-byte shader guard reports 746 artifacts, maximum
522,460 bytes, digest `ba0b6d2c9424987f`. All 2,980 selected source identities and
1,492 SPV/reflection payloads remain unchanged through measurement. The canonical
runner rebuilds the CLI with a different dependency fingerprint; its before and
measured binary hashes are retained separately. Commands stay below two minutes.

Evidence is in `benchmark_artifacts/performance/stdlib-gpu-20261009-nominal-constants/`:

- `frozen-inputs.json` and `checkpoint-metadata.json`: identities and verified measurements.
- `canonical-1mb.json`, `canonical-validation.log`, and `canonical-1mb.validation.json`: canonical samples, schema validation, and executable checks.
- `canonical-run.log`: retained runner exception after report publication.
- `generic-32.log` and `generic-32-profile.log`: ordinary measurements and separate diagnostic profile.

## Previous unmeasured explicit integer constants checkpoint

The preceding explicit integer constant checkpoint reports 229 passes and the same
two inline-array borrow failures across 231 tests. Four disjoint commands cover
every test once in 126.68 seconds combined; eight parser checks, eight GPU interface
export tests, and both layout/resource checks pass. Test elapsed times are
verification evidence, not compiler benchmarks.

Literal and scoped parameter operands feed the shared checked call environment;
consumed constant dependencies also survive scalar-only generic body replay.
Two private HIR-indexed columns add `8 * hir_rows` bytes. No kernel, dispatch, or
uniform allocation is added at this checkpoint. Existing lookup uniforms retain
the producer's logical capacity when physical buffers are reused. Private argument
records remain twenty bytes; the two appended grammar productions preserve the
previous 290 IDs. This is a static storage description, not a live allocation or
throughput measurement.

The enforced shader guard reports 744 artifacts, maximum 522,460 bytes, digest
`c29c4c43ee7e4d4c`. Compared with the preceding explicit type binding build, 26 SPV
and 20 reflection payloads change, with no added kernel; the largest x86 emitter
is byte-identical. Identities and results are recorded in
`explicit-constant-arguments-checkpoint.json`. No new throughput or allocation
benchmark was run. Performance preservation and the cross-compiler 10x ratio
remain unestablished. The latest measured 1 MB checkpoint, described below, is
still 47.642 ms.

### Preceding untimed explicit type binding checkpoint

The newest explicit type binding checkpoint reports 219 passes and the same two
borrow failures across 221 tests. Ten new tests pass in 11.25 seconds; 211 existing
controls report 209 passes and two failures in 99.44 seconds in a separate command.
Seven parser tests, eight GPU interface export tests, and both layout/resource
checks pass. These elapsed times are verification evidence, not compiler benchmarks.

Explicit local/imported function and associated-method types feed an immutable
checked environment shared with inference and final specialization retention.
One binding kernel reuses the existing twelve-byte indirect dispatch packet.
Four private workspace columns add `12 * token_rows + 4 * hir_rows` bytes; aliases
read existing parser/type buffers. Method receiver collectors now consume complete
checked rows, and obsolete whole-path reconstruction is removed. This is a static
storage description, not a measurement of live allocations or throughput.

The enforced shader guard reports 744 artifacts, maximum 522,460 bytes, digest
`2f16e4bdb9af9789`. Compared with the segmented-application build, 14 SPV and 15
reflection payloads change, including the new binding kernel; the largest x86
emitter is byte-identical. Identities and results are recorded in
`explicit-call-binding-checkpoint.json`. No new throughput or allocation benchmark
was run. Performance preservation and the cross-compiler 10x ratio remain
unestablished. The latest measured 1 MB checkpoint, described below, is still
47.642 ms.

### Preceding untimed metadata checkpoints

The preceding segmented-application checkpoint reports 210 passes and the same two
borrow failures out of 212 tests (102.92 seconds). Seven parser tests, eight GPU
interface export tests, and layout/resource checks pass. Segment lists now allocate
contiguous ranges independently of nested semantic row order. One final admission
kernel rejects explicit callable headers until checked binding exists; a twelve-byte
packet derives its dispatch from actual parser argument counts and disables work
for empty families. The private argument record grows from sixteen to twenty bytes,
with two raw list seed columns and one retained token-indexed range.

These changes have no throughput or allocation measurements. Test elapsed times
are not compiler benchmarks. The guard reports 743 artifacts, maximum 522,460 bytes,
digest `60429062696446f0`; the largest x86 emitter is byte-identical to the preceding
ordered-header build. Its 23 changed SPV and 23 changed reflection payloads are
recorded in `segmented-generic-applications-checkpoint.json`. Performance
preservation and the cross-compiler 10x ratio remain unestablished.

The preceding imported-requirement and ordered-parameter changes report 209 passes
and the same two borrowing failures out of 211 tests. The latest gate takes
109.03 seconds. The resource check, eight GPU interface export tests, and ten
transport/validation tests pass. Version 7 member metadata retains source order
independently of binding slots, with twelve words per member and shared layout
constants. No dispatch was added. These changes have no throughput measurements;
the figures below describe the preceding measured method-result build.

The first export test process hit its 60-second timeout. A timing-enabled retry
passed in 4.93 seconds and the full export suite subsequently passed within the
normal timeout in 2.28 seconds. This does not measure compiler throughput or
establish the first timeout's cause. The enforced shader guard still reports
742 artifacts and a 522,460-byte maximum; the largest x86 emitter is byte-identical
to the previous checkpoint. Performance preservation remains unproven.

## Latest measured method result ownership checkpoint (2026-10-04)

The full execution gate reports 208 passes and two retained inline-array borrowing
failures out of 210 tests. Seven structural receiver tests and the type-checker
resource check pass. Shared accepted call environments now own method result
substitution; competing shallow return projections and the unused argument-hash
buffer/dispatch are removed. This checkpoint includes the preceding structural
receiver changes, which were not measured separately.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 47.642 ms |
| Canonical 1 MB wall | 51.741 ms |
| Existing generic 32-parameter entry, first 10 samples | 326.879 ms |
| Same entry/build, repeat 10 samples | 289.685 ms |
| New local 32-parameter structural receiver, 10 samples | 517.477 ms |
| New imported structural receiver, 10 samples | 390.165 ms |

The existing `tools/lanius_perf.py` `single-file-1mb` preset uses seeds 20–39 in
`daemon_warm_workspace` mode. All 20 source hashes match their manifests and the
preceding frozen source identities. Timed cache hits and resource creations are
zero. Schema validation passes. All 20 emitted ELFs run with exact stdout, empty
stderr, and exit zero. The runner saves its report before the existing catalogue
`list.get` exception; the saved report and artifacts were independently validated.

The generic drivers use three warmups and ten entry recompiles with invalidation
outside the clock. Every final ELF passes exact output checks. Both existing-entry
runs are retained: their difference establishes timing variability on the same
build, not a cause. Compared with the preceding unpaired checkpoint, canonical
compiler time is 9.1% higher and generic entry time is 7–21% higher. Performance
preservation, causal attribution, and a cross-compiler 10x ratio are not
established. The new receiver cases have no preceding baseline. An instrumented
one-warmup/two-sample profile observes 16 call-inference closures, each converging
in two rounds; it does not isolate the timing difference. Wider scaling remains
unfinished.

Tracked live allocations are 1,584,713,263 bytes, up 8,601,648; five raw buffers
with unavailable sizes remain excluded. The enforced 524,288-byte guard records
742 artifacts, maximum 522,460 bytes, digest `68fa380c21cd0c29`. All 1,725 source
identities, three focused binaries, and 1,484 SPV/reflection hashes remain unchanged
through measurement. The canonical runner rebuilds the CLI with a different Cargo
dependency fingerprint; its actual measured SHA and transition are recorded and
validated separately. Sources were frozen while commands ran; commands stayed
below two minutes.

Evidence is retained under
`benchmark_artifacts/performance/stdlib-gpu-20261004-receiver-return-owner/`,
including `canonical-1mb.json`, both `generic-32*.log` runs, receiver logs,
`generic-32-profile.log`, `canonical-cli-build-transition.json`,
`checkpoint-metadata.json`, and `canonical-runtime-validation.log`.
Execution evidence is x86_64 Linux ELF run on the host. User-program GPU execution
is not established.

## Prior explicit record constructor checkpoint (2026-10-04)

Shader digest `bf594c3d1d422f3d` adds complete ordered arguments and shared
application ownership for explicit record constructors, structural value-path
classification, and preservation of explicit actual types during inference.
The full execution gate reports 201 passes and the same two inline-array borrow
failures out of 203 tests. Four focused compiler tests, two new parser tests,
22 semantic token/ownership controls, and both resource checks pass.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 43.660 ms |
| Canonical 1 MB wall | 46.772 ms |
| 32-parameter generic entry recompile, 10 samples | 270.681 ms |

The existing `tools/lanius_perf.py` `single-file-1mb` preset used seeds 20–39 in
`daemon_warm_workspace` mode. All 20 source hashes match their manifests and the
preceding frozen identities. Every timed sample has zero compiled-unit cache
hits and zero newly created buffers, bind groups, or pipelines. Schema validation
passes, and all 20 emitted ELFs execute with exact stdout, empty stderr, and exit
zero. The runner saved the report before the existing catalogue `list.get`
exception; the report and artifacts were independently validated.

The existing generic driver used three warmups and ten entry recompiles, with
invalidation outside the clock and warm imports. Minimum is 265.256 ms, mean
270.287 ms, maximum 275.694 ms. The 78,746-byte final ELF passes exact stdout,
empty stderr, and exit-zero checks. Canonical compiler time is 5.6% above and
generic entry time 1.0% below the preceding unpaired runs. These measurements do
not isolate the change's performance effect or establish a cross-compiler 10x
ratio. Wider generic graph scaling remains unfinished.

Tracked live allocation bytes are 1,576,111,615, down 7,373,052 from the preceding
run; five raw buffers with unavailable sizes remain excluded. The unchanged
enforced shader guard records 743 artifacts, maximum 522,460 bytes, against a
524,288-byte limit. Source edits were frozen during builds, tests, and measurement;
commands stayed below two minutes. The initial execution build reported digest
`714ce3a95edfb4a5`. Both digests were reconstructed from identical artifact bytes;
the builder hashes cached artifacts before freshly compiled ones. All 1,486
SPV/reflection SHA-256 values remain unchanged across measurement. Raw reports,
executable checks, digest audit, and source/binary identities are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261004-explicit-records/`.
Execution evidence is x86_64 Linux ELF run on the host. User-program GPU execution
is not established.

## Prior record receiving-context checkpoint (2026-10-04)

Shader digest `1eb05daac5b78263` adds shared receiving contexts for record literals
and declaration expansion for expected argument roots. The complete execution
gate reports 198 passes and two retained inline-array borrow failures out of 200
tests. All five focused record-context tests and the resource/lifetime check pass.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 41.354 ms |
| Canonical 1 MB wall | 44.275 ms |
| 32-parameter generic entry recompile, 10 samples | 273.333 ms |

The existing `tools/lanius_perf.py` `single-file-1mb` preset used seeds 20–39 in
`daemon_warm_workspace` mode. All 20 source hashes match their manifests and the
preceding frozen source identities. Every timed sample has zero compiled-unit
cache hits and zero newly created buffers, bind groups, or pipelines. Independent
schema validation passes. All 20 emitted ELFs execute with exact stdout, empty
stderr, and exit zero. The runner saved its report before the existing catalogue
`list.get` exception; the report and artifacts were independently validated.

The generic driver used three warmups and ten entry recompiles with invalidation
outside the clock and warm imports. Minimum is 258.345 ms, mean 272.435 ms,
maximum 298.900 ms. Its 78,746-byte final ELF passes exact stdout, empty stderr,
and exit-zero checks. Compared with the preceding unpaired runs, canonical
compiler time is 1.0% higher and generic entry time is 2.4% higher. These runs do
not isolate the change's performance effect or establish a cross-compiler 10x
ratio. Larger generic graph scaling remains unfinished.

Tracked live allocation bytes remain 1,583,484,667; five raw buffers with
unavailable sizes are excluded. Record inference uses existing buffers, and its
additional dispatches run only when struct initialization is required. The
unchanged enforced shader guard records 743 artifacts, maximum 522,460 bytes,
against a 524,288-byte limit. Sources were frozen during builds, tests, and
measurements; commands stayed below two minutes. Reports, executable checks,
binary/source identities, and per-artifact SHA-256 records are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261004-record-contexts/`.
Execution evidence is x86_64 Linux ELF run on the host. User-program GPU
execution is not established.

## Prior structural-header checkpoint (2026-10-04)

Shader digest `fb26a3ca5416983e` separates raw delimiter matching from semantic
bracket projection and recovers nested condition owners structurally. The full
execution gate reports 193 passes and two retained borrow failures out of 195
checks. Fresh generic record-literal receiving contexts were an additional
compiler dependency at that checkpoint; the current checkpoint fixes them.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 40.950 ms |
| Canonical 1 MB wall | 44.045 ms |
| 32-parameter generic entry recompile, 10 samples | 266.886 ms |

The existing `tools/lanius_perf.py` `single-file-1mb` preset used seeds 20–39 in
`daemon_warm_workspace` mode. All 20 source hashes match the frozen manifests;
all timed samples have zero compiled-unit cache hits and zero newly created
buffers, bind groups, or pipelines. Independent schema validation passes. Every
emitted ELF executes with exact stdout, empty stderr, and exit zero. The runner
saved its report before the existing catalogue `list.get` exception; that
postprocessing failure remains separate from the independently validated report.

The generic driver used three warmups and ten recompiles with entry invalidation
outside the clock and warm imports. Minimum is 264.479 ms, mean 267.431 ms,
maximum 271.332 ms. Its 78,746-byte final ELF passes exact stdout, empty stderr,
and exit-zero checks. Compared with the preceding unpaired runs, canonical
compiler time is 10.6% lower and generic entry time 2.2% higher. These measurements
do not isolate the effect of the change or establish a cross-compiler 10x ratio.

Tracked live allocation bytes are 1,583,484,667, up 9,830,352 from the preceding
run; five raw buffers with unavailable sizes remain excluded. The enforced
524,288-byte shader guard records 742 artifacts, maximum 522,460 bytes. Source
edits were frozen during builds and measurements; commands stayed below two
minutes. Raw reports, timings, executable validations, and binary identities are
retained in `benchmark_artifacts/performance/stdlib-gpu-20261004-structural-headers/`.
Execution evidence is x86_64 Linux ELF run on the host. User-program GPU execution
is not established.

The initial incremental test build reported digest `a2dc19b9266420ba`. The builder
hashes cached artifacts before newly compiled ones, so its digest can differ
with enumeration order. Both reported digests were reconstructed from identical
SPV/reflection bytes. `artifact-digest-order-audit.log` and the per-artifact
SHA-256 manifest retain that check; no shader payload changed between the
execution gate and these performance measurements.

## Prior native contract checkpoint (2026-10-04)

Shader digest `6544f2a90ef57db8` adds shared native frame/epilogue widths and
source completion ordering. The complete generics execution gate reports 191
passes and two retained inline-array borrow failures out of 193 tests. The two
native defects from the preceding checkpoint are fixed.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 45.818 ms |
| Canonical 1 MB wall | 48.539 ms |
| 32-parameter generic entry recompile, 10 samples | 261.105 ms |

The existing `tools/lanius_perf.py` `single-file-1mb` preset used seeds 20–39
in `daemon_warm_workspace` mode. All source hashes match their frozen manifests;
every timed sample has zero compiled-unit cache hits and zero new buffers,
bind groups, or compute pipelines. Independent schema validation passes. All 20
ELFs execute with exact stdout, empty stderr, and exit zero. The runner saved
its report before the existing catalogue `list.get` postprocessing exception.
Tracked live allocation bytes remain 1,573,654,315, excluding five raw buffers
whose sizes are unavailable.

The generic driver used three warmups and ten entry recompiles, with entry
invalidation outside the clock and warm imports. Minimum is 253.179 ms, mean
261.384 ms, and maximum 269.007 ms. Its final 78,746-byte ELF passes exact stdout,
empty stderr, and exit-zero checks. Compiler median is 4.6% above the preceding
43.793 ms run, and generic median is 0.2% above the preceding 260.563 ms run.
These are unpaired measurements. They do not identify a causal regression,
establish wider generic scaling, or establish a cross-compiler 10x ratio.

Source edits were frozen during builds and measurements. Commands were bounded
below two minutes. The unchanged enforced shader guard records 741 artifacts,
maximum 522,460 bytes, and limit 524,288 bytes. Reports, executable validations,
binary identities, and raw timings are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261004-native-contracts/`.
Runtime validation is x86_64 Linux ELF executed on the host; user-program GPU
execution remains unverified.

## Prior nested-result checkpoint (2026-10-04)

Shader digest `c1a8b52c1f408f18` includes shared nested receiving contexts,
explicit field scopes, final imported-pattern validation, argument-preserving
return materialization, and result-context validation after inference closes.
The CLI and generic driver were rebuilt against this source and shader set.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 43.793 ms |
| Canonical 1 MB wall | 46.993 ms |
| 32-parameter generic entry recompile, 10 samples | 260.563 ms |

The existing `tools/lanius_perf.py` preset used seeds 20–39 in
`daemon_warm_workspace` mode. All 20 source hashes match their frozen manifests.
Every timed sample has zero compiled-unit cache hits and zero new buffers, bind
groups, or compute pipelines. Independent schema validation passes, and all 20
ELFs execute with exact stdout, empty stderr, and exit zero. The runner saved its
report before the existing catalogue `list.get` postprocessing exception.
Tracked live allocation bytes remain 1,573,654,315; five raw user-owned buffers
have unavailable sizes and are excluded from that byte count.

The generic driver used three warmups and ten entry recompiles with entry
invalidation outside the clock. Imports may remain cached. Minimum is 255.343 ms,
mean 261.446 ms, and maximum 276.510 ms. Its final 78,746-byte ELF passes exact
stdout, empty stderr, and exit-zero validation. These unpaired medians are lower
than the preceding checkpoint; the measurements do not isolate the effect of the
changes, establish scaling across arbitrary generic programs, or establish a
cross-compiler 10x ratio.

Both drivers retained the enforced shader guard: 741 artifacts, maximum 522,460
bytes, limit 524,288 bytes. Source edits were frozen during builds and timings;
commands were bounded below two minutes. Reports, validators, hashes, and raw
timings are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261004-nested-results/`.
Runtime validation is x86_64 Linux ELF on the host. The two new native failures
documented in the [generics checkpoint](compiler-generic-types.md) remain open.

## Prior result-only constant checkpoint (2026-10-03)

Shader digest `49ceefb7cccfcae5` includes independent result constant environments,
shared local/imported declaration matching, accepted result validation, and sparse
retention. All existing performance drivers were rebuilt against this host code
and shader set. Runtime validation uses x86_64 Linux ELF on the host.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 56.074 ms |
| Canonical 1 MB wall | 59.229 ms |
| 32-parameter generic entry recompile, 10 samples | 293.330 ms |

The existing `tools/lanius_perf.py` `single-file-1mb` preset compiled all 20
million-byte programs, seeds 20–39, in `daemon_warm_workspace` mode. Their hashes
match the frozen manifests. Timed samples have zero compiled-unit cache hits and
zero newly created buffers, bind groups, or compute pipelines. Independent
report-schema validation passes; all 20 ELFs pass exact stdout, empty stderr,
and exit-zero checks. The report was saved before the runner's existing catalogue
`list.get` postprocessing exception; independent validators checked that report
and its artifacts. The CLI rebuilt by the runner and the measured example have
retained SHA-256 identities, alongside the earlier combined-build identities.

The existing generic driver uses three warmups and ten entry recompiles, with
entry invalidation outside the clock; imports may remain cached. Minimum is
288.373 ms, mean 293.625 ms, and maximum 298.787 ms. Its final 78,746-byte ELF
passes exact stdout, empty stderr, and exit-zero validation.

Compared with the preceding unpaired checkpoint, the compiler and generic medians
are 34.4% and 2.6% higher. The compiler's tracked live allocation bytes rise from
1,544,163,247 to 1,573,654,315: 29.49 MB, about 1.9%. This tracker excludes raw
user-owned wgpu buffers whose sizes are unavailable. These timings do not isolate
a code regression. Concurrent GPU use was observed before and after comparison
runs, at 40% and 39% utilization; those snapshots do not measure contention during
individual samples or prove the cause of the canonical increase.

Opposite-order controls use the existing `gpu_compile_bench` mixed 1 MB source,
seed 20, and a preserved binary with its matching shader set. Every measured
compile executes and validates its output, so these timings include validation.

| Order | Binary | Average | Minimum |
| --- | --- | ---: | ---: |
| Forward, first | Preserved baseline | 64.241 ms | 62.358 ms |
| Forward, second | Current | 64.749 ms | 62.937 ms |
| Reverse, first | Current | 63.974 ms | 62.059 ms |
| Reverse, second | Preserved baseline | 64.182 ms | 63.561 ms |

Current averages differ by +0.79% and -0.32% in the two orders. These controls use
a different nongeneric corpus and the older `5aa50faa5dc57d25` baseline, rather
than the immediately preceding constant-value checkpoint. They support this
specific control case but do not resolve the canonical timing increase, establish
generic workload scaling, or establish a current cross-compiler 10x ratio.

The unchanged shader guard remains enforced: 741 artifacts, maximum 522,460 bytes,
limit 524,288 bytes. Cold pipeline initialization remains uncharacterized; warm
measurements do not establish acceptable first-run performance. Source and shader
edits were frozen during builds and measurements. Each command had a timeout
below two minutes, and an EXIT trap restored the current shader link after each
baseline process.

Commands, reports, executable validations, hashes, GPU activity snapshots, and
raw controls are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261003-result-constants/`.

## Prior constant value checkpoint (2026-10-03)

Shader digest `3143f245e4678848` includes constant value expressions, required
local constant checks, complete imported array validation, and literal shape
context. Both existing drivers were rebuilt against this source and shader set.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 41.726 ms |
| Canonical 1 MB wall | 44.879 ms |
| 32-parameter generic entry recompile, 10 samples | 285.815 ms |

The existing `tools/lanius_perf.py` `single-file-1mb` preset compiled all 20
million-byte inputs, seeds 20–39, in `daemon_warm_workspace` mode. Their source
hashes match frozen manifests. All timed samples have zero compiled-unit cache
hits and zero new buffers, bind groups, or compute pipelines. Independent
report-schema validation passes; every emitted ELF passes exact stdout, empty
stderr, and exit-zero checks. The runner saved the report before its existing
catalogue `list.get` postprocessing exception. Its build step rebuilt the CLI;
`identities.sha256` records the resulting measured CLI and existing example.
The earlier combined-build hashes remain in `identities-before-runner-build.sha256`.
Both versions report the same shader digest.

The existing `stdlib_gpu_perf` example measured ten entry recompiles after three
warmups with entry invalidation outside the clock; imports may remain cached.
Minimum is 274.309 ms, mean 284.297 ms, and maximum 297.206 ms. The final
78,746-byte ELF passes exact stdout, empty stderr, and exit-zero validation.

The preceding unpaired medians are 41.711 ms compiler and 284.328 ms generic
entry. The present medians are about 0.04% and 0.5% higher. These observations
do not establish unchanged performance, a causal regression, large generic
source scaling, or a cross-compiler 10x ratio. The shader guard remains enforced:
741 artifacts, maximum 522,460 bytes, limit 524,288 bytes.

First-run initialization remains a separate concern. An initial shape-context
implementation with two materializer call sites took 60.16 seconds for the ten
focused tests on its first run. The single-walk implementation took 25.25 seconds,
and the final capacity-guard revision took 26.47 seconds. Each revision changed
the shader digest and can affect driver pipeline initialization. These are
observations from test runs, not controlled startup benchmarks; they do not
isolate pipeline creation from test execution or establish acceptable cold
startup. The warm measurements above do not resolve this concern.

Commands, reports, runtime validations, source/binary identities, and shader
metadata are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261003-constant-values/`.

## Prior constant domain checkpoint (2026-10-03)

Shader digest `1e60d9e7da516426` includes complete nested length inference,
symbolic forwarding, retained concrete replay values, and declaration bounds.
Both existing performance drivers were rebuilt against this host code and
shader set.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 41.711 ms |
| Canonical 1 MB wall | 44.831 ms |
| 32-parameter generic entry recompile, 10 samples | 284.328 ms |

The existing `tools/lanius_perf.py run-lanius --preset single-file-1mb --target
x86_64 --modes daemon_warm_workspace --skip-profile` runner compiled all 20
million-byte inputs, seeds 20–39. Source hashes match the frozen manifests.
Every timed sample has zero compiled-unit cache hits and zero new buffers,
bind groups, or compute pipelines. Independent report-schema validation passes,
and all 20 ELFs pass exact stdout, empty stderr, and exit-zero checks. The report
was saved before the existing catalogue `list.get` postprocessing exception;
independent validators checked the saved report and artifacts.

The existing `stdlib_gpu_perf` driver measured ten entry recompiles after three
warmups with `LANIUS_PERF_REBUILD_ENTRY=1`. Entry invalidation is outside the
clock, and imports may remain cached. Minimum is 275.093 ms, mean 284.466 ms,
and maximum 292.381 ms. Its final 78,746-byte ELF passes executable validation.

The preceding unpaired medians are 40.162 ms compiler and 268.152 ms generic
entry. The present medians are higher by 3.9% and 6.0%, respectively. These
measurements do not isolate the cause or establish unchanged performance.
They do not establish large generic-source scaling or a cross-compiler 10x
ratio. The unchanged shader guard remains enforced: 741 artifacts, maximum
522,460 bytes, limit 524,288 bytes.

Commands, reports, runtime validation, source/binary hashes, and shader metadata
are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261003-constant-domains/`.

## Prior argument inference checkpoint (2026-10-03)

Shader digest `60cb26d5a7d42101` includes the shared argument-priority contract and
scalar/array literal contexts documented in [compiler generics](compiler-generic-types.md).
Both existing performance drivers were rebuilt against the current host code and
shader set.

| Measurement | Median |
| --- | ---: |
| Canonical 1 MB compiler, 20 distinct programs | 40.162 ms |
| Canonical 1 MB wall | 42.941 ms |
| 32-parameter generic entry recompile, 10 samples | 268.152 ms |

The canonical run uses `tools/lanius_perf.py run-lanius --preset single-file-1mb
--target x86_64 --modes daemon_warm_workspace --skip-profile`. All 20 million-byte
inputs, seeds 20–39, match their frozen source manifests. Every timed sample has
zero compiled-unit cache hits and zero newly created buffers, bind groups, or
compute pipelines. All 20 ELFs pass exact stdout, empty stderr, and zero-exit
checks, and the independent report-schema validation passes. The runner saves
the complete report before the existing catalogue `list.get` postprocessing
error. Independent schema and executable checks were completed.

The existing `stdlib_gpu_perf` example measures ten entry recompiles after three
warmups with `LANIUS_PERF_REBUILD_ENTRY=1`. Entry invalidation is outside the timed
interval; imports may stay cached. Its final 78,746-byte ELF passes exact stdout,
empty stderr, and zero-exit checks. Minimum is 260.610 ms, mean 269.741 ms, and
maximum 282.603 ms.

These are unpaired measurements. The historical 41.287 ms canonical and
265.524 ms generic medians do not establish a causal speed change or unchanged
performance. This checkpoint also does not establish large generic-source scaling
or a current cross-compiler 10x ratio. The unchanged 524,288-byte shader guard
remains enforced; 741 artifacts have a maximum size of 522,460 bytes.

Raw reports, runtime validation, source/binary hashes, and shader metadata are in
`benchmark_artifacts/performance/stdlib-gpu-20261003-argument-inference/`.

## Prior contract checkpoint (2026-10-03)

Shader digest `eb68683844f2cb2e` has the contract consolidation described in
[compiler generics](compiler-generic-types.md). The existing
`tools/lanius_perf.py run-lanius --preset single-file-1mb --target x86_64
--modes daemon_warm_workspace --skip-profile` runner compiled 20 distinct
million-byte programs (seeds 20–39).

| Measurement | Median |
| --- | ---: |
| Compiler | 41.287 ms |
| Wall | 44.534 ms |

All 20 emitted ELFs produced exact expected stdout, empty stderr, and exit 0.
Source hashes match the frozen workload manifests. Every timed sample has zero
compiled-unit cache hits and zero new buffers, bind groups, or compute pipelines.
Independent result-schema validation passes. The runner saved the report before
the existing catalogue `list.get` postprocessing error; executable validation was
performed separately on all 20 artifacts.

The earlier 38.788 ms compiler median is an unpaired historical run. This result
does not establish unchanged performance, a causal regression, generic-graph
scaling, or a current cross-compiler 10x ratio. The shader size guard remains
524,288 bytes; the largest artifact is 522,460 bytes across 738 shaders.
Raw report, tool log, shader metadata, and runtime validation records are in
`benchmark_artifacts/performance/stdlib-gpu-20261003-contracts/`.

## Historical measurements

The preceding zero-layout checkpoint has shader digest `3979aa9b02a9bb6b` and
passes 126 focused checks. A fresh existing `stdlib_gpu_perf` driver measures
the real 32-parameter entry at **265.524 ms median**, over ten entry recompiles
after three warmups with warm imports. Its final ELF passes exact stdout,
empty stderr, and zero-exit checks. Results, commands, source/binary hashes, and
shader metadata are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261001-zero-layouts/`.
This unpaired measurement does not isolate the pointer/zero-layout changes or
establish unchanged performance. Large corpus controls and external compiler
comparisons were not rerun for this snapshot.

The preceding expression-inference checkpoint has shader digest
`96ddfc90abad06ef` and passes 115 focused checks. A fresh real 32-parameter
entry benchmark measures **248.106 ms median** over ten recompiles after three
warmups, with warm imports and successful final ELF validation. This is an
unpaired measurement and does not establish a speedup. Results and identities
are retained in `benchmark_artifacts/performance/stdlib-gpu-20261001-expressions/`.
The large canonical corpus and matched controls have not been rerun for this
checkpoint. The two intermediate snapshots, `7061ad913cc9d0ac` and
`36552debb8404547`, were unmeasured. Older measurements below retain their
original shader versions.

Measured inference checkpoint, 2026-10-01: the real 32-parameter generic program
measures **265.165 ms median** for an entry recompile with warm imports and
passes executable validation. Opposite-order 1 MB controls show current
averages of **69.620 and 68.257 ms**, versus matched baseline averages of
**64.119 and 66.413 ms**. The increases are 8.6% and 2.8%; the difference above
5% did not repeat. These controls do not establish unchanged performance or a
current 10x comparison. See the measured checkpoint below.

The preceding canonical run, 2026-10-01: **73.400 ms compiler / 78.147 ms wall** on
20 distinct 1 MB programs, all executed and validated, at the complete nominal
graph checkpoint. This is above the older scoped-field result of
37.580/40.501 ms. Two same-session control pairs also found higher absolute
times in the matched older compiler; the current compiler was faster in both
pairs. Those controls use a different 1 MB corpus and do not establish a matched
canonical-corpus comparison. A real 32-parameter generic program measured
**246.051 ms median** for a full entry recompile with warm imports and passed
runtime validation. The current compiler
checkpoint and remaining generic workload limits are documented in
[compiler generics](compiler-generic-types.md). Earlier measurements below
retain their original shader snapshots.

Measured on 2026-09-29. The initial GPU shader fixes for `Option<bool>` took
**33.9 ms** on the standard 1 MB benchmark, compared with **34.3 ms** before
the fixes. Fresh unoptimized cross-compiler measurements put that version of
Lanius **14–42 times faster than GCC, G++, Rust, and Zig** on that corpus.
TCC is faster than Lanius. Subsequent checks below cover dependency projection,
parser workspace, enum layout, match scheduling, imported method signatures, and
empty struct results, plus larger inputs; the original
measurements remain recorded separately.
The larger custom workload does **not** meet a 10× comparison against Zig.

Each comparison below records a particular shader snapshot. The initial
baseline is **c37d38b**, the previous stdlib commit; earlier compiler changes
are present in both versions and are outside that comparison.

The current worktree also contains later Option-slice, scalar payload-method,
native template-deferral, qualified generic return, Result descriptor-call,
source/dependency context retention, checked generic call capture, scalar body
replay and native relocation scheduling, string call/return projection, and
generic receiver body scheduling. Receiver-bound argument checks now resolve
generic fallback and combinator types from the checked receiver, and factory
receiver snapshots retain either checked type-argument representation.
Generic indexing and iteration now defer bodies until their element stride is
known. Imported scalar arguments resolve member field types, and both slice
claim paths bind generic parameters to the element rather than the whole view.
The specialized x86 emitter now uses the same minimum Slang optimization policy
as the main emitter to stay within the 512 KiB shader gate. The current semantic
scatter shader also uses that policy. The latest canonical result below
measures the scoped generic field checkpoint's shader set on the plain 1 MB
workload. The new checkpoint below includes structural graph replay and the
subsequent call/index/parser repairs. The call snapshot batches receiver
readback and is collected only for compiled source-unit objects. The plain
canonical corpus does not cover that retention/readback cost; the new generic
program measures the resulting entry-compile path with warm imported units.
Historical measurements below retain their original scope.

## Inferred-call closure checkpoint, 2026-10-01

This checkpoint uses shader digest `5b0b8f17178ea693`: 732 artifacts,
523,396-byte maximum, and the enforced 524,288-byte guard. Both performance
drivers were rebuilt against the current host code. Current and baseline
binary hashes, shader identities, commands, and raw logs are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261001-inference/`.

The existing `gpu_compile_bench` runs the same 1,000,134-byte mixed source,
seed 20, three warmups, ten full compiles, and executable validation in every
measured iteration. Its source hash matches the previous control corpus.
Matched host/shader pairs ran in opposite orders; an EXIT trap restored the
current shader link after each baseline run.

| Pair order | Baseline average / minimum | Current average / minimum | Average change |
| --- | ---: | ---: | ---: |
| Baseline, current | 64.119 / 57.376 ms | 69.620 / 64.710 ms | +8.6% |
| Current, baseline | 66.413 / 63.773 ms | 68.257 / 61.932 ms | +2.8% |

The difference above 5% did not repeat. Both current averages exceed the
baseline, so the result does not establish identical performance. The source
is nongeneric and does not exercise the new inference closure; these controls
cannot attribute a cause. They include execution and validation time and are
distinct from the canonical compiler-only timings below.

The existing `stdlib_gpu_perf` example recompiles the entry of
`generic_many_parameter_composition_32.lani` ten times after three warmups,
using `LANIUS_PERF_REBUILD_ENTRY=1`. Entry invalidation is outside the clock;
imports may remain cached. Median is **265.165 ms**, minimum 252.001 ms,
average 264.256 ms, and maximum 273.262 ms. Its final 66,433-byte ELF passes
exact stdout, empty stderr, and zero exit status. The previous 246.051 ms
median below is unpaired and cannot isolate these changes. This small real
program does not establish large generic-source throughput.

No external compiler measurements were repeated at this checkpoint. The
historical ratios below do not establish a current general 10x result.

## Complete nominal graph checkpoint, 2026-10-01 (preceding)

The existing command completed all 20 timed samples before a catalogue
postprocessing error:

```bash
timeout 110s python3 tools/lanius_perf.py run-lanius --preset single-file-1mb --target x86_64 --modes daemon_warm_workspace --skip-profile --startup-timeout 60 --job-timeout 30 --output benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-nominal-graph-1mb.json
```

Compiler time median was **73.400 ms**; wall median was **78.147 ms**
(72.176–86.137 ms across samples). All 20 outputs executed with exact expected
stdout, empty stderr, and zero exit status. Their source hashes match the
previous frozen seed-20-through-39 corpus. Timed compiled-unit cache hits and
misses were zero on this direct single-file path, and timed samples created no
new buffers, bind groups, or compute pipelines. The shader digest is
`969718dcfd9ce8a8`, with 732 artifacts and an enforced 524,288-byte guard;
the largest is 523,396 bytes.

The earlier 40.501 ms wall result is unpaired. To investigate the higher time,
the existing `gpu_compile_bench` compared a matched old host/shader snapshot
(`5aa50faa5dc57d25`) with the new host/shaders, alternating order over two pairs.
Both generators produce the exact same 1,000,134-byte `mixed` source with seed
20 (SHA-256 `09b3794912fc81fccf5b0c73c48d176b65d336c7dfbc6e804372b5191259c7f3`).
Every run uses three warmups and ten measured full compiles with executable
validation in each iteration. Thus these times include validation, unlike the
canonical compiler-only samples.

| Pair order | Old average / minimum | Current average / minimum |
| --- | ---: | ---: |
| Old, current | 78.495 / 72.078 ms | 63.905 / 58.211 ms |
| Current, old | 66.562 / 62.308 ms | 60.409 / 56.602 ms |

The older compiler also runs with higher absolute timings. These controls show
no repeatable slowdown on this mixed source and support machine conditions as
a contributor to the historical increase. They cannot isolate every compiler
change or establish performance on the canonical corpus. One observation before
a control showed GPU P0, 1,965 MHz, 71°C, and 65% utilization from shared activity.
The shared shader link was restored after each old run.

The existing `stdlib_gpu_perf` example measured the executable
`generic_many_parameter_composition_32.lani`: three warmups and ten entry
recompiles with `LANIUS_PERF_REBUILD_ENTRY=1`. Invalidation occurs outside the
timed span and prevents entry-unit reuse; imported units may remain cached.
Median was **246.051 ms**, minimum 209.666 ms, mean 244.472 ms, and maximum
261.647 ms. The final ELF passes its exact Unicode/empty-string stdout,
empty stderr, and zero-exit contract. There is no earlier matched result for
this generic program, and it is not a large generic-source throughput test.

Raw canonical results, all 20 executable validations, four control logs, and
the generic log are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/`.
Catalogue generation failed because an auxiliary JSON list was treated as a
canonical document. Measurement and executable validation had completed;
no timing samples were rerun to work around the catalogue error. External
compilers were not rerun, so the historical ratios below do not establish a
current general 10x comparison, especially against Zig.

## Follow-up checks before the parser workspace fix

The pre-parser snapshot contains twelve changed SPIR-V binaries, with shader
digest `42d86cd21a5a6cc0`. It includes the imported method-result argument and
generic slice-parameter fixes added after the original nine-shader measurement
(digest `8a2d0eab0280d053`). Rust production code is unchanged in that comparison.

Rechecking the frozen 1 MB preset gave **44.206 ms** with the pre-parser shaders
and **44.260 ms** with the original measured fixes, a **0.12% decrease**.
Both runs compiled twenty distinct programs and passed all forty executable
checks. The higher absolute times also occurred with the control shader set;
comparing the latest 44.2 ms result directly with the earlier 33.9 ms result
would conflate changes in machine conditions with compiler changes.
These results and the pre-parser patch and shader hashes are retained under
`benchmark_artifacts/performance/stdlib-gpu-20260929/integration-recheck/`.

### Larger executable inputs

The size sweep uses the existing `lanius_perf` generator, workspace priming,
cache clearing, and timed compile path. It uses the custom
`mixed-function-sizes` profile at 1, 4, and 5 million bytes, with seeds 20–22
and seed 19 as workspace primer. These are additional workloads, separate from
the frozen `single-file-1mb` comparison corpus. Every function is reachable;
the inputs contain arithmetic, branches, loops, arrays, and structures. Padding
is less than one function body rather than the source of their larger size.

For the 4 MB and 5 MB regression checks, each shader version compiled every
seed five times per process. Two pairs ran in opposite order, giving thirty
measured full recompiles per version at each size. Every measured output was
executed, and the before/after native hashes matched for every seed.

| Lanius source size | Baseline c37d38b | Pre-parser fixes | Pooled median change |
| --- | ---: | ---: | ---: |
| 4 MB | 191.295 ms | 194.658 ms | +1.76% |
| 5 MB | 251.017 ms | 254.832 ms | +1.52% |

The first 4 MB pair differed by 9.18%; the reverse-order pair differed by
0.98%. The 5 MB pairs differed by 4.93% and 0.55%. The larger increase did not
repeat. These measurements establish no repeatable increase above the 5%
investigation threshold; they do not establish that performance is identical.
The desktop GPU was shared with other activity. An observation between runs
showed P0, 1,950 MHz graphics clock, 68°C, and 78% utilization, so timing
variation is retained rather than filtered out.

### Cross-compiler size sweep

The representative inputs contain **30,956, 123,558, and 154,190 nonblank code lines**
at 1, 4, and 5 MB. Each CPU compiler ran once per seed, in deterministic
randomized order, using the same unoptimized configurations with debug symbols
disabled as the original comparison below. The GPU compiler ran fifteen timed
full recompiles at 1 MB and thirty at each larger size. GPU daemon startup is
excluded; CPU process startup is included. All source variants use the same
generated program structure and expected output, although their byte counts
differ by language.

All times below are median wall milliseconds. The 4 MB and 5 MB Lanius figures
pool the two current-shader runs; external medians use three distinct programs
per compiler and size. This is a size check on this machine and source shape,
with fewer distinct seeds than the frozen twenty-program corpus.

| Compiler | 1 MB | 4 MB | 5 MB | 5 MB time / Lanius time |
| --- | ---: | ---: | ---: | ---: |
| Lanius, warm GPU workspace | 48.369 | 194.658 | 254.832 | 1.00× |
| GCC, `-O0 -g0` | 1,391.081 | 4,680.813 | 6,481.886 | 25.44× |
| G++, `-O0 -g0` | 1,610.192 | 5,501.182 | 6,894.616 | 27.06× |
| Rust, `opt-level=0`, 16 frontend threads | 1,258.428 | 5,553.966 | 8,152.216 | 31.99× |
| Zig, `Debug -fstrip` | 494.379 | 1,090.008 | 1,331.862 | 5.23× |
| TCC, default | 20.555 | 59.023 | 80.710 | 0.32× |

The 10× target holds against GCC, G++, and Rust at every measured size in this
mode. It **does not hold against Zig at 4 MB or 5 MB**: the ratios are 5.60× and
5.23×. TCC is faster than Lanius at every size. The baseline shader version also
falls below 10× against Zig, so the recent fixes do not explain that shortfall.
Larger inputs alone are insufficient to establish the broad 10× claim.

All **135 measured Lanius outputs and 45 external compiler outputs** executed
with the exact expected stdout and zero exit status. No project compiled-unit
results were reused in the timed GPU samples, and all timed GPU samples created
zero new buffers, bind groups, or pipelines.

An **8 MB single-file input failed before GPU compilation** with `LNC0059`:
the default frontend compilation unit permits at most **5 MiB per source file**.
The diagnostic is retained as `size-sweep/unsupported-8mb.log`. It has no
successful timing result. Larger single files require compiler capacity support
or a project divided into supported compilation units.

The size-sweep drivers and raw executable validation records are retained in
`benchmark_artifacts/performance/stdlib-gpu-20260929/size-sweep/`. Each invocation
is bounded by `timeout 110s`; GPU versions and CPU trials run sequentially.
The drivers call existing perf helpers and do not change the compiler or the
frozen benchmark preset. After preparing the build and shader sets, run from
the worktree root, substituting 1000000, 4000000, or 5000000 for `SIZE`:

```bash
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/size-sweep/measure_lanius.py SIZE current
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/size-sweep/measure_external.py SIZE 0 15
```

Use a fresh external result directory for a fresh timing run. The external
driver checkpoints after each validated output and skips completed rows when
resuming an interrupted command. Switch the shared shader symlink before the
baseline runs, then restore the current set. To reproduce the historical size
sweep, select `pre-parser-shaders` for its `current` runs. The measured pairs are recorded in
`size-sweep/commands.txt`; each result records its actual shader digest.

## Parser workspace fix: sixteen-shader snapshot

The parser snapshot has shader digest `b6e58733a44b8b7d`. Sixteen SPIR-V binaries
differ from c37d38b; four differ from the twelve-shader pre-parser snapshot above.
GPU-private parser uniforms now pass the allocated delimiter-tree leaf position
to query shaders. The tree layout remains fixed when a later job has fewer
tokens. Compiler IR, extraction, formal proofs, and the native ABI are unchanged.

The regression test executes `character_inventory`, `halfword_window_total`,
then both again through the shared compiler. Previous shaders reproduce the
second program's `LNC0016` failure; current shaders pass. The complete foundation
suite passes all seven tests, including the combined 138-entry executable gate.
The reproduction and runtime logs are retained under
`tests/fixtures/stdlib_compiler_state/`.

Initial sequential 4 MB process pairs showed larger timings with the fix:

| Sequential pair | Previous shaders | Fixed shaders | Median change |
| --- | ---: | ---: | ---: |
| First | 151.201 ms | 190.770 ms | +26.17% |
| Repeat | 135.148 ms | 152.677 ms | +12.97% |

These observations triggered a closer comparison. Two separately primed daemons
held the previous and fixed shaders simultaneously. Requests compiled the same
seed in immediate pairs, alternating which version ran first. Each version made
fifteen full recompiles over three distinct seeds, with compiled project results
cleared before each request. All timed requests created zero new GPU buffers,
bind groups, or pipelines. Execution and hash validation occurred outside the
timer. The 5 MB run reversed both daemon startup and paired request order.

| Source size | Previous median | Fixed median | Median paired change |
| --- | ---: | ---: | ---: |
| 4 MB | 152.495 ms | 155.195 ms | +0.50% |
| 5 MB | 200.043 ms | 198.083 ms | -2.72% |

The paired column is the median of each fixed/previous timing ratio, rather
than a ratio of the two overall medians. The sequential slowdown did not repeat
under these interleaved comparisons. This establishes no repeatable increase
above the 5% investigation threshold on these workloads; it does not establish
identical performance. Both daemons shared the desktop GPU, and the sequential
results remain retained. No samples were removed.

All **120 measured outputs** from the sequential and interleaved parser checks
executed with the exact expected stdout and zero exit status. Before/after
native hashes matched for every seed. Both versions used the identical latest
Rust binary: the previous shaders ignore the new appended uniform fields. This
comparison measures the changed query shaders with the current host code.

Eight canonical performance documents, executable validation records, source
and shader hashes, the exact parser patch, and the interleaved driver are retained
under `benchmark_artifacts/performance/stdlib-gpu-20260929/parser-workspace-fix/`.
The driver calls the existing `lanius_perf` generator, daemon, priming, request
timing, and result helpers. After preserving both shader sets in the shared build
layout, run from the worktree root:

```bash
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/parser-workspace-fix/measure_pair.py 4000000 interleaved
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/parser-workspace-fix/measure_pair.py 5000000 interleaved-reverse --reverse
```

The driver selects the preserved `pre-parser-shaders` and
`parser-workspace-validated-shaders` snapshots by default. It restores the latest
shader link and closes both daemons. These are
regression comparisons, separate from the earlier cross-compiler size sweep.
No fresh external compiler timings were taken for the parser fix, so the
cross-compiler ratios above continue to describe the pre-parser snapshot.

## Factory receiver fix

The factory receiver snapshot has shader digest `83a7f39db9e32d2a`. Seventeen SPIR-V
binaries differ from c37d38b; one differs from the sixteen-shader parser snapshot.
`type_checker/dependencies/07_project_calls` preserves concrete scalar arguments
when an imported function returns a generic nominal value. Existing per-token
instance slots and tagged result references carry those values across dependency
page reuse. No new Rust production code, IR fields, extraction, proofs, or native
ABI changes are part of this fix.

Executable tests now cover direct `Option<bool>` factory receivers, all eight
methods, false/true/absent states, combinator chains, same-name methods on bool
and u8 `Maybe<T>` instances, and a four-argument `Quad<bool, u8, i32, u32>` result.
Wrong method-result scalar types are rejected. Previous shaders reproduce the
receiver lookup failure on the same test binary. The focused bool Option,
foundation, generic enum, and generic Vec suites pass **62 tests**, including
the combined 138-entry executable gate. Dependencies 70 and 74 were then ignored:
complete imported method argument validation and mixed generic enum layout.
The mixed layout failure has a nine-line reproduction and also occurs with
previous shaders; isolated Maybe and Quad modules each execute.

The existing interleaved performance driver compares the parser snapshot with
the factory fix on 4 MB inputs. Each version makes fifteen full recompiles over
three seeds, with cached project results cleared before each request and zero
new job resources. All thirty emitted programs execute with exact expected
stdout and zero exit status. The native hashes match in every pair.

| Regression case | Previous | With factory fix | Change |
| --- | ---: | ---: | ---: |
| 4 MB full recompiles, interleaved | 148.427 ms | 143.004 ms | -0.92% median paired ratio |
| Imported boolean window, entry rebuild | 25.933 ms | 23.070 ms | -11.04% pooled median |

The second row uses the existing `stdlib_gpu_perf` harness and paired driver:
four process pairs run in alternating order, with three warmups and ten timed
entry rebuilds per process. Both versions use identical newly rebuilt harnesses.
A private source copy has its modification time changed outside the timer to
force an entry miss; compiled dependencies remain available. Each of the eight
processes executes its final emitted program, checks stdout `3`, and checks
successful exit. These are **80 timed recompiles and 8 executable checks**;
the harness does not execute every intermediate timed output.

These observations establish no measured slowdown on the checked cases. The
lower timings are not an established general speedup, and this follow-up adds
no fresh cross-compiler ratios. The desktop GPU remains shared with other
activity; all samples are retained. Three canonical documents, raw timings,
validation records, the source patch, source/shader hashes, and commands are in
`benchmark_artifacts/performance/stdlib-gpu-20260929/factory-receiver-fix/`.

To repeat the large comparison with preserved snapshots:

```bash
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/parser-workspace-fix/measure_pair.py 4000000 factory-receiver --previous-shaders parser-workspace-validated-shaders --fixed-shaders factory-receiver-validated-shaders
```

## Mixed enum layout fix

The validated shader digest at this checkpoint is `ec6ad44b56155ace`. Only
`codegen/lir/semantic/scatter.spv` changes from the factory receiver snapshot;
it grows from 312,936 to 321,824 bytes. The same seventeen shader binaries
differ from c37d38b. The 512 KiB shader size guard remains enforced.

The semantic materializer now resolves an enum constructor's checked result
declaration for layout. Previously it treated the enum-local discriminant as
a row in the module-wide variant table. Adding an unused enum before a working
four-payload generic enum therefore selected the wrong owner and caused
`LNC0017`. No Rust production code, compiler IR, extraction, proofs, or native
ABI changes are part of this fix.

Three runtime regressions now execute the nine-line reproduction, combined
imported factory families, and a later generic enum's four distinct payloads
and empty variant through function returns. The same tests fail with the
previous shaders. The focused suites pass **65 tests**, including the combined
138-entry executable gate. Imported method argument validation and a separate
later-match-arm SSA failure remain dependencies 70 and 75.

The existing `lanius_perf` interleaved driver makes fifteen full recompiles per
version over three 4 MB inputs. It clears compiled project results before each
request; all measured jobs create zero new GPU resources. All thirty native
outputs pass their exact stdout and exit contracts, and native hashes match
in every pair. The real imported boolean program uses the existing entry
rebuild harness: four alternating process pairs, three warmups and ten timed
rebuilds each. Its eighty timed compilations retain compiled dependencies;
all eight final process outputs print `3` and exit zero.

| Regression case | Previous factory fix | With enum layout fix | Change |
| --- | ---: | ---: | ---: |
| 4 MB full recompiles, interleaved | 188.604 ms | 191.778 ms | +2.01% median paired ratio |
| Imported boolean window, entry rebuild | 24.895 ms | 24.260 ms | -2.55% pooled median |

Neither comparison crosses the 5% investigation threshold. These measurements
do not establish identical performance or a general speedup. The desktop GPU
is shared with other activity, and all samples are retained. The imported
harness checks the final output of each process; it does not execute every
intermediate timed output or establish zero resource creation for those jobs.
This follow-up adds no fresh cross-compiler ratios.

Three canonical results, raw timings, executable validations, the incremental
source patch, source/shader hashes, and commands are retained in
`benchmark_artifacts/performance/stdlib-gpu-20260929/mixed-enum-layout-fix/`.
Repeat the large comparison from the worktree root with preserved snapshots:

```bash
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/parser-workspace-fix/measure_pair.py 4000000 mixed-enum-layout --previous-shaders factory-receiver-validated-shaders --fixed-shaders mixed-enum-layout-validated-shaders
```

## Match arm scheduling fix

The match scheduling snapshot has shader digest `801026615965cd3d`. Only
`codegen/lir/semantic/scatter.spv` changes from the mixed enum layout snapshot,
growing from 321,824 to 322,536 bytes. The same seventeen shader binaries differ
from c37d38b; the 512 KiB shader size guard remains enforced.

A compound final match arm can share the match's closing token boundary.
Its result store, branch, and closing marker previously sorted after the
match's trap, merge, result read, and consuming local store. The materializer
now orders arm completion before match completion and the consuming effect.
Assignment of a match result uses that same completion boundary. SSA validation
remains enabled. No Rust production code, compiler IR, extraction, proofs, or
native ABI changes are part of this repair.

Three enabled runtime regressions check the seven-line comparison reproduction,
two- and four-payload compound logical arms, and match results used in locals,
direct returns, arithmetic arms, and assignments. Empty variants and matching
and nonmatching payloads execute. A false operand guards division by zero.
All three regressions fail with SSA reason 104 under the previous shaders and
execute under the fix on the same binary. The adjacent suites pass **68 tests**,
including the foundation's 138-entry executable gate. Imported method parameter
validation remains dependency 70; this check covers GPU compilation and native
execution on x86_64 Linux.

The existing `lanius_perf` interleaved driver recompiles three **5 MB** programs
five times per version, with alternating request order. A representative input
has 159,914 physical lines and 154,190 nonblank code lines. It clears compiled
project results before each request, and every timed job creates zero new GPU
buffers, bind groups, or pipelines. All thirty emitted programs pass the
expected stdout and exit contracts, and all fifteen paired native hashes match.

The real imported boolean program uses the existing entry rebuild harness:
four alternating process pairs, three warmups and ten timed rebuilds each.
Dependencies remain cached. Its eighty timed compilations succeed, and all
eight final process outputs print `3` and exit zero.

| Regression case | Previous enum layout fix | With match scheduling fix | Change |
| --- | ---: | ---: | ---: |
| 5 MB full recompiles, interleaved | 248.104 ms | 249.077 ms | -0.12% median paired ratio |
| Imported boolean window, entry rebuild | 21.628 ms | 21.689 ms | +0.28% pooled median |

The paired ratio summarizes each before/after request pair; the two pooled
medians summarize separate distributions, so their difference can have a
different sign. Neither comparison crosses the 5% investigation threshold.
These observations do not establish identical performance or a general
speedup. The desktop GPU is shared, and all samples are retained. The imported
harness checks each process's final output; it does not execute intermediate
timed outputs or establish zero resource creation for those jobs. This follow-up
adds no fresh cross-compiler ratios; the size sweep above still records the
shortfall against the broad 10× target.

Raw timings, three canonical results, executable validation records, the
scheduling-only patch, source/shader hashes, and commands are retained under
`benchmark_artifacts/performance/stdlib-gpu-20260929/match-arm-schedule-fix/`.
Repeat the large comparison from the worktree root with preserved snapshots:

```bash
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/parser-workspace-fix/measure_pair.py 5000000 match-arm-schedule --previous-shaders mixed-enum-layout-validated-shaders --fixed-shaders match-arm-schedule-validated-shaders
```

## Imported method signatures and empty results

The method/empty-result shader digest is `1398ae75ba780012`. Seven SPIR-V binaries
change from the match scheduling snapshot: three interface export passes, the
free-call and method projection passes, dependency argument validation, and the
checked call artifact pass. There are still 713 shader binaries. The maximum
is 522,600 bytes, and the 512 KiB size guard remains enforced. The x86 emitter
and all IR record layouts are unchanged.

Public methods now export typed parameter members linked by stable method
symbols and source ordinals. Imported calls reject wrong scalar and nominal
arguments. Static constructors retain their first typed parameter; syntactic
self and &self are implicit. A typed receiver can be supplied explicitly in a
qualified call or consumed by a dotted call after its type matches the receiver.
Concrete generic enum arguments from nested factory results use their checked
type argument references even when they have no annotation subtree.

Adding these signatures exposed the existing empty `RangeFull` failure after
unrelated interface growth. Dependency projection now proves a monomorphic
struct has no fields or generic parameters while its complete page is active.
Nominal type checks retain the declaration reference, and the runtime artifact
uses the existing zero-word unit representation. An unknown aggregate width
does not qualify. Neither the compiler IR layout nor the native ABI changes.

The focused and adjacent suites pass **82 tests**, including the foundation's
138-entry executable gate. Valid multi-parameter static, borrowed, and typed
receiver calls execute; wrong arguments in each position and unrelated nominal
types are rejected. Both existing empty-result growth reproductions execute,
and assigning their result to another struct or i32 still fails type checking.
Three new regression tests fail under the previous shaders on the same host
binary: invalid method arguments compile there, and the empty-result reproduction
fails with `LNC0017`. Dependencies 70 and 38 are resolved for the documented
concrete signatures and monomorphic empty results. General generic body
specialization remains unavailable.

The existing `lanius_perf` interleaved driver measures three **5 MB** programs,
with five full recompiles per version and alternating request order. A
representative input has 154,190 nonblank code lines. Compiled project results
are cleared before each timed request, and each timed job creates zero new GPU
buffers, bind groups, or pipelines. All thirty emitted executables pass their
exact stdout and zero-exit contracts; all fifteen paired native hashes match.

The imported boolean program uses the existing entry rebuild harness: four
alternating process pairs, three warmups and ten samples each. All eighty timed
rebuilds succeed. The eight final emitted programs each print `3` and exit zero.
Dependencies remain cached; intermediate timed outputs are not executed and
resource creation is not instrumented by this harness.

| Regression case | Previous match scheduling fix | With method and empty-result fixes | Change |
| --- | ---: | ---: | ---: |
| 5 MB full recompiles, interleaved | 232.548 ms | 229.419 ms | -1.34% median paired ratio |
| Imported boolean window, entry rebuild | 21.536 ms | 20.911 ms | -2.90% pooled median |

Neither comparison crosses the 5% investigation threshold. These are GPU
compilation and native execution checks on Linux x86_64; they do not establish
GPU device execution support. The shared desktop GPU and ambient shader cache
can affect timings. All samples are retained. No fresh external compiler ratio
is claimed; the earlier 5 MB sweep still misses 10× against Zig and TCC.

Raw timings, three validated canonical results, executable validation, source
and shader hashes, the method/empty-result patch, and commands are retained in
`benchmark_artifacts/performance/stdlib-gpu-20260929/method-parameters-fix/`.
Each command stays below two minutes. Reproduce the large comparison with:

```bash
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/parser-workspace-fix/measure_pair.py 5000000 method-parameters --previous-shaders match-arm-schedule-validated-shaders --fixed-shaders method-parameters-validated-shaders
```

## Generic enum tag predicates: latest measured snapshot

The validated shader digest is `efa9a254987c7afa`. Two existing SPIR-V binaries
change from `1398ae75ba780012` (semantic count and scatter), and two value-use
passes are added, giving 715 binaries. The maximum remains 522,600 bytes and
the 512 KiB size guard remains enforced. The host graph allocates one private
u32 table per token slot and records the two passes before counting LIR rows.
The count uniform uses an existing reserved word for token capacity. Compiler
IR records, extraction, formal proofs, and the x86 ABI are unchanged.

Unused match payloads no longer emit loads, including named and wildcard
bindings. Generic enum predicates read the parameter's address and discriminant
without guessing the payload width. Used symbolic payloads and offsets after
unknown-width payloads still reject with `LNC0017`. The previous compiler and
shaders reject the original imported `is_some<T>` reproduction at opcode 8;
the fix emits an executable that exits zero.

The final selected suites pass **87 tests**, including the foundation's expanded
**139-entry executable gate** and the actual Option wildcard bodies. The pending
nominal rejection check now runs only after its valid construction case passes.
One ignored test tracks imported caller-local nominal construction (dependency
76), whose eight-line Pair reproduction still fails type checking. Imported
Option predicates execute with bool, u8, u32, i32, and f32; their actual bodies
also execute with two-word and four-word payloads in a single source unit.
The actual Result tag bodies execute with independently sized payloads in
isolation. Complete generic Result payload operations still need specialization.
The boolean window program now uses generic predicates, slice mutation, and
saturating arithmetic, prints `3`, and exits zero. GPU device execution is not
claimed; these are GPU compilation and Linux x86_64 execution checks.

The existing `lanius_perf` generator, daemon, priming, cache clearing, and timing
helpers compare three 5 MB programs (154,190 code lines for a representative
input). Each version makes fifteen full recompiles in alternating pairs using
its own preserved host binary and shaders. Each timed job creates zero new
buffers, bind groups, or pipelines. All thirty outputs execute with exact
expected stdout and zero exit; every before/after native hash pair matches.

The existing stdlib example harness also measures eighty imported entry
rebuilds in four alternating process pairs, with three warmups and ten measured
rebuilds each. The control entry is identical and omits the two new predicate
calls; the previous stdlib snapshot omits their definitions because its compiler
cannot lower them. The fixed stdlib includes them. Dependencies remain cached.
All eight final outputs print `3` and exit zero; intermediate timed outputs are
not executed and per-job resource creation is not instrumented by this harness.

| Regression case | Previous compiler and shaders | With tag predicate fix | Change |
| --- | ---: | ---: | ---: |
| 5 MB full recompiles, interleaved | 188.253 ms | 185.530 ms | -0.89% median paired ratio |
| Imported boolean window control, entry rebuild | 21.198 ms | 21.011 ms | -0.88% pooled median |

Neither comparison crosses the 5% investigation threshold. The shared desktop
GPU and ambient shader cache can affect timing. No samples were discarded and
no fresh cross-compiler ratio is claimed. The earlier larger-input comparison
still falls below 10× against Zig, and TCC remains faster.

Three canonical results, raw logs, source and shader hashes, exact control
inputs, the six-file GPU fix patch, and commands are retained under
`benchmark_artifacts/performance/stdlib-gpu-20260929/generic-enum-tag-fix/`.
The previous materializer reconstructed for that patch matches the source hash
retained with the earlier match scheduling fix. After preparing the preserved
binaries and shader sets, run from the worktree root:

```bash
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/generic-enum-tag-fix/measure_pair.py 5000000 generic-enum-tag
timeout 110s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/generic-enum-tag-fix/measure_imported.py
```

## Original standard 1 MB benchmark

This uses the existing `tools/lanius_perf.py run-lanius --preset single-file-1mb`
workflow, targeting x86_64 in `daemon_warm_workspace` mode. The frozen
`pareas-common-subset` corpus has 20 distinct measured programs, seeds 20–39,
with seed 19 as primer. Each Lanius input is exactly 1,000,000 bytes, about
30,000 source lines and 1,100 reachable functions. Other languages use the
same generated program structure and output contract; their source byte counts
differ slightly.

The daemon starts before timing. GPU buffers, bind groups, and pipelines are
preallocated. Project compiled results are cleared before every measurement,
and no compiled unit results are reused. The runner verified that all measured
requests created zero new GPU buffers, bind groups, or pipelines. Timings below
include source loading, compilation, output writing, and the request round trip.
They exclude daemon startup and execution of the emitted program.

Two before/after pairs ran in current/baseline, then baseline/current order.
Every run measures all 20 programs. The medians pooled across 40 samples per
shader version are **34.317 ms baseline and 33.895 ms current**, a **1.23% decrease**.
The individual run medians are:

| Pair | Before fixes | With fixes | Change |
| --- | ---: | ---: | ---: |
| First | 33.910 ms | 33.685 ms | -0.66% |
| Repeat | 34.631 ms | 34.042 ms | -1.70% |

All 80 emitted Lanius executables passed the generator's stdout and exit-status
checks. Before/after native artifact hashes also matched for every seed. These
measurements establish no observed regression; the small reduction is not a
general speedup claim.

### Fresh debug compilation comparison

The existing `tools/run_compiler_stress_matrix.py` command templates, timing
function, source mapper, and executable validator measured only its unoptimized
lanes. A retained short driver calls those helpers on the standard runner's
generated corpus. All 100 compiler/seed combinations ran in the existing
randomized order, divided into four bounded commands. Every emitted executable
passed its generated output contract. CPU comparison runs were sequential and
ran between the two Lanius pairs.

Here, debug compilation means **unoptimized output with debug symbols disabled**:
GCC/G++ use `-O0 -g0`, Rust uses `opt-level=0`, `debuginfo=0`, and 16 frontend
threads, and Zig uses `Debug -fstrip`. Compiler binaries use their normal
optimized builds; Lanius uses a release compiler. These are fresh measurements
on an AMD Ryzen 9 5950X with an RTX 3090, rather than the retained August results.

| Compiler | Configuration | Samples | Median wall time | Other compiler time / Lanius time |
| --- | --- | ---: | ---: | ---: |
| Lanius GPU compiler | Warm daemon, x86_64 | 40 | 33.895 ms | 1.00× |
| GCC 13.3.0 | `-O0 -g0` | 20 | 1,228.973 ms | 36.26× |
| G++ 13.3.0 | `-O0 -g0` | 20 | 1,407.015 ms | 41.51× |
| Rust 1.99.0-nightly | `opt-level=0`, 16 frontend threads | 20 | 1,126.161 ms | 33.23× |
| Zig 0.16.0 | `Debug -fstrip` | 20 | 477.491 ms | 14.09× |
| TCC 0.9.27 | Default | 20 | 18.080 ms | 0.53× |

The 10× target is met against GCC, G++, Rust, and Zig in this benchmark mode.
TCC takes about half Lanius's time. This does not establish a 10× result for cold
compiler startup, debug-symbol generation, other GPUs, or other source shapes.

### Reproduction and retained results

After preparing the shared build target and shader directories described below,
point `target/release` at `stdlib-perf/build/release`: the standard runner expects
the compiler at `target/release/laniusc`. Then run from the worktree root:

```bash
export CARGO_INCREMENTAL=0 CARGO_PROFILE_RELEASE_DEBUG=0
export CARGO_TARGET_DIR="$PWD/target/stdlib-perf/build"
timeout 110s python3 tools/lanius_perf.py run-lanius \
  --preset single-file-1mb --target x86_64 \
  --modes daemon_warm_workspace --skip-profile \
  --startup-timeout 45 --job-timeout 45 \
  --output target/stdlib-perf/canonical/current-1mb.json
python3 benchmark_artifacts/performance/stdlib-gpu-20260929/canonical-1mb/validate_run.py \
  target/stdlib-perf/canonical/current-1mb.json
```

Validate each run's executables before the next run overwrites them. Switch the
shared shader root between `baseline-shaders` and `option-bool-validated-shaders`
for the original before/after runs and restore `current-shaders` afterward. Check that the
reported shader digests are `98ff5ae39fcec0c5` and `8a2d0eab0280d053`, respectively.

The retained `canonical-1mb/measure_external.py` calls the existing matrix helpers.
With a fresh `target/stdlib-perf/canonical/external` directory and the generated
corpus above, invoke it four times under `timeout 110s`, with arguments `0 25`,
`25 50`, `50 75`, and `75 100`. It saves samples after each validated program and
skips completed samples when resuming. Do not reuse prior samples for a fresh
measurement.

Five canonical performance result documents, raw timings, exact commands,
compiler versions, source/output hashes, output validation records, and the
summary are retained in
`benchmark_artifacts/performance/stdlib-gpu-20260929/canonical-1mb/`.

## Focused regression method

- NVIDIA RTX 3090, driver 595.91.07; Linux 7.0.0-34-generic.
- Rust 1.99.0-nightly (87e5904f5), Slang 2026.2, wgpu 29.0.3.
- Release optimization, debug information disabled, Cargo incremental compilation
  disabled. No shader optimization or validation settings were changed.
- The Rust compiler implementation is unchanged by this patch. Each comparison
  uses identical benchmark binaries with two separately compiled shader sets.
  The compiler reads SPIR-V and reflection files from disk in release builds;
  copying binaries alone would not isolate the versions.
- There are 713 shaders in each set. Nine SPIR-V binaries differ; their sizes and
  hashes are recorded in `changed-shaders.tsv`. Initial builds that reused the
  wrong shader set were discarded before measurements began. This section
  describes the original shader snapshot; the twelve-shader pre-parser snapshot
  sixteen-shader parser snapshot, and latest seventeen-shader snapshot are
  documented in the follow-up checks above.
- Four paired processes per version, alternating baseline/current and
  current/baseline. Each process performs three warmups and ten measured runs:
  **40 measured invocations per version per case, 720 across nine comparisons**.
- Timing includes the selected compilation API through completed x86 output.
  Compiler construction, warmups, and execution of the emitted program are
  excluded. Each process executes its emitted ELF and checks exit status and
  expected stdout. Synthetic cases use the existing generator's output oracle.
- The existing synthetic runner exposes the mean of its ten measured runs; the
  table uses the median of four process means. The entry harness exposes every
  sample and a process median; the table uses the median of four process medians.
- `rebuild` cases copy the entry into a private temporary file and change its
  modification time before each timed invocation. This forces an entry unit
  cache miss while retaining compiled dependencies and GPU workspace capacity.
  Repository sources are not modified. The cached case is listed explicitly.
- Runs were sequential on the desktop GPU. Process-to-process variation and the
  baseline's first arithmetic outlier are retained in the raw results.

## Results

Negative changes indicate shorter compilation time. Times are milliseconds.

| Case | Baseline | With fixes | Change |
| --- | ---: | ---: | ---: |
| Arithmetic and branches, 8 KB | 14.398 | 13.817 | -4.03% |
| Arithmetic and branches, 32 KB | 14.864 | 14.290 | -3.86% |
| Arithmetic and branches, 256 KB | 22.422 | 22.029 | -1.76% |
| Function-call stress, 32 KB | 14.473 | 14.749 | +1.91% |
| Local generic enum and scalar match | 10.890 | 10.524 | -3.37% |
| Small function-call program | 10.942 | 10.870 | -0.66% |
| Imported numeric/byte/range/slice program, cached units | 4.043 | 4.071 | +0.69% |
| Same imported program, entry rebuild | 20.478 | 20.540 | +0.30% |
| Imported generic enum plus scalar argument, entry rebuild | 17.770 | 18.024 | +1.44% |

The largest increase in these focused cases is **1.91%, or 0.276 ms**, for the
function-call stress input. Small differences here should not be treated as
established speedups.

All nine comparisons emitted programs that passed their output contracts on
both versions. The import rebuild cases exercise real recompilation: the
numeric/byte/range/slice program takes about 20.5 ms compared with about 4 ms
when compiled units are reused.

## Newly executable cases and excluded input

These cases are outside the paired timing table because the baseline cannot
execute them successfully:

| Case | Baseline | With fixes |
| --- | --- | --- |
| Concrete generic enum return, including `Some(false)` | Native backend rejects LIR opcode 9 | Executes correctly; warmed median 10.163 ms |
| Complete `Option<bool>` methods and state-pair fixture | Native backend rejects LIR opcode 9 | Executes correctly; entry rebuild median 20.987 ms |
| Boolean window checksum real program | Native backend rejects LIR opcode 9 | Prints `3`; entry rebuild median 28.098 ms |

These current-only timings come from one process with three warmups and ten
measured runs. They establish executable behavior and a measured current cost;
there is no baseline speed ratio for these cases.

The additional 64-enum layout stress fixture is rejected by both versions with
`LNC0057` during target generation. Its source and diagnostics are retained as
a compiler dependency. It contributes no successful performance result. The
paired generic comparison uses the existing supported scalar-match fixture.

## Reproduce and retain the check

The benchmark is `examples/stdlib_gpu_perf.rs`. The paired driver is
`tools/run_stdlib_gpu_perf.sh`. Keep each command bounded with `timeout 110s`;
the driver runs one case at a time and applies a timeout to each child process.

Prepare `target/stdlib-perf/results` with:

1. A source snapshot of c37d38b and the current shader sources. Use one shared
   `CARGO_TARGET_DIR` to reuse dependencies and save disk space.
2. Separately compiled `baseline-shaders` and `current-shaders` directories,
   containing their `.spv`, `.reflect.json`, and `artifacts.env` files. Force the
   shader build script to rerun when switching source snapshots; inspect the
   resulting shader hashes before measuring.
3. Identical release binaries named `baseline-gpu-compile-bench` and
   `current-gpu-compile-bench`, plus identical copies of the entry harness named
   `baseline-stdlib-gpu-perf` and `current-stdlib-gpu-perf`.
4. A symlink from the binaries' build-time shader artifact root to the current
   shader directory. The driver switches this link for each child process and
   restores the current shader set on exit. Run cases sequentially.

Build commands use `CARGO_INCREMENTAL=0 CARGO_PROFILE_RELEASE_DEBUG=0`,
`cargo build --locked --release --workspace --bin gpu_compile_bench
--example stdlib_gpu_perf`, and the same absolute `CARGO_TARGET_DIR` for both
snapshots. Build the identical harness against the shared compiler code.

Example commands from the worktree root, after preparation:

```bash
timeout 110s tools/run_stdlib_gpu_perf.sh target/stdlib-perf/results \
  mixed-256k synthetic --source mixed --target-bytes 262144 --allow-large

LANIUS_PERF_REBUILD_ENTRY=1 timeout 110s tools/run_stdlib_gpu_perf.sh \
  target/stdlib-perf/results portable-window-rebuild entry \
  "$PWD/sample_programs/portable_window_checksum.lani" "$PWD/stdlib" \
  "$PWD/sample_programs/portable_window_checksum.stdout"

LANIUS_PERF_REBUILD_ENTRY=1 timeout 110s tools/run_stdlib_gpu_perf.sh \
  target/stdlib-perf/results imported-generic-rebuild entry \
  "$PWD/tests/fixtures/stdlib_foundation/repro_imported_generic_enum_construct_only.lani" \
  "$PWD/tests/fixtures/stdlib_foundation/repro_generic_enum_only_root" -
```

For subsequent GPU fixes, repeat the arithmetic, generic, and import rebuild
cases against the previous shader version. Investigate a repeatable increase
above 5%; keep executable output checks enabled. This is a measured regression
check, rather than a noisy wall-clock assertion in the ordinary test suite.

Raw measurements, summary ranges, shader hashes, source hashes, and the exact
pending GPU patch are in
`benchmark_artifacts/performance/stdlib-gpu-20260929/`. Build artifacts remain in
the ignored `target/` directory, approximately 2.3 GB including the shared build,
the generated size-sweep corpora, and executable benchmark outputs.

## Limits

This measures the GPU compiler producing native x86 programs. User-program GPU
execution, cold startup, other GPU models, and earlier stdlib compiler patches
remain unmeasured here. The 64-enum target-generation failure remains open.

## Scoped generic fields and descriptor stores: 2026-10-01

The existing single-file-1mb runner measured the scoped field checkpoint with shader
digest 88fe9f6cd1685780. All twenty generated executables passed the existing
output validator; source SHA-256 hashes match the 2026-09-30 run at every seed.

| Measurement | 2026-09-30 | 2026-10-01 | Change |
| --- | ---: | ---: | ---: |
| Compiler median | 36.011 ms | 37.580 ms | +4.36% |
| Wall median | 39.069 ms | 40.501 ms | +3.67% |

This is one follow-up run without a same-session control. It does not isolate
the compiler change from machine conditions and does not establish performance
for large generic graphs or imported body readback/specialization. The retained
GCC, G++, Rust, and Zig debug-mode medians remain over 10 times this wall median;
those CPU measurements were not rerun. TCC remains faster.

Semantic scatter is 267,900 bytes under minimum Slang optimization. The largest
shader artifact is 523,396 bytes; the 524,288-byte guard remains enforced.

The runner wrote all twenty measurements before its catalogue generation
failed on an auxiliary JSON list. Executable validation then completed
successfully. The saved result document, validation records, source/output
hashes, and postprocessing failure log are under
benchmark_artifacts/performance/stdlib-gpu-20261001/. The validation list uses
a .txt suffix to avoid adding another noncanonical JSON document to that
catalogue. No measurement rerun was needed.

The subsequent structural replay, generated-application, nested-constructor,
enum-payload, nested-slice, generated-receiver, and imported record literal
checkpoints have executable regression coverage in
[compiler generics](compiler-generic-types.md). This includes compound slices,
composed Option/Result calls, nested call-result indexing, compiler-generated
field and enum payload types, five-argument imported receivers, and named to
anonymous workspace transitions. Their performance has not been measured.

Generic claim emission now uses the repository's per-shader minimum Slang
optimization policy after projected member lookup exceeded the artifact guard
under default optimization. Its current artifact is 111,384 bytes. The build
still enforces the 524,288-byte guard; this is a size check, not timing evidence.

The imported generic field read/write checkpoint also remains unmeasured.
It executes mixed scalar, descriptor, record, and array fields, including
multiword prefixes and local/imported/local member chains. Its new native
member range pass runs only when member expressions are present. Splitting
that pass from width production keeps both below the existing shader size
guard; this does not establish compilation latency or throughput. The current
artifact digest is `926af4b40ee020ca` across 729 shaders.
