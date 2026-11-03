# LowerFuncsTemps

- 11-03 (leafB): stated as an open leaf of the compile side (GenPC's SelfP02, `compile_declared`'s step
  needs it for `compile_lowered`'s `optTemps x ≤ K`). The cut: `compile_func`'s `locals + temps`, added
  before its room check, is the only use of an unbounded temporaries count; `Stmt_temps`, `Expr_temps`,
  `args_temps`, `compile_func`, `compile_funcs`, `compile_program`, `compile_or` and `compile_lowered`
  now pass with `funcsTemps ≤ K` carried down (`COMPILE_OVERRIDES`).
- Reordering `compile_func`'s checks so that `room_fits(stmt_room(image_limit(), func.body))` comes before
  `locals + temps` would make this leaf unnecessary: under the check the body's weight is at most
  `image_limit`, and its temporaries are at most its weight. Not done now (11-03, coordinator: three
  .lani changes are queued and each forces a full regeneration); cheap once regeneration is one command.
- The weight (nodes) has no such bound: a copied operand is counted again, so it can double per step.
