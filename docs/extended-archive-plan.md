# Bounded archive namespace planning

`ext::archive_plan` is a pure allocation-backed namespace planner for the
[extraction policy](library-archive-extraction-plan.md#one-path-policy-for-both-formats).
It parses no TAR/ZIP bytes and performs no filesystem operations. The actual
module compiled and passed its focused native x86_64 Linux contracts, 76-plan
independent model and four allocation-baseline/failure processes. These are
planner receipts, separate from archive adapters and filesystem extraction.

## Frozen public contract

```lanius
enum Kind { File, Directory }
enum ErrorKind {
    Bounds, Limits, Path, Component, Depth, Entries, Nodes, Paths, Work,
    Duplicate, Conflict, Allocation, InvalidState
}
struct Error { kind: ErrorKind, ordinal: i32, offset: i32 }
struct Limits {
    max_entries: i32, max_nodes: i32, max_path_bytes: i32,
    max_component_bytes: i32, max_depth: i32,
    max_stored_path_bytes: i32, max_work: u64
}
struct Node {
    parent: i32, kind: Kind, explicit: bool, ordinal: i32,
    path_start: i32, path_length: i32,
    component_start: i32, component_length: i32, depth: i32
}
default_limits() -> Limits
reservation_bytes(limits: Limits) -> Result<u64, Error>
new(limits: Limits) -> Result<Plan, Error>
Plan.borrow() -> &Plan
Plan.add(path: View<u8>, kind: Kind, ordinal: i32) -> Result<i32, Error>
Plan.seal() -> Result<i32, Error>
Plan.node(index: i32) -> Option<Node>
Plan.path(index: i32) / Plan.component(index: i32) -> Option<View<u8>>
Plan.entry(index: i32) -> Option<i32>
Plan.node_count() / Plan.entry_count() -> i32
Plan.work_used() / Plan.reserved_bytes() -> u64
Plan.is_sealed() -> bool
Plan.destroy()
```

Defaults are 4,096 explicit entries, 8,192 total nodes, 4,095 canonical path
bytes, 255 component bytes, depth 64, 16 MiB stored prefix bytes and 134,217,728
work units. Node count includes files and both explicit/implied directories.
Every node stores its full canonical prefix path; the stored-byte cap counts
each prefix separately. It is independent of the per-path and node caps.

Negative signed limits, component limits above 255 or capacities whose vector
allocation byte size exceeds the signed vector bound return Limits before
allocation. Other nonnegative caps, including zero, remain independent.
`reservation_bytes` computes exactly
`max_nodes * size_of<Node>() + max_stored_path_bytes + max_entries * size_of<i32>()`.
It does not allocate. `new` reserves exactly these three capacities, releasing
partial owners on failure. Allocation errors have ordinal/offset -1.
`reserved_bytes` reports the actual current sum using those same widths.
No add/seal operation grows capacity or allocates. These requested source bytes
exclude caller input, adapter/member tables, host reports and allocator/kernel
overheads; the composing owner must budget those independently.

## Paths and namespace

Input is a length-delimited raw-byte View with live physical backing. The only
canonicalization removes one terminal slash from a Directory. The canonical
path must be nonempty and relative. Reject leading slash, NUL, backslash,
second-byte colon, empty components, `.` and `..`. A File ending in slash fails;
`d//` fails after removing its one directory slash. There is no UTF-8 conversion,
normalization, case-folding, percent-decoding or path resolution. For example,
`d` and directory `d/` identify one name; `A` and `a` remain distinct.

Path-byte and depth limits apply to the canonical path; validation work includes
the original raw spelling. Error offsets are relative to the input View, not
its backing start. Bounds/no-byte errors use offset -1. Path covers unsafe
spelling and complete path length; Component covers empty/dot components and
component length; Paths is the stored-prefix byte cap. Capacity errors identify
the component that first exceeds the cap. Ordinal must equal entry_count before
each successful add; mismatches return InvalidState.

Root-level nodes have parent -1 and depth 1. Implied directories have
explicit=false and ordinal -1. Adding `a/b` first creates implied `a`, then the
explicit file `a/b`. One later Directory `a/` upgrades that same node ID; it does
not add another node or another stored path. `entry(i)` supplies the node ID for
explicit archive ordinal i, preserving entry order independently of node order.
Path/component offsets index the plan's owned path bytes, including the full
prefix backing for each node.

Repeated explicit same-kind destinations return Duplicate. Different kinds at
the same destination and files used as ancestors return Conflict, regardless of
input order. Complete path validation, namespace resolution and node/path/work
preflight finish before any node, path byte or explicit-order entry changes.
Failure can consume charged work but preserves that namespace and backing.

## Work and terminal behavior

The work meter charges conservatively before the corresponding scan or copy:

- `3 * raw_input_length + 1` for complete character/component validation.
- One canonical path byte per boundary-scan pass.
- One per node examined in namespace lookup and per compared component-byte pair.
- One per copied prefix byte, new node, explicit-order append and implied-node
  metadata update; new-node boundary scans are charged too.
- One on first seal. Repeated successful seal is inert.

Insufficient work does not partially debit a reservation. Add preflight must
reserve all insertion work before publishing its first node. Budgets bound
planning work, not wall time or kernel allocation duration. Lookup is a bounded
linear node scan per existing component; this first planner has no hash table.
Read-only accessors are constant-time metadata/view operations outside builder
work accounting; caller traversal is the caller's work.

The first add/seal failure poisons the owner. Later add/seal calls repeat the
same Error without work or mutation. Only a successful seal certifies the full
namespace. Add after seal returns InvalidState and poisons that certification;
successful seal itself is idempotent. Read access remains available on a failed
live plan for diagnostics. Destroy releases all three vectors, invalidates
borrowed views and certification, and can be repeated. Access after destroy
returns None; add/seal cannot reuse a destroyed owner.

Keep one active manual Plan owner. Copies alias ownership and cannot be
destroyed independently. Views are read-only by contract and remain stable
through successful adds because backing never grows. A copied Node descriptor
can become stale when an implied directory is upgraded; query it again for the
current explicit/ordinal metadata. Destroy ends every path/component borrow.

## Focused verification status

[`tests/extended_archive_plan_execution.rs`](../tests/extended_archive_plan_execution.rs)
and the [fixture guide](../tests/fixtures/extended/archive_plan/README.md) define
two focused gates:

- `namespace_model_paths_limits_and_sticky_failures_execute` compiles the
  direct Lanius contracts and a model consumer, comparing 76 authored namespaces
  with an independent full-prefix BTreeMap oracle. It checks raw names, every
  public node/path/component/order field, limits, transactional rejection,
  poison, exact work boundaries and source ownership.
- `reserved_storage_allocation_failures_release_partial_plans` checks the three
  fixed reservations, no growth during add/seal, actual requested bytes and all
  three reached source allocation failures with instruction/request-prefix
  binding and balanced release.

Both filters now have native x86_64 Linux acceptance, collected across separate
invocations. Receipt paths below are under `target/stdlib-work/`:

| Receipt | Actual result and timing scope |
| --- | --- |
| `archive-plan-and-zip-drivers-build.log` | Shared two-driver build, exit 0, 1.45 s; not a planner-only build time |
| `archive-plan-first.log` | Mixed invocation: allocation filter passed four native processes, three reached ENOMEM; namespace filter failed at model compilation after direct contracts executed. Its 11.29 s covers the whole mixed invocation, not allocation alone |
| `archive-plan-model-import-retry.log` | Namespace filter passed in 10.10 s, including direct contracts and all 76 model namespaces in the model process |

The initial model admission error was fixture `LNC0007` at `model.lani:25:45`:
its explicit `core::result::Result` type lacked `import core::result;`. Adding
that defining-module import fixed the fixture. Production planner and Rust
driver stayed unchanged; the already accepted allocation filter was not rerun.
The 76 model namespaces are fixture cases, not 76 native process invocations.

The planner source SHA-256 is
`6eaeedc3d55da398812459b10838952b46075d645cde952b5ccf8752538d3c3e`;
the unchanged Rust driver is
`60645802895adf8c1756f400e8e18b8c23ea4d0bbb7d49c8f80d0f9f267c5bda`.
The [fixture receipt manifest](../tests/fixtures/extended/archive_plan/README.md#accepted-receipts-and-hashes)
records all three Lanius fixture and retained ELF hashes. HEAD was
`86e853b877523cd3b9b68a1e3cd183a612526a47`, with uncommitted extraction work;
the commit alone does not identify a clean build-input snapshot.

The compiler produced native x86_64 ELFs; these are not GPU-kernel executions.
No TAR/ZIP adapter, host materializer, additional target or complete extraction
workflow is accepted by these finite pure-planner gates. There is no throughput
or universal path-sandbox claim.
