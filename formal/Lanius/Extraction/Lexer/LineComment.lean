import Lanius.Extraction.Lexer.Scanners
import Lanius.FunctionalViewLoop

namespace Lanius.Extraction.Lexer.LineComment

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer.Scanners
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Loop
open Lanius.FunctionalView.Core.Stateful.Reification

private abbrev T (arity : Nat) := Term signature arity
private abbrev C (arity : Nat) := Command signature actions arity

private def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

@[simp] private theorem sourceIntegers_length :
    (sourceIntegers source).length = source.length := by
  simp [sourceIntegers]

private def sourceTerm : T 4 := reference ⟨0, by omega⟩
private def boundTerm : T 4 := reference ⟨1, by omega⟩
private def cursorTerm : T 4 := reference ⟨3, by omega⟩
private def oneTerm : T 4 := literal (.signed .i32 1)
private def newlineTerm : T 4 := literal (.signed .i32 10)

private def beforeEnd : T 4 :=
  apply (.binary .less i32Type i32Type (.scalar .bool))
    [cursorTerm, boundTerm]

private def currentByte : T 4 :=
  apply (.index (.slice i32Type) i32Type i32Type)
    [sourceTerm, cursorTerm]

private def notNewline : T 4 :=
  apply (.binary .notEqual i32Type i32Type (.scalar .bool))
    [currentByte, newlineTerm]

private def condition : T 4 := logicalAnd beforeEnd notNewline

private def body : C 4 :=
  .sequence (.updateLocal .add ⟨3, by omega⟩ oneTerm) .skip

private def loop : C 4 := .whileLoop condition body

private def initializer : T 3 :=
  apply (.binary .add i32Type i32Type i32Type)
    [reference ⟨2, by omega⟩, literal (.signed .i32 2)]

private def command : C 3 :=
  .letValue i32Type initializer
    (.sequence loop
      (.sequence (.returnValue (some cursorTerm)) .skip))

theorem command_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 command = scanLineCommentEndBody := by
  rfl

def view := {
  Scanners.scanLineCommentEndView with
  command := command
  toCoreExactly := command_toCore_exactly
}

theorem view_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 view.command = scanLineCommentEndBody :=
  command_toCore_exactly

private def runtime (source : List Byte) (start cursor : Nat) :
    Runtime (ReadOnly.machine verifiedFrontendLexerCore) 4 :=
  (World.singleton 0 (sourceIntegers source), fun
    | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
    | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
    | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)
    | ⟨3, _⟩ => .signed .i32 (Int.ofNat cursor))

private def accepts (source : List Byte) (cursor : Nat) : Bool :=
  (source[cursor]?.map fun byte => byte.val != 10).getD false

private theorem condition_in_bounds
    (start cursor : Nat) (inBounds : cursor < source.length) :
    Term.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      (runtime source start cursor).world (runtime source start cursor).environment
      condition = .ok (.boolean (accepts source cursor),
        (runtime source start cursor).world) := by
  have left : Term.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      (runtime source start cursor).world (runtime source start cursor).environment
      beforeEnd = .ok (.boolean true, (runtime source start cursor).world) := by
    have evaluated := Term.evaluate_i32_less
      (program := verifiedFrontendLexerCore)
      (world := (runtime source start cursor).world)
      (environment := (runtime source start cursor).environment)
      (leftType := i32Type) (rightType := i32Type)
      (outputType := .scalar .bool)
      (left := cursorTerm) (right := boundTerm)
      (leftValue := cursor) (rightValue := source.length) (by rfl) (by rfl)
    simpa [beforeEnd, apply, runtime, inBounds] using evaluated
  apply Term.evaluate_logicalAnd_true left
  have evaluated : Term.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      (runtime source start cursor).world (runtime source start cursor).environment
      notNewline = .ok (.boolean (decide (Int.ofNat
        (source.get ⟨cursor, inBounds⟩).val ≠ Int.ofNat 10)),
        (runtime source start cursor).world) := by
    apply Term.evaluate_i32_notEqual_int
    · apply Term.evaluate_i32_index_as
        (cell := 0) (values := sourceIntegers source) (position := cursor)
        (expected := Int.ofNat (source.get ⟨cursor, inBounds⟩).val)
      · apply Term.evaluate_slot
        change (runtime source start cursor).environment ⟨0, by omega⟩ = _
        rw [sourceIntegers_length]
        rfl
      · apply Term.evaluate_slot
        change (runtime source start cursor).environment ⟨3, by omega⟩ = _
        rfl
      · exact World.singleton_finds
      · simp [sourceIntegers]
      · simpa [sourceIntegers] using inBounds
    · change Except.ok (Value.signed .i32 10,
        (runtime source start cursor).world) = _
      rfl
  rw [decide_intOfNat_notEqual] at evaluated
  simpa [accepts, List.getElem?_eq_getElem inBounds] using evaluated

private theorem condition_out_of_bounds
    (start cursor : Nat) (outOfBounds : ¬ cursor < source.length) :
    Term.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      (runtime source start cursor).world (runtime source start cursor).environment
      condition = .ok (.boolean false, (runtime source start cursor).world) := by
  apply Term.evaluate_logicalAnd_false
  have evaluated := Term.evaluate_i32_less
    (program := verifiedFrontendLexerCore)
    (world := (runtime source start cursor).world)
    (environment := (runtime source start cursor).environment)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := .scalar .bool)
    (left := cursorTerm) (right := boundTerm)
    (leftValue := cursor) (rightValue := source.length) (by rfl) (by rfl)
  simpa [beforeEnd, apply, runtime, outOfBounds] using evaluated

private theorem body_evaluates
    (start cursor : Nat) (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length) :
    Command.Evaluates (ReadOnly.machine verifiedFrontendLexerCore)
      (Stateful.machine verifiedFrontendLexerCore)
      (runtime source start cursor).world (runtime source start cursor).environment body
      .next (runtime source start (cursor + 1)).world
      (runtime source start (cursor + 1)).environment := by
  have advanceWorld : (runtime source start (cursor + 1)).world =
      (runtime source start cursor).world := by rfl
  have advanceEnvironment : (runtime source start (cursor + 1)).environment =
      Env.set (runtime source start cursor).environment ⟨3, by omega⟩
        (.signed .i32 (Int.ofNat (cursor + 1))) := by
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 := by omega
    rcases cases with zero | one | two | three
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      simp [runtime, Runtime.environment, Env.set]
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      simp [runtime, Runtime.environment, Env.set]
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      simp [runtime, Runtime.environment, Env.set]
    · have same : index = ⟨3, by omega⟩ := Fin.ext three
      rw [same]
      simp [runtime, Runtime.environment, Env.set]
  rw [advanceWorld, advanceEnvironment]
  have oneResult : Term.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      (runtime source start cursor).world (runtime source start cursor).environment oneTerm =
      .ok (.signed .i32 1, (runtime source start cursor).world) := by rfl
  have cursorValue : (runtime source start cursor).environment ⟨3, by omega⟩ =
      .signed .i32 (Int.ofNat cursor) := by rfl
  have updateResult : evalAssignValue verifiedFrontendLexerCore.target .add
      (some ((runtime source start cursor).environment ⟨3, by omega⟩))
      (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (cursor + 1))) := by
    have addition : Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) := by
      simp
    rw [cursorValue]
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    rw [addition]
    rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _
      (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)]
  apply Command.Evaluates.sequenceNext
  · exact Command.Evaluates.updateLocal oneResult (by
      simpa [Stateful.machine, Stateful.machineWith] using updateResult)
  · exact .skip

private theorem recurrence : CursorScan.Recurrence source.length
    (accepts source)
    (scanAcceptedFrom (fun byte => byte.val != 10) source) := by
  constructor
  · exact scanAcceptedFrom_out_of_bounds _ source
  · intro cursor inBounds rejected
    apply scanAcceptedFrom_rejected _ source cursor inBounds
    simpa [accepts, List.getElem?_eq_getElem inBounds] using rejected
  · intro cursor inBounds accepted
    apply scanAcceptedFrom_accepted _ source cursor inBounds
    simpa [accepts, List.getElem?_eq_getElem inBounds] using accepted

private theorem spec (start : Nat) (sourceBound : source.length ≤ 2147483647) :
    CursorScan.Spec (ReadOnly.machine verifiedFrontendLexerCore)
      (Stateful.machine verifiedFrontendLexerCore) condition body
      (runtime source start) source.length (accepts source) := {
  conditionInBounds := condition_in_bounds start
  conditionOutOfBounds := condition_out_of_bounds start
  body := fun cursor inBounds _ => body_evaluates start cursor sourceBound inBounds
}

theorem loop_evaluates
    (source : List Byte) (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ after,
      Command.Evaluates (ReadOnly.machine verifiedFrontendLexerCore)
        (Stateful.machine verifiedFrontendLexerCore)
        (runtime source start cursor).world (runtime source start cursor).environment loop
        .next after.world after.environment ∧
      after = runtime source start
        (scanAcceptedFrom (fun byte => byte.val != 10) source cursor) := by
  let execution := CursorScan.run (spec start sourceBound) recurrence cursor
  refine ⟨execution.after, ?_, ?_⟩
  · simpa [loop, execution.result.completionEq] using execution.trace.evaluates
  · simp [execution.result.afterEq, execution.result.finalEq]

private def parameterWorld (source : List Byte) : World :=
  World.singleton 0 (sourceIntegers source)

private def parameterEnvironment (source : List Byte) (start : Nat) : Env 3
  | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)

theorem command_evaluates
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates (ReadOnly.machine verifiedFrontendLexerCore)
        (Stateful.machine verifiedFrontendLexerCore)
        (parameterWorld source) (parameterEnvironment source start)
        command
        (.returned (some (.signed .i32 (scanLineCommentEnd source start))))
        afterWorld afterEnvironment := by
  let initialCursor := start + 2
  have initialBound : initialCursor ≤ 2147483647 :=
    Nat.le_trans (by omega : start + 2 ≤ source.length) sourceBound
  have initializerResult : Term.evaluate
      (ReadOnly.machine verifiedFrontendLexerCore) (parameterWorld source)
      (parameterEnvironment source start) initializer =
      .ok (.signed .i32 (Int.ofNat initialCursor), parameterWorld source) := by
    have startResult : Term.evaluate
        (ReadOnly.machine verifiedFrontendLexerCore) (parameterWorld source)
        (parameterEnvironment source start) (reference ⟨2, by omega⟩) =
        .ok (.signed .i32 (Int.ofNat start), parameterWorld source) := by rfl
    have twoResult : Term.evaluate
        (ReadOnly.machine verifiedFrontendLexerCore) (parameterWorld source)
        (parameterEnvironment source start) (literal (.signed .i32 2)) =
        .ok (.signed .i32 (Int.ofNat 2), parameterWorld source) := by rfl
    change Term.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      (parameterWorld source) (parameterEnvironment source start)
      (apply (.binary .add i32Type i32Type i32Type)
        [reference ⟨2, by omega⟩, literal (.signed .i32 2)]) = _
    exact Term.evaluate_i32_add
      (program := verifiedFrontendLexerCore)
      (leftType := i32Type) (rightType := i32Type) (outputType := i32Type)
      startResult twoResult initialBound
  have pushed : (parameterEnvironment source start).push
      (.signed .i32 (Int.ofNat initialCursor)) =
      (runtime source start initialCursor).environment := by
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 := by omega
    rcases cases with zero | one | two | three
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      rfl
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      rfl
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      rfl
    · have same : index = ⟨3, by omega⟩ := Fin.ext three
      rw [same]
      rfl
  obtain ⟨after, loopResult, afterEq⟩ :=
    loop_evaluates source start initialCursor sourceBound
  subst after
  let finish := scanAcceptedFrom (fun byte => byte.val != 10) source initialCursor
  have finishEq : finish = scanLineCommentEnd source start := by rfl
  have returnResult : Term.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      (runtime source start finish).world (runtime source start finish).environment
      cursorTerm = .ok (.signed .i32 (Int.ofNat finish),
        (runtime source start finish).world) := by rfl
  have bodyResult : Command.Evaluates
      (ReadOnly.machine verifiedFrontendLexerCore)
      (Stateful.machine verifiedFrontendLexerCore)
      (runtime source start initialCursor).world
      (runtime source start initialCursor).environment
      (.sequence loop
        (.sequence (.returnValue (some cursorTerm)) .skip))
      (.returned (some (.signed .i32 (Int.ofNat finish))))
      (runtime source start finish).world
      (runtime source start finish).environment := by
    apply Command.Evaluates.sequenceNext
    · simpa [finish] using loopResult
    · exact Command.Evaluates.sequenceStop
        (Command.Evaluates.returnSome returnResult) (by simp)
  have whole := Command.Evaluates.letValue (type := i32Type)
    initializerResult (by
    rw [pushed]
    exact bodyResult)
  rw [finishEq] at whole
  exact ⟨(runtime source start finish).world,
    Env.pop (runtime source start finish).environment, whole⟩

theorem view_evaluates
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates (ReadOnly.machine verifiedFrontendLexerCore)
        (Stateful.machine verifiedFrontendLexerCore)
        (parameterWorld source) (parameterEnvironment source start)
        view.command
        (.returned (some (.signed .i32 (scanLineCommentEnd source start))))
        afterWorld afterEnvironment := by
  exact command_evaluates source start sourceBound openingInBounds

private def localCells : Fin 3 → CellId :=
  fun index => index.val + 1

private theorem scannerParameterState_represents
    (source : List Byte) (start : Nat) :
    Representation identityLayout localCells (parameterWorld source)
      (parameterEnvironment source start)
      (scannerParameterState source start) := by
  have wellFormed := scannerParameterState_well_formed source start
  refine {
    worldOwned := ?_
    localOwned := ?_
    localCellsInjective := ?_
    worldLocalsDisjoint := ?_
  }
  · rw [World.owns_iff_represents wellFormed]
    apply World.singleton_represents wellFormed
    simp [sourceIntegers, sourceValues, signedI32Values,
      scannerParameterState, State.bindLocals, State.bindLocal,
      State.bindCell, sourceState, State.cellEntry?]
  · intro index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 := by
      omega
    rcases cases with zero | one | two
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      simp [identityLayout, localCells, parameterEnvironment,
        scannerParameterState, State.bindLocals, State.bindLocal,
        State.bindCell, sourceState, Assertion.localPointsTo,
        State.cellId?, State.cellEntry?, i32Type]
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      simp [identityLayout, localCells, parameterEnvironment,
        scannerParameterState, State.bindLocals, State.bindLocal,
        State.bindCell, sourceState, Assertion.localPointsTo,
        State.cellId?, State.cellEntry?, i32Type]
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      simp [identityLayout, localCells, parameterEnvironment,
        scannerParameterState, State.bindLocals, State.bindLocal,
        State.bindCell, sourceState, Assertion.localPointsTo,
        State.cellId?, State.cellEntry?, i32Type]
  · intro left right same
    apply Fin.ext
    simp [localCells] at same
    omega
  · intro cell worldMember localMember
    obtain ⟨values, found⟩ := worldMember
    have cellZero : cell = 0 := by
      by_cases same : cell = 0
      · exact same
      · simp [parameterWorld, World.singleton, same] at found
    subst cell
    obtain ⟨index, localZero⟩ := localMember
    exact (Nat.ne_of_gt (by simp [localCells] : 0 < localCells index))
      localZero

theorem core_body_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ after,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        Scanners.scanLineCommentEndBody
        (.returned (some
          (.signed .i32 (scanLineCommentEnd source start)))) after ∧
      StateWellFormed after := by
  obtain ⟨afterWorld, afterEnvironment, evaluated⟩ :=
    view_evaluates source start sourceBound openingInBounds
  have simulation := Stateful.command_executes
    (Stateful.readOnlyExpressionSoundness verifiedFrontendLexerCore)
    (Stateful.actionSoundness verifiedFrontendLexerCore)
    evaluated
    (scannerParameterState_represents source start)
    (LayoutBelow.identity (arity := 3))
    (scannerParameterState_well_formed source start)
  obtain ⟨after, writes, execution, afterWellFormed, _, _⟩ := simulation
  rw [view_toCore_exactly] at execution
  exact ⟨after, execution, afterWellFormed⟩

theorem call_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ after,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (scannerCall Scanners.scanLineCommentEndFunction source start)
        (.signed .i32 (scanLineCommentEnd source start)) after := by
  obtain ⟨bodyFinal, bodyExecution, _⟩ :=
    core_body_executes source start sourceBound openingInBounds
  exact scannerCall_executesBody verifiedFrontendLexerCore
    Scanners.scanLineCommentEndFunction Scanners.scanLineCommentEndBody
    (.signed .i32 (scanLineCommentEnd source start))
    Scanners.verifiedFrontendLexerCore_finds_scanLineCommentEnd
    (by rfl) Scanners.scanLineCommentEndFunction_has_body source start
    ⟨bodyFinal, bodyExecution⟩

end Lanius.Extraction.Lexer.LineComment
