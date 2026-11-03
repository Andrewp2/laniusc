# HomedCorrLocal

Without a home: as `Corr.local` (`values`, the cell from `locals`). With a home: `RefsAgree.homes` gives the home and its cell, which is the binding's (`locals`), of the binding's type (`homedTy`); `Homes.holds` gives the value, and Core's `.local` reads the cell (`CoreRefs.evalExpr_local`).
