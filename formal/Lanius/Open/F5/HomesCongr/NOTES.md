# HomesCongr

`homeView` reads only bytes in the block (each slot's bytes lie within `8 * words`, by `homeOk`), which are at or above `fsp` (`inside`); `SrcType.HoldsAt.congr` on the slots below `ty.size`.

## False as stated: replaced by HomesCongrV2 (leafC, 11-03)

`Homes.statics` is `hp.StaticsAt sx`, which needs `hp.staticBase` and `hp.statics`, but the hypotheses keep only `limit`, `frameSize`, `fsp` and the bytes at or above `fsp`. Counterexample (checked with lcheck, not committed): `places = []`, `bud = ⟨0, 0⟩`, `sx = {}`, `st = st' = {}`, `hp = { bytes := fun _ => 0, cursor := 0, limit := 0 }` (all of `Homes` vacuous, `StaticsAt` by `rfl`), `hp' = { hp with statics := [0] }`; then `hp'.StaticsAt {}` would need `[0] = []`. `HomesCongrV2` adds `hp'.staticBase = hp.staticBase` and `hp'.statics = hp.statics`, which every intended step keeps (`Heap.writeLE_statics`, allocation). `RefsLemmas` has `HomesCongr` as a conjunct, so it is false too and needs a V2 with `HomesCongrV2`.
