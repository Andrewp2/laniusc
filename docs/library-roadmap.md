# Standard and extended libraries

The goal is a complete, usable standard library and a broad extended library,
implemented in Lanius. This document tracks the whole scope. Completing the first
milestone does not complete the goal.

## Dependency layers

| Layer | Owns | May depend on |
| --- | --- | --- |
| `core` | Values, borrowed views, algorithms, codecs | Compiler intrinsics with explicit target contracts |
| `alloc` | Allocators and owned portable data structures | `core`, allocator bindings |
| `std` | Application interfaces and host services | `core`, `alloc`, explicit host bindings |
| `ext` | Larger optional libraries | The layers above and declared extended-library dependencies |

Allocation-backed collections currently live under `std`. Move them to `alloc`
with their consumers when their APIs are revised; do not add forwarding modules
solely to preserve internal paths. The first string implementation belongs to
`alloc`. Its temporary dependency on `std::vec` must disappear when that vector
moves. Extended modules can use an additional source root in this repository;
package distribution is a separate deliverable.

## Standard library scope

| Family | Required contents | Starting state, 2026-10-22 |
| --- | --- | --- |
| Fundamental values | Option, Result, ordering, comparison, hashing, cloning, explicit errors | Generic Option/Result and comparison exist; contracts and composition need review |
| Numbers | Every primitive width, checked/wrapping/saturating arithmetic, conversions, bit operations, floating-point utilities | Many implementations and runtime fixtures exist; consolidate duplicate paths |
| Borrowed data | Arrays, slices, ranges, searching, sorting, partitioning, copying | Generic algorithms and counted View values execute, including subviews, checked mutations and cursors; initial physical counts still require compiler length projection |
| Iteration | Explicit iterator protocol, ranges, slices, collections, text, adapters, consumers | Inherent slice/text/hash-map cursors execute; shared protocol dispatch hits an imported-generic compiler dependency; adapters and collection integration remain |
| Text | Borrowed UTF-8, owned String, Unicode scalars, byte boundaries, search, split, trim, join, parse, formatting | Packed String, borrowed Text, scalar/word iteration, join/repeat and integer conversion execute; general formatting and further Unicode operations remain |
| Memory | Allocation contracts, layout, owned buffers, arenas, explicit destruction and clone behavior | Allocator bindings and raw views exist; ownership conventions need consolidation |
| Collections | Vec, deque, hash map/set, ordered map/set, heap, bitset, fixed-capacity containers | Generic vectors/deques, linear maps/sets, alloc hash maps and min/max binary heaps execute; hash-set composition is a compiler dependency |
| I/O | Reader/writer contracts, buffers, exact/all operations, cursors, stdin/stdout/stderr, errors | Shared traits, slice cursors, owned byte sinks, native descriptor adapters and owned files execute; buffered adapters remain |
| Files and paths | File handles, metadata, directories, walking, lexical paths, filesystem operations | Owned files and borrowed byte paths execute with explicit close/error contracts; metadata, directories and complete lexical paths remain |
| Processes and environment | Arguments, environment, working directory, subprocesses, pipes, exit status | Argument/environment helpers exist; subprocess management remains |
| Time and randomness | Duration, instant, system time, deadlines, deterministic generators, OS entropy | Clock and entropy helpers exist; coherent types and generators remain |
| Networking | Addresses, sockets, TCP, UDP, resolution, deadlines, explicit host errors | Current network module is contract-only |
| Concurrency | Threads, joining, synchronization, atomics, channels, cancellation | Current thread module is contract-only; runtime prerequisites remain |
| Development | Assertions, test runner, property helpers, benchmarks, diagnostics, API docs | Existing compiler-driven fixtures; a complete Lanius-facing workflow remains |

## Extended library scope

Each entry needs a public API, executable implementation, examples, failure
tests, target support, and relevant performance evidence.

| Family | Deliverables |
| --- | --- |
| Data formats | JSON, CSV, TOML, binary serialization, schema/validation utilities |
| Text and parsing | Unicode properties and normalization, regex, lexers, parser utilities, diff and patch |
| Files and packaging | Globs, directory walking utilities, compression, archives |
| Network protocols | URL handling, HTTP client/server, WebSockets, DNS, TLS integration |
| Storage | Database interfaces, SQLite integration, key-value storage |
| Mathematics | Big integers, decimal arithmetic, statistics, linear algebra, geometry |
| Application utilities | CLI parsing, logging, configuration, tables, progress reporting |
| Media | Image codecs, pixel operations, audio codecs and signal utilities |

For external formats and algorithms, use their primary specifications and
published conformance vectors. Choose exact versions and formats when starting
each family. Host and third-party integrations need explicit dependency and
availability contracts; do not substitute success-shaped placeholders.

## Delivery sequence

1. **Text and data foundation.** Packed byte buffers, owned UTF-8 strings,
   text operations, parsing, formatting, writer/reader contracts, hash maps,
   CSV and JSON. Acceptance application: read CSV, validate and group records,
   then emit JSON, including malformed-input and I/O failure cases.
2. **Everyday programs.** Iterators, remaining collections, files and paths,
   arguments, configuration, logging, clocks and randomness. Acceptance
   application: a directory report with filters and structured output.
3. **Connected programs.** Runtime bindings for sockets, processes and threads;
   HTTP, URLs, cancellation and synchronization. Acceptance applications:
   a bounded concurrent downloader and a local HTTP service.
4. **Storage and packaging.** Database integration, key-value storage,
   compression, archives, binary serialization and schemas. Acceptance
   application: a persistent indexed archive with checked round trips.
5. **Text, mathematical and media libraries.** Complete the remaining extended
   families with representative applications and their conformance suites.
6. **Distribution and completion audit.** Document installation and imports,
   verify selective dependencies, target support and compile-time scaling,
   and audit every row above against executable evidence.

Families can proceed independently once their dependencies have working
contracts. A compiler defect should have a minimal reproduction and an affected
API list; unrelated library work can continue.

## Completion requirements

- Public APIs perform their documented work. Unsupported operations fail
  explicitly and are excluded from executable support claims.
- Bounds, overflow, invalid encoding, allocation failure, partial I/O and
  resource lifetime have documented behavior and runtime tests.
- Tests import the real modules, compile Lanius programs, and execute them.
  Type checking alone is insufficient. Collection tests compare operation
  sequences with a reference model; format tests include malformed inputs.
- Every family has a real application using several of its modules.
- Target support is recorded per module. The initial executable target is
  x86_64 Linux; Wasm claims need separate execution evidence. Running the
  compiler on a GPU does not establish user-program GPU execution.
- Measure relevant operations and representative large-library compile
  workloads with the repository's performance tools. Keep each command below
  two minutes and avoid unrelated GPU test reruns.
- The language implementations remain Lanius. Rust/Python may drive tests;
  they do not implement library behavior. No JSON transport or Wasm dependency
  is introduced as a substitute for native library execution.

## Current work

- Branch: `codex/stdlib`, based on `441e66f9`.
- Scope and API conventions: recorded in this document and
  [library-api-conventions.md](library-api-conventions.md).
- Packed owned UTF-8 string: the first implementation and three executable
  test groups pass on x86_64 Linux, including allocation fault injection and a
  text-processing program. See [stdlib-string.md](stdlib-string.md) for exact
  coverage and remaining String operations.
- Compiler and runtime prerequisites: [library-dependencies.md](library-dependencies.md).
- Extended CSV: parsing, independent field copies and canonical encoding execute
  on x86_64 Linux, including generated tables, borrowed field views and allocation fault injection.
  See [extended-csv.md](extended-csv.md). Incremental decoding now shares the same parser; row construction remains.
- Shared I/O: portable Read/Write traits, exact/all/copy operations, slice
  cursors, owned byte buffers and native descriptor adapters have execution
  coverage. CSV uses these streams. See [stdlib-streams.md](stdlib-streams.md).
- Extended JSON: iterative parsing/building/encoding, exact number text,
  queries and independent string copies execute on x86_64 Linux, including
  generated trees, limits and allocation fault injection. See
  [extended-json.md](extended-json.md).
- Integer text conversion: [decimal](stdlib-decimal.md) parsing, indexed digit
  access and checked buffer formatting execute for all ten native integer types,
  including i64/u64/isize/usize. Bounds, overflow and insufficient capacity have
  explicit errors. Text methods, owned String construction/appends and native
  output use these conversions; the window-report example now writes i64 sums
  directly. Reference cases and allocation/I/O faults pass on x86_64 Linux.
  With 4,096 samples and width 64, paired native application runtime falls from
  2,539 to 131 ms versus the previous two-word sum output.
- Hash map: [`alloc::hash_map`](stdlib-hash-collections.md) executes generic
  lookup, replacement/removal, reserve, shrink, clone and iteration, including
  collision models and allocation failures. String and all integer widths
  implement hashing. The HashSet wrapper is retained as a compiler reproduction,
  outside the production source root.
- Binary heap: [`alloc::binary_heap`](stdlib-binary-heap.md) executes min/max
  queues, linear bulk construction, root replacement, allocation-safe reserve,
  shrink, clone, aliased extension and sorted ownership transfer. Five test
  groups cover generic payloads, 12,000 modeled operations, zero-sized values,
  allocation failures and a top-scores program. For 65,536 records, bulk
  construction uses 131,040 comparisons and about 24 ms native runtime versus
  917,522 comparisons and 117 ms for repeated insertion, with one allocation
  in each path. This does not establish GPU user-program execution.
- CSV-to-JSON integration: the [report application](csv-report.md) validates
  schemas and integers, groups records, checks totals and emits JSON. Native
  tests cover generated records, all allocation failures and partial I/O.
  It now uses the hash map; paired measurements improve the 1,024-group case
  from about 694 ms to 307 ms. The report now uses incremental input and
  packed reusable record buffers.
- Borrowed text: [core::text::Text](stdlib-text.md) executes validation, checked
  subviews, comparison/search, scalar and split iteration, hashing and decimal
  parsing without copying. String and CSV expose borrowed views. The report
  copies each distinct group name once, and reads other fields directly. Paired
  native measurements show 232→175 ms for 4,096 records/64 groups and
  303→269 ms for 4,096 records/1,024 groups before the streaming migration.
- Streaming CSV: one decoder handles complete tables and chunked input,
  including split UTF-8/quotes/CRLF, explicit EOF, sticky errors, resource limits
  and owned record transfer. A syscall-traced 4,096-record run allocates nothing
  after warm-up. The grouping report now retains only current-record buffers
  and group data during input. Paired native runtime falls from 173 to 26 ms
  for 4,096 records/64 groups; peak live allocation request sizes fall from
  779 KB to 99 KB. See [extended-csv.md](extended-csv.md) and [csv-report.md](csv-report.md).
- Borrowed slices: [View and cursors](stdlib-slice-views.md) execute with checked
  logical bounds, overlapping copies, chunks/windows and iteration from either
  end. A 6,388-command model checks stateful behavior. The window-report example
  combines parsing and owned vectors with borrowed windows and exact statistics,
  including allocation and I/O failure coverage. Initial counts still require
  valid physical backing; shared generic iterator dispatch remains a compiler
  dependency with a minimal reproduction and executable controls.
- Next foundation work: resolve shared iterator and HashSet compiler dependencies;
  continue text operations, buffered I/O and
  remaining streaming format interfaces; complete HashSet when its compiler
  dependency is resolved. Consolidate Vec and deque under alloc with explicit
  fallible APIs and migrate their consumers; ordered collections remain.
  Completing the integration application does not complete the first phase.
- Text composition: [join, repeat and word splitting](stdlib-text-composition.md)
  execute with atomic, alias-safe appends, checked sizes and one-allocation
  construction. An executable whitespace normalizer combines borrowed words,
  owned strings, vectors, streams and decimal argument parsing. Generated models,
  capacity overflow and every observed allocation failure are covered.
  For 65,536 parts, paired native runtime is 75.73 ms for join versus 116.36 ms
  for repeated appends; whole-program allocation calls fall from 19 to 2.
  Generic buffered stream adapters hit the same module-context implementation
  routing limitation as iterator consumers; the minimal Write reproduction and
  successful controls are recorded in the compiler dependency list.
- Owned files: [File and Path](stdlib-files.md) execute read/create/append,
  generic stream operations, explicit close and ownership transfer on x86_64
  Linux. Tests check binary and non-UTF-8 data, descriptor reuse, path bounds,
  all acquisition/transfer/close failure paths and absence of heap allocation.
  The file-concatenation application closes inputs on errors and preserves bytes.
  Buffered I/O, complete paths and filesystem runtime extensions remain.
- The older [execution audit](stdlib-foundation.md) remains historical evidence;
  its top-level checkpoints do not establish this branch's current behavior.
