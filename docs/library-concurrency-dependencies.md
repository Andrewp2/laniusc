# Concurrency admission dependencies

This is a source and native-ABI audit of the current Linux x86_64/glibc
compiler. It proposes the next executable contracts for the full library;
bounded downloader scheduling does not complete threads or synchronization.
No compiler, runtime, IR or proof changes are made here. All seven focused
admission controls have run with unchanged compiler sources at
`4a7a9c5ef02f987ea449bd1c82c494a31cb34b61`: three positive controls execute and
four negative controls reject. These receipts establish no worker execution
or compare-exchange support.

## What already exists

The [native C profile](library-native-c.md) admits `i32`, `u32`, `i64`, `u64`,
`isize`, `usize`, `ptr`, `f32`, `f64` and void results, with at most 32
parameters. It supplies CRT/libc startup for the initial thread. It does not
admit C `_Bool`, byte/short scalars, C function-pointer types or aggregate
parameters/results. A declaration accepted as `ptr` does not establish that
the argument is a function pointer with a checked calling convention.

| Boundary | Current source evidence | Consequence |
| --- | --- | --- |
| Thread API | [`std::thread`](../stdlib/std/thread.lani) explicitly marks service 8 unavailable; `spawn`, `join`, `yield_now` and `current_id` are runtime externs | Type-checkable metadata does not provide executable operations |
| Callable definitions and values | [`grammar/lanius.bnf`](../grammar/lanius.bnf) has ordinary function bodies, extern declarations ending in a semicolon, and no function type or address-of expression | No checked source C callback definition/address capability is available |
| Checked calls | [`00_calls.slang`](../shaders/type_checker/semantic/artifact/00_calls.slang) resolves function/dependency/intrinsic/variant declaration targets; native metadata in [`semantic_interface.rs`](../crates/laniusc-compiler/src/compiler/semantic_interface.rs) carries scalar signatures | A direct C call is established; arbitrary indirect calls and callback entry are not |
| Memory effects | [`opt_ir_memory_effects`](../shaders/codegen/optimization_ir.slang) treats every call as an opaque memory read and write | Existing calls offer a plausible conservative foundation for native atomics; they are not yet a documented inter-thread memory model |
| Process context | [`crt_entry.s`](../shaders/codegen/lir/x86/crt_entry.s) reconstructs the argument/environment vector, keeps it in R15 and unmaps it when language main returns | A worker or callback must establish its own valid R15 context and retain the vector for its entire use |
| Termination | [`runtime_abi.slang`](../shaders/codegen/lir/x86/runtime_abi.slang) uses Linux syscall 60 for runtime exit and allocation failure | Calling-thread exit cannot silently become whole-process termination or normal pthread completion |

The compiler's GPU-side Slang atomics synchronize compiler workgroups. They
do not expose CPU atomic values or a source memory-order contract.

## Established libraries are usable, with exact prototypes

### libatomic

GCC documents `__atomic` operations in terms of a race-free C++11 memory
model. Atomicity and ordering are separate requirements; an acquire operation
can synchronize with a release operation, while sequential consistency adds
a total order among sequentially consistent operations. A first Lanius
profile can expose only sequential consistency and add weaker orders after
their rules are specified. [GCC atomic documentation](https://gcc.gnu.org/onlinedocs/gcc/_005f_005fatomic-Builtins.html)

The runtime symbols are distinct from the overloaded compiler builtins.
GCC's [libatomic declarations](https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-13.2.0/libatomic/libatomic_i.h)
define unsigned 4/8-byte operands and these relevant forms:

| Runtime operation | Exact Lanius scalar shape for this profile | Admission |
| --- | --- | --- |
| `__atomic_load_4` / `_8` | `(ptr, i32) -> u32` / `u64` | Current scalar shape suffices |
| `__atomic_store_4` / `_8` | `(ptr, u32, i32)` / `(ptr, u64, i32)` returning void | Current scalar shape suffices |
| `__atomic_exchange_4` / `_8` | `(ptr, u32, i32) -> u32` / corresponding `u64` | Current scalar shape suffices |
| `__atomic_fetch_add_4` / `_8` | Same argument/result shape as exchange | Current scalar shape suffices |
| `__atomic_compare_exchange_4` / `_8` | `(ptr, ptr, u32, i32, i32) -> C _Bool` / corresponding `u64` | C Boolean result is currently unsupported |

These are real versioned library exports, including the 4/8-byte forms;
linking needs the installed libatomic development/linker input, normally
`--native-library atomic`. [GCC export map](https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-13.2.0/libatomic/libatomic.map)

The compare-exchange runtime has **five** arguments and strong semantics.
It has no builtin `weak` argument. On failure it updates the caller's expected
value; its C `_Bool` result must not be redeclared as `i32` or `u32` to evade
admission. Generic size-based compare-exchange also returns `_Bool`, so it
does not remove this gap. [Sized implementation](https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-13.2.0/libatomic/cas_n.c),
[generic implementation](https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-13.2.0/libatomic/gcas.c)

The minimum compiler extension for direct native compare-exchange is a checked
C Boolean result with correct System V return normalization, retained through
imports and signature conflict checks. Boolean parameters would need their
own transport contract when admitted. A C shim returning int would be an
additional production bridge, not an accurate declaration of this symbol;
none is introduced here. A different lock-based design is possible, but all
operations on that object would have to share its synchronization discipline.

### pthreads

The installed `pthread.h` declares:

```c
int pthread_create(pthread_t *, const pthread_attr_t *,
                   void *(*start_routine)(void *), void *);
int pthread_join(pthread_t, void **);
```

The start function's return is the thread result. The native library manages
the thread stack and thread-local runtime state. The chosen first profile can
use default joinable attributes and avoid publishing opaque attribute layouts.
GNU documents the creation, return, join and attribute lifetimes in its
[thread manual](https://sourceware.org/glibc/manual/2.42/html_node/Creating-and-Destroying-Threads.html).
The installed glibc x86_64 headers make `pthread_t` an unsigned long; an opaque
wrapper can retain its bits in `usize` on this profile, without treating it as
an i32 handle, process ID or generally portable representation.

`pthread_self` and `pthread_equal` have usable current scalar signatures.
The initial-thread control now compiles and executes, but produces no worker.
`pthread_create` needs a checked C entry of shape `(ptr) -> ptr`, not an
ordinary function cast to a data pointer. The internal generated
`__lanius_<library>_<unit>_<declaration>` ELF symbol is not such an entry
contract. The existing CRT bridge is specific to `main`, not a reusable
worker trampoline.

## Minimum complete ownership and ordering contract

The following are prerequisites for publishing an executable thread/atomic
library. They are proposed acceptance conditions, not current guarantees.

1. **Checked entry authority.** Admit a monomorphic C callback definition and
   a typed entry capability, or a compiler-checked static entry registry.
   Validate the exact signature, imported identity, symbol lifetime and
   relocation. An arbitrary integer entry ID or data pointer grants no entry
   authority. General closures and arbitrary indirect calls can follow later.
2. **Worker initialization.** Use pthread creation for native stack/TLS setup.
   A generated trampoline receives a staged record, establishes R15, calls the
   ordinary Lanius body, preserves the native ABI and returns its `ptr` result
   to pthreads. Do not assume glibc copied the parent's reserved R15 value.
   The main bridge's process-vector mapping must outlive every worker that
   borrows it; initially require joining all workers before main returns.
3. **Spawn transfer.** Fully initialize argument/result/context storage before
   native creation. A worker may run before the creator observes success.
   Failed creation leaves the argument owner with the caller; success transfers
   its agreed authority to the worker and produces one join owner. No borrowed
   stack storage may expire while the worker can access it. Pthread error codes
   are returned directly, not taken from errno.
4. **Join and reclamation.** One active join owner retains the native handle
   and completion record. A successful join publishes the result and permits
   exactly-once reclamation; an error must retain authority for a defined
   recovery. Reject self-join and inactive/repeated/concurrent joins locally.
   Do not test invalid pthread handles by passing them to libc. Start with no
   detach, cancellation or implicit join-on-destroy. glibc's
   [join implementation](https://raw.githubusercontent.com/bminor/glibc/release/2.39/master/nptl/pthread_join_common.c)
   documents its single waiter and acquires termination before freeing the TCB.
5. **Atomic storage and access.** Start with separately owned, properly aligned
   4/8-byte unsigned words. Initialization precedes publication; destruction,
   reallocation and non-atomic aliases require exclusive access after users
   finish. Lanius `u32` raw views use eight-byte slots, so a packed array of C
   32-bit atomics cannot inherit that stride. Define exact byte addresses and
   checked offset arithmetic. CAS expected/result scratch remains caller-local.
6. **Compiler ordering.** Specify which native calls synchronize and preserve
   surrounding memory effects through optimization and generic replay.
   Current opaque read/write call effects are useful evidence, not a reason
   to invent a required new IR row or to declare the contract already complete.
   For weaker orders, validate operation-specific legal orders and CAS failure
   order before native entry. Ordinary data races remain invalid; volatile or
   an aligned plain load/store does not substitute for an atomic operation.
7. **Failures and termination.** Define worker normal return, recoverable error,
   trap, infallible allocation failure and explicit process exit separately.
   A raw syscall-60 exit can bypass pthread result publication, native cleanup
   and completion bookkeeping. Initially require recoverable allocation in
   workers and make unsupported fatal paths explicit. Cancellation/nonlocal
   unwinding across Lanius frames is not established.
8. **Library sharing.** Keep one active owner for mutable collections, buffers,
   files and native sessions, or protect all accesses with a defined lock.
   Shallow copies do not enforce Send/Sync or automatically share destruction
   authority. Existing single-threaded `std::command`/process-group contracts
   remain restrictions after adding threads. A thread-safe native function is
   not automatically an atomic composition of wrapper operations.
   [GNU safety concepts](https://sourceware.org/glibc/manual/2.42/html_node/POSIX-Safety-Concepts.html)

Mutexes, condition variables, channels, cooperative cancellation, join deadlines
and arbitrary foreign-thread callbacks need further public state/lifetime
contracts. Pthread mutex objects require audited size/alignment or a native
allocation interface; zeroed guessed bytes are not a portable initializer.
Blocking native lock/join calls have no elapsed-time guarantee from a Lanius
call budget. No lock-free, fairness or starvation guarantee follows merely
from a libatomic symbol name.

## Focused reproductions and next gates

Sources are in
[`concurrency_admission`](../tests/fixtures/stdlib_compiler_state/concurrency_admission/REPRODUCTION.md).
The parent runner compiled every source with the current GPU compiler. Each
positive executable passed linked-ELF validation and exited zero with empty
stdout and stderr. The observed outcomes are:

| Fixture | Compiler elapsed | Observed outcome |
| --- | --- | --- |
| `direct_entry_control.lani` | 2.460 s | Compile/link succeeds; ordinary `(ptr) -> ptr` direct call exits zero |
| `atomic_scalar_control.lani` | 2.145 s | Compile/link with `atomic` succeeds; single-thread full-width scalar operations exit zero |
| `pthread_identity_control.lani` | 2.391 s | Compile/link succeeds; initial-thread identity control exits zero |
| `atomic_compare_exchange_bool.lani` | 2.449 s | Exit 1, `LNC0006`: unsupported native C signature at the unused Boolean result |
| `function_value.lani` | 2.256 s | Exit 1, `LNC0005`: `worker` is unresolved when used as a value |
| `callback_definition.lani` | 2.362 s | Exit 1, `LNC0016`: extern declaration expects `;`, finds the body brace |
| `std_thread_unbound.lani` | 3.231 s | Exit 1, `LNC0059` wrapper; underlying native declaration has no definition or checked binding |

The summary receipt is
`target/stdlib-work/concurrency-admission-controls.log`; per-control compiler
and positive native logs are in `target/stdlib-work/concurrency-admission/`.
All commands completed within their 100-second limits. These elapsed figures
describe focused compiler invocations, not atomic or thread throughput.

The legacy thread diagnostic's decisive note is
`native declaration [0, 0, 43] has no Lanius definition or checked foreign binding`.
This agrees with the explicitly unbound service 8. Its generic
`source-pack artifact store failed` wrapper and remove-artifacts help do not
demonstrate a disk/cache failure; deleting artifacts does not supply a thread
binding.

The next compiler work is checked Boolean transport and callback/worker entry,
followed by the runtime ownership/order admission above. The paired controls
now isolate those admissions from working direct and scalar calls. Subsequent
bounded native tests should cover full-width CAS success/failure and expected
updates, two-worker fetch-add uniqueness, release/acquire message publication,
worker errno/TLS isolation and process argument access, imported entries, and
exact owner cleanup on spawn failure, normal join and recovery. Native pthread
oracles/observers should check entry ABI, lifetime and cleanup independently.
Use explicit operation counts and external process timeouts; a finite stress
run is not a proof of memory ordering, race freedom or liveness.

These controls establish neither concurrent memory ordering nor executable
Lanius callbacks, workers or compare-exchange. The earlier
[native integration prerequisites](library-native-integration-prerequisites.md)
and [full library roadmap](library-roadmap.md) remain applicable.
