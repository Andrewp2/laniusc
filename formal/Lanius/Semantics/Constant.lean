import Lanius.Semantics.Rules

namespace Lanius.Semantics

open Core

/-- An effect-free initializer. References are restricted to previously checked
    constants; the program-level initialization order authenticates that list. -/
inductive ConstantEvaluates (program : Program) (available : List ConstantId) : Expr → Value → Prop where
  | value : ConstantEvaluates program available (.value value) value
  | reference
      (earlier : constantId ∈ available)
      (found : program.constant? constantId = some declaration) :
      ConstantEvaluates program available (.constant constantId) declaration.value
  | unary
      (operand : ConstantEvaluates program available expression value)
      (operation : evalUnaryValue program.target op value = .ok result) :
      ConstantEvaluates program available (.unary op expression) result
  | binary
      (left : ConstantEvaluates program available leftExpression leftValue)
      (right : ConstantEvaluates program available rightExpression rightValue)
      (eager : op ≠ .logicalAnd ∧ op ≠ .logicalOr)
      (operation : evalBinaryValue program.target op leftValue rightValue = .ok result) :
      ConstantEvaluates program available (.binary op leftExpression rightExpression) result

private def constantDepth : Expr → Nat
  | .unary _ operand => constantDepth operand + 1
  | .binary _ left right => max (constantDepth left) (constantDepth right) + 1
  | _ => 1

private theorem ConstantEvaluates.eval
    (checked : ConstantEvaluates program available expression result)
    (enough : constantDepth expression ≤ fuel) :
    evalExpr fuel program state expression = .done result state := by
  induction checked generalizing fuel with
  | value =>
      cases fuel with
      | zero => simp [constantDepth] at enough
      | succ fuel => exact evalExpr_value fuel program state _
  | reference earlier found =>
      cases fuel with
      | zero => simp [constantDepth] at enough
      | succ fuel => rw [evalExpr.eq_def]; simp only [found]
  | unary operand operation ih =>
      cases fuel with
      | zero => simp [constantDepth] at enough
      | succ fuel =>
          have next := Nat.le_of_succ_le_succ enough
          rw [evalExpr.eq_def]
          simp only [ih next, operation]
  | binary left right eager operation ihLeft ihRight =>
      cases fuel with
      | zero => simp [constantDepth] at enough
      | succ fuel =>
          have next := Nat.le_of_succ_le_succ enough
          exact evalExpr_binary_done fuel program state _ _ _ _ _ _ state state
            (ihLeft (Nat.le_trans (Nat.le_max_left _ _) next))
            (ihRight (Nat.le_trans (Nat.le_max_right _ _) next)) eager operation

/-- Folding an initializer preserves its value in every caller state,
    with no environmental assumptions or hidden effects. -/
theorem ConstantEvaluates.evaluates
    (checked : ConstantEvaluates program available expression result) (state : State) :
    Evaluates program state expression result state :=
  ⟨constantDepth expression, checked.eval (Nat.le_refl _)⟩

end Lanius.Semantics
