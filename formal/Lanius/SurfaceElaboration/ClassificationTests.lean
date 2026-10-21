import Lanius.SurfaceElaboration.Classification

namespace Lanius.SurfaceElaboration.ClassificationTests

/-- Classification promises a type, not valid literal text. -/
theorem magnitudeClassifies (context : Context) :
    ExprClassifies context (.literal (.integer "2147483648")) (.scalar (.signed .i32)) :=
  .literal rfl

example (context : Context) :
    ExprClassifies context (.literal (.integer "not a number")) (.scalar (.signed .i32)) :=
  .literal rfl

theorem maximumLowers (context : Context) :
    ExprLowers context (.literal (.integer "2147483647")) (.scalar (.signed .i32))
      (.value (.signed .i32 2147483647)) :=
  (ExprClassifies.literal rfl).lowerLiteral (.signedInteger (by decide)
    (show (2147483647 : Int) ≤ 2147483647 from Int.le_refl _))

private theorem minimum (context : Context) :
    Elaboration.SignedMinimumLiteralElaborates context.target "2147483648" .i32
      (.value (.signed .i32 (-2147483648))) :=
  .minimum (magnitude := 2147483648) (by decide) rfl

/-- The old full-lowering cache invariant cannot hold at this positive child. -/
theorem magnitudeCannotLower (context : Context) :
    ¬ ∃ core, ExprLowers context (.literal (.integer "2147483648")) (.scalar (.signed .i32)) core := by
  rintro ⟨core, lowered⟩
  cases lowered with
  | literal value grounded => exact (minimum context).not_positive_literal value

/-- The whole negative expression is nevertheless a valid source program. -/
theorem negativeMinimumLowers (context : Context) :
    ExprLowers context (.unary .negative (.literal (.integer "2147483648"))) (.scalar (.signed .i32))
      (.value (.signed .i32 (-2147483648))) :=
  .signedMinimumLiteral (minimum context) rfl

#print axioms maximumLowers
#print axioms magnitudeCannotLower
#print axioms negativeMinimumLowers

end Lanius.SurfaceElaboration.ClassificationTests
