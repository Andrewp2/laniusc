# Lazy Option and Result composition

This increment fills the missing callback-based value operations in the main
library. Option and Result currently provide eager selection and shape
conversion. `optional_sum` prepares checked arithmetic even after parsing has
failed because it has no lazy Result chain. The complete library goal remains
open; borrowed collection lookup and caller-backed buffering are separately
identified gaps.

## Shared callback boundary

Move the existing `Mapper<T,U>` trait, with `apply(&self,value:T)->U`, from
`core::iter` into an import-free `core::function` module. Add
`Producer<T>` with `produce(&self)->T` for genuinely argument-free callbacks.
Option and Result can depend on that leaf without importing the iterator
module, which already depends on them. Keep iteration-specific fold, sink and
retirement contracts in `core::iter`.

Migrate current source, examples and executable fixtures to the one canonical
Mapper declaration. No compatibility alias or second identical trait is
justified by an identified human dependency. Preserve exact historical compiler
captures; document their old source context rather than silently rewriting
evidence. Inventory generated fixture sources as well as `.lani` consumers.

## Public family

Provide each operation as a free function and a method delegating to it.
Arguments below follow the receiver/value; every callback is passed by `&`.
Generic free-function ordering starts with T (and E for Result), followed by
any new output type, then callbacks in argument order.

| Receiver | Operation and callback contracts | Behavior |
| --- | --- | --- |
| Option<T> | map<U,M>(mapper), M:Mapper<T,U> | Some maps once; None stays absent. |
| Option<T> | map_or<U,M>(fallback:U, mapper), M:Mapper<T,U> | Some maps once; None selects the already evaluated fallback. |
| Option<T> | map_or_else<U,D,M>(fallback, mapper), D:Producer<U>, M:Mapper<T,U> | Exactly one selected callback produces U. |
| Option<T> | and_then<U,M>(mapper), M:Mapper<T,Option<U>> | Some calls once and returns its Option; None skips it. |
| Option<T> | or_else<P>(fallback), P:Producer<Option<T>> | Some is preserved; None invokes the fallback once. |
| Option<T> | unwrap_or_else<P>(fallback), P:Producer<T> | Some yields its payload; None invokes once. |
| Option<T> | ok_or_else<E,P>(fallback), P:Producer<E> | Some becomes Ok; None obtains the error once. |
| Option<T> | filter<P>(predicate), P:Mapper<T,bool> | Some is retained when its one predicate call is true; otherwise None. |
| Option<T> | is_some_and<P>(predicate), P:Mapper<T,bool> | None is false; Some returns its one predicate result. |
| Option<T> | is_none_or<P>(predicate), P:Mapper<T,bool> | None is true; Some returns its one predicate result. |
| Result<T,E> | map<U,M>(mapper), M:Mapper<T,U> | Ok maps once; Err preserves E. |
| Result<T,E> | map_err<F,M>(mapper), M:Mapper<E,F> | Err maps once; Ok preserves T. |
| Result<T,E> | map_or<U,M>(fallback:U, mapper), M:Mapper<T,U> | Ok maps once; Err selects the eager fallback. |
| Result<T,E> | map_or_else<U,D,M>(fallback, mapper), D:Mapper<E,U>, M:Mapper<T,U> | Exactly one selected callback receives the matching payload. |
| Result<T,E> | and_then<U,M>(mapper), M:Mapper<T,Result<U,E>> | Ok calls once; Err preserves its error without calling. |
| Result<T,E> | or_else<F,M>(fallback), M:Mapper<E,Result<T,F>> | Err calls once; Ok preserves its value without calling. |
| Result<T,E> | unwrap_or_else<M>(fallback), M:Mapper<E,T> | Ok yields its value; Err calls once with its error. |
| Result<T,E> | is_ok_and<P>(predicate), P:Mapper<T,bool> | Err is false; Ok returns its one predicate result. |
| Result<T,E> | is_err_and<P>(predicate), P:Mapper<E,bool> | Ok is false; Err returns its one predicate result. |

These nineteen operations preserve the existing type identities and eager
operations. All static callback bounds apply even when the runtime variant
would skip the callback. Callback objects and ordinary arguments are evaluated
before entry; laziness controls invocation, not their construction.

## Ownership, effects and failure

The library adds no allocation, clone, destruction, host call or panic. A
selected callback may have its own effects or return an Option/Result error.
There is no implicit retry, callback duplication, rollback or unwinding
guarantee. Values and wrapper descriptors are shallow; skipped or discarded
payloads are never silently destroyed.

Transformation callbacks follow Mapper's ordinary shallow-value contract.
Applications may explicitly transfer a selected owner's sole cleanup authority
into a callback, deactivating all older aliases; otherwise they retain that
authority externally and treat callback values as borrowed descriptors. They
must account for discarded owners and eager fallback owners. The library
cannot infer that policy and does not duplicate authority.

Filter and the four Boolean query operations use temporary read-only payload
observations. Their predicates must not mutate or destroy the represented
resource, retain cleanup authority, or invalidate the payload they inspect.
Borrowed payload descriptors must not escape the predicate call; independent
copied scalar observations and instrumentation are allowed. A rejected filter payload remains the
caller's cleanup responsibility. Callback objects and backing referenced by
returned values must remain live for their respective uses. These contracts
are manual, without borrow checking or automatic drop.

The branch-selection semantics follow the official Rust
[Option](https://doc.rust-lang.org/core/option/enum.Option.html) and
[Result](https://doc.rust-lang.org/core/result/enum.Result.html) documentation.
Lanius explicitly uses borrowed callback values at the source level and shallow
values rather than adopting Rust's closure/move/drop rules. These are generic
statically dispatched callbacks, not dynamic trait-object or closure support.

## Application and acceptance

Migrate `optional_sum` to a lazy parse/classify/checked-add path. Preserve its
input grammar, exact output, complete validation before publication, bounds,
exit statuses and owner cleanup. Mapping an error replaces transpose-only
classification scaffolding; failed parsing must skip the arithmetic callback.
Use the current independent application oracle and its model/CLI/rejection/I/O
groups, rather than rewriting expected results to match new code.

Required evidence:

- Tiny native admission of Mapper's new identity, Producer, mapping, lazy
  fallback and generic method delegation before larger gates.
- Direct branch tables for all nineteen APIs in free and method forms, exact
  zero/one callback counts and selected operand values; generic forwarding,
  full-width values, compound payloads/errors, floats, views and zero sizes.
- Exact-bound negative controls, including unselected branches, with intended
  source-local diagnostics rather than accepting arbitrary compile failure.
- Independent finite model of composed operations and callback effects, with
  deterministic witnesses for short circuits and callback-produced failures.
- Actual nested owners and selected allocation/cleanup callbacks, full-width
  backing identity, explicit one-time cleanup, nonselected failing callbacks,
  and allocation-free pure operations. Do not claim library OOM behavior for
  an operation that never allocates.
- A focused migration regression from each affected public family (iterators,
  slice segmentation, map updates and vector editing), plus relevant existing
  Option/Result behavior. Static inventory checks preserve historical captures
  and detect remaining live references to the old Mapper path.
- Updated contract guides and generated reference; inventory is separate from
  executable evidence. Acceptance initially targets native Linux x86_64 output
  from the GPU compiler, without a GPU-device execution claim.

Root serializes compiler/native/Cargo commands under the library lock and caps
each outer command at 100 seconds. Subagents may run bounded host-only checks.
No compiler/IR/ABI/extractor/proof, protected std::vec/core::mem/test harness,
root README or human policy edits. Missing compiler support gets a minimal
reproduction and explicit dependency record.
