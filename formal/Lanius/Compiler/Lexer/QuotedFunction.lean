import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.QuotedCall
import Lanius.Compiler.Lexer.QuotedOracle
import Lanius.Compiler.Lexer.QuotedSetup
import Lanius.Compiler.Lexer.ScanEndFunctions
import Lanius.Semantics.Call

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

theorem scanQuotedEnd_pure
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (delimiterByte : Byte) (backing : SourceByteBacking caller cell source)
    (formed : caller.CellsWellFormed) (startInSource : start < source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.scanQuotedEndFunction.id
        (quotedArgumentExpressions cell source start (Int.ofNat delimiterByte.val)))
      (scanEndValue (scanQuotedEnd source start delimiterByte)) := by
  let delimiter := Int.ofNat delimiterByte.val
  let expected := scanQuotedEnd source start delimiterByte
  let callee := quotedCallee caller cell source start delimiter
  let cursorState := callee.bindLocal 4 (.signed .i32 (Int.ofNat (start + 1)))
  let current := cursorState.bindLocal 5 (.boolean false)
  let initializer : Expr := .binary .add (.local 2) (.value (.signed .i32 1))
  let loop : Stmt := .whileLoop quotedCondition Artifact.scanQuotedLoopBody
  let tail : Stmt := .sequence
    (.returnValue (some (.call Artifact.failedScanFunction.id [.local 1]))) .skip
  let sequence : Stmt := .sequence loop tail
  let innerBody : Stmt := .letLocal 5 (.scalar .bool) (.value (.boolean false)) sequence
  let body : Stmt := .letLocal 4 (.scalar (.signed .i32)) initializer innerBody
  have entry := quotedLoopEntry_invariant caller cell source start delimiter formed backing
    startInSource sourceLengthI32
  have initial : quotedLoopInvariant caller cell source delimiterByte expected current := by
    refine ⟨start + 1, false, callee.nextCell, cursorState.nextCell, ?_, rfl⟩
    have cursorNextCell : cursorState.nextCell = callee.nextCell + 1 := by
      simp [cursorState, State.bindLocal, State.bindCell]
    simpa [delimiter, callee, current, cursorState, quotedLoopEntry,
      State.bindLocal, State.bindCell, cursorNextCell] using entry
  obtain ⟨loopFuel, completion, loopAfter, loopRun, loopDone⟩ :=
    quotedLoop_execute caller cell source delimiterByte expected current initial
  have initializerRun : StableExpr 2 Artifact.lexerProgram callee initializer
      (.signed .i32 (Int.ofNat (start + 1))) callee := fun fuel enough => by
    simpa [initializer] using evalScannerInitializer fuel Artifact.lexerProgram callee start
      (quotedCallee_localFacts caller cell source start delimiter formed).2.2.1 (by omega) enough
  have boolRun : StableExpr 1 Artifact.lexerProgram cursorState
      (.value (.boolean false)) (.boolean false) cursorState :=
    fun fuel enough => by cases fuel <;> simp_all [evalExpr.eq_def]
  have wrapBody : ∀ {seqFuel : Nat} {value : Value} {after : State},
      StableStmt seqFuel Artifact.lexerProgram current sequence (.returned (some value)) after →
      CallerFrame caller after →
      ∃ fuel completed, StableStmt fuel Artifact.lexerProgram callee body
        (.returned (some value)) completed ∧ CallerFrame caller completed := by
    intro seqFuel value after sequenceRun frame
    let innerAfter := restoreLocals cursorState after
    let completed := restoreLocals callee innerAfter
    have innerRun : StableStmt (max 1 seqFuel + 1) Artifact.lexerProgram cursorState innerBody
        (.returned (some value)) innerAfter := by
      simpa [innerBody, innerAfter, current] using
        StableStmt.letLocal Artifact.lexerProgram cursorState 5 (.scalar .bool)
          (.value (.boolean false)) sequence (.boolean false) cursorState after
          (.returned (some value)) boolRun (by simpa [current] using sequenceRun)
    refine ⟨max 2 (max 1 seqFuel + 1) + 1, completed, ?_, ?_⟩
    · simpa [body, completed, innerAfter] using
        StableStmt.letLocal Artifact.lexerProgram callee 4 (.scalar (.signed .i32))
          initializer innerBody (.signed .i32 (Int.ofNat (start + 1))) callee innerAfter
          (.returned (some value)) initializerRun innerRun
    · exact ⟨frame.callerFormed, frame.cells.restoreLocals, frame.heap, frame.world, frame.views⟩
  have bodyContract : ∃ fuel completed, StableStmt fuel Artifact.lexerProgram callee body
      (.returned (some (scanEndValue expected))) completed ∧ CallerFrame caller completed := by
    cases result : scanQuotedEnd source start delimiterByte with
    | success offset =>
        have done : completion = .returned (some (scanEndValue (.success offset))) ∧
            CallerFrame caller loopAfter := by
          cases completion <;> simp_all [quotedLoopDone, expected, result] <;>
            try { cases ‹Option Value› <;> simp_all [quotedLoopDone, expected, result] }
        rcases done with ⟨rfl, frame⟩
        have sequenceRun : StableStmt (loopFuel + 1) Artifact.lexerProgram current sequence
            (.returned (some (scanEndValue (.success offset)))) loopAfter := by
          simpa [sequence, loop] using
            StableStmt.sequence_completed (by simpa [loop] using loopRun) (by simp)
        simpa [expected, result] using wrapBody sequenceRun frame
    | failure offset =>
        cases completion with
        | returned value =>
            cases value with
            | none => simp_all [quotedLoopDone, expected, result]
            | some value =>
                have done : value = scanEndValue (.failure offset) ∧
                    CallerFrame caller loopAfter := by
                  simpa [quotedLoopDone, expected, result] using loopDone
                rcases done with ⟨valueEq, frame⟩
                have sequenceRun : StableStmt (loopFuel + 1) Artifact.lexerProgram current sequence
                    (.returned (some value)) loopAfter := by
                  simpa [sequence, loop] using
                    StableStmt.sequence_completed (by simpa [loop] using loopRun) (by simp)
                simpa [expected, result, valueEq] using wrapBody sequenceRun frame
        | next =>
            have done : expected = .failure source.length ∧
                quotedLoopInvariant caller cell source delimiterByte expected loopAfter := by
              simpa [quotedLoopDone, expected, result] using loopDone
            have offsetEq : offset = source.length := by
              simpa [expected, result] using done.1
            rcases done.2 with ⟨_, _, _, _, finalInvariant, _⟩
            have tailArgument : ThresholdPure 1 Artifact.lexerProgram loopAfter (.local 1)
                (.signed .i32 (Int.ofNat source.length)) loopAfter :=
              ThresholdPure.localValue finalInvariant.frame.currentFormed 1
                (.signed .i32 (Int.ofNat source.length)) finalInvariant.lengthLocal
            obtain ⟨callFuel, callAfter, callRun⟩ := failedScan_of_argument loopAfter
              (.local 1) source.length tailArgument
            have tailRun : StableStmt (callFuel + 2) Artifact.lexerProgram loopAfter tail
                (.returned (some (failedScanValue source.length))) callAfter := by
              simpa [tail, Artifact.failedScanFunction] using
                StableStmt.returnValueSequence Artifact.lexerProgram loopAfter
                  (.call Artifact.failedScanFunction.id [.local 1])
                  (failedScanValue source.length) callRun.run
            have sequenceRun : StableStmt (max loopFuel (callFuel + 2) + 1)
                Artifact.lexerProgram current sequence
                (.returned (some (failedScanValue source.length))) callAfter :=
              StableStmt.sequence_next (by simpa [sequence] using loopRun) tailRun
            simpa [expected, result, offsetEq, failedScanValue, scanEndValue] using wrapBody sequenceRun
              (finalInvariant.frame.transPure callRun.frame)
        | breakLoop | continueLoop => simp_all [quotedLoopDone, expected, result]
  obtain ⟨bodyFuel, completed, bodyRun, bodyFrame⟩ := bodyContract
  have arguments : ThresholdPureList 5 Artifact.lexerProgram caller
      (quotedArgumentExpressions cell source start delimiter)
      (quotedArgumentValues cell source start delimiter) caller := ⟨by
    intro fuel enough
    simpa [show fuel - 5 + 4 + 1 = fuel by omega] using
      evalQuotedArguments (fuel - 5) Artifact.lexerProgram caller cell source start delimiter,
    PureFrame.refl formed⟩
  have calleeShape : callee = ({ caller with locals := [] }).bindLocals
      (quotedBindings cell source start delimiter) := by
    simp [callee, quotedCallee, quotedBindings, quotedArgumentValues, scannerCallee,
      scannerBindings, State.bindLocals, State.bindLocal, State.bindCell]
  have contract := thresholdInternalCallUnderCaller Artifact.lexerProgram caller
    Artifact.scanQuotedEndFunction (quotedArgumentExpressions cell source start delimiter) body
    (quotedArgumentValues cell source start delimiter)
    (quotedBindings cell source start delimiter) caller callee completed
    (scanEndValue expected) Artifact.scanQuotedEndFunction_found (by rfl) arguments
    (scanQuotedEndFunction_bindParameters cell source start delimiter) calleeShape bodyRun bodyFrame
  simpa [expected, delimiter] using contract.erase

end Lanius.Compiler.Lexer
