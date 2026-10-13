# Structural receivers and native storage

Executable checkpoint, 2026-10-11. The GPU compiler emits x86_64 Linux programs;
these tests do not establish user-program GPU execution.

## Evidence

`verification.json` indexes 23 distinct checks: 18 native integration tests,
two library tests using the physical GPU, and three host graph checks. The final
eleven-test structural suite and five library checks ran after both method
selection repairs. The other seven native generic regressions ran earlier in
the same integration. Each accepted run has its own binary hash and deduplicated
source/shader manifests; every run reports unchanged sources and artifacts.

The native programs check storage identity after reassignment, owned copies,
argument evaluation order, reference depth, imported/local method ranking,
unused receiver arity, arrays/slices/empty arrays, iteration, and bounds exits.
Generic regressions include local/imported compositions, 32 parameters, and
nested Result call chains. The imported scalar test executes the receiver and
following argument, including negative values, with no local implementations
in the caller.

The library tests check the complete five-word parameter record, ambiguity in
both dependency-page orders, recovery after removing a competing page, graph
inputs, and resource lifetimes. Two extra host checks for performance-document
validation are recorded separately from the 23 compiler checks.

## Repairs and failure classification

- Compact parameters carry full checked type references, including unused
  implicit `self` and `&self`. Native argument layout and template closure use
  those same references.
- References retain one-word runtime shape. Referent bounds do not expand a
  reference into an array/slice descriptor. Borrowed array views alias original
  storage; owned array arguments keep their copies.
- Indexed elements of temporary slice descriptors can name backing storage.
  This does not make the temporary descriptor itself an addressable place.
- Dotted calls use the member leaf as callee, preserving nested receiver calls.
  Successful inherent implementation validation publishes its accepted status.
- An empty local method inventory reads no lookup buckets. Previously it could
  read reused workspace storage and invalidate a valid imported candidate.
- Finalized ambiguity/invalid diagnostics remain owned by candidate selection;
  late signature checking no longer replaces them with an unresolved-name error.

The preserved ambiguity failures distinguish the initial positive-control
rejection from the later diagnostic overwrite. The physical parameter test's
failure came from reading two old four-word records; the current record is five
words. Its repair reads and asserts both complete records. Temporary diagnostic
readback code was removed before the final accepted runs.

## Performance

`performance-comparison.json` summarizes paired baseline/current/current/baseline
runs of the existing `stdlib_gpu_perf` tool: three warmups, ten measurements per
run, matching preserved binaries/shaders, and eight successful executable output
checks. Pooled medians increased 2.6% for 32 trait operands and 2.4% for the
ordinary 32-parameter program. `perf_structural.py` retains the runner.

`current-1mb.json` is the existing canonical twenty-program 1 MB workload.
Compiler median: 38.474 ms; wall median: 41.380 ms. Its twenty executable output
checks are in `current-1mb.validation.json`. The command wrote its completed
result, then failed while cataloging an unrelated JSON array. The subsequent
validator repair rejects non-object results through the catalog's existing
invalid-result path. Compiler sources did not change during the measurements.

There is no matching preserved CLI baseline for the 1 MB result. These warm
measurements do not establish controlled cold performance, generic graph scaling,
or the cross-compiler 10x target.

## Remaining scope

Generic trait implementation prerequisites, generic trait methods/method bounds,
constant trait operands, full primitive widths, and typed full-width constant
identity/forwarding remain unfinished. Direct temporary borrows and
variant-payload places without a storage recipe reject explicitly. References
still require caller-managed lifetimes; static escape checking is not provided.

Run focused tests with the usual release native integration or library binary.
`verify.py LABEL BINARY TEST...` records source/shader stability and fails if the
command or either stability check fails. Use a fresh label to preserve prior
evidence. All build/test/benchmark commands in this checkpoint were bounded to
less than two minutes.
