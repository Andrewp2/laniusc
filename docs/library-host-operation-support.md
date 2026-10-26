# Native host operation support

Audit date: 2026-10-23. Source snapshot: `1602e5bb`, plus the focused panic
operation metadata correction described below. This is an operation inventory
for native x86_64 Linux ELF programs. It traces implementations and existing
native execution tests; it does not certify another target, a running host's
permissions, every raw argument combination, or composable-artifact linking.
The original inventory required no new GPU execution. The later
[raw host-width repair](stdlib-raw-host-width.md) adds focused native evidence
for the size, count, capacity and alignment contracts below. The native C
integrations below have separate, later execution receipts.

## Read the two capability inventories separately

`core::target` reports working library families. `core::runtime` reports direct
catalog services. For example, `core::target::HAS_NETWORK` is true because
`std::socket` works over service 14; `core::runtime::HAS_NETWORK` remains false
because the older `std::net` service 5 declarations have no binding. Both
inventories retain `HAS_RUNTIME_SERVICES=false`: the complete catalog is not
bound. This does not mean that every individual operation is unavailable.

A service-level flag also does not promise every operation in that family.
Clock service 4 has both executable timespec operations and unbound i64
declarations. Conversely, the panic-hook service is unbound while source panic
operations really trap. Use the operation row and its exact wrapper contract.

## Direct native operations

Implementation anchors for this table are
[`HostService`](../crates/laniusc-compiler/src/codegen/lowering_ir.rs),
the [shader IDs](../shaders/codegen/lowering_ir.slang),
the [native dispatch and thunks](../shaders/codegen/lir/x86/runtime_abi.slang),
and the [diagnostic catalog](../crates/laniusc-compiler/src/compiler/diagnostics.rs).
“Native tests” names existing test targets, not newly repeated executions.

| Family | Operations that work | Narrower contract / unavailable operations | Native tests |
| --- | --- | --- | --- |
| 1: allocator | `alloc`, `realloc`, `dealloc`, terminating `alloc_failed` | Low-level sole-owner/matching-layout contract; no automatic destruction. Sizes retain all native `usize` bits. Allocation/reallocation reject zero sizes and alignments outside 1/2/4/8 before the syscall; null reports failure and failed reallocation preserves the old owner. Initial mappings may lie anywhere in the address space (no `MAP_32BIT`); full-width transport is not a large-allocation success guarantee. Deallocation is void and cannot report kernel failure. `alloc::vec` retains its `i32::MAX` backing limit. | `stdlib_raw_host_width_execution`, `stdlib_allocator_metadata_execution`, `stdlib_allocator_failure_execution`, `stdlib_alloc_vec_execution` |
| 2: descriptor I/O and paths | Fixed read/write/create-append opens, read, write, close; remove file, create/remove directory, rename. Legacy text/integer helpers also have real native slots. | Counted paths reject NUL and lengths over 4,095. One-call I/O may be short. These fixed opens do not imply configurable flags, seeking, metadata, synchronization or enumeration; those execute through service 14 below. `File` supplies manual ownership, not automatic close. | `stdlib_owned_file_execution`, `filesystem_operations_execution`, `stdlib_stream_execution`, `stdlib_file_execution` |
| 3: stdio | Raw stdout/stderr writes and stdin reads; descriptor text/integer/byte/LF output; `print_i32` | `print_i32` executes one unchecked write and exposes no delivery status. Full-delivery callers use checked writers. `flush_stdout`/`flush_stderr` are executable source bodies with no pending userspace buffer; they do not synchronize storage. | `stdlib_host_execution`, `stdlib_stream_execution` |
| 4: clock, bound subset | `unix_seconds` (i32), `monotonic_read`, `system_read`, `sleep_ms_i32`; typed `std::clock` results/deadlines over those calls | `monotonic_now_ns() -> i64`, `system_now_unix_ms() -> i64`, and `sleep_ms(i64)` remain unbound. The explicit `CLOCK_I64_*` flags and their catalog rows correctly remain false. Native i64 arithmetic does not supply these bindings. | `time_execution::native_clocks_preserve_timespecs_errors_and_deadline_waits` |
| 5: legacy network | No direct binding | All ten `std::net` TCP/UDP externs are known-unbound. Working `std::socket` is a different library boundary over family 14. | Source flags/catalog; `stdlib_socket_execution` proves the separate working family |
| 6: panic/hook distinction | `core::panic::panic` and `unreachable` execute `assert(false)` and trap | Hook registration remains unavailable. These operations have executable source bodies and require no panic-hook binding. Their operation metadata now says `executable-stdlib`, while the owning service metadata remains `known-unbound`. | `stdlib_panic_execution::{panic_metadata_reports_executable_traps_and_unbound_hooks,panic_and_unreachable_trap_instead_of_returning}` |
| 7: generic host services | Descriptor/status metadata only | No separate executable generic-host operation. Service 14 does not change this service's status. | Catalog/source contract; no operation implementation claimed |
| 8: threads | No direct binding | `spawn`, `join`, `yield_now`, `current_id` remain unbound. No checked thread entry, new-stack trampoline or memory-ordering contract follows from raw syscalls. | Catalog/source contract; no thread execution claimed |
| 9: secure entropy | `fill_secure_bytes`, `secure_u32`; recoverable `std::entropy` wrappers | Raw fill makes one host request; higher wrappers handle partial progress/EINTR. Raw `secure_u32` traps on error or short result; it is not an error-returning operation or silent zero fallback. | `stdlib_random_execution`, `randomness_execution::os_entropy_preserves_bytes_progress_errors_and_source_sampling` |
| 10: user GPU service | No direct binding | Buffer alloc/free/read/write and dispatch declarations are unbound. GPU use by the compiler is independent. | Catalog/source contract; no user GPU execution claimed |
| 11: original process service | `argc`, `arg_len`, `arg_read`, `exit` | Arguments come from retained startup process state. This direct family does not bind spawn/wait; `std::command` implements those over 14. | `stdlib_host_execution`, `stdlib_command_execution` |
| 12: environment | Environment count/key/value length/read and current-directory read; source `current_dir_len` | Environment access reads startup state; no environment-mutation API is supplied. `current_dir_len` stages an actual bounded read and may allocate/fail. Command child cwd changes are separate. | `stdlib_env_execution` |
| 13: runtime test harness | Descriptor/status metadata only | No runtime registration/discovery/execution service. Explicit Lanius test suites and the compiler's Rust test runner are separate working workflows. | Catalog/source contract; no runtime harness execution claimed |
| 14: explicit Linux syscall boundary | Raw `syscall6(number, args) -> i64`; checked logical argument packing through `std::linux::call` | Six full-width words/pointers and raw result; errno conversion only in the helper. No syscall-specific memory safety, FD ownership, retry, signal trampoline or new-stack entry. Returning calls must retain the same valid stack/continuation. Wasm explicitly rejects this boundary. | `stdlib_linux_execution`: word/result width, fifth/sixth pointer, errors/EINTR, no allocation/retry, metadata, Wasm rejection |

## Source libraries executing over service 14

These operations are implemented in Lanius using the generic boundary; they do
not add a new compiler service per OS call or make old externs executable.

| Library family | Actual host operations and source responsibility | Existing evidence |
| --- | --- | --- |
| [`std::file_ops`](stdlib-file-operations.md) | `openat`, `lseek`, `ftruncate`, `fcntl`, `dup3`, `fsync`, `fdatasync`, `statx`; checked raw-byte paths/options, signed wide positions and lengths, metadata field-presence/layout validation, synchronization errors and manual FD ownership. No crash-durable namespace transaction or lock is implied. | `stdlib_file_operations_execution`: real identity/flags/large offsets, independent OS metadata, malformed/bounds atomicity and injected errors; [resize gates](stdlib-file-resize.md): sparse file lengths, zero extension, shared offsets and one-attempt errors |
| [`std::file_copy`](stdlib-file-copy.md) | Composes descriptor flags, statx identity, seek, truncate and File byte I/O for bounded regular-file replacement. Checks aliases before destruction, reads actual EOF and reports consumed/written progress. No transaction, lock, implicit retry, sync or close is supplied. | `stdlib_file_copy_execution`: 84 native cases including real partial writes and zero-size pseudo-files; `stdlib_copy_file_execution`: 59 application cases with owner and error cleanup |
| [`std::directory`](stdlib-directory.md) | `getdents64` plus open/statx; bounded record parsing and iteration, anchored no-follow traversal, explicit race and lifetime limits, staged snapshots. | `stdlib_directory_execution`: OS oracle, byte names, trees/scale/limits, allocation and descriptor cleanup |
| [`std::socket`](stdlib-sockets.md) | socket/connect/bind/listen/accept4; stream/datagram send/receive; endpoint queries, shutdown, supported options, descriptor status/duplication and one-FD readiness. Numeric IPv4/IPv6 addresses, ownership and errno/retry/deadline policy remain source code. System resolution and authenticated TLS use the separate native C integrations below. | `stdlib_socket_execution`: real IPv4/IPv6 TCP/UDP, datagram truncation, half-close, options, accept cleanup and deadline/error checks |
| [`std::signal`](stdlib-signals.md) | `rt_sigaction` for the supported typed signals and Default/Ignore dispositions. No arbitrary source handler/trampoline is installed. | `stdlib_signal_execution`: kernel disposition inspection, real broken-pipe behavior, restoration and injected failure |
| [`std::poll`](stdlib-poll.md) | Multi-FD poll with fixed-capacity owned scratch/publication, borrowed FD lifetimes and advisory readiness. One-call relative waits or bounded absolute CLOCK_MONOTONIC waits; post-poll observed expiry publishes zero. | `stdlib_poll_execution`: pipes/socketpairs, invalid/negative/duplicate FDs, saved-result atomicity, allocation/result/clock faults, EINTR budgets and independent `select.poll` over 4,096 records |
| [`std::command`](stdlib-command.md) | Same-stack fork/execve/wait4/kill, pipe2, dup3/fcntl, close_range, chdir and descriptor I/O; owned startup staging/status channel, explicit startup uncertainty and child/PID lifetime. Explicit new groups use setpgid/getpgid; waitid/WNOWAIT retains the unreaped leader anchor for group signaling and capture. Requires the documented single-threaded/no-outside-reaping contract and host close_range support. | `stdlib_command_execution`: real lifecycle, pipe/environment/cwd/FD actions and independent startup/resource-fault model; [group API and supervisor gates](stdlib-command-groups.md#focused-execution-evidence) cover authority, escalation and failure cleanup |

Higher-level DNS, TZif, file formats and command pipe-draining clients compose
these operations. Their own guides/tests establish protocol/format and resource
contracts. These source implementations do not bind the old catalog APIs.

Raw descriptor/stdio byte counts, startup argument/environment copy capacities,
environment key lengths, clock output capacities and current-directory capacity
also retain their full native `usize` width. The focused raw-width gate checks
high-word transport with injected errors and bounded real buffers; it does not
access huge sentinel buffers. Declared `i32` indices/results and each wrapper's
existing short-I/O/errno policy remain explicit. See the
[raw boundary guide](stdlib-raw-host-width.md) for ownership and backing rules.

## Ordinary native C integrations

[`std::resolve`](stdlib-resolve.md) calls libc `getaddrinfo` and `freeaddrinfo`
through the checked [native C profile](library-native-c.md), with CRT startup
and thread-local errno. It stages explicit hints, validates the selected glibc
layouts and returns owned socket addresses in native order, including
duplicates. All four [library groups](stdlib-resolve-testing.md) and all five
[`resolve-host` application groups](stdlib-resolve-host.md) pass through separate
receipts. Input/result caps bound Lanius staging and traversal, not native
NSS allocation, blocking time or cleanup work; there is no lookup deadline.

The same native C path supplies [OpenSSL TLS, including mutual TLS](extended-openssl-mutual-tls.md)
and [SQLite](extended-sqlite.md). These are ordinary library calls, with explicit
native owners and wrapper policies. They add no host intrinsic or service ID
and do not bind the ten legacy `std::net` externs. Callbacks, foreign thread
entry and aggregate C layouts remain outside the native C profile.

## Binding authority and metadata corrections

The direct host-service path is a closed compiler mapping:

1. `type_checker/params.rs` supplies builtin spellings; semantic
   `artifact/00_project.slang::host_service_for_function` admits the known
   extern slots through 62 (excluding intrinsic 52), plus syscall slot 74.
   Slots 63–73 are types/paths/intrinsics, not ordinary host bindings.
2. `HostService` and matching shader IDs identify the lowering operation.
3. `runtime_abi.slang::x86_runtime_service_offset` selects an actual thunk;
   `instruction_plan.slang` emits its runtime call. `x86/count.slang` rejects
   a remaining ordinary extern or unsupported host service before output.
4. The service/API diagnostic catalog describes that boundary for tooling;
   metadata itself does not create a native thunk.

The audit corrected the two panic operation rows to use the existing
`executable_stdlib_api` representation. Panic-hook service 6 stays unbound;
trap/runtime/IR/proof code is unchanged. Focused CPU assertions now check both
operations' API-true/service-false split. Existing native SIGILL tests supply
the execution evidence. Stale CPU test expectations for executable service 14
were also aligned with its already-working source/binding metadata.
The two service 14 operation rows now occupy the final service group, retaining
the catalog's canonical nondecreasing service-ID order and its existing gate.

Direct native success does not loosen composable-artifact descriptor policy:
target-byte descriptors with runtime requirements remain rejected, including
family 14. The separate [native C profile](library-native-c.md) supplies
executable scalar/pointer calls and CRT linking outside those descriptor modes.
Broader C ABI profiles, source thread-local storage and atomics, foreign thread
entry, user GPU execution and complete external runtime linking require their
own contracts and evidence.

### Keeping this inventory current

For a changed operation, update its source probe, the owning service row only
when appropriate, its operation catalog row and focused native/error evidence.
A body implemented over an existing service should be described as such.
Avoid inferring support from declaration spelling, scalar width, an aggregate
family boolean, a successful type check or status-constructor helpers. Group
tests by actual OS behavior and invariants rather than generating a probe for
every metadata synonym.
