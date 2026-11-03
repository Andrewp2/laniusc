# FrontEndTypeSlots

- 11-03 (leafB): stated for PreCompileWords.red3. `ts` is generated (`tools/hb_gen.py --slots`,
  `SelfPre/TS.lean`); `size_le_tySlots` gives a type's own size. It is stated on slot counts, not weights,
  because a slice (and so a struct field or a let of slice type) is never weighed: `[[...[S]]]` built
  through generic arguments has a weight that grows with its depth, while its size is 2.
- 11-03 (leafA): proved by a check rather than through the validator's weights: `untyped_rejected` rejects a
  program unless every type in it, and every type inside one, has at most `weight_limit()` slots (`lim_funcs`,
  SEMANTIC_DECISIONS "The front end's implementation limits"). Proof: `SelfPre/Limits.lean`
  (`frontEndWords_limits`).
