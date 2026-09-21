import Lanius.Compiler.Lexer.QuotedInvariant
import Lanius.Semantics.Scalar

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

private theorem i32LocalsLessEqualSubOne
    (program : Program) (state : State) (left right : Nat)
    (leftFound : state.local? 4 = some (.signed .i32 (Int.ofNat left)))
    (rightFound : state.local? 1 = some (.signed .i32 (Int.ofNat right)))
    (rightBound : right < 2 ^ 31)
    (formed : state.CellsWellFormed) :
    ThresholdPure 3 program state
      (.binary .lessEqual (.local 4)
        (.binary .subtract (.local 1) (.value (.signed .i32 1))))
      (.boolean (decide (left < right))) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [show fuel = (fuel - 3).succ.succ.succ by omega]
  have leftRun := evalExpr_local_of_local? ((fuel - 3).succ.succ) program state 4
    (.signed .i32 (Int.ofNat left)) leftFound
  have rightLocalRun := evalExpr_local_of_local? ((fuel - 3).succ) program state 1
    (.signed .i32 (Int.ofNat right)) rightFound
  have rightValueRun := evalExpr_value ((fuel - 3).succ) program state
    (.signed .i32 1)
  have rightRun : evalExpr (fuel - 3).succ.succ program state
      (.binary .subtract (.local 1) (.value (.signed .i32 1))) =
      .done (.signed .i32 (Int.ofNat right - 1)) state := by
    apply evalExpr_binary_done (fuel := (fuel - 3).succ) program state .subtract
      (.local 1) (.value (.signed .i32 1))
      (.signed .i32 (Int.ofNat right)) (.signed .i32 1)
      (.signed .i32 (Int.ofNat right - 1)) state state
      rightLocalRun rightValueRun (by simp)
    simp only [evalBinaryValue, evalSignedBinary]
    cases right with
    | zero => simp [wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
    | succ right =>
        simp only [beq_self_eq_true, if_true]
        rw [show Int.ofNat (Nat.succ right) - 1 = Int.ofNat right by simp]
        exact congrArg (fun value : Int =>
          (Except.ok (Value.signed .i32 value) : Except Trap Value))
          (wrapSigned_i32_nat_lt program.target right (by omega))
  apply evalExpr_binary_done (fuel := (fuel - 3).succ.succ) program state .lessEqual
    (.local 4) (.binary .subtract (.local 1) (.value (.signed .i32 1)))
    (.signed .i32 (Int.ofNat left)) (.signed .i32 (Int.ofNat right - 1))
    (.boolean (decide (left < right))) state state leftRun rightRun (by simp)
  simp only [evalBinaryValue, evalSignedBinary, signedComparison]
  simp
  omega

def quotedCondition : Expr :=
  .binary .lessEqual (.local 4)
    (.binary .subtract (.local 1) (.value (.signed .i32 1)))

theorem quotedCondition_outOfBounds
    (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (outOfBounds : ¬ cursor < source.length) :
    ThresholdPure 3 program current quotedCondition (.boolean false) current := by
  have less := i32LocalsLessEqualSubOne program current cursor source.length
    invariant.cursorLocal invariant.lengthLocal invariant.sourceLengthI32
    invariant.frame.currentFormed
  refine ⟨?_, PureFrame.refl invariant.frame.currentFormed⟩
  intro fuel enough
  simpa [quotedCondition, show decide (cursor < source.length) = false by
    simp [outOfBounds]] using
    less.run fuel (by omega)

theorem quotedCondition_inBounds
    (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (inBounds : cursor < source.length) :
    ThresholdPure 3 program current quotedCondition (.boolean true) current := by
  have less := i32LocalsLessEqualSubOne program current cursor source.length
    invariant.cursorLocal invariant.lengthLocal invariant.sourceLengthI32
    invariant.frame.currentFormed
  refine ⟨?_, PureFrame.refl invariant.frame.currentFormed⟩
  intro fuel enough
  simpa [quotedCondition, show decide (cursor < source.length) = true by
    simp [inBounds]] using
    less.run fuel (by omega)

end Lanius.Compiler.Lexer
