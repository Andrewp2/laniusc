# Direct bidirectional Text contracts

The authoritative contract is `docs/library-bidirectional-text-plan.md`.
These fixtures exercise borrowed `Text.lines()`, reverse `Scalars`, and reverse
`SplitAsciiWhitespace` through the canonical shared iterator traits.

## Registered gates

`tests/stdlib_text_bidirectional_execution.rs` registers four ordinary gates, plus an ignored compiler dependency probe:

- `bidirectional_text_all_three_cursors_execute_tiny_admission`: all three
  public cursor families, forward/backward pulls, CRLF and final LF,
  multibyte scalar indices relative to the original selected Text.
- `bidirectional_text_exact_partitions_indices_mixed_ends_and_strides_execute`:
  15 literal cases, both actual byte layouts and eight direction schedules
  for all three families. This gives 720 complete cursor traversals, plus
  repeated either-end exhaustion and separate null-backed empty cursors.
  Cases include LF/CRLF, lone CR, CRCRLF, leading/repeated terminators,
  all six ASCII word separators, NUL, Unicode nonseparators, every UTF-8 width,
  encoding boundary scalars, noncharacters and BOM. It checks returned bytes,
  original absolute Text offsets, relative Scalar indices, actual strides,
  nonzero selected starts and complete unchanged backing with outer guards.
- `bidirectional_text_shared_reverse_take_and_bounded_composition_execute`:
  Rev, zero/partial Take, explicit dual-bound generic calls, bounded reverse
  folds, independent whole/partial cursor copies, shared adapter copies and
  captured Text descriptors. It includes an executing ExactSize positive
  control over the existing byte cursor.
- `bidirectional_text_does_not_claim_metadata_only_exact_size`:
  three source-local negative fixtures require ExactSize from Lines, Scalars
  and SplitAsciiWhitespace independently. Each must reject with LNC0008 at
  its marked capability call. These negative checks establish rejection,
  while the other three gates establish actual successful native behavior.

The literal line expectations use only LF and CRLF. Unicode line/paragraph
separators and NEL remain content. Word expectations use exactly bytes
9, 10, 11, 12, 13 and 32. Independent larger partition models and live owned
backing tests have separate owners/drivers; their receipts are not claimed here.

## Execution and limits

Successful fixtures compile through the GPU compiler to Linux x86_64 CPU
executables, require strict ELF admission and shared in-function jump checks,
and execute under a 15-second child timeout. Their complete syscall trace must
contain exactly one successful launch and one successful exit, with no other
host effects. Stdout and stderr must remain empty.

Root performs all compiler/native execution serially under the library lock
and a bounded outer command. This fixture owner ran no compiler/native commands.
The tests establish the documented native CPU profile, not user-program GPU
execution, other targets, compiler-enforced lifetimes or formal verification.
Input backing must remain live, valid and immutable; invalid physical backing
with nonempty Text or forged cursor fields is outside this contract.

## Receipts

- Tiny admission accepted: 1 test in 5.59 seconds, including its complete
  no-host-effects trace; `target/stdlib-work/text-bidirectional-admission.log`.
- ExactSize rejection group accepted in the first remaining-gates run:
  `target/stdlib-work/text-bidirectional-direct-final.log`. The combined run
  took 7.59 seconds (Rust build 0.19 seconds): one group passed and two failed
  during compilation. The two failures were LNC0027 on chained generic
  `cursor.next().is_none()` / `next_back().is_none()` expressions, so neither
  failing fixture reached native execution.
- Those exhaustion helpers now use explicitly typed `Option<T>` locals and
  direct pattern matches. Generic traversal, call order, repeated pulls and
  capability bounds remain unchanged. The corrected direct and composition
  gates passed together: 2 tests in 7.99 seconds (Rust build 0.18 seconds),
  with complete no-host-effects traces;
  `target/stdlib-work/text-bidirectional-direct-revised.log`. Together with
  admission and the accepted rejection group, all four ordinary groups have
  accepted receipts.
- The [paired compiler dependency](../../stdlib_compiler_state/text_option_chain/README.md)
  preserves a reduced chained expression and typed-match control over an
  actual-backed slice cursor. Its separate ignored, positive-expected gate
  must execute both successfully when the compiler limitation is repaired.
  The driver was factored to share the unchanged execution checks with this
  probe after the ordinary-gate receipts above. Its explicit run took
  4.79 seconds (separate Rust build 1.69 seconds): the typed control executed
  with a pure trace, then the chained case failed LNC0027 at line 7. The
  overall ignored test failed (0 passed, 1 failed), as its positive
  expectation requires. See `target/stdlib-work/text-option-chain-dependency.log`.
  Production Text and compiler sources were not changed for the workaround.

## Frozen sources

| Source | SHA-256 |
| --- | --- |
| `tests/stdlib_text_bidirectional_execution.rs` | `c3ae5c1ea8b642b767b5707f5a6337099e72c094cb7ba5ea2fd45cfb3332cdfa` |
| `admission.lani` | `98018feebe11e0cc8dd716b680f228061871fefaabedb6e76320973a2a794fc7` |
| `contracts.lani` | `636e8b0281f68e94c13aad3a085f9760e1f4e0c7390ad7342a3d924239cb2477` |
| `composition.lani` | `daefca086aec0218e97614cb3092be51acb66f64af7c4465186ecd6f6bf1558f` |
| `negative_exact_lines.lani` | `4b3822fe3361ab0d0243209c3bd1b8167fcf61ec3bee7eedbd462002c647b0ce` |
| `negative_exact_scalars.lani` | `8a9e423cf020392a99ab2b75f9dd232205a8e7d52ed771db520001d5c40dd94d` |
| `negative_exact_words.lani` | `2298022fd9bdd93bbf2ba070f5a1b403d4b937cce0e34c28e860e3315bc654bc` |
