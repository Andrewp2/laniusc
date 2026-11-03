# PreCompileSourceV4

- 11-03 (leafB): stated to replace PreCompileSourceV3 (probably false: `params_size` adds the parameters'
  sizes with no per-function bound, V3/NOTES.md). The new premise is a plain hypothesis,
  `∀ f ∈ p.funcs, Lanius.Mini.paramsSize f.params ≤ 2 ^ 40`, for the front end's leaf to supply (leafA's
  params-slot limit, FrontEndParamSlots, not yet stated); PreCompileWords.red5 then uses V4 with it,
  FrontEndTypeSlots and FrontEndStmtDepth as red3 does. Struct fields need no premise: a struct's size
  is the sum of its fields' and `ts p ≤ weightLimit` bounds it.
- Work under it: GenPC's SelfP02 (pres, 71 failing at c4336d4de) with the leaves LowerFuncsTemps and
  OptimizeKeepsNumbers; the lowering side's invariants (slots below params + depth) next.
