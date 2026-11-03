# CoreBorrow

Core only. `evalExpr (.borrow T p)` is `evalPlace .read` (CorePlace), with `value = some v` and `raw = none`, giving `.reference T root projections`.
