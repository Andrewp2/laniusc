# Named Unix-stream independent peers

This fixture exercises the public named `std::socket::UnixStream` boundary
against Python AF_UNIX/SOCK_STREAM peers, following the
[Unix-stream plan](../../../../docs/library-unix-stream-plan.md). The Lanius
producer calls the real library; Python is an independent host peer and test
driver. Names and messages use raw bytes throughout, without UTF-8 conversion
or `@` namespace shorthand.

## Finite scenarios

The oracle runs **90 native probes**:

| Family | Native probes |
| --- | ---: |
| Five pathname and eight abstract spellings, in both client/server roles and both address backing layouts | 52 |
| Invalid lengths, mutated borrowed paths, existing names and explicit name-lifetime checks | 36 |
| Actual full-backlog nonblocking connect, pathname and abstract | 2 |

Peer cases cover pathname lengths 1 and 107, ordinary paths, non-UTF-8 bytes
and literal leading `@`. Abstract cases cover empty and one-byte names, length
107, ordinary names, embedded/trailing/multiple NUL bytes and literal `@`.
For embedded/trailing NUL cases, independent listeners hold the truncated
spellings concurrently. A producer that strips significant bytes therefore
cannot quietly use the same address and pass. Empty abstract peers connect to
the exact zero-marker name, distinguishing it from family-only autobind.

Both backing forms use a nonzero start: a native descending-byte array or
packed ascending storage. The producer checks every name-buffer byte and all
surrounding guards after the operation. Each connected exchange verifies a
16-byte binary request, a distinct reversed/XOR response, both half-closes
and EOF. It uses public bounded deadline methods, a single five-second
monotonic deadline per connected workflow and at most 32 calls per transfer
loop. This fixture does not claim the deadline bounds blocking stdin.

Boundary probes reject pathname lengths 0/108 and abstract length 108 through
both bind and connect, in both layouts. Borrowed pathname probes construct a
valid Path, then replace its first/middle/last byte with NUL before bind or
connect. The expected InvalidInput result is checked along with unchanged
directory entries and an empty host listener queue for connect cases.

Existing regular files retain their kind and full contents after refused bind.
Existing pathname and abstract listeners retain a usable endpoint. Pathname
nodes remain sockets after close; a later bind must refuse to overwrite them,
and Python explicitly unlinks them. Successful bind-report probes also create
a fresh Lanius stream after the explicit first close: pathname rebinding must
fail with EADDRINUSE, while abstract rebinding must succeed before process exit.
Python then independently checks abstract reuse and all pathname cleanup.

## Actual full queue

A host-only control was run before source freeze on a private local pathname
listener with `listen(0)`. One nonblocking connection queued successfully;
the next returned EAGAIN(11). That failed candidate had no connected peer
(getpeername returned ENOTCONN/107), while poll(0) reported writable and
SO_ERROR was zero. It was explicitly closed and never retried.

Each runtime backlog case repeats the bounded host setup, retaining every
queued owner and performing no accept before the Lanius attempt. It confirms
EAGAIN plus ENOTCONN and records the current poll result and zero SO_ERROR.
The Lanius nonblocking stream makes one public connect attempt, which must
report WouldBlock rather than acknowledged progress. The failed owner closes;
the host then drains exactly its own previously queued connections. No sleep,
readiness-only success, repeated connect on a failed owner or fabricated host
transfer count is used.

## Protocol and evidence

Each native process receives eight little-endian `u64` header words, then raw
name bytes. Modes select Lanius server/client exchange or a bind/connect result
probe. The server prints `R` only after successful bind/listen; host peers wait
for that pipe byte. Other roles use an already-bound/listening host socket.
Final output is four words for success/error tag, error kind, Host payload and
closed-owner confirmation. Both source-side assertions and the oracle check
exact results, messages, endpoint spelling and cleanup effects.

Python sockets have four-second operation timeouts. Readiness waits have a
six-second bound, each native process a nine-second completion bound, and the
outer Rust oracle an 85-second bound. Children are killed/reaped on failure;
all host socket owners close and all pathname nodes are explicitly removed.
No other process's pathname is unlinked. The temporary directory is private.

Pure CPU framing/vector controls pass. The host controls above are actual
Python/Linux observations.
The registered gate is
`named_unix_streams_preserve_raw_names_boundaries_lifetime_and_failed_connect_status`
in `stdlib_unix_stream_address_execution`, using shared strict x86 ELF checks.
Accepted scope: native Linux x86_64 CPU output from the GPU compiler, tested
local pathname filesystem and Linux abstract namespace. There is no direct GPU,
cross-filesystem, automatic ownership, allocation-trace or formal claim.
Logical forged/null views, syscall injection, socket-pair ownership and
cross-family transport regressions belong to separate contract fixtures.

The first registered native runtime run passed: **one test and all 90 probes
in 6.90 seconds**, comprising 52 peers, 36 boundary/lifetime probes and two
actual full-backlog attempts, across both backing layouts. Both backlog host
controls were writable while unconnected with zero SO_ERROR. The log is
`target/stdlib-work/unix-stream-address-first.log`; its exact summary is
`unix-stream-address cases=90 peers=52 boundaries=36 backlog=2 layouts=2 writable-unconnected-host-controls=2`.
This finite result checks the listed raw name spellings, namespace lengths,
mutation rejection, name-lifetime effects and connect error admission on the
tested local Linux system. It does not establish another Unix platform,
filesystem or untested address/descriptor shape.

Tested SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/std/socket.lani` | `44f6739da9be0aa5d28c97dee2c905bca157e237df91c34a0ee6790909c06ccb` |
| `named.lani` | `de6e9521f1882261d684fb347a3013bcf86eab133de0fa7ef18dceea417793cf` |
| `oracle.py` | `7cd08a1cfa95efce1de135db1117f2b03badb47a3aeeb639fadf6bacd595dadd` |

```sh
python3 -B tests/fixtures/stdlib_foundation/unix_stream_address/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/unix_stream_address/oracle.py /path/to/named
```
