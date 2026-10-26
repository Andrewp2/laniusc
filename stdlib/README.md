# Standard library

The standard library is implemented in Lanius. Use `--stdlib-root stdlib` when
compiling a program from this checkout. The [extended library](../extended/README.md)
contains optional codecs, protocols, mathematics and application utilities.

## Layers

| Layer | Contents | Dependencies |
| --- | --- | --- |
| `core` | Values, arithmetic, counted views, text, algorithms and codecs | Language operations and explicit target contracts |
| `alloc` | Owned buffers, strings, collections and arenas | `core` and allocator bindings |
| `std` | Process arguments, environment, files, streams, clocks and entropy | `core`, `alloc` and available native host bindings |
| `test` | Nontrapping checks, explicit suites, seeded properties and benchmarks | The layers needed by each operation; native clock/I/O only when requested |

## Find an API

The [generated declaration index](../docs/api/README.md) lists signatures,
generic bounds, fields and source locations across all library modules.
[Its guide](../docs/library-api-reference.md) explains generation and the
remaining semantic documentation gaps. Use the contract guides below for
runtime behavior, failure rules and supported targets.

| Need | Main modules | Contracts and examples |
| --- | --- | --- |
| Optional values and failures | `core::option`, `core::result`, `core::pair` | [Option](../docs/stdlib-option.md), [Result](../docs/stdlib-result.md) |
| Equality, ordering and hashing | `core::cmp`, `core::ordering`, `core::hash`, `core::float_order` | [Lawful comparison and float keys](../docs/stdlib-comparison.md) |
| Integer arithmetic | `core::{i8,i16,i32,i64,u8,u16,u32,u64,isize,usize}`, bit/conversion helpers | [8/16/32-bit contracts](../docs/stdlib-narrow-integers.md), [64-bit and pointer-sized contracts](../docs/stdlib-native-integers.md), [consumer consolidation](../docs/stdlib-numeric-migration.md); each operation names its checked, wrapping or saturating policy |
| Boolean values and bit operations | `core::bool`, `core::bits` | [Truth functions, widths, rotations and extraction](../docs/stdlib-boolean-bits.md) |
| Floating values and conversion | `core::f32`, `core::f64`, `core::float_decimal` | [Exact precision formatting](../docs/stdlib-float-precision.md) |
| Elementary mathematics | `core::math` | [Full-range binary64 functions and accuracy evidence](../docs/stdlib-math.md) |
| Wire coding and checksums | `core::base64`, `core::hex`, `core::binary`, `core::endian`, `core::varint`, `core::varint_i32`, `core::crc32`, `core::adler32` | [Byte codecs, endian values, varint statuses and CRC contracts](../docs/stdlib-byte-codecs.md) |
| Borrowed data and algorithms | `core::slice`, `core::range`, array helpers | [Counted views](../docs/stdlib-slice-views.md), [slice algorithms](../docs/stdlib-slice.md), [range membership and ordered overlap](../docs/stdlib-ranges.md) |
| Shared iteration | `core::iter`, collection and Text cursors | [Fused slice/range cursors and borrowed adapters](../docs/stdlib-iterators.md), [collection, Text and bitset integration](../docs/stdlib-collection-iterators.md), [range-statistics application](../docs/stdlib-range-stats.md) |
| UTF-8 and Unicode | `core::text`, `core::char`, `core::utf8`, `core::utf16`, `core::transcode`, `core::unicode` | [UTF encoding, edits and transcoding](../docs/stdlib-utf-codecs.md), [Unicode properties](../docs/stdlib-unicode.md); normalization and full casing are optional extended modules |
| Owned strings | `alloc::string` | [String ownership, edits and failures](../docs/stdlib-string.md) |
| Explicit value cloning and memory release | `core::clone`, `alloc::clone`, `alloc::clone_vec`, `alloc::string` | [Fallible element cloning and partial-owner cleanup](../docs/stdlib-clone.md), [recursive Vec ownership and typed errors](../docs/stdlib-nested-clone.md) |
| Formatting | `core::fmt`, `core::format`, `alloc::format` | [Runtime format strings and owned results](../docs/stdlib-format-strings.md), [bounded scratch output to byte writers](../docs/stdlib-format-write.md) |
| Inline collections | `core::vec`, `core::set` | [Borrowed free APIs, capacities, equality and returned values](../docs/stdlib-fixed-capacity.md) |
| Owned collections | `alloc::vec`, `alloc::deque`, `alloc::hash_map`, `alloc::hash_set`, `alloc::tree_map`, `alloc::tree_set`, `alloc::binary_heap`, `alloc::bitset` | [Owned bitsets](../docs/stdlib-bitset-owned.md), [ordered maps](../docs/stdlib-tree-map.md), [generic sets, representatives and algebra](../docs/stdlib-owned-sets.md) |
| Memory | `core::mem`, `alloc::allocator`, `alloc::arena` | [Value copying, raw storage and view layouts](../docs/stdlib-memory.md), [arena layouts and ownership](../docs/stdlib-arena.md) |
| Streams and files | `core::io`, `alloc::io`, `alloc::buffered`, `std::stream`, `std::file`, `std::filesystem` | [Byte streams](../docs/stdlib-streams.md), [buffered adapters and binary copying](../docs/stdlib-buffered.md), [files](../docs/stdlib-files.md), [filesystem operations](../docs/stdlib-filesystem.md) |
| File options and directories | `std::file_ops`, `std::directory` | [Seek, metadata, sync and duplication](../docs/stdlib-file-operations.md), [checked file lengths](../docs/stdlib-file-resize.md), [raw names and bounded walks](../docs/stdlib-directory.md) |
| Bounded file replacement | `std::file_copy` | [Descriptor alias checks, quotas and error prefixes](../docs/stdlib-file-copy.md), [copy-file application](../docs/stdlib-copy-file.md) |
| Paths | `core::path`, `alloc::path` | [Unix byte paths](../docs/stdlib-paths.md) |
| Arguments and environment | `std::args`, `std::args_checked`, `std::env`, `std::env_checked`, `std::process` | [Raw startup bytes, owned snapshots, checked copies, cwd and immediate exit](../docs/stdlib-process-context.md) |
| Child processes | `std::command`, `std::command_capture` | [Raw argv/environment, redirects, startup certainty and reaping](../docs/stdlib-command.md), [bounded concurrent pipe capture](../docs/stdlib-command-capture.md); native Linux single-threaded profile |
| Time and randomness | `core::time`, `core::calendar`, `std::clock`, `core::random`, `std::entropy` | [Time](../docs/stdlib-time.md), [calendar](../docs/stdlib-calendar.md), [randomness](../docs/stdlib-randomness.md); optional [TZif time zones](../docs/extended-timezone.md) |
| Network values and sockets | `core::net`, `std::socket` | [Address values](../docs/stdlib-net.md), [owned TCP/UDP and deadlines](../docs/stdlib-sockets.md), [binary TCP exchange](../docs/stdlib-tcp-exchange.md) |
| Descriptor readiness | `std::poll` | [Reusable borrowed-FD sets, flags, atomic publication and observed deadlines](../docs/stdlib-poll.md) |
| Signal dispositions | `std::signal` | [Explicit native Default/Ignore policies](../docs/stdlib-signals.md); source callbacks and signal trampolines remain unavailable |
| Native operating-system boundary | `std::linux` | [Unsafe Linux x86-64 syscall contract](../docs/stdlib-linux.md); higher-level modules validate their own operations |
| Native C libraries | Checked `extern "C"` declarations; optional `ext::openssl_digest` | [Linux x86_64/glibc ABI and linking](../docs/library-native-c.md), [OpenSSL digest ownership](../docs/extended-openssl-digest.md), [binary stdin hashing](../docs/extended-openssl-hash.md) |
| Tests and benchmarks | `test::assert`, `test::check`, `test::suite`, `test::property`, `test::bench` | [Development workflow](../docs/stdlib-development.md), `tools/lanius-test` |

The older `std::vec` remains for the verified compiler's extraction contract and
one heap dependency. New programs should use `alloc::vec`. Silent-failure map,
set, byte-vector and UTF-8 owners have been removed with their repository
consumers [migrated to checked APIs](../docs/stdlib-legacy-collections.md).

The optional [OpenSSL digest module](../docs/extended-openssl-digest.md) executes
streaming SHA-256, SHA-512, SHA3-256 and SHA3-512 through checked native C calls.
CRC, Adler and FNV hashing serve checksums and ordinary data structures.
TLS, encryption, signatures, certificate trust and SQLite wrappers remain
unimplemented; the [native integration guide](../docs/library-native-integration-prerequisites.md)
records that work. Sensitive operations use established native libraries.
The [extended library](../extended/README.md) also contains data formats,
mathematics, cleartext network protocols and raw certificate inspection.

## Ownership and errors

Owners are shallow values. Keep one active owner and use its explicit cleanup
operation when finished. A copy of an owner aliases its allocation; it does not
clone it.
Views borrow live initialized storage, and their initial physical backing count
remains a caller precondition. These rules are documented conventions rather
than compiler-enforced lifetime safety.

Explicit `TryClone`/`Destroy` implementations let
[`alloc::clone::from_view`](../docs/stdlib-clone.md) build independent String or
user-record owners, with cleanup on recoverable failure. Its `destroy_vec`
releases those owned entries and the outer vector. Existing collection clones
still copy entries shallowly; ordinary `Vec.destroy()` releases only outer
storage. The explicit `alloc::clone_vec` implementations let these protocols
compose through nested Vec levels, preserving each typed error layer and
releasing completed destinations on failure. A source containing borrowed
aliases still needs its separate owners released once. These protocols introduce
no automatic moves or destruction.

[`Vec.take_iter` and `Deque.take_iter`](../docs/stdlib-owning-iterators.md)
explicitly transfer storage and remaining item cleanup authority to an owning
cursor, resetting the source for reuse. Rejected finish preserves the cursor;
remainder recovery returns its original allocation. Explicit cursor cleanup
helpers destroy only the items still owned by that cursor. Generic discarding
adapters do not destroy items they consume from an owning source.

Fallible operations return explicit `Result` errors. Ordinary absence uses
`Option`. Mutations state whether an error preserves the owner; streams can
already have transferred a prefix when I/O fails. Panicking conveniences state
their preconditions. See the [API conventions](../docs/library-api-conventions.md).

## Build and run

With the compiler already built, from the repository root:

```sh
export CARGO_TARGET_DIR="$PWD/target/stdlib-build"
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s "$CARGO_TARGET_DIR/debug/laniusc" \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/expr_calc.lani -o target/stdlib-work/expr-calc
printf '1+2*3\n-(5+6)\n' | target/stdlib-work/expr-calc
```

Expected output is `7` and `-11`, each on its own line. The
[application index](../sample_programs/library/README.md) links executable
programs, commands, resource limits and failure tests.

For a relocatable package containing only reachable sources, use the
[source distribution guide](../docs/library-distribution.md). The vendoring
tool uses the compiler's existing package resolver and retains source hashes
and license notices.

## Supported target and remaining work

Verified execution is x86_64 Linux output from GPU compilation. Compiling on the
GPU does not establish execution of user GPU kernels. Other targets have no
current execution claim.

`core::target` describes executable library families; `core::runtime` inventories
direct host bindings. For example, the library network capability is true for
`std::socket`, implemented over Linux service 14, while the old direct network
service 5 remains unavailable. Neither inventory claims all host services work.
The [operation-level host inventory](../docs/library-host-operation-support.md)
records the supported subsets and their implementation/test evidence.
The [native C profile](../docs/library-native-c.md) supports checked scalar and
pointer calls, libc startup and OpenSSL digests. It currently requires source
packs that fit the resident compiler path; file-backed native ELF linking,
callbacks and foreign thread entry remain dependencies. Threads, further
security-library wrappers and database integration remain work. The older `std::net`
declarations remain unbound; executable numeric socket ownership is in
`std::socket`. [The remaining API audit](../docs/library-remaining-api-audit.md)
distinguishes unavailable services and legacy interfaces. Generic
composition limits have [reproductions and controls](../docs/library-dependencies.md).
The [full library roadmap](../docs/library-roadmap.md) remains open, including
binary SDK installation, complete API references and the final completion audit.
