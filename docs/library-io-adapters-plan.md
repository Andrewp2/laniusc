# Borrowed byte-reader adapters

This increment closes a main-library composition gap in `core::io`: a caller
can cap one reader or concatenate two readers while retaining the existing
Read and BufRead protocols. The full standard/extended-library goal remains
open. Existing cursor, buffered, delimiter, positional and owned-input APIs
remain their own implementation boundaries.

The increment now passes its focused native Linux x86_64 gates. The
[adapter guide](stdlib-io-adapters.md) records the accepted APIs, test receipts
and remaining target/lifetime limits; this document retains the design contract.

## Sources and design

The established [Take](https://doc.rust-lang.org/std/io/struct.Take.html) and
[Chain](https://doc.rust-lang.org/std/io/struct.Chain.html) interfaces provide
the basic quota and concatenation semantics. The
[reference implementations](https://doc.rust-lang.org/src/alloc/io/util.rs.html)
show a permanent first-reader handoff and a quota decremented by successful
reads. Lanius uses borrowed receivers, explicit count errors, a standalone
BufRead protocol and manual lifetimes. Its consume operation acknowledges an
exact count and can fail, so excessive consumption rejects instead of clamping.
No Rust implementation is added to the library.

## Public surface

All additions belong in existing `core::io`, with no forwarding module:

```text
take<R>(inner:&R, limit:u64) -> Take<R>
chain<A,B>(first:&A, second:&B) -> Chain<A,B>

Take<R>:
  borrow() -> &Take<R>
  limit() -> u64
  set_limit(limit:u64) -> Result<u64,Error>
  is_faulted() -> bool
  Read, where R: Read
  BufRead, where R: BufRead

Chain<A,B>:
  borrow() -> &Chain<A,B>
  is_first_done() -> bool
  is_faulted() -> bool
  Read, where A: Read, B: Read
  BufRead, where A: BufRead, B: BufRead
```

Constructors store references and scalar state without calling providers or
allocating. Their factories need no protocol bound: Read and BufRead remain
independent conditional implementations, including BufRead-only providers.
There is no close, destroy, automatic retirement or ownership transfer.
Keep every source, adapter and borrowed view alive; keep aliases inactive.
Copies must not operate independently on a shared source. Returned buffered
views are read-only by convention and expire before the next mutation through
either the adapter or its source. No Seek implementation is added: concatenated
or limited seeking needs a separate position contract.

## Shared forwarding rules

A faulted adapter rejects every Read/BufRead operation and set_limit with
InvalidCount before argument or empty-request checks. Queries remain usable.
Healthy read validates the complete offset/count range with valid_range before
any provider call. Invalid ranges return InvalidInput. A valid zero-count read
returns zero without provider calls or a chain transition.

Providers receive the original destination and offset with the admitted count.
Short reads return immediately; adapters do not fill the remainder. Any ordinary
provider Err propagates unchanged without an internal retry. In particular,
Interrupted, WouldBlock and even a provider Err(InvalidCount) do not by themselves
fault the outer adapter. Host-call/time budgets remain the consumer's concern.

A successful read count outside 0..requested, invalid successful fill metadata
(negative or overflowing start/length), or a successful consume acknowledgement
different from the requested count sets the adapter's permanent fault flag and
returns InvalidCount. No later provider calls are made through that adapter.
Only previously confirmed progress is retained; broken-provider effects cannot
be rolled back. A new adapter does not prove the provider itself recovered.

Healthy consume rejects negative counts with InvalidInput. Zero consumes return
zero without a provider call. A positive consume delegates once to the selected
provider; it never fills or switches sources. The provider remains responsible
for rejecting a count beyond its actual unread buffer. Its Err acknowledges no
consumption and leaves adapter quota/selection unchanged. Exact success commits
the adapter's accounting. There is no hidden last-fill cache or copying.

## Take semantics

The limit is the remaining logical byte quota, across both reads and successful
consumes, over the full u64 domain. set_limit replaces it, returns the new value
and performs no provider call. It can reopen an exhausted quota but cannot clear
a fault. The setter invalidates any previously borrowed fill view.

A read forwards min(requested count, remaining quota), narrowing only after the
comparison proves representability. Valid positive success subtracts exactly
that amount. Ordinary errors and underlying EOF preserve the quota. EOF is
observational: a later read/fill can observe newly available source bytes.

When quota is zero, healthy read and fill return EOF without consulting the
source. The empty fill is a zero-length View over a null raw slice; it carries
no live backing obligation and must never be dereferenced. Otherwise fill calls
the provider once, validates its entire returned metadata, then truncates only
the View length to the quota. Start, values and physical stride are preserved;
filling does not spend quota. Positive consume beyond the quota rejects locally
with InvalidInput. Exact successful consume spends the requested amount.

The limit bounds logical reads/exposure/consumption through this adapter. An
inner buffered provider may prefetch more bytes into its own storage, which
remain there for later use; this is not a bound on arbitrary underlying effects.

## Chain semantics

Initially all reads/fills/consumes select the first provider. A nonempty read
that returns zero, or a successful valid empty fill, permanently marks the first
provider done. The same call then consults the second provider. These operations
therefore make at most two direct provider calls; each other operation makes at
most one. A positive short first read does not consult the second provider.

No error, zero-count read or consume triggers handoff. Once a real first EOF
was observed, the transition remains committed even if the second call errors
or returns invalid metadata/counts. The first provider is never revisited.
Second-provider EOF remains observational and is not cached. This deliberately
differs from Take's treatment of its sole provider's EOF. Read and BufRead share
the same selection state, including mixed calls. Buffered views never span the
two providers; existing delimiter consumers can traverse the boundary normally.

## Application

Add `sample_programs/library/concat_bytes.lani` with CLI
`concat_bytes --limit N FIRST SECOND`. It opens the two named files for reading,
chains their borrowed File readers, caps the concatenation, wraps that reader
with the existing fixed-capacity buffered reader, and uses bounded owned-input
collection to stage the result. It outputs up to N bytes in first/second order;
early EOF is ordinary success. N is required and admits 0..1048576. Limit zero
still validates arguments and opens both files but performs no data reads.

Accept `-n`, `--help`/`-h`, and `--` through canonical ext::cli. Reject duplicate
options and wrong operands before opening files. Cap argv at 16 entries/8192
bytes, read-collection calls at 16384, staging at N, and output attempts at 4096.
Use a 4096-byte input buffer. Close both files and release the buffered input
before publishing staged output; argument path backing must remain live until
both opens complete. Release every partial owner on ordinary failures. Set the
existing explicit application SIGPIPE policy. Statuses: 0 success, 2 usage or
limits, 3 input/open/close failure, 4 allocation failure, 5 output failure, 6
invalid provider/internal state. Help makes no file or stdin reads. Document
partial stdout on output failure and bounded output/attempts without time claims.

## Verification and ownership

Root runs compiler/Cargo/native commands serially under
target/stdlib-work/library-gpu.lock, each command below two minutes. Agents own
separate production, direct contracts, independent model, composition/resources,
application, application oracle, documentation and independent review paths.
They run only bounded static/host controls. Start with one tiny mixed-protocol
admission, then focused portable contracts, negative capability checks, an
independent state-machine model, and actual owned buffered compositions. Preserve
full destination guards, source cursor/call effects, quota/selection/fault state,
exact error payloads and returned view bytes in observations. Cover u64::MAX,
zero/short transfers, Interrupted/WouldBlock, recoverable EOF, malformed metadata,
invalid acknowledgements, nested adapters and both actual byte stride forms.

Model expectations must not duplicate production forwarding code. Generate
mixed read/fill/consume/set-limit sequences and bias toward transition/error
boundaries, with a fixed recorded seed and deliberate oracle corruptions.
Resource checks must establish that the adapters introduce no allocation, retain
unconsumed buffered bytes and never close/discard caller-owned sources. Reuse
existing ownership providers; test their actual allocation failure paths only
where the new compositions introduce risk. The real application needs functional,
CLI/limit, reached I/O/allocation failure and exact standalone-example receipts.

Target acceptance initially means native Linux x86_64 CPU output of the GPU
compiler. Other targets, user GPU execution and formal/lifetime guarantees need
separate evidence. Missing compiler support gets a minimal reproduction and
dependency report; no compiler/IR/ABI/extractor/proof edits belong here. Human
root README, AI policy, CONTRIBUTING, tests/common and protected vector/memory
sources are outside the edit surface.
