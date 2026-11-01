# Lazy Option and Result composition model

This bounded fixture runs the nineteen imported lazy Option/Result operations
in both free-function and method forms. A separate Python reference generates
the complete expected binary transcript. Python supplies no production library
implementation; the native producer calls the real Lanius modules through the
canonical `core::function::Mapper` and `Producer` traits.

## Reference and observations

The oracle describes each API with a table mapping the receiver variant to a
callback selection and a value projection. Tagged values, selected effects and
register updates form the reference; it does not reproduce the nineteen Lanius
branch bodies. All 76 API/call-form/receiver-variant combinations are required
by a corpus assertion.

Each case maintains an Option, a Result, a plain value and a Boolean. API
results feed those registers; explicit harness instructions reconnect plain
values and queries to later Option/Result calls. A fixed chain creates `None`
inside a callback, skips subsequent maps/predicates, recovers through a chosen
fallback, creates `Err` inside another callback, skips successful-value work,
maps errors and recovers again. Seeded continuations combine all operations.

Every callback observation records its kind, unique identity, global invocation
ordinal, mode, full-width salt, whether an input exists, the complete input and
the complete returned value. Callback outputs depend on shared invocation state;
duplicate or unwanted invocations change both the event tape and later values.
Producers genuinely receive no argument. After every action, the transcript
also records the cumulative call count, all unchanged operand copies and every
new register value. Final states and counters are checked separately.

The first payload shape is `u64`. The second has two full-width words, an
`Option<bool>`, three signed array elements and a nested `Result<u64,i32>`.
Every field is serialized, including absent versus stored false and both
nested result variants. The cases use zero, `u64::MAX`, the high bit, adjacent
boundaries and patterned binary words. This model intentionally keeps input
and output payload types equal within a case; separate direct gates exercise
type-changing, view, floating and zero-sized instantiations.

Values here have no owned allocation. Predicate callbacks only observe their
payloads and update independent instrumentation. Eager fallbacks are constructed
before calls. Logging I/O is a chosen callback effect, not a library effect.
This fixture does not infer clone/destruction or allocation behavior from
absence of callbacks; separate resource tests cover selected owner obligations.

## Bounded corpus and protocol

Seed: `0x1a2f0261119`. Eight schedules run with each of two payload shapes:
16 cases, each with 96 commands. There are 1,536 commands in total, including
1,044 public API calls: 536 free functions and 508 methods. Selected paths make
616 calls, including 148 producers; 428 paths skip invocation. Callbacks return
60 absent values and 52 errors. Harness commands account for the remaining
492 commands and are not counted as new public APIs.

Expected native summary:

```text
lazy-outcomes-model cases=16 actions=1536 api_calls=1044 free=536 method=508 selected=616 skipped=428 callbacks=616 producer_calls=148 callback_absence=60 callback_errors=52 apis=19 branch_routes=76 shapes=2 seed=0x1a2f0261119
```

One native child processes the complete corpus. Input commands occupy at most
3,072 bytes per case and output is flushed from a 4,096-byte buffer. The strict
little-endian transcript includes complete framing, case/operation/call-form
ordinals, events and values. Comparison rejects any differing byte, truncation
or extra output and reports the containing case and operation. No native
aggregate size or allocator address is assumed. The child timeout is 75 seconds,
the Rust process wrapper is 90 seconds, and root caps its outer gate at 100.

## Verification status

Native admission passed: 1 test, 0 failures, 6.63 seconds, process exit 0. Log:
`target/stdlib-work/lazy-outcomes-model.log`. The executed producer's complete
485,856-byte transcript and exact summary above matched the independent
reference: 16 cases, 1,536 commands, all 76 API/form/variant combinations and
616 selected callback invocations. Accepted sources are producer
`c340d6d61bd23f8236f3012f5cae6fa4d82e1a0095e0f7df71e395b844dca153`, oracle
`3c0f29378251ea5200fb23d53984dcc606af22234eeafaef2dbf511b3a661c4f`, and driver
`e2c4bce58c438792eeac740cee3797351e8cfc645206e649e2beb82270d0c749`.

Separately, host-only oracle controls passed in 0.139 seconds:
22 corruptions were rejected against a 485,856-byte reference transcript.
These include complete semantic mutants for eager invocation on skipped paths,
double invocation, wrong callback operands, lost callback-produced failures,
inverted filtering and reset invocation state, plus selected field corruption,
truncation and trailing bytes. This validates reference sensitivity and is
separate from execution of Lanius.

Focused native selector:

```text
cargo test --test stdlib_lazy_outcomes_model_execution lazy_outcomes_match_composed_states_and_selected_callback_effects -- --exact --nocapture
```

Host-only controls:

```text
python3 -B tests/fixtures/stdlib_lazy_outcomes_model/oracle.py controls
```

Acceptance targets the tested Linux x86_64 native output of the GPU compiler.
It does not claim GPU-device execution, other targets, arbitrary callbacks,
ownership/lifetime enforcement, dynamic closures, panic recovery or a proof.
