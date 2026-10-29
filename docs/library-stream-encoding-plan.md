# Resumable copying and borrowed JSON encoding

The full standard/extended-library goal remains active. The preceding generic
slice increment is committed at `ca1e3d88`. This increment closes two connected
gaps: portable copying loses access to pending transfer state on return, and
JSON output requires a complete owned output String. Use the existing Read and
Write contracts to connect a resumable copier to a borrowed JSON byte reader.

## Sources and architecture

The local `core::io::Read`/`Write` contracts are authoritative for provider
effects: an Err acknowledges no bytes in that attempt. The familiar
[blocking copy contract](https://doc.rust-lang.org/std/io/fn.copy.html) and
[Read contract](https://doc.rust-lang.org/std/io/trait.Read.html) are comparison
references. Lanius adds explicit direct-call quotas, retained scratch and
confirmed progress; it does not add OS-specific copying or async scheduling.

[RFC 8259 sections 7, 8.1 and 10](https://www.rfc-editor.org/rfc/rfc8259.html)
define JSON string escaping, UTF-8 interchange and generator conformance.
Preserve the existing library policy: compact bytes, original number spelling,
member order and duplicates, lowercase control escapes, and scalar-valid UTF-8.
No normalization or cryptographic canonicalization is introduced.

There is one transfer engine in core::io and one JSON byte generator in
ext::json. Existing blocking copy and owned encode remain useful convenience
operations over those engines. Do not preserve duplicate legacy loops or
incidental allocation schedules. No separate JSON writer/transport abstraction
is needed: callers compose the encoder's Read implementation with Copier.

## Portable copier

Public types and methods in core::io:

```text
CopySide { Read, Write, State }
CopyStop { Eof, ReadLimit, CallLimit, ReadWouldBlock, WriteWouldBlock }
CopyStep { read:u64, written:u64, calls:u64, stop:CopyStop }
CopyStepFailure { cause:Error, read:u64, written:u64, calls:u64, side:CopySide }
Copier<R,W>
copier<R,W>(reader:&R, writer:&W, scratch:View<u8>) -> Result<Copier<R,W>,Error>
    where R:Read, W:Write
Copier.borrow() -> &Copier<R,W>
Copier.read_count() -> u64
Copier.written_count() -> u64
Copier.pending() -> View<u8>
Copier.is_active() -> bool
Copier.is_done() -> bool
Copier.is_faulted() -> bool
Copier.abort() -> View<u8>
Copier.step(read_limit:u64, max_calls:u64) -> Result<CopyStep,CopyStepFailure>
```

Construction requires positive scratch length and nonnegative, nonoverflowing
start/length metadata. Invalid metadata returns InvalidInput before providers
or backing are touched. Physical backing, initialization and disjoint live
storage remain caller obligations. Preserve the actual descriptor/stride.

State borrows endpoints and scratch and stores relative pending begin/end,
cumulative read/written counters, active, eof and faulted flags. It allocates,
flushes, closes and polls nothing. Results report cumulative confirmed bytes
and direct provider attempts made in this step. Provider-internal calls and
blocking duration are not bounded by this quota.

Each step drains pending bytes before reading again. read_limit bounds only
newly acknowledged input in that step; pending writes may exceed that quota.
Zero read quota can drain existing pending output, then returns ReadLimit.
Every immediate Read/Write attempt spends a call, including EOF, Interrupted,
WouldBlock and errors. Interrupted retries only within the remaining quota.
WouldBlock returns a resumable direction-specific stop. Other provider errors
and synthesized WriteZero return a failure while retaining resumable state;
retry is an explicit caller decision. Provider Err(InvalidCount) is an ordinary
error, distinct from a locally detected invalid successful count.

Only an Ok count outside 0..requested poisons the state. Keep the previous
confirmed counters and pending metadata; the nonconforming provider's actual
effects are unknowable. Do not promise physically safe replay after that fault.
Repeated step on a fault returns InvalidCount/State without provider calls.
Read Ok(0) for a positive request records permanent EOF with no pending bytes.

Precedence is exact: inactive -> InvalidInput/State; faulted ->
InvalidCount/State; cached EOF -> Eof, all with zero calls. For pending output,
check the call quota before writing. For an empty pending range, check the
new-read quota, then call quota, then cumulative read headroom. A read request
is min(scratch length, remaining new-read quota, u64::MAX - total read).
Zero headroom returns CountOverflow/State without calling or poisoning; it
does not infer EOF. Valid writes cannot overflow written because they are
bounded by confirmed pending input. Quota exhaustion does not probe past it.

pending() exposes a read-only live scratch view, valid until the next state
operation or caller reuse. abort() marks the state inactive and returns that
same tracked span, preserving counters/flags. Repeated abort returns the same
span without effects. The caller may deliberately recover or discard its
contents after ending use of all state aliases. No reset/rebind API is added.
is_done means observed EOF, is_faulted means a malformed successful reply,
and is_active means the state has not been aborted. One active state controls
the endpoints and scratch: copying it does not fork a transfer. No reentry,
interfering endpoint use, scratch edits or invalidation while it is active.

The old copy convenience drives this engine, returns the existing CopyFailure
shape, retries Interrupted and reports WouldBlock/errors immediately. It has
no useful small attempt bound and abandons its local resumption state on
return; callers needing recovery use Copier. Clip reads to counter headroom
instead of retaining the old conservative full-capacity refusal.

## JSON encoding

Add Document.encoded_len() -> Result<u64,Error> and Document.encoding() ->
Result<Encoding,Error>. Add Encoding.borrow(), remaining()->u64 and the single
canonical core::io::Read implementation. No Iterator or inherent next facade
is necessary for this byte-stream contract.

A private constant-storage machine follows first/next/parent links and tracks
structural phase, token position and small escape progress. Each edge is
visited a constant number of times. Preflight runs this same byte generator
through the configured output cap; admitted length is exact. NoRoot and
OutputLimit (offset -1) precede output allocation or provider effects. Encoding
starts a fresh machine with that remaining count. Each pass is linear in nodes
plus output bytes, without recursion, a depth stack or rescanning prefixes.

Read checks logical destination range before any effects; a zero request
returns zero unchanged. Otherwise it fills min(request, remaining) bytes.
Escape sequences and multibyte UTF-8 may cross read boundaries. Exhaustion is
fused. Copies fork complete position/escape state while sharing one stable,
immutable Document. Keep nodes, options, keys, strings and numbers unchanged
and live; destination/cursor storage must be disjoint from document backing.
Do not add a validator for forged/cyclic internal trees: valid Document and
String invariants established by the existing public APIs are preconditions.

Owned encode(document)->Result<String,Error> consumes that same Encoding
through alloc::io::read_to_string with exact admitted byte limit and
ceil(length/1024)+1 read calls, including the EOF probe. It cleans retained
failure output and preserves the source. The collector adopts its Vec as a
String; it does not make a second whole-output copy. Preserve precise errors
where representable and explain any unreachable internal-error mapping.

## Real program

Migrate sample_programs/json_normalize.lani. It accepts no arguments, retains
quiet errors and no appended newline, and uses read_to_string for bounded
zero-copy input adoption. Retire input after parse returns, before constructing
the borrowed encoder. Keep the Document alive through output and destroy it on
every ordinary terminal path. No output String or per-chunk owner is created.

CLI limits: input 1 MiB, 16,384 input read attempts, depth 128, 65,536 nodes
(including root), 1 MiB decoded key/string bytes per value, 1 MiB number bytes,
1 MiB admitted encoded output. These are app policy, not new parser defaults.
Use 1024-byte scratch and a 4096-byte new-read quota per step. Across all steps,
allow 131,072 total transfer-provider attempts: encoder reads plus writer
writes. Continue only ReadLimit, succeed only on observed Eof, return 2 on
CallLimit and 3 on WouldBlock or other I/O failure. Keep the final EOF read
possible after an exact quota; known output length alone is not observed EOF.

Statuses remain 0 success, 2 invalid arguments/text/JSON/configured limits,
3 I/O and 4 allocation. Ignore SIGPIPE explicitly; setup failure is silent 3.
No diagnostic bytes are added. Parsing and output-length admission precede
stdout. After publication begins, output failure may leave a confirmed prefix.

## Execution and ownership

Eight agent roles: core implementation; JSON implementation; core contracts and
independent schedule model; JSON contracts/model; resource/lifetime evidence;
normalizer migration/tests/guide; docs/metadata; independent review. Root owns
integration, compiler/Cargo/native execution, reference generation and push.
Native commands are serial under target/stdlib-work/library-gpu.lock, each
outer command limited to 100 seconds. Agents may run bounded host-only controls.

Begin with tiny generic admission. Use compact independent schedule/ordered-AST
models, real live owners, exact bytes and full-width release ledgers. Cover
normal/edge cases, explicit failures and recovery; do not inflate counts with
redundant campaigns. Seeded near-MAX counters are arithmetic tests, not claims
of transferring that many bytes. Existing focused regressions retain their
original API/source scopes; broaden only for concrete changed behavior.

No compiler/IR/ABI/extractor/proof, protected std::vec/core::mem, tests/common,
human README, AI_POLICY or CONTRIBUTING edits. Missing compiler support gets a
minimal reproduction and explicit dependency. Production remains Lanius.
Initial runtime evidence is Linux x86_64 CPU executables from the GPU compiler,
not user-program device execution. Commit/push the accepted increment while
keeping the whole standard/extended-library goal active.

## Accepted increment

All 14 new registered test groups pass across their focused commands: five
copier groups, two JSON encoding groups, three resource groups and four
normalizer groups. The independent models cover 72 copier schedules/348
actions and 978 JSON cases. The normalizer executes 100 process cases,
including 33 reached allocation failures. Three selected existing stream/JSON
regressions also pass. The standalone normalizer build and both documented
examples produce their exact 43-byte and 12-byte outputs.

Reference generation also exposed the existing response-file provider's direct
`core::io::Read` import beside the new `CopySide::Read` variant. Its focused
`native_response_provider_files_and_call_failures_execute` regression passes
39 cases in 8.13 seconds, after a separate 1.67-second Rust build
(`target/stdlib-work/stream-encoding-regression-imported-read.log`). This fourth
existing regression checks that concrete import/trait composition; it adds no
new library or normalizer cases. Reference generation and its subsequent check
pass for 275 pages, 274 modules and 9,102 public declaration markers; those
inventory counts are not execution claims.

The module guides and fixture READMEs record source hashes, individual receipts,
corrected fixture failures and the precise resource-observation scopes. The
accepted target is Linux x86_64 CPU execution from the GPU compiler. Other
targets, enforced lifetimes and formal proofs remain separate; this completes
the selected increment, not the full library goal.
