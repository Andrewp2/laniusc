import Lanius.Compiler.Lexer.PrefixScanner
import Lanius.Compiler.Lexer.ScannerCondition
import Lanius.Compiler.Lexer.ScannerStep

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

def scannerLoopInvariant
    (caller : State) (cell : CellId) (source : List Byte)
    (cursor : Nat) (state : State) : Prop :=
  ∃ cursorCellId, ScannerInvariant caller state cell source cursor cursorCellId

structure ScannerPredicateContract
    (caller : State) (cell : CellId) (source : List Byte)
    (predicateId : FunctionId) (accept : Byte → Bool) : Prop where
  call : ∀ {state : State} {cursor cursorCellId : Nat}
    (inBounds : cursor < source.length),
    ScannerInvariant caller state cell source cursor cursorCellId →
    ∃ threshold after, ThresholdPure threshold Artifact.lexerProgram state
      (.call predicateId [.index (.local 0) (.local 3)])
      (.boolean (accept (source.get ⟨cursor, inBounds⟩))) after

private theorem scannerConditionStable
    (predicateId : FunctionId)
    (condition : ThresholdPure threshold Artifact.lexerProgram state
      (scannerCondition 0 1 3 predicateId) (.boolean result) after) :
    StableExpr threshold Artifact.lexerProgram state
      (scannerCondition 0 1 3 predicateId) (.boolean result) after := by
  intro fuel enough
  exact condition.run fuel enough

def scannerLoopOracle
    (caller : State) (cell : CellId) (source : List Byte)
    (predicateId : FunctionId) (accept : Byte → Bool)
    (backing : SourceBacking caller cell (sourceI32Values source))
    (predicate : ScannerPredicateContract caller cell source predicateId accept) :
    PrefixLoopOracle Artifact.lexerProgram
      (Artifact.scannerCondition predicateId) Artifact.scannerLoopBody accept source := by
  refine ⟨scannerLoopInvariant caller cell source, ?_, ?_, ?_⟩
  · intro cursor state invariant outOfBounds
    rcases invariant with ⟨cursorCellId, invariant⟩
    have condition := scannerCondition_outOfBounds Artifact.lexerProgram state 0 1 3 predicateId
      cursor source.length invariant.lengthLocal invariant.cursorLocal invariant.frame.currentFormed
      outOfBounds invariant.sourceLengthI32
    exact ⟨4, state, scannerConditionStable predicateId condition,
      ⟨cursorCellId, invariant.afterPureFrame condition.frame⟩⟩
  · intro cursor state inBounds invariant rejected
    rcases invariant with ⟨cursorCellId, invariant⟩
    obtain ⟨predicateThreshold, predicateAfter, predicateCall⟩ := predicate.call inBounds invariant
    have predicateCall' := predicateCall
    rw [rejected] at predicateCall'
    have condition := scannerCondition_inBounds Artifact.lexerProgram state
      0 1 3 predicateId cursor source.length invariant.lengthLocal
      invariant.cursorLocal predicateThreshold false predicateAfter
      predicateCall' invariant.frame.currentFormed inBounds invariant.sourceLengthI32
    exact ⟨max 3 predicateThreshold + 1, predicateAfter,
      scannerConditionStable predicateId condition,
      ⟨cursorCellId, invariant.afterPureFrame condition.frame⟩⟩
  · intro cursor state inBounds invariant accepted
    rcases invariant with ⟨cursorCellId, invariant⟩
    obtain ⟨predicateThreshold, predicateAfter, predicateCall⟩ := predicate.call inBounds invariant
    have predicateCall' := predicateCall
    rw [accepted] at predicateCall'
    have condition := scannerCondition_inBounds Artifact.lexerProgram state
      0 1 3 predicateId cursor source.length invariant.lengthLocal
      invariant.cursorLocal predicateThreshold true predicateAfter
      predicateCall' invariant.frame.currentFormed inBounds invariant.sourceLengthI32
    have conditionInvariant := invariant.afterPureFrame condition.frame
    obtain ⟨after, bodyRun, nextInvariant⟩ := scannerLoopBody_step
      Artifact.lexerProgram conditionInvariant inBounds backing
    exact ⟨max 3 predicateThreshold + 1, 4, predicateAfter, after,
      scannerConditionStable predicateId condition, bodyRun, ⟨cursorCellId, nextInvariant⟩⟩

theorem identifierContinuePredicateContract
    (caller : State) (cell : CellId) (source : List Byte) :
    ScannerPredicateContract caller cell source
      Artifact.identifierContinueFunction.id isIdentifierContinue := by
  refine { call := ?_ }
  intro state cursor cursorCellId inBounds invariant
  have sourceInBounds : cursor < (sourceI32Values source).length := by simpa [sourceI32Values] using inBounds
  obtain ⟨after, predicateCall⟩ := identifierContinueConditionCall state 0 3 cell
    (sourceI32Values source) cursor invariant.sourceSlice invariant.cursorLocal
    invariant.frame.currentFormed sourceInBounds
  refine ⟨13, after, ?_⟩
  have valueEq : (sourceI32Values source).get ⟨cursor, sourceInBounds⟩ =
      Int.ofNat (source.get ⟨cursor, inBounds⟩).val := by simp [sourceI32Values]
  rw [valueEq, identifierStartPredicate_accepts _, decimalPredicate_accepts _] at predicateCall
  simpa [isIdentifierContinue] using predicateCall

theorem whitespacePredicateContract
    (caller : State) (cell : CellId) (source : List Byte) :
    ScannerPredicateContract caller cell source
      Artifact.whitespaceFunction.id isWhitespace := by
  refine { call := ?_ }
  intro state cursor cursorCellId inBounds invariant
  have sourceInBounds : cursor < (sourceI32Values source).length := by simpa [sourceI32Values] using inBounds
  obtain ⟨after, predicateCall⟩ := whitespaceConditionCall state 0 3 cell
    (sourceI32Values source) cursor invariant.sourceSlice invariant.cursorLocal
    invariant.frame.currentFormed sourceInBounds
  refine ⟨max 4 (Artifact.whitespacePredicate.exprFuel + 4), after, ?_⟩
  have valueEq : (sourceI32Values source).get ⟨cursor, sourceInBounds⟩ =
      Int.ofNat (source.get ⟨cursor, inBounds⟩).val := by simp [sourceI32Values]
  rw [valueEq, whitespacePredicate_accepts _] at predicateCall
  simpa using predicateCall

def identifierContinueScannerOracle
    (caller : State) (cell : CellId) (source : List Byte)
    (backing : SourceByteBacking caller cell source) :
    PrefixLoopOracle Artifact.lexerProgram
      (Artifact.scannerCondition Artifact.identifierContinueFunction.id)
      Artifact.scannerLoopBody isIdentifierContinue source := by
  exact scannerLoopOracle caller cell source Artifact.identifierContinueFunction.id
    isIdentifierContinue backing (identifierContinuePredicateContract caller cell source)

def whitespaceScannerOracle
    (caller : State) (cell : CellId) (source : List Byte)
    (backing : SourceByteBacking caller cell source) :
    PrefixLoopOracle Artifact.lexerProgram
      (Artifact.scannerCondition Artifact.whitespaceFunction.id)
      Artifact.scannerLoopBody isWhitespace source := by
  exact scannerLoopOracle caller cell source Artifact.whitespaceFunction.id
    isWhitespace backing (whitespacePredicateContract caller cell source)

end Lanius.Compiler.Lexer
