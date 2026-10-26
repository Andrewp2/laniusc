module

public import Lean
public meta import Lean.LabelAttribute

@[expose] public section

/-- The rules `rep` proves representation premises with: a Lean value built
by a constructor is represented by the value built by the matching Core
constructor from representations of its parts. (`register_label_attr`
expanded, with the initializer `meta` as modules need.) -/
public meta initialize repRuleExt : Lean.LabelExtension ←
  Lean.registerLabelAttr `rep_rule "representation rules" `rep_rule
syntax (name := Parser.Attr.rep_rule) "rep_rule" : attr

/-- The rewrites `pure_simp` runs the pure semantics with. -/
register_simp_attr pure_rule
