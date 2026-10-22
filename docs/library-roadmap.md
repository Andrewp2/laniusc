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
| Borrowed data | Arrays, slices, ranges, searching, sorting, partitioning, copying | Generic operations exist; length-bearing APIs and uniform bounds errors remain |
| Iteration | Explicit iterator protocol, ranges, slices, collections, text, adapters, consumers | Shared protocol and collection integration remain |
| Text | Borrowed UTF-8, owned String, Unicode scalars, byte boundaries, search, split, trim, join, parse, formatting | Packed owned String, byte codecs and scalar operations execute; split/join, formatting and borrowed text integration remain |
| Memory | Allocation contracts, layout, owned buffers, arenas, explicit destruction and clone behavior | Allocator bindings and raw views exist; ownership conventions need consolidation |
| Collections | Vec, deque, hash map/set, ordered map/set, heap, bitset, fixed-capacity containers | Generic vectors/deques and linear maps/sets exist; other structures remain |
| I/O | Reader/writer contracts, buffers, exact/all operations, cursors, stdin/stdout/stderr, errors | Shared traits, slice cursors, owned byte sinks and native descriptor adapters execute; buffered adapters and owned files remain |
| Files and paths | File handles, metadata, directories, walking, lexical paths, filesystem operations | Basic bindings exist; complete path and directory interfaces remain |
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
  on x86_64 Linux, including generated tables and allocation fault injection.
  See [extended-csv.md](extended-csv.md). Streaming and row construction remain.
- Shared I/O: portable Read/Write traits, exact/all/copy operations, slice
  cursors, owned byte buffers and native descriptor adapters have execution
  coverage. CSV uses these streams. See [stdlib-streams.md](stdlib-streams.md).
- Next integration milestone: JSON and a CSV-to-JSON application using validation
  and grouping, followed by remaining text/collection and I/O operations.
- The older [execution audit](stdlib-foundation.md) remains historical evidence;
  its top-level checkpoints do not establish this branch's current behavior.
