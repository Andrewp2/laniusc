# OptimizeKeepsNumbers

- 11-03 (leafB): stated as an open leaf of the compile side (GenPC's SelfP02, `compile_optimized`'s step:
  `compile_program (optimizeProgram p)` needs `nb ≤ K` and `funcsTemps ≤ K` of a result no post
  bounds). Only a value fact, by induction over `Stmt.optimize`, `Expr.optimize`, `Expr.subst`,
  `Stmt.factsAfter` (facts' slots and atoms come from the body) and `optimizeAll`/`substAll`.
  The validator (`validate`) does not give it: `Stmt.agrees` compares behaviour, not numbers.
