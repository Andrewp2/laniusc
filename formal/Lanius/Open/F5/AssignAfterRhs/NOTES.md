# AssignAfterRhs

`RPlace.addr_exec` gives the address in `t` from `st` and `hp`; `rhs` keeps `t`; the address is below `2 ^ 62` (as BorrowRefHeld); then `RefStoreV2` at `st₁` and `rhs`'s heap, for the home whose cell is the place's.
