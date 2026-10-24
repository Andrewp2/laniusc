# Generic iterator Option assignment reducer

This preserves a confirmed wrong `is_none` result after conditional assignment
of an `Option<i64>` returned through a generic Iterator. The parent selection
model first reported `Some(0)` for an empty Filter source, with source EOF and no
predicate calls. The reducer establishes the wrong Boolean observation, with
the direct binding and source/callback counts as controls. That observation did
not establish the assigned Option's actual tag. Subsequent compiler changes
and verification are described below and in the current compiler guide.

The initial reducer compiled but its native process trapped with SIGILL and no
stdout or stderr in the parent's 5.58 s gate. This differs from the original
model's `Some(0)` output and successful process exit, so the assignment failure
was not confirmed by that first version. The initial source bytes remain at
`target/stdlib-work/iterator-selection-assignment/initial-reducer.lani`; the
source SHA-256 is
`4fb7260f6671f22406afc54244eb43648758c58779d55aa41ed10f56cf82c413`.
Its distinct diagnostic log is copied unchanged to `observed/initial-sigill.log`.

`reducer.lani` uses the production `core::iter::Filter` and a source with the
original model's simple `i32` length, position and call-count fields. It removes
the initial reducer's Boolean present/yielded fields. It makes four generic
observations:

1. Bind the returned `Option<i64>` directly from an empty Filter.
2. Initialize `Option<i64>` to `None`, then assign `first.next()` in one branch.
3. Use the same assignment shape with `second.next()` in the other branch,
   where `second` is a by-value copy of the generic cursor.
4. Assign a valid `Some(0)` result through the second branch as a control.

Both observation helpers return `is_none(item)`. A checked raw Descriptor write
emits an ASCII checkpoint before each observation and the Boolean result
immediately after it. A trap retains its already written prefix. There are no
fixture assertions that could mask later observations. Intended output is:

```text
65 1 66 1 67 1 68 0   2 1 1   0 0 1
```

ASCII A/B/C/D identify direct binding, first-branch assignment, second-branch
assignment and the Some control. Each is followed by its `is_none` result.
The next three bytes are source call counts for the first empty source, second
empty source and Some source. The final three are their predicate call counts.
Borrowed source records and callback counters retain visible effects across
copied Filter descriptors.

## Confirmed result

The revised gate compiled the fixture, passed the unchanged common strict x86
checks and ran a native process that exited zero. The Rust test then failed
its marker comparison in 3.78 s. Exact actual output was:

```text
65 1 66 0 67 0 68 0   2 1 1   0 0 1
```

Direct binding correctly observes None. Assignment in either branch incorrectly
reports `is_none == false` for an empty source. The Some control is correct and
all six source/callback counts match expectations. Unlike the initial version,
this revised fixture did not trap. This was a failing regression test with one
strict ELF and one successful native process, not a passing target.

`observed/reducer-revised.log` is an exact copy of the parent's diagnostic log
from `target/stdlib-work/iterator-selection-admission/reducer-revised.log`.
The confirmed reducer's SHA-256 is
`4fb722be157d3df9f22f070b507d118621da1ba34084d0e3e29c17830079b89a`.
The reducer and observed logs remain unchanged. The original one-test driver
is preserved as `observed/driver-before-rejection.rs.txt` before the separate
negative test was appended to the live driver.
The confirmed log's SHA-256 is
`d95abfc946950e2096e20c32d0470a5a0ee5e4769f9a71ddd83b17a195435c9a`.
The parent built
`target/stdlib-build/debug/deps/stdlib_iterator_selection_assignment-03d5250f70073f07`
in 1.09 s; that binary performed the 3.78 s failing regression gate.

## Diagnostic control snapshot

`controls.lani` is an exact, unedited copy of
`target/stdlib-work/iterator-selection-assignment/assignment-controls.lani`, with
SHA-256 `d8966ed135637353310536b3bbfec083284eecc62b2255a80956ec6b1d650a7e`.
It compares direct binding, unconditional assignment and both conditional
branches. Each generic helper computes and emits `is_none` and `is_some`
locally, then returns unit. It introduces no generic record return type. The
source header says "Unexecuted" because it records its creation-time status;
those exact bytes remain preserved after execution.

The parent subsequently compiled this source. Its native process trapped with
SIGILL after producing exactly these bytes, retained as `observed/controls.stdout`:

```text
65 1 0 1 0 66
```

The complete A record shows correct direct-empty observations: `is_none == 1`,
`is_some == 0`, one source call and zero predicate calls. Byte 66 is the B
checkpoint for unconditional assignment; the process trapped before emitting
B's flags or counts. The conditional branches and later Some controls were not
observed in this run.

This began as an unregistered diagnostic snapshot. Exact
row identities cited in the
[compiler guide](../../../../docs/compiler-iterator-assignment-context.md)
come from captures of this control input. Those rows describe that source and
capture, not stable compiler identifiers or the distinct `reducer.lani` input.

## Subsequent compiler repair and verification

The parent corrected shared assignment-context handling to decode a statement
flag before checking the resulting dense node identity. The parent reports
that this corrected the positive reducer and selection model.

The live driver then gained one negative test,
`iterator_assignment_context_rejects_an_incompatible_actual_item_type`, using
`reject_incompatible_assignment.lani`. A generic `I: Iterator<i64>` returns an
actual `Option<i64>`, while the destination is `Option<bool>`. The assignment
`item = first.next();` must reject with source-local LNC0006; its expected
context must not change the iterator's actual item type. The first negative
gate instead emitted an ELF. That diagnostic now reports only the unexpected
ELF size, rather than dumping the binary bytes.

The parent then added a source-constraint guard and reports the final assignment
gates passed in 8.60 s and selection gates passed in 7.69 s. See the current
[compiler guide](../../../../docs/compiler-iterator-assignment-context.md) for
the final repair, acceptance scope and gate evidence. The earlier diagnostic
snapshots and failures here remain historical observations.
The positive test's source and expected markers remain unchanged. Its name is
`iterator_filter_option_assignment_matches_direct_binding`; it compiles the
confirmed reducer, applies the unchanged common strict x86 checks, runs one
native process and requires the intended markers. Both tests are in
`tests/stdlib_iterator_selection_assignment.rs`. No compiler-throughput result
is claimed by this capture.

After both repairs, the unchanged `controls.lani` input was registered as
`generic_option_assignment_forms_preserve_both_variant_predicates`. It passed
in 3.78 s: all eight five-byte records are present, with correct `is_none` and
`is_some` flags, one source call per case, and one predicate call only for
Some(0). This executes the formerly trapped unconditional None case directly.
Its strict native gate is separate from the earlier two-test 8.60 s run; the
original two tests were unchanged when this registration was appended.

## Historical and current manifests

`ORIGINAL_CAPTURE.sha256` preserves the original manifest bytes. Its live-driver
entry describes the earlier one-test snapshot, not today's driver. The exact
earlier driver bytes are in `observed/driver-before-rejection.rs.txt`, with
SHA-256 `375dd8a2aeea92586f11db86d293afe438e721c9ee86582854e65633bd51331c`.
The earlier README is preserved as `observed/README-before-current-manifest.md`.
The original manifest records the paths at that earlier snapshot; it is a
historical artifact, not a check against today's files at those live paths.

`SOURCES.sha256` checks the current capture. It pins this README, both regression
fixtures, the exact diagnostic control input and stdout, the actual current
Rust driver, both historical snapshots, the original manifest and the unchanged
observed logs. Run from the repository root:

```sh
sha256sum -c tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/SOURCES.sha256
```
