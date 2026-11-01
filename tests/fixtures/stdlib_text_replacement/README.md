# Literal text matching and replacement gates

Driver: `tests/stdlib_text_replacement_execution.rs`.
Contract: `docs/library-text-replacement-plan.md`.

All four native groups passed across the focused invocations below.
Independent source/driver review passed at the frozen hashes below, with no
changes or additional native runs requested. Root alone performed compiler/native commands. Rust
formatting, static checks and host-only controls of Unicode literal lengths,
scalar offsets and resource output bytes passed; they do not replace native
runtime evidence.

## Admission receipt

`literal_match_indices_and_owned_replacement_native_admission` passed 1/1
in 5.35 seconds after a 1.12-second Rust build, recorded in
`target/stdlib-work/text-replacement-admission.log`. It observed two exact
output allocations and releases, 0.004492 seconds native process time and
5.347922 seconds compilation. Production hashes were Text `b8495da2` and
String `dc9ccb76`.

The accepted admission driver was
`b811d6f2ddf94b46bd3c4088fc9567b0fe2b526f9b4d78e6fa9affe798093579`.
The final driver below adds three selectors without changing the admission
selector, runner or ledger. Admission is not rerun merely for those additions.

`admission.lani` checks relative byte indices and actual source subviews over
nonzero-offset, negative-stride UTF-8; empty-pattern scalar boundaries; both
replacement entry points with overlapping borrowed inputs; full source
preservation; and independent packed outputs of four and three bytes.

## Direct and resource receipts

The remaining three selectors passed 3/3 in 11.22 seconds after a 1.20-second
Rust build, recorded in
`target/stdlib-work/text-replacement-direct-resources.log`. Their source and
driver hashes are unchanged from the freeze below. The accepted run observed:

- Matcher: actual packed/descending layouts, generic Take composition, copied
  positions and fused exhaustion with zero allocations/releases and no host
  effects inside the pure phase. Native process time was 0.004504 seconds;
  compilation took 4.864005 seconds.
- Owned replacement: nineteen result cases, fifteen nonempty and four empty
  results, genuine 2^31-byte conceptual overflow, and seventeen exact
  allocations/releases. Native process time was 0.025214 seconds;
  compilation took 1.309680 seconds.
- Resources: one baseline and one reached denial/recovery process, each with
  six successful allocations/releases and all 307,712 output bytes matching.
  The selected large-result allocation was `mmap` 6. Old views and input
  owners survived the error, and the same inputs recovered in the same
  process. Native times were 0.230944 and 0.253679 seconds; compilation took
  4.524288 seconds.

Together with the earlier admission, these are four accepted selector
identities and five native processes. Admission was not repeated. Native
timings include tracing, setup, checks, publication and cleanup; they are
separate from compilation and are not isolated operation benchmarks.

## Borrowed matcher contracts

Selector:
`literal_match_indices_scalar_boundaries_strides_copies_and_generic_composition_execute`

`matcher.lani` checks leftmost nonoverlapping results, adjacent/end matches,
longer/absent needles, empty source and empty needle. A selected Unicode span
contains NUL, ASCII, and two-, three- and four-byte scalars; all empty-pattern
boundaries have exact expected byte offsets. Every returned Pair has the
relative index, matching source start/length, original stride and exact bytes.
Composed and decomposed accents remain distinct literal byte sequences.

Actual native byte arrays have negative stride; the packed control has stride
+1. Each is used as source with the other layout supplying its needle. Cursor
copies fork state, exhausted cursors remain exhausted, and generic Iterator
pulls compose with Take, including a zero-count adapter that leaves its source
unconsumed. All backing and guard bytes remain unchanged. The full process
has one pure phase and zero allocations or releases; no host service is
allowed between its markers.

## Owned replacement contracts

Selector:
`literal_owned_replacement_exact_limits_u64_counts_and_valid_backed_overflow_execute`

`owned.lani` has nineteen selected result cases: shrinking, growth, deletion,
nonrecursive insertion, overlapping source matches, zero/one/exact/wide u64
counts, absent/long needles, empty input/pattern, and Unicode/NUL replacement
over strided aliases. Count limits include 2^32 and u64::MAX. Every nonempty
result has exactly the measured capacity and bytes; its exact output limit
succeeds and one byte less returns OutputLimit. Four empty results allocate
nothing. Fifteen nonempty cases each make and release one exact result owner.

Two real packed owners contain 32,768 one-byte matches and a 65,536-byte
replacement. The complete conceptual result is exactly 2^31 bytes, so
CapacityOverflow must precede OutputLimit even at max_output zero. Negative
max_output returns Bounds before that measurement, including count-zero and
empty operations. A large source may shrink to an empty result under limit
zero. All 98,304 bytes of the real overflow inputs remain unchanged.

The expected process has seventeen pure phases and seventeen exact allocations
and releases: two input owners plus fifteen nonempty results. No fictitious
large Text or invalid physical backing is needed for the overflow boundary.

## Aliased owners, reached failure and independence

Selector:
`literal_matching_and_replacement_preserve_aliased_owners_and_recover_reached_allocation_failure`

`resources.lani` builds actual String owners containing selected source spans
of 4,096 and 262,144 bytes. Each source uses a 32-byte UTF-8 pattern containing
two literal accents, an emoji, NUL and mixed line/space bytes. Source, needle
and replacement are nested subviews of the same owner. Five leading and seven
trailing initialized guard bytes surround the selection; the reserved capacity
also exceeds initialized length.

Borrowed phases cover early stop, cursor copies, every nonempty match and every
empty-pattern scalar boundary. They check complete source bytes, original
pointer, length and capacity. Main replacement expands each accent to an emoji.
The small cycle also produces independent count-zero and no-match copies; the
absent needle borrows the same owner's guard prefix. Every old source view
remains valid on both success and error because inputs remain immutable.

After all results are built, the source owner is explicitly destroyed. Every
result is checked again, then its complete bytes are published. The host
independently derives the expected UTF-8 replacement using Rust strings and
compares all 307,712 output bytes. Each actual stdout write must occur with
exactly the independent result owners live, followed by one release per result.

The baseline has six exact allocations and releases across two source sizes.
One additional process denies the large result reservation selected from that
baseline. The error must return no partial owner and preserve the source's
complete bytes, pointer, length, capacity and borrowed aliases. A same-process
retry on those same inputs must succeed, with the same complete final output
and six successful allocations/releases plus one reached failed reservation.
There is no fake allocation-failure campaign for the allocation-free matcher.

## Trace and target scope

The full-syscall ledger tracks full-width addresses and exact requested extents,
rejects overlapping live owners, unknown/repeated releases and incorrect sizes,
and requires no live allocation at each cycle's explicit retirement marker.
Process exit is not cleanup evidence. Setup/source extents come from explicit
caller reservations; output extents follow the one-exact-allocation contract.
Pure phases forbid all host effects. Only marked owned calls may allocate
after setup; complete operation traces and every publication's owner set are
checked independently by the driver. Reached denial selection comes from
the successful baseline, not an assumed allocation ordinal.

All artifacts must be ELF x86-64 and pass the shared complete jump validator.
Each native process is limited to fifteen seconds. Native timings include
tracing, setup, checks, publication and cleanup, and are separate from compiler
timings. These finite sizes do not establish linear-time search or throughput.
Valid UTF-8 Text metadata, stable physical backing and manual lifetime rules
remain caller preconditions; these tests impose no forged-Text validation.
Initial support is Linux x86-64 CPU output from the GPU compiler. Device
execution, other hosts, enforced borrowing and formal proof need separate
evidence. Broad Unicode differential coverage belongs to the model gate.

## Frozen hashes

- Driver: `b644382b2e0ad6ae36da03a7c646f8c72a52722b9d44789c6bcf0726b6699221`
- `admission.lani`: `733fceabae90d175326191b6b8e33c305203336cf7b6d08f5a8283fad92e0706`
- `matcher.lani`: `518afab00b1930359382a20327ede943a8a3616df0b88541d4158835d3d5622f`
- `owned.lani`: `c2cc4bfe735dde606592187434bb6a5c33497e38cd8d65c2a1f420fe2add8cde`
- `resources.lani`: `dcb8f95a022532c3f5f246a6df7424bc5ac7105198c42c1ff79b9254b8d012ec`
