# Shared iterator sequence comparison

## Purpose and boundary

Complete the shared-iterator sequence-consumer family in `core::iter`.
Slices already have equality, lexicographic comparison and sortedness; this
increment makes those operations compose through the canonical `Iterator<T>`
protocol, including mapped, reversed and collection-backed sources. Do not add
a second iteration or comparison protocol. The full standard/extended-library
goal remains open.

The source reference is the official [Rust Iterator documentation](https://doc.rust-lang.org/std/iter/trait.Iterator.html):
equality compares corresponding elements and lengths, lexicographic comparison
uses the first decisive pair before length, and sortedness checks adjacent
relations. Lanius uses borrowed cursors, existing callback traits and its
four-variant PartialOrdering. Its exact effects and manual ownership follow
the contracts below, rather than Rust automatic destruction.

## Fixed API

Add exactly these eight free functions to existing `core::iter`:

```text
eq<A,B,T>(left:&A,right:&B) -> bool
    where A:Iterator<T>, B:Iterator<T>, T:PartialEq<T>
eq_by<A,B,P,T,U>(left:&A,right:&B,predicate:&P) -> bool
    where A:Iterator<T>, B:Iterator<U>, P:Mapper<Pair<T,U>,bool>
cmp<A,B,T>(left:&A,right:&B) -> Ordering
    where A:Iterator<T>, B:Iterator<T>, T:Ord<T>
cmp_by<A,B,C,T,U>(left:&A,right:&B,comparator:&C) -> Ordering
    where A:Iterator<T>, B:Iterator<U>, C:Comparator<T,U>
partial_cmp<A,B,T>(left:&A,right:&B) -> PartialOrdering
    where A:Iterator<T>, B:Iterator<T>, T:PartialOrd<T>
partial_cmp_by<A,B,P,T,U>(left:&A,right:&B,comparator:&P) -> PartialOrdering
    where A:Iterator<T>, B:Iterator<U>, P:Mapper<Pair<T,U>,PartialOrdering>
is_sorted<I,T>(source:&I) -> bool
    where I:Iterator<T>, T:PartialOrd<T>
is_sorted_by<I,P,T>(source:&I,predicate:&P) -> bool
    where I:Iterator<T>, P:Mapper<Pair<T,T>,bool>
```

Names refer to existing `core::cmp::{PartialEq,Ord,PartialOrd,PartialOrdering}`,
`core::ordering::{Ordering,Comparator}`, `core::pair::Pair` and
`core::iter::{Iterator,Mapper}`. Natural operations are same-item-type because
the current scalar comparison traits take two arguments of that trait type.
The custom pairwise operations permit different item types. No independent
supertrait bounds or implicit derive are assumed.

Use private natural callback adapters and delegate to the custom engines.
Natural total comparison reuses existing `core::ordering::Natural<T>`.
Do not duplicate traversal in natural wrappers, add forwarding aliases or
change existing consumer bodies. No compiler, ABI, host, formal or protected
`std::vec` changes belong here. A missing compiler composition gets a minimal
reproduction and a dependency report.

## Pairwise traversal and decisions

Every pairwise round pulls left once, then right once, even when left returns
None. Only when both yield Some does it invoke one callback, with left then
right operands (Pair.first/second for Mapper). No length/count shortcut,
identity shortcut, lookahead cache, rewind, final extra probe or zip/all
implementation may change those effects.

- Both None: equality true and comparison Equal.
- Left None, right Some: equality false, comparison Less.
- Left Some, right None: equality false, comparison Greater.
- Both Some: equality stops at false; total comparison stops at Less/Greater;
  partial comparison stops at Less/Greater/Unordered. Equal continues.

The decisive pair is consumed; the untouched suffix remains available.
A prefix-length decision consumes the longer side's first unmatched item.
Equal finite inputs of length n receive n+1 pulls on each side. No callback is
called on absent operands. Descending element policies do not reverse the
structural shorter-prefix rule.

The two borrows may intentionally refer to the same cursor or shared upstream
state. Sequential left/right pulls observe that actual state; no reflexivity
is implied. For example, three equal items in one aliased cursor produce one
equal pair then Some/None, so equality is false and comparison Greater.
Distinct cursors over the same immutable backing are ordinary independent
sources. Callbacks must not reenter or invalidate either source or its backing.

## Sortedness and partial comparison

Sortedness pulls one seed. Empty returns true after that None. Each later Some
invokes the predicate once on (previous,current); false returns immediately,
consuming the bad pair's second item and no later item. True advances previous.
A fully sorted n-item source observes EOF and uses max(n-1,0) predicate calls.
A singleton is true without a predicate call, even for NaN.

Natural equality uses PartialEq.partial_eq. Natural partial comparison uses
PartialOrd.partial_cmp and returns the existing explicit Unordered variant,
not a new Option encoding. Natural sortedness uses PartialOrd.partial_le;
an unordered adjacent pair is false. Native floats therefore support these
three partial operations, but do not satisfy natural total cmp. Custom
is_sorted_by is a bool adjacency relation (allowing strict or descending
policies), unlike slice::is_sorted_by's Ordering comparator.

## Ownership, work and failure

All items and callback operands are shallow values. The helpers do not clone,
allocate, destroy, drain or close sources. Sortedness retains one shallow
previous item until another comparison or return; callbacks must keep that
operand valid for its next adjacent use. Other callbacks also preserve operands
and backing. Owners/callbacks and borrowed storage outlive the call; no
concurrent/reentrant mutation or forged backing is supported.

These result-only consumers discard yielded values. An owning source transfers
cleanup authority for every Some, including a decisive or unmatched item.
Use borrowed sources, or retain a separate explicit cleanup authority for all
consumed items. Finishing an owning source releases only its remaining items
and backing; it cannot recover already discarded owners. No automatic move,
drop, alias/lifetime enforcement or physical-trap rollback is claimed.

There is no fabricated error/exhaustion conversion. Ordinary Iterator has no
error channel; callback/source errors require the caller's explicit policy.
These ordinary consumers have no work quota and may not terminate for equal
infinite inputs or indefinitely sorted sources. Bound inputs upstream with
Take when needed. One source/callback operation may do unbounded internal work.
Finite pairwise traversal is linear through its decision; sortedness is linear
through the first rejected adjacency, with constant helper storage.

## Acceptance and ownership

The real program is `compare_series [--descending/-r] [--help/-h]`, with no
operands or duplicate flags. Help accepts otherwise valid options and bypasses
stdin; it does not waive invalid CLI. Capture at most eight argument entries
and 1024 bytes with the existing argv owner. Ignore SIGPIPE first.

Read stdin through public read_to_end with 1 MiB/8192 Read calls, including
the actual required EOF/cap probe. Parse canonical CSV with exact header
`side,value`, then exactly two fields per record: literal `left` or `right`
and a signed i64 parsed by existing decimal rules (optional sign/leading zeros,
1..64 decoded bytes, no trimming). Preserve within-side order even for
interleaved records. Require the normal LF/CRLF/quoted/final-unterminated CSV
profile, 64 decoded bytes per field, 128 per record and 65,537 total records
including the header. At most 65,536 data records combined. Empty stdin is
invalid; header-only means two empty sequences. No BOM or case normalization.

Store each side in an ordinary Vec<i64>. Release raw input and CSV decoder
after parse; use fresh byte-independent slice cursors for each equality,
lexicographic comparison and sortedness operation. Natural mode calls eq,
cmp and is_sorted; descending mode uses cmp_by and is_sorted_by with per-call
contexts, and the same natural equality. Reversing element comparison leaves
the shorter-prefix rule unchanged. No private sequence comparison/sort loop.

Emit two fully quoted CRLF CSV rows. Header fields are
`left_count,right_count,equal,order,left_sorted,right_sorted`; data fields are
unsigned counts, `true`/`false`, `less`/`equal`/`greater`, and two booleans.
Stage the complete report through canonical CSV writing into a 512-byte
caller-backed SliceWriter. Release all Vec, argument and CSV owners before
stdout publication. No stdout appears for any earlier failure. Publication
is attempt-bounded (64 data/help writes, eight diagnostic writes), with only
confirmed positive progress and Interrupted retry; no atomic-output claim.

Statuses: zero for every valid report/help, regardless of comparison results;
2 for CLI/CSV/input/work/storage limits; 3 for input/argument host failures;
4 for allocation; 5 for output/SIGPIPE policy; 6 for internal contracts.
SIGPIPE setup failure is silent. Other failures preserve the primary status
and attempt `compare_series: operation failed\n` after releasing owners.
The app/test authors fix exact help spelling and literal lengths before
runtime admission, keeping these contracts and finite quotas.

Root owns this plan, native commands, reference generation and commit/push.
Separate authors own production, direct/capability tests, independent model,
owner/guard/scale tests, real program, program tests, selected consumer
migrations and semantic docs. Root alone runs compiler/Cargo/native gates,
serially under the library GPU lock, every command below two minutes.

Require strict native ELF/jump admission and real normal/edge execution for
all eight APIs; exact pull/callback order, both prefix directions, resumption,
shared-state aliases, heterogeneous and compound items, NaN/zero/infinity,
empty/singleton and strict/reverse policies. Negative capability tests supplement
execution. An independent finite model checks results, effects and remaining
state. Selected resource tests establish no hidden allocation/release, valid
native stride and zero-sized data, guarded short circuits and linear large
work. A bounded real program and direct migrated consumers need their own
focused runtime evidence. Old receipts retain their source/API scope.

Initial acceptance is native Linux x86_64 CPU output from the GPU compiler.
User-program GPU execution, other targets and formal verification require
separate support. Documentation must distinguish source inventory, runtime
receipts and remaining compiler/runtime dependencies.
