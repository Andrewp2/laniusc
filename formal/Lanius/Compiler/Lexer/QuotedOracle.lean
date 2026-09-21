import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.QuotedBody
import Lanius.Compiler.Lexer.QuotedCondition
import Lanius.Compiler.Lexer.QuotedModel
import Lanius.Semantics.TotalWhile

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

def quotedCursor (state : State) : Nat := match state.local? 4 with
  | some (.signed .i32 value) => value.toNat | _ => 0

def quotedLoopMeasure (source : List Byte) (state : State) : Nat := source.length - quotedCursor state

def quotedLoopInvariant
    (caller : State) (cell : CellId) (source : List Byte) (delimiter : Byte)
    (expected : ScanEnd) (state : State) : Prop :=
  ∃ cursor escaping cursorCellId escapingCellId,
    QuotedInvariant caller state cell source (Int.ofNat delimiter.val) cursor escaping cursorCellId escapingCellId ∧
    scanQuotedBody delimiter escaping (source.drop cursor) cursor = expected

def quotedLoopDone
    (caller : State) (cell : CellId) (source : List Byte) (delimiter : Byte)
    (expected : ScanEnd) : Completion → State → Prop
  | .returned (some value), state =>
      match expected with
      | .success _ | .failure _ => value = scanEndValue expected ∧ CallerFrame caller state
  | .next, state => match expected with
      | .failure _ => expected = .failure source.length ∧
          quotedLoopInvariant caller cell source delimiter expected state
      | .success _ => False
  | _, _ => False

abbrev quotedTrueStep (caller : State) (cell : CellId) (source : List Byte)
    (delimiter : Byte) (expected : ScanEnd) (state : State) : Prop :=
  ∃ conditionThreshold bodyThreshold conditionAfter completion bodyAfter,
    StableExpr conditionThreshold Artifact.lexerProgram state quotedCondition (.boolean true) conditionAfter ∧
    StableStmt bodyThreshold Artifact.lexerProgram conditionAfter Artifact.scanQuotedLoopBody completion bodyAfter ∧
    (completion ≠ .next ∧ completion ≠ .continueLoop →
      quotedLoopDone caller cell source delimiter expected (normalizeCompletion completion) bodyAfter) ∧
    (completion = .next ∨ completion = .continueLoop →
      quotedLoopMeasure source bodyAfter < quotedLoopMeasure source state ∧
      quotedLoopInvariant caller cell source delimiter expected bodyAfter)

def quotedLoopOracle
    (caller : State) (cell : CellId) (source : List Byte) (delimiter : Byte)
    (expected : ScanEnd) : TotalWhileOracle (quotedLoopMeasure source)
      Artifact.lexerProgram quotedCondition Artifact.scanQuotedLoopBody := by
  refine ⟨quotedLoopInvariant caller cell source delimiter expected,
    quotedLoopDone caller cell source delimiter expected, ?_⟩
  intro state inv
  obtain ⟨cursor, escaping, cursorCellId, escapingCellId, invariant, model⟩ := inv
  by_cases inBounds : cursor < source.length
  · have condition := quotedCondition_inBounds Artifact.lexerProgram invariant inBounds
    have conditionRun : StableExpr 3 Artifact.lexerProgram state quotedCondition
        (.boolean true) state := condition.run
    have modelHead : scanQuotedBody delimiter escaping
        (source.get ⟨cursor, inBounds⟩ :: source.drop (cursor + 1)) cursor = expected := by
      rw [List.drop_eq_getElem_cons inBounds] at model
      have sourceEq : source[cursor] = source.get ⟨cursor, inBounds⟩ := by rfl
      simpa only [sourceEq] using model
    have advance {nextEscaping : Bool} {after : State}
        (body : RunsStmt Artifact.lexerProgram state Artifact.scanQuotedLoopBody .next after)
        (nextInvariant : QuotedInvariant caller after cell source
          (Int.ofNat delimiter.val) (cursor + 1) nextEscaping cursorCellId escapingCellId)
        (nextModel : scanQuotedBody delimiter nextEscaping
          (source.drop (cursor + 1)) (cursor + 1) = expected) :
        quotedTrueStep caller cell source delimiter expected state := by
      obtain ⟨bodyThreshold, bodyRun, _⟩ := body
      refine ⟨3, bodyThreshold, state, .next, after, conditionRun, bodyRun, ?_, ?_⟩
      · intro h
        exact (h.1 rfl).elim
      · intro _
        refine ⟨?_, ?_⟩
        · simpa [quotedLoopMeasure, quotedCursor, invariant.cursorLocal,
            nextInvariant.cursorLocal] using
            scanQuotedBody_cursor_decreases source cursor inBounds
        · exact ⟨cursor + 1, nextEscaping, cursorCellId, escapingCellId,
            nextInvariant, nextModel⟩
    have finish {result : ScanEnd} {value : Value} {after : State}
        (body : RunsStmt Artifact.lexerProgram state Artifact.scanQuotedLoopBody
          (.returned (some value)) after)
        (frame : CallerFrame caller after)
        (valueEq : value = scanEndValue result) (expectedEq : expected = result) :
        quotedTrueStep caller cell source delimiter expected state := by
      obtain ⟨bodyThreshold, bodyRun, _⟩ := body
      refine ⟨3, bodyThreshold, state, .returned (some value), after,
        conditionRun, bodyRun, ?_, ?_⟩
      · intro _
        cases result <;>
          simpa [quotedLoopDone, expectedEq, normalizeCompletion] using ⟨valueEq, frame⟩
      · intro h
        rcases h with h | h <;> cases h
    right
    cases escaping with
    | true =>
      obtain ⟨after, body, nextInvariant⟩ := scanQuotedLoopBody_escaped invariant inBounds rfl
      have nextModel : scanQuotedBody delimiter false (source.drop (cursor + 1))
          (cursor + 1) = expected :=
        (scanQuotedBody_escaped delimiter (source.get ⟨cursor, inBounds⟩)
          (source.drop (cursor + 1)) cursor).symm.trans modelHead
      exact advance body nextInvariant nextModel
    | false =>
      by_cases isNewline : (source.get ⟨cursor, inBounds⟩).val = 10
      · have newlineInt : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = 10 := by
          simpa using congrArg Int.ofNat isNewline
        obtain ⟨after, body, frame⟩ := scanQuotedLoopBody_newline invariant inBounds
          rfl newlineInt
        have expectedEq : expected = .failure cursor := by
          simpa [newlineInt] using
            modelHead.symm.trans (scanQuotedBody_newline delimiter
              (source.get ⟨cursor, inBounds⟩) (source.drop (cursor + 1)) cursor isNewline)
        exact finish body frame rfl expectedEq
      · have notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10 := by
          intro h
          apply isNewline
          exact Int.ofNat_inj.mp (by simpa using h)
        by_cases isDelimiter : source.get ⟨cursor, inBounds⟩ = delimiter
        · have delimiterInt : Int.ofNat (source.get ⟨cursor, inBounds⟩).val =
              Int.ofNat delimiter.val := by
            simpa using congrArg (fun b : Byte => Int.ofNat b.val) isDelimiter
          obtain ⟨after, body, frame⟩ := scanQuotedLoopBody_delimiter invariant inBounds
            rfl notNewline delimiterInt
          have expectedEq : expected = .success (cursor + 1) := by
            simpa [isDelimiter] using
              modelHead.symm.trans (scanQuotedBody_delimiter delimiter
                (source.get ⟨cursor, inBounds⟩) (source.drop (cursor + 1)) cursor
                isNewline isDelimiter)
          exact finish body frame rfl expectedEq
        · have notDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠
              Int.ofNat delimiter.val := by
            intro h
            apply isDelimiter
            exact Fin.ext (Int.ofNat_inj.mp h)
          by_cases isBackslash : (source.get ⟨cursor, inBounds⟩).val = 92
          · have backslashInt : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = 92 := by
              simpa using congrArg Int.ofNat isBackslash
            obtain ⟨after, body, nextInvariant⟩ := scanQuotedLoopBody_backslash invariant
              inBounds rfl notNewline notDelimiter backslashInt
            have nextModel : scanQuotedBody delimiter true (source.drop (cursor + 1))
                (cursor + 1) = expected :=
              (scanQuotedBody_backslash delimiter (source.get ⟨cursor, inBounds⟩)
                (source.drop (cursor + 1)) cursor isNewline isDelimiter isBackslash).symm.trans modelHead
            exact advance body nextInvariant nextModel
          · have notBackslash : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 92 := by
              intro h
              apply isBackslash
              exact Int.ofNat_inj.mp (by simpa using h)
            obtain ⟨after, body, nextInvariant⟩ := scanQuotedLoopBody_ordinary invariant
              inBounds rfl notNewline notDelimiter notBackslash
            have nextModel : scanQuotedBody delimiter false (source.drop (cursor + 1))
                (cursor + 1) = expected :=
              (scanQuotedBody_ordinary delimiter (source.get ⟨cursor, inBounds⟩)
                (source.drop (cursor + 1)) cursor isNewline isDelimiter isBackslash).symm.trans modelHead
            exact advance body nextInvariant nextModel
  · left
    have condition := quotedCondition_outOfBounds Artifact.lexerProgram invariant inBounds
    have cursorEq : cursor = source.length := Nat.le_antisymm invariant.cursorInSource (Nat.le_of_not_gt inBounds)
    have expectedEq : expected = .failure source.length := by
      simpa [← model, cursorEq] using
        scanQuotedBody_source_eof delimiter escaping source cursor inBounds
    refine ⟨3, state, condition.run, ?_⟩
    rw [expectedEq]
    change (ScanEnd.failure source.length = ScanEnd.failure source.length) ∧ quotedLoopInvariant caller cell source delimiter (ScanEnd.failure source.length) state
    refine ⟨rfl, ?_⟩
    exact ⟨cursor, escaping, cursorCellId, escapingCellId, invariant, by simpa [expectedEq] using model⟩

theorem quotedLoop_execute (caller : State) (cell : CellId) (source : List Byte) (delimiter : Byte) (expected : ScanEnd) (state : State)
    (initial : quotedLoopInvariant caller cell source delimiter expected state) :
    ∃ threshold completion after,
      StableStmt threshold Artifact.lexerProgram state
        (.whileLoop quotedCondition Artifact.scanQuotedLoopBody) completion after ∧
      quotedLoopDone caller cell source delimiter expected completion after := by
  exact executeTotalWhile (quotedLoopMeasure source) Artifact.lexerProgram
    quotedCondition Artifact.scanQuotedLoopBody
    (quotedLoopOracle caller cell source delimiter expected) state initial

end Lanius.Compiler.Lexer
