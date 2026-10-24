# Fallible iterator collection

`core::iter::try_transfer_up_to` sends iterator items to a borrowed destination.
It reports the accepted prefix and returns any rejected item. This lets callers
collect into an existing owner, handle an allocation failure and resume without
silently losing the item that triggered the failure.

## Destination contract

```lani
pub trait TrySink<T, E> {
    pub fn try_accept(&self, item: T) -> core::option::Option<E>;
}
```

`None` means the destination accepted one item. `Some(error)` means it rejected
the item. A rejecting implementation must not retain the item or publish a
partial insertion. It may record instrumentation such as attempt counts.
The error type is part of the trait identity; it is not inferred from a desired
receiving annotation in conflict with an existing implementation.
For an optional error type, `Some(None)` is still a rejection; only the outer
`None` means acceptance.

The standard destinations use their existing checked insertion operations:

| Destination | Acceptance | Error |
| --- | --- | --- |
| `alloc::vec::Vec<T>` | Append with `try_push` | `alloc::vec::Error` |
| `alloc::deque::Deque<T>` | Append at the back with `try_push_back` | `alloc::deque::Error` |
| `core::vec::Vec<T,N>` | Append to the active prefix with `try_push` | `core::vec::Error`, including `Full` |

Each rejected insertion preserves the collection's contents, capacity and
existing views. Successful insertions follow that collection's ordinary
invalidation rules. The transfer itself can already have inserted earlier
items before a later rejection.
These append operations can return `CapacityOverflow` or `AllocationFailed`
for the alloc collections, and `Full` for the fixed vector. They do not produce
the collections' index or negative-capacity errors.

## Transfer contract

```lani
pub struct Transfer { accepted: u64, exhausted: bool }
pub struct TransferError<T, E> { accepted: u64, rejected: T, error: E }

pub fn try_transfer_up_to<I, S, T, E>(source: &I, sink: &S, limit: u64)
    -> core::result::Result<Transfer, TransferError<T, E>>
    where I: Iterator<T>, S: TrySink<T, E>;
```

Each step calls `source.next()`, then attempts one insertion if it returned
`Some(item)`. Source and destination item types must match exactly.

- A zero quota calls neither object and returns `accepted = 0`,
  `exhausted = false`.
- An observed `None` returns success with `exhausted = true`. It makes no sink
  call for that `None`.
- Reaching the quota returns success with `exhausted = false`, with no extra
  source probe. This includes a source containing exactly the quota's items.
- Rejection returns immediately with the destination's error, the original
  rejected item and the number accepted **during this call**. No later source
  or destination calls occur.
- Counts do not include entries already in the destination. The `u64::MAX`
  quota is valid; counting uses no overflowing `limit + 1` or narrowing cast.

At most `limit` calls reach the immediate source iterator. A filtered source's
single `next()` can scan many upstream items; this quota does not bound its
internal work. Put a `Take` upstream of filtering when the raw source also
needs a pull bound. Callbacks and sources own their effects and termination.

This function introduces no allocation, host calls, clones or destruction.
The source and destination can perform their documented operations. Runtime
errors represented inside an item such as `Result<T,E>` remain ordinary items;
the transfer does not interpret or suppress them.

## Recovery and ownership

Accepted items remain in the destination. They are not rolled back on error.
The source has consumed `TransferError.rejected`, while the destination has not
retained it. Before resuming the source, the caller can retry that item against
the same destination, store it elsewhere or release its owned resources. On a
second rejection, it still belongs to the caller. Retrying the source directly
would skip this item.
The rejected descriptor is a shallow value, not a deep snapshot: mutation of
shared nested state by a callback is not rolled back. Backing borrowed by the
returned item or error must outlive its later uses.

All values use Lanius's existing shallow copy policy. Copying a String handle
does not create an independent String owner; copying an error does not create
another cleanup authority. Keep one release authority for each resource. A
source can supply borrowed aliases or explicitly transfer its own authority,
but this API does not infer which policy applies. No successful or rejected
item invokes `Destroy` automatically. Destroying an outer Vec or deque releases
its storage only, so nested owners still require explicit cleanup.

The source, destination and any borrowed backing must remain valid throughout
the call. In particular, do not transfer from a cursor borrowing the destination
into that same destination: a successful insertion can invalidate its cursor or
reallocate storage. Use a separate snapshot when those inputs alias. Concurrent
or reentrant mutation is outside this contract. Lanius does not enforce these
lifetime constraints.
Backing borrowed by accepted items must also outlive their later uses in the
destination. A source that reuses an item's storage on its next call needs a
destination that copies that content into independent storage, or a different
source ownership policy.

Creating a fresh vector uses the same operation: construct `alloc::vec::new()`,
transfer into its borrowed owner, then handle the result while retaining that
owner. This keeps a partially filled collection available after a recoverable
failure and avoids hiding it in a failed factory result.

## Verification and targets

On **2026-10-24**, the following gates passed on native **x86_64 Linux**, using
the GPU compiler from `52872260` plus the four library-source changes in this
milestone. No compiler, shader, ABI, extractor or proof changes were required.
This evidence does not establish user-program GPU execution or other platforms.

| Gate | Accepted evidence | Time | Local log under `target/stdlib-work/iterator-transfer-admission/` |
| --- | --- | --- | --- |
| Typed contracts and state model | Two strict checked ELFs and two native executions; 236 independent scenarios containing 2,124 stateful actions | 7.46 s | `models-contracts.log` |
| Growth failures | One strict checked ELF; Vec and deque each complete a baseline and four separately denied/recovered growth allocations | 6.85 s | `faults-final.log` |
| Exact trait bounds | Three intended LNC0008 rejections at the source's transfer call: wrong source item, sink item and sink error | 4.03 s | `bounds.log` |
| [Word sorter](stdlib-sort-words.md) | One strict checked ELF, 51 native cases including all 12 observed input/vector allocation-failure positions | 7.24 s | `application.log` |
| Existing fixed-container composition | One strict checked ELF/native execution checks generic slice views, native stride and fixed vectors after their new protocol import | 7.19 s | `fixed-container-regression.log` |

The independent transfer model uses a finite host queue and rejection-index
selection. It compares every result field, complete destination prefix, source
position, source/sink call count and exact effect order after repeated transfers,
same-policy rejection retries, changed-policy acceptance and resumption. Quotas
include zero, exact length, larger values and `u64::MAX`. Existing destination
prefixes are retained. Its custom source/sink and transfer make no allocation.

Typed contracts exercise wide signed/unsigned fields, nested Option/Result
payloads, `Some(None)` errors, arrays and native slice strides, a generic helper
with symbolic item and fixed capacity, zero capacity, real deque wrapping and
zero-sized entries. A syscall ledger matches every active allocation's address
and requested length to one successful release. Exactly three allocations are
permitted: one externally retained String and the separate Vec/deque arrays.
The String remains usable after the collections are released and is destroyed
last, exactly once.

The allocation-failure fixture starts with an existing two-item prefix. Every
observed growth allocation is individually denied, then retried successfully.
Each refusal checks the complete rejected compound/String item, old prefix,
capacity and previously captured views. No subsequent source call precedes
recovery of the rejected item. The ledger checks all successful allocations are
released. The first fixture attempt correctly rejected a `u8` output argument
where the existing host helper requires `i32`; the fixture now casts that byte.
Its earlier source/log are retained locally as `faults-initial.lani` and
`faults.log`, outside the accepted evidence above.

The application validates complete bounded UTF-8 before collecting borrowed
words, sorts with Text ordering and preserves duplicates. Its native cases cover
exact/exceeded byte bounds, malformed text, a 4,096-word workload, every observed
allocation denial, read/write faults, real EPIPE and exact owner cleanup.
Rust provides independent models and test orchestration; all library and
application behavior is implemented in Lanius.

The existing `stdlib_gpu_perf` example also ran the frozen typed fixture with
one warm-up and one measured private-entry rebuild, validating native output
after both compilations. The measured compiler span was 1,927.702 ms for a
395,095-byte ELF (`typed-initial.log`). A single warmed sample is a smoke check,
not a performance comparison or a cold compilation measurement.

### Reproduction

Build focused test drivers from the repository root:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --locked --test stdlib_iterator_transfer_execution \
  --test stdlib_iterator_transfer_faults --test stdlib_iterator_transfer_bounds \
  --test stdlib_sort_words_execution --no-run
```

Each runtime gate was run separately, with a 100-second outer bound, up to
35 seconds waiting for the shared lock and a 60-second inner bound. A lock
timeout returns 75 without running the gate. For example:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_iterator_transfer_execution-90d764b7ffc61fab \
  --nocapture
```

The other accepted driver names were
`stdlib_iterator_transfer_faults-ac5c69efd331fb0f`,
`stdlib_iterator_transfer_bounds-255367c74db0d54d` and
`stdlib_sort_words_execution-731b2d8878d3ebfa`. Rebuilding may change these hashes;
use the executable paths printed by Cargo. Actual build logs were
`build-faults-bounds.log` (1.21 s) and `build-model-application.log` (1.32 s).
The latter also built `stdlib_slice_iterator_integration_execution`; only
`slice_cursors_compose_with_generic_views_native_stride_and_fixed_containers`
was selected with `--exact` for the existing composition recheck. The unrelated
chunk/window model was filtered out.
