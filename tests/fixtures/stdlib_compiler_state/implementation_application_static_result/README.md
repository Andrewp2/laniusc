# Static implementation result inside a generic record expression

This source-only snapshot preserves the exact original constant-application
entry, imported implementation, and imported consumer from the first native-v2
forwarding attempt. `SOURCES.sha256` identifies those three source files. It is
a captured compiler failure, not an expected-failure test or a fixed feature.

The consumer contains the original nested expression:

```lanius
return Observation { stamp:source.stamp(),payload:W::echo(source.payload()) };
```

Root's `target/stdlib-work/implementation-applications/forwarding-v2.log`
records successful compilation and native execution of the preceding controls
and minimal imported write entry. Compilation of this constant entry then
failed before native execution:

```text
error[LNC0006]: type mismatch
constant_consumer.lani:7:55
value type is unknown type but this context expects generic parameter 33
expected generic parameter 33, found unknown type
```

The generic parameter number is diagnostic evidence from that run, not a stable
expectation. The snapshot makes no claim that the current compiler still fails
or that the failure is resolved. It retains full-u64 constants with equal low
words, two generic mixed-width payload layouts, borrowed source-state effects,
and static required-method result flow; no host service or allocation is used.

The active focused fixture now isolates the nested expression with explicit
generic locals `let payload:T = source.payload(); let echoed:T = W::echo(payload);`
before constructing the Observation. That isolates expression flow without
substituting concrete types or constants. Its independent
`typed_constant_implementation_applications_preserve_values_and_layouts` test
passed native-v3 admission in 2.50 seconds: one compilation, strict x86 checking
and one native execution with zero exit status and empty stdout/stderr. All
full-width constant, mixed-record payload, static-call and source-alias
assertions passed. The log is
`target/stdlib-work/implementation-applications/constant-application-v3.log`.

That acceptance applies to the active fixture with explicit generic locals.
The original nested expression preserved here has not been rerun, its captured
failure remains open, and these three snapshot sources remain unchanged.

To compile the captured source shape from the repository root:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc --stdlib-root stdlib \
  --source-root tests/fixtures/stdlib_compiler_state/implementation_application_static_result \
  tests/fixtures/stdlib_compiler_state/implementation_application_static_result/main.lani \
  -o target/stdlib-work/implementation-application-static-result.elf
```

This command has not been rerun for this snapshot. A future successful ELF must
pass the common strict x86 checker and execute its native assertions before it
can be counted as runtime evidence.
