# FrontEndOutputSmall

- 11-03 (leafB): stated for PreCompileWords.red2; not attempted. The bound `2 ^ 48` leaves room over
  `5 * 2 ^ 40 + 5` (validated trees from files lower than `2 ^ 40`).
- 11-03 (leafB): still needed by PreCompileWords.red2 and left in place. The size plan does not
  replace it with a whole-program `sz p <= A * words + B`, because that is false (monomorphization,
  see PreCompileSourceV2/NOTES.md 11-03). A per-function size bound together with `tw p <= weightLimit`
  is the proposed replacement.
- 11-03 (leafB): not needed by PreCompileWords.red3, which takes the height from PostFrontEndWords
  (proved) and the budget, as red1 does. It may be false as stated. A match over v variants
  whose wildcard arm comes last is a list of v arms (`matchArm` chains after lowering). Nesting k such
  matches gives a height of about k * v from O(k + v) words, which is up to 2^60 under 2^31 words.
- 11-04 (leafA): off the chain. Only red2 uses it; red3 to red6 take the height from PostFrontEndWords.
  Not attempted, since it is probably false (the nested-wildcard argument above).
