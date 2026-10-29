# Generic borrowed slice segmentation

The complete standard/extended-library goal remains open. The preceding Text
increment is committed at `cd29120b`. The current source provides generic
slice iteration, chunks and windows, but no predicate segmentation. This
increment fills that ordinary main-library gap through the existing protocol.

## Interface and module boundary

Add three public cursor types and checked free factories in `core::slice`:

```text
Split<T,P>
SplitInclusive<T,P>
ChunkBy<T,P>
split<T,P>(values:View<T>, predicate:&P) -> Result<Split<T,P>,ViewError>
split_inclusive<T,P>(values:View<T>, predicate:&P) -> Result<SplitInclusive<T,P>,ViewError>
chunk_by<T,P>(values:View<T>, predicate:&P) -> Result<ChunkBy<T,P>,ViewError>
```

Each type has `borrow()`. Implement `Iterator<View<T>>` in `core::iter`, where
the existing slice cursor implementations already live. Split variants require
`P:Mapper<T,bool>`; ChunkBy requires `P:Mapper<Pair<T,T>,bool>`. Import core::iter
when using next. No duplicate inherent next, new predicate trait, import cycle,
View forwarding facade, reverse capability or ExactSize capability is added.
Factories do not invoke P; capability checking belongs to iteration, so a
descriptor with a non-Mapper P can be constructed but cannot be iterated.

Factories reject negative start/length or start+length exceeding i32::MAX with
ViewError::Bounds before reading backing or invoking P. Reuse/generalize the
existing private logical View validator instead of adding a competing policy.
Success captures the descriptor, cursor position and predicate reference only.
It neither validates physical length nor scans values. Empty valid ranges,
including a maximum start, require no backing access. Cursor fields remain
subject to valid-state preconditions; forged cursor fields are not revalidated.

## Partition and effect contracts

The partition meanings follow the familiar
[slice split](https://doc.rust-lang.org/std/primitive.slice.html#method.split),
[inclusive split](https://doc.rust-lang.org/std/primitive.slice.html#method.split_inclusive)
and [adjacent grouping](https://doc.rust-lang.org/std/primitive.slice.html#method.chunk_by)
interfaces. Lanius uses its existing borrowed Mapper and shallow item values.

- Split excludes matching elements. Leading, adjacent and final separators
  retain empty segments; empty input produces one empty segment.
- SplitInclusive includes a matching element at the end of its segment.
  Empty input produces no segment, and a terminal match adds no phantom item.
- ChunkBy joins adjacent elements while its predicate returns true. False
  starts another nonempty segment. Empty input yields none; a singleton yields
  itself without a callback. No equivalence/transitivity law is required.

next is lazy and stops immediately after the boundary needed for its result.
Unary predicates receive each scanned element once. Adjacent predicates receive
each scanned pair once in left/right index order, including the false boundary
pair; that pair is not repeated on the following pull. Complete traversal makes
exactly n unary or max(n-1,0) adjacent calls in increasing index order. Repeated
None makes no calls or reads. A split's final empty segment is Some(empty), not
None. Never compute length+1 in i32 to count possible split results.

Yielded Views preserve original absolute offsets and actual stride. No element
clone, allocation, destruction or backing write occurs in library traversal.
Callbacks can update their own context, so traversal may have callback-defined
effects; pure callbacks permit a pure full syscall trace. Callbacks must keep
operands/backing alive, must not mutate backing during a pull, and must not
reenter or directly modify the cursor. No cleanup authority is transferred.

Between pulls, caller alias writes to still-live elements and predicate context
are observed by later reads/calls; already selected boundaries are not revised.
ChunkBy reads both adjacent operands when making that call, retaining no T
across pulls. Cursor copies fork position and share the predicate context and
backing. Keep both alive, with stable storage, while cursors/results exist;
copies do not extend lifetimes. These conventions are not a borrow checker.
No trap recovery/rollback or fallible callback protocol is promised here.

Storage is constant. Complete traversal is linear in visited elements plus
callback work. One pull may scan the entire remainder. Arbitrary stateful
callbacks are supported under the effect rules; reverse order needs a separate
callback contract and is outside this family.

## Real program

Add `sample_programs/library/record_summary.lani`. Read binary stdin, split
records inclusively on LF, remove only that final LF from each record, split
fields on comma preserving empties, and find the longest run of identical
adjacent bytes using ChunkBy. CR, NUL, non-UTF-8 and quotes are ordinary bytes.
This is a delimiter report, not a quoted CSV parser.

Emit exact TSV header `record\tbytes\tfields\tempty_fields\tlongest_run\n`.
Rows contain one-based record number, content byte length, field count, empty
field count and longest equal-byte run. Empty stdin produces only the header;
an empty record has one empty field and longest run zero. A terminal LF adds
no phantom record. Keep one input byte owner and fixed 64-byte row scratch;
no owned per-record/field copies or cached record array.

Accept no arguments. Admit at most 1 MiB and 65,536 records, using a real
extra-byte/EOF probe at the byte cap. Complete byte/record admission precedes
the header. Read attempts are bounded to 16,384, global payload writes to
131,072 and diagnostic writes to 64; Interrupted consumes an attempt. Status
0 is success, 2 arguments/byte/record/call limit, 3 I/O/diagnostic failure, 4
allocation. Failed SIGPIPE-ignore setup returns 3 without a diagnostic.
After publication begins, output failure/attempt exhaustion can leave a
confirmed prefix. Diagnostic failure overrides the primary status with 3.
Reuse the canonical collector and stream/decimal/args APIs. App/test owners
agree phase-specific literal diagnostics before freezing.

## Verification and ownership

Root alone executes compiler, Cargo and native commands, serially under the
existing lock with each outer command below two minutes. Agents may inspect
files, prepare tests and run bounded host-only model controls. Do not change
compiler/IR/ABI/proofs/extractor, protected std::vec/core::mem or tests/common.
Reproduce a missing compiler capability separately. The known generic chained
Option method limitation has an existing reproduction; use typed locals/matches
where needed without specializing generic production APIs.

Required evidence: tiny generic admission; exact partitions/offsets/strides,
empty/MAX metadata and callback traces; compound generic elements and bounded
adapter composition; capability rejections with executable positive controls;
independent models including cursor copies and permitted alias/context edits;
live owner/no-cleanup observations and full backing preservation; complete
program output, limits and reached allocation/I/O failures. Choose focused
existing slice/iterator regressions because their source modules change.

Initial executable target is native Linux x86_64 CPU output via the GPU
compiler; broader targets and user-program device execution remain separate.
Keep API inventories, acceptance evidence and dependencies outside the human
README. Root updates the generated reference after metadata freeze, commits
the verified increment and pushes codex/stdlib. The full goal remains active.
