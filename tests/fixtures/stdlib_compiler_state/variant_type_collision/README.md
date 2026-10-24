# Type annotations and same-spelled unit variants

Baseline: `3fa72ac289cee546a0014fe4e93819cfaf86646f`.
The source files in `source.sha256` preserve the two independent reports and
small controls. These are compiler regression inputs, not alternate libraries.

## Contract and diagnosis

The declaration resolver already keys declarations by module, namespace, name
and optional parent. Types use namespace 3; enum variants use value namespace 2.
Resolving a value candidate for a type-expression row must not make that row a
value expression or overwrite its checked nominal reference.

`modules/10j_consume_value_enum_units.slang` consumed all resolved value rows,
including type-expression rows. Its neighboring value status, enum-call and
finalization consumers already restrict themselves to value-expression rows.
The correction applies that same path-kind restriction before the unit-variant
consumer writes any output. Names, layouts, namespaces, imported identities and
lookup policy are unchanged.

## Retained cases and outcomes

| Input | Baseline | With value-expression guard |
| --- | --- | --- |
| `enum_collision/main.lani` | LNC0006 at the typed match | Compiles; native exit 3 |
| `enum_control/main.lani` | Compiles; native exit 3 | Compiles; native exit 3 |
| `record_collision/main.lani` | LNC0006 at `empty()` in the local typed binding | Compiles; native exit 0 |
| `record_control/main.lani` | Compiles; native exit 0 | Compiles; native exit 0 |
| `local.lani` | Not used as a baseline gate | Native exit 0, including qualified/unqualified unit values and `Result<i32, Error>` |
| `enum_collision/wrong_nominal.lani` | Not used as a baseline gate | LNC0006: different nominal enums |
| `enum_collision/wrong_variant.lani` | Not used as a baseline gate | LNC0006: unit value belongs to another enum |
| `enum_collision/variant_as_type.lani` | Not used as a baseline gate | LNC0007: a value-only variant is not a type |

The enum case comes from the independent terminal wrapping provider. Its control
changes only `Overlong::Error` to `Overlong::Reject`. Native exit 3 is the expected
payload returned by the example, not a failed assertion.

The record case reduces the directory provider's report to a local record and an
imported `Kind::Directory`. Its control changes only that variant to `Folder`.
The failure needs the typed local inside the module importing the variant; an
external qualified record return alone was a passing reduction.

`directory-original.lani` preserves the complete pre-Reader directory module.
To reproduce it, copy a stdlib source root and replace its `std/directory.lani`
with this file, then compile `directory-main.lani` using that root. The baseline
fails in its unchanged `walk` body; the guard admits compilation and native
exit 0. `directory-layout-control.lani`, the independent nine-word owner return
control, also compiles and exits 0. The provider's exact Reader-only source and
original logs are retained in
`../../stdlib_foundation/directory_return_evidence/`.

The focused Rust target is `type_checker_variant_type_collision`: four tests
cover five successful native compilations and three intentional rejections.
The existing direct, unqualified and inferred imported Ordering variant tests
also pass. All native programs have empty stdout/stderr.

## Native workload measurement

The existing `examples/stdlib_gpu_perf.rs` now verifies every emitted ELF after
stopping that iteration's compiler timer. Previously it verified only the final
ELF. Both compared drivers use the updated harness. Each process has one warmup
and three private-entry rebuilds (`LANIUS_PERF_REBUILD_ENTRY=1`).

Inputs are the existing 1,000,000-byte workload with 12,274 stdlib call sites and
its expected stdout, plus an identical frozen stdlib snapshot. Every output is
verified, has 2,171,815 ELF bytes, exits 0 and matches expected stdout exactly.

An initial chronological run measured medians 992.538 ms before and 1232.490 ms
after (+24.18%). It used the old/new shader sets in sequence, but copying the
compiler binary did not preserve its dynamically loaded shader directory.
Retain this as an uncontrolled observation, not evidence of a causal regression.

The corrected comparison pins complete shader directories with
`LANIUS_SHADER_ARTIFACT_ROOT`. An isolated current consumer compiled with the
recorded Slang flags produces byte-identical SPIR-V and reflection to the Cargo
build. Recompiling that consumer from the exact baseline commit reconstructs
the baseline set; every other shader is identical. Its metadata digest is
recomputed with the existing build algorithm and generated artifact order.
Pinned fail/pass admission reproduces LNC0006 before and native exit 3 after.

| Run order | Shader set | Three measured compiler times (ms) | Median (ms) |
| --- | --- | --- | --- |
| 1 | Before | 1331.624, 1334.753, 1318.245 | 1331.624 |
| 2 | After | 1235.131, 1211.064, 1130.256 | 1211.064 |
| 3 | After | 1251.793, 1266.268, 1307.283 | 1266.268 |
| 4 | Before | 1295.267, 1328.210, 1212.939 | 1295.267 |

The six-sample medians are 1323.2275 ms before and 1243.462 ms after (-6.03%).
The initial slowdown does not reproduce in this alternating comparison. These
sequential runs do not control machine load, clocks or temperature and do not
establish a causal speedup or a fixed performance bound.

The existing `spirv_size` analyzer reports the changed consumer at 37,187 to
37,195 fully inlined instructions and 11,542 to 11,550 own instructions (+8).
Its SPIR-V grows from 193,168 to 193,356 bytes (+188). The module instruction
counts, including declarations outside functions, are 13,619 and 13,632.

### Preserved artifacts

Local logs, compiler/drivers, frozen sources and pinned shader sets are under
`target/stdlib-work/variant-type-collision/`. The pinned runs use
`pinned-perf.sh`; admission uses `pinned-admission.sh`. Each GPU command uses
the shared lock, at most 35 seconds queued and 60 seconds executing. Source
reproduction inputs are tracked here; build artifacts are local diagnostics.

| Artifact | SHA-256 or recorded shader digest |
| --- | --- |
| Compiler binary (unchanged Rust bytes) | `51704757e738dfbf37d7ed3bc33fc976f7bf8348ab340d1f4068efbed58abfcf` |
| Both perf driver binaries | `eaf53a5a1a56e83742e87955f786011cd8b92178bb0849a991ba56d6f82e66e0` |
| Workload source | `1b7c19d0d61b15115aa3007f624ccd7cb5c29d60f3d0b99875694ec5273bfd6e` |
| Expected stdout | `ba31e3207adaaa6423ec8065fcea3784d1e66393564fbbe9fc92ac897f7dd1fe` |
| Frozen stdlib manifest | `f6f371188658e7c99a1a69037d09be678b819d8ce3cc7d929e4219a7108fd52b` |
| Before shader manifest | `c786ed84b3a5a4ac9cef32a5954249d85ba33fbbedb131608c9d0d3b069c3ede` |
| After shader manifest | `e10de684668a0ce44ffe8a1ff2f7b3ec0bc5e4f90e13432b082d15d8cefa1edd` |
| Before shader digest | `7014358a14866f13` |
| After shader digest | `a1a3dc017ab72950` |
| Before consumer SPIR-V | `b7d7ffbf14b5c6146f7e8d38a0f063ac239304f6d42cb52cd61c13da16d695ec` |
| After consumer SPIR-V | `ce7a9f5cc0e46de4c08e0d6dd8a9256b8f97593aafc142dab4e3e391c5469e78` |
