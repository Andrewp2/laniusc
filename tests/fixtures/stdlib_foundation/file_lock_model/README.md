# Actual advisory file-lock state model

This fixture compares real Lanius file operations with an independent
open-description compatibility and lifetime model, following the
[locking contract](../../../../docs/library-file-locking-plan.md). Python
creates a private temporary file and supplies binary action schedules. The
compiled producer performs the actual opens, duplicates, nonblocking locks,
unlocks, seeks and closes through `std::file_ops` and `std::file::File`.
Python does not call a host flock implementation or implement production I/O.

## Finite corpus

There are **1,287 programs and 24,244 steps**, using seed `0xf10c20261030` and
four logical owner slots:

| Program family | Programs |
| --- | ---: |
| All action sequences of length zero through three over Shared/Exclusive/unlock on two independent opens | 259 |
| All action sequences of length zero through three over nine lock/unlock/close actions, starting with two independent opens and a locked duplicate pair | 820 |
| Explicit conversion, repeated acquisition, duplicate lifetime/unlock, reopen, closed-owner and shared-cursor sequences | 8 |
| Seeded 32-action sequences over opens, duplicates, locks, unlocks, closes and seeks | 200 |

Every program ends by closing all four slots, opening a fresh independent
description, acquiring Exclusive, explicitly unlocking and closing it. The
longest program has 43 actions. Everything runs in one native child process
against one private file; all lock requests are nonblocking.

The reference assigns an identity to every independent open. Duplicates point
to that same description and share its lock mode, cursor and status flags;
close-on-exec belongs to each handle. Shared holders may coexist, while an
Exclusive request conflicts with every locked independent description.
Repeated acquisitions are not reference counted. Closing a duplicate removes
only that handle; the lock disappears after the last handle closes.

Every actual WouldBlock result is followed by **one explicit unlock**, and
that normalization result is observed before any further prediction. The
model then treats that description as unlocked. This avoids assuming that a
failed conversion retained its previous lock or was atomic. The normalization
also occurs after an unsuccessful first acquisition; it is part of the test
sequence, not an implicit library retry, rollback or cleanup policy.

Each step checks exact result/error payloads, normalization, all file bytes,
and each owner's liveness, borrowed descriptor, cursor, selected status bits
and close-on-exec flag. Live descriptor numbers must be distinct; host numeric
allocation order and reuse are not pinned. A separate witness open uses
positional reads, so the observation does not move participating cursors.
The oracle checks complete file contents again after native completion.

The finite reference reaches these cases; counts overlap where applicable:

| Observation | Count |
| --- | ---: |
| WouldBlock followed by explicit normalization | 949 |
| Failed conversions among those conflicts | 138 |
| Repeated successful acquisition of the existing mode | 808 |
| Last close while the description holds a lock | 1,407 |
| Closing one duplicate while another retains a locked description | 941 |
| Unlock through a multiply referenced description | 322 |
| Seek through a multiply referenced description | 154 |
| Reopening a previously used logical slot | 1,572 |
| Closed-owner errors | 1,342 |
| States containing multiple independent shared holders | 1,070 |

Action counts for open, duplicate, close, Shared, Exclusive, unlock and seek
are respectively `4466, 1659, 8086, 3051, 3434, 2944, 604`.

## Protocol and acceptance

Each binary input program starts with identity and action count as
little-endian `u64` words. Each action adds operation, slot, other and argument.
For open, other contains append/nonblocking flags and argument is its initial
cursor; duplicate names another closed slot and selects close-on-exec; seek
uses argument as a position. The generator never overwrites a live owner.
The producer bounds action indices and admits at most 64 actions.

Each output step has 66 words: the action, four primary-result fields, a
normalization flag and four normalization-result fields, file length and all
32 file bytes, then five fields for each owner. Errors preserve their kind and
signed Host payload. The oracle rejects mismatched, truncated or extra output
and includes the program, action index and seed in diagnostics.

CPU controls pass, including explicit checks for last-close lifetime,
non-reference-counted repeated locks and failed-conversion normalization.
Six deliberate corruptions of errors, aliased cursors, close-on-exec,
descriptor uniqueness, content and closed-owner state are rejected.

The registered gate is
`independent_lock_models_match_real_compatibility_aliases_and_last_close_lifetimes`
in `stdlib_file_lock_model_execution`. It uses shared strict x86 ELF checks,
one batched native process and bounded 85-second outer / 70-second child
timeouts. Executable target: native Linux x86_64 CPU output from the GPU compiler
on the tested local temporary filesystem. Blocking wakeup, cross-process
contention and injected native results belong to separate contract tests.
This finite model supplies no device-execution, cross-filesystem, automatic
ownership, allocation-trace, atomic-conversion or formal verification claim.

The first registered native runtime run passed: **one test, 1,287 programs and
24,244 steps in 5.76 seconds**, with four owner slots and seed `0xf10c20261030`.
The log is `target/stdlib-work/file-lock-model-first.log`; its exact summary is
`file-locks programs=1287 steps=24244 handles=4 seed=0xf10c20261030`.
This result compares the complete finite corpus with actual Lanius operations
on the tested local Linux temporary filesystem. It does not extend the
compatibility/lifetime claim to other filesystems or atomic failed conversion.

Tested SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/std/file_ops.lani` | `9ca5ca58e09b39342c6409bded385b18e08d7488de233d32a87fe82826cf9f8a` |
| `stdlib/std/file.lani` | `ddee2d30de001612254102f00f20e3a1302886e6ab7d8f9995f990bb55220f4e` |
| `model.lani` | `af592ccc3f571462a74d56c6e1e973760820f9fe04bfc2c600144928d82efcc5` |
| `oracle.py` | `03a49bd8794053a1db2e9640b77e3d7d1484f17e3ed2e1facdd7b9cfbac1887c` |

```sh
python3 -B tests/fixtures/stdlib_foundation/file_lock_model/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/file_lock_model/oracle.py /path/to/model
```
