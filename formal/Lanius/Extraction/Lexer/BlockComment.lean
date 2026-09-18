import Lanius.Extraction.Lexer.Scanners
import Lanius.Extraction.Lexer.ScanEndCalls
import Lanius.Extraction.Lexer.Quoted
import Lanius.FunctionalViewLoop
import Lanius.FunctionalViewRenaming
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.Lexer.BlockComment

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Loop

private abbrev T (arity : Nat) := Term signature arity
private abbrev C (arity : Nat) := Command signature actions arity

private def sourceTerm : T 4 := reference ⟨0, by omega⟩
private def boundTerm : T 4 := reference ⟨1, by omega⟩
private def cursorTerm : T 4 := reference ⟨3, by omega⟩
private def literalI32 (value : Nat) : T 4 :=
  literal (.signed .i32 (Int.ofNat value))

private def addCursor (amount : Nat) : T 4 :=
  apply (.binary .add i32Type i32Type i32Type)
    [cursorTerm, literalI32 amount]

private def sourceAt (index : T 4) : T 4 :=
  apply (.index (.slice i32Type) i32Type i32Type) [sourceTerm, index]

private def equalsI32 (left : T 4) (right : Nat) : T 4 :=
  apply (.binary .equal i32Type i32Type (.scalar .bool))
    [left, literalI32 right]

private def beforeEnd : T 4 :=
  apply (.binary .less i32Type i32Type (.scalar .bool))
    [cursorTerm, boundTerm]

private def closes : T 4 :=
  logicalAnd (logicalAnd (equalsI32 (sourceAt cursorTerm) 42)
    (apply (.binary .less i32Type i32Type (.scalar .bool))
      [addCursor 1, boundTerm]))
    (equalsI32 (sourceAt (addCursor 1)) 47)

private def closeValue (source : List Byte) (cursor : Nat) : Bool :=
  (source[cursor]?.map fun byte =>
    decide (byte.val = 42) &&
      (source[cursor + 1]?.map fun next => decide (next.val = 47)).getD false).getD false

private def successfulTerm : T 4 :=
  apply (.call Functions.successfulScanFunction.id [i32Type]
    (.structure 0)) [addCursor 2]

private def failedTerm : T 4 :=
  apply (.call Functions.failedScanFunction.id [i32Type]
    (.structure 0)) [boundTerm]

private def body : C 4 :=
  .sequence
    (.ifThenElse closes
      (.sequence (.returnValue (some successfulTerm)) .skip)
      .skip)
    (.sequence (.updateLocal .add ⟨3, by omega⟩ (literalI32 1)) .skip)

private def loop : C 4 := .whileLoop beforeEnd body

private def initializer : T 3 :=
  apply (.binary .add i32Type i32Type i32Type)
    [reference ⟨2, by omega⟩,
      literal (.signed .i32 (Int.ofNat 2))]

private def command : C 3 :=
  .letValue i32Type initializer
    (.sequence loop
      (.sequence (.returnValue (some failedTerm)) .skip))

theorem command_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 command = Scanners.scanBlockCommentEndBody := by
  rfl

def view := {
  Scanners.scanBlockCommentEndView with
  command := command
  toCoreExactly := command_toCore_exactly
}

private def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

private def parameterWorld (source : List Byte) :
    (Lanius.FunctionalView.Core.Effectful.machine
      verifiedFrontendLexerCore ScanEndCalls.calls).World :=
  World.singleton 0 (sourceIntegers source)

private abbrev world := parameterWorld

private def parameterEnvironment (source : List Byte) (start : Nat) : Env 3
  | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)

private def runtime (source : List Byte) (start cursor : Nat) :
    Runtime (Lanius.FunctionalView.Core.Effectful.machine
      verifiedFrontendLexerCore ScanEndCalls.calls) 4 :=
  (parameterWorld source,
    (parameterEnvironment source start).push (.signed .i32 (Int.ofNat cursor)))

private abbrev termMachine :=
  Lanius.FunctionalView.Core.Effectful.machine
    verifiedFrontendLexerCore ScanEndCalls.calls

private abbrev statefulMachine :=
  Stateful.machineWith verifiedFrontendLexerCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendLexerCore ScanEndCalls.calls)

private abbrev Runs (before : Runtime termMachine arity)
    (command : C arity) (completion : Stateful.Completion)
    (after : Runtime termMachine arity) : Prop :=
  Command.Evaluates termMachine statefulMachine before.world before.environment
    command completion after.world after.environment

private abbrev Returns (before : Runtime termMachine arity)
    (term : T arity) (value : Value) : Prop :=
  Term.evaluate termMachine before.world before.environment term =
    .ok (value, before.world)

private theorem beforeEnd_evaluates
    (source : List Byte) (start cursor : Nat) :
    Returns (runtime source start cursor) beforeEnd
      (.boolean (decide (cursor < source.length))) := by
  unfold Returns
  rw [Effectful.Term.evaluate_eq_readOnly_of_callFree _ (by rfl)]
  exact ReadOnly.Term.evaluate_i32_less (leftValue := cursor)
    (rightValue := source.length) rfl rfl

private theorem closes_evaluates
    (source : List Byte) (start cursor : Nat)
    (inBounds : cursor < source.length)
    (sourceBound : source.length ≤ 2147483647) :
    Returns (runtime source start cursor) closes
      (.boolean (closeValue source cursor)) := by
  unfold Returns
  have current : Returns (runtime source start cursor)
      (equalsI32 (sourceAt cursorTerm) 42)
      (.boolean (decide ((source.get ⟨cursor, inBounds⟩).val = 42))) := by
    unfold Returns
    rw [Effectful.Term.evaluate_eq_readOnly_of_callFree _ (by rfl)]
    apply ReadOnly.Term.evaluate_i32_equal
    · apply ReadOnly.Term.evaluate_i32_index_map
        (cell := 0) (values := source) (encode := fun byte => Int.ofNat byte.val)
        (position := cursor) (baseResult := by rfl) (indexResult := by rfl)
        (found := World.singleton_finds)
        (inBounds := by simpa [sourceIntegers] using inBounds)
    · rfl
  simp only [List.get_eq_getElem] at current
  have cursorBound : cursor + 1 ≤ 2147483647 := by omega
  have nextBound : Returns (runtime source start cursor)
      (apply (.binary .less i32Type i32Type (.scalar .bool))
        [addCursor 1, boundTerm])
      (.boolean (decide (cursor + 1 < source.length))) := by
    unfold Returns
    rw [Effectful.Term.evaluate_eq_readOnly_of_callFree _ (by rfl)]
    exact ReadOnly.Term.evaluate_i32_less
      (ReadOnly.Term.evaluate_i32_add rfl rfl cursorBound) rfl
  unfold closes
  have inner := Term.evaluate_logicalAnd_guarded current (by
    intro _
    simpa using nextBound)
  have result := Term.evaluate_logicalAnd_guarded
    (right := equalsI32 (sourceAt (addCursor 1)) 47)
    (rightValue :=
      (source[cursor + 1]?.map fun next => decide (next.val = 47)).getD false)
    inner (by
    intro innerTrue
    have nextInBounds : cursor + 1 < source.length := by
      exact of_decide_eq_true (Bool.and_eq_true_iff.mp innerTrue).2
    have next : Returns (runtime source start cursor)
        (equalsI32 (sourceAt (addCursor 1)) 47)
        (.boolean (decide
          ((source.get ⟨cursor + 1, nextInBounds⟩).val = 47))) := by
      unfold Returns
      rw [Effectful.Term.evaluate_eq_readOnly_of_callFree _ (by rfl)]
      apply ReadOnly.Term.evaluate_i32_equal
      · apply ReadOnly.Term.evaluate_i32_index_map
          (cell := 0) (values := source) (encode := fun byte => Int.ofNat byte.val)
          (position := cursor + 1) (baseResult := by rfl)
          (indexResult := ReadOnly.Term.evaluate_i32_add rfl rfl cursorBound)
          (found := World.singleton_finds)
          (inBounds := by simpa [sourceIntegers] using nextInBounds)
      · rfl
    simpa [Returns, List.getElem?_eq_getElem nextInBounds] using next)
  by_cases nextInBounds : cursor + 1 < source.length
  · simpa [closeValue, List.getElem?_eq_getElem inBounds,
      List.getElem?_eq_getElem nextInBounds, List.get_eq_getElem,
      nextInBounds, logicalAnd] using result
  · simpa [closeValue, List.getElem?_eq_getElem inBounds,
      List.getElem?_eq_none (Nat.le_of_not_gt nextInBounds),
      nextInBounds, logicalAnd] using result

private theorem successfulTerm_evaluates
    (source : List Byte) (start cursor : Nat)
    (bound : cursor + 2 ≤ 2147483647) :
    Returns (runtime source start cursor) successfulTerm
      (ScanEnd.value true (Int.ofNat (cursor + 2)) 0) := by
  unfold Returns
  unfold successfulTerm
  apply Term.evaluate_apply1
  · rw [Effectful.Term.evaluate_eq_readOnly_of_callFree _ (by rfl)]
    exact ReadOnly.Term.evaluate_i32_add
      (leftValue := cursor) (rightValue := 2) rfl rfl bound
  change ScanEndCalls.calls.evaluate (world source)
    Functions.successfulScanFunction.id
    [.signed .i32 (Int.ofNat (cursor + 2))] = _
  exact ScanEndCalls.successful (world source) (Int.ofNat (cursor + 2))

private theorem failedTerm_evaluates
    (source : List Byte) (start cursor : Nat) :
    Returns (runtime source start cursor) failedTerm
      (ScanEnd.value false 0 (Int.ofNat source.length)) := by
  unfold Returns
  unfold failedTerm apply
  apply Term.evaluate_apply1 (by rfl)
  change ScanEndCalls.calls.evaluate (world source)
    Functions.failedScanFunction.id
    [.signed .i32 (Int.ofNat source.length)] = _
  exact ScanEndCalls.failed (world source) (Int.ofNat source.length)

private theorem body_evaluates_close
    (source : List Byte) (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (closeBound : cursor + 2 ≤ source.length)
    (conditionResult : Term.evaluate termMachine
      (runtime source start cursor).world
      (runtime source start cursor).environment closes =
        .ok (.boolean true, (runtime source start cursor).world)) :
    Runs (runtime source start cursor) body
      (.returned (some
          (ScanEnd.value true (Int.ofNat (cursor + 2)) 0)))
      (runtime source start cursor) := by
  exact .sequenceStop (.ifTrue conditionResult
      (.sequenceStop
      (.returnSome (successfulTerm_evaluates source start cursor
        (Nat.le_trans closeBound sourceBound)))
      (by simp))) (by simp)

private theorem body_evaluates_step
    (source : List Byte) (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length)
    (conditionResult : Term.evaluate termMachine
      (runtime source start cursor).world
      (runtime source start cursor).environment closes =
        .ok (.boolean false, (runtime source start cursor).world)) :
    Runs (runtime source start cursor) body .next
      (runtime source start (cursor + 1)) := by
  unfold Runs
  have afterEnvironment : (runtime source start (cursor + 1)).environment =
      Env.set (runtime source start cursor).environment ⟨3, by omega⟩
        (.signed .i32 (Int.ofNat (cursor + 1))) := by
    exact Env.eq_ofFn rfl
  rw [afterEnvironment]
  refine .sequenceNext (.ifFalse conditionResult .skip) ?_
  refine .sequenceNext (.updateLocal rfl ?_) .skip
  change evalAssignValue verifiedFrontendLexerCore.target .add
    (some (.signed .i32 (Int.ofNat cursor))) (.signed .i32 1) =
    .ok (.signed .i32 (Int.ofNat (cursor + 1)))
  simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
    beq_self_eq_true, if_true, evalSignedBinary]
  rw [show Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) by simp,
    wrapSigned_i32_ofNat verifiedFrontendLexerCore.target (cursor + 1) (by omega)]

private theorem scanBlockBody_step
    (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length) :
    scanBlockBody (source.drop cursor) cursor =
      if closeValue source cursor then .success (cursor + 2)
      else scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
  have dropped := List.drop_eq_getElem_cons inBounds
  by_cases nextInBounds : cursor + 1 < source.length
  · have droppedNext := List.drop_eq_getElem_cons nextInBounds
    rw [dropped, droppedNext, scanBlockBody]
    by_cases closesAt :
        source[cursor].val = 42 ∧ source[cursor + 1].val = 47
    · rw [if_pos closesAt]
      simp [closeValue, List.getElem?_eq_getElem inBounds,
        List.getElem?_eq_getElem nextInBounds, closesAt]
    · rw [if_neg closesAt]
      simp [closeValue, List.getElem?_eq_getElem inBounds,
        List.getElem?_eq_getElem nextInBounds, closesAt]
  · have droppedNext : source.drop (cursor + 1) = [] :=
      List.drop_eq_nil_of_le (Nat.le_of_not_gt nextInBounds)
    rw [dropped, droppedNext, scanBlockBody]
    simp [closeValue, List.getElem?_eq_getElem inBounds,
      List.getElem?_eq_none (Nat.le_of_not_gt nextInBounds)]
    rfl

private theorem loop_and_fallback_evaluates
    (source : List Byte) (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (cursorBound : cursor ≤ source.length) :
    ∃ finalCursor,
      Runs (runtime source start cursor)
        (.sequence loop
          (.sequence (.returnValue (some failedTerm)) .skip))
        (.returned (some
          (scanEndValue (scanBlockBody (source.drop cursor) cursor))))
        (runtime source start finalCursor) := by
  by_cases inBounds : cursor < source.length
  · have loopCondition := beforeEnd_evaluates source start cursor
    simp [inBounds] at loopCondition
    have stepResult := scanBlockBody_step source cursor inBounds
    have closeCondition := closes_evaluates source start cursor
      inBounds sourceBound
    by_cases closesAt : closeValue source cursor
    · have closeBound : cursor + 2 ≤ source.length := by
        have nextInBounds : cursor + 1 < source.length := by
          by_cases nextInBounds : cursor + 1 < source.length
          · exact nextInBounds
          · have impossible := closesAt
            simp [closeValue, List.getElem?_eq_getElem inBounds,
              List.getElem?_eq_none (Nat.le_of_not_gt nextInBounds)] at impossible
        omega
      simp [closesAt] at closeCondition
      have bodyResult := body_evaluates_close source start cursor sourceBound
        closeBound closeCondition
      have resultEq : scanBlockBody (source.drop cursor) cursor =
          .success (cursor + 2) := by
        simpa [closesAt] using stepResult
      refine ⟨cursor, ?_⟩
      rw [resultEq]
      change Command.Evaluates termMachine statefulMachine
        (runtime source start cursor).world
        (runtime source start cursor).environment
        (.sequence loop
          (.sequence (.returnValue (some failedTerm)) .skip))
        (.returned (some
          (ScanEnd.value true (Int.ofNat (cursor + 2)) 0)))
        (runtime source start cursor).world
        (runtime source start cursor).environment
      exact .sequenceStop
        (.whileReturn loopCondition bodyResult) (by simp)
    · simp [closesAt] at closeCondition
      have bodyResult := body_evaluates_step source start cursor sourceBound
        inBounds closeCondition
      have stepResult : scanBlockBody (source.drop cursor) cursor =
          scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
        simpa [closesAt] using stepResult
      obtain ⟨finalCursor, rest⟩ :=
        loop_and_fallback_evaluates source start (cursor + 1) sourceBound
          (Nat.succ_le_of_lt inBounds)
      refine ⟨finalCursor, ?_⟩
      rw [stepResult]
      exact Command.Evaluates.whileNextSequence loopCondition
        bodyResult rest
  · have atEnd : cursor = source.length :=
      Nat.le_antisymm cursorBound (Nat.le_of_not_gt inBounds)
    have loopCondition := beforeEnd_evaluates source start cursor
    simp [inBounds] at loopCondition
    have resultEq : scanBlockBody (source.drop cursor) cursor =
        .failure source.length := by
      simp [atEnd, scanBlockBody]
    refine ⟨source.length, ?_⟩
    rw [resultEq]
    simpa [loop, atEnd, scanEndValue, ScanEnd.value, scanEndDeclaration] using
      (Command.Evaluates.sequenceNext
        (Command.Evaluates.whileFalse (body := body) loopCondition)
        (.sequenceStop
          (.returnSome (by
            simpa [atEnd, scanEndValue, ScanEnd.value, scanEndDeclaration] using
              failedTerm_evaluates source start source.length))
          (by simp)))
termination_by source.length - cursor
decreasing_by all_goals omega

theorem command_evaluates
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates termMachine statefulMachine (world source)
        (parameterEnvironment source start) command
        (.returned (some
          (scanEndValue (scanBlockCommentEnd source start))))
        afterWorld afterEnvironment := by
  let initialCursor := start + 2
  have initialCursorBound : initialCursor ≤ source.length := by omega
  have initialI32Bound : initialCursor ≤ 2147483647 :=
    Nat.le_trans initialCursorBound sourceBound
  have initializerResult : Term.evaluate termMachine (world source)
      (parameterEnvironment source start) initializer =
      .ok (.signed .i32 (Int.ofNat initialCursor), world source) := by
    unfold initializer apply
    apply Term.evaluate_apply2 (by rfl) (by rfl)
    change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
      (.binary .add i32Type i32Type i32Type)
      [.signed .i32 (Int.ofNat start), .signed .i32 2] = _
    exact ReadOnly.evaluateOperation_i32_add
      (program := verifiedFrontendLexerCore) (world := world source)
      (leftType := i32Type) (rightType := i32Type) (outputType := i32Type)
      start 2 initialI32Bound
  have pushed : (parameterEnvironment source start).push
      (.signed .i32 (Int.ofNat initialCursor)) =
      (runtime source start initialCursor).environment := by
    exact Env.eq_ofFn rfl
  obtain ⟨finalCursor, bodyExecution⟩ :=
    loop_and_fallback_evaluates source start initialCursor sourceBound
    initialCursorBound
  have whole := Command.Evaluates.letValue (type := i32Type)
    initializerResult (by
      rw [pushed]
      exact bodyExecution)
  exact ⟨(runtime source start finalCursor).world,
    Env.pop (runtime source start finalCursor).environment,
    by simpa [command, scanBlockCommentEnd, initialCursor] using whole⟩

theorem view_evaluates
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates termMachine statefulMachine (world source)
        (parameterEnvironment source start) view.command
        (.returned (some
          (scanEndValue (scanBlockCommentEnd source start))))
        afterWorld afterEnvironment := by
  exact command_evaluates source start sourceBound openingInBounds

private theorem scannerParameterState_represents
    (source : List Byte) (start : Nat) :
    Representation identityLayout (callLocalCells (sourceState source))
      (parameterWorld source) (parameterEnvironment source start)
      (scannerParameterState source start) := by
  exact (Scanners.sourceState_represents source).enterCallParameters
    (sourceState_well_formed source)

theorem core_body_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ after,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        Scanners.scanBlockCommentEndBody
        (.returned (some
          (scanEndValue (scanBlockCommentEnd source start)))) after ∧
      StateWellFormed after := by
  obtain ⟨afterWorld, afterEnvironment, evaluated⟩ :=
    command_evaluates source start sourceBound openingInBounds
  have simulation := Stateful.command_executes
    (Lanius.FunctionalView.Core.EffectfulStateful.expressionSoundness
      verifiedFrontendLexerCore ScanEndCalls.calls
      Quoted.scanEndCallSoundness)
    (Lanius.FunctionalView.Core.EffectfulStateful.actionSoundness
      verifiedFrontendLexerCore ScanEndCalls.calls
      Quoted.scanEndCallSoundness)
    evaluated
    (scannerParameterState_represents source start)
    (LayoutBelow.identity (arity := 3))
    (scannerParameterState_well_formed source start)
  obtain ⟨after, writes, execution, afterWellFormed, _, _⟩ := simulation
  rw [command_toCore_exactly] at execution
  exact ⟨after, execution, afterWellFormed⟩

theorem call_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ after,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (scannerCall Scanners.scanBlockCommentEndFunction source start)
        (scanEndValue (scanBlockCommentEnd source start)) after := by
  obtain ⟨bodyFinal, bodyExecution, _⟩ :=
    core_body_executes source start sourceBound openingInBounds
  exact scannerCall_executesBody verifiedFrontendLexerCore
    Scanners.scanBlockCommentEndFunction Scanners.scanBlockCommentEndBody
    (scanEndValue (scanBlockCommentEnd source start))
    Scanners.verifiedFrontendLexerCore_finds_scanBlockCommentEnd
    (by rfl) Scanners.scanBlockCommentEndFunction_has_body source start
    ⟨bodyFinal, bodyExecution⟩

end Lanius.Extraction.Lexer.BlockComment
