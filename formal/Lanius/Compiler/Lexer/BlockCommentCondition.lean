import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.ArtifactComments
import Lanius.Compiler.Lexer.DirectPrefixScanner
import Lanius.Compiler.Lexer.ScannerInvariant
import Lanius.Semantics.Arithmetic
import Lanius.Semantics.ReadOnlySlice

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

def blockConditionResult (source : List Byte) (cursor : Nat) : Bool :=
  match source[cursor]?, source[cursor + 1]? with
  | some current, some next => current.val == 42 && next.val == 47
  | _, _ => false

private def blockCurrent : Expr := directByteComparisonExpr 0 3 (.equal 42)
private def blockLess : Expr :=
  .binary .lessEqual
    (.binary .add (.local 3) (.value (.signed .i32 1)))
    (.binary .subtract (.local 1) (.value (.signed .i32 1)))
private def blockNext : Expr :=
  .binary .equal (.index (.local 0)
    (.binary .add (.local 3) (.value (.signed .i32 1))))
    (.value (.signed .i32 47))

private theorem evalBlockLess
    (program : Program) {caller current : State} {cell : CellId}
    {source : List Byte} {cursor cursorCellId : Nat}
    (invariant : ScannerInvariant caller current cell source cursor cursorCellId)
    (inBounds : cursor < source.length) :
    ∀ fuel, 5 ≤ fuel →
      evalExpr fuel program current blockLess =
      .done (.boolean (decide (cursor + 1 < source.length))) current := by
  intro fuel enough
  have add := evalExpr_i32LocalAddNat program current 3 cursor 1
    invariant.cursorLocal
    (Nat.lt_of_le_of_lt (Nat.succ_le_of_lt inBounds) invariant.sourceLengthI32)
    (fuel - 1) (by omega)
  have length := evalExpr_local_of_local? (fuel - 3) program current 1
    (.signed .i32 (Int.ofNat source.length)) invariant.lengthLocal
  have length' : evalExpr (fuel - 2) program current (.local 1) =
      .done (.signed .i32 (Int.ofNat source.length)) current := by
    simpa [show fuel - 3 + 1 = fuel - 2 by omega] using length
  have subtract := evalExpr_binary_done (fuel := fuel - 2) program current .subtract
    (.local 1) (.value (.signed .i32 1))
    (.signed .i32 (Int.ofNat source.length)) (.signed .i32 1)
    (.signed .i32 (Int.ofNat source.length - 1)) current current
    length' (by simpa [show fuel - 3 + 1 = fuel - 2 by omega] using
      evalExpr_value (fuel - 3) program current (.signed .i32 1)) (by simp)
    (by
      simp only [evalBinaryValue, evalSignedBinary]
      cases lengthEq : source.length with
      | zero =>
          have impossible : cursor < 0 := by simpa [lengthEq] using inBounds
          exact (Nat.not_lt_zero _ impossible).elim
      | succ length =>
          simp only [beq_self_eq_true, if_true]
          rw [show Int.ofNat (Nat.succ length) - 1 = Int.ofNat length by simp]
          have sourceBound : Nat.succ length < 2 ^ 31 := by
            simpa [lengthEq] using invariant.sourceLengthI32
          exact congrArg (fun value : Int =>
            (Except.ok (Value.signed .i32 value) : Except Trap Value))
            (wrapSigned_i32_nat_lt program.target length (by omega)))
  have subtract' : evalExpr (fuel - 1) program current
      (.binary .subtract (.local 1) (.value (.signed .i32 1))) =
      .done (.signed .i32 (Int.ofNat source.length - 1)) current := by
    simpa [show fuel - 2 + 1 = fuel - 1 by omega] using subtract
  have compared := evalExpr_binary_done (fuel := fuel - 1) program current .lessEqual
    (.binary .add (.local 3) (.value (.signed .i32 1)))
    (.binary .subtract (.local 1) (.value (.signed .i32 1)))
    (.signed .i32 (Int.ofNat (cursor + 1)))
    (.signed .i32 (Int.ofNat source.length - 1))
    (.boolean (decide (cursor + 1 < source.length))) current current
    add subtract' (by simp)
    (by
      simp only [evalBinaryValue, evalSignedBinary]
      simp
      omega)
  simpa [blockLess, show fuel - 1 + 1 = fuel by omega] using compared

theorem blockCondition_eval
    (program : Program) {caller current : State} {cell : CellId}
    {source : List Byte} {cursor cursorCellId : Nat}
    (invariant : ScannerInvariant caller current cell source cursor cursorCellId)
    (inBounds : cursor < source.length) :
    ThresholdPure 9 program current Artifact.blockCondition
      (.boolean (blockConditionResult source cursor)) current := by
  refine ⟨?_, PureFrame.refl invariant.frame.currentFormed⟩
  intro fuel enough
  change evalExpr fuel program current
      (.binary .logicalAnd (.binary .logicalAnd blockCurrent blockLess) blockNext) =
    .done (.boolean (blockConditionResult source cursor)) current
  have currentRun := directByteComparison_eval program current 0 3 cell source cursor
    (.equal 42) invariant.sourceSlice invariant.cursorLocal inBounds
    (fuel - 2) (by omega)
  by_cases nextInBounds : cursor + 1 < source.length
  · have lessRun := evalBlockLess program invariant inBounds (fuel - 2) (by omega)
    have sourceEval : evalExpr (fuel - 3) program current (.local 0) =
        .done (i32SliceValue cell (sourceI32Values source)) current := by
      simpa [show fuel - 4 + 1 = fuel - 3 by omega] using
        (evalExpr_local_of_local? (fuel - 4) program current 0
          (i32SliceValue cell (sourceI32Values source)) invariant.sourceSlice.localFound)
    have addEval : evalExpr (fuel - 3) program current
        (.binary .add (.local 3) (.value (.signed .i32 1))) =
        .done (.signed .i32 (Int.ofNat (cursor + 1))) current := by
      simpa using
        (evalExpr_i32LocalAddNat program current 3 cursor 1 invariant.cursorLocal
          (Nat.lt_trans nextInBounds invariant.sourceLengthI32) (fuel - 3) (by omega))
    have indexed0 := evalExpr_i32_slice_index (fuel - 4) program current cell
      (sourceI32Values source) (cursor + 1)
      invariant.sourceSlice.backingFound.backingFound
        (by simpa [sourceI32Values] using nextInBounds)
    have indexed : evalExpr (fuel - 2) program current
        (.index (.local 0) (.binary .add (.local 3)
          (.value (.signed .i32 1)))) =
        .done (.signed .i32
          (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val)) current := by
      rw [← show (fuel - 3).succ = fuel - 2 by omega, evalExpr.eq_def]
      simp only [sourceEval, i32SliceValue]
      rw [addEval]
      rw [evalExpr.eq_def] at indexed0
      simp [evalExpr_value, i32SliceValue] at indexed0
      simpa [sourceI32Values,
        show (fuel - 4).succ.succ = fuel - 2 by omega] using indexed0
    have nextRun := evalExpr_binary_done (fuel := fuel - 2) program current .equal
      (.index (.local 0) (.binary .add (.local 3)
        (.value (.signed .i32 1)))) (.value (.signed .i32 47))
      (.signed .i32 (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val))
      (.signed .i32 47)
      (.boolean
        (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val == Int.ofNat 47)) current current
      indexed (by
        simpa [show fuel - 3 + 1 = fuel - 2 by omega] using
          evalExpr_value (fuel - 3) program current (.signed .i32 47)) (by decide)
      (evalBinaryValue_signed_equal program.target .i32
        (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val) (Int.ofNat 47))
    have inner := evalExpr_logicalAnd_booleans (fuel - 2) program current
      blockCurrent blockLess ((source.get ⟨cursor, inBounds⟩).val == 42)
      (decide (cursor + 1 < source.length)) currentRun lessRun
    have all := evalExpr_logicalAnd_booleans (fuel - 2).succ program current
      (.binary .logicalAnd blockCurrent blockLess) blockNext
      (((source.get ⟨cursor, inBounds⟩).val == 42) && decide (cursor + 1 < source.length))
      (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val == Int.ofNat 47)
      inner nextRun
    rw [show (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val == Int.ofNat 47) =
        ((source.get ⟨cursor + 1, nextInBounds⟩).val == 47) by
      apply Bool.eq_iff_iff.mpr
      simp only [beq_iff_eq, Int.ofNat.injEq]] at all
    simpa [blockConditionResult, nextInBounds,
      show fuel - 2 + 1 + 1 = fuel by omega,
      List.getElem?_eq_getElem inBounds] using all
  · have lessRun := evalBlockLess program invariant inBounds (fuel - 2) (by omega)
    have all := evalExpr_logicalAnd_false (fuel - 2).succ program current
      (.binary .logicalAnd blockCurrent blockLess) blockNext current
      (by
        simpa using (evalExpr_logicalAnd_booleans (fuel - 2) program current
          blockCurrent blockLess ((source.get ⟨cursor, inBounds⟩).val == 42) false
          currentRun (by simpa [nextInBounds] using lessRun)))
    simpa [blockConditionResult, show fuel - 2 + 1 + 1 = fuel by omega,
      List.getElem?_eq_getElem inBounds,
      List.getElem?_eq_none (Nat.le_of_not_gt nextInBounds)] using all

end Lanius.Compiler.Lexer
