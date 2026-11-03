# BorrowRefHeld

`RPlace.addr_exec` (as PlaceAddr) gives the address in `t`. The sub-place lies inside its home block (`SrcType.sub` offsets are at most `8 * words`), which is below `2 ^ 62` (`Homes.small`), so the word's `toNat` is the address and `RefTo` holds.
