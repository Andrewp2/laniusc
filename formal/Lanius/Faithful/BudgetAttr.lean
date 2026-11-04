module

public import Lean

@[expose] public section

/-- The rewrites `qsimp` runs the cost semantics with (`Budget.lean`). -/
register_simp_attr budget_rule

/-- The rewrites that decide a condition from a case's hypothesis (`budget`). -/
register_simp_attr budget_cond
