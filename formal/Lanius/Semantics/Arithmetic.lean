import Lean.Elab.Tactic.Omega
import Lanius.Semantics.Loop
import Lanius.Semantics.Stable

namespace Lanius.Semantics

open Lanius Lanius.Core

/-! Fuel-stable arithmetic contracts for non-wrapping signed-i32 addition. -/

theorem evalExpr_i32LocalAddNat
    (program : Program) (state : State) (localId : VarId)
    (start increment : Nat)
    (localFound : state.local? localId =
      some (.signed .i32 (Int.ofNat start)))
    (bound : start + increment < 2 ^ 31) (fuel : Nat)
    (enough : 2 ≤ fuel) :
    evalExpr fuel program state
      (.binary .add (.local localId)
        (.value (.signed .i32 (Int.ofNat increment))))
      = .done (.signed .i32 (Int.ofNat (start + increment))) state := by
  rw [← show (fuel - 2).succ.succ = fuel by omega]
  apply evalExpr_binary_done (fuel := (fuel - 2).succ) program state .add
    (.local localId) (.value (.signed .i32 (Int.ofNat increment)))
    (.signed .i32 (Int.ofNat start))
    (.signed .i32 (Int.ofNat increment))
    (.signed .i32 (Int.ofNat (start + increment))) state state
  · exact evalExpr_local_of_local? (fuel - 2) program state localId
      (.signed .i32 (Int.ofNat start)) localFound
  · exact evalExpr_value (fuel - 2) program state
      (.signed .i32 (Int.ofNat increment))
  · simp
  · simp only [evalBinaryValue, evalSignedBinary]
    rw [show Int.ofNat start + (Int.ofNat increment) =
        Int.ofNat (start + increment) by
          simp only [Int.ofNat_eq_natCast, Int.natCast_add]]
    simp only [beq_self_eq_true, if_true]
    simpa using congrArg (fun n : Int => Value.signed .i32 n)
      (wrapSigned_i32_nat_lt program.target (start + increment) bound)

theorem ThresholdPure.i32LocalAddNat
    (program : Program) (state : State) (localId : VarId)
    (start increment : Nat)
    (localFound : state.local? localId =
      some (.signed .i32 (Int.ofNat start)))
    (formed : state.CellsWellFormed)
    (bound : start + increment < 2 ^ 31) :
    ThresholdPure 2 program state
      (.binary .add (.local localId)
        (.value (.signed .i32 (Int.ofNat increment))))
      (.signed .i32 (Int.ofNat (start + increment))) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  exact evalExpr_i32LocalAddNat program state localId start increment
    localFound bound fuel enough

/- The dual non-wrapping subtraction rule is useful for checked output
   capacities and cursor arithmetic. -/
theorem evalExpr_i32LocalSubtractNat
    (program : Program) (state : State) (localId : VarId)
    (start decrement : Nat)
    (localFound : state.local? localId =
      some (.signed .i32 (Int.ofNat start)))
    (bound : decrement ≤ start) (startBound : start < 2 ^ 31) (fuel : Nat)
    (enough : 2 ≤ fuel) :
    evalExpr fuel program state
      (.binary .subtract (.local localId)
        (.value (.signed .i32 (Int.ofNat decrement))))
      = .done (.signed .i32 (Int.ofNat (start - decrement))) state := by
  rw [← show (fuel - 2).succ.succ = fuel by omega]
  apply evalExpr_binary_done (fuel := (fuel - 2).succ) program state .subtract
    (.local localId) (.value (.signed .i32 (Int.ofNat decrement)))
    (.signed .i32 (Int.ofNat start))
    (.signed .i32 (Int.ofNat decrement))
    (.signed .i32 (Int.ofNat (start - decrement))) state state
  · exact evalExpr_local_of_local? (fuel - 2) program state localId
      (.signed .i32 (Int.ofNat start)) localFound
  · exact evalExpr_value (fuel - 2) program state
      (.signed .i32 (Int.ofNat decrement))
  · simp
  · simp only [evalBinaryValue, evalSignedBinary]
    simp only [beq_self_eq_true, if_true]
    have subEq : (Int.ofNat start - Int.ofNat decrement) =
        Int.ofNat (start - decrement) := by
      symm
      exact Int.ofNat_sub bound
    rw [subEq]
    simpa using congrArg (fun n : Int => Value.signed .i32 n)
      (wrapSigned_i32_nat_lt program.target (start - decrement) (by omega))

theorem ThresholdPure.i32LocalSubtractNat
    (program : Program) (state : State) (localId : VarId)
    (start decrement : Nat)
    (localFound : state.local? localId =
      some (.signed .i32 (Int.ofNat start)))
    (formed : state.CellsWellFormed) (bound : decrement ≤ start)
    (startBound : start < 2 ^ 31) :
    ThresholdPure 2 program state
      (.binary .subtract (.local localId)
        (.value (.signed .i32 (Int.ofNat decrement))))
      (.signed .i32 (Int.ofNat (start - decrement))) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  exact evalExpr_i32LocalSubtractNat program state localId start decrement
    localFound bound startBound fuel enough

end Lanius.Semantics
