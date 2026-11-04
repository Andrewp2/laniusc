# PreBinaryWordsV3

- 11-03 (leafB): replaces PreBinaryWordsV2. True at any budget since compile_program checks the image
  limit as the sizes add up (`room_after`): every binary `compileSource` returns has an image of at most
  2^30 bytes. Proof plan: `compileProgram_spec` (Mini/Correct.lean) for `binary.image.length <=
  imageLimit`, then the pre lemmas of `pack_rounds`, `pack_round`, `round_join` and `image_words` with
  counts below 2^31.
- 11-03 (leafA): proved (Proof.lean): `binary_small` (`compileSource_some`, `compileOptimized_some`, `compileProgram_spec`: image ≤ 2^30, entries ≤ image / 24), then the pre lemmas of `pack_round`, `pack_rounds`, `round_join` and `length_of_usize` from the counts (`packRound_count`, `packRounds_count`: count + rest = length).
