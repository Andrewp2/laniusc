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
- 11-03 (leafA): `frame_block` is now checked as it adds up (compiler.lani `params_room`,
  `block_room`, `block_limit` = 2^31 - 1): each parameter's and let's bytes come out of the room,
  and a block over it is 2^31. So `frameBlock f ≤ 2^31` (`frameBlock_le`, Mini/FrameRoom.lean), with
  no premise, and V4 holds as stated as far as `frame_block` goes. The check changes no result of the
  compiler (`compileSource_unchecked`).
- 11-03 (leafA): the needs are saturated (coordinator's decision on leafB's finding): `need_capped`
  caps each round's need at `need_limit()` = 2^40 and keeps a need at the limit there, and
  `lower_func` rejects a need at the limit. So every need is at most 2^40 and `frame_block + callee
  need` at most 2^31 + 2^40, with no premise. The rooms are not below a fixed bound (a chain of
  callees with blocks makes a caller's need, and so its room, as large as their sum), so the limit
  does change what is accepted: `compileSource_unchecked` says `compileSource p` is the old
  compiler's result when every need is below 2^40 (`NeedsBelow`), and `none` otherwise. A need of
  2^40 bytes of frame memory is more than any binary has (`elf_fits`: stack < 2^40).
