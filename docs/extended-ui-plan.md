# Reactive native UI framework

The target is a Lanius-native desktop UI framework with GPUI's composable,
GPU-rendered elements and a run-once, fine-grained reactive programming model.
The element tree persists. Components construct it once; tracked computations
update individual properties and explicit dynamic regions afterward.

The framework is part of the extended standard library. Its implementation
lives under `extended/ext/` and uses the `ext::` namespace alongside the window,
GPU and reactive graph modules. UI module names are proposed until implemented.

This is a design and implementation plan, not an inventory of working APIs.
The existing executable pieces are `ext::window`, `ext::gpu` and the
[reactive graph kernel](extended-reactive-graph.md). Closure-based
application APIs, UI layout, text rendering, input routing and accessibility
are not implemented by those modules.

## Decisions

1. **The unit of change is a binding.** A signal read during a label's binding
   subscribes that binding, not its containing view. Components are construction
   functions, not the default invalidation boundary. Dynamic branches and keyed
   lists have their own retained identities and lifetime scopes.
2. **Keep the layers independently incremental.** Dependency precision is not a
   claim of cheap layout or painting. Style, measurement/layout, paint records,
   GPU uploads, damage/compositing and accessibility changes get separate queues
   and counters. An unchanged value does not automatically schedule a frame.
3. **Typed styles and builders first.** GPUI-like composition does not require a
   CSS parser, selector engine or cascade. Start with explicit typed properties,
   row/column layout, padding, gap, constraints and flex growth. Richer styling
   can be added without changing state or node identity.
4. **Signals hold arbitrary application types.** Do not expose separate
   `SignalBool`, `SignalInt` or a closed universal UI-value enum. Reactive graph
   metadata must not depend on a signal's value representation or callback type.
5. **UI state is single-threaded initially.** Worker results enter through a
   queued UI-thread message; workers do not mutate nodes or reactive cells.
6. **Use explicit runtime scopes now.** Scope disposal cancels observers and
   invalidates generational handles. Future borrow/affine/effect features should
   strengthen the contract, not require a different update model.

The article motivates binding-sized updates and warns that signals alone do
not eliminate engine-wide work. Its benchmark harness was unpublished and its
reported numbers excluded the window/compositor/input path; they are not our
performance targets or independently verified comparisons.
[Source: A Critique of GPUI](https://blog.zortax.de/posts/a-critique-of-gpui).

## Reactive runtime contract

Signals are mutable sources; memos are pure cached computations; effects are
sinks. Reads inside a running computation record its actual dependencies.
A successful rerun replaces that dependency set, including conditional reads.
A failed computation must not leave a half-replaced subscription set.

Invalidation pushes through the affected graph; evaluation pulls dependencies
current before running a consumer. A diamond must not expose a mix of old and
new inputs or run its sink twice in one settled batch. An unchanged memo result
suppresses downstream effects. Writes are batched at event boundaries, with an
explicit flush for deterministic tests and read-your-writes for derived reads.
Cycles, recursive entry and use of disposed handles produce explicit errors.
The first evaluation profile forbids reactive writes inside computations and
binding effects; event handlers are the mutation boundary. General effect
feedback needs a separate, bounded scheduling contract before it is admitted.

An explicit equality policy controls publication: a checked `set_if_changed`
requires an equality operation; an explicit mutation/publication path does not
silently assume arbitrary values have cheap or meaningful equality. UI property
bindings compare their own outputs before dirtying layout/paint. These details
are our proposed contract, not an exact copy of Leptos behavior.
[Leptos graph design](https://book.leptos.dev/appendix_reactive_graph.html).

Ownership has a separate scope tree. Removing a dynamic branch disposes its
observers/resources. Reordering keyed children retains their identity, focus,
local state and subscriptions. Removing one key disposes precisely that child's
scope. Cleanup must remove pending work as well as dependency edges. A handle
that escapes its scope must fail after disposal; reusing an arena slot must not
revive it. Typed destruction of signal values and captured environments is part
of this contract, not an optional widget-layer cleanup convention.
[Leptos ownership design](https://book.leptos.dev/appendix_life_cycle.html).

## Retained tree and frame pipeline

Keep four distinct structures: the reactive dependency graph, ownership scopes,
retained element/layout tree, and paint/compositing scene. None is implicitly
substituted for another. The lifecycle is:

```text
native input / completed worker message
  -> event handler mutations
  -> settle affected memos and bindings
  -> apply precise property/structure changes
  -> measure and lay out affected dependency paths
  -> update affected paint records and accessibility records
  -> upload changed records / composite damage
  -> submit only when pixels changed or an exposure requires presentation
```

A paint-only color change must not trigger measurement or layout. A text change
may require shaping and measurement; if its measured size is unchanged, stop
layout propagation. If a child's intrinsic size changes, ancestors and siblings
whose geometry depends on it may legitimately need layout. "Fine-grained" does
not mean every update is constant time. Scrolling, transforms and clipping have
explicit paint/composition dependencies. Dirty queues must not be implemented
as an unconditional walk of every retained node at each frame.

The first renderer can submit a complete display list while retaining nodes and
paint records, but that limitation must be measured and labeled. It must not be
called damage-based rendering merely because its reactive callbacks are precise.
The Vulkan foundation currently has a fixed graphics profile; batched UI
geometry, alpha blending, clipping/scissor support, glyph atlases and text shaping
need real work. Text should use established shaping/rasterization libraries
(HarfBuzz/FreeType or platform services), with Lanius owning UI policy and caches.
A bitmap counter demonstration is not a finished text system.

Input needs hit-testing in paint order, focus, pointer capture, keyboard
activation and bubbling/capture routing. Accessibility needs roles, names,
state and actions from the retained semantic tree, not reverse engineering of
pixels. Text input, IME, selection, clipboard, scrolling, virtualized lists and
multiple windows are explicit later milestones; none is a silent stub.

## Callback support and ownership

`claude/language` commits `7ad4046ff` and `00d3f2dbe` supply the language
capabilities needed to start the retained UI layer. `move` closures are owned
values. `alloc::callback` stores different closure types behind one signature:
`Callback<T,U>`, `Source<U>`, `Handler<T>` and `Action`. They can be returned from
a constructor, stored in a non-generic field, and invoked later. The entry
mechanism uses `call_ptr`; function types and trait objects are not required.
See [the stored callback contract](language-ergonomics.md#stored-callbacks) and
its [executable constructor/handler fixture](../tests/fixtures/language/closure_stored.lani).

The earlier `fn() -> i32` capability candidate is superseded: named
`alloc::callback::Source<i32>` provides the required behavior without that
proposed function-type syntax. Named callback structs and generic components
also remain useful; the runtime graph does not depend on the authoring syntax.

The next work is library integration and lifetime management. `destroy()` frees
the callback block, but does not destroy resources owned by captures. Copies
alias that block, and `move` copies captures without enforcing affine ownership.
UI scopes must own callback registrations, cancel them before disposal, and
release each callback exactly once. Initial bindings can capture signal/element
handles whose backing is owned by the scope. Arbitrary owning captures need an
explicit cleanup contract; retaining a borrow to a temporary remains invalid.

Stored callbacks use shared argument/result slots and must not be called
concurrently through aliased copies. The initial UI runtime is single-threaded;
its reactive graph already rejects reentrant flush and structural mutation
during evaluation. Callback allocation currently traps on failure. A fallible
registration profile would need a fallible storage API before promising recovery.
These are current library contracts, not reasons to invent an app-wide callback
ID switch or add another compiler feature before starting the UI.

The closure frontend still requires typed captured locals and rejects nested
closures, `self`, and captures involving the enclosing function's type
parameters. Those limitations constrain some future authoring patterns but do
not prevent the first concrete signal/binding/event-handler slice. The current
stored callback execution target is native x86_64; Wasm is unsupported.

## Milestones and acceptance gates

1. **Reactive kernel:** dynamic dependency replacement, memo equality, batching,
   diamond consistency, cycle detection, disposal, stale-handle rejection and
   sparse-update counters, all tested through executable programs.
2. **Typed public state/callback ownership:** `Signal<T>`, `Memo<T>`, scoped
   effects, closure/callback storage and destruction; no leaked captures or
   stale subscriptions after branch replacement.
3. **Retained elements:** label, button, row/column, binding-sized updates,
   focus/keyboard/mouse activation, one real native window. A counter with two
   independent branches must show which bindings/layout/paint work ran.
4. **Graphics and text:** batched quads, clipping, blending, shaped text, atlas
   ownership synchronized with asynchronous GPU submissions. GPU canvas
   integration can reuse the existing Life simulation.
5. **Dynamic UI:** conditional regions, keyed lists, scrolling/virtualization,
   text editing and accessibility. State survives a keyed reorder; removed
   children stop receiving updates and input.

The stress fixture should contain 100, 1,000 and 10,000 retained rows. Test an
isolated label, equal write, hover color, intrinsic-size change, keyed insertion,
reorder/removal and a batched burst. Record callback evaluations, graph edges
visited, layout nodes visited/recomputed, text shapes, paint records, upload
bytes, draw calls, live allocation bytes, and native frame latency separately.
No-op and sparse changes must have explicit work-count assertions. Creation,
disposal and memory cost belong in the report alongside update latency.

Prioritize a few working widgets and a reproducible application before adding a
large declaration inventory. Performance claims require our own executable
measurements; correctness, supported targets and remaining dependencies remain
visible in module guides.
