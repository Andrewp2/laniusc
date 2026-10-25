# Native raw host widths and allocation contracts

The native x86_64 Linux host thunks preserve the full 64-bit `usize` arguments
declared by the source APIs. This applies to allocation sizes, descriptor and
stdio counts, argument/environment copy capacities, environment key lengths,
and clock/current-directory output capacities. Results and indices declared
`i32` keep that domain. This repair adds no service or public name and changes
no IR or formal semantics.

## Allocation and manual ownership

`alloc::allocator::alloc(size, align)` accepts a nonzero size and alignment
**1, 2, 4 or 8**. Unsupported alignment (including a high-word value whose low
bits look supported), zero alignment, and zero size return null before mmap.
Size arithmetic must be checked by the caller before supplying a value.
The entire supplied size reaches mmap; it is never reduced modulo 2^32.

Initial allocation uses `MAP_PRIVATE | MAP_ANONYMOUS` and read/write
protection, without `MAP_32BIT`, which capped a process at 1 GiB of mappings.
Full size transport does not promise that a large allocation succeeds. Null denotes failure.

For `realloc(pointer, old_size, new_size, align)`, the caller must exclusively
own the live mapping base, with its matching nonzero old size and alignment.
An interior, stale, borrowed, null, multiply-owned or unrelated pointer is not
a valid owner. The thunk rejects null pointers, zero old/new sizes and every
alignment outside 1/2/4/8 with null before mremap. It does not verify that a
nonzero pointer actually owns the described mapping.

On null, the original mapping, owner and views remain live. On success,
retire the old pointer and every old view, use the returned pointer, and record
the new size. Reallocation uses `mremap(MREMAP_MAYMOVE)`: a successful moved
mapping is **not promised to remain below 2 GiB**. Native pointer transport is
full width. Requested alignment remains satisfied for this supported profile.

`dealloc(pointer, size, align)` requires the sole live mapping base and matching
nonzero size/alignment. Do not release interiors, stale aliases, borrowed,
null or zero-size owners. It forwards the full size to munmap. The signature
is void and exposes no munmap failure status; it is not a checked release API.
The ownership contract still requires retiring the owner and all views once
deallocation is attempted. There are no automatic destructors or deep moves.
The runtime does not track allocations or validate matching sizes/alignment.

## I/O counts and fixed-size outputs

Raw `std::io::{write_stdout,write_stderr,read_stdin}` forwards all count bits,
matching `std::fs::{read,write}`. `std::random::fill_secure_bytes` also retains
its existing full-count behavior. The raw syscall result remains the declared
`i32`; Linux may accept a shorter transfer than the request. A successful call
does not promise full delivery. Recoverable errno, EINTR, short progress and
completed-prefix policies belong to the checked source wrappers.

These raw pointer APIs do not establish memory safety: provide valid live
storage for every byte actually accessed, obey the API's backing contract,
and keep it alive throughout the call. A count is not a proof of allocation.
Checked source adapters continue to impose their existing `i32` logical limits.

`std::time::{monotonic_read,system_read}` compares the full unsigned capacity
against 16 before writing a fixed 16-byte timespec. Capacities below 16 fail
without a syscall. `std::env::current_dir_read` tests the entire capacity for
zero and forwards the original full value to getcwd. Zero fails without a
syscall. Its existing raw policy still normalizes any host failure to -1;
clock reads retain their existing negative host result. Wide capacity support
does not change those failure policies or validate physical backing.

## Startup arguments and environment

Argument and environment copy helpers preserve the complete capacity bound,
but stop at the finite startup string's NUL (or at `=` for a key copy).
Actual copied counts and argument/environment entry indices remain `i32`.
The runtime reads the retained original Linux process startup state; it does
not widen result counters into an unbounded caller-directed scan.

`std::env::{var_len,var_read}` compares the full supplied key length. When
matching an entry, it checks the current environment name byte for NUL or
`=` before reading the corresponding caller key byte. Reaching either before
the full key length rejects that entry. Only an `=` exactly after the complete
key matches. Thus `2^32 + 3` cannot alias a three-byte key, and a huge declared
length cannot scan past the finite environment name into its value or another
entry. Caller-provided key/output storage and retained startup state must stay
valid; the raw API has no general pointer validator.

## Byte tables and evidence

Readable assembly for the changed thunks is
`shaders/codegen/lir/x86/runtime_raw_width.s`. The matching arrays remain in
`runtime_abi.slang`; `raw_host_width_tables.py` assembles and compares them,
checks contiguous offsets/total size, and independently assembles the unchanged
path and Linux syscall blocks, including every embedded path entry symbol.
The runtime block is now 2,095 bytes; the path block begins at 1,644, assertion
at 2,056 and six-word Linux bridge at 2,063. Local branch displacements are
assembler-generated. Existing service IDs and public interfaces are unchanged.

Runtime emission uses the final checked layout's runtime length. A private
one-lane GPU pass validates its status and runtime range, replaces all three
indirect dispatch words, and schedules 256-thread groups over that length.
It runs after object status normalization and immediately before emission.
Invalid layouts publish a zero-work dispatch, including when reusing a
previously valid dispatch buffer. The graph records the storage-write and
indirect-read dependency. This replaces the former fixed 2,048-byte dispatch,
which left the enlarged runtime's last 47 bytes zero despite correct tables.
The emitted ELF is compared against every literal runtime byte before the
native execution gate; a successful early allocation call alone cannot show
that the assertion and Linux bridge at the runtime's end were emitted.
The focused GPU regression compares all bytes at lengths 2,048, 2,049 and
2,095, including misaligned packed-word boundaries and untouched prefix/suffix
canaries. It also reuses dispatch storage across valid, empty and invalid
layouts. Large-length arithmetic checks run only the one-lane producer, with
no large backing allocation or runtime-byte dispatch.

Focused native fixtures execute GPU-compiled x86_64 Linux Lanius:

- A retained pre-repair trace showed `alloc(2^32 + 4096,8)` sending only 4,096
  to mmap under injected ENOMEM. The same admission must send the full size.
- Synthetic ENOMEM/EIO tests inspect raw syscall arguments for small controls,
  `i32::MAX + 1`, `2^32`, `2^32 + 4096`, the high unsigned bit and `usize::MAX`.
  They cover mmap/mremap/munmap, stdio, descriptor I/O and entropy. Errors are
  injected before any oversized allocation or sentinel-buffer access.
- Clock/cwd capacity tests inject EIO after full-width validation; invalid
  small capacities make no syscall. These test validation/transport, not a
  successful huge output buffer.
- Short controlled argument/environment strings and canaried destinations
  test ordinary and synthetic high capacities. A three-byte key immediately
  before an unreadable page tests both key lookup operations with huge lengths.
  A test-only Python execve launcher supplies an entry without `=` to exercise
  the NUL boundary independently of the normal delimiter boundary.
  These are bounded ABI/comparison probes, not physically huge allocations.
- Small real allocation/reallocation/release and failed-validation owner
  controls exercise each supported alignment, rejected low and high-word
  alignments, zero size, binary stdio, actual 16-byte clocks and neighboring
  formatting/path/random/process/syscall entries after offset relocation.

No GB backing allocation or successful huge-buffer claim is part of this gate.
The scope is native Linux, with the existing low-level ownership and backing
preconditions. Wasm, general FFI and composable-artifact runtime linking are
separate contracts.
