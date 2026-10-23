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

Allocation-backed collections are moving from `std` to `alloc` with their
consumers and revised failure contracts. String and owned byte streams now use
`alloc::vec`. The heap migration has a compiler dependency; the old vector path
also remains part of the verified compiler's extraction contract. Do not add
forwarding modules solely to preserve internal paths. Extended modules can use
an additional source root in this repository;
package distribution is a separate deliverable.

## Standard library scope

| Family | Required contents | Executable state and remaining work |
| --- | --- | --- |
| Fundamental values | Option, Result, ordering, comparison, hashing, cloning, explicit errors | Generic Option/Result and comparison exist; contracts and composition need review |
| Numbers | Every primitive width, checked/wrapping/saturating arithmetic, conversions, bit operations, floating-point utilities | Many implementations and runtime fixtures exist; consolidate duplicate paths |
| Borrowed data | Arrays, slices, ranges, searching, sorting, partitioning, copying | Generic algorithms and counted View values execute, including subviews, checked mutations and cursors; initial physical counts still require compiler length projection |
| Iteration | Explicit iterator protocol, ranges, slices, collections, text, adapters, consumers | Inherent slice/text/hash-map cursors execute; shared protocol dispatch hits an imported-generic compiler dependency; adapters and collection integration remain |
| Text | Borrowed UTF-8, owned String, Unicode scalars, byte boundaries, search, split, trim, join, parse, formatting | Packed String, borrowed Text, scalar/word iteration, join/repeat, integer conversion and caller-buffer Display formatting execute; float formatting, format strings and further Unicode operations remain |
| Memory | Allocation contracts, layout, owned buffers, arenas, explicit destruction and clone behavior | Allocator bindings and raw views exist; ownership conventions need consolidation |
| Collections | Vec, deque, hash map/set, ordered map/set, heap, bitset, fixed-capacity containers | Borrowed-owner alloc Vec and deque with explicit errors, linear maps/sets, alloc hash maps, ordered tree maps and min/max heaps execute; legacy migration and ordered sets remain |
| I/O | Reader/writer contracts, buffers, exact/all operations, cursors, stdin/stdout/stderr, errors | Shared traits, slice cursors, owned byte sinks, native descriptor adapters and owned files execute; buffered adapters remain |
| Files and paths | File handles, metadata, directories, walking, lexical paths, filesystem operations | Owned files, borrowed Unix byte paths, components, names, prefixes, owned buffers, explicit lexical normalization and checked directory/file mutations execute; metadata, directory enumeration, walking and further host operations remain |
| Processes and environment | Arguments, environment, working directory, subprocesses, pipes, exit status | Owned raw-byte argument snapshots and argument/environment helpers execute; subprocess management remains |
| Time and randomness | Duration, instant, system time, deadlines, deterministic generators, OS entropy | Typed nanosecond arithmetic, native clocks, generic deadline waits, deterministic generators, sampling/shuffle and explicit OS entropy errors execute; legacy consolidation, additional clocks and distributions remain |
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

The [compiled byte-glob module](extended-glob.md) and its streaming path-filter
application execute on x86_64 Linux, including recursive components, explicit
work limits, raw byte paths and allocation/I/O failure cases. Filesystem walking
still needs directory-enumeration and metadata host bindings; glob matching
does not depend on them.

[Checked filesystem mutations](stdlib-filesystem.md) provide allocation-free
creation/removal of one directory, file unlinking and renaming over existing
host bindings. These operations retain Linux errors and do not recursively
traverse paths.

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
- Paths: [`core::path` and `alloc::path`](stdlib-paths.md) separate borrowed Unix
  paths and owned buffers from host filesystem services. Component cursors,
  names/extensions, ancestors, prefixes, comparison/hash, joins, atomic edits
  and explicit lexical normalization execute. Tests cover 633 reference pairs,
  4,014 modeled edits, aliased inputs, allocation/write failures, large batches
  and a raw-byte path-joining program. Existing mixed-separator/Windows byte
  rules moved to `core::path_rules` with callers. Direct malformed View-record
  construction has a compiler reproduction and an executable control. Host
  metadata and directory enumeration still block the directory-report application.
- Time: [`core::time` and `std::clock`](stdlib-time.md) execute normalized
  durations, full-width signed Unix timestamps, monotonic instants, deadlines
  and generic waits with injected or native clocks. Five test groups cover 400
  wide-reference arithmetic cases, simulated interrupts/reversals/long waits,
  native timespec/status fault injection, collection integration, large batches
  and a scheduled JSON-record program. Relative waits preserve the original
  deadline, round up to milliseconds and split requests at the native i32 limit.
  A generic Deadline-factory composition has a reduced compiler reproduction
  and two successful controls; shipped APIs retain their generic interface.
  Other clocks, cancellation, calendar support and legacy migration remain.
- Randomness: [`core::random` and `std::entropy`](stdlib-randomness.md) execute
  xoshiro256++ generation, seed/state restoration, jumps, unbiased integer
  sampling, fixed-grid floats, byte filling, generic choice/shuffle and checked
  host entropy. Six focused groups compare author-derived vectors, modeled
  sequences, generic payloads, large batches, injected host/allocation failures
  and a binary-safe line-shuffling program. Generation and sampling allocate
  nothing; shuffle uses the caller's storage. Native timing for 1,048,576 raw
  draws is about 46 ms, including a checksum. A nested allocation factory needs
  an explicit type, with failing reproduction and two executable controls.
  Additional distributions and legacy randomness consolidation remain; this
  milestone does not complete the time/randomness family.
- Owned vector: [`alloc::vec`](stdlib-vec.md) provides explicit allocation and
  bounds errors, removed-value transfer, atomic self-extension, shallow clone,
  resizing, sorting and counted views. Four execution groups include 6,000
  modeled edits, generic payloads, zero-sized entries, allocation failures and
  checked-index panics. String, streams, CSV/JSON and three reporting/text
  programs use it. The old vector remains for the verified compiler, legacy
  consumers and the heap migration's separate compiler dependency.
- Owned deque: [`alloc::deque`](stdlib-deque.md) replaces the old std module and
  its unchanged-owner failure convention. It executes both-end edits, rotations,
  borrowed views/cursors, alias-safe extension, split and clone. A 6,000-command
  model, generic payloads, allocation denial and ten migrated programs pass on
  x86_64 Linux. Large FIFO workloads perform 262,144 pop/push pairs at 4,096 and
  65,536 entries with one allocation each and no further allocation attempts.
- Ordered map: [`alloc::tree_map`](stdlib-tree-map.md) executes generic lookup,
  replacement/removal, bounds, ranges, both-ended cursors, clone and linear
  construction from sorted entries. Eight test groups cover a 6,000-command
  reference model, allocation failures, generic payloads, 32,768-key adversarial
  insertion orders and a sorted word-count program. Building from 65,536 sorted
  entries uses 65,535 key comparisons and about 32 ms whole-program CPU time,
  versus 1,966,082 comparisons and 312 ms for repeated insertion. The old
  insertion-ordered linear map remains a separate migration; ordered sets
  remain to be implemented.
- CLI and host arguments: [`ext::cli` and `std::args`](extended-cli.md) execute
  borrowed option parsing and owned raw-byte argument snapshots. Eight test
  groups cover schema errors, 96 generated command lines, allocation failures,
  32,768-argument lists and a streaming file-checksum application with injected
  I/O errors. Parsing makes no allocations after capture; two snapshot
  allocations suffice at both 4,096 and 32,768 arguments. Higher-level CLI help,
  subcommands and logging remain.
- Configuration: [`ext::config`](extended-config.md) executes strict JSON object
  sources, bounded file loading, typed borrowed queries and explicit shallow
  overlays with source indices. The checksum application combines configuration
  files and CLI overrides. Eight groups cover generated layers, numeric limits,
  every observed allocation failure and host errors. JSON now also exposes
  borrowed text/key queries and exact i64/u64 conversion of decimal/exponent
  forms. Environment adapters, reusable schemas and TOML sources remain.
- Formatting and logging: [`core::fmt`](stdlib-formatting.md) composes integers
  in bases 2–36, Text, scalars, booleans and custom Display implementations into
  caller-backed buffers with measurement and sticky append errors.
  [`ext::log`](extended-log.md) filters and prepares complete typed JSON records
  before any output. The checksum application combines both with configuration
  and CLI settings. Seven groups cover 746 integer reference cases, 67 quoted
  text round trips, record bounds, every observed application allocation/I/O
  failure and allocation-free batches of 8,192 records. Four existing checksum
  groups still pass. A combined generic log-and-write facade exposes a runtime
  compiler defect; it is outside production imports with a reproduction and
  controls. Preparing records and then calling write_all executes.
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
  dependency is resolved. Complete the remaining Vec consumer migrations and
  consolidate legacy maps/sets and specialized collections under alloc with
  explicit fallible APIs; ordered sets remain.
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
