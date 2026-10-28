# Positional file I/O

Complete the missing explicit-offset I/O family without changing the shared
cursor of an open file description. The portable layer belongs in `core::io`,
alongside Read/Write, and the Linux descriptor implementation belongs in
`std::file_ops`. No seek/read/restore emulation, compiler change, new runtime
ABI, allocation or automatic flush/close is needed.

## Fixed interface

```lani
pub trait ReadAt {
    pub fn read_at(&self,destination:[u8],offset:i32,count:i32,position:u64)
        -> core::result::Result<i32,Error>;
}
pub trait WriteAt {
    pub fn write_at(&self,source:[u8],offset:i32,count:i32,position:u64)
        -> core::result::Result<i32,Error>;
}
pub fn valid_position(position:u64,count:i32) -> bool;
pub fn read_exact_at<R>(reader:&R,destination:[u8],offset:i32,count:i32,
    position:u64,max_attempts:i32) -> core::result::Result<i32,Failure>
    where R:ReadAt;
pub fn write_all_at<W>(writer:&W,source:[u8],offset:i32,count:i32,
    position:u64,max_attempts:i32) -> core::result::Result<i32,Failure>
    where W:WriteAt;
```

The existing Failure records confirmed completed bytes. The checked logical
array range and the whole positional span must be valid before any callback.
The positional domain is `0..=9223372036854775807`, including the exclusive
end: count must be nonnegative and at most MAX-position. This supports ordinary
signed 64-bit file lengths without wrap or unsigned-to-signed ambiguity. Empty
requests may start at MAX. Physical backing/lifetime remain caller obligations.

Negative attempt budgets are InvalidInput even for empty input. Valid empty
operations return zero without callbacks, even with zero budget. A nonempty
zero budget returns LimitExceeded. Every trait call consumes one attempt,
including Interrupted; only Interrupted is retried. WouldBlock and other
errors are returned with the confirmed prefix. Each next request advances both
array offset and file position by completed bytes. A result outside
0..=remaining is InvalidCount; read zero is UnexpectedEof and write zero is
WriteZero. No additional call is made after completion. Exhaustion before
completion returns LimitExceeded. This is a call budget, not a host time limit.
Previously confirmed writes are never rolled back; completed excludes an
invalid count and the failing call. No atomicity or crash durability is promised.

## Native implementation

```lani
pub const POSITIONAL_CHUNK_BYTES:i32 = 1024;
pub fn read_at(file:&File,destination:View<u8>,position:u64)->Result<i32,Error>;
pub fn write_at(file:&File,source:View<u8>,position:u64)->Result<i32,Error>;
```

`File` implements both portable traits in file_ops. Import file_ops to bring
those implementations into the compilation. Validate full logical metadata and
positional span, then require a live owner. Empty requests on a live owner
return zero without host calls; closed owners return Host(9). For nonempty
requests, F_GETFL validates status: reject O_DIRECT (16384) for both operations,
and O_APPEND (1024) for writes, with InvalidInput. Reads permit O_APPEND.
The caller must prevent concurrent descriptor close/replacement and status flag
mutation, including through duplicates; the check is not synchronization.

Make at most one pread64 (17) or pwrite64 (18) after status validation, for at
most 1024 bytes. Pack arbitrary strided source bytes into contiguous stack
storage; stage reads and publish only after checking the returned count. A host
error or malformed read count publishes no destination bytes. Successful short
counts and EOF are returned unchanged. Map EINTR and EAGAIN to existing errors;
preserve other errno as Host. No retry or fallback. Nonseekable descriptors,
access modes, filesystem size/space and other host restrictions remain explicit
host errors. The functions borrow the owner and leave the shared file cursor
unchanged; they do not allocate, flush, synchronize or close.

Reference: [Linux pread/pwrite](https://man7.org/linux/man-pages/man2/pread.2.html).
Its O_APPEND behavior makes an unchecked pwrite wrapper incorrect for this
contract. This staging adapter does not support direct I/O; broader descriptor
flags and changes to the underlying file remain caller/host policy.

## Acceptance

- Scripted portable normal, empty, invalid, quota, short, EOF, zero, Interrupted,
  WouldBlock, host failure and malformed-count behavior, with observed calls,
  positions, array offsets, destination sentinels and confirmed progress.
- Independent deterministic model over mixed schedules and positional extremes.
- Native reads/writes with positive/negative native stride and nonzero View
  starts; exact helpers across the staging boundary, sparse offsets above 4GiB,
  duplicated-owner cursor preservation, append/direct rejection, access and pipe
  errors, close behavior, no allocation and injected native errors/counts.
- A bounded `file_patch PATH OFFSET EXPECTED_HEX REPLACEMENT_HEX` program:
  strict CLI and hex validation before opening; equal nonempty byte lengths,
  at most 4096 bytes; exact positional read/compare before any write; bounded
  positional write; explicit errors/cleanup. Mismatch leaves the file unchanged.
  Matching and replacement are not atomic, and write failure may leave a prefix.
  It must not claim concurrent compare-and-swap or crash durability.
- Focused existing core stream and file operations regressions; guides/reference
  match executable evidence, with targets and remaining dependencies explicit.

Portable traits/helpers contain no host dependency. Native evidence is Linux
x86_64 executable output produced by the GPU compiler; it is not GPU device
execution. Missing compiler support gets a minimal reproduction, not a compiler
patch in this library increment. The whole library goal remains open.
