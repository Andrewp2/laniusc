# Native linking, foreign calls and threads

The [checked native C profile](library-native-c.md) now executes on Linux
x86_64/glibc. It provides scalar/pointer calls, ordinary ELF linking through
the system C driver and libc startup. [OpenSSL digest contexts](extended-openssl-digest.md)
and the [stdin hashing program](extended-openssl-hash.md) execute through that
boundary with dynamic `libcrypto.so.3`. This guide records the remaining
integration and thread contracts. The earlier source audit was based on
compiler `678bf559`; its blanket native-FFI dependency is superseded by the
selected working profile.

[Linux syscalls](stdlib-linux.md), [sockets](stdlib-sockets.md),
[polling](stdlib-poll.md) and [subprocesses](stdlib-command.md) retain their
documented contracts. The full library goal remains open.

## System lookup and child-group authority

The [system hostname/service resolver](stdlib-resolve.md) uses the existing
scalar/pointer C profile to call libc `getaddrinfo`/`freeaddrinfo`; it adds no
compiler service or aggregate C ABI. Its Linux x86_64/glibc contract fixes and
checks the packed `addrinfo` and IPv4/IPv6 sockaddr layouts. Explicit hints
select ASCII host/service input, family, TCP/UDP and supported flags. Native
order and duplicates become independent owned `SocketAddr` values, with
all-or-nothing result caps and strict native-shape admission. Only successful
lookup transfers a list owner; cleanup receives the original head once.
`EAI_SYSTEM` preserves errno captured immediately before cleanup.

All four [resolver verification groups](stdlib-resolve-testing.md) execute,
including independent libc comparisons and every reached wrapper allocation
failure. The [resolve-host program](stdlib-resolve-host.md) composes the value
API with bounded staged output and passes five groups, including its seven
reached allocation failures. Separate receipts and corrected harness retries
are retained in the guides; no combined passing suite invocation is claimed.
Neither a byte/result cap nor a socket deadline bounds
synchronous libc/NSS allocation, internal work or elapsed lookup time.
Asynchronous resolution, callbacks, NSS policy isolation and portable layout
profiles require separate contracts and evidence.

[Explicit child process groups](stdlib-command-groups.md) use the existing
Linux syscall boundary, independently of libc resolution. Group creation and
confirmation are separate from startup certainty. Only the original confirmed
group with an owned, unreaped leader grants negative-PGID signal authority.
Non-reaping observation retains that leader: capture's terminal `status` can
exist while `reaped=false`, so descendant-held pipes can still be drained or
explicitly cancelled. Final reaping or observed ECHILD revokes authority.

The [run-group supervisor](stdlib-run-group.md) applies TERM/grace/KILL and
bounded direct-child reap attempts, reporting incomplete cleanup. Five focused
API groups and five supervisor groups (53 application cases) pass through
separate receipts. The single-threaded,
one-active-owner, no-outside-reaper preconditions still apply. Descendants can
leave the group/session or change permissions; this is not process-tree
containment, terminal job control or a guarantee that a kernel-stuck process
becomes reapable by a timestamp.

## Native cryptography and remaining security work

OpenSSL 3 EVP supplies executable SHA-256, SHA-512, SHA3-256 and SHA3-512.
The Lanius wrapper owns contexts, adapts byte layout and reports errors; all
cryptographic operations run in the established native library.
[Client TLS with peer verification](extended-openssl-tls.md) also executes through OpenSSL 3
`libssl`/`libcrypto`: 34 cases across four groups cover explicit CA trust,
DNS/IP identity, binary transfers, closure/truncation and stable WANT retries.
The caller supplies a connected nonblocking socket, readiness/deadline policy,
manual owner cleanup and process SIGPIPE policy. The TLS guide records the
separate passing receipts and corrected legacy test-peer fixture.
[Server TLS](extended-openssl-tls-server.md) now passes six native groups and
53 cases, including certificate/key validation, encrypted passphrases without
prompts, context retention, stable retries and native/allocation cleanup.
Its `Unauthenticated` policy leaves client authentication to the application.
[Required-client mutual TLS](extended-openssl-mutual-tls.md) now passes six
groups and 107 cases, using OpenSSL for client credentials, chain/purpose/time
checks and required peer presence. Required servers disable resumption for
fresh authentication; verified chains do not grant application authorization.
The existing client trust/identity and ordinary server regression gates pass.
Standalone encryption/signature APIs and certificate trust APIs outside TLS
remain work. The [TLS stream/HTTPS application](extended-https-fetch.md)
executes 62 cases across four groups on Linux x86_64, with a numeric endpoint,
explicit trust/identity, deadline/resource limits and manual owner cleanup.

Native `f32`/`f64` C calls now execute with independent SSE and integer/pointer
register banks and up to 32 total parameters. Exact IEEE transport, stack
alignment, imported generic replay and live SSE clobbers pass the focused
gate recorded in the [native C guide](library-native-c.md). An owned
[SQLite adapter](extended-sqlite.md) and
[persistent binary key/value program](extended-sqlite-kv.md) now execute through
system SQLite on the selected Linux x86_64/glibc profile. Their gates cover
typed values, transactions, persistence, locks, native failure cleanup and
[staging allocation failures](extended-sqlite-allocation.md). The module guide
records exact receipts and the bounded bulk workload's time/allocation sample.

TCP/UDP, polling, subprocesses and bounded OS entropy retain their documented
native contracts. Raw [DER](extended-der.md) and [X.509](extended-x509.md)
retain schema parsing and inspection roles. None supplies signature
verification, certificate trust or TLS peer authentication.

A native library adapter still needs:

1. Source declarations that match the actual C headers. The checker validates
   the supported Lanius signature shape; it cannot inspect a C library's types
   or establish pointer validity.
2. Explicit dependencies and native linker inputs within the
   [selected profile](library-native-c.md). Native entry/package builds spool
   original/replay payloads and execute above the resident aggregate threshold;
   each source file must still fit its frontend unit. Source snapshots and
   global metadata remain resident, and explicit descriptor CLI modes are not
   supported by this native path.
3. An owner contract for native contexts, allocations and borrowed buffers.
4. Correct library-specific initialization, error mapping and configuration.
   TLS also needs certificate trust/identity policy and socket deadlines.

The digest and client TLS gates exercise their documented EVP and SSL
contracts. They do not establish a different adapter's security policy.
Runtime loading with `dlopen`/`dlsym`, callbacks and foreign thread entry remain separate profiles.

## Existing boundaries

| Boundary | Current state |
| --- | --- |
| Direct Lanius calls | Monomorphic/imported calls execute; generic composition has separate [routing dependencies](library-dependencies.md). |
| Callable values | The grammar has no function type or address-of expression. Checked calls retain a declaration target; lowering has direct calls and host/intrinsic calls, with no checked indirect-call operation. |
| Native linking | The opt-in C profile packages generated sections as ordinary ELF ET_REL objects and invokes `cc -no-pie`, with normal CRT/libc startup and native object/library inputs. The default raw profile retains its existing linker. |
| Extern declarations | Checked `extern "C"` integer/pointer/f32/f64/void declarations execute through native linking, with independent SSE/GPR banks and up to 32 total parameters. Unknown ABIs and unsupported C signatures fail; unrelated runtime-service declarations still need a bound service. |
| Scaling and artifacts | Native entry/package builds spool original/replay payloads and stream ELF export; a two-file 6 MiB pack executes above the 5 MiB aggregate threshold. Source snapshots and global metadata still grow. Explicit descriptor CLI modes remain unsupported. Semantic interface v17 and x86 object v4 are unchanged. |
| Atomics | No source atomic or memory-order contract is established. Conservative call effects alone do not establish atomicity or a happens-before relation. |

The source boundaries are [grammar/lanius.bnf](../grammar/lanius.bnf),
[native objects](../crates/laniusc-compiler/src/codegen/x86/object.rs),
[lowering calls](../crates/laniusc-compiler/src/codegen/lowering_ir.rs),
[native argument layout](../shaders/codegen/lir/x86/common.slang) and
[call effects](../shaders/codegen/optimization_ir.slang).
The [declaration contract tests](../tests/native_c_contract.rs) pass four
groups and the [native C execution tests](../tests/native_c_execution.rs) pass
eight, including imported calls, generic replay, 32 mixed arguments and CRT
initialization. The [float C execution gate](../tests/native_c_float_execution.rs)
adds exact IEEE transport and independent SSE/GPR register/stack coverage.
The [native C guide](library-native-c.md) records the focused
receipts and remaining restrictions.

Ordinary Lanius calls retain their own convention: slices occupy three words,
aggregates have defined passing rules, and large returns use hidden storage.
The separate checked C call path implements the admitted System V scalar ABI;
it does not make a Lanius slice or record C-compatible.

## First thread profile

A small useful admission can use a compiler-checked monomorphic entry of shape
`(ptr) -> i32`, through an entry capability or checked static registry. General
closures and arbitrary function values need not precede that profile. The old
`std::thread::spawn(entry_id, arg)` has no entry registry or authority behind it.
A caller-selected integer cannot substitute for checked entry identity.

Required contracts are:

- A dedicated trampoline establishes a new aligned stack, preserves process
  context, enters the admitted function and publishes completion on return.
  The current syscall thunk must return on its original stack; it cannot be
  used for a clone call that resumes on a different stack.
- One join owner controls the stack, completion record and result. Failed spawn
  retains caller ownership. Successful spawn transfers it until completion and
  join permit reclamation. Define self-join, repeated join and copied aliases.
- Completion publication and observation need defined atomic ordering. Entry
  traps, allocation failure and unexpected worker termination must not leave
  join waiting forever. Initially exclude detach and asynchronous cancellation.
- Whole-process termination and worker completion need separate paths. The
  raw-entry wrapper, process exit and allocation-failure runtime use Linux
  syscall 60, which exits the calling thread in a multithreaded process. The
  wrapper also retains the original argument stack in R15. A thread runtime
  must define and preserve those process-context and termination contracts.

The relevant runtime code is [entry emission](../shaders/codegen/lir/x86/emit.slang)
and [native runtime bindings](../shaders/codegen/lir/x86/runtime_abi.slang).

## Atomics, allocation and thread local storage

A first atomic profile can be aligned 32/64-bit words with sequentially
consistent load, store, exchange, compare-exchange and fetch-add. Opaque native
bindings may reuse existing host-call representations. New atomic IR rows are
not an established prerequisite; indivisibility, ordering, aliasing and optimizer
effects still require a coordinated compiler contract and meaningful tests.

The existing allocator uses independent mmap/mremap/munmap mappings. No shared
userspace freelist is evident, so a new global allocator lock is not an
established prerequisite. Cross-thread ownership transfer, exclusion during
reallocation, and exactly-once destruction remain required. Current shallow
owner conventions do not create automatic Send/Sync or lifetime enforcement.

A Lanius/raw-syscall thread profile can explicitly omit thread local storage.
The native C profile supplies libc startup and thread local storage for its
initial thread. Libc-backed worker threads and foreign thread entry still need
initialization, attachment and teardown contracts. Their absence does not
prevent the initial-thread native C profile from executing.

## Foreign libraries

Separate three admissions:

1. **Direct foreign calls:** implemented for the selected scalar/pointer profile,
   including symbols resolved by the system linker from shared libraries.
   Actual C signature agreement, buffer validity and ownership remain caller
   contracts. C aggregate arguments and results are unsupported.
2. **Runtime dynamic calls:** `dlopen`/`dlsym`, library-handle lifetime and checked
   indirect signatures remain unimplemented. Linking a shared library at build
   time does not require this application-level loading interface.
3. **Callbacks:** addressable exported entries, ABI trampolines, context lifetime,
   reentrancy and foreign-thread attachment remain unimplemented.

OpenSSL digests, verified client/server TLS including mutual TLS, and SQLite supply native bindings with
execution evidence. The SQLite adapter and its application execute database,
statement, buffer and failure contracts documented in their guides, including
real files, transactions and native lock recovery. Client TLS verifies peer
trust and identity within its documented profile; required servers verify fresh
client chains without assigning application authorization. Standalone
encryption/signature APIs and broader certificate policy remain work.
The libc resolver has separate layout, blocking and ownership limits above.
No JSON bridge, subprocess serialization adapter or
declaration-only API is counted as native integration. Production sensitive
operations use established native libraries, with no custom Lanius or
Rust/Python cryptographic implementation.

Entry authority and concurrent memory semantics need compiler coordination.
Source ownership policies, synchronization algorithms and higher-level library
APIs can remain Lanius after the required boundaries execute. The
[full library roadmap](library-roadmap.md) remains open.
