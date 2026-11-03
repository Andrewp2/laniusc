# CoreAssign

Core only. `evalExpr (.assign .set ...)`: `evalPlace .address` in `st` (CorePlace), the right side from `st` to `st₁`, `evalAssignValue .set` (`.ok right`), `writeResolvedPlaceNative` with `raw = none` in `st₁` (`writeResolvedPlace`: `[]` is `assignCell`, otherwise `replaceProjectedValue` then `assignCell`), then the view sync: `ViewsHold st'` from `st₁`'s and the cell not being a root, then `Views.syncTo_ok`.
