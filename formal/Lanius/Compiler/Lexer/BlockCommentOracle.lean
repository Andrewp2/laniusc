import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.ArtifactComments
import Lanius.Compiler.Lexer.BlockCommentCondition
import Lanius.Compiler.Lexer.BlockCommentModel
import Lanius.Compiler.Lexer.BlockCommentStep
import Lanius.Compiler.Lexer.ScanEndFunctions
import Lanius.Semantics.TotalWhile

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

private def blockLoopCondition : Expr :=
  .binary .lessEqual (.local 3)
    (.binary .subtract (.local 1) (.value (.signed .i32 1)))

def blockCursor (state : State) : Nat :=
  match state.local? 3 with
  | some (.signed .i32 value) => value.toNat
  | _ => 0

def blockCommentMeasure (source : List Byte) (state : State) : Nat :=
  source.length - blockCursor state

def blockCommentInvariant
    (caller : State) (cell : CellId) (source : List Byte) (expected : ScanEnd)
    (state : State) : Prop :=
  ∃ cursor cursorCellId,
    ScannerInvariant caller state cell source cursor cursorCellId ∧
    scanBlockBody (source.drop cursor) cursor = expected

def blockCommentDone
    (caller : State) (cell : CellId) (source : List Byte) (expected : ScanEnd) :
    Completion → State → Prop
  | .returned (some value), state =>
      match expected with
      | .success offset => value = scanEndValue (.success offset) ∧
          CallerFrame caller state
      | .failure _ => False
  | .next, state => match expected with
      | .failure _ => ∃ cursor cursorCellId,
          ScannerInvariant caller state cell source cursor cursorCellId ∧
            scanBlockBody (source.drop cursor) cursor = expected
      | .success _ => False
  | _, _ => False

private theorem blockCommentClose_at
    (source : List Byte) (cursor : Nat) (inBounds : cursor < source.length)
    (closes : blockConditionResult source cursor = true) :
    ∃ nextInBounds : cursor + 1 < source.length,
      source[cursor].val = 42 ∧ source[cursor + 1].val = 47 ∧
      scanBlockBody (source.drop cursor) cursor = .success (cursor + 2) := by
  have nextInBounds : cursor + 1 < source.length := by
    by_cases nextInBounds : cursor + 1 < source.length <;>
      simp_all [blockConditionResult]
  have close : source[cursor].val = 42 ∧ source[cursor + 1].val = 47 := by
    simpa [blockConditionResult, List.getElem?_eq_getElem inBounds,
      List.getElem?_eq_getElem nextInBounds] using closes
  refine ⟨nextInBounds, close.1, close.2, ?_⟩
  rw [List.drop_eq_getElem_cons inBounds, List.drop_eq_getElem_cons nextInBounds]
  exact scanBlockBody_close _ _ _ _ close.1 close.2

private theorem scanBlockBody_step_at
    (source : List Byte) (cursor : Nat) (inBounds : cursor < source.length)
    (notClose : blockConditionResult source cursor ≠ true) :
    scanBlockBody (source.drop cursor) cursor =
      scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
  by_cases nextInBounds : cursor + 1 < source.length
  · have notClose' : ¬(source[cursor].val = 42 ∧ source[cursor + 1].val = 47) := by
      intro close
      apply notClose
      simp [blockConditionResult, List.getElem?_eq_getElem inBounds,
        List.getElem?_eq_getElem nextInBounds, close]
    rw [List.drop_eq_getElem_cons inBounds, List.drop_eq_getElem_cons nextInBounds]
    exact scanBlockBody_ordinary _ _ _ _ notClose'
  · rw [List.drop_eq_getElem_cons inBounds,
      List.drop_eq_nil_of_le (Nat.le_of_not_gt nextInBounds)]
    simp [scanBlockBody]

def blockCommentLoopOracle
    (caller : State) (cell : CellId) (source : List Byte) (expected : ScanEnd)
    (backing : SourceBacking caller cell (sourceI32Values source)) :
    TotalWhileOracle (blockCommentMeasure source) Artifact.lexerProgram
      blockLoopCondition Artifact.blockLoopBody := by
  refine ⟨blockCommentInvariant caller cell source expected,
    blockCommentDone caller cell source expected, ?_⟩
  intro state inv
  obtain ⟨cursor, cursorCellId, invariant, model⟩ := inv
  have condition := i32LocalsLessEqualSubOne Artifact.lexerProgram state 3 1 cursor source.length
    invariant.cursorLocal invariant.lengthLocal invariant.sourceLengthI32 invariant.frame.currentFormed
  have conditionRun : StableExpr 3 Artifact.lexerProgram state blockLoopCondition
      (.boolean (decide (cursor < source.length))) state := by
    intro fuel enough
    simpa [blockLoopCondition] using condition.run fuel enough
  have conditionAt (value : Bool) (equal : decide (cursor < source.length) = value) :
      StableExpr 3 Artifact.lexerProgram state blockLoopCondition (.boolean value) state := by
    simpa [equal] using conditionRun
  by_cases inBounds : cursor < source.length
  · right
    have conditionRun' := conditionAt true (by simp [inBounds])
    have bodyConditionRun : StableExpr 9 Artifact.lexerProgram state Artifact.blockCondition
        (.boolean (blockConditionResult source cursor)) state :=
      (blockCondition_eval Artifact.lexerProgram invariant inBounds).run
    by_cases closes : blockConditionResult source cursor = true
    · obtain ⟨nextInBounds, currentClose, nextClose, modelClose⟩ :=
        blockCommentClose_at source cursor inBounds closes
      have bound : cursor + 2 < 2 ^ 31 := Nat.lt_of_le_of_lt (by omega) invariant.sourceLengthI32
      have argument := ThresholdPure.i32LocalAddNat Artifact.lexerProgram state 3 cursor 2 invariant.cursorLocal invariant.frame.currentFormed bound
      obtain ⟨callFuel, callAfter, callRun⟩ := successfulScan_of_argument state (.binary .add (.local 3) (.value (.signed .i32 2))) (cursor + 2) argument
      have bodyRun := blockCommentLoopBody_close Artifact.lexerProgram invariant
        (by intro fuel enough; simpa [closes] using bodyConditionRun fuel enough) callRun.run
      have expectedEq : expected = .success (cursor + 2) := by simpa [← model] using modelClose
      refine ⟨3, max 9 (callFuel + 2) + 2, state, .returned (some (scanEndValue (.success (cursor + 2)))),
        callAfter, conditionRun', bodyRun, ?_, ?_⟩
      · intro _
        simpa [blockCommentDone, normalizeCompletion, expectedEq] using (⟨rfl, invariant.frame.transPure callRun.frame⟩ :
          scanEndValue (.success (cursor + 2)) = scanEndValue (.success (cursor + 2)) ∧ CallerFrame caller callAfter)
      · exact fun h => by rcases h with h | h <;> cases h
    · obtain ⟨after, bodyRun, nextInvariant⟩ := blockCommentLoopBody_ordinary Artifact.lexerProgram
        invariant inBounds backing (by intro fuel enough; simpa [closes] using bodyConditionRun fuel enough)
      have nextModel : scanBlockBody (source.drop (cursor + 1)) (cursor + 1) = expected := (scanBlockBody_step_at source cursor inBounds closes).symm.trans model
      refine ⟨3, 11, state, .next, after, conditionRun', bodyRun, ?_, ?_⟩
      · exact fun h => (h.1 rfl).elim
      · intro _
        refine ⟨?_, ⟨cursor + 1, cursorCellId, nextInvariant, nextModel⟩⟩
        simpa [blockCommentMeasure, blockCursor, invariant.cursorLocal, nextInvariant.cursorLocal] using scanBlockBody_cursor_decreases source cursor inBounds
  · left
    have conditionRun' := conditionAt false (by simp [inBounds])
    have cursorEq : cursor = source.length := Nat.le_antisymm invariant.cursorInSource (Nat.le_of_not_gt inBounds)
    have expectedEq : expected = .failure source.length := by
      simpa [← model, cursorEq] using scanBlockBody_source_eof source source.length (by simp)
    refine ⟨3, state, conditionRun', ?_⟩
    simpa [blockCommentDone, expectedEq] using (⟨cursor, cursorCellId, invariant, model⟩ :
      ∃ cursor cursorCellId, ScannerInvariant caller state cell source cursor cursorCellId ∧ scanBlockBody (source.drop cursor) cursor = expected)

theorem blockCommentLoop_execute
    (caller : State) (cell : CellId) (source : List Byte) (expected : ScanEnd)
    (backing : SourceBacking caller cell (sourceI32Values source))
    (state : State) (initial : blockCommentInvariant caller cell source expected state) :
    ∃ threshold completion after,
      StableStmt threshold Artifact.lexerProgram state
        (.whileLoop blockLoopCondition Artifact.blockLoopBody) completion after ∧
      blockCommentDone caller cell source expected completion after := by
  exact executeTotalWhile (blockCommentMeasure source) Artifact.lexerProgram
    blockLoopCondition Artifact.blockLoopBody
    (blockCommentLoopOracle caller cell source expected backing) state initial

end Lanius.Compiler.Lexer
