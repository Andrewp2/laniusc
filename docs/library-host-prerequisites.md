# Host and generic composition prerequisites

## Current support

The explicit [native Linux syscall boundary](stdlib-linux.md), added in
`3fa72ac2`, now supports executable Lanius implementations of
[TCP/UDP sockets](stdlib-sockets.md), [extended file operations](stdlib-file-operations.md),
[directory enumeration and walking](stdlib-directory.md) and
[signal dispositions](stdlib-signals.md). Their guides record exact host layouts,
bounds, ownership, failure behavior and native tests. Direct source binding does
not establish composable-artifact runtime linking or execution on other targets.

`core::target` describes executable library capabilities; its network flag is
true for `std::socket`. `core::runtime` describes direct service-catalog bindings;
its old network family 5 remains unavailable. Working sockets depend on family
14, not on the unbound `std::net` declarations. The aggregate runtime-services
flag remains false.
The [operation-level inventory](library-host-operation-support.md) records
the bound subset, source wrappers and retained native test evidence for all
fourteen families, including executable traps beside unavailable panic hooks.

Thread creation still needs checked entry, a new-stack trampoline, atomic
memory ordering and ownership/join contracts. Thread local storage can be absent
from an initial Lanius/raw-syscall profile; libc integrations need their storage
initialization contract separately.
The [native integration proposal](library-native-integration-prerequisites.md)
records the existing code-entry, linker, allocator and process-context evidence.
The syscall thunk requires the
same returning stack and continuation; it cannot implement clone/vfork/new-stack
entry by itself. Cryptography and TLS require an established external library
through a checked native binding. The [native C profile](library-native-c.md)
and [OpenSSL digests](extended-openssl-digest.md) now execute. C `f32`/`f64` calls
also execute through independent SSE/GPR banks, with exact IEEE transport,
mixed 32-parameter stack/alignment and imported generic replay evidence.
The owned [SQLite adapter](extended-sqlite.md) and
[persistent binary key/value program](extended-sqlite-kv.md) execute through
system SQLite on Linux x86_64/glibc. Native typed-value, transaction, file/lock,
error and [staging allocation](extended-sqlite-allocation.md) gates pass; the
module guide records the exact receipts and bounded bulk-workload measurement.
[Client TLS with peer verification](extended-openssl-tls.md) and the
[TLS stream/HTTPS application](extended-https-fetch.md) execute through OpenSSL 3.
[Server TLS](extended-openssl-tls-server.md) also executes through OpenSSL with
an explicit unauthenticated-client policy. Mutual TLS and broader security
wrappers remain library work. Callbacks,
variadics, aggregate C layouts and foreign thread entry need separate compiler
contracts.
[Subprocess support](stdlib-command.md) now executes over same-stack
fork/exec/wait, with explicit startup uncertainty, owned pipes and a
single-threaded/no-outside-reaping contract. The command runner and 78-case
independent oracle exercise real child lifecycle and fault cleanup. This uses
service 14; the older process service 11 still supplies its original argument
and exit operations.
[Concurrent pipe capture](stdlib-command-capture.md) now composes these
operations with explicit byte/work/deadline limits and retained child ownership
on failure.

## Historical baseline

The audit below describes compiler and source-library HEAD `5174a14d`, before
the Linux boundary existed. Its operation contracts guided the current source
implementations; statements about missing socket/file bindings refer to that
baseline. Its thread and generic-composition prerequisites remain relevant.

### The native boundary at 5174a14d

Native x86_64 Linux calls use a closed service catalog:

- `crates/laniusc-compiler/src/type_checker/params.rs:512` defines the builtin
  spelling table and declaration tags. Its intrinsics cover assertions, printing,
  pointer/slice construction, and slice stride; it contains no generic syscall,
  inline assembly, function-pointer call, or general C FFI primitive.
- `shaders/type_checker/semantic/artifact/00_project.slang:173` maps extern
  declarations to known service slots. Merely writing another extern name does
  not add a binding.
- `crates/laniusc-compiler/src/codegen/lowering_ir.rs:59` enumerates
  `HostService`; `shaders/codegen/lowering_ir.slang:437` defines matching IDs.
- `shaders/codegen/lir/x86/runtime_abi.slang:54` maps those IDs to native thunk
  offsets. An unknown service has no offset.
- `shaders/codegen/lir/x86/count.slang:240` rejects an ordinary remaining extern
  call or unsupported host call. The same file, at line 191, restricts expanded
  extern arguments to six register slots.

Consequently, declaring `extern "lanius_std" fn syscall(...)` cannot implement
missing operations at that baseline. A source-root module also cannot supply machine code
for such a declaration. The unsupported directory fixture at
`tests/fixtures/stdlib_foundation/filesystem_operations_directory_dependency.lani`
records the existing native-call ABI rejection.

The bound operations already support sequential descriptor I/O, three fixed open
modes, close, four pathname mutations, process argument reads and exit, immutable
environment reads, clocks, secure random bytes, and allocation. Networking and
thread declarations remain explicitly unbound in `stdlib/std/net.lani:17` and
`stdlib/std/thread.lani:17`. `HAS_PROCESS` being true denotes the bound argument
and exit operations; it does not supply child-process creation.

`std::stream::from_handle` can borrow an inherited regular-file, socket, pipe, or
terminal descriptor for existing read/write operations. `std::file::from_owned_handle`
adopts an exclusively owned descriptor. These operations neither create nor
duplicate a descriptor. A connected socket supplied by a launcher can therefore
already carry source-library stream I/O, but socket creation and endpoint setup
cannot be inferred from that success.

### File operations that required bindings

The existing open thunks use fixed flags and mode:
`shaders/codegen/lir/x86/runtime_path_ops.s:36` through line 79 select read-only,
write/create/truncate, or write/create/append, requesting `0666` for creation.
There is no configurable descriptor-relative open. The checked source wrapper
is `stdlib/std/file.lani:37`; its `flush` at line 106 drains no library buffer
and explicitly does not synchronize storage.

| Missing capability | Minimal proposed host operation | Source-library responsibility |
| --- | --- | --- |
| Configurable open | Descriptor-relative open with directory FD, counted raw path, flags, and creation mode; negative errno on failure. Five arguments fit the existing extern register bound. | Validate options and NUL-free paths, supply packed staging, make close-on-exec policy explicit, and adopt the returned FD only on success. |
| Seek and position | Signed 64-bit offset plus explicit origin, returning the resulting position or a separate status and output position. | Typed origin, checked arithmetic, and `Seek` contracts. Preserve the distinction between non-seekable descriptors and ordinary errors. |
| Metadata | Descriptor and path-relative variants, explicit follow/no-follow policy, and a fixed versioned output buffer containing kind, mode, unsigned size, and signed seconds plus fractional nanoseconds. | Decode and validate the documented output layout and requested fields; expose typed metadata. Do not reinterpret an undocumented native `struct stat`. |
| Directory reads | Directory-capable open plus a bounded raw entry-read operation with explicit byte count, EOF, short-buffer behavior, and errno. Linux `getdents64` is a possible primitive. | Validate every record boundary/name terminator, preserve raw name bytes and opaque position cookies, own the descriptor/buffer, and define entry-view lifetime. |
| Durability | Explicit `fsync` and data-only synchronization status operations. | Distinguish flushing library bytes from requesting host durability; report errors and leave namespace durability policy explicit. |
| Duplication | Duplication with close-on-exec policy and, where needed, an explicit target FD. | Create a new owner only after success; document shared open-file position and status flags. |
| Descriptor flags | Read/change the supported descriptor/status flags, including nonblocking and close-on-exec policy. | Validate the supported flag set and avoid silently changing an unrelated owner's descriptor. |

A path metadata request can fit six arguments by fixing the host query mask and
passing `(directory_fd, path_pointer, path_length, flags, output_pointer,
output_capacity)`. A packed request is another option if a larger contract is
needed; it avoids expanding the compiler calling convention. Metadata version,
field-presence bits, integer units, and output capacity must be agreed before
adding source declarations.

Reading and discarding bytes supplies only a limited forward traversal; it is
not general seek. Closing/reopening changes object identity and shared-position
behavior. Opening `/proc/self/fd` paths is not a general duplication contract.
No-op flush cannot stand in for synchronization. These shortcuts must not be
published as completed capabilities.

### Sockets, child processes, and threads at the baseline

The minimum useful numeric-address socket layer needs creation, connect, bind,
listen, accept, datagram send/receive, shutdown, endpoint queries, options, and a
bounded readiness operation. Connected byte streams can reuse existing
descriptor read/write/close bindings. `core::net` already supplies typed IPv4,
IPv6, scoped addresses and byte formatting/parsing; address packing, validation,
owners, retry policy and stream adapters should remain Lanius. DNS, TLS and
asynchronous scheduling are distinct deliverables. The existing declarations at
`stdlib/std/net.lani:276` have no corresponding executable `HostService` entries;
`crates/laniusc-compiler/src/compiler/diagnostics.rs:1508` records their
unavailable status.

Child-process support needs a spawn request with counted executable/argv/env
storage, explicit child FD actions and working-directory policy, an unambiguous
exec-failure result, wait-status output, pipes/duplication for redirection, and
signaling. All staging, argument validation and high-level command behavior can
remain Lanius. The runtime must execute child setup and return real host results;
it must not report successful spawn when exec failed. Current
`stdlib/std/process.lani:229` exports only argc, argument length/read, and exit.

Thread creation has an additional code-entry prerequisite. The unavailable
`spawn(entry_id, arg)` at `stdlib/std/thread.lani:148` has no bound entry registry
or callable-address contract. A usable implementation needs checked source task
entry/dispatch, a native child stack/TLS/trampoline, join handle lifetime and
result handoff, plus synchronization semantics. General mutexes/channels require
atomic operations with defined memory ordering or bound synchronization
primitives. There is no current atomic intrinsic in the language catalog. Merely
adding clone/futex-like declarations or returning success from yield/current-ID
cannot establish thread safety or implement spawn/join.

One possible future Linux boundary is an unsafe syscall primitive taking a
number and a counted six-word argument block and returning a signed 64-bit host
result. Such a primitive did not exist at this baseline. It required an explicit compiler
and runtime design change; a scalar number plus six scalar arguments also
exceeds the current extern register limit. Even an argument-block primitive
would not supply a correct thread trampoline, code-entry ABI, memory model, or
ownership contract automatically.

Each future binding needs coordinated catalog/semantic lowering/native thunk
support, truthful per-operation capability metadata and compiler diagnostics,
and native fault tests. Current work can prepare source algorithms and contracts
without claiming those host operations execute.

## Generic composition: independent admission gates

These failures are independent of missing host services. Existing evidence is
recorded in `docs/stdlib-owned-sets.md`,
`tests/fixtures/stdlib_foundation/iterator_dependency/README.md`, and
`tests/fixtures/stdlib_foundation/buffered_io_dependency/README.md`. Their
historical failing results are not a fresh compilation claim about `5174a14d`.

The owned-set repro wraps `HashMap<T, Unit>` or `TreeMap<T, Unit>` in another
generic receiver, while direct-map controls work. Both maps already keep scalar
and pointer owner state (`stdlib/alloc/hash_map.lani:14`,
`stdlib/alloc/tree_map.lani:14`). A coherent factoring candidate shares one
storage algorithm through owner-state operations instead of duplicating a map
implementation for sets or specializing each primitive key type. Typed key/value
layout witnesses and single ownership must survive that factoring.

The admission prototype under
`tests/fixtures/stdlib_compiler_state/foundation_admission/` reuses the current
HashMap implementation as its only allocation/hash/storage engine. It temporarily
reconstitutes a typed map view from state, checks recorded key/value widths, and
writes all scalar state back before returning. Its typed Map/Set receivers bind
the state to one key/value schema; widths alone are not type identity. This is an
isolated architectural probe, not a public erased container or a validated set
API. A production version would place the shared state operations inside the
map engine and verify full ownership, algebra and failure contracts.

The bounded admission at source HEAD `5174a14d` compiled and executed this
owner-state candidate successfully. Its `Set<i16>` exercises duplicate-key
return, and its `Map<i16, i64>` recovers a stored value of `4294967297`. All three
existing direct controls also compiled and exited zero. This admits further
factoring work; it does not establish a complete set API, TreeSet, owner-key
cleanup, algebra, or failure atomicity.

The iterator and forwarding-writer repros concern imported generic
implementation routing. An explicit associated/static witness call is a small
candidate for comparison with the existing member-dispatch controls. A forwarding
writer must still be accepted by the existing imported `core::io::write_all` to
establish that composition. Changing only its forwarding body may not repair the
outer call's routing; the probe deliberately retains that consumer.

The fresh static iterator witness still fails with `LNC0027` at `I::pull`: no
concrete implementation member can be routed. The forwarding-writer candidate
fails with `LNC0027` at `W::write` because its receiver has no valid checked type
adjustment. That failure occurs before the outer `write_all` composition can be
admitted. Exact source hashes, compiler identity, controls, and normalized
diagnostics are preserved with the admission probes.

Backend-independent cursor limits or buffer progress can also be factored as
ordinary source state machines. That can share useful algorithms while a
generic adapter remains blocked, but it does not establish a common executable
Iterator/Read/Write adapter protocol. The current `core::io::copy` implementation
and benchmark work/duration factoring demonstrate specific successful shapes;
they are not evidence that every imported generic composition works.
