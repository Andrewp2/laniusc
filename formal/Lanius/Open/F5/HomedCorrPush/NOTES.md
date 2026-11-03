# HomedCorrPush

As `Corr.push` for the old bindings (their cells are below the next cell, so `bindLocal` keeps them; `HoldsAt.mono` to the longer places). The new binding is homed: its cell is `x`'s. `RefsAgree.homes`: the new id finds `x`; other ids as before, with the frame slot kept. `refs`: an id without a home is not the new one, so its value is as before (`coreLocal_bindLocal`, every scope cell below the next cell) and its slot kept.
