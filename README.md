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
[SHA-224/256](docs/stdlib-sha256.md) and the
[SHA-512 family](docs/stdlib-sha512.md) provide allocation-free incremental
byte digests. The [stdin hashing program](docs/stdlib-hash-bytes.md) exercises
all six algorithms with explicit input and I/O limits.
[ChaCha20](docs/stdlib-chacha20.md), [Poly1305](docs/stdlib-poly1305.md),
[ChaCha20-Poly1305](docs/extended-chacha20-poly1305.md) and
[X25519](docs/extended-x25519.md) have focused native Linux execution evidence.
[AES-128/192/256](docs/core-aes.md) and
[AES-GCM](docs/extended-aes-gcm.md) also execute without allocation, with
independent block/AEAD models and authentication-before-output checks.
The [TLS record layer](docs/extended-tls-record.md) passes ordinary
consumers, 308 ChaCha commands and 220 AES-GCM commands after a
[host capacity repair](docs/tls-record-lowering-dependency.md).
[Ed25519 signatures](docs/extended-ed25519.md),
[borrowed DER](docs/extended-der.md),
[TLS handshake codecs](docs/extended-tls-handshake.md) and the
[key schedule/transcript](docs/extended-tls-schedule.md) also pass focused
native gates. General certificate trust remains work.
[X.509 structure parsing](docs/extended-x509.md) and
[incremental framing](docs/extended-tls-framing.md) add bounded certificate
inspection and record/handshake reassembly, including the full u24 body limit.
[Nonblocking OS entropy](docs/stdlib-entropy-bounded.md) provides shared attempt
budgets and explicit partial progress for connection initialization.
The [certificate inspector](docs/extended-certificate-info.md) passes 50 native
cases covering parsed metadata, report publication and resource/I/O failures.
[DNS/IP identity matching](docs/extended-service-identity.md) and
[ordered Ed25519 certificate paths](docs/extended-x509-path.md) enforce
explicit anchors, validity, supported constraints and shared resource budgets.
The [certificate verifier](docs/extended-verify-certificate.md) passes 84 native
cases. This offline profile rejects unsupported policies; general PKIX remains
work.
[Server-flight authentication](docs/extended-tls-authentication.md) now joins
that path decision to ordered CertificateVerify and Finished checks, with
110 protocol cases and 340 state observations. The
[connection engine](docs/extended-tls-connection.md) composes it with negotiation,
directional epochs and client-Finished acknowledgement, passing paired
handshakes, both retry forms, long certificate flights and 46 boundary cases.
The [TCP adapter](docs/extended-tls-tcp.md) passes 18 real OpenSSL exchanges,
37 fault/ownership cases, two 1 MiB pressure streams and six deadline/budget
resumption cases, including actual partial-send and retained-input witnesses.
The [exchange application](docs/extended-tls-exchange.md) passes 74 native cases
for duplex transfers, explicit trust, file/input limits, I/O and owner failures.
The [seal-bytes program](docs/extended-seal-bytes.md) passes 137 native cases,
including allocation/I/O failures and the full 1 MiB boundary. The
[pinned compiler comparison](docs/library-foundation-performance.md#authenticated-bytes-key-exchange-and-tls-records)
records the measured crypto and large-library workloads. These connections use
the explicit X25519/Ed25519/SHA-256 profile; mandatory P-256/RSA/ECDSA algorithms
and broader PKIX support remain part of the full TLS work.

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
