# Unsafe native Linux syscalls

`std::linux` is a Linux x86-64 boundary for the native ELF backend. Wasm does not
implement it. Portable filesystem, socket, and process APIs belong in source
modules above this boundary; the compiler does not need a new service for every
OS operation.

## Contract

Both entry points are **unsafe contracts**. Lanius currently has no unsafe-block
syntax: the caller must uphold the contract explicitly. Neither function
validates syscall-specific buffers, kernel structure layouts, pointer lifetimes,
permissions, descriptor ownership, or effects on process state.

`syscall6(number: i64, args: ptr) -> i64` is the raw
`extern "lanius_linux"` primitive. `args` must point to 48 readable bytes holding
six ascending little-endian 64-bit words. All six words are read even for a
zero-argument syscall. The thunk copies their bit patterns to the Linux syscall
registers and returns the kernel's full signed 64-bit result unchanged. It does
not translate errno, set thread-local errno, allocate, or retry an interrupted
operation. Linux dispatches syscall numbers using their signed low 32 bits;
passing a wider source number does not create a separate syscall namespace.

`Argument` has `Word(i64)` and `Address(ptr)` variants.
`call(number, arguments: core::slice::View<Argument>) -> Result<i64, Error>`
validates the logical view and accepts at most six arguments. It uses 48 bytes
of local packed i32 storage and zeroes unused words. One-element typed i64/ptr
views store full-width words without pointer/integer casts or assumptions that
a general Lanius array uses C layout. It makes no heap allocation.

| Result | Meaning |
| --- | --- |
| `Err(Bounds)` | Negative view start/length or overflowing start + length, rejected before indexing or entering the kernel. |
| `Err(ArgumentCount)` | More than six arguments, rejected before indexing or entering the kernel. |
| `Err(System(errno))` | Raw result in `-4095..-1`, with positive errno. |
| `Ok(value)` | Every other raw 64-bit result. Its meaning belongs to that syscall. |

The underlying view must physically back its declared range. Forged or
physically overclaimed backing can trap; the helper cannot recover from an
invalid pointer. `Address` marks a bit-preserving pointer argument, not a
validated buffer. Short I/O and EINTR/EAGAIN policy belong to the source wrapper
for the particular operation.

For example, Linux x86-64 `getpid` takes no arguments. A checked zero-length
view still has ordinary live backing:

```lanius
let backing: [std::linux::Argument; 1] = [std::linux::Argument::Word(0)];
let empty: core::slice::View<std::linux::Argument> =
    core::result::unwrap(core::slice::view(backing, 0));
let pid: core::result::Result<i64, std::linux::Error> = std::linux::call(39, empty);
```

Use `Address(pointer)` for pointer arguments. Do not convert pointers to integer
words. The native admission fixture in
`tests/fixtures/stdlib_foundation/linux_syscall_admission.lani` also demonstrates
packed output storage for `clock_gettime` and an errno result.

## Control flow and lifetime restrictions

A returning syscall must resume this thunk on the same valid continuation and
stack, preserving the language ABI's callee-saved registers and runtime state.
Do not call `clone`/`clone3` with a new stack, `vfork`, or `rt_sigreturn` through
this returning thunk. Thread entry, TLS, synchronization and signal trampolines
need their own reviewed architecture. A raw fork may return on a copied stack,
but parent/child resource handling and threading constraints require a separate
process contract; this primitive alone does not establish safe spawn or threads.
Successful exec/exit may end the old continuation; on failure they must return
under the same ABI requirements.

Memory mappings, protection changes, descriptor changes and other syscalls must
not invalidate the active code, stack, argument storage, or resources that the
caller still uses. The primitive is not a syscall sandbox or a general claim
that every kernel operation is usable from arbitrary Lanius code.

## Runtime integration

The raw binding appends language/HostService slot 74. Slots 63..73 remain
language names, types, or intrinsics and are not host services. Existing service
IDs and thunk offsets stay unchanged. The 32-byte bridge is appended at runtime
offset 1981, increasing the runtime block from 1981 to 2013 bytes. Its assembly
source is `shaders/codegen/lir/x86/runtime_linux_syscall.s`.

Native Linux syscalls use runtime inventory family 14. Families 1..13 retain
their IDs; aggregate host-services family 7 remains unbound. The ABI metadata
record format and existing calling conventions do not change. Native-target
requirements report family 14 available; Wasm and generic artifact requirements
report it unavailable. This status describes the direct native source binding.
The composable artifact descriptor pipeline still rejects target-byte records
whenever runtime service requirements are present, including native family 14.
Those descriptors remain contract-only; this change does not implement runtime
linking for composable artifacts or loosen that existing validator policy.

The register convention and syscall-number interpretation follow the
[Linux x86-64 entry implementation](https://github.com/torvalds/linux/blob/master/arch/x86/entry/entry_64.S).
