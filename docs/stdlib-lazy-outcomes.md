# Lazy Option and Result composition

`core::option` and `core::result` provide nineteen callback operations, each
as a free function and a method. They invoke only the callback selected by
the active variant. The [fixed plan](library-lazy-outcomes-plan.md) defines
this increment. All eight new library groups and four current application
groups pass on the finite native Linux x86_64 profile. Six selected old-family
regressions pass separately. Earlier
[eager-composition receipts](stdlib-outcome-composition.md) retain their
original source and API scope.

## One callback protocol

The import-free `core::function` module owns both callback traits:

```lani
pub trait Mapper<T,U> {
    pub fn apply(&self, value:T) -> U;
}
pub trait Producer<T> {
    pub fn produce(&self) -> T;
}
```

Implement `core::function::Mapper` for callbacks with an input, and
`core::function::Producer` for callbacks without one. Iterators, slice
segmentation and map/vector editing use this same Mapper identity.
`core::iter` retains its iterator, folder, sink and retirement traits; it
does not provide a Mapper alias. Existing callback implementations must use
the new path. Historical compiler captures keep their original source paths
and hashes; reproduce them with their recorded pre-migration source closure.
A current-module import failure is not a reproduction of the old compiler
behavior. They are not current import examples.

Callbacks are borrowed nominal values with static trait dispatch. This adds
neither closures nor dynamic trait objects. Each bound must hold even when
the runtime variant would skip that callback. Callback objects, eager
fallbacks and other ordinary arguments are evaluated before entry, without
a promised argument evaluation order. **Laziness controls invocation, not
construction.**

## Option operations

In this table, `value` is `Option<T>`. Every callback argument is a reference.
Each free function takes `value` first; its matching method takes the
remaining arguments in the same order.

| Operation | Callback bounds | `Some(t)` | `None` |
| --- | --- | --- | --- |
| `map<U,M>(mapper)` | `M: Mapper<T,U>` | Call once; return `Some(mapped)` | `None<U>` |
| `map_or<U,M>(fallback:U, mapper)` | `M: Mapper<T,U>` | Call once | Return the eager fallback |
| `map_or_else<U,D,M>(fallback, mapper)` | `D: Producer<U>`, `M: Mapper<T,U>` | Call mapper once | Call producer once |
| `and_then<U,M>(mapper)` | `M: Mapper<T,Option<U>>` | Call once; return its Option | `None<U>` |
| `or_else<P>(fallback)` | `P: Producer<Option<T>>` | Preserve the option | Call producer once |
| `unwrap_or_else<P>(fallback)` | `P: Producer<T>` | Return `t` | Call producer once |
| `ok_or_else<E,P>(fallback)` | `P: Producer<E>` | `Ok(t)` | Call producer once; return `Err(error)` |
| `filter<P>(predicate)` | `P: Mapper<T,bool>` | Call once; keep original Some if true, else None | None, no call |
| `is_some_and<P>(predicate)` | `P: Mapper<T,bool>` | Return one predicate result | false, no call |
| `is_none_or<P>(predicate)` | `P: Mapper<T,bool>` | Return one predicate result | true, no call |

The free-function generic list begins with `T`, followed by any new output
type and the callback types in argument order. Given borrowed arguments
`fallback: &D` and `mapper: &M`,
`core::option::map_or_else<T,U,D,M>(value, fallback, mapper)` returns `U`.
Presence depends on the tag: `Some(false)` and `Some(0)` invoke a selected
callback just like any other Some.

## Result operations

Here `value` is `Result<T,E>`. Methods and free functions follow the same
argument rule; free-function generic lists begin with `T,E`.

| Operation | Callback bounds | `Ok(t)` | `Err(e)` |
| --- | --- | --- | --- |
| `map<U,M>(mapper)` | `M: Mapper<T,U>` | Call once; return `Ok(mapped)` | Preserve `e` |
| `map_err<F,M>(mapper)` | `M: Mapper<E,F>` | Preserve `t` | Call once; return `Err(mapped)` |
| `map_or<U,M>(fallback:U, mapper)` | `M: Mapper<T,U>` | Call once | Return the eager fallback |
| `map_or_else<U,D,M>(fallback, mapper)` | `D: Mapper<E,U>`, `M: Mapper<T,U>` | Call mapper once with `t` | Call fallback once with `e` |
| `and_then<U,M>(mapper)` | `M: Mapper<T,Result<U,E>>` | Call once; return its Result | Preserve `e` |
| `or_else<F,M>(fallback)` | `M: Mapper<E,Result<T,F>>` | Preserve `t` | Call once; return its Result |
| `unwrap_or_else<M>(fallback)` | `M: Mapper<E,T>` | Return `t` | Call once with `e` |
| `is_ok_and<P>(predicate)` | `P: Mapper<T,bool>` | Return one predicate result | false, no call |
| `is_err_and<P>(predicate)` | `P: Mapper<E,bool>` | false, no call | Return one predicate result |

Given `mapper: &M`, `core::result::and_then<T,E,U,M>(value, mapper)` returns
`Result<U,E>`. `Result::map_or_else` gives its fallback the error payload;
Option's fallback instead uses the argument-free Producer. `map` preserves
a callback-produced Option or Result as an ordinary nested payload, while
`and_then` returns that callback's wrapper directly.

The branch rules follow the official Rust
[Option](https://doc.rust-lang.org/core/option/enum.Option.html) and
[Result](https://doc.rust-lang.org/core/result/enum.Result.html) references.
The Lanius ownership and callback rules below are explicit; Rust's closure,
move and automatic-drop rules do not apply here.

## Ownership, effects and failure

Library selection adds no allocation, clone, destruction, host call or
panic. It makes zero or one callback invocation. A selected callback may
allocate, perform I/O, change its context or return an error. Callback failure
does not trigger a retry, a second callback, rollback or unwind recovery.
Work includes shallow value transport and the selected callback's own work;
there is no wall-time bound or callback quota beyond the zero/one rule.

Passing an Option or Result by value leaves its wrapper descriptor unchanged
in the caller. It does **not** isolate backing referenced by that payload
from a transformation callback. The application must choose one policy:

- Transfer the selected owner's sole cleanup authority into the callback,
  deactivating every older alias and recovering any returned owner explicitly.
- Keep cleanup authority outside the callback and treat its shallow input
  as a borrowed descriptor.

No unselected or discarded value is implicitly destroyed. This includes an
unused eager `map_or` fallback, a discarded Result error, and a payload
removed by `filter`. Borrowed callback objects and their context must stay
live during the call; backing borrowed by returned values must survive every
later use. Owner-bearing return values need one explicit cleanup policy.

`filter`, `is_some_and`, `is_none_or`, `is_ok_and` and `is_err_and` have a
stricter predicate contract. Their shallow payload is a **call-scoped,
read-only observation**. A predicate must not mutate or destroy the represented
resource, invalidate it, retain cleanup authority, or retain a borrowed
payload descriptor beyond the call. Independent scalar observations and
instrumentation are allowed. A rejected filter payload still requires the
caller's cleanup. These are manual lifetime rules, not enforced borrowing or
automatic destruction.

## Real program and current evidence

The [optional integer total program](stdlib-optional-sum.md) maps a present
field to parsing, maps parser errors to application status 2, and chains
checked addition only after parse success. Missing values skip parsing;
parser errors skip arithmetic. Complete validation still precedes output.

Tiny registered admission passes one native test in 4.96s
(`target/stdlib-work/lazy-outcomes-admission.log`), using a strict ELF/jump
check and a full trace containing only exec/exit. It covers the shared Mapper
identity, Producer, selected/skipped callbacks and generic delegation.
Accepted source prefixes are function `a6e9f1ed`, option `54629225`,
result `a0f37cd2`, and admission fixture `4be3bfd0`. A separate 1.60s Rust
build prepared seven selected test executables; that build is not runtime evidence.

The remaining four direct groups pass together in 13.20s
(`lazy-outcomes-direct.log`, tiny admission filtered). Thus all five direct
groups pass: three native-positive groups and two capability-rejection groups.
The branch fixture checks all nineteen APIs in free and method forms through
112 invocations; the type fixture adds compound values/errors, floats, views
and zero sizes. Fourteen exact negative bounds cover eight Option and six
Result calls, including callbacks a runtime variant would skip. The
[direct fixture guide](../tests/fixtures/stdlib_lazy_outcomes/README.md)
records exact sources, assertions and diagnostic sites.

Four selected migration regressions also pass against the current callback
identity. Each row is one native test, with logs under `target/stdlib-work/`:

| Existing family | Test time | Log |
| --- | ---: | --- |
| Iterator typed callbacks and owner contracts | 6.58s | `lazy-outcomes-migration-iterator.log` |
| Slice compound aliases and borrowed composition | 6.69s | `lazy-outcomes-migration-slice.log` |
| Map lookup/update effects | 5.58s | `lazy-outcomes-migration-maps.log` |
| Vec retain/dedup cleanup | 4.79s | `lazy-outcomes-migration-vec.log` |

The source migration inventory records 101 current Lanius files and 189
qualified references. Eight old references in six historical compiler-capture
files remain deliberately unchanged; 575 historical/prototype/reconstruction
patch hashes match their originals. Generated Rust/Python/shell fixture source
strings contain no live old Mapper path. These are static inventory checks,
not additional native tests or a whole-suite rerun.

The foundation call inventory passes one host-only test in 0.01s
(`lazy-outcomes-inventory-accepted.log`). It includes the new executing branch
fixture and corrects stale Base64 and slice fixture references. This source
bookkeeping does not add a native test or establish execution on its own.

Two selected existing Option/Result runtime regressions also pass together in
3.86s (`lazy-outcomes-existing-options.log`): imported aggregate method chains
and the Option/Result example program. These six selected old-family tests
are separate from the new lazy API groups.

The migrated optional-sum program passes all four existing oracle groups in
one 8.02s invocation (`lazy-outcomes-optional-sum.log`): model 33, CLI 17,
rejection 30 and I/O 18, totaling 98 current native cases. Its
[guide](stdlib-optional-sum.md#current-migration) records the source hash and
separate historical application evidence.

The independent composition model passes one native test in 6.63s
(`lazy-outcomes-model.log`): 16 cases, 1,536 actions and 1,044 API calls
(536 free / 508 method). It covers all nineteen APIs and 76 branch routes
across two shapes, seed `0x1a2f0261119`. Of those API calls, 616 invoke a
callback and 428 skip callbacks: exactly 616 callbacks, including 148 Producer calls,
60 callback-produced absences and 52 callback-produced errors. The complete
485,856-byte transcript is compared; 22 host corruption controls are a
separate oracle check. The
[model fixture guide](../tests/fixtures/stdlib_lazy_outcomes_model/README.md)
records the exact corpus and source hashes.

Both owner/effect tests pass together in 7.71s
(`lazy-outcomes-resources-retry.log`). The positive process observes six
original nested Vec/String owners, selected replacement and cleanup callbacks,
unused eager fallback cleanup, call-scoped predicate observations and skipped
allocating callbacks. It has five pure phases, fourteen exact allocations and
releases, and checks all twenty output bytes.

The second test runs a callback baseline and one reached allocation denial
followed by recovery in the same process. The selected `and_then` callback
cleans its partial allocation and returns the intact original owner; the caller
explicitly transfers that owner into a retry. Baseline allocation/release
counts are 4/4; denial at the fourth attempt followed by retry has five
successful allocations and five releases. Both publish all twenty replacement
bytes after original-input retirement. This tests a callback's allocation
failure and recovery policy; the library itself does not allocate or roll back.
The [resource guide](../tests/fixtures/stdlib_lazy_outcomes_resources/README.md)
records exact identities, live-owner checks and the finite denial scope.

The first resource command failed before execution: zero passed and two failed
in 4.49s (`lazy-outcomes-resources.log`). Both entry fixtures lacked
`module app::main` headers and rejected with `LNC0016`; only those headers
changed for the successful retry. This was fixture repair, not observed
library or compiler failure.

In total, the eight new library groups contain six native-positive tests and
two capability-rejection groups. The four current application groups/98 cases,
six selected existing regressions and static inventories remain separate;
overlapping historical receipts are not added to these totals.
The executed target is native Linux x86_64 CPU output from the GPU compiler.
No GPU-device execution, other-target support, formal proof, general generic
completeness or automatic ownership follows from this increment.

The whole library goal remains open. Borrowed collection lookup,
caller-backed buffering and the broader
[roadmap](library-roadmap.md) remain separate work.
