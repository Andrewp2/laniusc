# HomedParamStore

A borrowed parameter's entry store (lowering-spec S6c, 1). The heap side is `HomedLetStore.firstStore`
(shared with `HomedLetStore`) at the parameter's own cell, with Core's state unchanged. The local's value
comes from `HomedCorr.values`, because it was unhomed. The scope stays as it is: `HomedCorr` does not read
`Binding.home`, and only the context gains the home. The other ids' cells differ from the parameter's
(the hypothesis `distinct`), so they stay unhomed.
