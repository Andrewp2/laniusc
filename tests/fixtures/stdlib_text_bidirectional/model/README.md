# Independent bidirectional text model

This finite runtime model compares borrowed `Lines`, `Scalars` and
`SplitAsciiWhitespace` with independent semantic partitions and two deques.
The reference defines the complete forward item sequence once, then applies
front pulls, back pulls and cursor copies to that sequence. It does not copy
the production cursor scanners.

## Reference and corpus

The line reference partitions at explicit LF positions and strips only a CR
immediately before that LF. It does not use Python `splitlines`. Scalars use
Python's UTF-8 decoder and the encoded width of each scalar to obtain original
byte offsets. Words use an explicit byte class containing exactly HT, LF, VT,
FF, CR and space. NUL, Unicode whitespace and noncharacters remain content.

The fixed seed is `0xb1d17e0261108`. The corpus contains 813 texts:

- All 585 texts of length zero through three over `a`, CR, LF, space, HT, NUL,
  `é` and `😀`. Every three-pull front/back pattern is exercised after a fresh
  cursor copy, including the empty and exhausted states.
- All 81 four-character texts over `a`, CR and LF.
- 15 literal boundary profiles, including all UTF-8 widths, noncharacters,
  CRLF, repeated terminators, lone CR and Unicode separators.
- 36 profiles combining every pair of the six ASCII separator bytes with
  Unicode and NUL content.
- 96 seeded profiles up to 511 generated scalars, with additional leading
  and trailing CR/LF boundaries and byte lengths bounded by 2,048.

Each text is exercised through all three cursor families and two actual
backing layouts: native byte arrays with stride `-8` and packed raw byte views
with stride `+1`. Selected texts begin at byte origins 3, 5 or 7. This gives
**4,878 cases, 276,732 pulls, 129,686 yielded items and 77,262 cursor copies**.
The longer schedules mix both cursors and both directions, copy either cursor
into the other, and restart either from an unchanged original cursor. Each
case drains both cursors and probes both ends repeatedly after exhaustion.

## Observations and protocol

The Lanius producer uses generic helpers bounded by both `Iterator` and
`DoubleEndedIterator`. Every yielded text item includes its original-relative
start, byte length, actual stride and complete bytes. Every scalar includes
its original byte offset and value. Pulls distinguish `None` from `Some` of an
empty line. Copy actions are framed explicitly. The selected `Text` descriptor
is observed before and after traversal; all 2,056 backing cells, including
guards outside the selected text, are compared after each case.

The driver starts one native process for the complete batch. Input is six
little-endian u64 fields followed by the selected UTF-8 bytes and action
bytes. Output contains fixed-width little-endian metadata and explicitly
framed item bytes. No JSON or hashes replace item comparisons. Unexpected
exit status, stderr, missing output and extra output fail the verifier.

## Verification status

Host-only verifier controls pass for all 4,878 cases and reject ten deliberate
output corruptions covering descriptor metadata, empty-item tagging, item
offsets, copy framing, bytes, immutable backing and truncated/extra framing.
These controls test the reference and verifier; they are separate from native
library execution. The root-owned native gate passed one test in 5.87 seconds,
with a separate Rust build of 1.75 seconds:

```text
stdlib_text_bidirectional_model_execution::independent_bidirectional_text_matches_partitions_offsets_copies_and_exhaustion
```

The receipt is `target/stdlib-work/text-bidirectional-model.log`. It confirms
the complete batch: 4,878 cases, three families, two layouts, 276,732 pulls,
129,686 yielded items and 77,262 cursor copies with seed `0xb1d17e0261108`.

The tested target is native Linux x86_64. GPU use during compiler execution
does not establish GPU device execution of these cursors. This finite corpus
is not a proof, a performance benchmark or lifetime/alias enforcement. Backing
validity, immutable contents, nonoverlap where required and physical lifetime
remain caller obligations.
