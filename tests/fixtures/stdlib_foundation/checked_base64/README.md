# Checked Base64 direct contracts

Both registered direct tests passed on their first runs, in separate commands:

| Receipt | Accepted scope | Time |
| --- | --- | --- |
| `target/stdlib-work/checked-base64-admission-first.log` | One admission test and native process | 4.46s |
| `target/stdlib-work/checked-base64-direct-first.log` | One native four-scenario contract test; admission filtered | 4.25s |

Root ran the compiler, Cargo and native commands. Independent canonical-wire
model, guarded-memory, application and WebSocket regression gates are separate
from these finite direct receipts.

`admission.lani` directly executes all four checked APIs, a literal RFC foo
vector, all four profiles, the standard/URL symbol distinction, padded and
unpadded tails, same-base encode/decode aliases and an exact indexed error.
Both accepted native processes passed strict x86_64 ELF checks and full syscall
tracing: only process entry and exit occurred, with no allocation or other host
services.

`contracts.lani` has four finite scenario functions and directly executes all
four checked APIs. The seven RFC length-zero-through-six vectors and five
binary vectors run under every profile with both source/output byte strides,
for 96 literal vector cases. Encoders must match exact wire bytes and decoders
independently consume literal wire, with every backing guard checked.

Length cases check exact padded/unpadded i32 boundaries. Null-backed malformed
metadata and structurally invalid lengths reject before access, including huge
lengths. Invalid output metadata precedes all input access; encoding capacity
admission precedes input access; decoding validates all input before capacity.
Error cases assert exact indexed alphabet, whitespace, padding-shape and unused-
bit failures, including failures after a valid first group and the specified
third-padding/fourth-byte precedence.

Every recoverable codec rejection checks complete input/output backing for
atomicity, including same-base aliases. Successful same-base multi-group tail
encode/decode runs through both actual strides and checks all remaining bytes.
Other partial overlap and physically invalid backing remain caller obligations;
physical traps have no rollback claim.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `0e12cf9dcfc81125583430dc3f90a90d4bef10343a9f5faf0c1b8040ea636d3d` |
| `contracts.lani` | `37cb43dddefc8258843e1ff4af8672111fd99940bee6ddc4c507ae8795523497` |
| `stdlib/core/base64.lani` | `c5eb1fc4ee603adb8f681695a3dd22885008b76d37fb70d78ce013d95b1837e8` |

```text
cargo test --test stdlib_base64_execution checked_base64_profiles_execute_rfc_url_tail_alias_and_error_admission -- --exact
cargo test --test stdlib_base64_execution checked_base64_profiles_execute_rfc_precedence_lengths_and_atomic_backing_contracts -- --exact
```

The two old positive fixtures and name-presence test are retired. Physical
backing-overclaim traps and guarded-memory tests have a separate boundary suite.
Accepted target scope is native Linux x86_64 CPU execution of GPU-compiler output;
GPU device execution and formal correctness are unclaimed.
