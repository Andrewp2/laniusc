# Direct borrowed slice segmentation contracts

The authoritative behavior is `docs/library-slice-segmentation-plan.md`.
These fixtures exercise the checked `core::slice::split`, `split_inclusive`
and `chunk_by` factories through their canonical shared iterator implementations.

## Registered gates

`tests/stdlib_slice_segmentation_execution.rs` registers five groups:

- `slice_segmentation_all_three_generic_cursors_execute_tiny_admission`:
  all three APIs over a record containing Option<bool>, including Some(false),
  generic Iterator<View<T>> helpers, exact offsets and callback totals.
- `slice_segmentation_partitions_callback_effects_bounds_and_strides_execute`:
  20 literal input/relation cases across two actual byte layouts and all three
  families (120 complete traversals). It checks every returned offset/length,
  byte content, unchanged backing, exact callback prefix after every result,
  every callback operand, guard entries and repeated exhaustion. Adjacent
  policies include a nontransitive ascending-by-one relation. Null-backed
  invalid metadata must fail before access/callbacks; a valid empty view at
  i32::MAX requires no access. All three unbounded factories also admit a
  descriptor with a policy that has no Mapper implementation.
- `slice_segmentation_compound_values_alias_edits_and_borrowed_composition_execute`:
  records with nested Option<Option<bool>> and u64-array payloads, zero-sized
  elements, zero/partial Take, bounded fold, forked cursors and shared adapter
  copies. Permitted between-pull edits change future values and policy state.
  A ChunkBy witness edits both operands following an observed false boundary,
  requiring fresh reads and exactly one observation of each visited pair.
  Executing byte-cursor controls supply exact-size and reverse capabilities.
- `slice_segmentation_enforces_mapper_item_and_output_capabilities`:
  six independent source-local rejections for missing unary Mapper, wrong
  unary item/output, and wrong adjacent Pair/output. Construction remains
  unbounded; the marked generic traversal call must reject with LNC0008.
- `slice_segmentation_does_not_claim_reverse_or_exact_size`:
  six rejections, checking both unsupported capabilities for each family.
  These negative fixtures establish capability rejection; successful behavior
  is established by the three separate executing groups.

Generic exhaustion helpers use explicitly typed Option locals and direct
matches, preserving the known generic chained-Option dependency without
specializing the public API. No new production or compiler implementation is
included in this fixture set. Independent larger models, live-owner tests and
the record-summary application have separate drivers and receipts.

## Execution gate and scope

Each positive fixture compiles through the GPU compiler to a Linux x86_64 CPU
executable, passes strict ELF admission/shared in-function jump validation,
and executes under a 15-second child timeout. Its complete syscall trace must
contain exactly one successful launch and one successful exit, with no other
host effects. Stdout/stderr must be empty. Callback instrumentation changes
only its caller-owned memory. Root performs serial compiler/native execution
under the library lock and bounded outer command; this owner runs neither.

This is native CPU evidence, not user-program GPU execution, broader target
support or formal verification. Callers remain responsible for physically
backed ranges, stable lifetime, valid cursor state and callback non-reentrancy.
No implicit allocation, clone, destruction or cleanup transfer is promised.

## Receipts

- Tiny generic admission accepted: 1 test in 5.05 seconds, separate Rust build
  4.37 seconds, with its full pure syscall trace;
  `target/stdlib-work/slice-segmentation-admission.log`.
- The remaining four groups passed in 11.76 seconds (Rust build 0.18 seconds):
  both native contracts/composition fixtures with full pure syscall traces,
  and both capability-rejection groups covering all 12 negative fixtures;
  `target/stdlib-work/slice-segmentation-direct.log`.
- All five registered groups are accepted across these two runs on the frozen
  sources below. Independent source review also passed the exact partitions,
  callback/alias timelines, compound/ZST values and capability boundaries.
  No rerun or source change followed acceptance.

## Frozen sources

| Source | SHA-256 |
| --- | --- |
| `tests/stdlib_slice_segmentation_execution.rs` | `9fa26cb0c9a82b298de4af2d66606585db1bf1ef9daa831820ec2b45ecf02378` |
| `admission.lani` | `f797298795b903a82515bed3d51d7f8b15fe0556d8a09fd9872de995027ef6aa` |
| `composition.lani` | `3d0d29adfbde8ef4e7d50c7d45f5bc08d3f616ca406a99a0497d1ff23d8d4c32` |
| `contracts.lani` | `0213d9815f5b6bb23496871e9bc1bf8e99a39b9e7f20a08e793b1b923a34edf5` |
| `negative_chunk_exact.lani` | `d64302d7faf01074d4b17e89ada00dc3bdbd67232ba8ac05c1400bcf95ed10c1` |
| `negative_chunk_reverse.lani` | `0e475a47546ea7a182681d14192fd002373318f3edc135165cdbeeda1cf586e3` |
| `negative_chunk_wrong_output.lani` | `24088678396e24bd50ccb90703f3152a1b92106a4a300cb62f81f8a5ea30b660` |
| `negative_chunk_wrong_pair.lani` | `2d2d767ed4fbe02f96d6673bc418a40f3564c084362f576863a972b67ba591e9` |
| `negative_inclusive_exact.lani` | `8f2ec495480619f5e8a34b13414605d999a38e3821785a8c430d4e1d192acd48` |
| `negative_inclusive_missing_mapper.lani` | `b2f0713f401239acc880b3a8ab74c02e450b9af4a02fc14c740b5ed747ef133b` |
| `negative_inclusive_reverse.lani` | `d3c42956d7df06a2accb1b4b5f8450202878ffaa2d4f8dce6f1ce9b08d592062` |
| `negative_inclusive_wrong_item.lani` | `521f90180e0de6655826fe947394e76951ecd0e7065d94be009cfb1b1213ebe7` |
| `negative_split_exact.lani` | `416ccc69ef8bee70f7007da8825adadd7f905cfd2b942c43a80bbc4d92a9e674` |
| `negative_split_missing_mapper.lani` | `65ba2c7031ae8cc54d9cb69342e41c6b5694dc0d6f898cfc5493f52b47fb8aef` |
| `negative_split_reverse.lani` | `8919ef78df350938dc0f04639fdda00f6dc117a616170e7888dad72968c4bde6` |
| `negative_split_wrong_output.lani` | `d18631ed99b91a1f3dfe7ce61462905145563bbd1d62f9fa944d94e2cdff7a3d` |
