# The Lanius Programming Language

Lanius is a systems programming language that compiles on the GPU. That is, it compiles on the GPU and targets the CPU.

## Lanius Values

### 1) Iteration speed
Lanius is designed around GPU-resident compilation for fast iteration. The
current compiler is still early alpha; published benchmark claims need checked
local evidence before they should be treated as production numbers.

### 2) Embeddadbility
Lanius is intended to be embeddable, including future web/Wasm-style hosts, but
the current production backend work is focused on native x86_64.

### 3) Honesty
Lanius is explicit, but more than that Lanius is honest. Lanius code does what it says it does. There is no operator overloading, all usages of typeclasses are explicit. Nothing is "auto-wired" or otherwise transforms the control flow graph in a way that you could not expect.

## Stability

Lanius is in an extremely early alpha. I would not recommend using it for any purpose.

`laniusc --version` outputs the compiler version.
`laniusc doctor` will output a JSON report whether laniusc can run or not.
There are only two targets, `x86_64` and `wasm`. `x86_64` is the default.
Those correspond to `x86_64-unknown-linux-gnu` and `wasm32-unknown-unknown`.

You can control the diagnostics output using `--diagnostic-format=<json|lsp-json>`
`laniusc lsp serve --stdio` starts an LSP server (work in progress).
`laniusc fmt [--check] <file> [<file> ...]` runs a formatter on the given files, and edits them. `--check` only checks without editing the file.
`laniusc check` runs frontend checks like lexing, parsing, and typechecking, but it doesn't validate whether the backend accepts that code yet.

## Standard library

The [execution audit and portable foundation](docs/stdlib-foundation.md) lists
the stdlib APIs verified on x86_64, their edge behavior, and the remaining
compiler and runtime dependencies.

The [standard and extended library roadmap](docs/library-roadmap.md) tracks the
full scope and delivery requirements. New APIs follow the
[library conventions](docs/library-api-conventions.md); the first
[owned UTF-8 String](docs/stdlib-string.md) has executable native examples and
allocation-failure tests.
[Borrowed UTF-8 text](docs/stdlib-text.md) provides subviews, splitting, scalar
iteration and hashing without copying.
The [byte stream APIs](docs/stdlib-streams.md) provide shared reader/writer
contracts, owned byte buffers and native descriptor adapters.
The [generic hash map](docs/stdlib-hash-collections.md) provides hashed lookup,
explicit allocation errors and returned displaced keys/values.
The [shared iterator protocol](docs/stdlib-iterators.md) connects ranges, views,
collections and text with borrowed adapters. A checked
[range dot-product program](docs/stdlib-range-dot.md) composes zip, take, map
and enumeration, including arithmetic and output failures.
[Canonical slice cursors](docs/stdlib-cursor-integration.md),
[text splits](docs/stdlib-text-split-iterators.md) and
[heap iteration](docs/stdlib-heap-iterators.md) use that same protocol.
[Selection, searches and folds](docs/stdlib-iterator-selection.md) add lazy
filtering and typed short circuits. The [column-sum program](docs/stdlib-column-sum.md)
combines text splitting, filtering, Result items and checked reduction.
[Fallible collection](docs/stdlib-iterator-transfer.md) transfers items into
vectors and deques with explicit progress and rejected-item recovery. The
[word sorter](docs/stdlib-sort-words.md) collects borrowed text before sorting.
[Map, set and heap sinks](docs/stdlib-iterator-collection-sinks.md) preserve
rejected items and stored representatives. The
[identifier index](docs/stdlib-index-words.md) rejects duplicates and prints
ordered identifiers with their original positions.
[Owning Vec and Deque cursors](docs/stdlib-owning-iterators.md) transfer items,
recover unconsumed storage and provide explicit nested cleanup. The
[streaming word deduplicator](docs/stdlib-unique-words.md) moves independent
Strings into an ordered set while reusing its batch allocation.
[Runtime formatting to byte writers](docs/stdlib-format-write.md) validates
before publication and uses bounded scratch with explicit partial progress.
The [CSV report program](docs/stdlib-format-report.md) composes it with numeric
parsing and buffered output.

[Checked native C calls](docs/library-native-c.md) execute on Linux x86_64/glibc
through ordinary ELF objects, the system C linker and libc startup.
[OpenSSL digest contexts](docs/extended-openssl-digest.md) provide streaming
SHA-256, SHA-512, SHA3-256 and SHA3-512 through `libcrypto`; the
[hashing program](docs/extended-openssl-hash.md) hashes bounded binary stdin.
All cryptographic operations use the native library. TLS, encryption,
signatures, certificate trust and SQLite wrappers remain unimplemented; the
[remaining native prerequisites](docs/library-native-integration-prerequisites.md)
record those boundaries. TCP/UDP sockets and
[bounded OS entropy](docs/stdlib-entropy-bounded.md) are also available.
[DER](docs/extended-der.md) and
[X.509 structure parsing](docs/extended-x509.md) provide data inspection; they
do not verify signatures, certificate trust or TLS peers.

Optional modules use the [`extended` source root](extended/README.md).
[`ext::csv`](docs/extended-csv.md) and [`ext::json`](docs/extended-json.md)
include executable normalizers, generated round trips and allocation-failure
coverage.

The [CSV report application](docs/csv-report.md) combines streams, UTF-8 text,
checked decimal parsing, generic collections, CSV and JSON to validate and
group records with executable failure coverage.

## Benchmarks

TODO

## Performance viewer

```bash
python3 tools/lanius_perf.py serve
```

## Future

Lanius is looking to add formally verified semantics, capabilities, algebraic effects, graded modal types, tree borrows, mixin modules, row/rank polymorphism, first class property testing, compilation to ARM and RISC-V, polyhedral compilation, and more in the future.
