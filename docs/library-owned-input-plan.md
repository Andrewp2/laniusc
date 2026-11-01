# Bounded owned input collection

## Purpose and boundary

Add reusable whole-input collection to `alloc::io`. Programs currently repeat
read/Interrupted/EOF/cap/allocation loops. The canonical `core::io::Read`
protocol and existing Vec/String owners already supply the needed mechanisms.
Keep the reader borrowed; collection neither seeks nor flushes nor closes it.
No compiler, ABI, extractor, proof or new host service change belongs here.

## Public contracts

```text
ReadLimits { max_bytes:i32, max_calls:u64 }
ReadError = InvalidLimits | CallLimit | ByteLimit | Io(core::io::Error)
          | Storage(alloc::vec::Error) | Text(alloc::string::Error)
ReadFailure { cause:ReadError, bytes:Vec<u8>, calls:u64, extra:Option<u8> }
default_read_limits() -> ReadLimits
read_to_end<R:Read>(&R, ReadLimits) -> Result<Vec<u8>,ReadFailure>
read_to_string<R:Read>(&R, ReadLimits) -> Result<String,ReadFailure>
ReadFailure::borrow(&self) -> &ReadFailure
ReadFailure::destroy(&self)
```

Defaults: 16 MiB and 65,536 calls. Negative max_bytes is InvalidLimits before
allocation or delegation. Zero max_calls is valid but immediately CallLimit,
including for empty input or zero byte limit. Every actual Read invocation
spends one call before delegation, including Interrupted, EOF and the cap
probe. No synthetic EOF, retry reset or unbounded retry loop. The count cannot
overflow: test the quota before incrementing. Limits bound local work and
delegations, not the duration or internal work of a provider call.

Successful read_to_end returns exactly the confirmed bytes, without terminator.
Success requires an actual Ok(0) on a nonempty request. Each ordinary request
is min(1024, remaining byte allowance), with a valid private scratch array.
At the exact byte cap, make a one-byte read using separate private storage.
EOF succeeds; a confirmed extra byte gives ByteLimit and retains that byte in
extra. Thus confirmed consumed bytes equal bytes.len()+extra.is_some(), widened
before arithmetic. A subsequent caller can recover the consumed probe byte.
No reads occur after a terminal result.

ReadFailure always owns the confirmed admitted prefix in bytes, even for
Interrupted exhaustion, storage failure or invalid UTF-8. extra is Some only
for a confirmed over-cap byte; it is None for all other failures. calls is the
number of delegated calls. Err from a conforming Read transfers no bytes for
that call. A negative or excessive successful count gives Io(InvalidCount),
without appending scratch. Provider preconditions still apply; a broken
provider's actual consumption cannot be reconstructed from an invalid count.
Failures preserve earlier confirmed bytes and do not roll back the reader.
Destroy the failure exactly once (its method is reusable on the emptied owner),
or assume cleanup authority for its bytes; copies are shallow aliases.

## Allocation and UTF-8 ownership

Before each ordinary read, reserve enough Vec capacity for that request.
Grow geometrically, capped by max_bytes, using checked arithmetic and existing
Vec operations. Allocation failure consumes no additional input and returns
Storage with the original Vec error and retained prefix. Reserving before an
EOF observation may fail even when the next read would have returned EOF.
Empty input with a positive byte limit therefore can require the initial
reservation; a zero-byte cap probe does not allocate. Append only the confirmed
scratch prefix after reservation, with no further allocation. Never mutate
Vec owner fields directly or expose uninitialized spare capacity.

Add two general ownership operations in alloc::string:

```text
from_utf8_vec(bytes:&Vec<u8>) -> Result<String,alloc::string::Error>
String::into_bytes(&self) -> Vec<u8>
```

Validate before adoption. Invalid UTF-8 reports the existing first malformed
sequence offset and preserves the complete Vec owner, capacity and bytes.
Success transfers the existing backing/capacity without allocation or copying
and empties the source Vec. into_bytes similarly transfers backing/capacity and
leaves an empty reusable String. Use existing Vec take_iter/take_remaining to
transfer authority; do not add owner-field mutation to Vec. Existing copying
from_utf8 remains a distinct operation, without forwarding aliases.

read_to_string uses the same collection engine, observes EOF first, and then
adopts the bytes through from_utf8_vec. Text failure preserves all raw bytes in
ReadFailure with its actual call count. I/O/byte/call/storage errors therefore
precede UTF-8 validation. A split multibyte sequence across reads is ordinary.
No newline normalization or lossy replacement. Caller must end all borrows and
keep shallow aliases inactive before transfers/destruction; no automatic move,
drop, lifetime enforcement or formal verification claim follows.

## Real program and acceptance

`input_stats bytes|text [PATH|-]` collects stdin or one borrowed opened file
through the public helpers. Use a 1 MiB/8192-call profile. Byte mode reports
byte and NUL counts; text mode reports byte/scalar/LF counts. Output is fixed
ASCII records with decimal counts and no path echo. Retire input and close an
owned file before output. Strict CLI, raw byte paths and explicit primary-error
preservation are required. Status 0 success/help, 2 CLI/data/limits, 3 input or
file failure, 4 allocation, 5 output/signal, 6 internal. SIGPIPE ignored; output
and diagnostic attempts bounded. Stage the complete small result before stdout.

Acceptance: a small native generic admission; direct scripted short reads,
Interrupted/error/invalid counts and cap/EOF/quota precedence; an independent
state model; zero-copy String transfer with pointer/capacity identity and
invalid-input preservation; actual reached allocation failures with reader
progress and matched owner releases; growth/scale observations; real program
binary/UTF-8/file/CLI/cap/I/O/cleanup cases; selected existing alloc::io and
String regressions. Root serializes compiler/native/Cargo work under the
existing lock, with every command below two minutes. Agents use static or
bounded test-oracle controls only until root runs each gate.

Initial execution profile is native Linux x86_64 CPU output from the GPU
compiler. Other targets and user GPU execution require separate evidence.
The full standard and extended library goal remains open.
