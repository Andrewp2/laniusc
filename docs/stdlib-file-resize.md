# Checked file lengths

`std::file_ops::set_len(file, length)` changes an open file's byte length on
x86_64 Linux. It is implemented in Lanius over the existing `std::linux`
syscall boundary, without allocation or a new compiler service.

```lani
pub fn set_len(file: &std::file::File, length: u64)
    -> core::result::Result<i32, core::io::Error>;
```

## Behavior and ownership

The function borrows a live `File`; ownership stays with the caller. A smaller
length discards the tail. A larger length exposes zero bytes in the extension
where the filesystem supports extension. The shared open-file offset stays
unchanged, including when it lies beyond the new EOF. A same-length request
still makes one host attempt. These are the
[Linux ftruncate semantics](https://man7.org/linux/man-pages/man2/ftruncate.2.html).

The descriptor must be open for writing. Filesystem limits, file seals,
permissions and other host restrictions can reject the operation. The wrapper
does not seek, close, synchronize storage or implement a transaction. Keep the
borrowed descriptor live and prevent concurrent close/reuse. Other users of
the same file can observe its changed length immediately; the operation does
not provide an isolated snapshot or rollback.

## Bounds and errors

Validation order is explicit:

1. Lengths above `9_223_372_036_854_775_807` return `InvalidInput` before any
   descriptor lookup or syscall. The native boundary uses a signed 64-bit length.
2. An inactive `File` returns `Host(9)` before a syscall.
3. A live owner makes exactly one `ftruncate` attempt. Only zero means success,
   returned as `Ok(0)`; an unexpected successful host value is `InvalidCount`.

EINTR becomes `Interrupted`, EAGAIN becomes `WouldBlock`, and other errno values
become `Host(errno)`. The call never retries. An error does not close the owner
and does not promise rollback of host effects. See the
[descriptor guide](stdlib-file-operations.md) for the shared error and ownership
rules.

## Executable evidence

The focused native gates are in
[`stdlib_file_resize_execution.rs`](../tests/stdlib_file_resize_execution.rs).
The contract fixture checks shrinking, same length, zero, zero extension,
sampled sparse bytes above 4 GiB, and unchanged positions through duplicate
descriptors. The Rust driver independently checks final file contents and the
syscall trace. Oversized lengths and inactive owners must not issue truncate
calls; the wrappers allocate no memory.

The fault fixture checks one attempt each for EINTR, EAGAIN, EIO, EFBIG and
ENOSPC, plus an injected nonzero success result. Every case preserves caller
ownership until its explicit close. Injection skips the actual syscall, so
the unchanged-file oracle in those cases establishes wrapper behavior under
that fault model rather than general filesystem error atomicity.

Both gates passed on 2026-10-24: contracts in 5.51 s and faults in 4.37 s.
They compiled two native executables and ran eight native processes: one
contract process and seven normal/injected fault cases. The Rust test driver
built in 2.07 s. Logs are retained under
`target/stdlib-work/file-resize-admission/`.
The tests execute GPU-compiled native ELF files through the existing strict
x86 transfer checker. They make no claim for other operating systems or user
GPU kernels.
