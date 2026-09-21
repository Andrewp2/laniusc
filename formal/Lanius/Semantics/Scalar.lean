import Lean.Elab.Tactic.Omega
import Lanius.Semantics.Loop
import Lanius.Semantics.Stable

namespace Lanius.Semantics

open Lanius Lanius.Core

/-! Fuel-stable scalar contracts shared by scanner conditions and direct byte
    comparisons.  The expression itself is intentionally generic over the
    program, state, and local IDs. -/

theorem ThresholdPure.i32LocalBinaryLiteral
    (program : Program) (state : State) (operation : BinaryOp)
    (localId : VarId) (left literal : Int) (result : Value)
    (localFound : state.local? localId = some (.signed .i32 left))
    (formed : state.CellsWellFormed)
    (operationIsEager : operation ≠ .logicalAnd ∧ operation ≠ .logicalOr)
    (operationEvaluates : evalBinaryValue program.target operation
      (.signed .i32 left) (.signed .i32 literal) = .ok result) :
    ThresholdPure 2 program state
      (.binary operation (.local localId)
        (.value (.signed .i32 literal))) result state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [← show (fuel - 2).succ.succ = fuel by omega]
  apply evalExpr_binary_done (fuel := (fuel - 2).succ) program state operation
    (.local localId) (.value (.signed .i32 literal))
    (.signed .i32 left) (.signed .i32 literal) result state state
  · exact evalExpr_local_of_local? (fuel - 2) program state localId
      (.signed .i32 left) localFound
  · exact evalExpr_value (fuel - 2) program state
      (.signed .i32 literal)
  · exact operationIsEager
  · exact operationEvaluates

theorem ThresholdPure.i32LocalsBinary
    (program : Program) (state : State) (operation : BinaryOp)
    (leftId rightId : VarId) (left right : Int) (result : Value)
    (leftFound : state.local? leftId = some (.signed .i32 left))
    (rightFound : state.local? rightId = some (.signed .i32 right))
    (formed : state.CellsWellFormed)
    (operationIsEager : operation ≠ .logicalAnd ∧ operation ≠ .logicalOr)
    (operationEvaluates : evalBinaryValue program.target operation
      (.signed .i32 left) (.signed .i32 right) = .ok result) :
    ThresholdPure 2 program state
      (.binary operation (.local leftId) (.local rightId)) result state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [← show (fuel - 2).succ.succ = fuel by omega]
  apply evalExpr_binary_done (fuel := (fuel - 2).succ) program state operation
    (.local leftId) (.local rightId)
    (.signed .i32 left) (.signed .i32 right) result state state
  · exact evalExpr_local_of_local? (fuel - 2) program state leftId
      (.signed .i32 left) leftFound
  · exact evalExpr_local_of_local? (fuel - 2) program state rightId
      (.signed .i32 right) rightFound
  · exact operationIsEager
  · exact operationEvaluates

theorem ThresholdPure.i32LocalLessEqualNegOne
    (program : Program) (state : State) (localId : VarId) (left : Int)
    (localFound : state.local? localId = some (.signed .i32 left))
    (formed : state.CellsWellFormed) :
    ThresholdPure 4 program state
      (.binary .lessEqual (.local localId)
        (.unary .negate (.value (.signed .i32 1))))
      (.boolean (decide (left ≤ -1))) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [← show (fuel - 4).succ.succ.succ.succ = fuel by omega]
  apply evalExpr_binary_done (fuel := (fuel - 4).succ.succ) program state .lessEqual
    (.local localId)
    (.unary .negate (.value (.signed .i32 1)))
    (.signed .i32 left) (.signed .i32 (-1))
    (.boolean (decide (left ≤ -1))) state state
  · exact evalExpr_local_of_local? (fuel - 4).succ.succ program state localId
      (.signed .i32 left) localFound
  · rw [evalExpr.eq_def]
    simp [evalUnaryValue, evalExpr_value, wrapSigned, signedModulus,
      signedSignBit, SignedIntTy.bits]
  · simp
  · simp [evalBinaryValue, evalSignedBinary]

theorem ThresholdPure.i32LocalsLess
    (program : Program) (state : State)
    (leftId rightId : VarId) (left right : Int)
    (leftFound : state.local? leftId = some (.signed .i32 left))
    (rightFound : state.local? rightId = some (.signed .i32 right))
    (formed : state.CellsWellFormed) :
    ThresholdPure 2 program state
      (.binary .less (.local leftId) (.local rightId))
      (.boolean (decide (left < right))) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [← show (fuel - 2).succ.succ = fuel by omega]
  exact evalExpr_i32_locals_less (fuel - 2) program state leftId rightId left right
    leftFound rightFound

theorem ThresholdPure.i32LocalEqualLiteral
    (program : Program) (state : State)
    (localId : VarId) (left literal : Int)
    (localFound : state.local? localId = some (.signed .i32 left))
    (formed : state.CellsWellFormed) :
    ThresholdPure 2 program state
      (.binary .equal (.local localId) (.value (.signed .i32 literal)))
      (.boolean (left == literal)) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [← show (fuel - 2).succ.succ = fuel by omega]
  apply evalExpr_binary_done (fuel := (fuel - 2).succ) program state .equal
    (.local localId) (.value (.signed .i32 literal))
    (.signed .i32 left) (.signed .i32 literal) (.boolean (left == literal)) state state
  · exact evalExpr_local_of_local? (fuel - 2) program state localId
      (.signed .i32 left) localFound
  · exact evalExpr_value (fuel - 2) program state (.signed .i32 literal)
  · simp
  · exact evalBinaryValue_signed_equal program.target .i32 left literal

theorem ThresholdPure.i32LocalEqualConstant
    (program : Program) (state : State)
    (localId constant : Nat) (left value : Int) (declaration : Constant)
    (localFound : state.local? localId = some (.signed .i32 left))
    (constantFound : program.constant? constant = some declaration)
    (constantValue : declaration.value = .signed .i32 value)
    (formed : state.CellsWellFormed) :
    ThresholdPure 3 program state
      (.binary .equal (.local localId) (.constant constant))
      (.boolean (left == value)) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [show fuel = (fuel - 2).succ.succ by omega]
  apply evalExpr_binary_done (fuel := (fuel - 2).succ) program state .equal
    (.local localId) (.constant constant) (.signed .i32 left)
    (.signed .i32 value) (.boolean (left == value)) state state
  · exact evalExpr_local_of_local? (fuel - 2) program state localId
      (.signed .i32 left) localFound
  · rw [show (fuel - 2).succ = ((fuel - 2).succ - 1).succ by omega,
      evalExpr.eq_def]
    simp [constantFound, constantValue]
  · simp
  · exact evalBinaryValue_signed_equal program.target .i32 left value

theorem ThresholdPure.i32LocalsEqual
    (program : Program) (state : State)
    (leftId rightId : VarId) (left right : Int)
    (leftFound : state.local? leftId = some (.signed .i32 left))
    (rightFound : state.local? rightId = some (.signed .i32 right))
    (formed : state.CellsWellFormed) :
    ThresholdPure 2 program state
      (.binary .equal (.local leftId) (.local rightId))
      (.boolean (left == right)) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [← show (fuel - 2).succ.succ = fuel by omega]
  apply evalExpr_binary_done (fuel := (fuel - 2).succ) program state .equal
    (.local leftId) (.local rightId)
    (.signed .i32 left) (.signed .i32 right) (.boolean (left == right)) state state
  · exact evalExpr_local_of_local? (fuel - 2) program state leftId
      (.signed .i32 left) leftFound
  · exact evalExpr_local_of_local? (fuel - 2) program state rightId
      (.signed .i32 right) rightFound
  · simp
  · exact evalBinaryValue_signed_equal program.target .i32 left right

end Lanius.Semantics
