import Lanius.Semantics.Call
import Lanius.Semantics.Branch

namespace Lanius.Semantics

open Lanius
open Lanius.Core

/-! Fuel-stable calls to a one-parameter Core function with a simple return body.

The body contract is supplied by the caller, so this layer is independent of
the expression used by the function: aggregate constructors, field getters,
and scalar bodies all use the same call composition.
-/

def oneParameterFunction
    (functionId : FunctionId) (parameter : VarId)
    (parameterType returnType : Ty) (body : Expr) : Function := {
  id := functionId
  parameters := [(parameter, parameterType)]
  returnType := returnType
  body := some (.sequence (.returnValue (some body)) .skip)
}

theorem thresholdOneParameterCall
    (program : Program) (caller : State)
    (functionId : FunctionId) (parameter : VarId)
    (parameterType returnType : Ty) (body : Expr) (value : Value)
    (found : program.function? functionId =
      some (oneParameterFunction functionId parameter parameterType returnType body))
    (formed : caller.CellsWellFormed)
    {bodyFuel : Nat} {result : Value} {bodyAfter : State}
    (bodyContract : ThresholdPure bodyFuel program
      (({ caller with locals := [] }).bindLocal parameter value)
      body result bodyAfter) :
    ThresholdPure (bodyFuel + 4) program caller
      (.call functionId [.value value]) result
      (restoreLocals caller bodyAfter) := by
  let callee : State := ({ caller with locals := [] }).bindLocal parameter value
  have arguments : ThresholdPureList 2 program caller [.value value]
      [value] caller := by
    simpa using (ThresholdPureList.singleton
      (ThresholdPure.value (program := program) (state := caller) (value := value) formed))
  have bodyRun : StableStmt (bodyFuel + 2) program callee
      (.sequence (.returnValue (some body)) .skip)
      (.returned (some result)) bodyAfter := by
    exact StableStmt.returnValueSequence program callee body result bodyContract.run
  have calleeFrame : CallerFrame caller callee := by
    exact ⟨formed, by
      simp [callee, FreshCellFrame, State.bindLocal, State.bindCell], rfl, rfl, rfl⟩
  have contract := thresholdInternalCall program caller
    (oneParameterFunction functionId parameter parameterType returnType body)
    [.value value] (.sequence (.returnValue (some body)) .skip)
    [value] [(parameter, value)] caller callee bodyAfter result found rfl
    arguments (by simp [oneParameterFunction, bindParameters])
    (by simp [callee, State.bindLocals]) bodyRun calleeFrame bodyContract.frame
  exact contract.weaken (by omega)

theorem thresholdOneParameterCallOfArgumentBuilder
    (program : Program) (caller : State)
    (functionId : FunctionId) (parameter : VarId)
    (parameterType returnType : Ty) (body : Expr)
    (argument : Expr) (argumentValue result : Value)
    {argumentFuel : Nat} {argumentAfter : State}
    (argumentContract : ThresholdPure argumentFuel program caller argument
      argumentValue argumentAfter)
    (builder : ∀ callee, callee.CellsWellFormed →
      callee.local? parameter = some argumentValue →
      ∃ fuel, ThresholdPure fuel program callee body result callee)
    (found : program.function? functionId =
      some (oneParameterFunction functionId parameter parameterType returnType body)) :
    ∃ threshold after, ThresholdPure threshold program caller
      (.call functionId [argument]) result after := by
  let callee : State := ({ argumentAfter with locals := [] }).bindLocal parameter argumentValue
  have calleeFrame : CallerFrame caller callee :=
    ⟨argumentContract.frame.beforeFormed,
      argumentContract.frame.cells.trans
        (FreshCellFrame.bindLocal ({ argumentAfter with locals := [] })
          parameter argumentValue),
      argumentContract.frame.heap, argumentContract.frame.world,
      argumentContract.frame.views⟩
  have calleeFormed := calleeFrame.currentFormed
  have clearedFormed : ({ argumentAfter with locals := [] } : State).CellsWellFormed :=
    argumentContract.frame.afterFormed
  have localFound : callee.local? parameter = some argumentValue := by
    simpa [callee] using clearedFormed.bindLocal_local parameter argumentValue
  obtain ⟨bodyFuel, bodyContract⟩ := builder callee calleeFormed localFound
  have bodyRun : StableStmt (bodyFuel + 2) program callee
      (.sequence (.returnValue (some body)) .skip)
      (.returned (some result)) callee := by
    exact StableStmt.returnValueSequence program callee body result bodyContract.run
  have arguments : ThresholdPureList (max argumentFuel 1 + 1) program caller
      [argument] [argumentValue] argumentAfter :=
    ThresholdPureList.singleton argumentContract
  have call := thresholdInternalCall program caller
    (oneParameterFunction functionId parameter parameterType returnType body)
    [argument] (.sequence (.returnValue (some body)) .skip)
    [argumentValue] [(parameter, argumentValue)] argumentAfter callee callee result found rfl
    arguments (by simp [oneParameterFunction, bindParameters])
    (by simp [callee, State.bindLocals]) bodyRun calleeFrame
    (PureFrame.refl calleeFormed)
  exact ⟨_, _, call⟩

theorem purelyEvaluatesOneParameterCall
    (program : Program) (caller : State)
    (functionId : FunctionId) (parameter : VarId)
    (parameterType returnType : Ty) (body : Expr) (value : Value)
    (found : program.function? functionId =
      some (oneParameterFunction functionId parameter parameterType returnType body))
    (formed : caller.CellsWellFormed)
    {bodyFuel : Nat} {result : Value} {bodyAfter : State}
    (bodyContract : ThresholdPure bodyFuel program
      (({ caller with locals := [] }).bindLocal parameter value)
      body result bodyAfter) :
    PurelyEvaluates program caller (.call functionId [.value value]) result := by
  exact (thresholdOneParameterCall program caller functionId parameter
    parameterType returnType body value found formed bodyContract).erase

theorem purelyEvaluatesOneParameterCallOfBuilder
    (program : Program) (caller : State)
    (functionId : FunctionId) (parameter : VarId)
    (parameterType returnType : Ty) (body : Expr) (argument result : Value)
    (builder : ∀ callee, callee.CellsWellFormed → callee.local? parameter = some argument →
      ∃ fuel, ThresholdPure fuel program callee body result callee)
    (found : program.function? functionId =
      some (oneParameterFunction functionId parameter parameterType returnType body))
    (formed : caller.CellsWellFormed) :
    PurelyEvaluates program caller (.call functionId [.value argument]) result := by
  let callee := ({ caller with locals := [] }).bindLocal parameter argument
  have baseFormed : ({ caller with locals := [] } : State).CellsWellFormed := formed
  have calleeFormed := baseFormed.bindLocal parameter argument
  have localFound := baseFormed.bindLocal_local parameter argument
  obtain ⟨fuel, contract⟩ := builder callee calleeFormed localFound
  exact purelyEvaluatesOneParameterCall program caller functionId parameter
    parameterType returnType body argument found formed (by simpa [callee] using contract)

def guardReturnBody (condition : Expr) (thenBranch : Stmt) (localId : VarId) : Stmt :=
  .sequence (.ifThenElse condition thenBranch .skip)
    (.sequence (.returnValue (some (.local localId))) .skip)

theorem purelyEvaluatesFourValueGuardReturnCall
    (program : Program) (caller : State) (function : Function)
    (condition : Expr) (thenBranch : Stmt) (localId : VarId)
    (first second third fourth result : Value)
    (bindings : List (VarId × Value))
    (found : program.function? function.id = some function)
    (bodyShape : function.body = some (guardReturnBody condition thenBranch localId))
    (parametersBind : bindParameters function.parameters
      [first, second, third, fourth] = some bindings)
    (conditionContract : ThresholdPure 3 program
      (({ caller with locals := [] }).bindLocals bindings)
      condition (.boolean false) (({ caller with locals := [] }).bindLocals bindings))
    (localFound : (({ caller with locals := [] }).bindLocals bindings).local? localId = some result)
    (formed : caller.CellsWellFormed) :
    PurelyEvaluates program caller
      (.call function.id
        [.value first, .value second, .value third, .value fourth]) result := by
  let callee := ({ caller with locals := [] }).bindLocals bindings
  have calleeFormed : callee.CellsWellFormed := by
    simpa [callee] using (show ({ caller with locals := [] }).CellsWellFormed from formed).bindLocals bindings
  have conditionRun : StableStmt 4 program callee
      (.ifThenElse condition thenBranch .skip) .next callee :=
    StableStmt.ifThenElse_false conditionContract.run (StableStmt.skip program callee)
  have returnRun := StableStmt.returnValueSequence program callee (.local localId) result
    (ThresholdPure.localValue calleeFormed localId result localFound).run
  have bodyRun : ∃ fuel, StableStmt fuel program callee
      (guardReturnBody condition thenBranch localId)
      (.returned (some result)) callee :=
    ⟨_, StableStmt.sequence_next conditionRun returnRun⟩
  obtain ⟨bodyFuel, bodyRun⟩ := bodyRun
  let values := [first, second, third, fourth]
  have arguments : ThresholdPureList 5 program caller
      [.value first, .value second, .value third, .value fourth] values caller := by
    simpa [values] using ThresholdPureList.cons (ThresholdPure.value formed)
      (ThresholdPureList.cons (ThresholdPure.value formed)
        (ThresholdPureList.cons (ThresholdPure.value formed)
          (ThresholdPureList.singleton (ThresholdPure.value formed))))
  have frame : CallerFrame caller callee := by
    have clear : CallerFrame caller ({ caller with locals := [] }) :=
      ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl, rfl⟩
    simpa [callee] using clear.bindLocals bindings
  exact (thresholdInternalCall program caller function
    [.value first, .value second, .value third, .value fourth]
    (guardReturnBody condition thenBranch localId) values bindings
    caller callee callee result found bodyShape
    arguments parametersBind (by rfl) bodyRun
    frame (PureFrame.refl calleeFormed)).erase

end Lanius.Semantics
