# Byte-array repetition count context capture

`original.lani` preserves the exact file-copy descriptor fixture rejected by
the first admission gate. `original.stderr.txt` preserves that gate's complete
log. `typed-count-failed.lani` and `typed-count-failed.stderr.txt` preserve the
exact second failed source and its complete log. `original.sha256` records all
four files' exact bytes.

At the parent-reported compiler checkpoint `59612b34`, compilation failed with
`LNC0069` at original line 102:

```lanius
let storage: [u8; 4100] = [0; 4100];
```

The diagnostic marks the repetition count literal as outside its checked type
range. The count exceeds `u8::MAX`; the surrounding array's element type is
`u8`. This records an observed source-context boundary, without claiming a
compiler-level diagnosis or repair. The failed gate ran for 4.03 seconds and
performed no native execution. Its original log path is
`target/stdlib-work/file-copy-admission/descriptor.log`.

The second gate replaced only the repetition count with a private typed
constant, keeping the ordinary 4100-element byte array:

```lanius
const SCRATCH_BACKING_LENGTH: i32 = 4100;
// In main:
let storage: [u8; 4100] = [0; SCRATCH_BACKING_LENGTH];
```

That source failed with `LNC0016` at line 104: the parser expected an integer
literal at the repetition count and rejected `SCRATCH_BACKING_LENGTH`. This
was a failed candidate, not an accepted control. The gate ran for 3.72 seconds
and performed no native execution. Its original log path is
`target/stdlib-work/file-copy-admission/descriptor-typed-count.log`. No cast
candidate was attempted: the repetition-count grammar requires a literal.

Two small source probes remain under the ignored directory
`target/stdlib-work/byte-array-repeat-count/`: `minimal-fail.lani` uses
`[u8; 300] = [0; 300]`, and `typed-count-failed-candidate.lani` contains the
earlier proposed typed `i32` count form with the same real byte array and
endpoint checks. Neither minimal probe has been executed. The full descriptor
fixture establishes that the typed-count syntax fails; these files provide no
accepted compilation or runtime control. The parent owns final compiler and
gate metadata.

The live fixture at
`tests/fixtures/stdlib_foundation/file_copy/descriptor.lani` has been restored
byte-for-byte to `original.lani`, with literal `[u8; 4100] = [0; 4100]` and no
unused count constant. Its ordinary strided backing, nonzero scratch start,
4096-byte logical capacity, and packed-buffer branch retain the original test
shape. The copy module and 84-case execution driver are unchanged. These two
failures establish no runtime evidence for the copy API. No compiler or runtime
changes are part of this capture.

## Accepted original after the count-checker fix

With the current count-checker fix, the unchanged original fixture passed the
canonical descriptor gate: one strict ELF/jump check and all 84 native x86_64
Linux executions in 6.33 seconds. The separate test-driver build took 1.22
seconds. Logs are
`target/stdlib-work/file-copy-admission/descriptor-fixed-checker.log` and
`target/stdlib-work/file-copy-admission/build.log`. Compiler commit `e59a9183`
contains the [count ownership correction and focused gates](../../../../docs/compiler-array-repeat-context.md),
including preserved element/extent rejections and bounded performance evidence.

The current live fixture remains byte-for-byte identical to `original.lani`,
with SHA-256
`cff017e806a349b2cec6c9c0de326353ec2270783f0f0c889836e5ac04d81edd`.
It retains the literal repetition count and full strided backing; the typed
constant remains a failed grammar candidate. The earlier `LNC0069` (4.03 s)
and `LNC0016` (3.72 s) attempts are historical failures, not accepted cases or
native executions. The 84 accepted executions are the unchanged descriptor
driver's cases; this evidence concerns the existing Linux native target and
does not establish GPU kernel behavior or performance.
