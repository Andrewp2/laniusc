import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.PrefixScanner
import Lanius.Compiler.Lexer.ScannerCall
import Lanius.Compiler.Lexer.ScannerInvariant
import Lanius.Semantics.Branch
import Lanius.Semantics.Call

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

private def prefixScannerI32Type : Ty := .scalar (.signed .i32)

/-! The common three-argument scanner shape.  Keeping the shape here makes the
    outer-call theorem independent of whether the loop condition is a
    predicate call or an inlined byte comparison. -/
def prefixScannerBody
    (initializer condition : Expr) (loopBody : Stmt)
    (finalCursorLocal : VarId) : Stmt :=
  .letLocal finalCursorLocal prefixScannerI32Type
    initializer
    (.sequence (.whileLoop condition loopBody)
      (.sequence (.returnValue (some (.local finalCursorLocal))) .skip))

theorem acceptedPrefixCursor_scanEnd_width
    (accept : Byte → Bool) (source : List Byte) (start width : Nat) :
    acceptedPrefixCursor accept source (start + width) =
      scanEnd accept source start width := rfl

/-! Compose setup, the total loop theorem, the return tail, and the external
    three-argument call.  The caller supplies only the exact body/initializer
    contracts and lookup facts for its concrete artifact function. -/
theorem prefixScannerFunction_call
    (program : Program) (caller : State) (cell : CellId) (source : List Byte)
    (start initialWidth : Nat) (condition : Expr) (loopBody : Stmt)
    (accept : Byte → Bool) (function : Function) (finalCursorLocal : VarId)
    (oracle : PrefixLoopOracle program condition loopBody accept source)
    (current : State)
    (initialInvariant : oracle.Inv (start + initialWidth) current)
    (currentShape : current = (scannerCallee caller cell source start).bindLocal
      finalCursorLocal (.signed .i32 (Int.ofNat (start + initialWidth))))
    (frameInvariant : ∀ {cursor state}, oracle.Inv cursor state →
      CallerFrame caller state)
    (finalLocal : ∀ {state}, oracle.Inv (scanEnd accept source start initialWidth) state →
      state.local? finalCursorLocal =
        some (.signed .i32 (Int.ofNat (scanEnd accept source start initialWidth))))
    (initializer : Expr) (initializerFuel : Nat)
    (initializerRun : ∀ fuel, initializerFuel ≤ fuel →
      evalExpr fuel program (scannerCallee caller cell source start) initializer =
        .done (.signed .i32 (Int.ofNat (start + initialWidth)))
          (scannerCallee caller cell source start))
    (functionFound : program.function? function.id = some function)
    (bodyFound : function.body = some
      (prefixScannerBody initializer condition loopBody finalCursorLocal))
    (parametersBind : bindParameters function.parameters
      (scannerArgumentValues cell source start) = some (scannerBindings cell source start)) :
    ∃ threshold after, ThresholdPure threshold program caller
      (.call function.id (scannerArgumentExpressions cell source start))
      (.signed .i32 (Int.ofNat (scanEnd accept source start initialWidth))) after := by
  let callee := scannerCallee caller cell source start
  let finalCursor := scanEnd accept source start initialWidth
  obtain ⟨loopThreshold, loopAfter, loopRun, loopInvariant, loopFrame⟩ :=
    executePrefixLoop_underCaller caller oracle (start + initialWidth) current
      initialInvariant frameInvariant
  have finalInvariant : oracle.Inv finalCursor loopAfter := by
    simpa only [finalCursor, acceptedPrefixCursor_scanEnd_width] using loopInvariant
  have tailRun := StableStmt.returnValueSequence program loopAfter (.local finalCursorLocal)
      (.signed .i32 finalCursor)
      (ThresholdPure.localValue loopFrame.currentFormed finalCursorLocal
        (.signed .i32 finalCursor) (finalLocal finalInvariant)).run
  have sequenceRun := StableStmt.sequence_next loopRun tailRun
  have bodyRun := StableStmt.letLocal program callee finalCursorLocal
      prefixScannerI32Type initializer
      (.sequence (.whileLoop condition loopBody)
        (.sequence (.returnValue (some (.local finalCursorLocal))) .skip))
      (.signed .i32 (Int.ofNat (start + initialWidth))) callee loopAfter
      (.returned (some (.signed .i32 finalCursor))) (by simpa [StableExpr, callee] using initializerRun)
      (by simpa [callee, currentShape] using sequenceRun)
  have bodyFrame : CallerFrame caller (restoreLocals callee loopAfter) :=
    ⟨loopFrame.callerFormed, loopFrame.cells.restoreLocals, loopFrame.heap, loopFrame.world, loopFrame.views⟩
  have arguments : ThresholdPureList 4 program caller (scannerArgumentExpressions cell source start)
      (scannerArgumentValues cell source start) caller := by
    refine ⟨?_, PureFrame.refl (frameInvariant initialInvariant).callerFormed⟩
    intro fuel enough
    simpa [show fuel - 4 + 3 + 1 = fuel by omega] using
      evalScannerArguments (fuel - 4) program caller cell source start
  refine ⟨max 4 (max initializerFuel (max loopThreshold 3 + 1) + 1) + 1,
    restoreLocals caller (restoreLocals callee loopAfter), ?_⟩
  simpa [finalCursor] using
    (thresholdInternalCallUnderCaller program caller function
      (scannerArgumentExpressions cell source start)
      (prefixScannerBody initializer condition loopBody finalCursorLocal)
      (scannerArgumentValues cell source start) (scannerBindings cell source start)
      caller callee (restoreLocals callee loopAfter)
      (.signed .i32 (Int.ofNat finalCursor)) functionFound bodyFound arguments
      parametersBind (by rfl) bodyRun bodyFrame)

end Lanius.Compiler.Lexer
