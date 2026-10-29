# Bounded byte-delimiter contracts

All three registered library tests passed across two separate commands:

| Receipt | Accepted scope | Time |
| --- | --- | --- |
| `target/stdlib-work/delimited-io-admission-first.log` | One admission test and native process | 7.24s |
| `target/stdlib-work/delimited-io-contracts-first.log` | Two tests: one native six-scenario contract process and two marked LNC0008 rejections; admission filtered | 7.56s |

Root ran the compiler, Cargo and native commands. These receipts cover the
finite direct library cases below; independent model and application gates are
separate.

`admission.lani` first exercises both generic helpers through a provider that
implements only `BufRead`, then uses actual `SliceReader` and allocating
`alloc::buffered::Reader` values. Binary delimiters are included, trailing bytes
remain unread, read-ahead is distinguished from logical consumption, and the
buffer owner is explicitly discarded without modifying the borrowed input.
The driver requires strict x86_64 ELF and matches the actual buffered reader
allocation and release by address and size.

`contracts.lani` has six finite scenario functions. Literal byte and provider
event expectations cover binary delimiters, exact-limit precedence, EOF and
resumption; both actual native byte strides; range and budget admission;
metadata checks before EOF or consume-budget checks; fill-only Interrupted
retry; and copied-versus-consumed error progress. Consume errors retain unread
bytes and require an explicit later helper call to retry. Malformed successful
consume counts make no rollback or retry claim. Null-backed descriptors check
that invalid metadata and exhausted budgets prevent data access. Successful
zero-byte paths make no provider calls. The accepted pure contract process left
the selected memory and host I/O service trace empty.

Two negative fixtures implement `Read` without `BufRead` and require LNC0008
at the marked delimiter-helper call. The positive admission fixture independently
demonstrates that neither delimiter helper requires `Read`.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `859ec43ae9a500f3f96b64adfe089d882098663e27dde2ea8de074956332aab2` |
| `contracts.lani` | `8e5ce07e6daf41ef9a5e3e9d0c10688f085df151aad461f6e129139918fb0e39` |
| `stdlib/core/io.lani` | `d2d4d869cec351b29b1e2d026f4cfe684f06bda16bbc1738f2dae64252e287fb` |
| `stdlib/alloc/buffered.lani` | `025394873442bfe8b50254db4a4d50273a22a825cde83ff381578b2be0bd269d` |

```text
cargo test --test stdlib_delimited_io_execution bufread_only_generic_helpers_and_real_readers_execute_binary_admission -- --exact
cargo test --test stdlib_delimited_io_execution delimiter_contracts_execute_binary_limits_budgets_and_distinct_failure_progress -- --exact
cargo test --test stdlib_delimited_io_execution delimiter_helpers_require_bufread_instead_of_sequential_read -- --exact
```

Initial target scope is native Linux x86_64 CPU output from the GPU compiler.
No device-execution or formal-proof claim is made.
