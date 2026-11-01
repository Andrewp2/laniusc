# Literal text matching and replacement

At `eef87def`, Text has literal search and splitting, and String has range
edits, join and repeat. Literal match iteration and whole-result replacement
are missing. This increment completes that shared operation family; the full
standard and extended library goal remains open.

## Contract

Use the existing valid UTF-8 Text invariant and literal search engine. The
[Rust string reference](https://doc.rust-lang.org/std/primitive.str.html#method.match_indices)
provides a comparison for leftmost nonoverlapping matches and
[first-N replacement](https://doc.rust-lang.org/std/primitive.str.html#method.replacen).
Lanius adds explicit allocation errors and an output-byte limit.

```text
Text.match_indices(needle: Text) -> MatchIndices
MatchIndices.borrow() -> &MatchIndices
Iterator<Pair<i32, Text>> for MatchIndices
alloc::string::replace(text, needle, replacement: Text, max_output: i32)
    -> Result<String, alloc::string::Error>
alloc::string::replacen(text, needle, replacement: Text,
                       max_matches: u64, max_output: i32)
    -> Result<String, alloc::string::Error>
```

The canonical Pair is core::pair::Pair. Its first field is a byte index relative
to the source Text; second is the matching source subview with original stride.
Nonempty matches advance by needle length. An empty needle matches every scalar
boundary, including both ends; empty text has one such match. A done flag avoids
incrementing the terminal i32 index. Cursors are fused, allocate nothing, and
copy independent positions over shared immutable backing. No reverse or
ExactSize capability is implied. Valid UTF-8, physical backing and stable
lifetimes are caller obligations, as for existing Text methods. Forged Text
descriptors have no new checked-admission guarantee.

Replacement uses this public cursor in a measure pass and a fill pass, sharing
the existing search engine. Select only original leftmost nonoverlapping matches;
inserted bytes are never searched. A full u64 count handles the possible
i32::MAX + 1 empty-pattern boundaries. Count zero and no-match results still
copy into independent owned storage. Source, needle and replacement may overlap
one another because they remain read-only throughout both passes.

Negative max_output returns Bounds before searching. Compute the complete final
length in u64: exceeding i32::MAX returns CapacityOverflow; otherwise exceeding
max_output returns the new OutputLimit variant. Do not reject a large source
before measuring a shrinking result. Preflight precedes one exact allocation;
empty output allocates nothing. AllocationFailed returns no partial owner.
Every error preserves inputs and existing owners. A successful nonempty result
has one cleanup authority and survives destruction of input owners.

Reuse Text.find_from, UTF-8 widths, Iterator, Pair, String.append_reserved and
Vec reservation. Worst-case search is O(source bytes * needle bytes), with two
passes for replacement, plus output copying and O(1) auxiliary storage. This
increment adds no linear-search or throughput claim, normalization, case folding,
grapheme interpretation, regular expression or in-place replacement API.

## Consumer and verification

The literal_rewrite stdin/stdout program uses checked UTF-8 arguments, bounded
owned input, replacement and bounded output. Initial policy: 256 KiB input,
256-byte needle, 4096-byte replacement and 1 MiB output. Finish validation and
replacement before writing stdout; write errors may leave a confirmed prefix.
Read/write attempts and manual owner cleanup remain explicit. It preserves
all bytes including NUL and line endings. No automatic newline is added.

Eight agents own matcher, owned replacement, program, independent model,
direct/resource tests, program tests, docs and independent review. Root owns
integration and native execution. Tests cover exact Unicode byte offsets,
empty/overlapping patterns, literal replacement, count/output edges, real strides,
cursor copies/exhaustion, generic composition, genuine capacity overflow using
valid backing, reached allocation failure with recovery and full cleanup.
An independent Unicode oracle compares complete outputs. Targeted existing
Text/String regressions cover the shared source and error-enum additions.

Root alone runs compiler/native/Cargo commands serially under
target/stdlib-work/library-gpu.lock; every outer command is capped at 100 seconds.
Preserve human README, AI_POLICY, CONTRIBUTING, tests/common, std/vec and core/mem.
No compiler/IR/ABI/extractor/proof edits. New compiler limitations need a minimal
reduction and a dependency report. Initial evidence is Linux x86_64 CPU output
from the GPU compiler; user-program GPU execution and proofs remain separate.
The accepted receipts below cover this increment only.

## Accepted increment

All five new library groups and all four application groups pass on Linux
x86_64 CPU output from the GPU compiler. Tested production hashes were Text `b8495da2`,
String `dc9ccb76` and literal_rewrite `e1a142ec`. Independent source, model and
resource reviews pass; no compiler change or new compiler dependency was needed.
Final whitespace checking removed one extra trailing newline from the program,
yielding `513c569e`; all other source bytes are identical to the tested program.

| Gate | Result | Receipt under target/stdlib-work/ |
| --- | --- | --- |
| Tiny matcher/replacement admission | 1/1, 5.35 s; build 1.12 s | text-replacement-admission.log |
| Matcher, owned limits and owner recovery | 3/3, 11.22 s; build 1.20 s | text-replacement-direct-resources.log |
| Independent Unicode model | 1/1, 6.86 s; build 1.08 s | text-replacement-model.log |
| Final application model/admission/limits/faults | 4/4, 9.91 s; build 0.19 s | text-replacement-app-final.log |
| Existing String contract regression | 1/1, 11.59 s; build 1.08 s | text-replacement-existing-string.log |
| Existing Text reference regression | 1/1, 6.20 s; build 1.14 s | text-replacement-existing-text.log |

The model covers 440 cases, 13,883 pulls and 4,033 replacement calls across
eight layouts, with seed `0x7e871a0261116`. Its 3,182 successes, 440 Bounds
and 411 OutputLimit results compare complete data. Separate host controls
reject 22 transcript corruptions. Direct tests cover 19 owned cases, a 2^31-byte
conceptual result from valid smaller input buffers, pure matching, generic
composition and one
reached output-allocation failure followed by retry with the same input owners.
The two owner processes each release all six successful mappings; the failed
allocation is not counted as an owner. Scale inputs are 4,096 and 262,144 bytes;
these observations are not an isolated throughput measurement.

The application has 94 unique native cases: 29 model, 30 admission, seven
limits and 28 I/O/allocation cases, including twelve reached allocation denials.
An initial 9.71-second run passed with a weaker ownership observer. Review
required an explicit live-input/argument check at output allocation; the final
observer adds that assertion and negative controls. The focused rerun above
passes with unchanged application source. These runs are not additive counts.

Standalone compilation and both exact documented pipelines pass separately,
recorded in text-replacement-cli-build.log and text-replacement-cli-examples.log.
The output is exactly Xba (three bytes) and the eight-byte UTF-8/NUL insertion
example. Historical hash-bound compiler reproductions remain byte-preserved;
this increment makes no updated reproduction claim. Manual ownership, the
documented quadratic search bound, other targets and formal verification remain
explicit limits. The broader library roadmap stays open.
