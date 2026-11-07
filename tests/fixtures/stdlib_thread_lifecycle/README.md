# Canonical thread lifecycle fixtures

These fixtures target native Linux x86_64/glibc code emitted by the GPU
compiler. They test the ordinary `std::thread` library functions, independently
of the compiler's historical unbound service-8 metadata. All seven registered native execution tests pass on Linux x86_64/glibc
in 12.04 seconds. Host observer controls remain separate evidence.

- `admission.lani` starts and joins a real thread through canonical
  `std::thread`, verifies the worker's actual pthread identity and C-entry
  process context, checks local repeated-join rejection, and exercises yield
  and affinity queries. It uses no interposition shim.
- `failures.lani` uses the [shared probe](SHIM.md) around real glibc pthreads.
  It checks invalid-input admission before any host call, default and zero
  stack requests without attribute setup, actual 256 KiB and minimum stack
  extents, initialization/set/create/destroy failure order, primary plus
  secondary errors, and default-spawn error wrapping. A post-create destroy
  failure must return the actual held worker as an owned recovery value.
  A failed join must preserve that same ID and join authority until retry.
  The local second-join error must not make another host join call.
- `scheduling.lani` and `scheduling_oracle.py` exercise 13 reached syscall
  outcomes, including 11 injected cases. They check successful yield and an
  independently measured real affinity population, preserved kernel errno,
  unexpected nonzero yield results, raw affinity lengths zero/129/above-u32,
  zero masks, and exact bit counts at both ends of a 128-byte mask. Each case
  requires exactly one syscall of the expected kind; eleven observer controls
  reject extra, mistargeted or falsely reported injections and unrelated stderr.
  Only the two exact strace compat-personality warnings for the full-width
  injected values are permitted; the actual x86_64 result must remain intact.

The shared C probe is test infrastructure, not a replacement thread library.
Successful operations call glibc; held workers are real pthreads blocked on
futex conditions before entering Lanius. Source-owned allocation accounting
for pool/par tests belongs to their separate exact native source-site ledger.
The direct raw-thread fixtures use caller-owned stack backing and join every
successful thread before main returns.

The driver also runs four [callback frame regressions](repros/README.md).

Lifecycle selectors in `tests/stdlib_thread_lifecycle_execution.rs`:

```text
canonical_thread_ordinary_functions_execute_real_native_threads
thread_attributes_and_failed_joins_preserve_real_native_owners
thread_scheduling_preserves_syscall_errors_and_checks_full_width_affinity_counts
```

Host-only checks:

```sh
timeout --kill-after=2s 100s cc -std=c11 -Wall -Wextra -Werror -fsyntax-only tests/fixtures/stdlib_thread_lifecycle/thread_probe.c
timeout --kill-after=2s 100s python3 -I -B tests/fixtures/stdlib_thread_lifecycle/scheduling_oracle.py controls
```

Native process bounds are six seconds for admission, fifteen seconds for the
real-thread fault fixture, and five seconds per scheduling child under a
seventy-second outer oracle. Worker-gate readiness has a three-second
monotonic deadline. Other targets, enforced callback signatures and argument
lifetimes, data-race safety, arbitrary fault schedules and formal correctness
remain outside this evidence.
