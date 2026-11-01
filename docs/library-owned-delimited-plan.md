# Bounded owned delimiter and line input

## Scope

Add complete owned record input to `alloc::io` over the canonical
`core::io::BufRead` protocol. Reuse `ReadLimits`, `ReadError`, the existing
geometric Vec reservation helper and validated zero-copy Vec/String transfer.
Do not add a second reader/buffer protocol, compiler changes or host services.
The whole-input collector and caller-buffer delimiter helpers keep their own
contracts. No cryptographic work belongs here.

The old `std::io_line` helper executes, but its storage cap does not bound its
overlong-line drain or retain exact consumption progress. It still has 23
sample consumers. Migrate the owned UTF-8 and recent-i32 samples in this
increment. Remaining consumers and retirement of the old helper remain work;
do not introduce a compatibility bridge through i32 byte storage.

## Fixed public surface

All new declarations are in `alloc::io`:

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

Each returned record has `borrow()->&Self` and `destroy()`; destruction releases
only its Vec/String allocation and preserves historical ending/call/consumption
facts. Copies alias one cleanup authority. Fields describe state, not authority
to mutate or forge owners. Keep borrowed provider/backing and aliases valid.

`ReadLimits` defaults remain 16 MiB and 65,536 calls. max_bytes bounds the
complete stored record **including** its delimiter. Calls count actual public
fill_buf and consume delegations separately, including EOF, errors and
Interrupted. They do not count a buffered provider's internal Read calls.
No wall-clock or underlying read-ahead bound follows from these quotas.

`read_until` includes the first delimiter and leaves every later buffered byte
unconsumed. An empty successful fill ends with Eof; a nonempty final
unterminated record is also Eof. Empty Eof means no record, while an empty
LF-terminated line contains one LF byte. A delimiter is any u8, including NUL.

`read_line` selects LF and preserves LF and any preceding CR in its String.
It does not trim, strip CR, normalize or reject NUL. It validates UTF-8 only
after a terminal LF or EOF, then transfers the same byte allocation into String.
Malformed terminal text retains the entire raw record in the failure.

## State and failure order

Use one owned binary engine for both public functions:

1. Negative max_bytes -> InvalidLimits, empty owner, zero calls, no provider
   operation or allocation. Zero calls -> CallLimit before fill/allocation.
2. Charge before each fill. Retry Interrupted from fill only, spending quota.
   Other errors -> Io with prior retained bytes and confirmed consumption.
3. Admit all View start/length/sum metadata before backing access, even if
   empty or the consume quota is unavailable. Invalid metadata -> Io(InvalidCount).
4. Empty fill -> Eof before byte-limit/consume checks. Therefore a zero byte
   cap can accept an observed empty EOF, and an exact-fit record can accept EOF.
5. Nonempty fill with no byte room -> ByteLimit. Do not inspect any backing
   byte, allocate, consume, drain or store an extra byte. Read-ahead may already
   have occurred in fill; buffered pending data remains available.
6. Require quota for consume before scanning, reserving or copying. A final
   nonempty fill can spend the last call and fail CallLimit with no new copied
   or acknowledged bytes.
7. Scan at most min(available.length, remaining byte room), ending at the first
   delimiter. Reserve the complete selected append before copy or consumption,
   using capped geometric growth. Storage error preserves prior bytes and
   leaves this buffered chunk unconsumed. No allocation occurs in consume.
8. Copy selected bytes while the fill view is live; end that borrow, charge
   consume, then request exactly selected. Do not use the fill view afterward.
9. Exact consume success advances consumed. Err (including Interrupted) is
   never retried, acknowledges none and retains the staged bytes. A successful
   count unequal to selected -> Io(InvalidCount); a nonconforming provider's
   actual state is unspecified. Record only earlier exact acknowledgements.
10. A found delimiter ends immediately without an additional fill. Otherwise
    repeat, including an extra fill at the byte cap to distinguish EOF from
    pending data. There is no overlong-record drain or consumed cap probe.

Success has consumed == original byte length. Failure has consumed <= retained
byte length: bytes copied before a rejected/invalid consume remain retained,
although their consumption was not acknowledged. `ending` is None for binary
engine failures and Some(Delimiter/Eof) only for terminal UTF-8 adoption errors.
Source/work/storage failures precede malformed text in an incomplete prefix.
Recover/release retained owners explicitly; do not concatenate an unacknowledged
suffix with resumed input as though it had been consumed. Physical traps have
no rollback guarantee. Callback reentrancy and invalid backing are preconditions.

## Consumers and acceptance

A new `line_report [--text] [--max-bytes N]` program uses both APIs and the
canonical buffered stdin provider. Emit staged fully quoted CRLF CSV with
`record,bytes,scalars,ending`. Record positions are zero-based; byte/scalar
counts include LF and CR. Binary scalar fields are empty. Endings are `lf`/`eof`.
An empty EOF emits no row; empty stdin emits only the header.

The default record cap is 65,536 bytes; N is 0..1,048,576. Total logical input
is capped at 4 MiB and each next record receives min(record cap, remaining total).
Limit fill/consume delegations to 131,072 total, passing the actual remaining
quota between records. At most 16,384 nonempty records and 1 MiB staged output.
Use one 1024-byte buffered stdin owner. Ignore SIGPIPE, stage before publication,
release record/provider/argument owners on every normal/error path, preserve
primary status, and bound output/diagnostic attempts. CLI/data/limits ->2,
input host ->3, allocation ->4, output/signal ->5, internal contract ->6;
success/help ->0. The app author fixes exact help/diagnostic/CLI policy with its
test author before native acceptance.

Migrate `sample_programs/utf8_owned_line.lani` and `recent_i32_lines.lani`
directly to the public collector and buffered provider, retaining their ordinary
output and documented status policy. Strip one terminal LF only at those
application boundaries. Preserve the old payload caps (12/20 bytes) by admitting
one additional LF byte and explicitly rejecting excess payload. UTF-8 ownership
must transfer without the old i32/u8 copy bridge. No old helper wrapper or broad
unrelated sample rewrite.

Require actual native admission, direct scripts with exact fill/consume order,
call/byte boundary and malformed metadata cases, retained/unacknowledged failure
bytes, UTF-8 terminal precedence and backing identity, independent model/state
comparisons, reached allocation failures with exact cleanup and no failed-reserve
consumption, and guarded/large buffered records. Run the real app through normal,
edge, exact-cap, actual EOF/I/O/owner/CLI/publication failures and the two migrated
sample regressions. Old whole-input and fixed-delimiter regressions are separate.

Root alone runs compiler/Cargo/native commands serially under the library lock;
every command is below two minutes. Agents use bounded CPU/static controls.
Initial supported evidence is native Linux x86_64 CPU output from the GPU
compiler. User GPU execution, other targets, automatic ownership and formal
verification need separate support. The complete standard/extended-library
goal remains open.
