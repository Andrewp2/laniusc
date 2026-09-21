import Lanius.Semantics.Stable

namespace Lanius.Semantics

open Lanius
open Lanius.Core

/-! Small evaluator rules for aggregate expressions.

`evalExprs` evaluates every element with the same remaining fuel, so a list
contract has to carry both the state after the prefix and the state after the
whole list.  `ThresholdPureList` packages that otherwise repetitive detail;
the expression-level `ThresholdPure` contract is recovered by the struct
constructor below.
-/

/-- A stable execution contract for a list of aggregate expressions. -/
structure ThresholdPureList (fuelThreshold : Nat)
    (program : Program) (before : State) (expressions : List Expr)
    (values : List Value) (after : State) : Prop where
  run : ∀ fuel, fuelThreshold ≤ fuel →
    evalExprs fuel program before expressions = .done values after
  frame : PureFrame before after

namespace ThresholdPureList

theorem nil (formed : state.CellsWellFormed) :
    ThresholdPureList 1 program state [] [] state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  cases fuel with
  | zero => omega
  | succ fuel => rw [evalExprs.eq_def]

theorem cons
    {headFuel tailFuel : Nat} {program : Program} {before middle after : State}
    {head : Expr} {tail : List Expr} {headValue : Value} {tailValues : List Value}
    (headContract : ThresholdPure headFuel program before head headValue middle)
    (tailContract : ThresholdPureList tailFuel program middle tail tailValues after) :
    ThresholdPureList (max headFuel tailFuel + 1) program before
      (head :: tail) (headValue :: tailValues) after := by
  refine ⟨?_, headContract.frame.trans tailContract.frame⟩
  intro fuel enough
  have headEvaluates := headContract.run (fuel - 1) (by omega)
  have tailEvaluates := tailContract.run (fuel - 1) (by omega)
  rw [← show (fuel - 1).succ = fuel by omega, evalExprs.eq_def]
  simp only [headEvaluates, tailEvaluates]

theorem singleton
    {fuelThreshold : Nat} {program : Program} {before after : State}
    {expression : Expr} {value : Value}
    (contract : ThresholdPure fuelThreshold program before expression value after) :
    ThresholdPureList (max fuelThreshold 1 + 1) program before
      [expression] [value] after := by
  exact cons contract (nil contract.frame.afterFormed)

theorem pair
    {firstFuel secondFuel : Nat} {program : Program}
    {before middle after : State}
    {first second : Expr} {firstValue secondValue : Value}
    (firstContract : ThresholdPure firstFuel program before first firstValue middle)
    (secondContract : ThresholdPure secondFuel program middle second secondValue after) :
    ThresholdPureList (max firstFuel (max secondFuel 1 + 1) + 1) program before
      [first, second] [firstValue, secondValue] after := by
  exact cons firstContract (singleton secondContract)

end ThresholdPureList

namespace ThresholdPure

theorem value {program : Program} {state : State} {value : Value}
    (formed : state.CellsWellFormed) :
    ThresholdPure 1 program state (.value value) value state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  cases fuel with
  | zero => omega
  | succ fuel => exact evalExpr_value fuel program state value

theorem localValue {program : Program} {state : State}
    (formed : state.CellsWellFormed) (id : VarId) (value : Value)
    (localFound : state.local? id = some value) :
    ThresholdPure 1 program state (.local id) value state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  cases fuel with
  | zero => omega
  | succ fuel => exact evalExpr_local_of_local? fuel program state id value localFound

theorem structValue
    {fieldFuel : Nat} {program : Program} {before after : State}
    {id : TypeId} {expressions : List Expr} {values : List Value}
    (fields : ThresholdPureList fieldFuel program before expressions values after) :
    ThresholdPure (fieldFuel + 1) program before (.structValue id expressions)
      (.structure id values) after := by
  refine ⟨?_, fields.frame⟩
  intro fuel enough
  have fieldEvaluation := fields.run (fuel - 1) (by omega)
  rw [← show (fuel - 1).succ = fuel by omega, evalExpr.eq_def]
  simp only [fieldEvaluation]

theorem structValue_singleton
    {fuelThreshold : Nat} {program : Program} {before after : State}
    {id : TypeId} {expression : Expr} {value : Value}
    (field : ThresholdPure fuelThreshold program before expression value after) :
    ThresholdPure (max fuelThreshold 1 + 2) program before
      (.structValue id [expression]) (.structure id [value]) after := by
  exact structValue (ThresholdPureList.singleton field)

theorem structValue_pair
    {firstFuel secondFuel : Nat} {program : Program}
    {before middle after : State} {id : TypeId}
    {first second : Expr} {firstValue secondValue : Value}
    (firstContract : ThresholdPure firstFuel program before first firstValue middle)
    (secondContract : ThresholdPure secondFuel program middle second secondValue after) :
    ThresholdPure (max firstFuel (max secondFuel 1 + 1) + 2) program before
      (.structValue id [first, second])
      (.structure id [firstValue, secondValue]) after := by
  exact structValue (ThresholdPureList.pair firstContract secondContract)

theorem structValue_triple
    {firstFuel secondFuel thirdFuel : Nat} {program : Program}
    {before middle next after : State} {id : TypeId}
    {first second third : Expr} {firstValue secondValue thirdValue : Value}
    (firstContract : ThresholdPure firstFuel program before first firstValue middle)
    (secondContract : ThresholdPure secondFuel program middle second secondValue next)
    (thirdContract : ThresholdPure thirdFuel program next third thirdValue after) :
    ThresholdPure (max firstFuel (max secondFuel (max thirdFuel 1 + 1) + 1) + 2)
      program before (.structValue id [first, second, third])
      (.structure id [firstValue, secondValue, thirdValue]) after := by
  exact structValue (ThresholdPureList.cons firstContract
    (ThresholdPureList.cons secondContract
      (ThresholdPureList.cons thirdContract
        (ThresholdPureList.nil thirdContract.frame.afterFormed))))

theorem field
    {baseFuel : Nat} {program : Program} {before after : State}
    {base : Expr} {field : FieldId} {structureId : TypeId}
    {fields : List Value} {value : Value}
    (baseContract : ThresholdPure baseFuel program before base
      (.structure structureId fields) after)
    (fieldFound : fields[field]? = some value) :
    ThresholdPure (baseFuel + 1) program before (.field base field) value after := by
  refine ⟨?_, baseContract.frame⟩
  intro fuel enough
  have baseEvaluation := baseContract.run (fuel - 1) (by omega)
  rw [← show (fuel - 1).succ = fuel by omega, evalExpr.eq_def]
  simp only [baseEvaluation, fieldFound]

theorem localField
    (formed : state.CellsWellFormed) (id : VarId) (structureId : TypeId)
    (fields : List Value) (field : FieldId) (value : Value)
    (localFound : state.local? id = some (.structure structureId fields))
    (fieldFound : fields[field]? = some value) :
    ThresholdPure 2 program state (.field (.local id) field) value state := by
  exact ThresholdPure.field (ThresholdPure.localValue formed id _ localFound) fieldFound

end ThresholdPure

end Lanius.Semantics
