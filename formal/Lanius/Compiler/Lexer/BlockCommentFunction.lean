import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.ArtifactComments
import Lanius.Compiler.Lexer.BlockCommentOracle
import Lanius.Compiler.Lexer.CommentCall
import Lanius.Compiler.Lexer.ScannerCall
import Lanius.Semantics.Call

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

private theorem scanOffset
    (scan : BlockBodyScan input offset result) :
    match result with
    | .success _ => True
    | .failure error => error = offset + input.length := by
  induction scan <;> simp_all [List.length_cons] <;>
    try { cases ‹ScanEnd› <;> simp_all [List.length_cons] <;> omega }

private theorem scanFailureAt
    (input : List Byte) (offset error : Nat)
    (failed : scanBlockBody input offset = .failure error) :
    error = offset + input.length := by
  cases h : scanBlockBody input offset with
  | success value => simp_all
  | failure value =>
      have valueEq : value = error := ScanEnd.failure.inj (h.symm.trans failed)
      subst error
      have scan : BlockBodyScan input offset (.failure value) := by
        simpa [h] using scanBlockBody_spec input offset
      exact scanOffset scan

theorem scanBlockCommentEnd_pure
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (backing : SourceByteBacking caller cell source)
    (formed : caller.CellsWellFormed)
    (startWithinSource : start + 2 ≤ source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.scanBlockCommentEndFunction.id
        (scannerArgumentExpressions cell source start))
      (scanEndValue (scanBlockCommentEnd source start)) := by
  let expected := scanBlockCommentEnd source start
  change PurelyEvaluates Artifact.lexerProgram caller
    (.call Artifact.scanBlockCommentEndFunction.id
      (scannerArgumentExpressions cell source start)) (scanEndValue expected)
  let callee := scannerCallee caller cell source start
  let current := scannerCalleeWithCursorWidth caller cell source start 2
  let initializer : Expr := .binary .add (.local 2) (.value (.signed .i32 2))
  let loopCondition : Expr :=
    .binary .lessEqual (.local 3)
      (.binary .subtract (.local 1) (.value (.signed .i32 1)))
  let loop : Stmt := .whileLoop loopCondition Artifact.blockLoopBody
  let tail : Stmt := .sequence (.returnValue (some (.call Artifact.failedScanFunction.id [.local 1]))) .skip
  let sequence : Stmt := .sequence loop tail
  let body : Stmt := .letLocal 3 (.scalar (.signed .i32)) initializer sequence
  have scannerInvariant := scannerCalleeWithCursorWidth_invariant caller cell source start 2 formed backing startWithinSource sourceLengthI32
  have initial : blockCommentInvariant caller cell source expected current := ⟨start + 2, _, scannerInvariant, rfl⟩
  obtain ⟨loopFuel, completion, loopAfter, loopRun, loopDone⟩ := blockCommentLoop_execute caller cell source expected backing current initial
  have arguments : ThresholdPureList 4 Artifact.lexerProgram caller (scannerArgumentExpressions cell source start)
      (scannerArgumentValues cell source start) caller := ⟨by
    intro fuel enough
    simpa [show fuel - 4 + 3 + 1 = fuel by omega] using
      evalScannerArguments (fuel - 4) Artifact.lexerProgram caller cell source start,
    PureFrame.refl scannerInvariant.frame.callerFormed⟩
  have initializerRun : StableExpr 2 Artifact.lexerProgram callee initializer (.signed .i32 (Int.ofNat (start + 2))) callee := fun fuel enough => by
    simpa [initializer] using evalCommentInitializer_of_source fuel Artifact.lexerProgram callee source start
      (scannerCallee_startLocal caller cell source start formed) sourceLengthI32 startWithinSource enough
  have wrapBody : ∀ (value : Value) (seqFuel : Nat) (after : State), StableStmt seqFuel Artifact.lexerProgram current sequence
      (.returned (some value)) after → CallerFrame caller after → ∃ bodyFuel completed, StableStmt bodyFuel Artifact.lexerProgram callee body
        (.returned (some value)) completed ∧ CallerFrame caller completed := by
    intro value seqFuel after sequenceRun frame
    refine ⟨max 2 seqFuel + 1, restoreLocals callee after, ?_, ?_⟩
    · simpa [body, current, callee, scannerCalleeWithCursorWidth] using
        StableStmt.letLocal Artifact.lexerProgram callee 3 (.scalar (.signed .i32)) initializer sequence
          (.signed .i32 (Int.ofNat (start + 2))) callee after (.returned (some value)) initializerRun sequenceRun
    · exact ⟨frame.callerFormed, frame.cells.restoreLocals, frame.heap, frame.world, frame.views⟩
  have bodyContract : ∃ bodyFuel completed, StableStmt bodyFuel Artifact.lexerProgram callee body (.returned (some (scanEndValue expected))) completed ∧ CallerFrame caller completed := by
    cases h : scanBlockCommentEnd source start with
    | success offset =>
        have done : completion = .returned (some (scanEndValue (.success offset))) ∧ CallerFrame caller loopAfter := by
          cases completion <;> simp_all [blockCommentDone, expected] <;> try { cases ‹Option Value› <;> simp_all [blockCommentDone, expected] }
        rcases done with ⟨completionEq, loopFrame⟩
        have sequenceRun := StableStmt.sequence_completed (second := tail) (by simpa [loop, completionEq] using loopRun) (by simp)
        simpa [expected, h] using wrapBody _ (loopFuel + 1) loopAfter sequenceRun loopFrame
    | failure offset =>
        have done : completion = .next ∧ ∃ cursor cursorCellId, ScannerInvariant caller loopAfter cell source cursor cursorCellId ∧
            scanBlockBody (source.drop cursor) cursor = .failure offset := by
          cases completion <;> simp_all [blockCommentDone, expected] <;> try { cases ‹Option Value› <;> simp_all [blockCommentDone, expected] }
        rcases done with ⟨rfl, ⟨cursor, cursorCellId, finalInvariant, finalModel⟩⟩
        have result := scanFailureAt (source.drop cursor) cursor offset finalModel
        simp only [List.length_drop] at result
        have cursorBound := finalInvariant.cursorInSource
        have offsetEq : offset = source.length := by omega
        have argument := ThresholdPure.localValue (program := Artifact.lexerProgram) finalInvariant.frame.currentFormed 1 (.signed .i32 (Int.ofNat source.length)) finalInvariant.lengthLocal
        obtain ⟨callFuel, callAfter, callRun⟩ := failedScan_of_argument loopAfter (.local 1) source.length argument
        have tailRun := StableStmt.returnValueSequence Artifact.lexerProgram loopAfter
          (.call Artifact.failedScanFunction.id [.local 1])
          (failedScanValue source.length) callRun.run
        have sequenceRun := StableStmt.sequence_next (by simpa [loop] using loopRun) tailRun
        simpa [offsetEq, expected, h, failedScanValue, scanEndValue] using wrapBody _ (max loopFuel (callFuel + 2) + 1)
          callAfter sequenceRun (finalInvariant.frame.transPure callRun.frame)
  obtain ⟨bodyFuel, completed, bodyRun, bodyFrame⟩ := bodyContract
  have calleeShape : callee = ({ caller with locals := [] }).bindLocals (scannerBindings cell source start) := rfl
  exact (thresholdInternalCallUnderCaller Artifact.lexerProgram caller Artifact.scanBlockCommentEndFunction
    (scannerArgumentExpressions cell source start) body (scannerArgumentValues cell source start)
    (scannerBindings cell source start) caller callee completed (scanEndValue expected)
    Artifact.scanBlockCommentEndFunction_found (by rfl) arguments
    (scanBlockCommentEndFunction_bindParameters cell source start) calleeShape bodyRun bodyFrame).erase

end Lanius.Compiler.Lexer
