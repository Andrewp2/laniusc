# PlaceLoad

Mini side, the deref-load shape of target/claude-work/leafA/lowering-spec.md. `PlaceAddr` gives the home `x ∈ places` (an index `i` by `List.mem_iff_getElem?`), the sub-place's address and the code's run with the address in `t`. The address is below `2 ^ 62` (`Homes.sub_lt`), so `t`'s word reads back as it. Then `RefLoad` at `r = t` (apart from the target slots), and `Exec.seq`.
