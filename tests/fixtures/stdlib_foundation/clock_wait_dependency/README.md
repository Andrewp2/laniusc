# Generic deadline construction

Reproduced on 2026-10-23 with compiler base `441e66f9`. This directory holds
compiler reproductions, outside production imports. No compiler code was changed.

## Reduced case

`reduced/std/deadline_probe.lani::after<C>` reads an Instant through a clock trait,
calls `core::time::deadline_after(initial, span)` and returns the new Instant.
`reduced/main.lani` supplies a local zero clock and checks an offset of one second.
It should exit zero without any host operation. Compilation instead reports
LNC0047: a replay argument lacks a complete GPU native layout.

Two controls compile and exit zero:

- `split_control.lani` calls the same trait and preserves the same public result.
  It uses a typed `initial.checked_add(span)` result, followed by
  `deadline_at(at)`. This changes the internal composition without changing the
  requested deadline or its errors.
- `forward_control.lani` forwards already supplied Instant/Duration values
  through a generic function to `deadline_after`. It has no clock trait call.
  Thus this is not evidence that every generic call to deadline_after fails.

Reproduce with the probe classified as a standard-library module:

```sh
mkdir -p target/stdlib-work/deadline-repro-root
cp -R stdlib/. target/stdlib-work/deadline-repro-root/
cp tests/fixtures/stdlib_foundation/clock_wait_dependency/reduced/std/*.lani target/stdlib-work/deadline-repro-root/std/
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc tests/fixtures/stdlib_foundation/clock_wait_dependency/reduced/main.lani --stdlib-root target/stdlib-work/deadline-repro-root -o target/stdlib-work/deadline-repro
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc tests/fixtures/stdlib_foundation/clock_wait_dependency/reduced/split_control.lani --stdlib-root target/stdlib-work/deadline-repro-root -o target/stdlib-work/deadline-split
timeout 2s target/stdlib-work/deadline-split
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc tests/fixtures/stdlib_foundation/clock_wait_dependency/reduced/forward_control.lani --stdlib-root target/stdlib-work/deadline-repro-root -o target/stdlib-work/deadline-forward
timeout 2s target/stdlib-work/deadline-forward
```

Run a control only after its compilation succeeds. A failed compile can leave an
older output file. Do not require this compiler defect to persist in a test gate.

## Original facade and production behavior

`std/clock.lani` preserves the original relative-sleep facade, including its
shared generic wait loop. Replace `std/clock.lani` in an isolated copy of stdlib
with this version and compile this directory's `main.lani` to reproduce the same
LNC0047 failure. The original full scripted-clock fixture also failed. Inlining
the wait loop did not repair it.

Production `std::clock` retains both generic `sleep_for` and `sleep_until`, the
clock trait and a single shared wait loop. Only relative-deadline construction
uses the successful separately typed stages. The executable suite covers a
scripted clock, native reads/sleep, interruptions, rounding, long waits split into
chunks, overflow, reversed clocks and a scheduled JSON-reporting program.
This confirms the shipped APIs' behavior; it does not repair the compiler's
composition limitation.
