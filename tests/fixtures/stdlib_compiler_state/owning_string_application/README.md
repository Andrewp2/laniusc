# Owning String helper replay-layout dependency

The original `alloc::clone::destroy_vec_iter<String>` implementation can reach
`LNC0047`, `GenericInstantiationBoundary detail=6`, when its caller does not
materialize the cursor's finish error. This remains a compiler dependency.
The accepted library implementation uses empty-owner recovery and destruction
after draining; no compiler fix is claimed.

## Retained sources

- [`01_vec_string.lani`](01_vec_string.lani) is the minimal caller: two distinct
  String allocations enter one Vec, the cursor yields and destroys one, and
  `destroy_vec_iter<String>` destroys the remainder. It never calls `try_finish`
  or projects `IntoIterError` itself. No TreeSet, Words record, Buffer, or I/O
  operation is needed to reproduce the rejection.
- [`06_vec_string_finish_projection.lani`](06_vec_string_finish_projection.lani)
  adds an explicitly typed `Option<alloc::vec::IntoIterError>` local, unwraps it,
  and matches `Remaining(count)` before calling the same cleanup helper. The
  refused finish preserves the remaining owner, which the helper then destroys.
- [`original_clone.lani`](original_clone.lani) is the exact historical library
  source from commit `f867a59606127508110208986318bb5eaaa82192`. Its Git blob is
  `d714e4e312b6500f2c9bdf2b615089db06deafc5`. Both cursor helpers end with
  `assert(owner.try_finish().is_none())`.

The unused TreeSet, transfer, Words, and Buffer reduction candidates are retained
locally under
`target/stdlib-work/owning-iterators-admission/reduction-candidates/` as
`02_tree_string.lani`, `03_transfer_string.lani`, `04_words_record.lani`, and
`05_words_buffer.lani`. They are ignored exploratory sources, excluded from
accepted gate counts.

## Captured sequence

All listed probe outcomes are compilation outcomes. These CLI probes do not
establish strict ELF validation or native execution.

| Source and helper state | Recorded outcome | Admission artifact |
| --- | --- | --- |
| Full `unique_words` application, original helper | `LNC0047`, detail 6 | `unique-words-layout.log` |
| Minimal 01, original helper | Compiler exit 1, same diagnostic | `probe-01.log` |
| Minimal 01, typed finish local inside helper | Compiler exit 1, same diagnostic | `probe-01-fixed.log`, `clone-typed-finish-local.lani` |
| Caller projection control 06, typed finish local inside helper | Compiler exit 0 | `probe-06.log`, `probe-06.elf` |
| Minimal 01, empty-owner recovery helper | Compiler exit 0 | `probe-01-recovery.log`, `probe-01-recovery.elf` |
| Caller projection control 06, separately staged byte-original helper | Compiler exit 0 | `probe-06-original.log`, `probe-06-original.elf` |

These files live under `target/stdlib-work/owning-iterators-admission/`. The empty
success logs accompany emitted ELF files; they are not native execution logs.
The first 06 probe ran after the typed-local helper retry and before the recovery
change. Admission of 06 against the byte-original helper was verified later in a
separately staged historical stdlib. Its empty log and emitted ELF are
`probe-06-original.log` and `probe-06-original.elf`; the outcome is distinct from
`probe-06.log` and is also compile-only.
The original application source is `unique-words-layout-original.lani` there.
`unique-words-layout-debug.log` retains the specialization diagnostic. Earlier
application captures, `unique-words-unresolved-original.lani` and
`unique-words-unresolved.log`, precede the correction from `InvalidUtf8(_)` to a
named payload binding and are separate from the replay-layout result above.

The debug capture contains a replay argument with identity
`Public([0, 0, 55])`, `words: None`, `local_replay: None`, and width witness
`4294967295`. The neighboring catalog declarations are Vec and IntoIter, and
`IntoIterError` is the suspected missing nominal. The caller-projection control
supports that diagnosis; it does not establish that arbitrary foreign enum
layouts are now available to replay.

The diagnostic is reported at `alloc/allocator.lani:3:1`, with this note:

> a replay argument has no complete GPU native layout; its defining nominal
> payloads or a retained checked width witness are required

## Library resolution

Adding an explicitly typed `Option<IntoIterError>` local inside each generic
helper did not admit minimal 01. The final helpers keep the same front-to-back
drain and exactly one `Destroy<T>` call for each remaining item, then perform:

```lanius
let empty: alloc::vec::Vec<T> = owner.take_remaining();
assert(empty.is_empty());
empty.destroy();
```

The deque helper uses the corresponding Deque owner. Recovery disarms the cursor
and transfers the empty backing allocation; destruction then releases it. This
uses the canonical collection ownership operations and preserves the helper API.
It avoids the missing finish-error replay layout without changing the compiler,
IR, ABI, passes, resources, or proofs. General `try_finish` remains public and
retains its nonempty-rejection contract.

The dedicated runtime regression is
[`helper_only_strings.lani`](../../stdlib_foundation/owning_iterators/helper_only_strings.lani),
registered as
`imported_string_cursor_helpers_cleanup_without_caller_finish_result_projection`
in [`stdlib_owning_iterator_execution.rs`](../../../stdlib_owning_iterator_execution.rs).
It passed alongside the typed ownership contracts in `ownership-final.log`
(8.51 s). The helper-only case checks eight allocation generations and the typed
contracts check 36, with exact cleanup identities and order. These results apply
to the recovery helpers; they do not establish admission of the original helper.

The full application then passed in `unique-words.log` (8.78 s): one strict ELF,
79 observed representative allocation-denial positions, and 126 native cases.
Its 4096-word scale workload checks correctness and does not establish compiler
throughput performance. This application admission also uses the recovery helper.

The parent assembles final admission manifests named `source.sha256` and
`binary.sha256` in the admission directory after source freeze. Those final
manifests are distinct from the historical clone Git blob recorded above.

## Exact historical CLI

From the repository root, the original minimal probe used this bounded command
with the original helper in `stdlib/alloc/clone.lani`:

```sh
RUST_MIN_STACK=16777216 LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 tests/fixtures/stdlib_compiler_state/owning_string_application/01_vec_string.lani -o target/stdlib-work/owning-iterators-admission/probe-01.elf > target/stdlib-work/owning-iterators-admission/probe-01.log 2>&1
```

The typed-local retry used the original minimal entry and `probe-01-fixed`
output/log names. Probe 06 then substituted
`06_vec_string_finish_projection.lani`, `probe-06.elf`, and `probe-06.log`, while
retaining that typed-local helper state. The recovery retry used the original
minimal entry and `probe-01-recovery` output/log names. There was no
`--source-root`.

The parent staged the original library state without replacing the current
stdlib, using these bounded commands in the ignored admission directory:

```sh
timeout --kill-after=2s 100s mkdir -p target/stdlib-work/owning-iterators-admission/original-stdlib
timeout --kill-after=2s 100s git archive --format=tar --output=target/stdlib-work/owning-iterators-admission/original-stdlib.tar f867a59606127508110208986318bb5eaaa82192 stdlib
timeout --kill-after=2s 100s tar -xf target/stdlib-work/owning-iterators-admission/original-stdlib.tar -C target/stdlib-work/owning-iterators-admission/original-stdlib
```

The verified original-state control then used:

```sh
RUST_MIN_STACK=16777216 LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc --stdlib-root target/stdlib-work/owning-iterators-admission/original-stdlib/stdlib --emit x86_64 tests/fixtures/stdlib_compiler_state/owning_string_application/06_vec_string_finish_projection.lani -o target/stdlib-work/owning-iterators-admission/probe-06-original.elf > target/stdlib-work/owning-iterators-admission/probe-06-original.log 2>&1
```

To repeat minimal 01 against that historical stdlib, substitute
`01_vec_string.lani`, `reproduce-01.elf`, and `reproduce-01.log` in the final
command. That additional repeat is an instruction, not another recorded probe.
The README author extracted the retained source and compared its blob identity;
the parent performed the compiler probes and historical staging reported here.
