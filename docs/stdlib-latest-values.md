# Latest values with displaced history

Status: implemented; all four direct model, bounds, reached-OOM and I/O
campaigns pass on the native Linux x86_64 profile below. The full library goal
remains open. The program uses canonical TreeMap replacement and the shared
[replacement transfer](library-replacement-sinks-plan.md) with an existing
TrySink history collector.

## Record and output grammar

`latest_values [OPTION N ...]` reads UTF-8 stdin. Each physical LF-delimited row
contains exactly one TAB: `key<TAB>value`. Keys are nonempty; values can be
empty. A final row may omit LF, and a trailing LF adds no phantom row. Empty
input has zero rows. Blank rows, extra/missing TABs, malformed UTF-8, C0 bytes
other than TAB/LF, and DEL reject. In particular CRLF, NUL and embedded field
TAB/LF are unsupported. Spaces and valid multibyte UTF-8 remain ordinary field
content. There is no trimming, normalization, quoting or escape syntax.

Repeated keys compare by exact UTF-8 bytes. Every update stores the new owned
key and value and returns the complete previous key/value owner. Successful
stdout first lists displaced entries in update order, then the latest snapshot
sorted by UTF-8 key bytes:

```text
old<TAB>key<TAB>old-value<LF>
new<TAB>key<TAB>latest-value<LF>
```

There are no section headers. Empty input produces no output. Every input
entry appears once across history and final snapshot. All normal output is
staged before delivery; a processing failure publishes no normal stdout.
Host delivery failure can expose an actual accepted prefix.

## Command bounds

Optional unsigned-decimal pairs occur at most once. `--help` must appear alone.
Unknown, duplicate, missing, signed or over-limit values reject before stdin.
Argument snapshots admit 16 selected arguments and 1,024 bytes, excluding
argv[0] and trailing NULs.

| Option | Default | Maximum |
| --- | --- | --- |
| `--input-bytes` | 262,144 | 2,097,152 |
| `--rows` | 1,024 | 4,096 |
| `--key-bytes` | 1,024 | 4,096 |
| `--value-bytes` | 4,096 | 65,536 |
| `--history` | 1,024 | 4,096 |
| `--output-bytes` | 524,288 | 4,194,304 |
| `--read-calls` | 4,096 | 65,536 |
| `--write-calls` | 4,096 | 65,536 |

Zero is allowed. A zero key cap admits empty input but no row; zero history
admits distinct-key insertion but rejects the first displaced entry after its
replacement has committed. Read calls include interruptions and EOF, with a
one-byte probe at an exact byte cap. Empty input still needs an EOF read.
Host attempts transfer at most 1,024 bytes. EINTR alone retries under the call
allowance. Empty normal output needs no stdout calls. A checked SIGPIPE-ignore
policy precedes all allocation/output; failed installation returns without
writing.

## Replacement failure and cleanup

Input is validated before constructing independent String keys/values and an
owned Entry vector. Its owning cursor transfers entries to
`TreeMap<String,String>` through `try_replace_up_to`. A bounded history Vec
uses the existing TrySink contract: quota/allocation failure rejects the old
entry before retaining it.

- `Rejected` returns the uncommitted incoming entry; the map retains its prior
  state. The app releases that entry and the unconsumed source remainder.
- `Undelivered` returns the displaced old entry. The current new entry already
  belongs to the map; progress includes that commit and displacement. The app
  does not repeat or roll back the replacement.

For Undelivered, a bounded best-effort stderr record reports progress and the
old/current fields while both owners remain live, before cleanup:
`undelivered<TAB>committed<TAB>replaced<TAB>remaining<TAB>old-key<TAB>old-value<TAB>current-key<TAB>current-value<LF>`.
This diagnostic is not normal stdout and cannot guarantee delivery if stderr
also fails. A history-limit test must witness the known new value still stored
at this point. Every current/remaining/failure entry releases both String fields
exactly once; the cursor backing, map, history, input, output and arguments are
explicit owners with no implicit Drop. Error payloads are scalar metadata.

Exit 0 is success/help; 2 is argument/record/UTF-8 or explicit resource limits;
3 is host/progress/ownership failure; 4 is source allocation failure. Secondary
diagnostic delivery does not replace a primary failure. There is no rollback,
database persistence, concurrent writer or implicit destruction promise.

The input owner is released after independent String entries are built. One
owner for each complete row resides in the map, accepted history, failure item
or unconsumed input cursor. Map and history grow through their canonical
fallible operations; the collector's logical quota can be smaller than its
reserved Vec capacity. Output reserves its configured byte bound, then drains
and releases history/map entries through owning cursors before host delivery.
No traversal or report scratch allocation is introduced. For bounded input B
and rows R, String payload reservations total at most `B+8R`; entry/map/history
storage is additionally bounded by R and their documented element layouts and
growth rules. The input and output reservations do not overlap. Argument bytes
are at most 1,024 plus 16 view entries. These are explicit library-owner bounds,
not process RSS, native/kernel memory or host-call duration bounds.

The Undelivered report has a shared 256-write-attempt bound, including EINTR
and partial progress; each attempt is at most 1,024 bytes. A final generic
diagnostic makes at most one more stderr attempt after owner cleanup. Report
failure never skips cleanup or changes the primary limit/allocation status.

## Current executable receipts

`sample_programs/library/latest_values.lani` is source-frozen at SHA-256
`62fce749...`. Its first corrected compile passes
(`target/stdlib-work/replacement-latest-values-expression-arms.log`). Two direct
native cases pass in `replacement-latest-values-admission-native-first.log`:
four rows produce the exact displaced `b/1` entry and sorted `a/b/c` snapshot;
history quota zero returns 2 with no normal stdout, reporting the third commit,
new `b/2`, old `b/1` and one unconsumed row. Those are narrow composition
admissions; their overlapping behavior is not added to the campaign counts.

The following direct Python oracle invocations reuse that retained native ELF;
they are not receipts for four passing Rust libtests. Logs are under
`target/stdlib-work/`.

The registered app and ownership Rust drivers build together in 3.42 seconds
(`replacement-app-owner-driver-build-first.log`, `--no-run`); this is build
admission only.

| Group | Process invocations | Receipt and scope |
| --- | --- | --- |
| Models | 136 | `replacement-latest-values-models-first.log`; eight authored and 128 seeded cases |
| Bounds | 61 | `replacement-latest-values-bounds-live-order-retry.log`; strengthened causal owner-lifetime witness |
| Allocations | 34 | `replacement-latest-values-allocations-first.log`; one baseline and all 33 reached source ENOMEM positions |
| I/O faults | 17 | `replacement-latest-values-faults-first.log`; interruptions, count/call errors, real EPIPE, confirmed prefixes and failed diagnostic delivery |

These are 248 process group cases across separate invocations, with overlapping
baselines and behavior. They are not 248 independent properties. The earlier
61-case bounds invocation is repeated coverage and is not added again.

Independent review found that the original bounds witness could accept an
owner allocated after the record, provided its release followed the record.
The corrected oracle binds each trusted allocation ordinal to its original
full-trace mmap, including instruction address, arguments and result. Each
witness must be allocated before the first actual positive diagnostic write
and released after the complete record. The source and retained ELF are
unchanged. Current oracle SHA-256: `2806ad3a...`; the strengthened 61-case bounds
rerun passes. The original `replacement-latest-values-bounds-first.log` is
retained as the earlier, weaker witness receipt.

The initial source used unsupported block expressions in match arms and failed
before ELF emission (`replacement-latest-values-admission-first.log`). Moving
those side effects into helper calls preserves the owner/error order. This
was an application syntax correction, not a compiler bug or API narrowing.

Independent byte/UTF-8 dictionary models check complete old owners in
update order and a sorted latest snapshot, empty values, multibyte keys and
strict invalid-input rejection. Exact/over limits, causal history rejection,
all reached source/map/history/output OOMs and real EPIPE/partial-prefix I/O
use the existing verified full-width source ledger. The causal history-zero
fixture requires old/current and unconsumed-remainder owners to exist before
reporting begins, remain live through the complete record and release before
the traced exit.
This app has no ACK or live `/proc` checkpoint; direct owner fixtures provide
that separately. Twenty-six CPU oracle controls pass, including negative
traces with an owner allocated during or after the diagnostic, release during
a partial diagnostic, and an allocation ordinal bound to a different owner.

### One larger native observation

The same accepted ELF processes 4,096 rows with 512 distinct keys, producing
3,584 displaced-history entries and 512 sorted snapshot entries: 49,152 input
bytes and 65,536 output bytes. One untraced process takes 0.087919031 seconds,
including launch, stdin, validation, String allocation, map replacement,
history, staging and stdout capture. The exact expected output was prepared
before timing and validated afterward. Arguments were `--rows 4096 --history
4096 --input-bytes 2097152 --output-bytes 4194304`.

Receipt: `target/stdlib-work/replacement-latest-values-scale-first.log`;
evidence: `/tmp/latest-values-scale-o1plx38m`. This single sample measures no
source allocation or RSS count, establishes no general speed ratio or compiler
benchmark, and adds no case to the 248-case campaign count.

The first native target is Linux x86_64 CPU code emitted by the GPU compiler;
no user GPU-kernel, other-host or general performance support is claimed.
See [the focused driver](../tests/stdlib_latest_values_execution.rs) and
[fixture guide](../tests/fixtures/stdlib_execution/latest_values/README.md).
