# Scoped stacks: Goose-style memory in Lanius

Status: design proposal, 2026-10-26. Phase S0 is implemented as
[`std::scope`](stdlib-scope.md) (2026-10-27); its result is under
[S0 result](#s0-result-go). The rest is not implemented.

## Summary

Make the default home of every dynamically sized value (`String`, `Vec<T>`,
records that contain them) a **compiler-managed data stack tied to a scope**.
Memory is reclaimed when the owning scope exits, by resetting a stack
pointer. There is no per-object `free`, and in ordinary code there is no
allocator argument and no lifetime annotation.

Two independent compile-time checks keep this safe:

1. **The root check.** It gives memory safety. Every reference has an
   inferred root (a local, a global or a temporary), and a reference may not
   outlive its root. This replaces per-program use-after-free proofs with one
   soundness theorem about the checker.
2. **The exclusivity check.** It gives cheap functional proofs and
   optimization. A `&mut` reference is never aliased. This is a much smaller
   borrow checker than Rust's, because lifetimes come from roots and are never
   written.

Data whose lifetime does not nest inside a scope uses an explicit store: a
global, a pool with typed handles, an `alloc::arena`, or the raw allocator.

Three ideas come from Odin and Jai: a per-frame scratch store reset in one
step, `distinct` types for handles, and struct-of-arrays layout.

## Why

- **Speed.** Most allocations in real programs fall into two groups:
  - one long-lived thing (a server's SDK client, configuration);
  - very many short-lived or same-lifetime things (strings built and used
    once, per-frame or per-request data, the nodes of a parse).

  The second group is what per-object `malloc` handles badly. Games and fast
  compilers use per-frame and per-string arenas for this. Goose makes that
  style the default and reports 1.13-1.19x the speed of the best safe Rust on
  its benchmarks.
- **Proof cost.** Today a Lanius program that wants memory safety either uses
  raw `ptr` code and proves it with separation logic, or trusts the stdlib.
  Proofs cost LLM tokens. A checker proved sound once in the verified compiler
  makes memory safety free for every program that passes it. Per-program
  proofs are left with only the properties the programmer cares about.
- **Defaults shape programs.** Rust's default, one heap object per value,
  makes the fast arena style the verbose one, because a `'arena` lifetime
  spreads through every signature. Haskell's lazy default shows how hard it is
  to escape a default. Lanius should make the fast style the short one.

## Background

### Goose

The main source is the Goose spec (v4 draft):
- **No heap.** Dynamically sized values live inline on a handful of data
  stacks. Scope exit resets stack pointers; nothing else frees memory.
- **Results built by the callee in the caller's storage.** A returned value
  is built directly in its receiving storage, so returning a growable array
  never copies it. Locals are moved by `return`; copies are written as
  `copy(x)`.
- **At most one growable value per stack, always on top.** Growth is a bump
  and never moves memory. Two growables that are live at the same time get
  different stacks. The compiler assigns stack indices by walking every
  specialization from `main`, and specializes functions per destination
  stack.
- **Roots instead of lifetimes.** Storing a reference requires its root to
  outlive the destination, and a returned reference's root must be visible to
  the caller. There are no lifetime annotations and no exclusivity rule.
- **Mutation-heavy trees** use `reusable` pools with a freelist. A stale
  reference into a pool is a logic error, not memory corruption.
- **Threads share nothing.** Each worker is compiled as a separate program
  with its own stacks. Globals are copied into each worker, and only flat
  values cross threads, through typed queues.

Sources:
- [Goose README](https://github.com/aardappel/goose)
- [Goose spec](https://github.com/aardappel/goose/blob/master/docs/goose_spec.md)
- [Goose benchmark summary](https://github.com/aardappel/goose/blob/master/bench/summary.md)

### Lanius today

- `std::vec::Vec<T>` owns a buffer from `alloc::allocator::alloc` and grows
  by reallocating.
- `alloc::arena` hands out raw `Block { data: ptr, length }` and `View<T>`
  values; `reset`/`clear` invalidate them with no compile-time check.
- References are shared `&T` only (`value.borrow()`). There is no `&mut`.
- Memory safety of `ptr` code is a proof obligation, not a checked property.

## Programming model

The syntax below is proposed. The point is what the programmer does not write.

### Temporary strings cost a pointer bump

```lanius
fn greet(names: &[String]) -> i32 {
    let total: i32 = 0;
    for name in names {
        // Built on the loop body's stack; freed when the iteration ends.
        let line = format("hello, {}\n", name);
        total = total + write_stdout(line.borrow());
    }
    return total;
}
```

The loop body is a scope, so each iteration's `line` is released at the end
of that iteration. Memory does not grow with the number of names.

### Returning a growable value never copies it

```lanius
fn words(text: &str) -> Vec<&str> {
    let out = Vec::new();
    for word in split_whitespace(text) { out.push(word); }
    return out; // built in the caller's destination, then moved
}

fn main() -> i32 {
    let input = read_stdin();
    let list = words(input.borrow()); // lives on main's stack
    return list.len() as i32;
}
```

The `&str` elements point into `input`. The root check accepts this because
`input` outlives `list` in `main`. Returning `words(read_stdin().borrow())`
directly would be rejected: the temporary would be the root, and it dies at
the end of the statement.

### Long-lived data lives in an outer scope

A server's client and configuration are locals of `main`, so they live for the
whole program without any heap. A per-request scope holds everything a request
builds:

```lanius
fn serve(client: &Client, listener: &Listener) {
    while (true) {
        let request = accept(listener);  // per-iteration scope
        let reply = handle(client, request.borrow());
        send(reply.borrow());
    } // everything the request built is gone here
}
```

### Lifetimes that do not nest use an explicit store

A cache entry added during one request and evicted during another does not
follow scope lifetimes. Such data goes into a store owned by an outer scope:

```lanius
let cache = Pool<Entry>::new();        // owned by main's scope
let handle = cache.insert(entry);      // Handle<Entry>, a typed index
let found = cache.get(handle);         // checked; a stale handle reads None
```

A handle is a typed, generation-checked index. A stale handle can be a logic
error, but never memory corruption. The root check still applies: a handle
may not outlive its pool.

### Frame scratch: allocate deep, release once

Scope stacks free a callee's temporaries when it returns. Some data must
outlive the callee but not the frame: debug strings built by many systems and
drawn at frame end, a render command list that gameplay, UI and particles all
append to, a server's per-request log lines. Odin's `context.temp_allocator`
and Jai's temporary storage serve this case, and Lanius takes it:

```lanius
while (running) {
    let frame = Scratch::new();          // root: this iteration's scope
    update(world, frame.borrow_mut());   // callees allocate into it
    render(frame.borrow());              // read what they built
}                                        // released at scope exit
```

- `Scratch` is a scope stack with a name. Allocating into it from any call
  depth is a pointer bump.
- Every allocation in it has the scratch's scope as its root (R2). Keeping a
  reference past the iteration is a compile error, where Odin's equivalent
  (using a temp string after `free_all`) is undefined behavior.
- The scope exit releases it, so there is no reset call to forget.
- An early `frame.reset()` takes `&mut Scratch`. The exclusivity check
  rejects it while any reference into the scratch is live. Until `&mut`
  exists (S4), scope exit is the only reset.

The scratch is passed as an explicit parameter. An ambient frame scratch
inherited by callees, like Odin's `context`, can be added later if passing it
gets tedious; it is a convenience, not a new rule, because its root is still
the scope that created it.

### Handles are distinct integers

Odin's `Handle :: distinct u32` makes a new type with `u32`'s representation
and no implicit conversion either way. Lanius adopts `distinct`:

```lanius
type EntityId = distinct u32;
type TextureId = distinct u32;
```

An `EntityId` cannot be passed where a `TextureId` or a plain `u32` is
expected; converting is an explicit `as`. `Pool<T>`'s `Handle<T>` is a
distinct index plus a generation, so handles from different pools never mix.
Arithmetic on a distinct type is available only if the declaration asks for
it (open question: the spelling).

### Struct-of-arrays layout

A `Vec` of records stores each record's fields together. Loops that read one
field of every record waste cache on the others. Odin's `#soa` and Jai's
SOA layouts store each field in its own array behind the same element syntax:

```lanius
let particles: Soa<Particle> = Soa::new();   // one array per field
for p in particles.iter_mut() { p.x = p.x + p.vx; } // touches x and vx only
```

`Soa<T>` is a library type over scope stacks: one growable array per field,
which by R4 needs one stack per field, or one stack with per-field capacity
doubling. Element access returns a view whose fields are references into the
field arrays. It needs field reflection over `T` at compile time, which the
generic machinery can provide without general compile-time execution.

### Errors teach the style

```text
error[LNC....]: this reference outlives the value it points into
  |     return words(read_stdin().borrow());
  |                  ^^^^^^^^^^^^ root: a temporary that ends here
  = help: bind the input to a local in the caller, or return an owned copy
```

## Rules

### R1. Storage classes

| Class | Holds | Freed |
|---|---|---|
| Native stack | fixed-size values | function return |
| Scope stack | dynamically sized values (default) | owning scope exit |
| Static | literals, constant globals | never |
| Global | values in global variables | program exit |
| Store | pools, `alloc::arena`, explicit heap | by the store's API |

Only the store row involves an allocator call in user code.

### R2. Roots

Every reference has one inferred root: a local, a global or a temporary.

- **Store rule.** A reference may be stored into a location owned by `L` only
  if its root's scope contains `L`'s scope.
- **Return rule.** A returned reference's root must be a parameter's root or a
  global, never a callee local or a temporary.
- Roots are inferred per function from its body and its callees' published
  signatures (R7). The programmer never writes them.

### R3. Results are written into the caller's destination

A call returning a dynamically sized value passes a destination: the stack
and slot of the receiving scope. The callee builds the result there. Its own
temporaries go on stacks above the destination's in-use set and are released
when the callee returns.

### R4. One growable per stack top

- A value that can still grow stays on top of its stack.
- A second growable that is live at the same time goes on another stack.
- Completed values can be buried under later allocations; buried values never
  move.
- Each function's stack use is a small number (its scratch stacks above the
  destination), computed by the compiler.

### R5. No implicit copies

Dynamically sized values are moved, never silently copied. `copy(x)` is
explicit, so the cost of every copy shows at its site.

### R6. Scopes are blocks

Every block is a scope, including loop bodies and `if`/`match` arms.
Releasing a scope's memory is a pointer reset per stack it used, a few
instructions.

### R7. Separate compilation: stack use is part of the signature

**This is the main departure from Goose.** Goose assigns stacks by walking the
whole program from `main`, which fights Lanius's dependency units and
incremental rechecks.

In Lanius, each function's published interface carries its **stack effect**:
- which parameter roots its result and returned references may point into;
- how many scratch stacks it needs above the caller's in-use set.

The type checker infers the stack effect within a unit and publishes it in the
unit interface, the same way checked signatures are published today. Callers
in other units read it and never look at the body.

At run time a function receives a small **stack table**: the current top of
each stack it may touch, passed in one register. Specializing a function per
stack set is an optimization the compiler may do within a unit, not a
requirement. That avoids Goose's code growth and keeps library code compiled
once.

## The borrow checker: keep a narrow one

Goose has no exclusivity rule; aliased mutation is allowed. Lanius should add
one, but only for `&mut`:

- **`&T`**: shared and read-only; any number may coexist.
- **`&mut T`**: exclusive. While it is live, its target has no other usable
  reference.
- **No lifetime syntax.** How long a reference is live comes from its root
  (R2). The checker only verifies exclusivity, which is a local dataflow
  check.

Why keep it:
1. **Cheap functional proofs.** With exclusive `&mut`, code translates into
   pure functions: `&mut x` becomes "take `x`, return the new `x`". That is
   what Aeneas does for Rust, and what the verified compiler's shallow
   extraction needs. Without it, every proof about aliased mutation needs a
   memory model.
2. **Optimization.** Exclusive references never alias, so the backend may
   keep their targets in registers and reorder accesses.
3. **Readable calls.** A call that can mutate an argument shows `&mut` at
   the call site.

What it costs: two mutable views into one array need a splitting API
(`split_at_mut`, disjoint index sets) instead of two plain references. Truly
shared mutable state goes into a pool and is addressed by handles; a handle is
an index, not a reference, so it is not subject to exclusivity.

Raw `ptr` code stays as the escape hatch, outside both checks, and carries
separation-logic proof obligations. An aliasing model such as Tree Borrows
would define the contract between raw pointers and checked references.

## Parallelism

Start from Goose's share-nothing model, then add the one thing a systems
language needs for speed.

1. **Workers and queues.** As in Goose: a worker has its own stack block, and
   only flat values cross threads, by copy through typed queues. It is
   race-free by construction.
2. **Fork-join, added for Lanius.** A scoped `parallel` block starts workers
   that may hold `&T` references rooted in the parent's scopes, because the
   parent waits for them before those scopes exit. With exclusivity, a worker
   may also receive a disjoint `&mut` piece (one half of a `split_at_mut`).
   That gives a parallel loop over a shared array without copying it, and the
   two checks still rule out data races. Each worker gets its own stacks for
   its temporaries.

## Proof story

Two theorems, each proved once in the verified compiler:

1. **Root soundness.** A program accepted by the root check never reads or
   writes released stack memory. The Lean model is a stack of frames per data
   stack; scope exit truncates it.
2. **Exclusivity gives pure translation.** For code without raw `ptr`, the
   shallow extraction into pure Lean functions is faithful.

Per-program proofs then cover only functional correctness, stated about pure
Lean functions. `ptr` code, FFI and `unsafe`-style stores keep explicit
separation-logic obligations, and should be rare and small.

## Fit with the GPU compiler

- **Root inference** is a dataflow over HIR, the same shape as the existing
  inference rounds: each expression's root is the minimum scope among its
  operands' roots, and calls use their callees' published stack effects.
- **The exclusivity check** is a per-function liveness pass over references,
  computed with segmented scans over the scheduled rows, like existing
  liveness.
- **Scratch stack counts** are a maximum over each function's call tree in its
  unit: a tree reduction.
- **Codegen.** Destinations and the stack table are ordinary hidden
  parameters, and scope exit is one store per stack used.

## Phases

| Phase | Work | Evidence before moving on |
|---|---|---|
| S0 | `std::scope::Stack` and `Scratch` library types with explicit use, no compiler support | Goose-style rewrites of 3 benchmarks (string-heavy, per-request, tree) beat today's `Vec`/allocator versions |
| S1 | Root check for `&T` | Escape tests reject; stdlib passes or has a documented list of fixes |
| S2 | Destination-passing returns, stack table parameter | Returned `Vec`/`String` are never copied (checked in emitted code) |
| S3 | `Vec`/`String` default to scope stacks; `alloc::` stores stay explicit | Stdlib and sample programs pass; peak memory on S0 benchmarks matches the hand-written versions |
| S4 | `&mut` with the exclusivity check | Aeneas-style extraction works on a `&mut` pilot in the mini compiler |
| S5 | Fork-join `parallel` blocks | Parallel speedup on a shared read-only array; race tests reject |

S0 is cheap and decides whether the rest is worth it. If the library version
is not faster in Lanius, compiler support will not fix that.

### S0 result: go

Measured on 2026-10-27 on the target laptop: Ryzen 9 5900HX, x86-64 ELF
from `laniusc --emit x86_64`, best of 5 wall-clock runs. Checksums agree
across each workload's versions. The sources, runner and raw table are in
`benchmark_artifacts/scoped_stacks_s0`.

| Workload | `Vec` / per-node allocation | `alloc::arena` | `std::scope` | vs `Vec` | vs arena |
|---|---|---|---|---|---|
| strings: 200,000 lines built byte by byte | 5.62 s | 0.46 s | 0.30 s | 18.7x | 1.53x |
| requests: 50,000 × (24 headers + reply) | 3.78 s | 0.58 s | 0.43 s | 8.8x | 1.35x |
| tree: 20 trees of depth 15, pointer-linked | 8.73 s, 262 MB | 0.40 s | 0.23 s | 37.6x | 1.72x |
| layout: 200,000 particles × 50 steps | 0.164 s (records) | | 0.058 s (`Soa`) | | 2.8x |

What the numbers mean:

- **The `Vec` column overstates the case.** Today's native allocator makes
  one `mmap` per `alloc` and one `mremap` per `realloc`. Any bump allocator
  beats it by an order of magnitude.
- **The fair comparison is the arena column.** Both sides bump-allocate
  there. The stack still wins by 1.35-1.72x.
- **Where the gain comes from:**
  - in-place growth of the newest growable: the arena's buffers copy when
    they double;
  - two ends, so a request's headers and its reply both grow in place at
    once;
  - a two-store release, where the arena resets chunk by chunk.
- **Layout.** Struct-of-arrays columns are 2.8x faster than records when a
  loop touches two of eight fields.

The criterion was that the library rewrites beat today's versions; they do,
by 8.8-37.6x, and they also beat the arena. **S1 is go.** Two things S0
showed:

- **Packed types run the other way.** In today's raw layout, packed
  `u8`/`i32` views ascend and every other view descends. One stack end per
  direction is what makes in-place growth work for both. S2/S3 must keep
  that, or change the layout contract first.
- **The default allocator should change anyway.** An `mmap` per allocation
  is the bottleneck of every `Vec` and `String` today, whatever S1-S3
  decide.

## Borrowed from Odin and Jai

| Idea | Decision |
|---|---|
| Per-frame scratch reset in one step | Taken: `Scratch`, released at scope exit, checked by roots |
| `distinct` types | Taken: handles and ids |
| Struct-of-arrays layout | Taken: `Soa<T>` library type |
| Implicit `context` allocator | Later, as a convenience over an explicit `Scratch` |
| Compile-time execution | Deferred: the compiler runs on the GPU, so it would need a GPU evaluator for Lanius code |
| Unchecked manual memory as the default | Not taken: stores and raw `ptr` stay available, but the default is checked |

## Open questions

- **Recursion.** Goose cannot keep growable data across a recursive call,
  because its stack count is fixed. With a run-time stack table, a recursive
  call could take a fresh stack from a small pool. That needs a design and a
  bound.
- **Unbounded outer accumulation.** A long loop that appends to a value owned
  by an outer scope grows that scope's stack forever. That is correct, but it
  should be visible, for example in a lint on growth in `while (true)`.
- **`Soa<T>` and R4.** One growable per stack top means a `Soa<T>` with
  many fields needs many stacks, or a layout that reserves per-field capacity
  and moves fields when it grows. Measure both in S0.
- **The current stdlib.** `alloc::arena`'s raw `Block` API and `Vec`'s
  allocator calls would become the store layer under the default. The
  migration order and the raw-`ptr` surface left over need an inventory.
- **Wasm.** One linear memory holds all stacks; each stack needs reserved
  space or a way to grow a stack that is not the last.
