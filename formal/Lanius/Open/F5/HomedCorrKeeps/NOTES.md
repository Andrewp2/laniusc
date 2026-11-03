# HomedCorrKeeps

As `Corr.keeps`, for the unhomed bindings: their cells are no home's and below the next cell, so kept unless viewed; a viewed array's cell holds an array again (`Keeps.arrays`). `RefsAgree.homes` reads only the locals. `RefsAgree.refs`: a reference local without a home is unhomed (`unhomed`); its cell is kept, or it is a viewed array and so not a reference.
