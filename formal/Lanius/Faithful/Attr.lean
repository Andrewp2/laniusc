import Lean

/-- The rules `rep` proves representation premises with: a Lean value built
by a constructor is represented by the value built by the matching Core
constructor from representations of its parts. -/
register_label_attr rep_rule

/-- The rewrites `pure_simp` runs the pure semantics with. -/
register_simp_attr pure_rule
