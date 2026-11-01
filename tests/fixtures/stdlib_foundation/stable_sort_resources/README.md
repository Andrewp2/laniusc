# Stable-sort resource, guard and scale fixtures

All three registered gates passed compiler/native acceptance through separate
commands. Their accepted runs comprise five successful native lifecycles. Root
performed all compiler/native commands; the author performed static review and
bounded host-only oracle controls.
These fixtures exercise the fixed [stable-sort contract](../../../../docs/library-stable-sort-plan.md).
Accepted execution is finite Linux x86_64 CPU output from the GPU
compiler. GPU-device execution, other targets, automatic ownership and formal
verification are not established by this suite.

## Nested owners and workspace authority

`owners.lani` sorts an interior View of twelve `Record<Bundle<Leaf>>` values,
with two complete outside guard records. Each of fourteen records owns two
Strings and two Vec<u64> buffers. The **57 input allocations** comprise 56
distinct nested buffers and one outer record backing. The fixture snapshots
every nested pointer and capacity and checks every payload byte, numeric word,
record ID and outside guard after each sort. Strings include embedded NUL and
multibyte UTF-8; wide payloads exercise the high bit and u64::MAX.

Four successive policies exercise ascending custom, descending custom,
all-Equal custom and natural ascending sorting. Before each call, the fixture
records the current position of every ID. Equal-key results must retain that
order. The first ascending result also has an independently checked literal ID
sequence. Exact permutation is checked separately from sortedness and
stability. The all-Equal policy requires the complete sequence to remain
unchanged. These record types implement neither Clone nor Destroy.

The input slots remain the sole authorities for nested cleanup. Scratch copies
and comparator arguments are shallow observations. Cleanup walks the final
input slots, destroys each nested owner once and releases the outer backing
last. Successful nontrivial sorts each allocate and retire one separate
workspace before returning. The normal owner lifecycle therefore has **61
successful mappings/releases**: 57 input allocations plus four workspaces.
A separate pure phase sorts seven actual zero-sized Unit values through both
APIs, with no physical workspace allocation and an observable custom callback.

The owner fault schedule injects ENOMEM into actual mmap ordinal **58**, the
first workspace reservation after all 57 input mappings. It requires
Storage(AllocationFailed), zero comparator calls, unchanged original ID order,
all original payloads and ownership metadata, then explicitly retries the same
input and completes all four policies. There is one additional failed
reservation, not an additional successful owner. It is one selected reached
failure, not an allocation-failure campaign.

## Admission and honest physical boundaries

`guards.lani` owns one **12288-byte mapping**, protecting its first and last
4096-byte pages. Six lengths (2, 3, 7, 8, 9 and 17) exercise four layouts:

- native packed +4 i32 array, with complete outside sentinels;
- packed +4 i32 range ending immediately before the upper protected page;
- packed +1 byte range with nonzero start, several unaligned byte bases, and
  its final selected byte immediately before the upper protected page;
- descending compound Node storage whose final selected element occupies the
  lowest accessible element span, followed physically by the protected page
  in its index direction.

All **24 guarded sorts** check complete identifiable stable permutations,
payloads and outside guards. The raw descriptors in these successful tests
claim only physically accessible initialized elements. The protected mapping
is separately released with its complete original extent.

One pure metadata phase rejects negative start/length and overflowing endpoint
metadata and rejects a nonzero-sized Vec byte-cap overflow. Valid zero/singleton
Views at extreme starts use null backing and must return without access,
callback or allocation, as required by the explicit fast-path contract. These
are no-access path observations, not permission to dereference null backing.

A separate mode injects ENOMEM at actual mmap ordinal **2**, immediately after
the protected setup mapping, for a two-i32 workspace request. Its input pointer
is deliberately in a protected page. This is a **no-input-access tripwire on
the returned reservation-error path**, not a successful valid-backing example
or a relaxation of the caller's physical-backing obligation. After observing
AllocationFailed and zero callbacks, it sorts a separate honestly backed
input. The real-owner ENOMEM schedule above independently establishes input
preservation and recovery with valid owned storage.

## Stable outputs at meaningful sizes

`scale.lani` runs **36 cases**: sizes 257, 4096 and 65536, six families and both
public APIs. The families are ascending, descending, eight-way duplicates,
organ pipe, sawtooth modulo 97 and an affine permutation with multiplier 40503
and seed 17. Each call starts with freshly populated original ID order, an
offset View and untouched outside records. Every record has ID-derived wide
payload fields, checked after sorting.

Two input/report Vec backings are reserved once and reused. Each sort acquires
and retires its own one workspace: **38 successful mappings/releases** in the
whole process. The native fixture reports every resulting ID, in bounded raw
output chunks. The Rust oracle independently uses the host's stable
`sort_by_key` over original IDs and compares the entire sequence. This detects
lost/duplicated records, wrong key order and reversed representatives within
an equal-key group; it does not merely compare checksums or sorted keys.

Custom callback counts must be positive and at most **n*ceil(log2(n))**.
Instrumented natural Ord.lt calls have their own ceiling of twice that value,
since Natural may invoke two primitive predicates per comparison. These are
finite work bounds from the public contract, not exact callback schedules,
adaptive-input promises or wall-clock performance claims.

Host-only controls checked all 36 generated family/size/API expectations and
rejected three deliberately corrupted representative sequences (equal-key
swap, duplicated ID and cross-key swap). The owner first-sort literal was
checked with the same host-only ordering control. These controls did not
execute Lanius.

## Trace boundaries and gates

The driver requires genuine x86_64 ELF and shared strict jump admission before
publication. Every native process has a 75-second lifecycle deadline. Commands
are run separately under root's compiler/native lock and remain below two
minutes.

Full syscall tracing distinguishes C/F sort intervals from P/p pure admission
and observation phases. Each nontrivial sort interval permits exactly one
workspace mmap attempt and, on success, its exact matching munmap. A failed
reservation must immediately return without another host effect. No other
host service is permitted inside sorting, and no service at all is permitted
inside a pure phase. Outside those intervals only explicit configuration,
bounded reports, the known setup/protection lifecycle and final cleanup are
allowed. The ledger matches every successful allocation address and requested
extent to one release; D is accepted only with no live mapping. This is a
finite fixture ledger, not an automatic resource checker or an ownership proof.

The three accepted registered gates use five native lifecycles: one owner
success, one owner ENOMEM recovery, one 24-case guard process, one
protected-input ENOMEM process and one 36-case scale process. The earlier
failed command is recorded separately below and is not counted among these
five accepted lifecycles.

## Execution receipts

- Owner gate: **1 passed in 7.50 seconds**, plus a 1.88-second Rust build,
  recorded in `target/stdlib-work/stable-sort-owners-first.log`. Actual summary:
  56 nested owners, one outer owner, four workspaces, 61 successful matching
  mappings/releases and five pure phases.
- Scale gate: **1 passed in 8.11 seconds**, plus a 0.20-second Rust build,
  recorded in `target/stdlib-work/stable-sort-scale-first.log`. All 36 complete
  ID sequences passed; 36 workspaces and 38 total mappings/releases matched.
  Observed maxima were 0.9349460601806641 custom callbacks per n*ceil(log2(n))
  and 1.6900749206542969 natural lt calls per that denominator. Those counters
  have separate ceilings and are not interchangeable performance metrics.
- Corrected allocation-failure/guard gate: **1 passed in 8.79 seconds**, plus
  a 0.19-second Rust build, with two other tests filtered, recorded in
  `target/stdlib-work/stable-sort-workspace-failures-corrected.log`. Both
  genuinely reached workspace ENOMEM schedules passed, including unchanged
  real-owner recovery and the protected-input no-access tripwire. All 24
  guarded cases passed across six lengths and four layouts; both protected
  pages and every exact allocation/release lifecycle were observed.
- Combined allocation-failure/guard gate first attempt: **failed in 9.38
  seconds** in `target/stdlib-work/stable-sort-workspace-failures-first.log`.
  The real-owner ENOMEM/recovery process completed before the next guard
  process trapped after its metadata phase and before any C/sort/workspace.
  The fixture incorrectly asserted that a native i32 array has negative
  stride. The existing accepted `settings_array_view/fields/main.lani`
  regression requires native i32 slice stride +4. The corrected fixture now
  requires exactly +4 and keeps all payload, sentinel and guarded checks.
  No library or compiler code changed. The first attempted guard source was
  `513c7258d13a66e78ae4e203eabb8e9f8e6979ff25836dfac48038a8c3b2a3f8`.
  Its successful owner subprocess and failed guard subprocess are historical
  first-attempt observations, separate from the corrected gate's three
  accepted lifecycles.

| Accepted source | SHA-256 |
| --- | --- |
| `owners.lani` | `7fe282e508be49c47d1c6fd085bed2f0d2e8171351fb2d926e7ca239842b3d9b` |
| Corrected `guards.lani` | `c6cb4291e272d528ef28dc94db9c55474a4dc8e0d524f2310f555d1f1e6c9295` |
| `scale.lani` | `3f6e178a902c2e8e9c937b29cb498df4d7ce1e6fe6cc922bf3e755848aeb4902` |
| Rust driver, executed before root formatting | `d2442df3d3689827fc97e640731f05e0965f542e1eec493a07c5c2903e673f99` |

```text
cargo test --test stdlib_stable_sort_resource_execution stable_sort_preserves_nested_owner_identity_stability_and_exact_workspace_lifecycle -- --exact
cargo test --test stdlib_stable_sort_resource_execution stable_sort_reached_workspace_failures_and_honest_guarded_ranges -- --exact
cargo test --test stdlib_stable_sort_resource_execution stable_sort_large_outputs_match_independent_stable_order_and_logarithmic_work_bound -- --exact
```
