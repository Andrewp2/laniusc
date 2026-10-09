import Lanius.SurfaceElaboration
import Lanius.Semantics.Constant
import Lanius.Typing.Check
import Lanius.Compiler.NameResolutionCheck

namespace Lanius.Compiler.ConstantExprCheck

open Lanius

/-- The original expression and its computed value remain connected by both
    source elaboration and the executable Core semantics. -/
structure CheckedInteger (program : Core.Program) (available : List ConstantId)
    (context : SurfaceElaboration.Context) (source : Surface.Expr) where
  expression : Core.Expr
  value : Core.Value
  lowers : SurfaceElaboration.ExprLowers context source (.scalar (.signed .i32)) expression
  evaluates : Semantics.ConstantEvaluates program available expression value

private def checkMinimum (program : Core.Program) (available : List ConstantId)
    (context : SurfaceElaboration.Context) (source : Surface.Expr) :
    Option (CheckedInteger program available context source) :=
  match source with
  | .unary .negative (.literal (.integer text)) => do
      match parsed : Elaboration.parseUnsignedInteger text with
      | none => none
      | some magnitude =>
          if minimum : Int.ofNat magnitude = -(Typing.signedMin context.target .i32) then
            some {
              expression := .value (.signed .i32 (Typing.signedMin context.target .i32))
              value := .signed .i32 (Typing.signedMin context.target .i32)
              lowers := .signedMinimumLiteral (.minimum parsed minimum) rfl
              evaluates := .value }
          else none
  | _ => none

/-- Initializers have no locals. Ordinary module, visibility, ambiguity, and
    declaration-kind resolution still apply to every referenced name. -/
def resolveConstant (context : SurfaceElaboration.Context) (path : Surface.Path) :
    Option { entry : SurfaceElaboration.ConstantEntry //
      SurfaceElaboration.ResolvesConstant context path entry } :=
  match empty : context.locals with
  | [] => do
      let resolved ← NameResolutionCheck.checkGlobal context .value path
      match found : context.constants.find?
          (fun entry => decide (entry.declaration = resolved.symbol.declaration)) with
      | none => none
      | some entry =>
          some ⟨entry, .intro (by
            unfold SurfaceElaboration.GlobalPathNotShadowed
            split <;> simp [SurfaceElaboration.NoLocalNamed, empty])
            resolved.symbol resolved.resolved (List.mem_of_find?_eq_some found)
            (of_decide_eq_true (List.find?_eq_some_iff_getElem.mp found).1)⟩
  | _ => none

/-- Arithmetic uses the Core evaluator. Referenced values are available only
    after their source initializers have passed the program-level check. -/
def checkInteger (program : Core.Program) (available : List ConstantId)
    (context : SurfaceElaboration.Context) (source : Surface.Expr) :
    Option (CheckedInteger program available context source) :=
  (checkMinimum program available context source).orElse fun _ =>
  match source with
  | .literal (.integer text) =>
      match parsed : Elaboration.parseUnsignedInteger text with
      | none => none
      | some number =>
          if upper : Int.ofNat number ≤ Typing.signedMax context.target .i32 then
            some {
              expression := .value (.signed .i32 number)
              value := .signed .i32 number
              lowers := .literal (.signedInteger parsed upper) rfl
              evaluates := .value }
          else none
  | .unary op operand => do
      let input ← checkInteger program available context operand
      let typed ← Typing.Check.checkUnary (SurfaceElaboration.lowerUnaryOp op)
        (.scalar (.signed .i32)) (.scalar (.signed .i32))
      match evaluated : Semantics.evalUnaryValue program.target
          (SurfaceElaboration.lowerUnaryOp op) input.value with
      | .error _ => none
      | .ok value => some {
          expression := .unary (SurfaceElaboration.lowerUnaryOp op) input.expression
          value
          lowers := .unary input.lowers rfl rfl typed.down
          evaluates := .unary input.evaluates evaluated }
  | .binary op left right => do
      let lhs ← checkInteger program available context left
      let rhs ← checkInteger program available context right
      let coreOp := SurfaceElaboration.lowerBinaryOp op
      let typed ← Typing.Check.checkBinary coreOp
        (.scalar (.signed .i32)) (.scalar (.signed .i32)) (.scalar (.signed .i32))
      if eager : coreOp ≠ .logicalAnd ∧ coreOp ≠ .logicalOr then
        match evaluated : Semantics.evalBinaryValue program.target coreOp lhs.value rhs.value with
        | .error _ => none
        | .ok value => some {
            expression := .binary coreOp lhs.expression rhs.expression
            value
            lowers := .binary lhs.lowers rhs.lowers rfl rfl rfl typed.down
            evaluates := .binary lhs.evaluates rhs.evaluates eager evaluated }
      else none
  | .path path => do
      let entry ← resolveConstant context path
      if integer : entry.val.type = .scalar (.signed .i32) then
        if earlier : entry.val.constant ∈ available then
          match found : program.constant? entry.val.constant with
          | none => none
          | some declaration => some {
              expression := .constant entry.val.constant
              value := declaration.value
              lowers := by simpa only [integer] using
                (SurfaceElaboration.ExprLowers.constant entry.property)
              evaluates := .reference earlier found }
        else none
      else none
  | _ => none

end Lanius.Compiler.ConstantExprCheck
