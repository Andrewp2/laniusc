# Iterator equality, ordering and sortedness

The eight free consumers in [core::iter](../stdlib/core/iter.lani) compare
remaining sequences through the existing Iterator protocol. They fill a
previously missing iterator API family; existing slice operations retain their
own contracts. All eight registered library tests, all 119 application cases,
three migrated-consumer regressions and standalone build/examples pass on the
finite native Linux x86_64 profile. The [fixed increment plan](library-iterator-comparison-plan.md)
defines the contract and real-program acceptance scope.

## API and policies

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

Iterator and Mapper belong to core::iter; Pair to core::pair; Comparator and
Ordering to core::ordering. The [comparison traits](stdlib-comparison.md) and
four-variant PartialOrdering belong to core::cmp. No implicit supertrait or
blanket comparison implementation is assumed. Natural calls use the same item
type on both sides; the custom pairwise calls permit different item types.
Private natural policies delegate to the custom engines; total comparison
reuses core::ordering::Natural<T>, which may call lt(left,right) and then
lt(right,left). One policy invocation need not mean one scalar comparison.

The primary [Rust Iterator reference](https://doc.rust-lang.org/std/iter/trait.Iterator.html)
describes equality over elements and lengths, lexicographic decisions and
adjacent sortedness. Lanius supplies exact borrowed-cursor effects, existing
callback traits, explicit Unordered and manual cleanup in place of Rust's
ownership behavior.

## Pairwise consumption

Every round pulls **left once, then right once**, including when left returns
None. It calls a policy only for two Some values. Mapper receives one Pair
with left in first and right in second; Comparator receives those two operands
in that order.

| Observed round | Equality | Total/partial order |
| --- | --- | --- |
| None / None | true | Equal |
| None / Some | false | Less |
| Some / None | false | Greater |
| Some / Some | Continue only on true | Continue only on Equal |

A first unequal pair decides equality or total order immediately. Partial
comparison also stops immediately at Unordered; it is neither Equal nor an
absent Option result. No later element or final extra EOF probe is observed.
A length decision consumes the longer side's first unmatched item without a
callback. Equal finite n-item inputs make n+1 pulls on each side and n policy
calls. Descending element order still makes a shorter equal prefix Less.

There is no count, pointer-identity or length shortcut, cached lookahead,
rewind, or zip/all substitution. The two borrows may intentionally share a
cursor or upstream state: they observe sequential pulls, not two snapshots.
For example, three equal items in one aliased cursor yield one equal pair,
then Some/None: equality is false and order is Greater. Distinct cursors over
one immutable backing retain their ordinary independent positions.

## Adjacency and native floats

Sortedness pulls one seed. Empty returns true after that None. Each later
Some invokes the predicate once on (previous,current). A false result consumes
the second item of that rejected adjacency and returns without another pull;
the later remainder is available. A fully sorted finite source observes EOF
and makes max(n-1,0) predicate calls. A singleton is true without a comparison.

Natural eq uses PartialEq.partial_eq; partial_cmp uses PartialOrd.partial_cmp;
is_sorted uses PartialOrd.partial_le. Native float NaN therefore makes equality
false and a compared partial pair Unordered. An unordered adjacent pair is not
sorted, while a singleton NaN is sorted without a policy call. Signed zeros
compare equal; infinities retain the native partial-order rules. Native floats
do not satisfy natural total cmp; choose an explicit total float key or policy.

Custom is_sorted_by takes a **bool adjacency relation**, allowing nondecreasing,
strict or descending policies. This differs from
[slice::is_sorted_by](stdlib-slice-ordering.md), whose Comparator returns
Ordering. No existing slice signature or natural Ord requirement changes.

## Owners, effects and termination

Items, Pairs and callback operands are shallow observations. The helpers add
no allocation, cloning, destruction, source closing or draining after a decision.
Sortedness retains one previous shallow item, which must remain valid across the next pull and
adjacent comparison. Policies preserve operands and backing; owners, cursors
and policy context outlive the call. Concurrent/reentrant source mutation and
forged storage are outside the contract.

These result-only consumers do not return yielded items. An owning cursor
transfers cleanup authority on every Some, including decisive and unmatched
items; finishing it cannot recover owners already discarded by a consumer.
Use borrowed sources or retain a separate explicit cleanup authority for all
consumed items. There is no automatic move/drop, alias/lifetime enforcement,
source retirement or physical-trap rollback.

Iterator has no error channel. A source or policy must supply its own failure
behavior; these consumers do not convert errors into successful EOF. The
helper adds no host service, but a source or callback may allocate, perform
I/O, trap or take unbounded time. There is no quota. Bound inputs upstream
with Take when needed; matching infinite sequences or an indefinitely sorted
source need not terminate. Traversal is linear through its decision with a
constant number of shallow item slots; no metadata query is made.

## Program and verification status

The [compare_series program](stdlib-compare-series.md) parses bounded side/value
CSV into two Vec<i64> owners and uses fresh slice cursors for equality, lexicographic order
and each sortedness check. Descending mode supplies per-call policies; shorter
prefix order remains structural. It stages a quoted CRLF report before stdout
and releases input/CSV/vector owners before publication. The plan owns its
exact input, call, record, output and status limits. All 119 native application
cases pass across separate commands. Its functional group passes 44 cases in
one test/10.63s, three filtered
(iterator-comparison-compare-series-functional-retry.log), on
application source c143a686. CLI19/rejection35/I/O21 pass three tests in 9.63s,
functional filtered (iterator-comparison-compare-series-remaining-retry.log).
Two earlier batches stopped before execution; this is not a single passing
four-test command. The documented standalone compile exits zero silently
(iterator-comparison-compare-series-build-command.log); natural/descending
pipelines both exit zero and match exact 111-byte CRLF reports. These examples
overlap the corpus and add no case count.

Current production core::iter is 0efff466. The all-eight-API native admission
passes one registered test in 6.48s
(target/stdlib-work/iterator-comparison-admission-typed-retry.log). Its first
attempt stopped before execution with LNC0006 at a generic Option extraction
inside a Pair initializer. Explicit free extraction to typed element locals
before Pair/comparator calls preserves the API and traversal contract; no compiler repair is included.
The initial 2.60s compile failure remains a separate receipt, not a green run.

The remaining direct gates pass three tests in 8.90s, admission filtered
(iterator-comparison-direct-first.log): one five-scenario native contract
fixture and two tests grouping eight marked LNC0008 capability rejections.
All four direct registered tests are accepted across the two passing commands;
the negative compilations supplement the two native executions.

The independent model passes one test in 9.25s
(iterator-comparison-model-spaced-retry.log): 11,502 cases, all eight operations,
two layouts and seed 0xc0a0261104, producer 20916e2a. Its first attempt stopped
before execution with LNC0021 because fixture `>` immediately followed by `=`
was lexed as `>=`. Spacing alone fixed the fixture; compound Pair shapes and
production stayed unchanged. This is not a nested-Pair compiler restriction.
Physical model inputs contain at most 12 elements. Exact results, ordered
pull/callback pairs, remaining compound values and complete source backings
are checked; eight serialized-output corruptions are separate CPU verifier
controls, not native coverage counts or production mutants.

The guarded resource gate passes one test in 6.76s, two filtered
(iterator-comparison-guards-first.log): ten phases, one protected mapping with
its matching release, zero-sized values and native/packed stride cases.
The owner retry passes one test in 7.28s, two filtered
(iterator-comparison-owners-typed-retry.log): ten pure phases, twelve nested
owners with 24 backings and 28 matched mappings/releases, externally retained
owning yields, unmatched-item cleanup and remainder recovery. Its fixture's
first attempt failed before execution on pointer-literal typing; a typed
pointer element corrected only the fixture.
The scale gate passes one test in 7.33s, two filtered
(iterator-comparison-scale-first.log): 33 cases at lengths 257, 4096 and 65,536,
exact custom-policy counts <= n, pulls <= n+1 per source and two matched
mappings/releases. These are finite work-count checks, not isolated throughput
or a compiler-speed comparison.

The migrated Text equality/order operations and arena_words byte ordering now
use these engines. Three selected existing regressions pass separately:

| Receipt under target/stdlib-work | Accepted scope |
| --- | --- |
| iterator-comparison-text-contracts-regression.log | 1 Text contract test / 6.25s; three filtered |
| iterator-comparison-text-model-regression.log | 1 Text model test / 7.14s; three filtered |
| iterator-comparison-arena-words-regression.log | 1 arena_words program test / 9.26s; two filtered |

Their frozen sources are Text 2af4ec64 and arena_words 8019fcd4. These selected
regressions do not replace the new family gates. All eight registered library
tests are accepted: six native tests and two capability-bound groups with
eight marked rejections. The [direct](../tests/fixtures/stdlib_foundation/iterator_comparison/README.md),
[model](../tests/fixtures/stdlib_foundation/iterator_comparison_model/README.md) and
[resource](../tests/fixtures/stdlib_foundation/iterator_comparison_resources/README.md)
fixture guides retain exact commands, tested identities and failure histories.
Earlier iterator, comparison and slice receipts retain their original
source/API scopes and do not establish
these additions. Existing typed PartialOrdering match controls and other
[narrow compiler dependencies](library-dependencies.md) remain separately
documented; this increment does not claim a compiler repair. The new
[Option/Pair extraction reproduction and typed control](../tests/fixtures/stdlib_compiler_state/iterator_comparison_pair/README.md)
separately confirm the original source form's LNC0006 and successful native
typed extraction, without a general Option/Pair restriction.

Accepted execution is native Linux x86_64 CPU output from the GPU compiler.
User-program GPU execution, other targets, automatic ownership and formal
verification require separate support. The full library goal remains open.
