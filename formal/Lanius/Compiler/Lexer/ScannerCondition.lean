import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.ArtifactScanners
import Lanius.Compiler.Lexer.PredicateStable
import Lanius.Semantics.Branch
import Lanius.Semantics.Call
import Lanius.Semantics.Loop
import Lanius.Semantics.ReadOnlySlice
import Lanius.Semantics.Scalar

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

theorem i32LocalsLessEqualSubOne
    (program : Program) (state : State)
    (leftId rightId : VarId) (left right : Nat)
    (leftFound : state.local? leftId = some (.signed .i32 (Int.ofNat left)))
    (rightFound : state.local? rightId = some (.signed .i32 (Int.ofNat right)))
    (rightBound : right < 2 ^ 31)
    (formed : state.CellsWellFormed) :
    ThresholdPure 3 program state
      (.binary .lessEqual (.local leftId)
        (.binary .subtract (.local rightId) (.value (.signed .i32 1))))
      (.boolean (decide (left < right))) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [show fuel = (fuel - 3).succ.succ.succ by omega]
  have leftRun := evalExpr_local_of_local? ((fuel - 3).succ.succ) program state leftId
    (.signed .i32 (Int.ofNat left)) leftFound
  have rightLocalRun := evalExpr_local_of_local? ((fuel - 3).succ) program state rightId
    (.signed .i32 (Int.ofNat right)) rightFound
  have rightValueRun := evalExpr_value ((fuel - 3).succ) program state
    (.signed .i32 1)
  have rightRun : evalExpr (fuel - 3).succ.succ program state
      (.binary .subtract (.local rightId) (.value (.signed .i32 1))) =
      .done (.signed .i32 (Int.ofNat right - 1)) state := by
    apply evalExpr_binary_done (fuel := (fuel - 3).succ) program state .subtract
      (.local rightId) (.value (.signed .i32 1))
      (.signed .i32 (Int.ofNat right)) (.signed .i32 1)
      (.signed .i32 (Int.ofNat right - 1)) state state
      rightLocalRun rightValueRun (by simp)
    simp only [evalBinaryValue, evalSignedBinary]
    cases right with
    | zero => simp [wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
    | succ right =>
        simp only [beq_self_eq_true, if_true]
        rw [show Int.ofNat (Nat.succ right) - 1 = Int.ofNat right by simp]
        exact congrArg (fun value : Int =>
          (Except.ok (Value.signed .i32 value) : Except Trap Value))
          (wrapSigned_i32_nat_lt program.target right (by omega))
  apply evalExpr_binary_done (fuel := (fuel - 3).succ.succ) program state .lessEqual
    (.local leftId)
    (.binary .subtract (.local rightId) (.value (.signed .i32 1)))
    (.signed .i32 (Int.ofNat left)) (.signed .i32 (Int.ofNat right - 1))
    (.boolean (decide (left < right))) state state leftRun rightRun (by simp)
  simp only [evalBinaryValue, evalSignedBinary, signedComparison]
  simp
  omega

def scannerCondition (sourceId limitId cursorId predicateId : FunctionId) : Expr :=
  .binary .logicalAnd
    (.binary .lessEqual (.local cursorId)
      (.binary .subtract (.local limitId) (.value (.signed .i32 1))))
    (.call predicateId [.index (.local sourceId) (.local cursorId)])

theorem scannerCondition_outOfBounds (program : Program) (state : State)
    (sourceId limitId cursorId predicateId : FunctionId) (cursor limit : Nat)
    (limitFound : state.local? limitId = some (.signed .i32 (Int.ofNat limit)))
    (cursorFound : state.local? cursorId = some (.signed .i32 (Int.ofNat cursor)))
    (formed : state.CellsWellFormed) (outOfBounds : ¬ cursor < limit)
    (limitBound : limit < 2 ^ 31) :
    ThresholdPure 4 program state
      (scannerCondition sourceId limitId cursorId predicateId)
      (.boolean false) state := by
  have less := i32LocalsLessEqualSubOne program state cursorId limitId cursor limit
    cursorFound limitFound limitBound formed
  refine ⟨(fun fuel enough => by
    simpa [scannerCondition, show fuel - 1 + 1 = fuel by omega] using
      evalExpr_logicalAnd_false (fuel - 1) program state
        (.binary .lessEqual (.local cursorId)
          (.binary .subtract (.local limitId) (.value (.signed .i32 1))))
        (.call predicateId [.index (.local sourceId) (.local cursorId)]) state
        (by simpa [show decide (cursor < limit) = false by simp [outOfBounds]] using
          less.run (fuel - 1) (by omega))), PureFrame.refl formed⟩

theorem scannerCondition_inBounds (program : Program) (state : State)
    (sourceId limitId cursorId predicateId : FunctionId) (cursor limit : Nat)
    (limitFound : state.local? limitId = some (.signed .i32 (Int.ofNat limit)))
    (cursorFound : state.local? cursorId = some (.signed .i32 (Int.ofNat cursor)))
    (predicateThreshold : Nat) (predicateResult : Bool) (predicateAfter : State)
    (predicateCall : ThresholdPure predicateThreshold program state
      (.call predicateId
        [.index (.local sourceId) (.local cursorId)])
      (.boolean predicateResult) predicateAfter)
    (formed : state.CellsWellFormed) (inBounds : cursor < limit)
    (limitBound : limit < 2 ^ 31) :
    ThresholdPure (max 3 predicateThreshold + 1) program state
      (scannerCondition sourceId limitId cursorId predicateId)
      (.boolean predicateResult) predicateAfter := by
  have less := i32LocalsLessEqualSubOne program state cursorId limitId cursor limit
    cursorFound limitFound limitBound formed
  refine ⟨(fun fuel enough => by
    simpa [scannerCondition, show fuel - 1 + 1 = fuel by omega] using
      evalExpr_logicalAnd_true (fuel - 1) program state
        (.binary .lessEqual (.local cursorId)
          (.binary .subtract (.local limitId) (.value (.signed .i32 1))))
        (.call predicateId [.index (.local sourceId) (.local cursorId)])
        (.boolean predicateResult) state predicateAfter
        (by simpa [show decide (cursor < limit) = true by simp [inBounds]] using
          less.run (fuel - 1) (by omega))
        (predicateCall.run (fuel - 1) (by omega))), less.frame.trans predicateCall.frame⟩

theorem thresholdPureArgumentCall
    (program : Program) (caller : State)
    (functionId parameter : Nat) (body argument : Expr) (input : Int)
    (argumentThreshold bodyFuel : Nat)
    (argumentStable : ∀ fuel, argumentThreshold ≤ fuel →
      evalExpr fuel program caller argument =
        .done (.signed .i32 input) caller)
    (found : program.function? functionId =
      some (oneParameterBooleanFunction functionId parameter body))
    (formed : caller.CellsWellFormed)
    {result : Bool} {bodyAfter : State}
    (bodyContract : ThresholdPure bodyFuel program
      (({ caller with locals := [] }).bindLocal parameter
        (.signed .i32 input))
      body (.boolean result) bodyAfter) :
    ThresholdPure (max (argumentThreshold + 2) (bodyFuel + 4)) program caller
      (.call functionId [argument]) (.boolean result)
      (restoreLocals caller bodyAfter) := by
  let value : Value := .signed .i32 input
  let callee : State := ({ caller with locals := [] }).bindLocal parameter value
  have bodyRun := StableStmt.returnValueSequence program callee body
    (.boolean result) bodyContract.run
  have cleared : FreshCellFrame caller callee := by
    simp [callee, value, FreshCellFrame, State.bindLocal, State.bindCell]
  have call := thresholdInternalCall program caller
    (oneParameterBooleanFunction functionId parameter body) [argument]
    (.sequence (.returnValue (some body)) .skip) [value] [(parameter, value)]
    caller callee bodyAfter (.boolean result) found rfl
    (ThresholdPureList.singleton ⟨argumentStable, PureFrame.refl formed⟩)
    (by simp [oneParameterBooleanFunction, bindParameters])
    (by simp [callee, State.bindLocals]) bodyRun
    { callerFormed := formed, cells := cleared, heap := rfl, world := rfl, views := rfl }
    bodyContract.frame
  exact call.weaken (by omega)

theorem identifierContinueConditionCall
    (state : State) (sourceId cursorId : VarId) (cell : CellId) (values : List Int)
    (cursor : Nat) (source : SourceSlice state sourceId cell values)
    (cursorFound : state.local? cursorId =
      some (.signed .i32 (Int.ofNat cursor)))
    (formed : state.CellsWellFormed) (inBounds : cursor < values.length) :
    ∃ after, ThresholdPure 13 Artifact.lexerProgram state
      (.call Artifact.identifierContinueFunction.id
        [.index (.local sourceId) (.local cursorId)])
      (.boolean (Artifact.identifierStartPredicate.accepts
        (values.get ⟨cursor, inBounds⟩) ||
        Artifact.decimalPredicate.accepts (values.get ⟨cursor, inBounds⟩))) after := by
  let input := values.get ⟨cursor, inBounds⟩
  obtain ⟨bodyAfter, bodyContract⟩ := thresholdUnaryPredicateOr Artifact.lexerProgram state 0 0 2
    Artifact.identifierStartPredicate Artifact.decimalPredicate input
    (by simpa [Artifact.identifierStartFunction, unaryI32PredicateFunction] using
      Artifact.identifierStartFunction_found)
    (by simpa [Artifact.decimalFunction, unaryI32PredicateFunction] using
      Artifact.decimalFunction_found)
    formed
  have argumentStable := evalExpr_source_slice_index_of_locals Artifact.lexerProgram
    state sourceId cursorId cell values cursor source cursorFound inBounds
  have call := thresholdPureArgumentCall Artifact.lexerProgram state 1 0
    (.binary .logicalOr (.call 0 [.local 0]) (.call 2 [.local 0]))
    (.index (.local sourceId) (.local cursorId)) input 2
    _
    argumentStable
    (by simpa [Artifact.identifierContinueFunction, oneParameterBooleanFunction] using
      Artifact.identifierContinueFunction_found)
    formed bodyContract
  exact ⟨_, by simpa [input, Artifact.identifierContinueFunction,
    Artifact.identifierStartPredicate,
    Artifact.decimalPredicate, UnaryI32Predicate.exprFuel] using call⟩
theorem whitespaceConditionCall
    (state : State) (sourceId cursorId : VarId) (cell : CellId) (values : List Int)
  (cursor : Nat) (source : SourceSlice state sourceId cell values)
    (cursorFound : state.local? cursorId = some (.signed .i32 (Int.ofNat cursor)))
    (formed : state.CellsWellFormed) (inBounds : cursor < values.length) :
    ∃ after, ThresholdPure (max 4 (Artifact.whitespacePredicate.exprFuel + 4))
      Artifact.lexerProgram state
      (.call Artifact.whitespaceFunction.id [.index (.local sourceId) (.local cursorId)])
      (.boolean (Artifact.whitespacePredicate.accepts
        (values.get ⟨cursor, inBounds⟩))) after := by
  let input := values.get ⟨cursor, inBounds⟩
  let value : Value := .signed .i32 input
  let callee : State := ({ state with locals := [] }).bindLocal 0 value
  have argumentStable := evalExpr_source_slice_index_of_locals Artifact.lexerProgram
    state sourceId cursorId cell values cursor source cursorFound inBounds
  have call := thresholdPureArgumentCall Artifact.lexerProgram state 3 0
    (Artifact.whitespacePredicate.compile 0)
    (.index (.local sourceId) (.local cursorId)) input 2
    _ argumentStable
    (by simpa [Artifact.whitespaceFunction, unaryI32PredicateFunction,
      oneParameterBooleanFunction] using Artifact.whitespaceFunction_found)
    formed ⟨fun fuel enough => evalExpr_unaryI32Predicate Artifact.whitespacePredicate fuel enough
      Artifact.lexerProgram callee 0 input (formed.bindLocal_local 0 value),
      PureFrame.refl (formed.bindLocal 0 value)⟩
  exact ⟨_, by simpa [input, Artifact.whitespaceFunction,
    unaryI32PredicateFunction, oneParameterBooleanFunction] using call⟩

end Lanius.Compiler.Lexer
