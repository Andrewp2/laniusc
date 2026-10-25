# Opt-in scalar and structural value cloning

`core::clone_values` supplies explicit [clone and release protocols](stdlib-clone.md)
for resource-free scalars and Option, Result and Pair compositions. All five
focused groups pass on Linux x86_64 through the production GPU compiler in
19.37 seconds. They cover exact scalar bits with the empty Infallible error,
nested independent owners, active payloads, minimal bounds, typed rollback and
all 45 reached allocation failures. This is explicit manual ownership; it
does not add automatic moves or cleanup.

Import this module in composition entries and generic consumers that select
its implementations. It imports the existing core clone, Option, Result and
Pair modules; those modules do not import it. There is no change to the
`core::clone` contract or its import dependencies.

## Scalar protocols

The module provides exactly these fourteen concrete scalar implementations:

| Scalar types | Clone error | Clone and release |
| --- | --- | --- |
| `bool`, `char` | `Infallible` | Copy the scalar; release does nothing |
| `i8`, `i16`, `i32`, `i64`, `isize` | `Infallible` | Copy the scalar; release does nothing |
| `u8`, `u16`, `u32`, `u64`, `usize` | `Infallible` | Copy the scalar; release does nothing |
| `f32`, `f64` | `Infallible` | Copy the scalar bits; release does nothing |

```lanius
pub enum Infallible {}

impl TryClone<i32,Infallible> for i32
impl Destroy<i32> for i32
// Corresponding concrete implementations exist for the other listed types.
```

Every scalar clone returns `Ok(source)`. It performs no arithmetic,
normalization, text conversion or allocation. Floating signed zero and NaN
payload bits survive the tested identity transport unchanged. The native gate
checks twelve bit patterns at each float width, including signed zeros,
subnormals, infinities and quiet/signaling NaN payloads. The source performs no
floating operation that would alter them.

Scalars own no nested memory resource, so Destroy has nothing to release.
Copying one creates no second cleanup authority for an allocation. This is
why a no-op Destroy is valid here; it is not permission to use the same release
policy for owner descriptors. The clone error is one explicit empty enum with
no constructible variant. The implementation never substitutes an inhabitable
sentinel or invents an error value.

There are no pointer, reference, slice/view, `str` or arbitrary-record
implementations, and no scalar implementation for an arbitrary E. A scalar's
selected TryClone error is exactly Infallible. Resources and aliasing handles
require their own ownership contract.

## Helper signatures and bounds

```lanius
try_clone_option<T,E>(source: core::option::Option<T>)
    -> Result<Option<T>,E>
    where T: TryClone<T,E>

try_clone_result<T,F,TE,FE>(source: core::result::Result<T,F>)
    -> Result<Result<T,F>,ResultError<TE,FE>>
    where T: TryClone<T,TE>, F: TryClone<F,FE>

try_clone_pair<A,B,AE,BE>(source: core::pair::Pair<A,B>)
    -> Result<Pair<A,B>,PairError<AE,BE>>
    where A: TryClone<A,AE>, A: Destroy<A>, B: TryClone<B,BE>
```

The functions live in `core::clone_values`. Matching TryClone implementations
exist for each wrapper with the same bounds and error types. Explicit generic
arguments or a complete expected Result select the leaf errors. Receiver types
alone do not choose among multiple leaf implementations; a contradictory error
annotation must reject.

Option and Result clone only one active leaf and hold no completed destination
prefix. They therefore need no Destroy bound to clone. Pair needs Destroy for
its first field because it can have a completed first clone when the second
fails. The second field's TryClone releases its own partial construction on
failure, so Pair cloning does not additionally require `B: Destroy<B>`.

All stated static bounds still apply when a runtime variant is inactive. For
example, cloning `None<T>` requires the selected T TryClone implementation,
and cloning `Ok<T,F>` requires the selected F implementation too. No inactive
leaf clone or release function is invoked.

## Active variants and typed errors

```lanius
pub enum ResultError<TE,FE> { Value(TE), Error(FE) }
pub enum PairError<AE,BE> { First(AE), Second(BE) }
```

| Source and outcome | Returned clone result |
| --- | --- |
| `None` | `Ok(None)`, without a leaf call |
| `Some(value)`, leaf succeeds | `Ok(Some(independent_value))` |
| `Some(value)`, leaf fails with E | `Err(E)`, unchanged |
| `Ok(value)`, T clone succeeds | `Ok(Ok(independent_value))` |
| `Err(error_payload)`, F clone succeeds | `Ok(Err(independent_error_payload))` |
| T clone fails with TE | `Err(ResultError::Value(TE))` |
| F clone fails with FE | `Err(ResultError::Error(FE))` |
| Pair first clone fails with AE | `Err(PairError::First(AE))`; second is not called |
| Pair second clone fails with BE | Destroy the fresh first clone, then return `Err(PairError::Second(BE))` |

The outer Result reports whether cloning succeeded. An original Result's Err
payload is ordinary source data to clone; it does not itself mean the clone
operation failed. Success preserves that original variant and representative
content.

Pair accesses source fields with the existing `core::pair::first` and `second`
functions and constructs success through `core::pair::new`. It clones first
before second. On second failure it extracts BE before releasing the fresh
first owner. It never destroys the source first field or treats that source
descriptor as a fresh owner.

Returned E, TE, FE, AE or BE remains a separate owner under its own contract.
It may own memory and is passed unchanged inside the stated error wrapper.
The caller inspects and releases it explicitly. It cannot borrow a partial
destination that the failing leaf or Pair rollback releases. If it borrows
source storage, that borrowing needs the leaf's explicit lifetime contract;
it does not automatically survive source destruction. Independently owned
errors must remain valid through destination rollback and later source cleanup.

## Source and release ownership

Clone helper arguments are by-value shallow descriptors used as borrowed
sources. Source payloads and any storage they borrow must stay live and
read-only throughout the call, including through aliases. Each successful
leaf must yield a separate owner with the same logical content. Success or
recoverable failure leaves the original source unchanged. An Option or Pair
may contain borrowed repeated leaf handles; cloning each active logical leaf
must still produce its own independent result.

The module provides these separate release implementations:

```lanius
impl<T> Destroy<Option<T>> for Option<T> where T: Destroy<T>
impl<T,F> Destroy<Result<T,F>> for Result<T,F>
    where T: Destroy<T>, F: Destroy<F>
impl<A,B> Destroy<Pair<A,B>> for Pair<A,B>
    where A: Destroy<A>, B: Destroy<B>
```

Option releases only Some's payload; None invokes no leaf. Result releases
only its active Ok or Err payload. Pair releases both owned fields. These
operations need no TryClone bound. Each active payload must be a valid memory
owner for its Destroy contract. Repeated borrowed descriptors are not multiple
owners and must not be recursively released twice.

Destroy logically consumes its by-value descriptor. The language does not
reset the caller's other aliases, change an Option to None, clear a Result,
or replace Pair fields. Stop using the consumed value and old borrowed views.
Repeating Destroy on a stale resource-owning copy is invalid. There is no
implicit move, automatic Drop, compiler-enforced uniqueness or cleanup on a
trap. Leaf Destroy must finish without allocation, panic or reportable failure;
resources with fallible close operations need their own protocols.

## Composition and cost

These implementations compose with existing independently owned leaves and
the opt-in container modules. For example, `Vec<i32>` can select
`alloc::clone::Error<Infallible>` when both `alloc::clone_vec` and
`core::clone_values` are imported in the relevant generic consumers. A wrapper
adds only the error layer specified above: Option forwards E, Result records
which payload failed, and Pair records which field failed.

The wrappers allocate no backing of their own. Scalar copy/release and None
are constant work with no allocation. Some and Result add constant dispatch
work to the one active leaf operation. Pair adds constant work to its two leaf
clones, plus first-field release when the second fails. Nested work, memory
limits and termination follow the selected leaves; there is no new aggregate
quota, deadline or recursion limit.

## Execution evidence

[The independent driver](../tests/stdlib_clone_values_execution.rs) uses the
production module and
[durable fixtures](../tests/fixtures/stdlib_foundation/clone_values/). All five
groups pass in **19.37 seconds**, recorded in
`target/stdlib-work/clone-values-native-current.log`. The driver performs eight
entry compilations: four positive programs with the unchanged strict native
ELF/transfer checker and four rejected calls. The four programs and 45 fault
injections produce 49 native process runs.

| Group | Accepted coverage |
| --- | --- |
| Scalar values | All fourteen TryClone/Destroy selections through an imported generic consumer; signed/unsigned width extremes and high bits, false/true, NUL and Unicode characters, and twelve exact IEEE bit patterns per float width. No native mapping is allocated. |
| Nested owners | Clone `Option<Result<Pair<String,Vec<i32>>,String>>` twice through a helper and imported trait dispatch. Distinct String/Vec backings survive independent mutation, source destruction and destruction of the other clone. Updated descriptors are transferred and rebuilt before recursive release. |
| Active payloads and bounds | Poisoned inactive Option/Result clone and destroy callbacks are never reached. Clone-only leaves work without an unnecessary Destroy bound; Destroy-only leaves release all three wrapper shapes without TryClone or comparison bounds. |
| Typed errors and allocation failures | Eighteen callback scenarios cover Option, both original Result arms and all first/second Pair success/failure stages. Fourteen independently owned errors preserve their distinct types, binary messages, high u64 bits and inline arrays after source and destination cleanup. Pair's right leaf deliberately has no Destroy; a failed second clone releases the fresh first exactly once. All 45 reached allocation requests are denied individually, with one ENOMEM, the exact reached prefix and balanced address/request-length releases. Error owners are released only after all source, fresh and partial owners are gone. |
| Source rejection | Missing module opt-in, a contradictory scalar error, missing first-field Destroy for Pair, and missing leaf TryClone even for None all report LNC0008 at their actual caller lines. |

The first scalar gate failed with LNC0047 detail 6 in 4.00 seconds
(`target/stdlib-work/clone-values-scalars.log`). Paired reductions identified a
general empty-enum layout gap. The
[empty-enum compiler repair](compiler-empty-enum-layout.md) aligns the checked
native-width producer, program-evidence materializer and imported enum
projection. Complete empty enums retain the existing one-word discriminant
layout; unavailable definitions still fail closed. This does not invent a
constructible variant or change the public `Infallible {}` error. The library
source and assertions were unchanged for the passing gate.

These receipts establish the tested Linux x86_64 native CPU profile produced
by the GPU compiler. Other native targets and user GPU execution are not
validated here. The empty-enum repair does not revalidate unrelated generic
compiler failures or supply compiler-enforced ownership.
