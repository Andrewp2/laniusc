import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.UnaryI32Predicate
import Lanius.Semantics.AggregateCall

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

theorem thresholdUnaryI32Call
    (program : Program) (caller : State)
    (functionId parameter : Nat) (predicate : UnaryI32Predicate) (input : Int)
    (found : program.function? functionId =
      some (unaryI32PredicateFunction functionId parameter predicate))
    (formed : caller.CellsWellFormed)
    (localFound : caller.local? parameter = some (.signed .i32 input)) :
    ThresholdPure (predicate.exprFuel + 3) program caller (.call functionId [.local parameter])
      (.boolean (predicate.accepts input))
      (restoreLocals caller
        (({ caller with locals := [] }).bindLocal parameter (.signed .i32 input))) := by
  let after := restoreLocals caller
    (({ caller with locals := [] }).bindLocal parameter (.signed .i32 input))
  have cells : FreshCellFrame caller after := by
    exact (FreshCellFrame.bindLocal caller parameter (.signed .i32 input)).restoreLocals
  refine ⟨?_, ?_⟩
  · intro fuel enough
    apply evalExpr_unaryI32PredicateCall_of_fuel fuel program caller
      functionId parameter predicate (.local parameter) input found formed enough
    simpa [show fuel - 3 + 1 = fuel - 2 by omega] using
      (evalExpr_local_of_local? (fuel - 3) program caller parameter
        (.signed .i32 input) localFound)
  · exact ⟨formed, cells, rfl, rfl, rfl, rfl⟩

theorem thresholdUnaryPredicateOr
    (program : Program) (caller : State) (parameter leftId rightId : Nat)
    (left right : UnaryI32Predicate) (input : Int)
    (leftFound : program.function? leftId =
      some (unaryI32PredicateFunction leftId parameter left))
    (rightFound : program.function? rightId =
      some (unaryI32PredicateFunction rightId parameter right))
    (formed : caller.CellsWellFormed) :
    ∃ after, ThresholdPure (max (left.exprFuel + 3) (right.exprFuel + 3) + 1) program
      (({ caller with locals := [] }).bindLocal parameter (.signed .i32 input))
      (.binary .logicalOr (.call leftId [.local parameter])
        (.call rightId [.local parameter]))
      (.boolean (left.accepts input || right.accepts input)) after := by
  let value : Value := .signed .i32 input
  let callee : State := ({ caller with locals := [] }).bindLocal parameter value
  have base : ({ caller with locals := [] }).CellsWellFormed := fun _ m => formed _ m
  have calleeFormed : callee.CellsWellFormed := base.bindLocal parameter value
  have localFound : callee.local? parameter = some value :=
    base.bindLocal_local parameter value
  have leftContract := thresholdUnaryI32Call program callee leftId parameter left input
    leftFound calleeFormed localFound
  cases h : left.accepts input with
  | true =>
      exact ⟨_, (logicalOrTrue (right := .call rightId [.local parameter])
        (by simpa [h, value] using leftContract)).weaken (by omega)⟩
  | false =>
      let middle := restoreLocals callee
        (({ callee with locals := [] }).bindLocal parameter value)
      have middleFormed : middle.CellsWellFormed := leftContract.frame.afterFormed
      have middleLocal : middle.local? parameter = some value :=
        leftContract.frame.cells.localFound leftContract.frame.locals parameter value localFound
      have rightContract := thresholdUnaryI32Call program middle rightId parameter right input
        rightFound middleFormed middleLocal
      exact ⟨_, logicalOrFalse (by simpa [h, middle, value] using leftContract)
        rightContract⟩

def oneParameterBooleanFunction
    (functionId parameter : Nat) (body : Expr) : Function := {
  id := functionId
  parameters := [(parameter, .scalar (.signed .i32))]
  returnType := .scalar .bool
  body := some (.sequence (.returnValue (some body)) .skip)
}

theorem thresholdOneParameterCall
    (program : Program) (caller : State)
    (functionId parameter : Nat) (body : Expr) (input : Int)
    (found : program.function? functionId =
      some (oneParameterBooleanFunction functionId parameter body))
    (formed : caller.CellsWellFormed)
    {bodyFuel : Nat}
    (bodyContract : ThresholdPure bodyFuel program
      (({ caller with locals := [] }).bindLocal parameter (.signed .i32 input))
      body (.boolean result) bodyAfter) :
    ThresholdPure (bodyFuel + 4) program caller
      (.call functionId [.value (.signed .i32 input)]) (.boolean result)
      (restoreLocals caller bodyAfter) := by
  simpa [oneParameterBooleanFunction, Lanius.Semantics.oneParameterFunction] using
    (Lanius.Semantics.thresholdOneParameterCall program caller functionId parameter
      (.scalar (.signed .i32)) (.scalar .bool) body (.signed .i32 input)
      (by simpa [oneParameterBooleanFunction, Lanius.Semantics.oneParameterFunction] using found)
      formed bodyContract)

end Lanius.Compiler.Lexer
