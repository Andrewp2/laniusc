# File comparison and exact patch application

`sample_programs/library/text_patch.lani` combines [`ext::diff`](extended-diff.md)
and [`ext::patch`](extended-patch.md) with counted byte views, CLI parsing,
owned byte buffers, native files and checked descriptor streams. The program
and its algorithms are Lanius. GNU tools and Python appear only in reference
tests.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/text_patch.lani -o target/stdlib-work/text-patch
target/stdlib-work/text-patch diff old.txt new.txt >change.patch
# Exit 1 means a successful comparison found differences.
target/stdlib-work/text-patch check change.patch <old.txt
target/stdlib-work/text-patch apply change.patch <old.txt >result.txt
```

## Commands and bytes

```text
text-patch diff [OPTIONS] OLD NEW
text-patch apply|check [OPTIONS] PATCH_FILE <BASE
```

`diff` reads both files and writes a deterministic single-file unified patch.
It returns 0 with empty stdout when the bytes are identical, and 1 with the
complete patch when they differ. The default labels are `before` and `after`;
`--old-name` and `--new-name` replace them. Labels are informational. They do
not identify filesystem targets during application. Labels must be nonempty
and cannot contain NUL, TAB, CR or LF; other bytes, including non-UTF-8 bytes,
are preserved. There are no timestamp fields in generated headers.

`apply` reads the patch file and the original bytes from stdin, checks every
hunk, and writes the complete result to stdout. `check` performs the same
application and resource checks, then discards the result without writing
stdout. Neither command modifies a file. An empty patch is the identity
operation, including on nonempty input.

Line boundaries are LF bytes. CRLF, NUL, non-UTF-8 bytes, repeated lines,
empty files and missing final LF are supported. Missing final LF uses the
unified no-newline marker. No decoding, newline conversion or whitespace
normalization occurs. Context must match exactly at the specified positions;
there is no offset search or fuzzy application. Unsupported patch formats,
multiple file sections and malformed hunk counts fail explicitly. The library
guides define the accepted unified grammar.

Operands are raw Unix byte paths. `--` ends option parsing. A path named `-`
is an ordinary filename; stdin supplies only the base for `apply` and `check`.
There must be exactly two filenames for `diff` or one patch filename for the
other commands. Options can be interspersed with operands. Repeated value
options use their last value. Argument capture permits at most 32 tokens and
8,192 total bytes after the executable name.

## Resource limits

| Option | Default | Upper bound and meaning |
| --- | --- | --- |
| `--max-input-bytes N` | 4,194,304 | 67,108,864; separately bounds each file and stdin base |
| `--max-output-bytes N` | 16,777,216 | 67,108,864; encoded patch or complete applied result, including in quiet checking |
| `--max-lines N` | 65,536 | 1,000,000; library line/hunk limits |
| `--max-work N` | 100,000,000 | Full unsigned 64-bit range; allowance per library phase |
| `--max-trace-cells N` | 1,048,576 | 67,108,864; Myers trace entries, not bytes; `diff` only |
| `--max-edits N` | 131,072 | 2,000,000; library edit/step limit; `diff` only |
| `-U N`, `--context N` | 3 | 67,108,864; unchanged context lines per side; `diff` only |
| `--old-name NAME`, `--new-name NAME` | before, after | Header labels; `diff` only |
| `-h`, `--help` | off | Print usage after command-line validation |

Numeric values use unsigned decimal without signs or separators. Zero is
permitted, with the library's explicit empty-input and resource-limit behavior.
Diff-only options are rejected with `apply` and `check`. Invalid options still
fail when help is requested. Help does not require filenames or a command.

Each library call owns its budget: comparison and unified encoding are separate
phases; patch parsing and application are separate phases. The work flag is
not one cumulative budget shared with host I/O or CLI parsing. Input byte caps
also bound file copying and output cap checks occur before publication.

Peak storage includes the bounded input buffers, line descriptors, edit script
and Myers trace, plus the complete encoded patch or applied result. Vector
capacity can exceed its logical length during growth. The algorithms are
whole-input operations; large edit distances can hit the explicit trace or
work limit. They do not substitute a nonminimal script after exhaustion.

## Failures and ownership

Every input, comparison, parse, conflict, limit or allocation error produces
no stdout. All source files are closed before algorithm output is published;
even a close failure suppresses output. Every temporary owner is released on
all returned paths. Patch views borrow the live patch buffer; script views
borrow both live source buffers until encoding finishes. Argument-backed
label/path views remain live through the operation.

| Exit | Meaning |
| --- | --- |
| 0 | Identical files, successful application/check or help |
| 1 | Successful `diff` found changes and wrote a patch |
| 2 | Arguments, input/format/conflict or resource limits |
| 3 | File/stream/argument-read error, including a failed stderr diagnostic |
| 4 | Allocation failure |

Errors are written to stderr with a category and a named stage such as
`old-file`, `patch-parse` or `output`. Parse errors can include a zero-based
patch byte; conflicts can include a zero-based base line. File open makes one
host attempt. Reads and writes retry EINTR; writes resume after positive short
counts and reject zero progress. Linux close is attempted once, including
after a read failure. A stdout error can leave a prefix of a fully validated
result; earlier successful bytes cannot be rolled back on a descriptor.

## Executable evidence

`tests/extended_text_patch_execution.rs` compiles the real application and
executes x86_64 Linux output. It checks byte-exact diff/apply/check round trips,
independent Python unified patches, GNU diff/patch interoperability, missing
final LF, CRLF, binary bytes, labels, context boundaries, malformed input,
conflicts, caps and argument errors. It denies each observed allocation and
exercises file/stream failures with mapping-release checks, short and interrupted
I/O, `/dev/full` and failed diagnostics.

A 20,000-line sparse-edit case uses 520,000 source bytes and a 1,549-byte patch.
One native observation took 233.162 ms for comparison and 132.843 ms for
application. These timings include process and file I/O, exclude compilation,
and were recorded under uncontrolled desktop activity. They are not an
optimized-tool comparison or a user GPU execution claim.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --test extended_text_patch_execution -- --test-threads=1 --nocapture
```

Supported execution is x86_64 Linux output from GPU compilation. There is no
Wasm dependency or host diff/patch implementation in the production path.
