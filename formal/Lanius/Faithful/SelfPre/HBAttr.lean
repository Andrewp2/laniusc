import Lean

/-! The simp set of the list height `hb` (`SelfPre/HB.lean`), declared apart from
its lemmas as a simp attribute must be. -/

register_simp_attr hb_simp

/-- Report each value `hbFacts` bounds or fails to bound. -/
register_option lanius.hb.debug : Bool := {
  defValue := false
  descr := "report the height facts post_auto and pre_auto find"
}
