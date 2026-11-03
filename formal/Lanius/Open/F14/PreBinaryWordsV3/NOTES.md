# PreBinaryWordsV3

- 11-03 (leafB): replaces PreBinaryWordsV2. True at any budget since compile_program checks the image
  limit as the sizes add up (`room_after`): every binary `compileSource` returns has an image of at most
  2^30 bytes. Proof plan: `compileProgram_spec` (Mini/Correct.lean) for `binary.image.length <=
  imageLimit`, then the pre lemmas of `pack_rounds`, `pack_round`, `round_join` and `image_words` with
  counts below 2^31.
