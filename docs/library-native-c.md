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
| Omitted result | C void; not a parameter type |

Declarations accept up to 32 parameters. The backend supplies System V register
and stack arguments, stack alignment, preserved registers, pointer bits and
integer argument/return normalization. The contract tests reject unsupported
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

Native linking currently requires a source pack that fits the resident compiler
path. A pack requiring bounded file-backed compilation fails explicitly:
file-backed native ELF linking remains a compiler dependency. This profile
does not establish large-library scaling beyond that boundary.

Callbacks, exported C callback trampolines, variadics, floating-point C
arguments/results, narrow integer and Boolean C types, aggregate C layouts,
generic extern declarations and foreign thread entry are unsupported. Runtime
`dlopen`/`dlsym` interfaces are separate work. Wasm, other platforms and user GPU
execution have no support claim from these gates.

TLS, encryption, signatures, certificate trust and SQLite wrappers remain
unimplemented. The [native integration prerequisites](library-native-integration-prerequisites.md)
record their ownership, policy and concurrency requirements. The
[complete library roadmap](library-roadmap.md) remains open.

## Execution evidence

The retained focused receipts are from actual GPU compilation to Linux x86_64
programs and subsequent native execution:

| Gate | Result | Receipt |
| --- | --- | --- |
| [`native_c_contract`](../tests/native_c_contract.rs) | 3 groups pass in 9.63 s: invalid unused signatures, visibility/identity/runtime-name collisions, and the 32-parameter limit | `target/stdlib-work/native-c-contract-current-shaders.log` |
| [`native_c_execution`](../tests/native_c_execution.rs) | 8 groups pass in 9.99 s: scalar/pointer/void behavior, register/stack arguments, startup, imported calls, generic replay, 31/32 mixed parameters, linked-ELF validation and rejection paths | `target/stdlib-work/native-c-execution-all-first.log` |
| [`extended_openssl_digest_execution`](../tests/extended_openssl_digest_execution.rs) | 4 groups pass in 8.11 s: 2,124 digest cases and 12 native failure modes | `target/stdlib-work/openssl-digest-execution-first.log` |
| [`extended_openssl_hash_execution`](../tests/extended_openssl_hash_execution.rs) | 3 groups pass in 10.11 s: real binary stdin, CLI bounds, short transfers and native failure cleanup | `target/stdlib-work/openssl-hash-execution-first.log` |

The OpenSSL gates verify dynamic `libcrypto.so.3` integration. Rust, Python,
the OpenSSL CLI and small native observers are test infrastructure and reference
oracles. The production digest operations execute only in OpenSSL.

The CPU checks passed: nine native ELF/linker tests, two native interface tests,
and eleven CLI argument tests. The rebuilt CLI compiled `openssl-hash`, which
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
