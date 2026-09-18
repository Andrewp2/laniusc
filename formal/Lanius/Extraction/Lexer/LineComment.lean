import Lanius.Extraction.Lexer.Scanners
import Lanius.FunctionalViewLoop
import Lanius.FunctionalViewRenaming
import Lanius.FunctionalViewCoreCallFrame

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

private def parameterWorld (source : List Byte) : World :=
  World.singleton 0 (sourceIntegers source)

private def parameterEnvironment (source : List Byte) (start : Nat) : Env 3
  | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)

private def runtime (source : List Byte) (start cursor : Nat) :
    Runtime (ReadOnly.machine verifiedFrontendLexerCore) 4 :=
  (parameterWorld source,
    (parameterEnvironment source start).push (.signed .i32 cursor))

private def accepts (source : List Byte) (cursor : Nat) : Bool :=
  (source[cursor]?.map fun byte => byte.val != 10).getD false

private theorem condition_evaluates (start cursor : Nat) :
    Term.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      (runtime source start cursor).world (runtime source start cursor).environment
      condition = .ok (.boolean (accepts source cursor),
        (runtime source start cursor).world) := by
  have model : (decide (cursor < source.length) && accepts source cursor) =
      accepts source cursor := by
    by_cases inBounds : cursor < source.length <;> simp [accepts, inBounds]
  rw [← model]
  apply Term.evaluate_logicalAnd_guarded
    (left := beforeEnd) (right := notNewline)
    (leftResult := by
      simpa [beforeEnd, apply, runtime] using
        (Term.evaluate_i32_less (leftValue := cursor) (rightValue := source.length)
          rfl rfl))
  intro guard
  have inBounds : cursor < source.length := by simpa using guard
  simp [accepts, List.getElem?_eq_getElem inBounds]
  rw [← decide_intOfNat_notEqual]
  apply Term.evaluate_i32_notEqual_int
  · unfold currentByte
    change Term.evaluate _ _ _ (.apply _ [sourceTerm, cursorTerm]) = _
    apply Term.evaluate_i32_index_map
      (cell := 0) (values := source)
      (encode := fun byte => Int.ofNat byte.val) (position := cursor)
      <;> functional_eval
  · functional_eval

private theorem body_evaluates
    (start cursor : Nat) (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length) :
    Command.Evaluates (ReadOnly.machine verifiedFrontendLexerCore)
      (Stateful.machine verifiedFrontendLexerCore)
      (runtime source start cursor).world (runtime source start cursor).environment body
      .next (runtime source start (cursor + 1)).world
      (runtime source start (cursor + 1)).environment := by
  rw [show (runtime source start (cursor + 1)).environment =
      Env.set (runtime source start cursor).environment ⟨3, by omega⟩
        (.signed .i32 (Int.ofNat (cursor + 1))) by
    exact Env.eq_ofFn rfl]
  refine .sequenceNext (.updateLocal rfl ?_) .skip
  change evalAssignValue verifiedFrontendLexerCore.target .add
    (some (.signed .i32 (Int.ofNat cursor))) (.signed .i32 1) =
    .ok (.signed .i32 (Int.ofNat (cursor + 1)))
  simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
    beq_self_eq_true, if_true, evalSignedBinary]
  rw [show Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) by simp,
    wrapSigned_i32_ofNat verifiedFrontendLexerCore.target (cursor + 1) (by omega)]

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
  conditionInBounds := fun cursor _ => condition_evaluates (source := source) start cursor
  conditionOutOfBounds := fun cursor outOfBounds => by
    simpa [accepts, outOfBounds] using
      condition_evaluates (source := source) start cursor
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
  obtain ⟨_, loopResult, rfl⟩ := loop_evaluates source start (start + 2) sourceBound
  refine ⟨_, _, .letValue ?_ (.sequenceNext loopResult (.sequenceStop (.returnSome rfl) (by simp)))⟩
  exact Term.evaluate_i32_add (leftValue := start) (rightValue := 2) rfl rfl (by omega)

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
        afterWorld afterEnvironment := command_evaluates source start sourceBound openingInBounds

private theorem scannerParameterState_represents
    (source : List Byte) (start : Nat) :
    Representation identityLayout (callLocalCells (sourceState source)) (parameterWorld source)
      (parameterEnvironment source start)
      (scannerParameterState source start) := by
  have wellFormed := sourceState_well_formed source
  exact (Scanners.sourceState_represents source).enterCallParameters wellFormed

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
