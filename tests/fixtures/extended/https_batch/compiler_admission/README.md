# Nested enum-pattern admission

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

`nested_io.lani` is an unexecuted candidate reduction using the same outer
variant and inner `core::io::Error` pattern. `typed_io.lani` is an unexecuted
candidate control: select the outer payload into an explicit
`Option<core::io::Error>`, then match the inner error separately. Both check
exact Host(5), wrong errno, another I/O variant and another outer variant.
Neither candidate is claimed accepted or rejected until separately compiled.

The active direct consumer uses this same explicit two-match spelling and
retains both exact typed Host(5) assertions, immediately after abort and from
the retained `last_failure`. It compiled and passed all six direct invocations
within the accepted resource-group retry. That group passed 66 cases in
37.52 seconds, including 42 reached source-allocation ENOMEM positions;
the receipt is `target/stdlib-work/https-batch-resource-direct-typed-retry.log`.
This accepts the actual revised consumer. The standalone `nested_io.lani`
and `typed_io.lani` candidates remain unexecuted. No compiler, production
HTTP/TLS source or observer/oracle behavior changed for this admission fix.
