import Lanius.Extraction.CompactOutput.Tokens.Source
import Lanius.Extraction.CompactOutput.Word.Chunks

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Lexer

def encoding (token : RawToken) : List Nat :=
  (hexDigits token.kind.gpuCode 8 ++ hexDigits token.start 8) ++ hexDigits token.finish 8

/-- All three source calls execute, including after exhaustion. The sentinel
cursor makes later calls preserve precisely the already-written prefix. -/
theorem write_fields (word : Word.Checked program byte digit)
    (token : RawToken) (capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before)
    (kindFit : token.kind.gpuCode ≤ 2147483647)
    (startFit : token.start ≤ 2147483647) (finishFit : token.finish ≤ 2147483647)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (cursor : (Assertion.localPointsTo 7 cursorCell (some (.signed .i32 position))).holds before)
    (outputRead : before.local? 4 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 5 = some (.signed .i32 capacity))
    (kind : Evaluates program.core before kindRead (.signed .i32 token.kind.gpuCode) before)
    (startRead : before.local? 10 = some (.signed .i32 token.start))
    (finishRead : before.local? 11 = some (.signed .i32 token.finish))
    (stable : ∀ id ∈ [4, 5, 10, 11], ∀ cell, before.cellId? id = some cell → cell ≠ cursorCell)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ first second after,
      Evaluates program.core before (kindWrite word.source.function.id) .unit first ∧
      Evaluates program.core first (startWrite word.source.function.id) .unit second ∧
      Evaluates program.core second (finishWrite word.source.function.id) .unit after ∧
      (Assertion.localPointsTo 7 cursorCell
        (some (.signed .i32 (appendAll capacity (encoding token) position original).position))).holds after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll capacity (encoding token) position original).contents)) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton cursorCell)) before after := by
  have keep {state : State}
      (effect : CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton cursorCell)) before state)
      {id : VarId} {value : Value} (member : id ∈ [4, 5, 10, 11])
      (found : before.local? id = some value) (different : value ≠ .array (signedI32Values original)) :
      state.local? id = some value := by
    apply effect.preserves_local wellFormed found
    intro cell binding changed
    rcases changed with output | cursor
    · exact local_cell_ne_of_distinct_value found backing different binding output
    · exact stable id member cell binding cursor
  obtain ⟨first, firstRun, firstCursor, firstBacking, firstEffect⟩ := Word.assign_word word
    position capacity token.kind.gpuCode wellFormed capacityBound capacityFit kindFit cursor backing
    (local_evaluates program.core outputRead) (local_evaluates program.core capacityRead) kind
  have firstOutput : first.local? 4 = some (.slice i32 outputCell [] 0
      (appendAll capacity (hexDigits token.kind.gpuCode 8) position original).contents.length) := by
    simpa only [appendAll_length] using keep firstEffect (by simp) outputRead (by intro same; cases same)
  obtain ⟨second, secondRun, secondCursor, secondBacking, secondEffect⟩ := Word.assign_word word
    (appendAll capacity (hexDigits token.kind.gpuCode 8) position original).position capacity token.start
    firstEffect.wellFormed (by simpa only [appendAll_length] using capacityBound) capacityFit startFit
    firstCursor firstBacking (local_evaluates program.core firstOutput)
    (local_evaluates program.core (keep firstEffect (by simp) capacityRead (by intro same; cases same)))
    (local_evaluates program.core (keep firstEffect (by simp) startRead (by intro same; cases same)))
  have pair := Word.appendAll_following_word capacity token.start (hexDigits token.kind.gpuCode 8) position original
  rw [← pair] at secondCursor secondBacking
  have pairEffect := firstEffect.trans secondEffect
  have secondOutput : second.local? 4 = some (.slice i32 outputCell [] 0
      (appendAll capacity (hexDigits token.kind.gpuCode 8 ++ hexDigits token.start 8) position original).contents.length) := by
    simpa only [appendAll_length] using keep pairEffect (by simp) outputRead (by intro same; cases same)
  obtain ⟨after, thirdRun, finalCursor, finalBacking, thirdEffect⟩ := Word.assign_word word
    (appendAll capacity (hexDigits token.kind.gpuCode 8 ++ hexDigits token.start 8) position original).position
    capacity token.finish pairEffect.wellFormed (by simpa only [appendAll_length] using capacityBound)
    capacityFit finishFit secondCursor secondBacking (local_evaluates program.core secondOutput)
    (local_evaluates program.core (keep pairEffect (by simp) capacityRead (by intro same; cases same)))
    (local_evaluates program.core (keep pairEffect (by simp) finishRead (by intro same; cases same)))
  have triple := Word.appendAll_following_word capacity token.finish
    (hexDigits token.kind.gpuCode 8 ++ hexDigits token.start 8) position original
  exact ⟨first, second, after, firstRun, secondRun, thirdRun,
    by simpa only [encoding, triple] using finalCursor,
    by simpa only [encoding, triple] using finalBacking,
    pairEffect.trans thirdEffect⟩

end Lanius.Extraction.CompactOutput.Tokens
