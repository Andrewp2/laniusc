# Iterator comparison owners, guards and finite work

All three registered resource gates passed compiler/native acceptance through
separate commands. The parent agent ran every compiler, Cargo and native
command. The author ran only bounded CPU reference controls
and static grammar, range and raw I/O audits. These three focused gates check
the [iterator comparison contract](../../../../docs/library-iterator-comparison-plan.md)
alongside the separate direct and independent state-model suites.

The first owner gate stopped before native execution in 4.42 seconds with
LNC0006 at `owners.lani:102`: the integer-literal repeat `[0;24]` did not infer
the `[ptr;24]` field type inside Context construction. The fixture now supplies
an explicit ptr local as its repeated element. All payloads, actual owners and
assertions are preserved, with no compiler/production change. The initial diagnostic is in
`target/stdlib-work/iterator-comparison-owners-first.log`; its source was
captured separately under target. This authoring stop establishes no runtime
result.

The guarded gate passed its first attempt: one test with two filtered in
6.76 seconds, recorded in
`target/stdlib-work/iterator-comparison-guards-first.log`. The corrected owner
gate passed one test with two filtered in 7.28 seconds, recorded in
`target/stdlib-work/iterator-comparison-owners-typed-retry.log`: all ten pure
phases, twelve compound records with 24 nested backings, and all 28 exact
mapping/release matches passed. The scale gate passed its first attempt: one
test with two filtered in 7.33 seconds, recorded in
`target/stdlib-work/iterator-comparison-scale-first.log`. All 33 cases at
lengths 257/4096/65536 matched exact results and effects, with callbacks<=n,
pulls<=n+1 per source, and two exact mapping/release matches. Executed source
identities are recorded below; no code changed after those accepted runs.

## Nested borrowed values and external cleanup authority

`owners.lani` creates twelve distinct `Record<Payload>` values. Each has an
actual owned String containing NUL/UTF-8, an actual Vec with three full-width
integers, and nested high-bit/NaN/signed-zero/Option payloads. Pointer/capacity
and content checks identify all 24 nested backings. Two source Vec backings
and two pre-reserved external keeper Vecs make 28 successful setup allocations.
The compound source storage has its actual negative native stride.

Ten P/p phases cover all eight public APIs:

| Phase | Operation and decision | Pulls, callbacks and remaining ownership |
| --- | --- | --- |
| 1 | Natural equality, six equal keys | Seven pulls each, six PartialEq calls |
| 2 | Heterogeneous eq_by with compound Lookup | Seven pulls each, six callbacks |
| 3 | Natural total comparison, shorter right prefix | Six pulls each, five equal pair comparisons; one unmatched left value |
| 4 | Heterogeneous total comparison, first mismatch at pair 3 | Three pulls/callbacks each, suffix untouched |
| 5 | Natural partial comparison, equal | Seven pulls each, six PartialOrd calls |
| 6 | Heterogeneous partial callback returns Unordered at pair 2 | Two pulls/callbacks each, suffix untouched |
| 7 | Natural sortedness with duplicate keys | Seven pulls, five partial_le calls |
| 8 | Owning sources, total decision at pair 2 | Both consumed prefixes are kept externally; four items remain per source |
| 9 | Custom sortedness resumes the owning left source | Four more items kept, three adjacency calls and one EOF observation |
| 10 | Exhausted owning left versus remaining right | One more pull per side; the unmatched right item is also kept |

Borrowed phases keep both actual source owners intact. Callback operands and
intermediate items are shallow observations, with no Clone/Destroy or owner
field mutation. Custom callbacks use distinct concrete receiver types for their
different roles and inspect the real compound argument data.

An actual IntoIter transfers cleanup authority for each Some. The comparison
helpers return only results and cannot recover their discarded items. For the
owning phases, a test-only Recorder first puts each yielded item in an already
reserved external keeper, then returns a shallow observation of it. That keeper
owns the nested cleanup obligation before the consumer sees the value. This
also keeps sortedness's previous operand valid for the next adjacency call.
No push can grow the keeper in a pure phase.

After the decisive and unmatched-item cases, the left keeper has all six left
items, the right keeper has its first three, and the remaining three right items
are recovered separately with take_remaining. Their IDs must be exactly the
twelve originals, with no duplicate cleanup authority. The fixture explicitly
releases their String/Vec resources and all four outer backings. The initial
left source backing remains live until every nested owner has retired and is
released last. No automatic cleanup by the comparison helpers is assumed.

Each phase emits nine i32 effect fields. The Rust driver checks literal goldens
for result, actual cursor pulls and each callback family. Natural<T>'s two lt
probes for an equal total comparison are counted separately from comparator
invocations. Neither metric is a wall-clock or generic callback-work bound.

## Honest guarded reads, zero-size values and exact early exits

`guards.lani` allocates two native 4096-byte pages and protects the second with
PROT_NONE. A raw slice honestly covers one leading canary and one or two live
payload bytes ending immediately before that guard. The opposite byte source
is a native descending-stride array with a nonzero View start; the guard source
uses its actual packed +1 stride. Both backings remain unchanged.

Ten no-host phases cover immediate unequal equality/total/partial decisions,
the first descending pair, strict rejection of equal adjacent values, a shorter
empty source against a nonempty source under a reverse element comparator,
and three zero-sized Unit cases. The zero-sized raw/native values have actual
stride 0 and need no byte backing. A valid empty null view is never read.
The final custom equality case checks Pair operands over the guarded/native
byte sources as well.

Each cursor has a literal pull ceiling for its expected decision. This rejects
an extra next call even when it could have safely returned EOF. Physical guard
pages check item-read extents; counters check delegation effects. The fixture
does not advertise an inaccessible tail as though it were valid storage.
It does not claim logical views establish arbitrary backing/lifetime safety or
promise rollback after physical traps. Five i32 result/effect fields per phase
are compared against independent host goldens.

## Large linear traversal

`scale.lani` reserves two real Vec backings once and reuses them at lengths
257, 4096 and 65536. Compound Row values and full-width u64 lookup keys have
their actual negative strides. Eleven cases per length give 33 pure phases:
equal equality/total/partial comparison, non-strict sorted duplicate runs,
first/middle/last mismatches, middle Unordered, a strict right prefix, a last
adjacency inversion and strict rejection of the first duplicate pair.

The host checks every result, both pull counts, callback count and final source
positions. Equal n-element comparisons make n callbacks and n+1 pulls per
side. Sorted n-element data makes n-1 adjacency calls and n+1 pulls. Decisive
pairs and inversions make only the pulls needed to consume that pair; prefix
comparison includes the unmatched longer-side item. Literal finite ceilings
are callbacks<=n and pulls<=n+1 per source. No exact-size, cached-identity or
length shortcut may change them. Every selected source field/value is checked
after each operation, including the deliberately changed mismatch/inversion.

The independent CPU sequence reference checked all 33 cases and exact effects,
the owner decision/resumption/keeper schedule and honest guard extents. Those
controls do not establish native execution. The accepted runtime gate separately
observed exactly two mappings/releases and no operation allocation. It makes
no claim about the internal cost of an arbitrary user callback, infinite-input
termination or wall-clock performance.

## Full effect/resource ledger and scope

Every executable must pass the existing strict x86_64 ELF/jump admission. Full
syscall traces reject every host effect inside P/p. All storage is reserved
before the first phase, with no allocation or release through the operations.
Every successful mmap address and requested length must match exactly one
successful munmap; unknown/double releases and live owners at D fail. Guard
setup additionally requires one protection of exactly the second 4096-byte
page of its 8192-byte mapping. Observation writes are parsed by their argument
and result counts, without depending on strace alignment.

Expected ledgers are 28 mappings/releases and ten phases for owners; one
mapping/protection/release and ten phases for guards; two mappings/releases
and 33 phases for scale. Each native lifecycle is bounded to 30 seconds and
the three registered selectors are run separately under the parent command
budget. Accepted target evidence is finite Linux x86_64 CPU execution produced
by the GPU compiler, with the actual tested storage layouts and page profile.
GPU-device execution, other targets, automatic ownership/lifetime enforcement
and formal verification remain unclaimed.

| Executed source | SHA-256 |
| --- | --- |
| `owners.lani` | `5e5e2e7ea25e92968fae8bf3b8e22348b6787ff7f728ce8b8637bdab54135bcf` |
| `guards.lani` | `3032fea61fc83120c7c4cbae60a36c7ac76ffc44dbb405120d79777e050cc9fa` |
| `scale.lani` | `a7ac6cc2ce4b94e09d6f91dad1a799b4490dc62d0fe2de30ef014c385a9a7174` |
| Rust driver/oracle, tested before formatting | `44416c97201609195a99addb63e8f88e4af7571bd165fe642483e87322cf9cbe` |

```text
cargo test --test stdlib_iterator_comparison_resource_execution iterator_comparisons_borrow_nested_owners_and_recover_discarded_owning_items -- --exact --nocapture
cargo test --test stdlib_iterator_comparison_resource_execution iterator_comparisons_guarded_short_circuits_zero_size_and_real_byte_strides_are_effect_free -- --exact --nocapture
cargo test --test stdlib_iterator_comparison_resource_execution iterator_comparisons_large_sequences_use_linear_pulls_and_callbacks -- --exact --nocapture
```
