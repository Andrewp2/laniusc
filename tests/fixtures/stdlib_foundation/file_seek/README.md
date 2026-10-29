# Native File Seek contracts

Both registered gates have passed compiler/native acceptance for the finite
Linux x86_64 scope below. Root performed all executable runs.
The production adapter is the `core::io::Seek for std::file::File`
implementation in `std::file_ops`; importing that module selects it. The
existing Linux-specific `seek(offset, Origin)` API remains separate.

The first registered run (`target/stdlib-work/seek-file-first.log`) reported
one pass and one failure: the actual-file/pipe gate passed, while the fault
gate stopped at the driver's empty-stderr
assertion on strace's exact 32-bit compatibility warning for an injected
2^32+7 result. The native trace retained 4294967303 and the producer correctly
reported InvalidCount. The driver now accepts only the exact warning associated
with each scheduled wide result, independently requires that full-width native
trace result, and still rejects all other stderr. Production and both Lanius
fixtures remained unchanged.

The warning-only retry (`target/stdlib-work/seek-file-fault-warning-retry.log`)
then reached raw -4096 and stopped in the trace parser: strace printed its
register bits as unsigned decimal 18446744073709547520. The parser now admits
either an i64 decimal or a u64 decimal and reinterprets the latter's exact
64 bits as i64; malformed or out-of-u64 values still reject. This is a second
fixture-formatting correction. The exact injected register assertion and
producer InvalidCount expectation remain unchanged.

The final fault-only retry
(`target/stdlib-work/seek-file-fault-register-retry.log`) passed one registered
test in 6.19 seconds, with one other test filtered. It completed all
`file-seek schedules=18 genuine=5 reached-injections=13`. This final driver
therefore accepted the complete finite fault corpus; the direct gate's earlier
pass used the same unchanged production and Lanius fixture sources.

The selected existing file-operation regression also passed one registered
test in 7.65 seconds (`target/stdlib-work/seek-existing-file-regression.log`).
That receipt is a focused regression check, not an additional claim about
all filesystems, devices or unrelated library APIs.

| Source | Final SHA-256 |
| --- | --- |
| `stdlib/std/file_ops.lani` | `ba46d7505dff070a53b5c007db0ca880c8398826552eab795d70eb536442662e` |
| `contracts.lani` | `5a323377b41b3127cea143086adac426b1fb15622b9ad2ed4b42010fb8da419a` |
| `fault.lani` | `431cee07c492bce220bb81930a794907e5877bb84c7a33477c0c583c0f3126f0` |
| Fault-tested Rust driver before formatting | `3f2de3d76f137078bf1ba9c6e64a94aef854a7f062150c86f073de9c8f741772` |
| Rust driver after rustfmt only | `e644e32b720a0239116758c8a7086f45025edc960aae5199a64ce3b353a5fc6d` |

## Actual positioning and ownership

`contracts.lani` opens one private 16-byte file supplied by the Rust driver,
duplicates its descriptor, and uses the portable Seek protocol through a
generic helper plus `stream_position` and `rewind`. Binary reads and writes
check nonzero ranges and destination guards. The two descriptors observe the
same open-description cursor. Positive and negative offsets above 2^32 and
the complete i64::MIN bit pattern reach the real lseek boundary.

The fixture seeks beyond EOF without writing there. A later O_APPEND write
after Start(0) must still append at the original EOF. Independent host checks
require the final file length to be exactly 18 and compare all actual bytes;
they check length before reading so an accidental huge extension cannot
trigger a large host allocation. A genuine pipe2 pair is adopted once, both
ends report ESPIPE for seeking, and a subsequent binary pipe transfer proves
the endpoints remain usable.

One P/p interval requires no host calls: live Start targets above i64::MAX
return InvalidInput, while closed owners return Host(9) before target
admission. The D marker follows explicit retirement of every owner. The
driver compares all 19 lseek argument pairs, one explicit duplication and
all five actual descriptor acquisitions/releases. Repeated close calls make
no extra syscall. Its complete syscall allowlist rejects allocation,
synchronization, polling and unexpected services.

## Selected first-call faults

`fault.lani` receives one mode byte and opens the same private file. Each
mode makes one selected portable seek and then a separate Current(0) query
to observe the actual kernel cursor. A 24-byte little-endian report contains
the error/result tag, reported position and observed cursor.

The driver runs **18 schedules**: five genuine baselines and thirteen reached
injections. Baselines cover Start, positive full-width Current, negative End,
and i64::MIN Current/End. Injected EINTR, EAGAIN, EIO and ESPIPE are propagated
without retry. Mismatched Start acknowledgements include zero, eight,
2^32+7 and i64::MAX for a requested Start(7). The 2^32+7 case would expose
truncation before comparison. A raw negative result outside Linux's errno
range is InvalidCount for each origin family.

Injection skips the selected kernel call. Its later cursor observation of
zero therefore describes this fixture's actual skipped-call state, not a
rollback guarantee for arbitrary seek errors. No valid data-transfer count
or descriptor acquisition is fabricated. The independent file length and
contents stay unchanged across every fault schedule. All acquired owners
remain live until one explicit close and are checked against actual trace
events.

Both registered gates require strict x86_64 ELF/jump admission and bounded
eight-second native lifecycles. Intended scope is finite Linux x86_64 CPU
execution produced by the GPU compiler on the tested regular filesystem and
real pipe endpoints. Direct GPU execution, arbitrary devices/filesystems,
automatic ownership and formal correctness are unclaimed. No compiler,
runtime or ABI source is changed.

```text
cargo test --test stdlib_file_seek_execution file_seek_executes_shared_binary_cursors_full_width_offsets_and_unseekable_errors -- --exact
cargo test --test stdlib_file_seek_execution file_seek_selected_faults_preserve_full_width_acknowledgements_and_one_attempt -- --exact
```
