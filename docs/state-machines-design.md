# State machines: a `machine` item in Lanius

Status: design proposal, 2026-10-27. Nothing here is implemented.

## Summary

Add one item, `machine`, that declares a finite state machine: its states
with per-state data, the event type it consumes, the output it produces, and
every transition. The compiler checks three things that hand-written
`enum State` code cannot:

1. **Every (state, event) pair is handled.** Each state lists its events with
   no top-level `_` for enum events, so adding an event or a state breaks the
   build at every place that must decide what to do with it.
2. **Every state is reachable and no state is a silent dead end.** A state no
   `goto` can reach from `start` is an error. A state that cannot leave must
   be marked `final`.
3. **Only the machine changes its state.** Code outside the machine can read
   the state but never assign it. All transitions are the `goto`s in the
   declaration.

A machine elaborates into an ordinary enum, a struct and a `step` function
containing a `match`: the code a programmer writes by hand, so `step` costs
nothing and Core gains no construct. A second entry point, `run`, drives the
machine over a slice with each `goto` lowered to a direct jump. The machine
extracts to Lean as `step : State → Event → Output × State`, and properties
are invariants proved by induction. Not in scope: typestate, nested states,
entry/exit actions. Generators come later as sugar over machines (M5).

## Why

- **Library code is full of hand-written machines.** `ext::openssl_tls`
  (`State { Handshake, Open, PeerClosed, Closing, Closed, Failed }`),
  `ext::sqlite`, `ext::archive_extract` and others keep a state enum in a
  struct field and assign it from many functions. A grep finds 73
  `InvalidState` sites in 15 stdlib and extended files. Each is a runtime
  check for a pair nobody wrote down in one place. With a machine those pairs
  are listed per state, checked for completeness, and visible to proofs.
- **Proof cost.** A state field assigned from ten functions needs ten
  preservation proofs. A machine has one transition function: one induction.
- **Speed.** Lexers, decoders and protocol parsers are hot loops over a
  state, where a loop around a `match` funnels every transition through one
  dispatch branch. `run` jumps directly.

## Background

- **Typestate** puts the state in the type, so a call in the wrong state is a
  compile error. In Rust it is a library pattern where transitions consume
  `self` ([Biffle](https://cliffle.com/blog/rust-typestate/)); the
  [`sm`](https://docs.rs/sm) crate generates it from a macro and adds an
  `as_enum()` view for runtime dispatch. It needs the state to be known
  statically at each use.
- **[`statig`](https://github.com/mdeloof/statig)** (Rust): states are
  handlers with state-local storage; a handler returns `Transition(next)`,
  `Handled` or `Super`; no heap. The handler-returns-a-transition shape is
  taken here.
- **[P](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming/)**
  ([repo](https://github.com/p-org/P)): communicating machines whose checker
  treats an unhandled event in any state as a bug; `ignore` and `defer` are
  explicit; specifications are monitor machines. Used for the Windows 8 USB
  stack and AWS protocols. Taken: every pair handled, spec monitors. Left
  out: queues, `defer`, model checking.
- **[Harel statecharts](https://doi.org/10.1016/0167-6423(87)90035-9) and
  [SCXML](https://www.w3.org/TR/scxml/)** add nesting, parallel regions,
  history and entry/exit actions. They scale to large models, but the step
  semantics become hard to state (SCXML's macrostep algorithm is pages long).
- **Esterel and Céu** react to each input in one run-to-completion step.
  Esterel's first compiler built one automaton for the whole program, which
  grew exponentially with parallel composition
  ([Edwards](https://www.cs.columbia.edu/~sedwards/papers/edwards2004compiling.pdf)).
  [Céu](https://github.com/fsantanna/ceu) adds `await` on events in
  structured code. Lesson: one `step` per event, no implicit products.
- **Erlang [`gen_statem`](https://www.erlang.org/doc/system/statem.html)**:
  in `state_functions` mode each state is a function of the event and a
  machine-wide `Data`. That split is taken here.
- **Zig labeled `switch`** (`continue :sw value`,
  [#8220](https://github.com/ziglang/zig/issues/8220),
  [0.14.0 notes](https://ziglang.org/download/0.14.0/release-notes.html)):
  a comptime-known operand becomes an unconditional branch, a runtime one
  gets a branch per site, instead of one shared indirect branch in a loop.
- **Async and generators lower to machines.** Rust's
  [coroutine pass](https://doc.rust-lang.org/beta/nightly-rustc/rustc_mir_transform/coroutine/index.html)
  makes an enum with one variant per suspension point holding the locals
  live across it ([walkthrough](https://blag.nemo157.com/2018/12/09/inside-rusts-async-transform.html));
  C# ([`IAsyncStateMachine`](https://learn.microsoft.com/dotnet/api/system.runtime.compilerservices.iasyncstatemachine)),
  [Kotlin](https://kotlinlang.org/spec/asynchronous-programming-with-coroutines.html)
  (a `label` field) and Swift ([LLVM coroutines](https://llvm.org/docs/Coroutines.html))
  do the same. A [2026 Rust project goal](https://rust-lang.github.io/rust-project-goals/2026/async-statemachine-optimisation.html)
  targets the space naive generation wastes.

## Programming model

The syntax is proposed. Arms use `match` arm syntax.

### A reactive machine

```lanius
pub enum Input { Open, Close, Lock(u32), Unlock(u32) }
pub enum Reply { Done, Ignored, WrongCode }

pub machine Door on Input -> Reply {
    start Closed;

    state Opened {
        Input::Close -> goto Closed with Reply::Done,
        Input::Open | Input::Lock(_) | Input::Unlock(_) -> stay with Reply::Ignored,
    }
    state Closed {
        Input::Open -> goto Opened with Reply::Done,
        Input::Lock(code) -> goto Locked(code) with Reply::Done,
        Input::Close | Input::Unlock(_) -> stay with Reply::Ignored,
    }
    state Locked(stored: u32) {
        Input::Unlock(code) -> {
            if (code != stored) { stay with Reply::WrongCode; }
            goto Closed with Reply::Done;
        },
        Input::Open | Input::Close | Input::Lock(_) -> stay with Reply::Ignored,
    }
}

fn main() -> i32 {
    let door = Door {};                      // starts in Closed
    let reply = door.step(Input::Lock(7));   // Reply::Done, now Locked(7)
    return match (door.state()) { Door::State::Locked(_) -> 0, _ -> 1 };
}
```

- `on Input -> Reply` names the event type and the output type. A machine
  with no output writes `-> ()` and plain `goto S;`.
- `state Locked(stored: u32)` declares per-state data. Its fields are in
  scope in that state's arms, by value.
- `goto S(args) with out` ends the arm: the next state, its data and the
  output. `stay with out` keeps the current state and its data unchanged.
- `door.state()` returns a copy of the state as the enum `Door::State`, for
  reading. There is no way to assign it.

### Machine-wide data

Data every state needs (a socket handle, limits, counters) is declared as
fields before the states, like `gen_statem`'s `Data`, and arms use them
through `self`:

```lanius
pub machine Session on Event -> Step {
    handle: i32,
    limits: Limits,
    start Handshake;
    state Handshake {
        Event::Ready -> {
            if (!handshake(self.handle)) { goto Failed with Step::Error; }
            goto Open with Step::Progress;
        },
        Event::Write(_) | Event::Read -> stay with Step::NotYet,
        Event::Close -> goto Closed with Step::Done,
    }
    // Open, Closed, and `final state Failed` ...
}
```

The constructor is a struct literal of the fields,
`Session { handle: fd, limits: limits }`. The `start` state takes no data,
so construction never chooses a state.

### A driven machine: `run`

When the events are already in memory, `run` feeds a slice through the
machine and returns when the slice ends. Integer event types use one binding
arm, so `_` is allowed only there (R3).

```lanius
machine SumNumbers on u8 -> () {
    total: i64,
    start Between;

    state Between {
        c -> {
            if (is_digit(c)) { goto InNumber((c - 48) as i64); }
            stay;
        },
    }
    state InNumber(value: i64) {
        c -> {
            if (is_digit(c)) { goto InNumber(value * 10 + (c - 48) as i64); }
            self.total = self.total + value;
            goto Between;
        },
    }
}

fn sum(text: &[u8]) -> i64 {
    let m = SumNumbers { total: 0 };
    m.run(text);
    return match (m.state()) {
        SumNumbers::State::InNumber(v) -> m.total + v,
        SumNumbers::State::Between -> m.total,
    };
}
```

End of input is not an event. The caller reads the final state, as above.

### Errors

```text
error[LNC....]: state `Locked` does not handle `Input::Close`
  |     state Locked(stored: u32) {
  |           ^^^^^^ add an arm, e.g. `Input::Close -> stay with ...`

error[LNC....]: state `Draining` is unreachable from `start Idle`

error[LNC....]: state `Closed` has no `goto` to another state
  = help: mark it `final state Closed` if the machine is meant to stop here
```

## Rules

### R1. Elaboration

A `machine M on E -> O` elaborates to:

```lanius
pub enum M::State { /* one variant per state, with its data */ }
pub struct M { /* machine-wide fields */, state: M::State }   // `state` private
impl M {
    pub fn step(&mut self, event: E) -> O {
        match (self.state) { /* one arm per state: match (event) { ...arms } */ }
    }
    pub fn state(&self) -> M::State { return self.state; }
    pub fn run(&mut self, events: &[E]) { /* see Lowering */ }
}
```

`goto S(a) with o` is `{ self.state = M::State::S(a); return o; }`, and
`stay with o` is `return o;`. Nothing else is generated. `&mut self` exists
since scoped-stacks S4's first step (2026-10-27).

### R2. Arms end in a transition

Every path through an arm ends in `goto` or `stay`. This is the existing
missing-return check: an arm is typed as returning a hidden transition type,
and `goto`/`stay` are its only `return` forms. A plain `return` inside an arm
is an error.

### R3. Every pair is listed

Each state's arms are a `match` over `E`, checked by the existing
exhaustiveness check. If `E` is an enum, a top-level `_` or bare binding arm
is rejected; alternatives with `|` and `_` inside payloads are allowed. If `E`
is an integer, the last arm may be a binding or `_`. Rationale: the bug class
is "added an event, forgot a state"; a wildcard reintroduces it. It also
keeps extracted Lean matches exhaustive (no wildcard equation lemmas).

### R4. Reachability and dead ends

The compiler builds the graph with one edge per `goto` (ignoring conditions,
so it over-approximates). Every state must be reachable from `start`. A state
with no edge to a different state must be declared `final`, and a `final`
state with such an edge is an error. A machine has at most 256 states.

### R5. The state is private

Only `goto`/`stay` change `state`. `state()` returns a copy. Outside code can
match on it but not construct an `M` in a chosen state. So every state an `M`
can ever hold arises from `start` by declared transitions, which is what makes
induction proofs complete.

### R6. No typestate

The state is not part of `M`'s type. A wrong (state, event) pair gets an
explicit arm, usually `stay with` an error output. Sessions and decoders
change state on runtime input and live in fields and pools, where no static
state exists; flow-sensitive types would break local inference's rule that a
binding's type is readable from its own line; and "in states X and Y,
`Write` yields `Step::NotYet`" is one Lean lemma over `step`.

A typestate library API (a builder whose `finish` consumes `Ready`) can still
be written with structs and moves; it needs no machine support.

### R7. Not in the first design

Entry/exit actions (hidden code at every `goto`; call a helper instead),
nested and parallel states (write a struct of machines), and deferred events,
queues and timers (the caller owns the event source; a timeout is an event).

## Lowering

**`step`** is R1's code: a `match` on the state tag, then a `match` on the
event, then a tag and payload store. It is the code a programmer writes by
hand, with the same enum layout, so there is nothing to optimize away. A
codegen test compares the emitted rows of `Door::step` with a hand-written
`enum` + `match` version and requires them to be identical.

**`run`** lowers each state to a block and each `goto` to a jump:

```text
Between:   if (i == n) { store Between; exit }
           c = events[i]; i += 1
           if is_digit(c) { value = c - 48; jump InNumber }
           jump Between
InNumber:  if (i == n) { store InNumber(value); exit }
           c = events[i]; i += 1
           if is_digit(c) { value = value * 10 + (c - 48); jump InNumber }
           total += value; jump Between
```

- Every `goto` target is static, so each is an unconditional jump: no
  dispatch branch at all, not even Zig's per-site one.
- Per-state data stays in locals (`value`); the tag and payload are stored
  only on exit. A hand-written `while` around a `match` stores and reloads
  the tag on every byte and shares one dispatch branch.
- Code size is one copy of each arm, as in `step`. Each entry point is
  generated only if used.

## Generators and async: later, as sugar

A function that suspends is a machine whose states are its suspension points
and whose per-state data is the locals live across each point, as in Rust's
coroutine pass. Lanius will define `gen fn` that way, as an elaboration into
a `machine`, so it inherits R1-R5 and the proof story with no new semantics.

It is phase M5, not M1. A suspended frame's dynamically sized locals must
survive while the caller keeps using its stacks, which conflicts with R4 of
the scoped-stacks design (one growable per stack top) and needs its own
design; explicit machines avoid this because their data is declared (below).
And Lanius has `std::poll` but no executor: a machine plus a poll loop covers
servers today and shows which async surface is worth adding.

## Fit with scoped stacks and `&mut`

- **The machine lives in its owning scope.** A local machine is released with
  its scope; a long-lived one is a local of `main` or sits in a `Pool`.
- **Per-state data is fixed size, or references and handles rooted outside
  the machine.** `goto S(r)` stores `r` into the machine, so the root check's
  store rule applies: `r`'s root must contain the machine's scope. A growable
  `Vec` or `String` cannot be per-state data, because a long-lived machine
  cycling through states would grow its scope stack forever. Buffers are
  machine-wide fields allocated once and reused, which is what
  `ext::openssl_tls` already does with its reader and writer buffers.
- **Each `step` is a scope.** An arm's temporaries are released on return.
- **`&mut`.** `step` and `run` take `&mut self`. Today's exclusivity check
  works at calls: `m.step(e)` is rejected when `e` reaches `m`, so no
  argument observes a half-done step. With full S4's liveness check, a
  reference into the old payload also cannot be live across `goto`, because
  `goto` is a write to `self.state`. No machine-specific borrow rule is
  needed.
- **Workers.** A machine with only flat data can cross a worker queue.

## Fit with the GPU compiler

- **Parsing.** New productions for `machine`, `state`, `final`, `start`,
  `goto ... with`, `stay ... with`. Arms reuse the match-arm production.
- **Elaboration by reinterpretation, not rewriting.** Each machine row is
  classified as the enum, struct, function or match row it plays in R1. State
  rows are variant rows; a state block is a match arm whose pattern binds the
  state's fields. The type checker and codegen then see the rows they already
  handle. No tree rewrite pass, no new inference round, and little new kernel
  code against the shader size budget.
- **R3** is the existing exhaustiveness pass plus a per-arm flag ("top-level
  wildcard") reduced over the machine's segment.
- **R4.** Each `goto` row is an edge: its source state comes from a
  segmented scan, its target from name resolution. Reachability is a bit
  matrix (at most 256 x 256 per machine, in a buffer) closed by 8 squaring
  rounds, each parallel over rows and words with no local arrays. Dead ends
  are a segmented count of edges leaving their source.
- **`run` codegen.** Block labels are state indices from a prefix sum over
  state rows. Each `goto` row lowers to a fixed number of LIR rows (assign
  payload locals, jump), so row offsets come from the usual scan.

## Proof story

Extraction emits the elaborated enum and `step` as Lean definitions. The
output comes first, as for any function with a `&mut` parameter:

```lean
namespace Door
inductive State | opened | closed | locked (stored : BitVec 32)

def step : State → Input → Reply × State
  | .closed, .lock code    => (.done, .locked code)
  | .locked s, .unlock c   => if c ≠ s then (.wrongCode, .locked s) else (.done, .closed)
  -- one equation per arm, exhaustive
end Door
```

The standard library carries the generic run and its induction lemma, proved
once:

```lean
def Machine.run (step : S → E → O × S) (s : S) : List E → S
  | []      => s
  | e :: es => Machine.run step (step s e).2 es

theorem Machine.inv_run (h0 : Inv s) (hs : ∀ s e, Inv s → Inv (step s e).2) :
    Inv (Machine.run step s es)
```

A per-program proof is then the invariant, its start case, and one case per
arm. R5 makes this complete: no state reachable at run time is missed.

- **Machine-wide data** extracts as a product, `Data × State`, by the pure
  translation of `&mut` that the mini compiler's pilot uses
  (`formal/MINI_COMPILER.md`, "Exclusive references"): `step` returns the
  output and the updated machine. **Host calls** in arms
  extract into the existing `World` model; the induction is unchanged.
- **Trace properties** ("no `Wrote` output before `Open`") use a spec monitor
  as in P: a second machine that steps on outputs and has an `error` state.
  The proof is an invariant over the pair that `error` is never reached.
- **Compiler side.** `step` adds nothing: it is elaborated into constructs the
  verified compiler already covers, so only an elaboration lemma is needed.
  `run`'s direct-jump lowering needs one theorem, proved once, that the
  emitted blocks compute `Machine.run step s events`. It is a CFG
  simulation proof and goes into the mini compiler first.

## Phases

| Phase | Work | Evidence before moving on |
|---|---|---|
| M0 | No compiler change. Hand-write `ext::sqlite`'s statement state and one byte scanner as `enum` + `step`; extract `step` to Lean; prove one invariant with `Machine.inv_run` | Proof is short (one case per arm); a loop-switch scanner benchmark gives the baseline for `run` |
| M1 | `machine` with `step` and `state()`, R1-R5, elaboration by reinterpretation | Codegen test: `step` rows equal the hand-written version; `ext::openssl_tls` `State` ported, its state assignments outside the machine gone |
| M2 | Lean extraction of machines; `Machine` library lemmas; spec monitors | One trace property of the TLS session proved |
| M3 | `run` with direct-jump lowering | Scanner beats the M0 loop-switch baseline on the laptop; lowering theorem proved in the mini compiler |
| M4 | Payload references across `goto` (after scoped-stacks S4's liveness check) | Exclusivity rejects a reference to old payload across `goto` |
| M5 | `gen fn` as sugar over `machine` | A design for suspended scope-stack data; iterator adapters rewritten as generators match hand-written speed |

M0 is cheap and decides whether the checks and proofs pay off before any
grammar changes.

## Open questions

- **Spelling of the output.** `goto S with out` reads well but adds a keyword.
  `-> ()` machines never write it. Revisit after porting two real machines.
- **Hierarchical states.** TLS and HTTP sessions repeat the same `Close` and
  `Fault` arms in many states. A `group` of states sharing arms is the
  smallest form of nesting; it must keep R3 and extraction simple.
- **Generic machines** (`machine Retry<T>`) should follow generic enums.
- **`run` over iterators.** M3 takes `&[E]`. Running over an `Iterator`
  needs the iterator's `next` inlined into each state block.
- **Early exit from `run`** at a `final` state, reporting the position.
- **Growable per-state data.** A per-machine `Scratch` reset when entering a
  named state would allow owned buffers in states. It needs a root rule for
  data that dies on a transition rather than a scope exit.
- **The 256-state cap.** Generated lexers can exceed it. Larger machines need
  BFS rounds instead of a fixed squaring count, or a split into sub-machines.
