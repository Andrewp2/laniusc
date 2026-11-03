# PreCompileSourceV4

- 11-03 (leafB): stated to replace PreCompileSourceV3 (probably false: `params_size` adds the parameters'
  sizes with no per-function bound, V3/NOTES.md). The new premise is a plain hypothesis,
  `∀ f ∈ p.funcs, Lanius.Mini.paramsSize f.params ≤ 2 ^ 40`, for the front end's leaf to supply (leafA's
  params-slot limit, FrontEndParamSlots, not yet stated); PreCompileWords.red5 then uses V4 with it,
  FrontEndTypeSlots and FrontEndStmtDepth as red3 does. Struct fields need no premise: a struct's size
  is the sum of its fields' and `ts p ≤ weightLimit` bounds it.
- Work under it: GenPC's SelfP02 (pres, 71 failing at c4336d4de) with the leaves LowerFuncsTemps and
  OptimizeKeepsNumbers; the lowering side's invariants (slots below params + depth) next.
- 11-03 (leafB): red5 (PreCompileWords) uses V4 with FrontEndParamSlots, FrontEndTypeSlots and
  FrontEndStmtDepthV2.
- 11-03 (leafB): `frame_block` probably makes V4 false too, and `room_fits` does not bound it.
  `lower_func`'s precondition has `frame_block`'s right after `params_size`'s: `paramsArrayBytes`
  plus `SrcStmt.arrayBytes`, which adds `declBytes` over every let of the source body (both branches
  of an `if`, every arm) with no cost check between the additions. `room_fits` bounds the weight of
  the Mini body in `compile_func`, after lowering, so nothing bounds the source body's lets when
  `frame_block` runs. Their number is bounded only by the budget (`slice_uses`, which walks every
  node, is charged before), and a wildcard arm copied per variant and nested gives many lets from few
  words. So the sum reaches about `2^25 * 2^62` (`arrayBytesOf ≤ 8 * ts ≤ 2^25` per let). Fix: a
  front-end or lowering check, e.g. `frameBlock` summed against a limit as it adds up (as `stmt_room`
  does), or a per-function bound on the source body's lets before `frame_block`; the same goes for
  any other whole-body sum in lowering (`SrcStmt_array_bytes`, `params_array_bytes`).
