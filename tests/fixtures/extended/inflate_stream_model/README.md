# Resumable decompression model

This independent model drives the raw `ext::inflate::Decoder` and the raw,
zlib and gzip forms of `ext::compression::Decoder` through **1,925 cases**.
There are **311 reset cases**, yielding **2,236 complete decoder passes**.
The recorded seed is `0x1f1a7e0261107`.

The primary byte oracle is Python's system zlib. It independently generates or
validates every valid stream. Gzip verification explicitly visits every member
and rejects unused trailing bytes; raw/zlib container verification also rejects
trailing bytes. The raw-engine oracle permits the trailing suffix that its
public contract leaves unread. Python is test infrastructure; production
remains Lanius with no zlib dependency.

## Corpus

The corpus includes every byte split of selected small stored, fixed and dynamic
streams in all four decoder forms. One bitstream writer produces two
independently constructed empty dynamic streams with repeat-16 across the
literal/distance alphabet boundary, both repeat-17 endpoints, and a maximum
repeat-18 run. System zlib
accepts both streams. Every byte split therefore includes splits inside those
headers and repeat descriptions. The generator writes the format; it does not
decode Huffman codes or repeat the production parser.

Every truncated prefix of selected stored/dynamic streams is checked, along
with every prefix and split of optional-header gzip and a three-member gzip
sequence. Optional headers include extra bytes, raw non-UTF8 name/comment,
FHCRC and split trailers. Complete gzip-member prefixes remain valid sequences.
Malformed cases cover reserved raw block types, stored length complements,
fixed headers, dictionary IDs, checksums, ISIZE, trailing data and member/input/
output limits. A split `1f 00` gzip tail rejects as TrailingData before an
exhausted member quota; a lone final `1f` follows the documented quota/truncation
precedence.

Large witnesses include a 32,768-byte stored seed, 180 explicit length-258
references at distance 32,768, followed by 140 distance-one references. This
wraps history repeatedly and exercises overlapping copies. Other streams cover
a 98,305-byte run and history crossing a sync-flush block boundary.

Input schedules expose a selected two-part split, single bytes or irregular
frontiers that include empty offers. Output schedules contain zero, one and
irregular capacities through 509 bytes. Some callers defer the final-input
promise until a separate EOF observation. Reset reruns the same source with
ample chunks, checking the same terminal result, complete output and consumed
endpoint. Full-span input-budget admission is deliberate; cases do not assert
malformed-versus-limit equivalence across different offered spans.

## Progress and buffer evidence

Every call reports the offered bytes, capacity, final-input promise, actual
read/written counts, suspension/error, completion/failure flags, cumulative
container counters and completed members. Each count must stay inside the
actual offered range. NeedInput must consume the offered span and cannot occur
on a final call. NeedOutput must fill the provided output span. Container
counters equal the sum of actual progress, including failure prefixes.

The exact stored-block witness uses an independent analytical rule: five header
bytes followed by a known literal payload, with the specified input-before-
output suspension precedence. It checks **38 cases** and **160 scheduled calls**
in host verifier controls. Other compressed forms use zlib's decoded bytes and
terminal endpoints, accounting/suspension laws and chunk invariance. The model
does **not** equate zlib's internal lookahead or per-call consumption with this
library's consumption policy.

For valid and truncated streams, an independent incremental zlib decoder sees
only input bytes the native decoder reports consuming. Native output cannot
precede independently available decoded bytes, and NeedInput must have drained
that available output. Every published byte is checked against the independent
expected output, including provisional output before failure.

Before each call, all **520 destination bytes** receive a changing pattern.
The oracle checks the complete written prefix and every other byte, including
both guards and the untouched tail. After each call the producer overwrites
consumed input bytes. Future calls must therefore resume using retained bits,
history and parser state. Unconsumed input is compared against the original
transport bytes after each call; the complete recycled source and both guards
are checked after every pass. No previous input/output view stays usable by
accident. History/workspace guard cells are checked after all passes.

Eight layouts cover native and packed source, output and history storage.
Actual native u8 stride is -8 on this target; packed raw u8 stride is +1.
i32 workspace stride is +4. Every view has a nonzero start. Native terminal
probes verify sticky failure/Done and metadata-first Bounds without state or
counter mutation. Reset restores active state and zero container counters.
The separate direct/resource gates cover additional invalid reset, selected
metadata/guard/storage-state cases and allocation failures. Physical backing,
lifetimes and nonoverlapping active aliases remain caller obligations.

## Protocol and focused gate

One native process receives the entire deterministic batch through raw binary
stdin/stdout. Headers use little-endian u64 words; compressed bytes, output
backing and source observations are raw bytes. Record sizes are checked and
extra/truncated output, stderr or nonzero exit rejects. A mismatch reports seed,
case, format, layout, schedule and byte position. The native subprocess deadline
is 75 seconds; the enclosing host oracle deadline is 90 seconds.

Test selector:

```text
independent_inflate_streams_match_zlib_splits_progress_recycled_views_and_reset
```

The Rust driver checks Linux x86_64 ELF format and the shared executable writer's
jump containment checks. Root owns all compiler/native runs under the serial
library compiler lock.

## Evidence

Host controls pass zlib stream generation/validation, explicit trailing-data
rejection, all 38 analytical stored cases, and eleven verifier corruptions:
read/written counts, status, terminal state, cumulative counters, output guard,
output byte, unwritten tail, workspace guard, truncation and extra output.
These controls are separate from native runtime cases.

The native gate passed **1,925 cases, 311 resets and 2,236 passes**, checking
**29,914 decoder calls** and **2,626,630 published output bytes** across all four
decoder forms and eight layouts with seed `0x1f1a7e0261107`. The focused test
passed in **12.90 seconds**, after a separate 1.97-second Rust build. The local
receipt is `target/stdlib-work/inflate-stream-model-final.log`.

The initial attempt stopped before native execution because seven fixture type
assignments omitted the space between a generic closing `>` and `=`. The fixture
syntax and a stale Rust summary assertion were corrected; production
sources and the oracle/corpus were unchanged by those test repairs.

This receipt establishes finite **native Linux x86_64 CPU behavior from the GPU
compiler**. It does not establish user GPU execution, other platforms,
arbitrary strides or formal verification.
