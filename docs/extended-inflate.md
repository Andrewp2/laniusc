# Raw DEFLATE decoding

`ext::inflate` implements raw RFC 1951 DEFLATE in Lanius. Stored, fixed
Huffman and dynamic Huffman blocks execute on x86_64 Linux, including
cross-block history and overlapping copies. It imports `core` only, performs
no heap allocation and uses fixed-size stack tables.

```lanius
import core::result;
import core::slice;
import ext::inflate;

let progress: ext::inflate::Progress = core::result::unwrap(
    ext::inflate::decode_into(compressed, destination));
// progress.read: compressed bytes consumed, including the final partial byte.
// progress.written: initialized bytes at the start of destination.
```

Both arguments are `core::slice::View<u8>`. Native strided byte arrays,
nonzero view offsets and packed buffers are supported. Input and destination
must have live physical backing for their declared ranges and must not
overlap. These backing, lifetime and alias conditions are caller obligations;
the compiler does not enforce them. Logical metadata is checked before use.

## API and progress

| API | Behavior |
| --- | --- |
| `decode_into(input, output) -> Result<Progress, Failure>` | Decode one complete raw stream with the full 32768-byte history window. |
| `decode_into_window(input, output, max_distance: i32) -> Result<Progress, Failure>` | Require distances within a container's advertised history window. Accept powers of two from 256 through 32768. |
| `Progress { read: i32, written: i32 }` | Compressed bytes consumed and output bytes initialized. |
| `Failure { error: Error, read: i32, written: i32 }` | Failure kind and actual progress before failure. |

The decoder stops after the first final block. It does not consume trailer
bytes or concatenated streams. Unused bits in the final compressed byte, and
stored-block alignment bits, are ignored as the format requires.

Output capacity is a hard limit. An empty stream succeeds with empty output.
On any later failure, the completed output prefix is retained; every other
output element remains unchanged. A stored block or overlapping copy may be
partly written before `OutputTooSmall`. Input is loaded only as needed, so
`read` includes any byte loaded for the failing field or symbol. Failure
progress is diagnostic: the operation cannot resume from those byte counts
because the partial bit and block state is internal.

This is a caller-buffer operation over a complete input, without incremental
stream state or preset dictionaries. Raw DEFLATE supplies no checksum or
uncompressed length; container code must validate its own metadata and
checksums. An invalid source can leave a correctly bounded output prefix.

## Errors

| `Error` | Condition |
| --- | --- |
| `Bounds` | Negative start/count, overflowing logical end, or invalid window. Returns `read = written = 0` without accessing either range. |
| `UnexpectedEof` | Input ends inside a header, length field, code description, symbol or stored data. |
| `InvalidBlockType` | Reserved block type 3. |
| `InvalidStoredLength` | Stored length and its one's complement disagree. |
| `InvalidCodeLengths` | Invalid literal count, over-subscribed or disallowed incomplete tree, missing end-of-block symbol, repeat without predecessor or repeat beyond the described alphabet. |
| `InvalidSymbol` | Unused code, reserved literal/length symbol 286/287, reserved distance symbol 30/31, or a length with an empty distance alphabet. |
| `InvalidDistance` | Reference precedes available output or exceeds the selected window. |
| `OutputTooSmall` | Another decoded byte would exceed output capacity. |

Code-length alphabets must be complete. Literal/length and distance alphabets
may be incomplete only for a single one-bit symbol. An entirely absent
distance alphabet is accepted for literal-only blocks. Dynamic headers can
describe up to 32 distance symbols as specified by RFC 1951; reserved symbols
are rejected if used. This includes valid descriptions with 31/32 entries
whose reserved entries are unused, which zlib's usual strict decoder rejects
at the header.

Canonical length counts and sorted symbol arrays decode at most fifteen bits
per symbol. There is no recursive tree traversal or backtracking. Copies
advance forward one byte at a time so distance-one runs and other overlaps
repeat the decoded data correctly. Runtime work is bounded by compressed
input and produced output; output expansion cannot exceed the caller's view.

## Executable evidence

`tests/extended_inflate_execution.rs` drives native Lanius executables rather
than type-checking library declarations. All five groups passed together in
5.87 seconds. The tests cover:

- 330 Python-zlib reference streams spanning stored/fixed/dynamic blocks,
  six compression configurations, arbitrary bytes, empty input, runs,
  random alphabets and sync-flush block boundaries; exact output/trailer
  counts and capacity-limited prefixes are checked.
- Every legal length from 3 through 258 and every distance from 1 through
  32768, overlapping copies and history crossing block boundaries. The
  alternate length-258 representation is accepted.
- Fifteen-bit literal and distance codes, both repeat-17 endpoints,
  repeat-18 maximum and repeat-16 across the literal/distance boundary.
- Missing markers, malformed/incomplete/over-subscribed trees, repeat
  overruns, reserved symbols, invalid history and all truncated prefixes of
  eighteen independently compressed streams.
- Strided and offset views, NUL/non-UTF8 bytes, invalid logical metadata,
  allowed/rejected windows, untouched output guards and tails.

All native batches run with allocation syscalls traced and every attempted
`mmap` forced to fail; they perform no allocation calls. Python and Rust are
test drivers and references, not library implementations. GPU-kernel
execution has not been established by these CPU execution tests. No compiler
or runtime changes were needed.

Run the focused suite with an absolute target directory:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_inflate_execution -- --nocapture
```

The implementation follows the format in [RFC 1951, sections 3.1–3.2](https://www.rfc-editor.org/rfc/rfc1951)
and canonical decoding conventions discussed in [Mark Adler's puff source](https://github.com/madler/zlib/blob/master/contrib/puff/puff.c).
