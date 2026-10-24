# Generic iterator Option assignment reducer

This preserves a confirmed wrong `is_none` result after conditional assignment
of an `Option<i64>` returned through a generic Iterator. The parent selection
model first reported `Some(0)` for an empty Filter source, with source EOF and no
predicate calls. The reducer establishes the wrong Boolean observation, with
the direct binding and source/callback counts as controls. It does not identify
the compiler layer responsible or establish the assigned Option's actual tag.

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
this revised fixture does not trap. This is a failing regression test with one
strict ELF and one successful native process, not a passing target.

`observed/reducer-revised.log` is an exact copy of the parent's diagnostic log
from `target/stdlib-work/iterator-selection-admission/reducer-revised.log`.
`SOURCES.sha256` pins this README, the confirmed reducer, both preserved logs
and the dedicated Rust driver. The confirmed reducer's SHA-256 is
`4fb722be157d3df9f22f070b507d118621da1ba34084d0e3e29c17830079b89a`.
The reducer and driver stay unchanged while additional controls are prepared.
The confirmed log's SHA-256 is
`d95abfc946950e2096e20c32d0470a5a0ee5e4769f9a71ddd83b17a195435c9a`.
The parent built
`target/stdlib-build/debug/deps/stdlib_iterator_selection_assignment-03d5250f70073f07`
in 1.09 s; that binary performed the 3.78 s failing regression gate.

The separate ignored source
`target/stdlib-work/iterator-selection-assignment/assignment-controls.lani`
compares direct binding, unconditional assignment and both conditional
branches. Each generic helper computes and emits `is_none` and `is_some`
locally, then returns unit. It introduces no generic record return type. That
additional source has not been compiled or run and is not evidence for a
repair.

The dedicated driver is
`tests/stdlib_iterator_selection_assignment.rs`, with one test:
`iterator_filter_option_assignment_matches_direct_binding`. It compiles one
fixture, applies the unchanged common strict x86 checks, runs one native
process and requires the intended markers. No current model, production,
compiler, runtime, IR or ABI source changes are part of this capture. No repair
or compiler-throughput result is claimed.
