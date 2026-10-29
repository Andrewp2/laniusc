# Bounded owned delimiter and line input

The [increment contract](library-owned-delimited-plan.md) adds owned records to
[alloc::io](../stdlib/alloc/io.lani) over canonical core::io::BufRead. Both
functions share one binary engine and existing Vec growth/String transfer
operations. All eight registered library tests, all 131 application cases,
both sample migrations and two selected older regressions pass on the finite
native Linux x86_64 profile. The full library goal stays open.

## API and existing helpers

```text
ReadEnding = Delimiter | Eof
ReadBytes { bytes:Vec<u8>, ending:ReadEnding, calls:u64, consumed:u64 }
ReadLine { text:String, ending:ReadEnding, calls:u64, consumed:u64 }
BufferedReadFailure {
    cause:ReadError, bytes:Vec<u8>, calls:u64, consumed:u64,
    ending:Option<ReadEnding>
}
read_until<B>(&B, delimiter:u8, limits:ReadLimits)
    -> Result<ReadBytes,BufferedReadFailure> where B:BufRead
read_line<B>(&B, limits:ReadLimits)
    -> Result<ReadLine,BufferedReadFailure> where B:BufRead
```

The shared ReadLimits/ReadError types and default_read_limits retain the
[whole-input contract](stdlib-owned-input.md): defaults are 16 MiB and 65,536
calls. These new functions require **only BufRead**; Read/Seek/Write are separate
protocols. The [core caller-buffer helpers](stdlib-delimited-io.md) remain
allocation-free and have a successful Limit ending. These owned functions
instead report ByteLimit when a nonempty fill cannot fit more record bytes.
They neither close nor flush nor own the provider.

[Rust BufRead read_until/read_line](https://doc.rust-lang.org/std/io/trait.BufRead.html#method.read_until)
retain the delimiter/LF and validate line UTF-8. Here the result is a fresh
owned record instead of an append to caller storage, with finite actual
fill/consume quotas, a non-draining byte-cap peek and retained raw bytes plus
separate consumption acknowledgements. The plan defines those deliberate
Lanius differences.

ReadBytes, ReadLine and BufferedReadFailure each expose borrow()->&Self and
destroy(). Destruction releases only the retained Vec/String allocation and
leaves historical ending/call/consumption facts intact. Repeated destruction of
an emptied owner is valid. Copies are shallow aliases, not new cleanup rights;
public fields describe state rather than permission to forge or mutate owners.

## Records, endings and budgets

read_until includes the first delimiter, which can be any u8 including NUL.
Every later buffered byte remains logically unread. Empty successful fill means
Eof, with or without an already collected unterminated prefix. Empty Eof means
no record; a record containing only LF has one byte and Delimiter ending.

read_line selects LF, preserves that LF and any preceding CR, and permits NUL.
It performs no trimming, CR stripping, normalization or lossy replacement.
Strict UTF-8 validation runs only after terminal LF/EOF; success transfers the
same allocation into String without a byte copy or second text allocation.

max_bytes includes the delimiter. max_calls counts actual public fill_buf and
consume delegations separately, including EOF, errors and Interrupted. Charge
before each delegation and check before incrementing. Calls do not count a
buffered provider's internal Read/host calls or impose a duration/read-ahead
bound. Limits apply to one collection call; a multi-record caller must pass
its actual remaining allowance to impose a total quota. A fill may already have
read ahead even if no consume quota remains.

## Exact operation and failure order

1. Negative max_bytes returns InvalidLimits before allocation/delegation. A zero
   call budget returns CallLimit before fill/allocation, including at EOF.
2. Charge fill before calling it. Retry only Interrupted from fill, against the
   same quota. Other fill errors preserve prior bytes and consumption as Io.
3. Admit the returned View start/length/nonoverflowing sum before backing reads,
   EOF or consume-quota checks, even for empty Views. Malformed metadata gives
   Io(InvalidCount); logical checks still do not prove physical backing.
4. A valid empty fill returns Eof before byte-limit checks. Thus zero byte cap
   can accept observed empty EOF, and an exact-fit record can finish at EOF.
5. A nonempty fill with no byte room gives ByteLimit, without inspecting any
   backing byte, allocating, consuming, draining or storing an extra byte.
   Buffered pending data remains available.
6. Require consume quota before scanning, reserving or copying. A nonempty fill
   may spend the last call and fail CallLimit without new copied/consumed bytes.
7. Scan at most min(available.length, remaining room), stopping at the first
   delimiter. Reserve the complete selected append using capped geometric Vec
   growth before copying/consuming. Storage failure leaves this chunk unread.
8. Copy while the fill View is live. End that borrow, charge consume and request
   exactly the selected count; never use that View afterward.
9. Exact consume success advances consumed. Any Err, including Interrupted,
   acknowledges none and is never retried. A nonexact successful count gives
   Io(InvalidCount) and records only earlier exact acknowledgements; that broken
   provider's actual state is unspecified.
10. A found delimiter returns immediately, without another fill. Otherwise repeat,
    including a fill at the byte cap to distinguish EOF from pending data. There
    is no overlong-record drain or consumed cap probe.

## Retained and unacknowledged bytes

At return, success.consumed equals the original stored byte length. Failure has
consumed <= bytes.len(): staged bytes copied before a consume error remain in
its owned Vec even though their consumption was not acknowledged. Earlier
confirmed prefixes are never discarded. No rollback of provider state follows.

For example, copying three bytes then receiving consume Err returns retained
length 3 and consumed 0. A conforming provider still exposes those three bytes.
Do not concatenate that unacknowledged suffix with resumed input as if it had
been consumed. A nonconforming successful count cannot establish safe replay.
Recover or release the retained owner explicitly.

Failure.ending is None for binary engine errors. Only terminal UTF-8 adoption
failure has Some(Delimiter/Eof), preserving the entire raw record and its actual
calls/consumed facts. Incomplete-prefix source, quota or storage failure wins
over malformed UTF-8. Multibyte sequences can span fills normally.

Providers must keep filled bytes physically valid and read-only until consume.
End Views before provider mutation; keep provider/backing alive and aliases
inactive. Concurrent or reentrant mutation is outside the contract. Private
owned bytes are disjoint from provider backing; no spare uninitialized capacity
is exposed or Vec owner fields rewritten. Physical traps have no rollback.
There is no automatic move/drop, lifetime enforcement or formal proof claim.

## Applications and legacy scope

The [line_report program](stdlib-line-report.md) uses a 1024-byte buffered stdin
provider and both public helpers, staging quoted CRLF CSV records before
stdout. It caps record bytes, total logical input, record count, protocol calls
and output; its separate guide owns the exact CLI/publication policy. Five
application groups pass 131 cases across separate receipts.

The audit found 23 sample consumers of executable std::io_line. Its storage
cap does not bound overlong-line draining or preserve exact consumption
progress. Two samples now migrate directly; source scanning confirms **21**
remaining consumers. The helper is unchanged, with retirement still open.

- [utf8_owned_line](../sample_programs/utf8_owned_line.lani) uses read_line with
  13 stored bytes and 64 fill/consume calls.
  It strips one terminal LF at the application boundary, retaining CR/NUL and
  a 12-byte payload cap. A 13-byte unterminated payload is status 2 even for a
  terminal text failure; admissible malformed text remains status 3. Empty EOF
  is status 2 while an empty LF line succeeds. String cleanup authority transfers
  directly from the record, without the old i32/u8/String copy bridge.
- [recent_i32_lines](../sample_programs/recent_i32_lines.lani) uses binary
  read_until(LF), 21 stored bytes and a shared
  65,536-call allowance across records. After stripping LF, it enforces the
  20-byte payload cap and parses owned u8 bytes directly. Ordinary output and
  status policy are preserved; empty stdin still succeeds with LF.

Both borrow stdin through a 1024-byte buffered provider and explicitly discard
its buffer on every terminal path, without closing stdin. Read-ahead can fetch
that host chunk; overlong records are not logically drained, and pending data
is discarded when these applications terminate. Record/failure/provider and
other owners retire explicitly. No compatibility wrapper or unrelated sample
rewrite is introduced. Separate UTF-8/recent sample tests pass in 6.86s/7.08s,
with six/nine other tests filtered; their source hashes are e796208f/775d7979.

## Evidence and targets

Current production alloc::io is 9eeb63f4. All eight registered library tests
are accepted across separate commands under target/stdlib-work: seven native
tests and one capability-bound test.

| Receipt | Accepted scope |
| --- | --- |
| owned-delimited-admission-first.log | 1 native generic admission / 6.67s; separate driver build 37.40s |
| owned-delimited-direct-first.log | 1 capability test with two LNC0008 rejections; mixed batch 7.72s also had two pre-native fixture failures |
| owned-delimited-direct-retry.log | 2 corrected native direct tests / 8.82s; admission/capability filtered |
| owned-delimited-model-first.log | 1 test / 7.63s: 15,724 cases / 31,448 invocations, two layouts, payloads <= 32 bytes, seed 0xd3110261104 |
| owned-delimited-resources-first.log | 1 test / 8.38s: four 1 MiB modes, complete bytes/call facts, matched owners and pending NEXT |
| owned-delimited-allocation-failures-first.log | 1 test / 8.33s: seven reached reservation failures, retained bytes/progress and no failed-reserve consumption |
| owned-delimited-guards-first.log | 1 test / 6.16s: nine guarded observations and matched releases |

The first direct batch was not green: two fixtures hit the known payload-
wildcard followed by fallback form before execution. Named binders/typed match
locals fixed only those fixtures; the [minimal reproduction](../tests/fixtures/stdlib_foundation/repro_payload_wildcard.lani)
and [dependency ledger](library-dependencies.md) retain its narrow compiler
scope. Production did not change. The model independently compares bytes,
endings/errors, calls/acknowledgements and pending-buffer resumption; its eight
serialized-output corruption controls are CPU checks, not native coverage counts.
The [direct](../tests/fixtures/stdlib_foundation/owned_delimited/README.md),
[model](../tests/fixtures/stdlib_foundation/owned_delimited_model/README.md) and
[resource](../tests/fixtures/stdlib_foundation/owned_delimited_resources/README.md)
fixture guides retain exact commands and tested identities.

The first application target records four passes and one failure in 12.26s
(owned-delimited-line-report-first.log):
model43, CLI34, rejection33 and I/O19 pass (129 cases). Its quota test stopped
before launching the ELF because host strace rejected an oversized finite
injection range. A separate quota retry passes two cases in 12.82s, four tests
filtered (owned-delimited-line-report-quota-retry.log), completing **131** cases.
The mixed initial target was not a passing five-test command. Only schedules
changed; production and quotas did not. The documented standalone compile and
both binary/text pipelines pass with exact 89/74-byte CRLF output; these overlap
the corpus and add no case count.

Both migrated samples pass separately. Two selected older admission regressions
also pass: whole-input collection in 6.47s, one test filtered
(owned-delimited-whole-input-regression.log), and caller-buffer delimiters in
7.35s, two tests filtered (owned-delimited-fixed-helper-regression.log).
These regressions do not establish the additions; historical receipts retain
their original source/API scopes.

The accepted profile is native Linux x86_64 CPU output from the GPU
compiler, with existing allocator/provider contracts. User-GPU execution,
other targets, automatic ownership and formal verification require separate
support. No compiler, ABI, host service or new module belongs to this increment.
