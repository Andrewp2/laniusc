# Native C calls and linking

Lanius executes checked `extern "C"` calls on Linux x86_64 with glibc. The GPU
compiler emits the call instructions and C-facing entry bridge. The native
profile packages generated sections as ordinary ELF ET_REL objects and invokes
the system C compiler driver with `-no-pie`. Its normal CRT and libc startup
establish process initialization and thread local storage before Lanius enters
its application code.

[OpenSSL EVP digest contexts](extended-openssl-digest.md) and the
[binary stdin hashing program](extended-openssl-hash.md) exercise this path with
dynamic `libcrypto.so.3`. Every cryptographic operation runs in OpenSSL. The
production binding has no Rust/Python cryptographic implementation, serialization
bridge or per-library compiler service.

## Checked declarations

Declare the native symbol with its actual name and a supported monomorphic
signature:

```lanius
pub extern "C" fn EVP_DigestUpdate(context: ptr, bytes: ptr, count: usize) -> i32;
pub extern "C" fn EVP_MD_CTX_free(context: ptr);
```

The first declaration corresponds to C
`int EVP_DigestUpdate(EVP_MD_CTX *, const void *, size_t)`; the second returns
void. Public declarations can be imported through ordinary modules. Private
declarations retain their native binding identity without becoming public
imports. A native function name that also names a runtime operation remains a
C call. Conflicting checked signatures for the same native symbol fail linking.

| Lanius type | Admitted Linux x86_64/glibc representation |
| --- | --- |
| `i32` / `u32` | Signed / unsigned 32-bit integer |
| `i64` / `u64` | Signed / unsigned 64-bit integer |
| `isize` / `usize` | Signed / unsigned 64-bit pointer-sized integer |
| `ptr` | 64-bit native pointer, including null |
| `f32` | IEEE binary32, matching C `float` |
| `f64` | IEEE binary64, matching C `double` |
| Omitted result | C void; not a parameter type |

Declarations accept up to 32 parameters. The backend supplies System V register
and stack arguments, stack alignment, preserved registers, pointer bits,
integer argument/return normalization and floating-point scalar transport.
The contract tests reject unsupported
signatures even when the declaration is never called.

The checker validates Lanius signature shapes. It does not read C headers or
prove that a declaration matches a linked library. Callers must select the
actual C types and uphold pointer validity, alignment, buffer capacity,
lifetimes, aliasing, error and ownership rules. A `ptr` carries no element type,
length, NUL termination or cleanup authority. Raw declarations are an unsafe
boundary even though this language has no `unsafe` block.

Lanius slices, strings, arrays and records do not acquire C layouts through
this feature. Library adapters must stage bytes or use a documented raw-memory
layout. The EVP wrapper demonstrates explicit NUL-terminated names, packed
input/output staging, immediate error capture and native context cleanup.

## C floating-point ABI

Checked C calls now execute with `f32` as C `float` and `f64` as C `double`.
The native gate covers exact IEEE argument/result bits, signed zero, NaN
payloads, mixed 32-parameter calls, imported generic replay and values that
remain live across calls which clobber SSE registers.

The floating-point ABI uses independent banks of six integer/pointer
registers and eight SSE registers. Overflow arguments share 8-byte stack slots
in their original parameter order. Float results use XMM0. The limit remains
32 total parameters, including mixed integer, pointer, `f32` and `f64` values.
Argument/result transport preserves scalar bits; a called C operation has its
own floating-point behavior. C variadics, callbacks and aggregate layouts remain
outside the profile. Existing scalar IDs and the selected System V ABI tag
represent this extension, so it requires no artifact version change.

## SQLite databases and application

An owned [SQLite adapter](extended-sqlite.md) and a
[persistent binary key/value program](extended-sqlite-kv.md) execute through
system `libsqlite3` on the selected Linux x86_64/glibc profile. The adapter uses
ordinary checked declarations such as:

```lanius
extern "C" fn sqlite3_bind_double(statement: ptr, index: i32, value: f64) -> i32;
extern "C" fn sqlite3_column_double(statement: ptr, column: i32) -> f64;
```

The library calls native `libsqlite3` directly for database and prepared
statement operations. Lanius owns handle lifetimes, byte staging, limits and
error handling. The application uses bound BLOB keys and values with explicit
input/output limits. The gates cover 558 typed-value cases, a 640-command
transaction model, actual file persistence and locking, 21 native failure modes,
four [staging allocation failures](extended-sqlite-allocation.md), and 99
application oracle cases plus scripted stream checks. The module guide records
the 32,768-insert/indexed-read workload and its measured native time and SQLite
allocation high-water mark. These results apply to the audited SQLite 3.45.1
host; the guides define the ownership and SQL/resource limits.

## Build and link

Build from the repository root with an absolute target directory, so the
compiler and generated shader metadata come from the intended checkout:

```sh
export CARGO_TARGET_DIR="$PWD/target/stdlib-build"
timeout --kill-after=2s 110s env \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 \
  cargo build --locked --bin laniusc

timeout --kill-after=2s 100s "$CARGO_TARGET_DIR/debug/laniusc" \
  --native-link --native-library crypto \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/openssl_hash.lani -o /tmp/openssl-hash

printf 'abc' | timeout --kill-after=2s 10s /tmp/openssl-hash sha256
```

The digest is
`ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
OpenSSL 3 and the system C toolchain must be installed. Compiler construction
still runs on the GPU; the resulting program runs on the CPU.

| Option | Meaning |
| --- | --- |
| `--native-link` | Select the C-linked x86_64 executable profile. |
| `--native-library NAME` | Add a plain library name, such as `crypto`, as `-lNAME`. Repeat for more libraries. |
| `--native-object PATH` | Add an existing native object or shared-library file. Repeat for more inputs. |
| `--native-library-path DIR` | Add an existing link search directory with `-L`. Repeat for more directories. |
| `--native-linker PROGRAM` | Select one C compiler driver executable, by name or path; default `cc`. |

Each native input option also selects the native profile. Value options accept
separate arguments or `--option=value`. The CLI canonicalizes object and library
directory paths, and preserves input ordering within each list. The linker is
one executable, not a shell command with embedded flags. A link search directory
does not install a shared library or configure its runtime search path; the
system dynamic loader must still find every required dependency when the
program starts.

The profile supports entry files, `--stdlib-root`, `--source-root`, and the
existing package manifest/lock resolution path. It uses the same checked source
unit scheduling and imported generic replay as the ordinary compiler. A native
symbol must resolve from supplied objects/libraries or the system driver;
declaring it alone supplies no implementation.

## Artifacts and current limits

Semantic interface artifacts use version 17 and x86 object artifacts use
version 4. Rebuild older cached interfaces and objects. These versions preserve
foreign declaration identities and signature metadata through imports and
native linking; older artifacts are not an accepted compatibility path.

Native entry/package linking supports source packs above one resident unit.
The compiler privately spools each original object's opaque text/rodata before
retaining it, keeps the same whole-program admission receipts, and spools each
generic replay before publication. ELF export validates global metadata first,
then copies section payloads one object at a time. No host instruction decoding
or synthesis is involved. Source files must still fit their frontend unit
limits; these changes do not raise those limits.

The system driver receives a quoted response file capped at 64 MiB. Its timeout
defaults to 30 seconds and admits at most 120 seconds; diagnostics are capped at
64 KiB. `NativeLinkOptions::max_output_bytes` defaults to 256 MiB and accepts
1..=u32::MAX. Linked-output reads and copies check that cap and reject changed
lengths. `GpuCompiler::compile_path_manifest_with_native_link_to_file` writes
through a private, exclusively created sibling and atomically replaces the
destination after success; the bytes API remains bounded by the same cap.

This bounds retained machine-code payloads and final output, not total host or
system-linker memory. Exact source snapshots, interfaces and global metadata
remain resident and grow with the program. Explicit source-pack descriptor CLI
modes remain unsupported by native linking; ordinary raw x86/Wasm execution
retains its existing storage policy.

Callbacks, exported C callback trampolines, variadics,
narrow integer and Boolean C types, aggregate C layouts,
generic extern declarations and foreign thread entry are unsupported. Runtime
`dlopen`/`dlsym` interfaces are separate work. Wasm, other platforms and user GPU
execution have no support claim from these gates.

[OpenSSL client TLS with peer verification](extended-openssl-tls.md) now executes through
`libssl.so.3` and `libcrypto.so.3`, including peer trust/identity checks, stable
WANT retries and authenticated closure/truncation. Sessions manually borrow a
connected nonblocking descriptor; callers supply polling/deadlines and process
SIGPIPE policy. [Server TLS](extended-openssl-tls-server.md) now passes six
native groups and 53 cases through the same native libraries, with explicit
unauthenticated-client policy and shared session I/O. The mandatory client
trust/identity rejection gate also passes after introducing session roles.
Mutual TLS, standalone encryption/signature APIs and general certificate
trust APIs remain work. The
[native integration prerequisites](library-native-integration-prerequisites.md)
record ownership, policy, callback and concurrency requirements. The
[complete library roadmap](library-roadmap.md) remains open.

## Execution evidence

The native execution gates compile Lanius on the GPU and execute the generated
Linux x86_64/glibc programs. The semantic-interface gate checks CPU artifact
handling separately:

| Gate | Result | Receipt |
| --- | --- | --- |
| [`native_c_storage_execution`](../tests/native_c_storage_execution.rs) | 1 group passes in 3.86 s: two 3 MiB source files exceed the 5 MiB aggregate resident threshold, private C calls survive imported generic replay, direct file output executes, and output-limit rejection preserves the previous executable | `target/stdlib-work/native-storage-large-pack-execution.log` |
| Native ELF/linker CPU tests | 18 tests pass in 0.94 s: streamed opaque payloads, metadata/rejections, exact CRT bridge, actual response-file grammar, bounded diagnostics/output and driver cleanup | `target/stdlib-work/native-storage-exporter-unit.log` |
| Private object storage CPU tests | 3 tests pass in 0.00 s: payload/clone lifetime, truncation/layout rejection and entry eligibility | `target/stdlib-work/native-storage-file-object-unit.log` |
| Atomic output CPU tests | 2 tests pass in 0.00 s: symlink-collision rejection and existing-output preservation/cleanup | `target/stdlib-work/native-storage-atomic-output-unit.log` |
| Original facts and metadata CPU tests | Two new tests pass in 0.00 s, alongside an existing cache-charge test: spilling retains exact original facts and metadata mutation preserves frozen code | `target/stdlib-work/native-storage-facts-unit.log` |
| [`native_c_float_execution`](../tests/native_c_float_execution.rs) | Final regression: 1 group passes in 3.82 s, covering exact IEEE bits including NaN payloads, independent GPR6/SSE8 banks, mixed 32-parameter stack/alignment cases, imported generic replay and live SSE clobbers | `target/stdlib-work/native-c-float-final-regression.log` |
| [`native_c_contract`](../tests/native_c_contract.rs) | 4 groups pass in 9.77 s: nine unsupported signature categories, accepted f32/f64 metadata, visibility/identity/runtime-name collisions, and the 32-parameter limit | `target/stdlib-work/native-c-float-contract.log` |
| [`native_c_execution`](../tests/native_c_execution.rs) | 8 groups pass in 10.55 s: integer/pointer/void regression, register/stack arguments, startup, imported calls, generic replay, 31/32 mixed parameters, linked-ELF validation and rejection paths | `target/stdlib-work/native-c-float-integer-regression.log` |
| Native C semantic-interface unit tests | 2 CPU tests pass in 0.00 s after a 42.45 s test build: native binding identity/signature round-trip and forged/unsupported profile rejection | `target/stdlib-work/native-c-float-interface-unit.log` |
| [`extended_sqlite_execution`](../tests/extended_sqlite_execution.rs), ordinary cases | 4 groups pass in 14.92 s: typed values, model, file persistence/locking and bounded bulk workload | `target/stdlib-work/sqlite-library-execution-current.log` |
| Same driver, native failures | 1 group passes all 21 modes in 9.03 s | `target/stdlib-work/sqlite-native-fault-execution.log` |
| [`extended_sqlite_allocation_execution`](../tests/extended_sqlite_allocation_execution.rs) | 1 group passes in 8.60 s: baseline plus four staging allocation failures, retries and cleanup ledgers | `target/stdlib-work/sqlite-staging-allocation-execution.log` |
| [`extended_sqlite_program_execution`](../tests/extended_sqlite_program_execution.rs) | 5 groups pass in 17.54 s: 99 oracle cases plus scripted stream helpers | `target/stdlib-work/sqlite-program-execution-current.log` |
| [`extended_openssl_tls_execution`](../tests/extended_openssl_tls_execution.rs) | 34 cases pass across four groups; the [TLS guide](extended-openssl-tls.md#native-linking-and-verification-status) separates the verified matrix, rejection rerun and close/retry receipts, including the corrected peer fixture | `target/stdlib-work/openssl-tls-matrix-first.log`, `target/stdlib-work/openssl-tls-errors-retries.log`, `target/stdlib-work/openssl-tls-verification-current.log` |
| [`extended_https_fetch_execution`](../tests/extended_https_fetch_execution.rs) | 4 groups pass in 14.44 s: 4 buffered TLS stream cases, 14 verification/HTTP failures, 26 limit cases and 18 binary/framing matrix cases; [profile and ownership](extended-https-fetch.md) remain explicit | `target/stdlib-work/https-fetch-execution-current.log` |
| HTTPS after the two layout repairs | The 18-case binary/framing matrix passes again in 9.01 s | `target/stdlib-work/https-fetch-final-regression.log` |
| [`extended_openssl_tls_server_execution`](../tests/extended_openssl_tls_server_execution.rs) | Six groups pass 53 cases in 5.98 s: verified peers, credentials, binary transfers, closure, retries and native/allocation cleanup; explicit unauthenticated-client server policy | `target/stdlib-work/openssl-tls-server-native-current.log` |
| Mandatory client policy after server roles | Nine trust/identity/protocol rejections pass in 5.98 s | `target/stdlib-work/openssl-tls-client-policy-server-regression.log` |
| HTTPS client after shared context ownership | All four groups and 62 cases pass in 13.90 s | `target/stdlib-work/https-fetch-server-context-regression.log` |
| [`extended_https_server_execution`](../tests/extended_https_server_execution.rs) | All four groups pass 106 cases: 28 verified exchanges in 7.17 s and 78 limits/failures/stream cases in 10.87 s | `target/stdlib-work/https-server-matrix-vec-corrected.log`, `target/stdlib-work/https-server-limits-failures-stream.log` |
| [`extended_archive_index_execution`](../tests/extended_archive_index_execution.rs) | Seven groups pass: the 56-case ownership matrix in 8.27 s and six remaining groups in 17.16 s, including native/transaction errors, allocation failures and a measured 1,024-entry workload | `target/stdlib-work/archive-index-matrix.log`, `target/stdlib-work/archive-index-failures-workload.log` |
| [`extended_openssl_digest_execution`](../tests/extended_openssl_digest_execution.rs) | 4 groups pass in 8.11 s: 2,124 digest cases and 12 native failure modes | `target/stdlib-work/openssl-digest-execution-first.log` |
| [`extended_openssl_hash_execution`](../tests/extended_openssl_hash_execution.rs) | 3 groups pass in 10.11 s: real binary stdin, CLI bounds, short transfers and native failure cleanup | `target/stdlib-work/openssl-hash-execution-first.log` |

The combined host build for native object storage completed in 35.42 s; its
large-pack execution and focused CPU gates are recorded above. This does not
establish constant total memory or every library's scale behavior.
The earlier compiler build for the floating-point extension completed in 46.71 s.
Its new gates extend the C ABI evidence; SQLite uses native C double calls and
the retained OpenSSL gates verify dynamic `libcrypto.so.3` integration. Rust,
Python, their SQLite/OpenSSL reference clients and small native observers are
test infrastructure. Production database operations execute in SQLite and
production digest and TLS operations execute in OpenSSL.

The earlier integer/OpenSSL milestone passed nine native ELF/linker CPU tests,
two native interface tests and eleven CLI argument tests. Its rebuilt CLI
compiled `openssl-hash`, which
matched the OpenSSL CLI for all four algorithms on 1,285 binary input bytes;
`readelf` confirmed its `libcrypto.so.3` dependency. An ordinary raw-entry byte
stream program also passed its errno, bounds, partial-EOF and exact-output
checks after the ABI changes.

Normal return from language main returns through the C runtime. Existing
nonreturning runtime exit and trap paths terminate immediately; they do not
run libc exit callbacks or automatically destroy native context owners.

To rerun one focused gate from the repository root:

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test native_c_execution -- --nocapture --test-threads=1
```

The relevant implementation sources are the [C signature metadata](../crates/laniusc-compiler/src/compiler/semantic_interface.rs),
[native ELF packaging and system link](../crates/laniusc-compiler/src/codegen/x86/native.rs),
[native source-pack path](../crates/laniusc-compiler/src/compiler/gpu_compiler/native_codegen.rs)
and [CLI input handling](../crates/laniusc-compiler/src/cli/args/native_link.rs).
