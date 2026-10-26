# Concurrency admission controls

These small Lanius sources separate current scalar C calls from missing
Boolean/callback/thread admission. After source and official ABI review, the
parent runner compiled all seven controls with unchanged compiler sources at
`4a7a9c5ef02f987ea449bd1c82c494a31cb34b61`. Three positives passed linked-ELF
validation and exited zero with empty stdout and stderr; four negatives
rejected. No fixture source changed for these runs.

Use the already-built compiler selected by the parent runner. From the
repository root, a positive control can be compiled as:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --native-link --native-library atomic --stdlib-root stdlib \
  tests/fixtures/stdlib_compiler_state/concurrency_admission/atomic_scalar_control.lani \
  -o /tmp/concurrency-atomic-scalar-control
```

The scalar fixture uses the actual libatomic runtime symbols and unsigned
4/8-byte operands. It owns one malloc allocation, touches two disjoint aligned
words only through atomic functions and frees the allocation after every
checked operation path. It checks returned old values, unsigned wrapping and
full-width load/exchange values, all with `__ATOMIC_SEQ_CST=5`. An allocation
failure returns 90. It starts no worker and establishes no concurrent ordering.

For `direct_entry_control.lani` and `pthread_identity_control.lani`, use the
same command with the corresponding source/output paths and omit
`--native-library atomic`. Both compiled and returned zero in the recorded run.
The pthread control only compares the initial thread with itself. On this
glibc x86_64 profile `pthread_t` is unsigned long, matched by `usize`; it is not
declared as i32 or treated as a kernel thread ID.

Compile each rejection separately, without executing it. The observed results
are:

| Source | Compiler elapsed | Observed boundary |
| --- | --- | --- |
| `atomic_compare_exchange_bool.lani` | 2.449 s | Exit 1, `LNC0006` unsupported C signature at `bool`; five runtime parameters, no builtin weak parameter |
| `function_value.lani` | 2.256 s | Exit 1, `LNC0005` unresolved `worker` as a value |
| `callback_definition.lani` | 2.362 s | Exit 1, `LNC0016` expected semicolon, found body brace |
| `std_thread_unbound.lani` | 3.231 s | Exit 1, `LNC0059` wrapper with an unbound native declaration note; `--stdlib-root stdlib` supplied |

The Boolean fixture deliberately leaves its declaration unused: native
signature admission must still validate it. Do not replace `_Bool` with an
integer return to make the source compile. No `pthread_create` declaration
with a data pointer substituted for its function-pointer parameter is supplied.

The positive compiler/linker elapsed times were 2.460 s for
`direct_entry_control`, 2.145 s for `atomic_scalar_control` and 2.391 s for
`pthread_identity_control`. The summary receipt is
`target/stdlib-work/concurrency-admission-controls.log`. Per-control logs are
`target/stdlib-work/concurrency-admission/NAME.compile.log`; the positives also
have `NAME.native.log`. All commands completed within their 100-second limits.

The thread rejection's actual note is
`native declaration [0, 0, 43] has no Lanius definition or checked foreign binding`.
Classify this as the missing service binding. The generic artifact-store
wrapper and stale-artifact removal help are not evidence of a disk/cache
failure and do not resolve the missing runtime.

These are finite direct-call, scalar and initial-thread controls. They do not
establish a happens-before contract or execute CAS, a callback or a worker.
Unexpected future acceptance of a negative control needs review before running
a purported thread/callback program.

The ownership/order proposal and primary references are in
[`docs/library-concurrency-dependencies.md`](../../../../docs/library-concurrency-dependencies.md).
