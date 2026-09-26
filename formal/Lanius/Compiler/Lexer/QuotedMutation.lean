import Lanius.Compiler.Lexer.ArtifactQuoted
import Lanius.Compiler.Lexer.QuotedInvariant
import Lanius.Semantics.StmtList

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

/-! Fuel-hidden contracts for the two mutations at the quoted-loop head. -/

private theorem assignedRun
    {program : Program} {state after : State} {id : VarId} {value : Value}
    {expression : Expr} {threshold : Nat}
    (stable : StableExpr threshold program state expression .unit after)
    (assigned : state.assignLocal id value = some after) :
    RunsExpr program state expression .unit after :=
  RunsExpr.ofStable stable
    (assignLocal_preserves_frame (protectedId := id) assigned).1

theorem quotedEscapingSet_runs
    (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (nextEscaping : Bool) (after : State)
    (assigned : current.assignLocal 5 (.boolean nextEscaping) = some after) :
    RunsStmt program current
      (.expression (.assign .set (.local 5) (.value (.boolean nextEscaping))))
      .next after ∧
      QuotedInvariant caller after cell source delimiter cursor nextEscaping
        cursorCellId escapingCellId := by
  have expression : RunsStmt program current
      (.expression (.assign .set (.local 5) (.value (.boolean nextEscaping))))
      .next after := RunsStmt.expression (assignedRun
    (StableExpr.assignSetBool program current 5 escapingCellId
      (.boolean escaping) nextEscaping after invariant.escapingCell
      invariant.escapingLocal assigned rfl) assigned)
  exact ⟨expression, QuotedInvariant.afterEscapingAssignment invariant nextEscaping
    (.boolean nextEscaping) assigned rfl⟩

theorem quotedLoopBeginEscape_runs
    (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (after : State)
    (assigned : current.assignLocal 5 (.boolean true) = some after) :
    RunsStmt program current Artifact.quotedLoopBeginEscape .next after ∧
      QuotedInvariant caller after cell source delimiter cursor true
        cursorCellId escapingCellId := by
  obtain ⟨setRun, nextInvariant⟩ := quotedEscapingSet_runs program invariant true after assigned
  have whole := RunsStmt.sequenceNext setRun (RunsStmt.skip program after)
  refine ⟨?_, nextInvariant⟩
  change RunsStmt program current
    (.sequence (.expression (.assign .set (.local 5) (.value (.boolean true)))) .skip)
    .next after
  exact whole

theorem quotedCursorAdvance_runs
    (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (nextValue : Value) (after : State)
    (assigned : current.assignLocal 4 nextValue = some after)
    (valueEq : nextValue = .signed .i32 (Int.ofNat (cursor + 1)))
    (nextInSource : cursor + 1 ≤ source.length) :
    RunsStmt program current Artifact.quotedLoopAdvance .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) escaping
        cursorCellId escapingCellId := by
  have sourceLengthI32 := invariant.sourceLengthI32
  have nextBound : cursor + 1 < 2 ^ 31 := by omega
  have wrapped : wrapSigned program.target .i32 (Int.ofNat cursor + 1) =
      Int.ofNat (cursor + 1) := by
    have sumEq : Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) := by simp
    rw [sumEq]
    simpa [Int.ofNat_eq_natCast] using
      wrapSigned_i32_nat_lt program.target (cursor + 1) nextBound
  have assignedWrapped : current.assignLocal 4
      (.signed .i32 (wrapSigned program.target .i32 (Int.ofNat cursor + 1))) = some after := by
    rw [wrapped]
    simpa [valueEq] using assigned
  have expression : RunsStmt program current
      (.expression (.assign .add (.local 4) (.value (.signed .i32 1)))) .next after := by
    have run : RunsExpr program current
        (.assign .add (.local 4) (.value (.signed .i32 1))) .unit after :=
      assignedRun (StableExpr.assignAddI32 program current 4 cursorCellId
        (Int.ofNat cursor) 1 after invariant.cursorCell invariant.cursorLocal
        assignedWrapped) assignedWrapped
    exact RunsStmt.expression run
  refine ⟨?_, QuotedInvariant.afterCursorAssignment invariant (cursor + 1)
    nextValue assigned valueEq nextInSource⟩
  change RunsStmt program current
    (.expression (.assign .add (.local 4) (.value (.signed .i32 1)))) .next after
  exact expression

theorem quotedLoopEscaped_runs
    (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (setAfter after : State) (advanceValue : Value)
    (setAssigned : current.assignLocal 5 (.boolean false) = some setAfter)
    (advanceAssigned : setAfter.assignLocal 4 advanceValue = some after)
    (advanceValueEq : advanceValue = .signed .i32 (Int.ofNat (cursor + 1)))
    (nextInSource : cursor + 1 ≤ source.length) :
    RunsStmt program current Artifact.quotedLoopEscaped .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) false
        cursorCellId escapingCellId := by
  obtain ⟨setRun, setInvariant⟩ := quotedEscapingSet_runs program invariant false setAfter
    setAssigned
  obtain ⟨advanceRun, finalInvariant⟩ := quotedCursorAdvance_runs program setInvariant
    advanceValue after advanceAssigned advanceValueEq nextInSource
  have tail := RunsStmt.sequenceNext advanceRun (RunsStmt.skip program after)
  have whole := RunsStmt.sequenceNext setRun tail
  refine ⟨?_, finalInvariant⟩
  change RunsStmt program current
    (.sequence (.expression (.assign .set (.local 5) (.value (.boolean false))))
      (.sequence (.expression (.assign .add (.local 4) (.value (.signed .i32 1)))) .skip))
      .next after
  exact whole

end Lanius.Compiler.Lexer
