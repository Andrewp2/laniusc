# Reader adapter ownership and composition

These producers exercise `core::io::Take` and `Chain` around existing
`alloc::buffered` readers and `alloc::io` consumers. The driver is
`tests/stdlib_io_adapters_resource_execution.rs`. It requires Linux x86_64
ELF output and shared jump validation before native execution. Root owns
all compiler and native commands, run serially under the library lock.

## Buffered ownership

`composition.lani` creates two packed input owners and two real buffered
readers. A local `Chain<Take<Reader>, Reader>` mixes fill, consume and read
calls, retains the first reader's unread bytes beyond the Take quota, and
commits the handoff even if Take's quota is subsequently reopened. Every
destination guard is checked. The adapter construction and these operations
run between markers that prohibit allocation, release or other host work.

After those adapters retire, a second composition feeds the existing owned
delimiter consumer. The result crosses the first/second boundary and is
exactly `[7,8,133,134,135]`; the consumer acknowledges six protocol calls and
five consumed bytes. Remaining buffered bytes stay with their original
owners. Both buffers are then explicitly discarded, both underlying cursors
are reused, and every input byte remains unchanged. The collected result is
checked again after source backing is destroyed. Only the two input owners,
two fixed buffers and three consumer growth allocations are expected.

Selector:

```text
io_adapters_preserve_real_buffered_suffixes_and_caller_owned_sources
```

## Binary collection and reached allocation failures

`collection.lani` uses 327,692 binary bytes covering all 256 byte values.
Normal vectors hold the input; it creates no large stack arrays. Buffered
source capacities are 4,093 and 2,053. Their chain feeds a Take quota of
300,007, an outer buffer of 3,079 bytes and the existing bounded whole-input
consumer. These deliberately different boundaries exercise short transfers
and retained buffered state.

At quota exhaustion, the second source has prefetched 1,309 additional bytes.
After the outer reader and adapters retire, the original second buffered
reader supplies the remaining 27,685 bytes, starting with that retained
suffix. Both original source cursors remain usable after buffer release.
Every input byte is checked before destruction; the retained and collected
results are checked afterward. The host compares all 327,692 emitted bytes
in order, including NUL and high bytes.

The driver records one successful baseline, then derives four fault ordinals
from its observed allocations: construction of the new nested outer reader,
plus first, middle and final whole-input growth. Each fault must be a reached
injected ENOMEM with the same preceding normalized syscall sequence as the
baseline. Construction failure leaves the borrowed adapters reusable.
Collection failure preserves its owned prefix and the same live adapter's
quota and buffered remainder; recovery continues without rewinding or
recreating that adapter. The error-owned prefix stays live through recovery.

The full syscall ledger requires exact address/extent releases, rejects
overlapping live owners, duplicate/unknown releases and unexpected host
services, and checks precisely which owners survive each operation. Pure
observation phases prohibit allocation and cleanup. Every owner must retire
before the final marker; process exit is not cleanup evidence. No source
close or implicit adapter cleanup is accepted.

Selector:

```text
io_adapters_large_binary_collection_and_reached_allocations_preserve_exact_prefixes
```

## Evidence

Both focused native tests passed in 9.97 seconds, following a separate
1.87-second Rust build. The local receipt is
`target/stdlib-work/io-adapters-resources-first.log`.

The small composition returned all five expected delimiter bytes, with
seven pure phases and seven successful allocations matched by seven exact
releases. The large baseline returned all 327,692 expected bytes, retained
the 1,309-byte prefetched suffix at quota exhaustion and matched all 21
successful allocations with exact releases.

All four selected ENOMEM failures were reached and recovered the full byte
stream in the same process:

| Reached baseline mmap | Failure site | Retained error prefix | Successful allocations / exact releases |
| ---: | --- | ---: | ---: |
| 5 | Nested outer reader construction | 0 | 21 / 21 |
| 6 | First collection reservation | 0 | 21 / 21 |
| 10 | Middle collection growth | 7,172 | 25 / 25 |
| 15 | Final collection growth | 261,280 | 27 / 27 |

These ordinals identify the observed baseline; the driver derives them from
that trace on each run. All output bytes, retained owner contents, quota
accounting and source reuse checks passed. The test duration includes
compilation and traced native execution and is not a performance benchmark.

Bounded host controls checked the full binary pattern, six split/rejoin
identities, all 256 byte values, the small delimiter result, the 1,309-byte
prefetch calculation and the expected 21 successful baseline allocations.
Those controls validate fixture expectations; they are not native cases.

Accepted scope is native Linux x86_64 CPU output of the GPU
compiler. Other targets, user GPU execution, automatic lifetime safety,
formal verification and performance claims require separate evidence.
