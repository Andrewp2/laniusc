import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.QuotedFunction
import Lanius.Compiler.Lexer.QuotedCall
import Lanius.Semantics.Rules

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics Lanius.Compiler.Lexer.Artifact

private theorem quotedWrapper_pure (function : Function) (delimiterByte : Byte) (delimiter : Int)
    (delimiterEq : delimiter = Int.ofNat delimiterByte.val)
    (functionFound : Artifact.lexerProgram.function? function.id = some function)
    (bodyFound : function.body = some (.sequence (.returnValue (some
      (.call Artifact.scanQuotedEndFunction.id [.local 0, .local 1, .local 2,
        .value (.signed .i32 delimiter)]))) .skip))
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (parametersBind : bindParameters function.parameters (scannerArgumentValues cell source start) =
      some (scannerBindings cell source start)) (backing : SourceByteBacking caller cell source)
    (formed : caller.CellsWellFormed) (startInSource : start < source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    PurelyEvaluates Artifact.lexerProgram caller
      (.call function.id (scannerArgumentExpressions cell source start))
      (scanEndValue (scanQuotedEnd source start delimiterByte)) := by
  let callee := scannerCallee caller cell source start
  let localCall : Expr := .call Artifact.scanQuotedEndFunction.id
    [.local 0, .local 1, .local 2, .value (.signed .i32 delimiter)]
  let body : Stmt := .sequence (.returnValue (some localCall)) .skip
  have calleeFrame := scannerCallee_frame caller cell source start formed; have calleeFormed := calleeFrame.currentFormed
  have facts := scannerCallee_localFacts caller cell source start formed; have startFact := scannerCallee_startLocal caller cell source start formed
  obtain ⟨innerAfter, innerPure⟩ := scanQuotedEnd_pure callee cell source start delimiterByte
    (backing.afterCallerFrame calleeFrame) calleeFormed startInSource sourceLengthI32
  rcases innerPure with ⟨⟨innerFuel, innerRun⟩, _, innerFormed, innerLocals, innerHeap, innerWorld, innerViews⟩
  have innerFuelEnough : 5 ≤ innerFuel := by
    by_cases enough : 5 ≤ innerFuel
    · exact enough
    · have cases : innerFuel = 0 ∨ innerFuel = 1 ∨ innerFuel = 2 ∨ innerFuel = 3 ∨ innerFuel = 4 := by omega
      rcases cases with rfl | rfl | rfl | rfl | rfl <;> cases innerRun
  obtain ⟨fuel, fuelEq⟩ := Nat.exists_eq_add_of_le innerFuelEnough; have fuelEq' : innerFuel = fuel + 5 := by omega
  rw [fuelEq'] at innerRun
  have localArgsEq : evalExprs (fuel + 4) Artifact.lexerProgram callee [.local 0, .local 1, .local 2, .value (.signed .i32 delimiter)] = evalExprs (fuel + 4) Artifact.lexerProgram callee (quotedArgumentExpressions cell source start delimiter) := by
    change evalExprs (fuel + 4) Artifact.lexerProgram callee [.local 0, .local 1, .local 2, .value (.signed .i32 delimiter)] = evalExprs (fuel + 4) Artifact.lexerProgram callee [.value (sourceSliceValue cell source), .value (.signed .i32 (Int.ofNat source.length)), .value (.signed .i32 (Int.ofNat start)), .value (.signed .i32 delimiter)]
    repeat (rw [evalExprs.eq_def] <;> simp only [evalExpr_local_of_local? (fuel + 2) Artifact.lexerProgram callee 0 (sourceSliceValue cell source) facts.1, evalExpr_local_of_local? (fuel + 1) Artifact.lexerProgram callee 1 (.signed .i32 (Int.ofNat source.length)) facts.2, evalExpr_local_of_local? fuel Artifact.lexerProgram callee 2 (.signed .i32 (Int.ofNat start)) startFact, evalExpr_value])
  have localArgsEq' := localArgsEq; rw [delimiterEq] at localArgsEq'
  have localRun : evalExpr (fuel + 5) Artifact.lexerProgram callee localCall =
      .done (scanEndValue (scanQuotedEnd source start delimiterByte)) innerAfter := by
    dsimp only [localCall]; rw [delimiterEq]; simp only [evalExpr.eq_def] at innerRun ⊢
    rw [localArgsEq']; exact innerRun
  have bodyRun : execStmt (fuel + 7) Artifact.lexerProgram callee body =
      .done (.returned (some (scanEndValue (scanQuotedEnd source start delimiterByte)))) innerAfter := by
    simpa [body, localCall, show fuel + 5 + 1 + 1 = fuel + 7 by omega] using execStmt_sequence_completed (fuel := fuel + 6)
      Artifact.lexerProgram callee (.returnValue (some localCall)) .skip (.returned (some (scanEndValue (scanQuotedEnd source start delimiterByte)))) innerAfter
      (execStmt_return (fuel + 5) Artifact.lexerProgram callee localCall (scanEndValue (scanQuotedEnd source start delimiterByte)) innerAfter localRun) (by simp)
  have argumentsRun : evalExprs (fuel + 7) Artifact.lexerProgram caller (scannerArgumentExpressions cell source start) = .done (scannerArgumentValues cell source start) caller := by
    simpa [show (fuel + 3).succ.succ.succ.succ = fuel + 7 by omega] using
      evalScannerArguments (fuel + 3) Artifact.lexerProgram caller cell source start
  have callRun := evalExpr_call_internal (fuel := fuel + 7) (program := Artifact.lexerProgram) (caller := caller)
    (functionId := function.id) (arguments := scannerArgumentExpressions cell source start) (function := function)
    (body := body) (values := scannerArgumentValues cell source start) (bindings := scannerBindings cell source start)
    (afterArguments := caller) (completed := innerAfter) (value := scanEndValue (scanQuotedEnd source start delimiterByte))
    functionFound bodyFound argumentsRun parametersBind (by simpa [callee, scannerCallee] using bodyRun)
  refine ⟨restoreLocals caller innerAfter, ?_⟩
  refine ⟨⟨fuel + 8, by simpa [show fuel + 7 + 1 = fuel + 8 by omega] using callRun⟩, formed, innerFormed, rfl,
    innerHeap.trans calleeFrame.heap, innerWorld.trans calleeFrame.world, innerViews.trans calleeFrame.views⟩

theorem scanStringEnd_pure (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (backing : SourceByteBacking caller cell source) (formed : caller.CellsWellFormed)
    (startInSource : start < source.length) (sourceLengthI32 : source.length < 2 ^ 31) :
    PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.scanStringEndFunction.id (scannerArgumentExpressions cell source start))
      (scanEndValue (scanQuotedEnd source start 34)) := by
  exact quotedWrapper_pure Artifact.scanStringEndFunction 34 34 rfl (by rfl) (by rfl)
    caller cell source start (by rfl) backing formed startInSource sourceLengthI32

theorem scanCharacterEnd_pure (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (backing : SourceByteBacking caller cell source) (formed : caller.CellsWellFormed)
    (startInSource : start < source.length) (sourceLengthI32 : source.length < 2 ^ 31) :
    PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.scanCharacterEndFunction.id (scannerArgumentExpressions cell source start))
      (scanEndValue (scanQuotedEnd source start 39)) := by
  exact quotedWrapper_pure Artifact.scanCharacterEndFunction 39 39 rfl (by rfl) (by rfl)
    caller cell source start (by rfl) backing formed startInSource sourceLengthI32

end Lanius.Compiler.Lexer
