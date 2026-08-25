import Lanius.MatchFunctionality
import Lanius.UnaryFunctionality
import Lanius.AssignmentFunctionality

namespace Lanius.ProgramElaboration

open Lanius

/-- Only paths and member expressions are callable surface forms. Keeping this
    syntactic boundary explicit lets the total structural proof discharge the
    remaining call shapes by inversion of the elaboration judgment. -/
private def CallableCallee : Surface.Expr → Prop
  | .path _
  | .member _ _ => True
  | _ => False

private theorem ExprSpecializationFunctional.unsupportedCall
    (notCallable : ¬ CallableCallee callee) :
    ExprSpecializationFunctional (.call callee arguments) := by
  have inference : ExprInferenceSpecializationFunctional
      (.call callee arguments) := by
    intro pack catalog imports program externalBindings outer
      groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
      leftCore rightSymbolic rightGround rightCore _complete left _right
    cases left <;> simp [CallableCallee] at notCallable
  exact ⟨inference,
    ExprCheckingSpecializationFunctional.of_inference inference (by
      intro direct
      cases direct <;> simp [CallableCallee] at notCallable),
    by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

/-- The structural recursor needs the functionality of a member expression's
    base when that member later occurs as a call callee. The second component
    retains precisely that proper-child induction hypothesis; it is `True` for
    every other expression form. -/
private def ExprFunctionalityEvidence (surface : Surface.Expr) : Prop :=
  ExprSpecializationFunctional surface ∧
    match surface with
    | .member base _ => ExprSpecializationFunctional base
    | _ => True

private theorem exprFunctionalityEvidence (surface : Surface.Expr) :
    ExprFunctionalityEvidence surface := by
  apply Surface.Expr.rec
    (motive_1 := fun _ => True)
    (motive_2 := ExprFunctionalityEvidence)
    (motive_3 := fun _ => True)
    (motive_4 := fun _ => True)
    (motive_5 := fun _ => True)
    (motive_6 := fun _ => True)
    (motive_7 := ExprListSpecializationFunctional)
    (motive_8 := NamedExprListSpecializationFunctional)
    (motive_9 := MatchArmListSpecializationFunctional)
    (motive_10 := fun _ => True)
    (motive_11 := fun _ => True)
    (motive_12 := fun _ => True)
    (motive_13 := fun field => ExprFunctionalityEvidence field.2)
    (motive_14 := fun arm => ExprFunctionalityEvidence arm.2)
    (t := surface)
  · trivial
  · intro _path _payload _payloadIH
    trivial
  · intro _text
    trivial
  · intro _value
    trivial
  · intro literal
    exact ⟨ExprSpecializationFunctional.literal, trivial⟩
  · intro path
    exact ⟨ExprSpecializationFunctional.path, trivial⟩
  · exact ⟨ExprSpecializationFunctional.selfValue, trivial⟩
  · intro elements elementsFunctional
    exact ⟨ExprSpecializationFunctional.array elementsFunctional, trivial⟩
  · intro path fields fieldsFunctional
    exact ⟨ExprSpecializationFunctional.structValue fieldsFunctional, trivial⟩
  · intro op operand operandEvidence
    exact ⟨ExprSpecializationFunctional.unary operandEvidence.1, trivial⟩
  · intro op left right leftEvidence rightEvidence
    exact ⟨ExprSpecializationFunctional.binary leftEvidence.1 rightEvidence.1,
      trivial⟩
  · intro op place value placeEvidence valueEvidence
    exact ⟨ExprSpecializationFunctional.assign placeEvidence.1 valueEvidence.1,
      trivial⟩
  · intro callee arguments calleeEvidence argumentsFunctional
    cases callee with
    | path path =>
        exact ⟨ExprSpecializationFunctional.pathCall argumentsFunctional,
          trivial⟩
    | member receiver name =>
        exact ⟨ExprSpecializationFunctional.methodCall calleeEvidence.2
            argumentsFunctional,
          trivial⟩
    | literal literal =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | selfValue =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | array elements =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | structValue path fields =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | unary op operand =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | binary op left right =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | assign op place value =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | call nested arguments =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | index base index =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
    | matchValue scrutinee arms =>
        exact ⟨ExprSpecializationFunctional.unsupportedCall (by
            simp [CallableCallee]), trivial⟩
  · intro base index baseEvidence indexEvidence
    exact ⟨ExprSpecializationFunctional.index baseEvidence.1 indexEvidence.1,
      trivial⟩
  · intro base name baseEvidence
    exact ⟨ExprSpecializationFunctional.field baseEvidence.1, baseEvidence.1⟩
  · intro scrutinee arms scrutineeEvidence armsFunctional
    exact ⟨ExprSpecializationFunctional.matchValue scrutineeEvidence.1
        armsFunctional,
      trivial⟩
  · intro _text
    trivial
  · intro _expression _expressionIH
    trivial
  · intro _path
    trivial
  · intro _kind _start _stop _startIH _stopIH
    trivial
  · intro _name _type _initializer _initializerIH
    trivial
  · intro _value _valueIH
    trivial
  · intro _condition _thenBody _elseBody _conditionIH _thenIH _elseIH
    trivial
  · intro _condition _body _conditionIH _bodyIH
    trivial
  · intro _name _iterable _body _iterableIH _bodyIH
    trivial
  · trivial
  · trivial
  · intro _body _bodyIH
    trivial
  · intro _expression _expressionIH
    trivial
  · trivial
  · intro _head _tail _headIH _tailIH
    trivial
  · intro surface member
    simp at member
  · intro head tail headEvidence tailFunctional surface member
    simp only [List.mem_cons] at member
    rcases member with rfl | member
    · exact headEvidence.1
    · exact tailFunctional surface member
  · intro name expression member
    simp at member
  · intro head tail headEvidence tailFunctional name expression member
    simp only [List.mem_cons] at member
    rcases member with rfl | member
    · exact headEvidence.1
    · exact tailFunctional name expression member
  · intro pattern body member
    simp at member
  · intro head tail headEvidence tailFunctional pattern body member
    simp only [List.mem_cons] at member
    rcases member with rfl | member
    · exact headEvidence.1
    · exact tailFunctional pattern body member
  · trivial
  · intro _value _valueIH
    trivial
  · trivial
  · intro _value _valueIH
    trivial
  · trivial
  · intro _head _tail _headIH _tailIH
    trivial
  · intro _name _expression evidence
    exact evidence
  · intro _pattern _expression _patternIH evidence
    exact evidence

/-- Exact specialization is functional for every surface expression. This is
    the syntax-directed closure theorem consumed by statement and declaration
    functionality; downstream proofs no longer need constructor-specific
    expression premises. -/
theorem exprSpecializationFunctional (surface : Surface.Expr) :
    ExprSpecializationFunctional surface :=
  (exprFunctionalityEvidence surface).1

end Lanius.ProgramElaboration
