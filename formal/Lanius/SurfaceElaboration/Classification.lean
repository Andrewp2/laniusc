import Lanius.SurfaceElaboration

namespace Lanius.SurfaceElaboration

/-- Type classification precedes literal decoding/range validation. This
    relation deliberately does not assert that a source expression can lower.
    It uses the existing source AST, ground types and operator typing rules;
    it is not part of an extracted program's representation. -/
inductive ExprClassifies (context : Context) : Surface.Expr → Static.GroundTy → Prop where
  | literal (grounded : groundType.toCore context.monomorphization =
      some (Elaboration.literalDefaultType literal)) :
      ExprClassifies context (.literal literal) groundType
  | unary (operand : ExprClassifies context source input)
      (inputCore : input.toCore context.monomorphization = some inputType)
      (outputCore : output.toCore context.monomorphization = some outputType)
      (typed : Typing.UnaryOpHasType (lowerUnaryOp operation) inputType outputType) :
      ExprClassifies context (.unary operation source) output
  | binary (left : ExprClassifies context leftSource leftGround)
      (right : ExprClassifies context rightSource rightGround)
      (leftCore : leftGround.toCore context.monomorphization = some leftType)
      (rightCore : rightGround.toCore context.monomorphization = some rightType)
      (outputCore : output.toCore context.monomorphization = some outputType)
      (typed : Typing.BinaryOpHasType (lowerBinaryOp operation) leftType rightType outputType) :
      ExprClassifies context (.binary operation leftSource rightSource) output

/-- Classification plus a checked literal value yields the real lowering
    relation. Classification alone cannot supply that value or its bounds. -/
theorem ExprClassifies.lowerLiteral
    {literal : Surface.Literal}
    (classified : ExprClassifies context (.literal literal) groundType)
    (value : Elaboration.LiteralElaborates context.target literal
      (Elaboration.literalDefaultType literal) core) :
    ExprLowers context (.literal literal) groundType core := by
  cases classified with
  | literal grounded => exact .literal value grounded

end Lanius.SurfaceElaboration
