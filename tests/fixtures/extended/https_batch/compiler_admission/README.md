# Nested enum-pattern admission

Status (2026-10-27): fixed on `lang`. Nested variant patterns, imported and generic ones included, now type-check and lower. `nested_io.lani` compiles and its four assertions pass.

`original_exchange.lani` preserves the exact direct HTTPS consumer rejected
before any resource-campaign case executed. Its SHA-256 is
`4be4ec59195da23cec8bc364551904b15e57c9fade33009cb18be708fe1da131`.
The original expression at line 59 is:

```lani
match(error.cause) { ext::https_client::Cause::Io(core::io::Error::Host(number)) -> number == 5, _ -> false }
```

The current compiler parsed this expression, then rejected `number` with
`AssignMismatch` / `LNC0006` at line 59, column 156. `compile-first.log`
preserves that diagnostic and the zero-case failed gate (10.24 seconds).
The grammar/HIR includes nested variant payload patterns; this receipt
establishes a compiler admission limitation in this expression shape, not
a TLS runtime failure. It does not identify the compiler's internal cause.

`nested_io.lani` is now a confirmed 14-line reproduction. The current CLI
parsed its local outer variant and nested `core::io::Error::Host(number)`, then
rejected the binding at line 6, column 59 with `AssignMismatch` / `LNC0006`.
The command exited 1; `compile-reduction-first.log` preserves the diagnostic.
This isolates the limitation without importing any HTTP, TLS or batch module.

`typed_io.lani` is a confirmed explicit two-match control: select the outer
payload into `Option<core::io::Error>`, then match the inner error separately.
The same CLI compiled it successfully to an ELF64 little-endian x86_64
executable, and that executable exited 0 with no output under a two-second
limit. Its four assertions cover exact Host(5), wrong errno, another I/O
variant and another outer variant. This finite control is not evidence that
all nested patterns or all generic compositions work.

Reproduce from the repository root, with each command bounded independently:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  tests/fixtures/extended/https_batch/compiler_admission/nested_io.lani \
  -o target/stdlib-work/nested-io-probe

timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  tests/fixtures/extended/https_batch/compiler_admission/typed_io.lani \
  -o target/stdlib-work/typed-io-probe

timeout --kill-after=2s 2s target/stdlib-work/typed-io-probe
```

The first command is expected to fail. Root serialized these invocations with
`target/stdlib-work/library-gpu.lock`; the local control receipts are
`nested-io-reduction-first.log`, `typed-io-control-first.log` and
`typed-io-control-native-first.log` under `target/stdlib-work/`.

The active direct consumer uses this same explicit two-match spelling and
retains both exact typed Host(5) assertions, immediately after abort and from
the retained `last_failure`. It compiled and passed all six direct invocations
within the accepted resource-group retry. That group passed 66 cases in
37.52 seconds, including 42 reached source-allocation ENOMEM positions;
the receipt is `target/stdlib-work/https-batch-resource-direct-typed-retry.log`.
This accepts the actual revised consumer. The separate minimal reproduction
and executable control above strengthen the admission boundary without changing
the compiler, production HTTP/TLS source or observer/oracle behavior.
