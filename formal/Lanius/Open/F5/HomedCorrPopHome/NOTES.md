# HomedCorrPopHome

`locals`, `homedTy`, `unhomed`, `refs.homes` from the outer `HomedCorr` (the locals and frame slot are the same). `values`, `unviewed`, `viewed` from the inner one: an outer binding's cell is not `x`'s, so it is unhomed inside too; its value names no `x` (`HoldsAt` drop). `refs.refs`: for the `let`'s id, the outer `HomedCorr` (hypothesis); for others, the inner one, where the reference's cell is not `x`'s (it is an outer binding's value).
