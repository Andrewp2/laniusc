# Temporary directory execution gates

**All four native groups passed: 46 distinct finite profiles.** Acceptance was
recorded across separate commands. This counts the profiles in each accepted
group once, rather than summing executions across failed attempts and retries.

| Accepted group | Profiles | Receipt in `target/stdlib-work/` | Invocation elapsed |
| --- | ---: | --- | --- |
| `owner` | 9 | `filesystem-temp-dir-native-first.log` | 6.88 seconds, mixed four-group invocation |
| `creation_faults` | 8 | `filesystem-temp-dir-callback-retry.log` | 7.66 seconds, mixed three-group invocation |
| `cleanup_faults` | 10 | `filesystem-temp-dir-callback-retry.log` | Same invocation as the preceding row |
| `admission_entropy` | 19 | `filesystem-temp-dir-single-entropy-rule-retry.log` | 6.07 seconds, admission-only pass |

The first invocation accepted `owner`; the other three groups stopped at a
Python callback-shadowing error. Injection expectation assembly assigned a
dictionary to the callback parameter, causing `TypeError: 'dict' object is not
callable`. Its correction preserved the callback and all behavior/provenance
assertions. The next invocation accepted `creation_faults` and `cleanup_faults`
but stopped `admission_entropy` at its first collision profile: strace replaced
the first of two `getrandom` injection options with the second. The unchanged
reached-injection check rejected the real first draw. The corrected harness
uses one option to force only the first draw and binds later OS entropy to each
actual candidate; a command guard rejects duplicate syscall injection options.
The final admission-only retry passed all 19 cases. Neither 6.88 nor 7.66
seconds is an isolated passing-group timing. Source, probe and Rust driver were
unchanged by these harness corrections.

The accepted oracle SHA256 is
`4a097176ff554ce1c6b793f3541207098ce79c219310978262e3071c191c36e0`.

This fixture calls the real
`std::temp_dir::TempDir` owner. Python supplies independent filesystem fixtures,
finite syscall injection and observations, not production directory behavior.

`probe.lani` receives five little-endian u64 values: mode, name attempts, entropy
calls, parent profile and skipped-close repair role. Four 549-byte ACK snapshots
expose empty ownership, completed construction, first cleanup, and final explicit
release. Each snapshot contains 64 u64 words and a copied 37-byte name; its
header identifies actual state, fds, counters, original diagnostic, latest
cleanup and current action receipt. Borrowed generated-name storage is copied
before cleanup can release it. No hook is added to the library.

## Finite groups

| Group | Intended executable scope |
| --- | --- |
| `owner` | Nine profiles: empty cleanup, keep, real child create/write/read-by-host, nonempty cleanup retaining both descriptors, removal through the borrowed child and retry, caller-parent closure plus parent rename/replacement, external absence, active recreate rejection, explicit child close, and inactive/duplicate cleanup. |
| `admission_entropy` | Invalid limits and regular/closed/O_PATH parents; real GRND_NONBLOCK request provenance, positive partial/EINTR recovery, finite exhaustion, zero/invalid counts, EIO/EAGAIN, real file/directory/symlink collisions, candidate exhaustion and one shared entropy budget across candidates. |
| `creation_faults` | Every reached source allocation and exact reached duplicate/stat/status/mkdir/open failures. Actual mkdir success followed by failed child open retains name/parent/removal duty. A nonzero mkdir return is rejected, without inventing a created directory. |
| `cleanup_faults` | Removal EIO with both descriptors retained, explicit-closed-child retention, keep versus retry, child/parent close retirement, explicit close diagnostics, and original OpenDirectory EIO preserved alongside a later removal EPERM receipt. |

The child runs under explicit umask 0077. Successful generated directories must
actually be 0700 in the tested local fixture, not merely receive that argument.
Existing parent/sentinel/replacement/collision objects stay unchanged. Every
generated name is bound to traced entropy bytes, mkdir/open paths and cleanup
targets. Collision recovery forces the first entropy draw to the existing
zero-named object with test-only ptrace substitution; later draws use real OS
entropy. The successful name must differ, all failed candidate mkdirs must
return real EEXIST, and measured counters must agree with the bounded draws and
attempts. Candidate-exhaustion profiles repeat the single forced draw. Namespace
objects and mkdir effects are real. No recursive cleanup is supplied by
production, and no adversarial namespace or power-loss claim follows.

## Ownership and fault evidence

The oracle imports the unchanged TempFile raw ELF opcode verifier and the
archive Source full-width live-map helper. Named fallback is rejected. Verified
instruction ranges, exact per-site 0x22/0x62 allocation flags, requested lengths,
and full-width addresses are mandatory. `/proc` mappings and fd generations
are checked while each ACK holds the child alive. Final cleanup must leave no
source mapping or fd beyond stdin/stdout/stderr before process exit.

The local fd projection has no exit-based cleanup fallback. Unowned or duplicate
closes, queries through unowned descriptors, unanchored generated lookups, and
production retries of retired descriptors are rejected. A strace close error
skips the physical close. The test records that exact generation as physically
live, verifies the library's logical retirement, then performs exactly one
separately marked Q-phase raw repair. This is not a natural Linux close-error
or successful physical-close claim.

Every declared injection must be reached and marked. Faults selected from a
baseline bind the native source address, operation phase and argument shape;
source OOM also binds the complete preceding allocation request prefix. All
partial owners are released explicitly. Failed removal retains the same source
name and parent authority; normal cleanup attempts removal before either close.
Successful retry preserves the first stage/cause while the per-attempt cleanup
receipt changes. Pure keep and repeated terminal destruction perform no native
work.

Python-only controls pass **45** assertions: 17 reused source-provenance
controls, four framing controls, 11 fd/phase/IP/name checks and two callback
regressions. The latter run actual injection expectation assembly with nonempty
error/return-value rules, require the original callback to execute once with its
result, and require a callback rejection to propagate. Restoring the old
callback-shadowing pattern fails these controls. Two option-assembly controls
accept distinct syscall rules and reject the old duplicate-getrandom pattern.
Nine collision-validator controls accept recovery with one or multiple real
collisions and reject missing substitution, missing EEXIST, incorrect counters,
unexplained later injection, or a name inconsistent with the trace/entropy.
They execute no compiler or native Lanius. Scoped static diff checks and prior
Rust driver formatting also pass.

## Commands

Root serializes compilation/native execution. Run one group at a time. The
oracle stops starting cases after 75 seconds, per-checkpoint waits are 12
seconds, and the Rust oracle deadline is 90 seconds.

```sh
python3 -B tests/fixtures/stdlib_execution/temp_dir/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/temp_dir/oracle.py owner PATH_TO_ELF
cargo test --test stdlib_temp_dir_execution temp_dir_owns_real_children_and_retains_anchored_nonempty_recovery -- --exact --nocapture
```

Other exact Rust filters:

- `temp_dir_validates_preflight_and_bounds_real_entropy_and_collisions`
- `temp_dir_creation_faults_retain_every_confirmed_namespace_owner`
- `temp_dir_cleanup_preserves_first_error_and_exact_retained_resources`

Failures preserve packets, traces, mapping checkpoints and diagnostics in the
printed `/tmp/temp-dir-*` directory. Killing a child is diagnostic recovery and
cannot convert a failure into acceptance. Kept directories remain inside these
test-owned temporary roots for explicit host cleanup.
