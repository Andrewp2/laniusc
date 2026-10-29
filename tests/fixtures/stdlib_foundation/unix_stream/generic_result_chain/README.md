# Generic Result method-chain reduction

The first full Unix direct-contract compile failed before native execution
with `LNC0027` at `stream.write(...).unwrap()` inside a function bounded by
`W:core::io::Write`. Evidence is
`target/stdlib-work/unix-stream-direct-first.log`; the unchanged failed source
is retained in `target/stdlib-work/unix-stream-direct-first-contracts.lani`
(SHA-256 `ecd6240bf4912ed16ea128dcc3c2993108037a101dab911724389377fe4e5fd3`).

The direct fixture now binds the generic Read/Write results to explicit
`Result<i32,core::io::Error>` locals before unwrapping. Generic calls, byte
counts, staging checks and all native behavior assertions remain intact.
That corrected direct gate passed one registered test in 8.11s, with three
others filtered, in `target/stdlib-work/unix-stream-direct-final.log`.
Separate pair admission passed one test in 7.30s in
`target/stdlib-work/unix-stream-admission-first.log`. There is no production
or compiler change.

`chained.lani` is a verified small reduction without Unix sockets or host I/O.
`typed_local.lani` differs only in introducing the typed Result local. Its
scripted writer records the supplied byte, so the positive native control can
check both the returned count and a real memory effect.

The explicit ignored run in
`target/stdlib-work/unix-stream-generic-result-chain-control.log` took 4.67s
and returned overall status 101:

- The chained positive-success test failed before native execution with
  `LNC0027` at `chained.lani:14`, the immediate `.unwrap()` after the generic
  bounded `Write.write` call.
- The typed-local positive control compiled and executed successfully,
  observing both returned count 1 and the supplied byte 7 in memory.

This mixed result records a compiler dependency; it is not a passing gate.
Both follow-ups remain explicitly ignored and expect successful compilation
and execution, so a compiler fix can make the chained test pass without
preserving rejection as required behavior. The observed boundary is this
generic Result method-chain form; broader expression forms are unclaimed.

Retained SHA-256 identities:

| Source | Hash |
| --- | --- |
| `chained.lani` | `9fd024301ceb06ffd305e850637b9b1cbaac56d3569736eb61bbee7007594396` |
| `typed_local.lani` | `ce03a6354aa474126f1192876d7af5427562a26985b8ebaabee897f245886102` |
| Corrected direct contracts | `217d2c638eb9855d5b12681a5d237e9e5770d3f7f1aa0b6ee5ed9681befabe83` |

```text
cargo test --test stdlib_unix_stream_execution generic_write_result_chain_should_execute_without_typed_local -- --ignored --exact
cargo test --test stdlib_unix_stream_execution generic_write_result_typed_local_control_executes -- --ignored --exact
```
