# Full string casing program

`sample_programs/library/text_case.lani` reads bounded UTF-8 stdin and writes
Unicode 17.0.0 full string casing to stdout. The default is root-locale
lowercasing. Input NUL, supplementary characters and line endings are retained
as ordinary text; no newline or terminator is added.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/text_case.lani -o target/stdlib-work/text-case
printf 'Straße\n' | timeout 10s target/stdlib-work/text-case --kind upper
# STRASSE
```

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `--kind lower\|upper\|title\|fold` | `lower` | Full lowercase, uppercase, titlecase, or full case folding. |
| `--locale root\|turkic\|lithuanian` | `root` | Explicit casing rules; no host locale lookup. |
| `--max-input-bytes N` | 4,194,304 | Maximum input bytes. |
| `--max-output-bytes N` | 16,777,216 | Maximum output bytes; checked before allocating output. |
| `--max-work N` | 100,000,000 | Budget for each sizing/transformation call. |
| `--help`, `-h` | off | Print usage without reading stdin. |

There are no operands. Kind and locale spellings are lowercase. Byte limits
accept 0 through 67,108,864 and work accepts 0 through 1,000,000,000, as unsigned
decimal digits. Argument capture is limited to 32 tokens and 8,192 raw bytes.
Help does not suppress other invalid arguments.

Titlecase uses [Unicode 17 default word boundaries](extended-unicode-words.md),
then titlecases the first cased character and lowercases the rest in each word
segment. For example, `they're BILL'S` becomes `They're Bill's`. This differs
from algorithms that break on every nonletter. Lowercasing uses the original
text's contextual rules: Greek final sigma, Turkic dotted/dotless I and
Lithuanian combining accents are handled by the
[full casing engine](extended-unicode-case.md). Folding uses default mappings,
with Turkic overrides only when requested; Lithuanian folding uses the default.
No normalization is implicit. Casing and folding can change length and do not
preserve every normalization form.

## Failures, ownership and output

Exit 0 means success/help; 2 means invalid arguments, malformed UTF-8 or a
resource limit; 3 means host I/O failure; 4 means allocation failure. Errors
attempt a stderr diagnostic containing reason and stage. Malformed UTF-8
reports the malformed sequence's initial byte offset in stdin.

The whole input is read and validated before conversion. Sizing and conversion
receive separate work budgets; the option is not a total process-time quota.
Input reads, initialization and output writes are bounded by byte limits.
The engine's detailed context/segmentation work accounting is documented in
its guide. Input and output owners are distinct and are released on every
returned outcome. Empty input needs no data allocation and works with zero
byte/work limits. Encoding/resource failures occur before stdout is written;
a host write failure can leave a prefix. Short writes advance, interruptions
retry, and zero writes fail explicitly. Failed diagnostic output still returns
I/O status after cleanup.

## Executable evidence

`tests/extended_text_case_execution.rs` has three native test groups covering
all kinds/locales, full expansions, contextual rules, apostrophe/numeric title
boundaries, NUL/CRLF, UTF-8 across read boundaries, exact and exceeded limits,
invalid raw arguments, malformed input, all observed allocation denials,
read/write errors, interruptions, short/zero writes, `/dev/full`, and failed
stderr. Allocation traces reconcile every successful mapping and unmapping.

An independent Python root lower/upper/fold oracle uses overlapping Unicode
characters; default titlecase is checked against the Unicode word contract,
not Python's different title-boundary policy. A seeded 198,450-byte workload
measured lower 1,312 ms / 201,973 output bytes, upper 1,724 ms / 194,857 bytes,
and fold 1,365 ms / 201,973 bytes on this machine. Native timings include process
and file setup/I/O and exclude compilation; they are observations, not host
Unicode performance comparisons.

Verified target: native **x86_64 Linux** emitted by the GPU compiler. Production
is Lanius and does not call Python or a host Unicode library. Other targets and
user-program GPU execution remain unverified.
