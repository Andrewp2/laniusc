# Semantic replay and native layout prerequisites

This checkpoint records **19 passing test executions covering 17 distinct test
names** across builds 19, 20, and 23. The compound-result native test repeats in all
three builds. Six distinct host tests, six distinct physical-GPU replay/retention/
admission tests, and five distinct native execution tests are represented.
`verification.json` identifies each exact command, binary hash, category,
source/shader manifest, and any cache alias. Passing tests were not rerun to
assemble this package. No equivalence between different builds is inferred.

| Build | Recorded passes | Scope |
| --- | ---: | --- |
| 19 | 8 | Four host contracts, one GPU missing-layout replay/readback check, three native executions |
| 20 | 6 | Two GPU layout edge checks, two GPU original-recipe retention checks, two native regressions |
| 23 | 5 | Two host transport checks, one GPU recipe-admission fault/recovery test, two native controls |

## What the checks establish

A replay seed preserves closed semantic identity independently of optional native
width. Missing width is distinct from known zero, and equal semantic nodes can
refine compatible witnesses without changing the scheduling key. GPU replay
completes tested local nominal and array layouts. Its owned output vector replaces
unknown input witnesses in the native cache; a later conflicting known witness
cannot reuse that body.

The GPU edge cases check a zero-sized local nominal/array, contradictory array
width rejection, valid replay after rejection in the same compiler, and unchanged
prior owned readback. Reference and slice descriptors can retain an opaque
caller-private referent whose own width is unknown. These tests perform real GPU
replay/lowering/readback; they do not themselves execute the emitted replay object.
Known opaque nominal widths remain witnesses when payloads are unavailable, so
this is not proof that arbitrary supplied nominal widths are independently derived.

Original public/private nominal recipes retain complete symbolic record fields,
ordered enum variants and payloads, and exact owner/snapshot identity. Definitions
with no calls or predicates remain represented. Replay reuses the original
symbolic recipe snapshot. The host serializes these graphs without matching types,
substituting parameters, or computing native sizes.

The build 23 GPU admission test first accepts complete recipes, then rejects an
incorrect catalog epoch, a broken group backlink, and a valid sibling parameter
used outside its lexical owner. It checks exact GPU failure receipts and recovery
on a fresh valid catalog. Both catalog and recipe admission must succeed before
program evidence becomes available. The native controls still execute imported
bound methods and independently copied compound results after admission is added.
This establishes recipe transport/admission, not the missing foreign-layout consumer.

Native tests compile on the physical GPU, emit x86_64 Linux programs and execute
them. The caller-private native relay and zero-size controls complement the GPU
readback cases; none establishes user-program GPU execution.

## Build and cache provenance

Each build has a distinct compiler-library binary and source manifest. Builds 19
and 20 share their shader manifest; build 23 has its own artifact snapshot. Compiler
library GPU tests used hardlinks under the native integration test basename.
`cache-provenance/build-{19,20,23}.json` records the original path, alias,
`same_inode: true`, and hash at creation. Later builds replace the original path,
so that recorded relation is not a claim about today's inode at that path.
Native integration binaries are separate executables with their own recorded hashes.

These aliases reuse the cache condition observed in the preceding
`generic-trait-methods/` checkpoint. No new file-open cache traces were collected
for builds 19, 20, and 23. The original strict initialization timeout remains unresolved;
test elapsed times do not establish cold-start or compiler-throughput performance.
Each recorded command stays below two minutes. Build 23 is the successful admission
build after intermediate integration repairs; no admission success is attributed
to the earlier builds.

## Remaining boundaries

Applying these admitted recipes to an actual foreign nominal with no width
witness remains in progress. Abstract required-member routing through `T: Trait`
and trait methods' own headers/where clauses also remain unfinished. This package
does not claim complete generics, a refreshed stdlib API acceptance run, expanded
native-width/constant coverage, or current large-workload/cross-compiler performance.
