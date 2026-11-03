# FrameCorrHomes

For the move off `FrameCorr`. Its places are packed `i32`/`u8` arrays, whose `HoldsAt` does not depend on the places (`fieldsHold_replicate_scalar`), and whose `Addressed.view` is `homeView`. `words ≤ size` for packed arrays, so `FrameCorr`'s bounds give `Homes`'s. `Nodup` turns `FrameCorr.apart` (by distinct members) into `Homes.apart` (by distinct indices).
