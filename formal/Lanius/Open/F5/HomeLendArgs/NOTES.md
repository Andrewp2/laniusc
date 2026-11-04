# HomeLendArgs

`HomesLend` at the callee's entry slots for the two argument words `frame + offset` and the length
(lowering-spec S6b, 6): the home's address is its pointer, since a packed array's pointer is its lowest
byte (`Addressed.pointer`), and it is below `2 ^ 62` (`Homes.small`), so `addOff` does not wrap. With the
copy, the callee's places were the copies then the caller's; here they are the caller's alone.
