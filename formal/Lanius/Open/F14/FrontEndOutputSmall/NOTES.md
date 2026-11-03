# FrontEndOutputSmall

- 11-03 (leafB): stated for PreCompileWords.red2; not attempted. The bound `2 ^ 48` leaves room over
  `5 * 2 ^ 40 + 5` (validated trees from files lower than `2 ^ 40`).
- 11-03 (leafB): still needed by PreCompileWords.red2 and left in place. The size plan does not
  replace it with a whole-program `sz p <= A * words + B`, because that is false (monomorphization,
  see PreCompileSourceV2/NOTES.md 11-03). A per-function size bound together with `tw p <= weightLimit`
  is the proposed replacement.
