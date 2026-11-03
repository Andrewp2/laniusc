# RefCodeWithin

Induction on `loadsFrom` / `storesFrom` (each access is a `loadByte`/`loadWord` or `storeByte`/`storeWord` at `addOff r _`, one temporary), and on the place (`elementAddr` uses two temporaries, the bounds check one, `refTrap` one).
