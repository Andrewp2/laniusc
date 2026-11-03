# FrontEndTypeSlots

- 11-03 (leafB): stated for PreCompileWords.red3. `ts` is generated (`tools/hb_gen.py --slots`,
  `SelfPre/TS.lean`); `size_le_tySlots` gives a type's own size. It is stated on slot counts, not weights,
  because a slice (and so a struct field or a let of slice type) is never weighed: `[[...[S]]]` built
  through generic arguments has a weight that grows with its depth, while its size is 2.
