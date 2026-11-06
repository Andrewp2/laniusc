# Borrowed text partition verification

`contracts.lani` checks the public `split_once`, `rsplit_once`, `rmatch_indices`,
`rsplit`, `splitn`, and `rsplitn` contracts. Pairs remain in source left/right
order. Rightward and leftward searches choose different overlapping matches.
Empty delimiters use UTF-8 scalar boundaries. Bounded splits preserve an unsplit
final remainder, return nothing for zero, and return the entire source for one.
Cursor copying, descriptor capture, `Take`, repeated exhaustion, nonzero source
origins, aliases, and unchanged invalid sentinels are checked at runtime.

The same fixture compares `core::search::{find_byte,rfind_byte,find,rfind,count}`
with a finite indexed byte reference over ranges through 37 bytes. Haystack and
needle storage independently use packed ascending bytes or native descending
array slots. It includes empty ranges, single-byte misses, periodic prefixes,
nonzero range and needle origins, and empty needles. These are the two available
publicly constructible byte-slice layouts; no arbitrary-stride descriptor is
forged. No claim is made here for an unexecuted positive stride greater than one.

`noalloc.py` runs the direct native-linked executable with `LANIUS_ALLOC=mmap`
and reuses the current shared native/runtime syscall authority. Any source
allocation or release fails the test. Loader and exact CRT bootstrap mappings
are classified separately; unrecognized executable-image syscall sites fail.
Ten host controls exercise the observer's acceptance and rejection paths.

`model.lani` receives one binary batch and emits both bytes and view metadata.
Its independent Python reference uses Unicode regular expressions, scalar
string reversal for rightmost matches, and UTF-8 prefix offsets. It does not
copy the implementation's byte scanner or reverse a leftmost match list.
The fixed corpus has 873 cases: directional overlap witnesses, Unicode scalar
boundaries, embedded NUL, combining marks, ZWJ, noncharacters, exhaustive short
strings, and seeded varied strings. Limits include zero, one, exact/excess
counts, 2^32, 2^63, and u64::MAX. Four source/needle layout combinations and
read-only aliased needles are exercised. The reference expects 57,204 pulls,
28,934 returned fields, 13,968 copied cursor states, and 1,820 reverse matches.
Every field's start, byte length, bytes, and signed stride are checked, along
with both full backing buffers after traversal.

The negative fixtures independently reject `DoubleEndedIterator` and
`ExactSizeIterator` bounds for each new cursor type. Ordinary forward iteration
executes in the direct/model fixtures; rightmost partitioning is not a promise
of reversible leftmost partitioning or a metadata-only field count.

The integration driver is `tests/stdlib_text_partitions_execution.rs`. Native
execution requires Linux x86_64, the GPU compiler, `python3`, `strace`, and the
shared native authority tools. Each selector can be run separately. Host-only
reference checks need no compiler:

```sh
python3 -I -B tests/fixtures/stdlib_text_partitions/oracle.py controls
python3 -I -B tests/fixtures/stdlib_text_partitions/noalloc.py controls
```

## Accepted execution receipts

The parent test lane accepted these Linux x86_64 runs using the GPU compiler:

| Gate | Accepted result | Test time | Log |
| --- | --- | --- | --- |
| Direct contracts and source-allocation observer | 1 passed; packed and descending storage, zero source allocations/releases | 7.07 s | `text-partitions-direct.log` |
| Independent Unicode model | 1 passed; exact 873-case / 57,204-pull summary above | 4.95 s | `text-partitions-model.log` |
| Cursor capability boundaries | All 8 rejection fixtures passed | 6.45 s | `text-partitions-capabilities.log` |

The final integration-driver build took 9.90 s. The host-only reference controls
passed all 17 checks, and the allocation observer controls passed all 10.
These receipts execute GPU-compiled native programs; they do not claim execution
of the library APIs as GPU compute kernels or coverage of other byte strides.
