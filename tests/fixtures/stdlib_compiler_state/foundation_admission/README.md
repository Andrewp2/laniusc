# Foundation architecture admission probes

These isolated source probes inform architecture at source HEAD `5174a14d`.
They do not add production set, iterator, or buffering APIs. Compile them as
stdlib dependencies: moving an imported generic helper to a user source root
changes the experiment.

| Candidate | Question | Existing positive control |
| --- | --- | --- |
| `shared_state.lani` + `prototype/alloc/admission_state.lani` | Does a typed Map/Set facade over nongeneric owner state avoid the nested generic receiver layout boundary while reusing one current HashMap engine? | `../../stdlib_foundation/owned_sets_hash_map_control.lani` |
| `static_iter.lani` + `prototype/core/admission_static_iter.lani` | Can an imported generic iterator implementation dispatch through an explicit associated witness call? | `../../stdlib_foundation/iterator_dependency/direct_control.lani` and its imported `core/pull_probe.lani` |
| `forward.lani` + `prototype/core/admission_forward.lani` | Is an imported `Forward<W>` accepted by the current imported `core::io::write_all` when its forwarding body uses explicit associated calls? | `../../stdlib_foundation/buffered_io_dependency/direct_control.lani` and its imported `core/buffer_probe.lani` |

The controls worked in the earlier recorded investigations. Their results at
this source snapshot must be recorded independently; a timeout or unavailable
GPU lock is not a compiler rejection. No test requires the candidates to fail.

## Owner-state prototype boundaries

The state prototype contains no hash buckets, probing, allocation sizing,
insertion algorithm, or typed storage casts of its own. It uses the unchanged
`alloc::hash_map` as its only storage engine. Its typed Map/Set facades bind owner
state to one schema, and recorded key/value native widths are checked before
reconstituting a typed temporary map view. Width equality is not type identity;
the typed facade and construction convention also matter.

Exactly one facade owns each State. Temporary map views cannot escape or be
destroyed independently, mutations write every map owner field back on both
success and recoverable failure, and `destroy` writes back the closed state.
Concurrent/reentrant operations, mutation through forged fields, and externally
mixed schemas violate the probe's ownership preconditions. Returning a displaced
set key keeps that key explicit; no full generic owner-key, set algebra,
allocation-failure or aliasing contract is claimed from this small admission.

A successful admission would motivate moving these shared state operations
inside the production map engine. The temporary view bridge is not proposed as
a public erased container. If admission fails, retain the diagnostic and stop;
do not add primitive-key specializations, copied map implementations, unused
implementations, or compiler changes to make the probe appear successful.

## Bounded run

Run from the repository root. The wrapper waits at most 35 seconds for the shared
GPU lock and executes at most 60 seconds. Each compile gets 7 seconds plus a
one-second kill grace; native probe runs get half a second plus half a second
grace. Six tiny compilations and controls share this one bounded batch.

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s bash \
  tests/fixtures/stdlib_compiler_state/foundation_admission/run-admission.sh
```

Exit 75 means the lock was not acquired. Compile/run status 124 or 137 means a
timeout, not a language boundary. The batch records actual statuses rather than
declaring success when a candidate fails. A native artifact runs only after its
own compile status is zero. Inputs and compiler hashes, diagnostics, and status
ledger belong with the results; timings are not golden outputs.

The batch stages current stdlib files under
`target/stdlib-work/foundation-admission-5174a14d/stdlib/` and adds the isolated
candidate/control modules there. It never mutates production maps or helpers.
The existing marker-map control, direct iterator control, and direct forwarding
control remain the baseline. `SOURCES.sha256` records exact probe and control
source inputs. The work directory records compiler hash, source HEAD, per-case
compile logs, native output, and `results.txt`.

## Recorded results

The admission used source HEAD `5174a14d6651ce012a0f7cca1c5ca3a283ba5161` and
compiler SHA-256
`662b2ffeeb8b773bcfc57942ca4abc20f1533c856e0c466d3ed2a2953e32d9af`.

| Case | Compile exit | Native exit | Result |
| --- | --- | --- | --- |
| Shared-state direct control | 0 | 0 | Existing marker-map composition works. |
| Shared-state candidate | 0 | 0 | Typed Set/Map facades work through one unchanged HashMap engine, including duplicate-key return and a value wider than 32 bits. |
| Iterator direct control | 0 | 0 | Existing direct imported implementation works. |
| Static iterator witness | 1 | not run | `LNC0027` at `I::pull`: no concrete implementation member to route. |
| Forwarding direct control | 0 | 0 | Existing direct writer composition works. |
| Static forwarding writer | 1 | not run | `LNC0027` at `W::write`: no valid checked receiver adjustment. The outer `write_all` composition is not admitted. |

`RESULTS.txt` records the statuses. `static_iter.stderr.txt` and
`forward.stderr.txt` preserve normalized diagnostics. `SOURCES.sha256` covers
the final inputs and their imported source closure. Initial candidate literal
typing mistakes were corrected before the recorded shared-state result; these
were not architecture rejections.

The batch script exits zero when orchestration completes, even when a candidate
is rejected; inspect its status ledger. A passing small owner-state admission
does not establish complete set semantics, TreeSet, owner-key cleanup, algebra,
or fallible atomicity. No production API is added by these probes.

## Reproduce the recorded source shape

Later map factoring can change the shape of these imported dependencies. The
recorded result belongs to the base map engines, not every future revision. To
stage those exact stdlib sources without changing the current checkout:

```sh
mkdir -p target/stdlib-work/foundation-admission-base
git archive 5174a14d6651ce012a0f7cca1c5ca3a283ba5161 stdlib | \
  tar -x -C target/stdlib-work/foundation-admission-base
ADMISSION_STDLIB_ROOT=target/stdlib-work/foundation-admission-base/stdlib \
ADMISSION_SOURCE_HEAD=5174a14d6651ce012a0f7cca1c5ca3a283ba5161 \
  timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s bash \
  tests/fixtures/stdlib_compiler_state/foundation_admission/run-admission.sh
```

Use the compiler with the recorded digest for an exact compiler comparison.
The manifest retains the probe/control inputs and their imported source hashes;
check dependency hashes against the archived tree when current stdlib differs.
