import Lean.Elab.Tactic.Omega
import Lanius.Semantics.Aggregate
import Lanius.Semantics.CallerFrame

namespace Lanius.Semantics

open Lanius
open Lanius.Core

/-! Fuel-stable composition for an internal Core function call.

The caller supplies the exact lookup and binding facts, while the argument
and body contracts hide their evaluator fuel.  The frame assumptions expose
only the state facts needed to restore the caller's locals at the boundary.
-/

theorem thresholdInternalCallUnderCaller
    (program : Program) (caller : State) (function : Function)
    (arguments : List Expr) (body : Stmt) (values : List Value)
    (bindings : List (VarId × Value)) (afterArguments callee completed : State)
    (result : Value)
    (functionFound : program.function? function.id = some function)
    (bodyFound : function.body = some body)
    {argumentsFuel bodyFuel : Nat}
    (argumentsContract : ThresholdPureList argumentsFuel program caller
      arguments values afterArguments)
    (parametersBind : bindParameters function.parameters values = some bindings)
    (calleeShape : callee = ({ afterArguments with locals := [] }).bindLocals bindings)
    (bodyContract : StableStmt bodyFuel program callee body
      (.returned (some result)) completed)
    (completedFrame : CallerFrame caller completed) :
    ThresholdPure (max argumentsFuel bodyFuel + 1) program caller
      (.call function.id arguments) result (restoreLocals caller completed) := by
  refine ⟨?_, ?_⟩
  · intro fuel enough
    have argumentsEvaluate := argumentsContract.run (fuel - 1) (by omega)
    have bodyEvaluate := bodyContract (fuel - 1) (by omega)
    have call := evalExpr_call_internal (fuel := fuel - 1) program caller
      function.id arguments function body values bindings afterArguments completed
      result functionFound bodyFound argumentsEvaluate parametersBind
      (by simpa [calleeShape] using bodyEvaluate)
    simpa [show fuel - 1 + 1 = fuel by omega, restoreLocals,
      argumentsContract.frame.locals] using call
  · simpa using completedFrame.restoreLocals

theorem thresholdInternalCall
    (program : Program) (caller : State) (function : Function)
    (arguments : List Expr) (body : Stmt) (values : List Value)
    (bindings : List (VarId × Value)) (afterArguments callee completed : State)
    (result : Value)
    (functionFound : program.function? function.id = some function)
    (bodyFound : function.body = some body)
    {argumentsFuel bodyFuel : Nat}
    (argumentsContract : ThresholdPureList argumentsFuel program caller
      arguments values afterArguments)
    (parametersBind : bindParameters function.parameters values = some bindings)
    (calleeShape : callee = ({ afterArguments with locals := [] }).bindLocals bindings)
    (bodyContract : StableStmt bodyFuel program callee body
      (.returned (some result)) completed)
    (calleeFrame : CallerFrame caller callee)
    (bodyFrame : PureFrame callee completed) :
    ThresholdPure (max argumentsFuel bodyFuel + 1) program caller
      (.call function.id arguments) result (restoreLocals caller completed) := by
  exact thresholdInternalCallUnderCaller program caller function arguments body values
    bindings afterArguments callee completed result functionFound bodyFound
    argumentsContract parametersBind calleeShape bodyContract
    (calleeFrame.transPure bodyFrame)

theorem thresholdInternalCall_exists
    (program : Program) (caller : State) (function : Function)
    (arguments : List Expr) (body : Stmt) (values : List Value)
    (bindings : List (VarId × Value)) (afterArguments callee completed : State)
    (result : Value)
    (functionFound : program.function? function.id = some function)
    (bodyFound : function.body = some body)
    {argumentsFuel bodyFuel : Nat}
    (argumentsContract : ThresholdPureList argumentsFuel program caller
      arguments values afterArguments)
    (parametersBind : bindParameters function.parameters values = some bindings)
    (calleeShape : callee = ({ afterArguments with locals := [] }).bindLocals bindings)
    (bodyContract : StableStmt bodyFuel program callee body
      (.returned (some result)) completed)
    (calleeFrame : CallerFrame caller callee)
    (bodyFrame : PureFrame callee completed) :
    ∃ threshold, ThresholdPure threshold program caller
      (.call function.id arguments) result (restoreLocals caller completed) := by
  exact ⟨max argumentsFuel bodyFuel + 1,
    thresholdInternalCall program caller function arguments body values bindings
      afterArguments callee completed result functionFound bodyFound
      argumentsContract parametersBind calleeShape bodyContract calleeFrame bodyFrame⟩

end Lanius.Semantics
