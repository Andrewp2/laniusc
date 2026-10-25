# Generic forwarding of record formatting

Observed on 2026-10-23 using the stdlib branch's compiler base `441e66f9`.
These are compiler reproductions, outside the production source roots. No
compiler IR, extractor, proof or ABI files were changed.

## Reduced case

Start with `reduced/main.lani` and `reduced/ext/record_probe.lani`.
The module has a borrowed record containing a severity, two Text values and a
View of fields. `count` measures one quoted key (`"ABC"`) through core::fmt and
returns `Ok(5)`. A generic `forwarded<W>` merely calls count; its writer parameter
is unused and it performs no I/O. Both calls should return 5.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc tests/fixtures/stdlib_foundation/log_write_dependency/reduced/main.lani --stdlib-root stdlib --source-root tests/fixtures/stdlib_foundation/log_write_dependency/reduced -o target/stdlib-work/log-record-repro
timeout 5s target/stdlib-work/log-record-repro
```

Compilation succeeds. Execution terminates with SIGILL (shell status 132).
Instrumenting the caller confirms the direct count returns 5, then the generic
forwarding call fails before its unwrapped count can be printed.

`reduced/direct_control.lani` removes only the forwarded call. It compiles and
exits zero using the same source root. Additional reduction experiments found
that removing the leading record fields or replacing formatting with direct key
length access also makes the program execute. These observations narrow the
boundary; they do not identify the compiler's internal cause.

## Original logging facade

`ext/log.lani` preserves the original combined facade. Its relevant shape is:

```lanius
pub fn write<W>(writer: &W, filter: Filter, record: &Record,
               scratch: [u8], capacity: i32)
    -> core::result::Result<Outcome, Error> where W: core::io::Write {
    // Filter, encode the complete record, then call core::io::write_all.
}
```

`main.lani` sends a single record to a SliceWriter and should exit zero after
checking all 70 bytes. It compiles but exits 101. Instrumentation places the
failure in the encoding call before the first writer call. This is not evidence
that SliceWriter or the short-write loop is at fault.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc tests/fixtures/stdlib_foundation/log_write_dependency/main.lani --stdlib-root stdlib --source-root tests/fixtures/stdlib_foundation/log_write_dependency -o target/stdlib-work/log-write-repro
timeout 5s target/stdlib-work/log-write-repro
```

`direct_control.lani` encodes the same record, then calls core::io::write_all at
the caller. It compiles and exits zero. A second control replaces only the
facade's `write<W>(writer: &W, ...)` signature with
`write(writer: &core::io::SliceWriter, ...)` and removes its where clause: the
original main also exits zero. The concrete signature is a diagnostic control,
not a proposed public specialization.

Production `ext::log` uses borrowed record preparation, returns an explicit
Filtered/Encoded outcome, and leaves delivery to the caller's existing writer.
That composition is exercised by the memory/output contract fixture, checksum
application, injected host failures and allocation-free batches. The combined
generic facade remains pending this compiler dependency. Passing a type check
alone is insufficient to restore it.
