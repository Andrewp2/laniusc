# Borrowed bidirectional text traversal

The complete standard/extended-library goal remains open. This increment adds
ordinary line traversal and backward scalar/word pulls to canonical core Text.
Current source already implements ASCII-word splitting; no duplicate word API
or String forwarding facade is needed. Predicate slice segmentation remains
separate roadmap work.

## Public contract

```text
Text.lines() -> Lines
Lines.borrow() -> &Lines
Iterator<Text> and DoubleEndedIterator<Text> for Lines
DoubleEndedIterator<Scalar> for Scalars
DoubleEndedIterator<Text> for SplitAsciiWhitespace
```

Keep existing forward behavior and the canonical Iterator/DoubleEndedIterator
protocol. Generic callers name both bounds. Do not duplicate next/next_back as
inherent methods or add reverse wrapper types: core::iter::Rev already supplies
that composition. These cursors do not implement ExactSizeIterator; counting
scalars, words or lines would require scanning backing rather than metadata.

The three cursor families consume one common remaining sequence. Arbitrary
front/back pulls never duplicate or cross items. None from either end exhausts
both ends permanently. Copies fork cursor position and share immutable backing;
they do not extend its lifetime or transfer cleanup authority. Existing
Scalars/SplitAsciiWhitespace state may gain an explicit back bound. Update
their constructors directly; no compatibility type or layout shim is needed.
Leave the original Text descriptor immutable inside a cursor where practical,
so offsets have one clear origin.

Lines partitions at LF and CRLF, excluding those terminators. A lone CR, NUL,
NBSP and Unicode line/paragraph separators remain ordinary content. Empty text
yields no lines; a final LF yields no extra phantom line. Leading and repeated
terminators produce empty lines. CR is removed only immediately before a
consumed LF. Mixed directions consume this same forward-defined partition.
This matches the familiar [Rust lines profile](https://doc.rust-lang.org/std/primitive.str.html#method.lines).

Scalars yields the existing Scalar { byte_index, value }. Its byte_index stays
relative to the original selected Text, including backward pulls and views
with nonzero backing offsets. Reverse decoding uses valid UTF-8 boundaries
and the existing UTF-8 helpers; do not copy a second codec implementation.
[RFC 3629](https://www.rfc-editor.org/rfc/rfc3629) explains why ASCII delimiters
cannot appear inside a multibyte scalar.

Words retain Lanius's existing six separators: HT, LF, VT, FF, CR and space.
Yield maximal nonempty words; Unicode whitespace and NUL remain content.
Backward pulls preserve the same word partition, not a different whitespace
definition taken from a host-language convenience function.

All constructors are inert descriptor/scalar setup. Traversal is allocation-free,
does not write backing, revalidate valid UTF-8, normalize, clone or destroy
owners, or call a host service. Preserve actual byte stride and view offsets.
Full traversal in any mixed-end schedule takes linear work in input bytes and
constant cursor storage; no repeated prefix scans or recursive traversal.

Input is an already-valid Text. Existing checked constructors remain the entry
for untrusted bytes. Physical backing, immutable contents and lifetime remain
caller obligations; new methods do not validate forged Text/cursor fields or
provide automatic alias/lifetime enforcement. Empty valid views require no
backing access. Do not change compiler IR, lowering, ABI machinery, proofs,
protected std::vec or core::mem. Reproduce missing compiler support separately.

## Applications

Migrate sample_programs/unicode_text_report.lani to backward borrowed scalar
traversal, preserving its existing byte/scalar-count header, scalar-reversed
output and error profile. Remove the temporary reversed String and destructive
pop_scalar loop. Reuse core UTF-8 encoding and bounded stack output staging;
reporting should leave its input String unchanged. Keep the existing input
capture profile; do not fold unrelated command-line redesign into this edit.

Add sample_programs/library/line_summary.lani: read bounded UTF-8 stdin and emit
one TSV record per line, in source order. Fields are one-based line number,
byte count, ASCII-word count, last-word byte count (zero if absent), and final
Unicode scalar value as decimal (-1 for an empty line). Header:
`line\tbytes\twords\tlast_word_bytes\tlast_scalar\n`.
Use lines(), a backward word pull followed by forward word counting, and a
backward scalar pull. Keep one input owner and fixed output scratch; no owned
copy per line or word. No arguments are accepted.

The application profile admits at most 1 MiB input and 65,536 lines. Validate
the complete UTF-8 input and line count before publishing the header; use a
real extra-byte/EOF probe at the byte cap. Read attempts are bounded to 16,384,
payload write attempts to 131,072, and diagnostic attempts to 64; Interrupted
spends an attempt. Status is 0 success, 2 arguments/UTF-8/input/line/call limit,
3 I/O (including failed signal setup/diagnostics), 4 allocation. After output
starts, I/O or payload-write attempt exhaustion may leave a confirmed stdout
prefix; status 2 is not a universal promise of empty stdout. UTF-8, byte, line
and read-attempt admission failures occur before the header. No rollback claim.
Failed SIGPIPE-ignore setup returns status 3 immediately without a diagnostic;
a diagnostic write cannot reliably return while SIGPIPE retains its default.
Agree literal diagnostics between app/test owners before freezing fixtures.
Use established stdlib stream, args, decimal and UTF-8 interfaces. All commands
remain under two minutes; root owns serial compiler/Cargo/native execution.

## Acceptance evidence

- Direct native tests: empty and singleton views, all UTF-8 widths, NUL and
  noncharacters, CR/LF/CRLF boundaries, six ASCII whitespace bytes, non-ASCII
  whitespace, leading/trailing empties, arbitrary mixed directions and fused
  exhaustion. Check original scalar indices, subview offsets, actual positive
  and descending byte strides, guards and unchanged backing.
- Shared-trait composition through Rev, Take and generic bounded helpers;
  negative ExactSize requirements if needed, with executable positive paths.
- Independent partition models over exhaustive short texts and seeded longer
  inputs, mixed direction schedules, cursor copies and repeated exhaustion.
  Compare full items/bytes and original offsets, not only aggregate hashes.
  Use explicit six-byte word predicates; Python splitlines is not the line
  oracle because it accepts more separators.
- Full-syscall observation for pure direct traversal. Owned-backing tests
  establish live owners, early stops, unchanged contents and explicit final
  cleanup, without pretending borrowed traversal has allocation failures.
- Migrated Unicode report and real line-summary behavior, complete output,
  invalid input/limits and reached allocation/read/write/diagnostic failures.
- Focused existing text/word regressions after changing cursor state. Native
  Linux x86_64 is the initial target; compiler GPU use is not device execution.
  No broad GPU or compiler performance reruns.

Keep runtime acceptance pending until executable evidence exists. Store guides
and inventory changes outside the human-maintained root README. Root refreshes
the generated declaration inventory after source/metadata freeze, commits the
verified increment and pushes codex/stdlib. Formal verification, broader
targets and the remaining library roadmap are not completed by this increment.
