# Literal text matching and replacement model

The Lanius producer executes `Text.match_indices`, generic iteration and
`alloc::string::{replace,replacen}`. A separate Python oracle establishes
complete matches with Unicode `re.finditer(re.escape(needle), source)` and
complete replacement output with Unicode `str.replace`. Patterns and
replacement bytes are literal. The reference does not copy the Lanius search,
iterator state, or measurement/fill passes.

Unicode indices from Python are converted to UTF-8 byte offsets using each
scalar's encoded width. The reference therefore distinguishes scalar, byte and
grapheme boundaries. Empty needles yield every scalar boundary, including one
match on empty input. Python's signed replacement count is safely clamped to
`scalar_count + 1`, which bounds every possible literal match sequence, before
calling `str.replace` with the semantically equivalent count.

## Fixed finite corpus

Seed `0x7e871a0261116` gives **440 cases**:

- 280 exhaustive pairs: all 40 sources of zero through three scalars over
  `a`, `b` and `é`, each with seven selected empty/present/absent/overlapping
  needles.
- 40 explicit cases covering longer overlaps, all UTF-8 widths, NUL, CRLF,
  regex punctuation treated literally, literal backslashes and `$`, combining
  marks, variation selectors, ZWJ, BOM, noncharacters and shrinking/deleting
  results. Eight of these use actual read-only source subviews for the needle,
  replacement or both.
- 64 seeded cases up to 257 scalars, biased toward empty, present and absent
  needles and repeated near matches.
- 56 additional runs make eight representative cases execute on all eight
  source/needle/replacement layout combinations. Other cases rotate layouts.

Actual native byte arrays have stride `-8`; independently backed packed bytes
have stride `+1`. Text starts rotate among 3, 5 and 7, with guarded backing of
2,056, 264 and 136 cells. Aliased Text subviews use the actual source stride.
All input Text values come from checked UTF-8 constructors and checked slices;
no forged metadata or physical overclaim is used.

Each cursor schedule pulls two independent value copies, copies their current
states in both directions, restarts from an unchanged seed and drains both.
It copies an exhausted cursor and probes both repeatedly. A concrete generic
`Take` composition yields the first three matches and then checks that the
original cursor resumes at the following match. The producer's schedule helper
is itself generic over `Iterator<Pair<i32,Text>>`.

Every item records the complete byte offset, source subview start/length,
actual stride and payload. It also reads the first and last cells of the
original source backing through the returned Text's slice, distinguishing a
source subview from an accidental needle view. `None` remains distinct from
`Some` of an empty match.

Replacement counts include zero, one, the match-count boundaries, `2^32`,
`2^63` and `u64::MAX`. Output limits include exact fit, extra room, one byte
short, zero, `-1` and `i32::MIN`. Complete shrinking output is admitted even
when the source exceeds the output limit. Count-zero and no-match successes
must still return independent owned storage. The model does not freeze a
geometric allocation policy: it asserts only adequate capacity and the
contract's zero-capacity empty output.

For every operation, all input descriptors and all 2,456 backing cells are
observed unchanged. After success, the borrowed views have finished being
used; all three input buffers are overwritten, and the complete owned result
is checked again. Appending `!` to that result and destroying it must preserve
the overwritten inputs. The actual destroyed owner reports zero length and
capacity. Input buffers are restored before constructing new Text views for
the next operation. This is an independence witness, not lifetime enforcement.

## Driver, controls and target scope

The strict binary protocol uses little-endian u64 metadata and complete byte
payloads, with no JSON transport or digest substitution. One native process
handles the whole batch. The driver uses the existing GPU compiler helper,
checks the x86_64 ELF, and requires zero exit status, empty stderr, exact output
framing and the complete fixed summary. The native child limit is 75 seconds;
the host reference limit is 90 seconds. The root-owned native gate passed
**1 test, 0 failures in 6.86 seconds**, after a separate 1.08-second Rust build.
The accepted receipt is `target/stdlib-work/text-replacement-model.log`.
No compiler/native command was run by the model author.

Accepted source SHA-256 values:

- Producer: `2dffcede8c19acfeb6efba5b95e290d2d7937f9b1837720311a7464d64caf587`
- Oracle: `95dca178b8796757efc52082ed3c912784a644823cd6b423d850a08c0977eadc`
- Driver: `17f20cd596743330f275cceb2c2f6c8848f70b5fcb644a0339bcfcd4923c2666`

Selector:

```text
--test stdlib_text_replacement_model_execution literal_matches_and_owned_replacement_match_independent_unicode_model --exact --nocapture
```

Observed complete summary:

```text
text-replacement-model cases=440 pulls=13883 items=5221 copies=4974 operations=4033 successes=3182 bounds=440 output_limit=411 result_bytes=75478 layouts=8 seed=0x7e871a0261116
```

Separate host-only controls passed for the complete 20,256,717-byte synthetic
transcript and rejected 22 deliberate corruptions. These include wrong offsets/stride,
`Some(empty)` tagging, result and guard bytes, input preservation, recycled
backing, destroyed-owner state, counts/limits and truncated/extra framing.
Coherent output-only mutants also model overlapping replacements, searching
inserted bytes and advancing an empty match inside a multibyte scalar. The
corpus includes 220 successful empty outputs, 440 successful count-zero calls,
469 successful `u64::MAX` calls, 440 `replace` calls and 3,593 `replacen` calls.
Host controls check the oracle/verifier separately from native acceptance.

The accepted target is Linux x86_64 CPU execution of GPU-compiled Lanius.
Other targets, GPU device execution, formal proof, actual allocation failure
and true `i32::MAX` capacity overflow belong to separate evidence. Physical
backing, immutable borrowed inputs, lifetimes and one cleanup authority remain
caller responsibilities.
