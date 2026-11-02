# Zstandard decoding, XXH64 and unzstd

`ext::zstd` decodes Zstandard frames (RFC 8878) as a stream. It handles:

- skippable frames and concatenated frames;
- raw, RLE and compressed blocks;
- Huffman-coded literals in one or four streams, including treeless blocks
  that reuse the previous table;
- FSE sequence tables in all four modes (predefined, RLE, compressed and
  repeat);
- repeat offsets;
- frame content sizes, XXH64 content checksums and a window limit.

It is pure Lanius over caller-owned workspace, staging, literal and window
views. It allocates nothing and calls no host service. Dictionaries are not
supported: a frame that names a dictionary ID is refused.

`ext::xxhash` is XXH64, one-shot and streaming. zstd frames use it for their
checksum.

[`sample_programs/library/unzstd.lani`](../sample_programs/library/unzstd.lani)
is an `unzstd`/`zstdcat` program built on both modules.

Executable evidence covers **x86_64 Linux with native executables produced by
the GPU compiler**. Other targets and GPU-kernel execution are unverified.

## Library API

```text
// ext::zstd
Error = Bounds | Truncated | Magic | FrameHeader | Dictionary | WindowTooLarge
      | BlockType | BlockSize | Literals | Huffman | Fse | Sequences | Offset
      | ContentSize | Checksum | Failed
Status = NeedInput | NeedOutput | NeedWindow | Done
Step { read: i32, written: i32, status: Status }
Limits { max_window: i32 }             // bytes, 1 KiB to 1 GiB
default_limits() -> Limits             // 128 MiB, zstd's own default
BLOCK_MAX = 131072
workspace_len() -> i32                 // 8192 i32 words
stage_len() -> i32                     // BLOCK_MAX + 32 bytes
literals_len() -> i32                  // BLOCK_MAX + 32 bytes

decoder(workspace: View<i32>, stage: View<u8>, literals: View<u8>, limits: Limits)
    -> Result<Decoder, Error>
Decoder.step(input: View<u8>, output: View<u8>, final_input: bool) -> Result<Step, Error>
Decoder.window_len() -> i32            // bytes wanted after NeedWindow
Decoder.set_window(window: View<u8>) -> Result<bool, Error>
Decoder.is_done() -> bool
Decoder.frames() -> u64                // finished frames, skippable ones included

// ext::xxhash
state(seed: u64) -> State
State.update(bytes: View<u8>)
State.digest() -> u64                  // the state is unchanged; updates may continue
xxh64(bytes: View<u8>, seed: u64) -> u64
```

The stage and literal views must be packed (byte stride 1). The decoder
keeps raw pointers into them, and into the window, so they must outlive it
and must not move.

A typical loop is in `unzstd.lani`'s `decode`:

1. Call `step` with the unread input, an output buffer and `final_input`.
2. Write `written` bytes and drop `read` bytes of input.
3. On `NeedWindow`, provide at least `window_len()` bytes with `set_window`
   and call again. On `NeedInput`, read more. On `NeedOutput`, drain and
   call again. Stop on `Done`.

Errors are sticky: after one, every `step` returns the same error.

## Decoding rules

**Frames.** Input is any sequence of zstd frames (magic `28 b5 2f fd`) and
skippable frames (`50`-`5f 2a 4d 18` plus a 32-bit length, whose contents are
discarded). The stream ends at `Done`. The decoder reports `Done` only once
the input ends exactly at a frame boundary, after at least one frame. Other
cases are errors:

- empty input, or input that stops inside a frame, is `Truncated`;
- trailing bytes that do not start a frame are `Magic`.

**Frame header.** A set reserved bit is `FrameHeader`. A nonzero dictionary
ID is `Dictionary`. The window size comes from the window descriptor, or
from the content size in single-segment frames. A window larger than
`max_window` is `WindowTooLarge` before any block is read.

The window the caller provides needs `window_size + min(window_size, 128 KiB)
+ 32` bytes: the history, one block of output, and spare bytes for word
copies. Its contents need not survive between frames, so a single buffer
sized for the largest frame serves a whole file. A 10-byte single-segment
frame asks for 52 bytes; a `--long=27` frame asks for 128 MiB plus 128 KiB.

**Blocks.** A block may not exceed `min(window_size, 128 KiB)`, whether as
its stored size or as its decoded size (`BlockSize`). Reserved block type 3
is `BlockType`. Each block is decoded whole into the window, then delivered
through `output` and hashed as it goes. Input is staged one block at a time,
so `step` accepts any split of input and output, down to one byte.

**Literals.** Raw, RLE, Huffman and treeless sections are supported. The
Huffman tree comes from direct 4-bit weights or from FSE-compressed weights
(two interleaved states). The last weight is implied by the power-of-two
rule. Tables up to 12 bits are accepted, as zstd's decoder accepts them,
though RFC 8878 says 11. Four-stream sections need at least 6 literals and a
consistent jump table.

Each Huffman stream must decode its exact literal count and end exactly at
its first bit. zstd's fast decoding loops do not check that end. As a result,
some corrupted streams without a frame checksum decode under `zstd -d` but
are `Huffman` errors here (the fuzz group's "stricter" count).

**Sequences.** The reserved bits of the modes byte must be zero. zstd 1.5.6
also rejects them; 1.5.5 ignores them.

- `Fse` covers bad table descriptions: an accuracy log above the per-table
  maximum (LL 9, ML 9, OF 8, Huffman weights 6), counts that do not sum to
  the table size, or too many symbols.
- `Sequences` covers bad codes or counts, and literal or match lengths that
  overrun the block.
- `Offset` covers offsets of 0, offsets beyond the frame's output so far, or
  offsets larger than the window.

A repeat table with no previous table is `Sequences`. The sequence bitstream
must also be consumed exactly.

**Checks.** At the end of a frame, a declared content size must equal the
decoded size (`ContentSize`, also raised as soon as output passes it). A
frame checksum must equal the low 32 bits of the XXH64 of the content
(`Checksum`).

## XXH64

`ext::xxhash` follows the reference algorithm. `update` takes any split of
the input. Packed views are read eight bytes at a time through raw `u64`
views. Other views, and the bytes that do not fill a 32-byte stripe, are
read a byte at a time. Hashing runs at about 1.5 GB/s on packed data; the
checksum costs zstd decoding about 5%.

## The unzstd tool

```text
unzstd [-c] [-t] [-f] [-M MIB] [FILE...]
zstdcat [FILE...]          # unzstd -c, chosen by program name
```

- `FILE.zst` or `FILE.zstd` is decoded to `FILE`. The input is kept, as with
  zstd.
- An existing output is refused unless `-f` is given.
- With no FILE, or with `-`, standard input is decoded to standard output.
- `-c` writes every file to standard output, concatenated.
- `-t` decodes without writing.
- `-M`/`--memory` raises the window limit to MIB mebibytes (1-1024). For
  example, `--memory 256` accepts `--long=28` frames. As with `zstd -d`, the
  default is 128 MiB.
- `-d`, `-k` and `-q` are accepted for compatibility and change nothing.

A failed decode removes its partial output file. Errors name the file and
the error class (for example `unzstd: x.zst: checksum mismatch`). Exit
status is 0 on success; 2 for arguments, existing outputs, unknown suffixes
and invalid data; 3 for I/O; 4 for allocation. With several files, the tool
continues after an error and exits with the highest status.

Input and output use 128 KiB buffers. Memory is those buffers, about 290 KiB
of decoder storage and the largest window any frame asks for.

## Executable evidence

`python3 -I tests/fixtures/extended/zstd_oracle/oracle.py UNZSTD XXH64_PROBE
ZSTD_PROBE WORKDIR` (seeded, 30 s) passes **3,866 cases with 0 failures**.
The reference is `/usr/bin/zstd` 1.5.5; the probes are
[`xxh64_probe.lani`](../tests/fixtures/extended/zstd_oracle/xxh64_probe.lani)
and [`zstd_probe.lani`](../tests/fixtures/extended/zstd_oracle/zstd_probe.lani)
compiled with `lcc`.

| Group | Cases | What agrees |
|---|---:|---|
| xxh64 probe | 60 | `ext::xxhash` against a Python XXH64 over random lengths and update splits |
| xxh64 trailer | 20 | the Python XXH64 against zstd's own frame checksums |
| levels 1-19 | 95 | five inputs per level (0 B to 1.5 MB; random, text, runs, periodic), with and without checksums and content sizes |
| piped | 19 | frames compressed from a pipe (no content size), one per level |
| ultra 20-22 | 3 | `--ultra` levels on 1 MB |
| params | 60 | `--zstd=wlog=10..23,strat=1..9[,mml]`, forced raw or compressed literals, 1,340-byte target blocks |
| long=27 | 4 | a 24 MB input repeating 3 MB at 12 MB distance, levels 1, 3, 9 and 15 |
| window limit | 2 | a `--long=28` frame is refused by default and decoded with `--memory 256` |
| multi-frame | 43 | 2-5 frames per file, mixing levels, empty frames and skippable frames; a lone skippable frame |
| trailing garbage | 4 | a zero byte, a partial magic, a non-zstd file and a cut skippable frame are refused |
| empty input | 1 | refused, as `zstd -d` refuses it |
| dictionary | 2 | a frame with a dictionary ID, and one made with `zstd --train`, are refused |
| cli | 9 | output naming, `-f`, `-t`, `-c` with two files, `zstdcat`, bad suffix, partial-output removal, missing file |
| chunked steps | 50 | multi-frame files through the streaming API with 1 B to 64 KiB input and output steps |
| fuzz | 3,493 | truncations and 1-3 bit flips of 16 frames: exit 0 or 2 only, with no signal and no hang, and output identical to `zstd -d` whenever both accept |

Of the fuzz cases, 3,438 match zstd's verdict and 55 are rejected here while
zstd decodes them. None is accepted here and rejected by zstd. The 55 are the
Huffman end check and, in 1.5.5, the reserved sequence bits described above.

## Performance

These are min-of-3 CPU times on 100 MB of Lanius source text (the extended
library repeated), on the shared laptop:

| File | unzstd | zstd 1.5.5 |
|---|---:|---:|
| `-3` (22 MB, 7.65 M sequences) | 0.95 s (105 MB/s) | 0.08 s |
| `-19` (632 KB, long matches) | 0.33 s (300 MB/s) | 0.02 s |

The decoder already uses whole-word copies through raw `u64` views, a local
bit reader in the sequence and Huffman loops, and word-pair copies for short
literals and matches. The remaining gap is codegen. Microbenchmarks give
these per-operation costs:

- creating a raw view costs about 10 ns;
- an indexed raw `u64` access costs about 8 ns;
- a byte copy through `[u8]` views costs about 9 ns.

Sequence execution therefore costs about 100 ns per sequence, and decoding
about 75 ns.
