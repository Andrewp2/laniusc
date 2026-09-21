import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.ScannerOracle
import Lanius.Compiler.Lexer.ScannerStep
import Lanius.Semantics.Scalar

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

/-! A scanner condition whose byte test is inlined in Core rather than called
    through a predicate function.  The comparison family is deliberately
    small: these are the two scalar equality operators used by direct byte
    tests, with an arbitrary i32 literal. -/

inductive DirectByteComparison where
  | equal (value : Nat)
  | notEqual (value : Nat)
deriving DecidableEq, Repr

def DirectByteComparison.operation : DirectByteComparison → BinaryOp := fun
  | .equal _ => .equal | .notEqual _ => .notEqual

def DirectByteComparison.literal : DirectByteComparison → Nat
  | .equal value | .notEqual value => value

def DirectByteComparison.accepts : DirectByteComparison → Byte → Bool := fun
  | .equal value, byte => byte.val == value
  | .notEqual value, byte => !(byte.val == value)

def directByteComparisonExpr (sourceId cursorId : VarId)
    (comparison : DirectByteComparison) : Expr :=
  .binary comparison.operation (.index (.local sourceId) (.local cursorId))
    (.value (.signed .i32 (Int.ofNat comparison.literal)))

def directScannerCondition (sourceId limitId cursorId : VarId)
    (comparison : DirectByteComparison) : Expr :=
  .binary .logicalAnd
    (.binary .lessEqual (.local cursorId)
      (.binary .subtract (.local limitId) (.value (.signed .i32 1))))
    (directByteComparisonExpr sourceId cursorId comparison)

theorem directByteComparison_eval (program : Program) (state : State)
    (sourceId cursorId : VarId) (cell : CellId) (source : List Byte) (cursor : Nat)
    (comparison : DirectByteComparison)
    (sourceSlice : SourceSlice state sourceId cell (sourceI32Values source))
    (cursorFound : state.local? cursorId = some (.signed .i32 (Int.ofNat cursor))) (inBounds : cursor < source.length) :
    ∀ fuel, 3 ≤ fuel →
      evalExpr fuel program state
        (directByteComparisonExpr sourceId cursorId comparison) =
        .done (.boolean (comparison.accepts (source.get ⟨cursor, inBounds⟩))) state := by
  intro fuel enough
  simpa [directByteComparisonExpr, show fuel - 1 + 1 = fuel by omega] using
    (evalExpr_binary_done (fuel := fuel - 1) program state comparison.operation
      (.index (.local sourceId) (.local cursorId))
      (.value (.signed .i32 (Int.ofNat comparison.literal)))
      (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))
      (.signed .i32 (Int.ofNat comparison.literal))
      (.boolean (comparison.accepts (source.get ⟨cursor, inBounds⟩))) state state
      (by simpa [sourceI32Values] using
        (evalExpr_source_slice_index_of_locals program state sourceId cursorId cell
          (sourceI32Values source) cursor sourceSlice cursorFound
          (by simpa [sourceI32Values] using inBounds) (fuel - 1) (by omega)))
      (by simpa [show fuel - 2 + 1 = fuel - 1 by omega] using
        (evalExpr_value (fuel - 2) program state
          (.signed .i32 (Int.ofNat comparison.literal))))
      (by cases comparison <;> simp [DirectByteComparison.operation])
      (by
        have intOfNatBeq (left right : Nat) :
            (Int.ofNat left == Int.ofNat right) = (left == right) := by
          apply Bool.eq_iff_iff.mpr <;> simp only [beq_iff_eq, Int.ofNat.injEq]
        cases comparison <;> rename_i value <;>
          simpa [DirectByteComparison.operation, DirectByteComparison.literal,
            DirectByteComparison.accepts, evalBinaryValue, scalarEqual] using
            intOfNatBeq (source.get ⟨cursor, inBounds⟩).val value))

theorem directScannerCondition_outOfBounds
    (program : Program) (state : State)
    (sourceId limitId cursorId : VarId) (comparison : DirectByteComparison)
    (cursor limit : Nat)
    (limitFound : state.local? limitId =
      some (.signed .i32 (Int.ofNat limit)))
    (cursorFound : state.local? cursorId =
      some (.signed .i32 (Int.ofNat cursor)))
    (formed : state.CellsWellFormed) (outOfBounds : ¬ cursor < limit)
    (limitBound : limit < 2 ^ 31) :
    ThresholdPure 4 program state
      (directScannerCondition sourceId limitId cursorId comparison)
      (.boolean false) state := by
  have less := i32LocalsLessEqualSubOne program state cursorId limitId cursor limit
    cursorFound limitFound limitBound formed
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  simpa [directScannerCondition, show fuel - 1 + 1 = fuel by omega] using
    evalExpr_logicalAnd_false (fuel - 1) program state
      (.binary .lessEqual (.local cursorId)
        (.binary .subtract (.local limitId) (.value (.signed .i32 1))))
      (directByteComparisonExpr sourceId cursorId comparison) state
      (by simpa [show decide (cursor < limit) = false by simp [outOfBounds]] using
        less.run (fuel - 1) (by omega))

theorem directScannerCondition_inBounds
    (program : Program) (state : State)
    (sourceId limitId cursorId : VarId) (comparison : DirectByteComparison)
    (cell : CellId) (source : List Byte) (cursor limit : Nat)
    (limitFound : state.local? limitId =
      some (.signed .i32 (Int.ofNat limit)))
    (cursorFound : state.local? cursorId =
      some (.signed .i32 (Int.ofNat cursor)))
    (sourceSlice : SourceSlice state sourceId cell (sourceI32Values source))
    (formed : state.CellsWellFormed) (inBounds : cursor < limit)
    (sourceFits : cursor < source.length) (limitBound : limit < 2 ^ 31) :
    ThresholdPure 4 program state
      (directScannerCondition sourceId limitId cursorId comparison)
      (.boolean (comparison.accepts (source.get ⟨cursor, sourceFits⟩))) state := by
  have less := i32LocalsLessEqualSubOne program state cursorId limitId cursor limit
    cursorFound limitFound limitBound formed
  refine ⟨?_, less.frame⟩
  intro fuel enough
  simpa [directScannerCondition, show fuel - 1 + 1 = fuel by omega] using
    evalExpr_logicalAnd_true (fuel - 1) program state
      (.binary .lessEqual (.local cursorId)
        (.binary .subtract (.local limitId) (.value (.signed .i32 1))))
      (directByteComparisonExpr sourceId cursorId comparison)
      (.boolean (comparison.accepts (source.get ⟨cursor, sourceFits⟩))) state state
      (by simpa [show decide (cursor < limit) = true by simp [inBounds]] using
        less.run (fuel - 1) (by omega))
      (directByteComparison_eval program state sourceId cursorId cell source cursor
        comparison sourceSlice cursorFound sourceFits (fuel - 1) (by omega))

/-! The execution oracle has the same state invariant and incrementing body as
    the predicate-backed scanner.  Only the condition proof changes. -/
def directScannerLoopOracle
    (program : Program) (caller : State) (cell : CellId) (source : List Byte)
    (comparison : DirectByteComparison)
    (backing : SourceByteBacking caller cell source) :
    PrefixLoopOracle program
      (directScannerCondition 0 1 3 comparison)
      Artifact.scannerLoopBody (DirectByteComparison.accepts comparison) source := by
  refine ⟨scannerLoopInvariant caller cell source, ?_, ?_, ?_⟩
  · intro cursor state ⟨cursorCellId, invariant⟩ outOfBounds
    have condition := directScannerCondition_outOfBounds program state 0 1 3
      comparison cursor source.length invariant.lengthLocal invariant.cursorLocal
      invariant.frame.currentFormed outOfBounds invariant.sourceLengthI32
    exact ⟨4, state, condition.run, ⟨cursorCellId, invariant.afterPureFrame condition.frame⟩⟩
  · intro cursor state inBounds ⟨cursorCellId, invariant⟩ rejected
    have condition := directScannerCondition_inBounds program state 0 1 3 comparison
      cell source cursor source.length invariant.lengthLocal invariant.cursorLocal
      invariant.sourceSlice invariant.frame.currentFormed inBounds inBounds invariant.sourceLengthI32
    rw [rejected] at condition
    exact ⟨4, state, condition.run, ⟨cursorCellId, invariant.afterPureFrame condition.frame⟩⟩
  · intro cursor state inBounds ⟨cursorCellId, invariant⟩ accepted
    have condition := directScannerCondition_inBounds program state 0 1 3 comparison
      cell source cursor source.length invariant.lengthLocal invariant.cursorLocal
      invariant.sourceSlice invariant.frame.currentFormed inBounds inBounds invariant.sourceLengthI32
    rw [accepted] at condition
    obtain ⟨after, bodyRun, nextInvariant⟩ := scannerLoopBody_step
      program (invariant.afterPureFrame condition.frame) inBounds backing
    exact ⟨4, 4, state, after, condition.run, bodyRun, ⟨cursorCellId, nextInvariant⟩⟩

def directScanEnd (comparison : DirectByteComparison) (source : List Byte) (start : Nat)
    (prefixWidth : Nat := 1) : Nat :=
  scanEnd (comparison.accepts) source start prefixWidth

def lineCommentComparison : DirectByteComparison := .notEqual 10

theorem directScanEnd_lineComment (source : List Byte) (start : Nat) :
    directScanEnd lineCommentComparison source start 2 = scanLineCommentEnd source start := by
  rfl

end Lanius.Compiler.Lexer
