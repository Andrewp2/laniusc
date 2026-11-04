# HomedLetStore

The first store of a homed `let` (lowering-spec S6b, 3), and of a borrowed parameter at entry.
`homeInit` stores a `u8` as a `u32`: `homeView` reads a `u8` home as its 4-byte word, and a new home's
upper bytes are not known, so a 1-byte store (`refSlotAt`) would not do. With `homeInit`, `refSlotAt` is
`slotAt` for every type (`SrcType.homeInit_refSlotAt`), and the stores write the home's native layout.
`HoldsAt.trunc` gives the home's view, the other homes lie apart, then `HomesPush` and `HomedCorrPushV2`.
