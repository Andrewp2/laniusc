# Borrowed segmentation ownership observations

Driver: `tests/stdlib_slice_segmentation_resources_execution.rs`.
Root owns compiler and native execution. Both selectors require a native
Linux x86_64 ELF and shared validation of every generated x86 jump.

## Scalar backing at two sizes

`scalars.lani` reserves one Vec<i32> for each of 4,096 and 65,536 selected
elements, plus three leading and four trailing guards. The selected View has
a nonzero absolute offset. The input repeats a 16-key pattern with leading,
adjacent and terminal separators and equal-key runs across pattern boundaries;
higher bits vary between blocks so complete source checks cover the full owner.

Five pure phases per size exercise failed logical admission and inert factory
creation, early stopping and cursor copies, complete Split traversal, complete
SplitInclusive traversal, complete ChunkBy traversal, and original owner reuse.
The first and last phases both retire most cursor input unread. Every yielded
span and value is checked against independent analytical pattern boundaries.
Strict callbacks check input order and exact total counts. Repeated exhaustion
must perform no additional callbacks.

Every original element and guard is then checked and emitted for complete host
comparison. The sole owner is explicitly destroyed only after cursor/result
use ends. There are no large stack arrays or per-segment owners.

Selector:

```text
slice_segmentation_preserves_live_scalar_backing_at_two_sizes_without_host_effects
```

## Real ownership-bearing elements

`handles.lani` holds 23 distinct Vec<u8> owners inside an outer Vec. Sixteen
handles form the selected View; the other seven are guards. Every inner Vec
owns eight identity-bearing payload bytes. Unary and adjacent predicates
receive the actual nested handles, read their complete payloads and metadata,
and preserve them. A scalar surrogate cannot satisfy these checks.

The producer applies all three segment families, early stopping, shared
predicate context through cursor copies, full exact partitions and fused
exhaustion. After those cursors retire, every byte and descriptor of every
inner owner is checked again and all 184 payload bytes are emitted. The caller
then destroys each actual inner owner exactly once and releases the outer
handle storage last. Borrowing never transfers cleanup authority.

Selector:

```text
slice_segmentation_borrows_real_nested_owner_handles_and_preserves_cleanup_authority
```

## Observation and acceptance

The full syscall ledger permits allocation only during source construction.
Marker-delimited pure phases prohibit all host work, including allocation,
release and callback effects. The ledger tracks every live address and extent,
rejects overlap, unknown or duplicate releases, and requires explicit cleanup
before each retirement marker. For nested owners it also requires every inner
release before the outer. Process exit is not cleanup evidence. No allocation
failure is fabricated for these allocation-free cursors, and no application
I/O tests are duplicated here.

The first root resource run completed in 6.86 seconds with one passing gate
and one failing gate; the receipt is
`target/stdlib-work/slice-segmentation-resources.log`. The scalar gate passed
both sizes, all ten pure phases, complete backing/guard output and exactly two
allocations and two explicit releases.

The nested producer exited successfully and completed its cleanup trace, but
its Rust ledger incorrectly expected 368 bytes for the outer reservation.
That expectation assumed a packed C-style Vec layout. The authoritative
`stdlib/core/mem.lani` size contract uses eight-byte native words for record
fields; `stdlib/alloc/vec.lani` declares three one-word fields. Thus each
Vec<u8> handle occupies 24 bytes, and 23 handles require exactly 552 bytes.
The driver now derives that extent as `23 * 3 * 8`, retaining every exact
address/extent, payload and cleanup assertion. Both producer sources remained
unchanged. Independent source review accepted the correction.

The narrow corrected nested gate then passed (1/1, one other test filtered) in
6.62 seconds after a separate 1.78-second Rust build. Its receipt is
`target/stdlib-work/slice-segmentation-resources-handles-revised.log`. It checked
all 16 selected handles, seven guards, 23 live payloads, five pure phases and
all 184 payload bytes. All 24 allocations had exact explicit releases, with
every inner owner retired before the outer storage. Both resource gates are
now accepted across these separate invocations; the first nested process exit
alone was not treated as a passing resource-test receipt.

Bounded host-only controls checked the analytical partitions independently:

| Selected elements | Split segments | Inclusive segments | Adjacent groups | Full unary / adjacent calls |
| ---: | ---: | ---: | ---: | ---: |
| 16 nested handles | 7 | 6 | 9 | 16 / 15 |
| 4,096 i32 values | 1,537 | 1,536 | 2,049 | 4,096 / 4,095 |
| 65,536 i32 values | 24,577 | 24,576 | 32,769 | 65,536 / 65,535 |

These controls and static syntax/format checks remain distinct from the native
receipts above. Accepted resource observations are ten pure phases and two
exact source allocations/releases for the scalar sizes; five pure phases and
24 exact allocations/releases for nested handles. The initial target is native
Linux x86_64 CPU output from the GPU compiler. Device execution, other targets,
formal verification and language-enforced lifetimes remain separate work.
