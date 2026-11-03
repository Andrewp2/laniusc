# HomesCongrV2

HomesCongr with the static region kept (`staticBase`, `statics`), which `Homes.statics` (`Heap.StaticsAt`) needs. Proof: every byte `homeView` reads is at or above the home's address, so at or above `fsp` (`inside`); `SrcType.HoldsAt.congr` on every slot; `Heap.StaticsAt.congr` for the region.
