# Text wrapping

`sample_programs/library/text_wrap.lani` is a real stdin UTF-8 → wrapped stdout
program. `ext::unicode_lines_wrap` provides its reusable, owned-output API. It
combines the complete default Unicode 17 line opportunities with the existing
[terminal cell-width policy](extended-terminal.md).

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended sample_programs/library/text_wrap.lani -o target/stdlib-work/text-wrap
timeout --kill-after=2s 100s target/stdlib-work/text-wrap --columns 40 < article.txt > wrapped.txt
```

## Fitting and output policy

Wrapping greedily chooses the latest legal opportunity that fits. Soft choices
must also be extended grapheme boundaries, even with scalar width selected.
UTF-8 scalars and grapheme clusters are never split. Width is the additive sum
of `terminal::width` over each cluster, using the chosen scalar/grapheme mode and
ambiguous-width setting. This is a deterministic policy; it does not inspect a
font, terminal, locale, shaping engine, or physical screen.

Spaces are **preserved and measured**, including spaces at a line's end. For
example, `ab cd ef` at three columns becomes `ab ⏎cd ⏎ef`, where each visible
space before ⏎ remains a real space. Runs of spaces follow UAX #14's legal
opportunities. No trimming or indentation synthesis occurs.

CRLF, CR, LF, VT, FF, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR are explicit
hard separators and become one LF each. Consecutive separators retain empty
lines. A terminal newline remains present; **EOT does not add a newline** to
unterminated input, and empty input produces empty output. These formatting
decisions belong to wrapping; the opportunity API preserves original offsets.

An unbreakable segment wider than the limit is emitted intact by default.
`--overlong error` rejects it instead. There is no emergency cut inside a word
or cluster. No hyphenation or discretionary glyph insertion occurs: soft
hyphens and other accepted format characters remain original bytes. These
policies do not implement full typesetting or language-specific shaping.

Other controls, including tabs, NUL, ANSI escapes and bidi controls, fail under
the terminal policy. Unsafe escapes are never silently removed. The separate
line-opportunity API accepts valid UTF-8 controls according to UAX #14.

## Command options

| Option | Default | Meaning |
| --- | --- | --- |
| `--columns N`, `-c` | 80 | Positive cell limit, at most 67,108,864 |
| `--ambiguous-wide` | off | Ambiguous EAW characters occupy two cells |
| `--scalar-width` | off | Sum scalar widths; default uses grapheme policy |
| `--overlong overflow\|error` | overflow | Preserve or reject an oversized unbreakable segment |
| `--max-input-bytes N` | 4,194,304 | Staged input byte limit |
| `--max-scalars N` | 1,048,576 | Input scalar limit |
| `--max-output-bytes N` | 8,388,608 | Complete staged output limit |
| `--max-lines N` | 1,048,576 | Emitted lines; a trailing LF does not create an extra line |
| `--max-work N` | 268,435,457 | Abstract wrap work limit |
| `--help`, `-h` | off | Usage, appearing alone |

CLI count limits are in `0..=67,108,864`; `max-work` accepts `u64`. No operands,
repeated options, negative/overflowing numbers, or unknown values are accepted.
Exit codes are 0 success/help, 2 invalid input/options or resource limit,
3 I/O failure (including diagnostics), and 4 allocation failure.

## Library API and resources

`wrap(Text,Options,Limits)` returns `Result<Vec<u8>,Error>`.
`Options { columns, mode, ambiguous_wide, overlong }` uses terminal `Mode` and
`Overlong::{Overflow,Reject}`. `Limits` contains the five input/output/count/work
fields described above. Library output-byte and line limits may extend through
the nonnegative `i32` range; input byte/scalar limits retain the hard 67,108,864
bound. `work(byte_length)` exposes the exact abstract charge `64*bytes+1`,
including opportunity construction/iteration, grapheme scans, terminal width
calls, amortized output growth and copying. It is a policy charge, not a count
of physical decoder reads, instructions or allocator calls. Exact limits are
inclusive. Each cluster's inherited terminal budget is set to exactly six
units per selected byte; no input prefix is repeatedly measured.

A complete wrap takes O(input bytes + output bytes) time, constant segmentation
state and O(output bytes) owned memory. Output capacity grows geometrically,
clamped to the output limit; exact per-line reservation would otherwise copy
prefixes quadratically. There is no table of all opportunities or line spans.
The input is validated and scalar-limited before allocation. A late control,
oversized segment, output/line limit or allocation error destroys the partial
owner. Borrowed input is preserved. `Text` still requires physical backing,
lifetime and immutable storage as described in the opportunity guide.

The returned vector is a single manual owner; copies alias it. Destroy it once
after all borrowed uses. Errors identify bounds/options/limits, bytes/scalars/
lines/output/work, UTF-8 and control offsets, overlong segment start, overflow,
or allocation failure. The CLI stages all bytes before any stdout write, so
processing failures publish no prefix. An I/O failure after writing begins can
leave a prefix; interrupted I/O retries. Every exit destroys native owners.
The CLI explicitly ignores SIGPIPE before argument capture or allocation, so
closed stdout and stderr pipes return through checked I/O and cleanup. Failure
to install that process-wide disposition exits with status 3 before allocation.
A focused native gate checks real closed stdout/stderr pipes, mapping cleanup
and pre-allocation signal-setup failure without rerunning Unicode conformance.

Focused native tests use an independent fitting search over explicit cluster
width and legal-opportunity vectors, exercise both width modes and ambiguity,
emoji/flags/combining/CJK, preserved spaces, every hard separator, final-newline
and empty cases, exact and exceeded limits, 20,000 short lines, every allocator
denial with a mapping ledger, late-error cleanup, and read/write EIO/EINTR.
The separate full official corpus checks the underlying Unicode decisions.
