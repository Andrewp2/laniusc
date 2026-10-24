# Native threads and foreign-call prerequisites

This is a source audit and a proposed dependency sequence, based on compiler
`678bf559`. It adds no public declarations or execution claims. Current
[Linux syscalls](stdlib-linux.md), [sockets](stdlib-sockets.md),
[polling](stdlib-poll.md) and [subprocesses](stdlib-command.md) execute through
the documented native profile. Threads, native foreign libraries and callbacks
need additional contracts.

## Existing boundaries

| Boundary | Current state |
| --- | --- |
| Direct Lanius calls | Monomorphic/imported calls execute; generic composition has separate [routing dependencies](library-dependencies.md). |
| Callable values | The grammar has no function type or address-of expression. Checked calls retain a declaration target; lowering has direct calls and host/intrinsic calls, with no checked indirect-call operation. |
| Native linking | The custom LNX86OBJ format resolves static Lanius symbols and text/rodata relocations. This does not supply an ELF-object or shared-library loader. |
| Arbitrary externs | Parsing/type checking a declaration does not bind it. Native emission rejects an unrecognized service call. |
| Atomics | No source atomic or memory-order contract is established. Conservative call effects alone do not establish atomicity or a happens-before relation. |

The source boundaries are [grammar/lanius.bnf](../grammar/lanius.bnf),
[native objects](../crates/laniusc-compiler/src/codegen/x86/object.rs),
[lowering calls](../crates/laniusc-compiler/src/codegen/lowering_ir.rs),
[native argument layout](../shaders/codegen/lir/x86/common.slang) and
[call effects](../shaders/codegen/optimization_ir.slang).
Existing direct-call controls and arbitrary-extern rejections are retained in
[codegen_x86.rs](../tests/codegen_x86.rs). This audit did not rerun those tests.

The native calling convention is Lanius-specific: slices occupy three words,
aggregates have defined passing rules, and large returns use hidden storage.
Register names shared with System V do not establish C ABI compatibility.

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
  current wrapper, process exit and allocation-failure runtime use Linux
  syscall 60, which exits the calling thread in a multithreaded process. The
  wrapper also retains the original argument stack in R15. A thread runtime
  must define and preserve those process-context and termination contracts.

The relevant runtime code is [entry emission](../shaders/codegen/lir/x86/emit.slang)
and [native runtime bindings](../shaders/codegen/lir/x86/runtime_abi.slang).

## Atomics, allocation and TLS

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

A Lanius/raw-syscall thread profile can explicitly omit language/libc TLS.
Libc-backed threads and TLS-dependent foreign functions need initialization,
attachment and teardown. TLS is a requirement of those profiles rather than
an unconditional blocker of every possible native worker.

## Foreign libraries

Separate three admissions:

1. **Direct static foreign calls:** checked platform ABI signatures, foreign
   symbol identity, supported object sections/relocations and linker inputs.
   Argument/return normalization and aggregate layouts must be explicit;
   arbitrary source extern declarations are insufficient.
2. **Dynamic calls:** loading/symbol lookup, library-handle lifetime, address
   relocation and checked indirect-call signatures.
3. **Callbacks:** addressable exported monomorphic entries, ABI trampolines,
   context lifetime, reentrancy and foreign-thread attachment.

TLS and SQLite integration depend on an appropriate foreign-call profile or
another explicitly implemented native boundary. No JSON bridge, subprocess
serialization adapter or declaration-only API is counted as that integration.

Entry authority and concurrent memory semantics need compiler coordination.
Source ownership policies, synchronization algorithms and higher-level library
APIs can remain Lanius after the required boundaries execute. The
[full library roadmap](library-roadmap.md) remains open.
