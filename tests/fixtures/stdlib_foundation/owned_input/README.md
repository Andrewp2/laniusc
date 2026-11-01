# Bounded owned-input direct contracts

Both registered direct tests passed on their first runtime attempts, in
separate commands:

| Receipt | Accepted scope | Time |
| --- | --- | --- |
| `target/stdlib-work/owned-input-admission-first.log` | One generic admission test and native process | 7.26s |
| `target/stdlib-work/owned-input-direct-first.log` | One native five-scenario contract test; admission filtered | 6.98s |

Root ran the compiler, Cargo and native commands. Independent state-model,
allocation-denial, String-transfer and application gates are separate from
these finite direct receipts.

`admission.lani` calls both collectors through generic Read bounds, preserving
binary NUL/non-UTF-8 bytes and validating a multibyte UTF-8 scalar split across
reads. It checks actual reader calls and cursor positions, including the EOF
probe at the exact byte cap, and explicitly destroys the returned Vec/String.
Both accepted native processes passed strict x86_64 ELF checks and full syscall
tracing. The traces contained only process entry/exit and owner allocation and
release, matched by complete address and size, with no live owners left.

`contracts.lani` has five finite scenario functions. Scripted readers record
each nonempty request and source position, and assert the 1024-byte request cap.
Cases cover defaults, invalid limits, zero/exact call allowances and admission
of a u64::MAX quota followed by one actual EOF call. This maximum configuration
case does not execute an exhaustive 2^64-call sequence. Other cases cover
short reads, Interrupted, actual EOF at zero/exact byte caps, interrupted cap
probes, and confirmed extra bytes including NUL. The extra byte remains distinct
from the admitted Vec prefix; failure cleanup does not read the borrowed source,
and an explicit later read recovers its still-unread tail.

I/O errors and invalid provider counts preserve the exact admitted prefix and
take precedence over invalid UTF-8. Call/byte limits likewise precede text
validation; after actual EOF, text errors retain all raw bytes and the exact
malformed-sequence offset. A Euro scalar and an emoji split across several
reads preserve NUL, CR and LF without normalization. Real 1024-byte requests
exercise growth and the one-byte cap probe, with full retained-byte checks.
Invalid provider counts in this scripted fixture do not mutate its source;
no general consumption/rollback claim is made for a broken provider.

All returned owners and failures are explicitly destroyed, including repeated
cleanup of emptied owners. Allocation denial campaigns and zero-copy String
identity have separate focused gates.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `63906416f18e3734219f1652c3115d8bca739de2886198b34a89ad90a431650b` |
| `contracts.lani` | `3f44135f238b45d8e2a75721943cc5a3fbf8e6c255c63b45d462f97e99e5202f` |
| `stdlib/alloc/io.lani` | `2ed4586e3f33702e10c935d0e68b618fdc65ca6260d1b764cc893e7af9ee7c86` |
| `stdlib/alloc/string.lani` | `2196e427ba4091eafc7de4c13ae66c640027fa1f3ad1b5c63b2c53b2348d6282` |

```text
cargo test --test stdlib_owned_input_execution owned_input_generic_bytes_and_split_utf8_execute_admission -- --exact
cargo test --test stdlib_owned_input_execution owned_input_executes_scripted_caps_probes_quotas_failures_and_utf8_precedence -- --exact
```

Accepted target scope is native Linux x86_64 CPU execution of GPU-compiler
output; GPU device execution and formal correctness are unclaimed.
