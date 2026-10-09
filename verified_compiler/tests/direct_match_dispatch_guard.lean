import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.MatchRun
import Lanius.Semantics.SourceValue

namespace MatchDispatchGuardTests

open Lanius Lanius.Core Lanius.Semantics

private def expression := Extracted.«verified::lean_typed_body».Functions.«surface_expression_output».core
private def matching := Extracted.«verified::lean_typed_body».Functions.«surface_match_output».core
private def finalArms : Stmt → List (Pattern × Expr)
  | .returnValue (some (.matchValue _ arms)) => arms
  | .letLocal _ _ _ body => finalArms body
  | .sequence _ rest => finalArms rest
  | _ => []
private def arms (function : Function) : List (Pattern × Expr) := finalArms (function.body.getD .skip)
private def binding (index : Nat) : VarId := match (arms expression)[index]? with
  | some (.enumVariant _ _ [.bind id], _) => id
  | _ => 0
private def arguments (enclosed : Bool) : List Expr :=
  (List.range 3).map (fun index => .local (expression.argumentId index)) ++ [.value (.boolean enclosed)]

/-- Inspect the real expression arm, with fresh admission and no imported
    program-specific proof artifacts. The helper's fourth argument is true. -/
theorem alwaysEncloses (header : Value) :
    selectedArm (source_value Extracted.«ir::body_events».Types.«Event».«ExpressionMatch» [header]) (arms expression) =
      some ([(binding 9, header)], .call matching.id (arguments true)) := rfl

#print axioms alwaysEncloses

end MatchDispatchGuardTests
