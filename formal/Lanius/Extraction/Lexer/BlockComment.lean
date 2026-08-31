import Lanius.Extraction.Lexer.Scanners
import Lanius.Extraction.Lexer.ScanEndCalls
import Lanius.Extraction.Lexer.Quoted
import Lanius.FunctionalViewLoop

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

private def world (source : List Byte) :
    (Lanius.FunctionalView.Core.Effectful.machine
      verifiedFrontendLexerCore ScanEndCalls.calls).World :=
  World.singleton 0 (sourceIntegers source)

private def runtime (source : List Byte) (start cursor : Nat) :
    Runtime (Lanius.FunctionalView.Core.Effectful.machine
      verifiedFrontendLexerCore ScanEndCalls.calls) 4 :=
  (world source, fun
    | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
    | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
    | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)
    | ⟨3, _⟩ => .signed .i32 (Int.ofNat cursor))

private abbrev termMachine :=
  Lanius.FunctionalView.Core.Effectful.machine
    verifiedFrontendLexerCore ScanEndCalls.calls

private abbrev statefulMachine :=
  Stateful.machineWith verifiedFrontendLexerCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendLexerCore ScanEndCalls.calls)

@[simp] private theorem sourceIntegers_length :
    (sourceIntegers source).length = source.length := by
  simp [sourceIntegers]

private theorem beforeEnd_evaluates
    (source : List Byte) (start cursor : Nat) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment beforeEnd =
      .ok (.boolean (decide (cursor < source.length)),
        (runtime source start cursor).world) := by
  unfold beforeEnd apply
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore
      (world source)
      (.binary .less i32Type i32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat cursor),
        .signed .i32 (Int.ofNat source.length)] = _
  exact ReadOnly.evaluateOperation_i32_less
      (program := verifiedFrontendLexerCore) (world := world source)
      (leftType := i32Type) (rightType := i32Type)
      (outputType := .scalar .bool) cursor source.length

private theorem addCursor_evaluates
    (source : List Byte) (start cursor amount : Nat)
    (bound : cursor + amount ≤ 2147483647) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment (addCursor amount) =
      .ok (.signed .i32 (Int.ofNat (cursor + amount)),
        (runtime source start cursor).world) := by
  unfold addCursor apply
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
      (.binary .add i32Type i32Type i32Type)
      [.signed .i32 (Int.ofNat cursor),
        .signed .i32 (Int.ofNat amount)] = _
  exact ReadOnly.evaluateOperation_i32_add
    (program := verifiedFrontendLexerCore) (world := world source)
    (leftType := i32Type) (rightType := i32Type) (outputType := i32Type)
    cursor amount bound

private theorem currentByte_evaluates
    (source : List Byte) (start cursor : Nat)
    (inBounds : cursor < source.length) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment (sourceAt cursorTerm) =
      .ok (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val),
        (runtime source start cursor).world) := by
  unfold sourceAt apply
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.index (.slice i32Type) i32Type i32Type)
    [.slice i32Type 0 [] 0 source.length,
      .signed .i32 (Int.ofNat cursor)] =
    .ok (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val),
      world source)
  have evaluated := ReadOnly.evaluateOperation_i32_index
    (program := verifiedFrontendLexerCore) (world := world source)
    (baseType := .slice i32Type) (indexType := i32Type)
    (elementType := i32Type) (cell := 0)
    (values := sourceIntegers source) (position := cursor)
    World.singleton_finds (by simpa [sourceIntegers] using inBounds)
  simpa [sourceIntegers, i32Type] using evaluated

private theorem equalsCurrent_evaluates
    (source : List Byte) (start cursor expected : Nat)
    (inBounds : cursor < source.length) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment
        (equalsI32 (sourceAt cursorTerm) expected) =
      .ok (.boolean (decide
        ((source.get ⟨cursor, inBounds⟩).val = expected)),
        (runtime source start cursor).world) := by
  unfold equalsI32 apply
  apply Term.evaluate_apply2
    (currentByte_evaluates source start cursor inBounds) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.binary .equal i32Type i32Type (.scalar .bool))
    [.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val),
      .signed .i32 (Int.ofNat expected)] = _
  exact ReadOnly.evaluateOperation_i32_equal
    (program := verifiedFrontendLexerCore) (world := world source)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := .scalar .bool)
    (source.get ⟨cursor, inBounds⟩).val expected

private theorem nextBeforeEnd_evaluates
    (source : List Byte) (start cursor : Nat)
    (cursorBound : cursor + 1 ≤ 2147483647) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment
        (apply (.binary .less i32Type i32Type (.scalar .bool))
          [addCursor 1, boundTerm]) =
      .ok (.boolean (decide (cursor + 1 < source.length)),
        (runtime source start cursor).world) := by
  unfold apply
  apply Term.evaluate_apply2
    (addCursor_evaluates source start cursor 1 cursorBound) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.binary .less i32Type i32Type (.scalar .bool))
    [.signed .i32 (Int.ofNat (cursor + 1)),
      .signed .i32 (Int.ofNat source.length)] = _
  exact ReadOnly.evaluateOperation_i32_less
    (program := verifiedFrontendLexerCore) (world := world source)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := .scalar .bool) (cursor + 1) source.length

private theorem nextByte_evaluates
    (source : List Byte) (start cursor : Nat)
    (nextInBounds : cursor + 1 < source.length)
    (cursorBound : cursor + 1 ≤ 2147483647) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment (sourceAt (addCursor 1)) =
      .ok (.signed .i32
        (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val),
        (runtime source start cursor).world) := by
  unfold sourceAt apply
  apply Term.evaluate_apply2 (by rfl)
    (addCursor_evaluates source start cursor 1 cursorBound)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.index (.slice i32Type) i32Type i32Type)
    [.slice i32Type 0 [] 0 source.length,
      .signed .i32 (Int.ofNat (cursor + 1))] =
    .ok (.signed .i32
      (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val), world source)
  have evaluated := ReadOnly.evaluateOperation_i32_index
    (program := verifiedFrontendLexerCore) (world := world source)
    (baseType := .slice i32Type) (indexType := i32Type)
    (elementType := i32Type) (cell := 0)
    (values := sourceIntegers source) (position := cursor + 1)
    World.singleton_finds (by simpa [sourceIntegers] using nextInBounds)
  simpa [sourceIntegers, i32Type] using evaluated

private theorem equalsNext_evaluates
    (source : List Byte) (start cursor expected : Nat)
    (nextInBounds : cursor + 1 < source.length)
    (cursorBound : cursor + 1 ≤ 2147483647) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment
        (equalsI32 (sourceAt (addCursor 1)) expected) =
      .ok (.boolean (decide
        ((source.get ⟨cursor + 1, nextInBounds⟩).val = expected)),
        (runtime source start cursor).world) := by
  unfold equalsI32 apply
  apply Term.evaluate_apply2
    (nextByte_evaluates source start cursor nextInBounds cursorBound) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.binary .equal i32Type i32Type (.scalar .bool))
    [.signed .i32
      (Int.ofNat (source.get ⟨cursor + 1, nextInBounds⟩).val),
      .signed .i32 (Int.ofNat expected)] = _
  exact ReadOnly.evaluateOperation_i32_equal
    (program := verifiedFrontendLexerCore) (world := world source)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := .scalar .bool)
    (source.get ⟨cursor + 1, nextInBounds⟩).val expected

private theorem closes_evaluates_true
    (source : List Byte) (start cursor : Nat)
    (inBounds : cursor < source.length)
    (isStar : (source.get ⟨cursor, inBounds⟩).val = 42)
    (nextInBounds : cursor + 1 < source.length)
    (isSlash : (source.get ⟨cursor + 1, nextInBounds⟩).val = 47)
    (sourceBound : source.length ≤ 2147483647) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment closes =
      .ok (.boolean true, (runtime source start cursor).world) := by
  unfold closes
  apply Term.evaluate_logicalAnd_true
  · apply Term.evaluate_logicalAnd_true
    · have evaluated := equalsCurrent_evaluates source start cursor 42 inBounds
      have actual : source[cursor].val = 42 := by
        simpa [List.get_eq_getElem] using isStar
      have decided : decide
          ((source.get ⟨cursor, inBounds⟩).val = 42) = true := by
        simpa [List.get_eq_getElem] using actual
      rw [decided] at evaluated
      exact evaluated
    · have cursorBound : cursor + 1 ≤ 2147483647 :=
        Nat.le_trans (Nat.le_of_lt nextInBounds) sourceBound
      simpa [nextInBounds] using
        nextBeforeEnd_evaluates source start cursor cursorBound
  · have cursorBound : cursor + 1 ≤ 2147483647 :=
      Nat.le_trans (Nat.le_of_lt nextInBounds) sourceBound
    have evaluated :=
      equalsNext_evaluates source start cursor 47 nextInBounds cursorBound
    have actual : source[cursor + 1].val = 47 := by
      simpa [List.get_eq_getElem] using isSlash
    have decided : decide
        ((source.get ⟨cursor + 1, nextInBounds⟩).val = 47) = true := by
      simpa [List.get_eq_getElem] using actual
    rw [decided] at evaluated
    exact evaluated

private theorem closes_evaluates_not_star
    (source : List Byte) (start cursor : Nat)
    (inBounds : cursor < source.length)
    (notStar : (source.get ⟨cursor, inBounds⟩).val ≠ 42) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment closes =
      .ok (.boolean false, (runtime source start cursor).world) := by
  unfold closes
  apply Term.evaluate_logicalAnd_false
  apply Term.evaluate_logicalAnd_false
  have evaluated := equalsCurrent_evaluates source start cursor 42 inBounds
  have actual : source[cursor].val ≠ 42 := by
    simpa [List.get_eq_getElem] using notStar
  have decided : decide ((source.get ⟨cursor, inBounds⟩).val = 42) = false := by
    simpa [List.get_eq_getElem] using actual
  rw [decided] at evaluated
  exact evaluated

private theorem closes_evaluates_no_next
    (source : List Byte) (start cursor : Nat)
    (inBounds : cursor < source.length)
    (isStar : (source.get ⟨cursor, inBounds⟩).val = 42)
    (nextOutOfBounds : ¬ cursor + 1 < source.length)
    (sourceBound : source.length ≤ 2147483647) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment closes =
      .ok (.boolean false, (runtime source start cursor).world) := by
  unfold closes
  apply Term.evaluate_logicalAnd_false
  apply Term.evaluate_logicalAnd_true
  · have evaluated := equalsCurrent_evaluates source start cursor 42 inBounds
    have actual : source[cursor].val = 42 := by
      simpa [List.get_eq_getElem] using isStar
    have decided : decide
        ((source.get ⟨cursor, inBounds⟩).val = 42) = true := by
      simpa [List.get_eq_getElem] using actual
    rw [decided] at evaluated
    exact evaluated
  · have cursorBound : cursor + 1 ≤ 2147483647 := by
      exact Nat.le_trans (by omega : cursor + 1 ≤ source.length) sourceBound
    simpa [nextOutOfBounds] using
      nextBeforeEnd_evaluates source start cursor cursorBound

private theorem closes_evaluates_not_slash
    (source : List Byte) (start cursor : Nat)
    (inBounds : cursor < source.length)
    (isStar : (source.get ⟨cursor, inBounds⟩).val = 42)
    (nextInBounds : cursor + 1 < source.length)
    (notSlash : (source.get ⟨cursor + 1, nextInBounds⟩).val ≠ 47)
    (sourceBound : source.length ≤ 2147483647) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment closes =
      .ok (.boolean false, (runtime source start cursor).world) := by
  unfold closes
  apply Term.evaluate_logicalAnd_true
  · apply Term.evaluate_logicalAnd_true
    · have evaluated := equalsCurrent_evaluates source start cursor 42 inBounds
      have actual : source[cursor].val = 42 := by
        simpa [List.get_eq_getElem] using isStar
      have decided : decide
          ((source.get ⟨cursor, inBounds⟩).val = 42) = true := by
        simpa [List.get_eq_getElem] using actual
      rw [decided] at evaluated
      exact evaluated
    · have cursorBound : cursor + 1 ≤ 2147483647 :=
        Nat.le_trans (Nat.le_of_lt nextInBounds) sourceBound
      simpa [nextInBounds] using
        nextBeforeEnd_evaluates source start cursor cursorBound
  · have cursorBound : cursor + 1 ≤ 2147483647 :=
      Nat.le_trans (Nat.le_of_lt nextInBounds) sourceBound
    have evaluated :=
      equalsNext_evaluates source start cursor 47 nextInBounds cursorBound
    have actual : source[cursor + 1].val ≠ 47 := by
      simpa [List.get_eq_getElem] using notSlash
    have decided : decide
        ((source.get ⟨cursor + 1, nextInBounds⟩).val = 47) = false := by
      simpa [List.get_eq_getElem] using actual
    rw [decided] at evaluated
    exact evaluated

private theorem successfulTerm_evaluates
    (source : List Byte) (start cursor : Nat)
    (bound : cursor + 2 ≤ 2147483647) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment successfulTerm =
      .ok (ScanEnd.value true (Int.ofNat (cursor + 2)) 0,
        (runtime source start cursor).world) := by
  unfold successfulTerm apply
  apply Term.evaluate_apply1
    (addCursor_evaluates source start cursor 2 bound)
  change ScanEndCalls.calls.evaluate (world source)
    Functions.successfulScanFunction.id
    [.signed .i32 (Int.ofNat (cursor + 2))] = _
  exact ScanEndCalls.successful (world source) (Int.ofNat (cursor + 2))

private theorem failedTerm_evaluates
    (source : List Byte) (start cursor : Nat) :
    Term.evaluate termMachine (runtime source start cursor).world
        (runtime source start cursor).environment failedTerm =
      .ok (ScanEnd.value false 0 (Int.ofNat source.length),
        (runtime source start cursor).world) := by
  unfold failedTerm apply
  apply Term.evaluate_apply1 (by rfl)
  change ScanEndCalls.calls.evaluate (world source)
    Functions.failedScanFunction.id
    [.signed .i32 (Int.ofNat source.length)] = _
  exact ScanEndCalls.failed (world source) (Int.ofNat source.length)

private theorem body_evaluates_close
    (source : List Byte) (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length)
    (isStar : (source.get ⟨cursor, inBounds⟩).val = 42)
    (nextInBounds : cursor + 1 < source.length)
    (isSlash : (source.get ⟨cursor + 1, nextInBounds⟩).val = 47) :
    Command.Evaluates termMachine statefulMachine
      (runtime source start cursor).world
      (runtime source start cursor).environment body
      (.returned (some
        (ScanEnd.value true (Int.ofNat (cursor + 2)) 0)))
      (runtime source start cursor).world
      (runtime source start cursor).environment := by
  have conditionResult := closes_evaluates_true source start cursor inBounds
    isStar nextInBounds isSlash sourceBound
  have returnResult : Command.Evaluates termMachine statefulMachine
      (runtime source start cursor).world
      (runtime source start cursor).environment
      (.returnValue (some successfulTerm))
      (.returned (some
        (ScanEnd.value true (Int.ofNat (cursor + 2)) 0)))
      (runtime source start cursor).world
      (runtime source start cursor).environment := by
    apply Command.Evaluates.returnSome
    apply successfulTerm_evaluates
    exact Nat.le_trans (by omega : cursor + 2 ≤ source.length) sourceBound
  have returnedBranch : Command.Evaluates termMachine statefulMachine
      (runtime source start cursor).world
      (runtime source start cursor).environment
      (.sequence (.returnValue (some successfulTerm)) .skip)
      (.returned (some
        (ScanEnd.value true (Int.ofNat (cursor + 2)) 0)))
      (runtime source start cursor).world
      (runtime source start cursor).environment :=
    .sequenceStop returnResult (by simp)
  have returnedIf : Command.Evaluates termMachine statefulMachine
      (runtime source start cursor).world
      (runtime source start cursor).environment
      (.ifThenElse closes
        (.sequence (.returnValue (some successfulTerm)) .skip) .skip)
      (.returned (some
        (ScanEnd.value true (Int.ofNat (cursor + 2)) 0)))
      (runtime source start cursor).world
      (runtime source start cursor).environment :=
    .ifTrue conditionResult returnedBranch
  exact .sequenceStop returnedIf (by simp)

private theorem body_evaluates_step
    (source : List Byte) (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length)
    (conditionResult : Term.evaluate termMachine
      (runtime source start cursor).world
      (runtime source start cursor).environment closes =
        .ok (.boolean false, (runtime source start cursor).world)) :
    Command.Evaluates termMachine statefulMachine
      (runtime source start cursor).world
      (runtime source start cursor).environment body .next
      (runtime source start (cursor + 1)).world
      (runtime source start (cursor + 1)).environment := by
  have afterWorld : (runtime source start (cursor + 1)).world =
      (runtime source start cursor).world := by rfl
  have afterEnvironment : (runtime source start (cursor + 1)).environment =
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
  rw [afterWorld, afterEnvironment]
  apply Command.Evaluates.sequenceNext
  · exact .ifFalse conditionResult .skip
  · apply Command.Evaluates.sequenceNext
    · have oneResult : Term.evaluate termMachine
          (runtime source start cursor).world
          (runtime source start cursor).environment (literalI32 1) =
          .ok (.signed .i32 1, (runtime source start cursor).world) := by rfl
      have cursorValue :
          (runtime source start cursor).environment ⟨3, by omega⟩ =
          .signed .i32 (Int.ofNat cursor) := by rfl
      have bound : cursor + 1 ≤ 2147483647 :=
        Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
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
        rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _ bound]
      exact Command.Evaluates.updateLocal oneResult (by
        simpa [statefulMachine, Stateful.machineWith] using updateResult)
    · exact .skip

private theorem loop_evaluates
    (source : List Byte) (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (cursorBound : cursor ≤ source.length) :
    (∃ _resultEq : scanBlockBody (source.drop cursor) cursor =
        .failure source.length,
      Command.Evaluates termMachine statefulMachine
        (runtime source start cursor).world
        (runtime source start cursor).environment loop .next
        (runtime source start source.length).world
        (runtime source start source.length).environment) ∨
    (∃ finalCursor,
      Command.Evaluates termMachine statefulMachine
        (runtime source start cursor).world
        (runtime source start cursor).environment loop
        (.returned (some
          (scanEndValue (scanBlockBody (source.drop cursor) cursor))))
        (runtime source start finalCursor).world
        (runtime source start finalCursor).environment) := by
  by_cases inBounds : cursor < source.length
  · have loopCondition := beforeEnd_evaluates source start cursor
    have loopConditionTrue : Term.evaluate termMachine
        (runtime source start cursor).world
        (runtime source start cursor).environment beforeEnd =
        .ok (.boolean true, (runtime source start cursor).world) := by
      simpa [inBounds] using loopCondition
    let byte := source.get ⟨cursor, inBounds⟩
    have dropped := List.drop_eq_getElem_cons inBounds
    by_cases isStar : byte.val = 42
    · by_cases nextInBounds : cursor + 1 < source.length
      · let nextByte := source.get ⟨cursor + 1, nextInBounds⟩
        by_cases isSlash : nextByte.val = 47
        · have closeCondition := closes_evaluates_true source start cursor
            inBounds (by simpa [byte] using isStar) nextInBounds
            (by simpa [nextByte] using isSlash) sourceBound
          have bodyResult := body_evaluates_close source start cursor sourceBound
            inBounds (by simpa [byte] using isStar) nextInBounds
            (by simpa [nextByte] using isSlash)
          have resultEq : scanBlockBody (source.drop cursor) cursor =
              .success (cursor + 2) := by
            rw [dropped, List.drop_eq_getElem_cons nextInBounds,
              scanBlockBody, if_pos]
            exact ⟨by simpa [byte] using isStar,
              by simpa [nextByte] using isSlash⟩
          right
          refine ⟨cursor, ?_⟩
          rw [resultEq]
          change Command.Evaluates termMachine statefulMachine
            (runtime source start cursor).world
            (runtime source start cursor).environment loop
            (.returned (some
              (ScanEnd.value true (Int.ofNat (cursor + 2)) 0)))
            (runtime source start cursor).world
            (runtime source start cursor).environment
          exact Command.Evaluates.whileReturn loopConditionTrue bodyResult
        · have closeCondition := closes_evaluates_not_slash source start cursor
            inBounds (by simpa [byte] using isStar) nextInBounds
            (by simpa [nextByte] using isSlash) sourceBound
          have bodyResult := body_evaluates_step source start cursor sourceBound
            inBounds closeCondition
          have notClose :
              ¬(source[cursor].val = 42 ∧ source[cursor + 1].val = 47) := by
            intro closesAt
            apply isSlash
            simpa [nextByte] using closesAt.2
          have stepResult : scanBlockBody (source.drop cursor) cursor =
              scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
            rw [dropped, List.drop_eq_getElem_cons nextInBounds,
              scanBlockBody, if_neg notClose]
          rcases loop_evaluates source start (cursor + 1) sourceBound
              (Nat.succ_le_of_lt inBounds) with
            ⟨resultEq, rest⟩ | ⟨finalCursor, rest⟩
          · left
            exact ⟨stepResult.trans resultEq,
              Command.Evaluates.whileNext loopConditionTrue bodyResult rest⟩
          · right
            refine ⟨finalCursor, ?_⟩
            rw [stepResult]
            exact Command.Evaluates.whileNext loopConditionTrue bodyResult rest
      · have closeCondition := closes_evaluates_no_next source start cursor
          inBounds (by simpa [byte] using isStar) nextInBounds sourceBound
        have bodyResult := body_evaluates_step source start cursor sourceBound
          inBounds closeCondition
        have droppedNext : source.drop (cursor + 1) = [] :=
          List.drop_eq_nil_of_le (Nat.le_of_not_gt nextInBounds)
        have stepResult : scanBlockBody (source.drop cursor) cursor =
            scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
          rw [dropped, droppedNext]
          rfl
        rcases loop_evaluates source start (cursor + 1) sourceBound
            (Nat.succ_le_of_lt inBounds) with
          ⟨resultEq, rest⟩ | ⟨finalCursor, rest⟩
        · left
          exact ⟨stepResult.trans resultEq,
            Command.Evaluates.whileNext loopConditionTrue bodyResult rest⟩
        · right
          refine ⟨finalCursor, ?_⟩
          rw [stepResult]
          exact Command.Evaluates.whileNext loopConditionTrue bodyResult rest
    · have closeCondition := closes_evaluates_not_star source start cursor
        inBounds (by simpa [byte] using isStar)
      have bodyResult := body_evaluates_step source start cursor sourceBound
        inBounds closeCondition
      have byteNotStar : source[cursor].val ≠ 42 := by
        simpa [byte] using isStar
      have stepResult : scanBlockBody (source.drop cursor) cursor =
          scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
        rw [dropped]
        cases tail : source.drop (cursor + 1) with
        | nil => rfl
        | cons next rest =>
            rw [scanBlockBody, if_neg]
            intro closesAt
            exact byteNotStar closesAt.1
      rcases loop_evaluates source start (cursor + 1) sourceBound
          (Nat.succ_le_of_lt inBounds) with
        ⟨resultEq, rest⟩ | ⟨finalCursor, rest⟩
      · left
        exact ⟨stepResult.trans resultEq,
          Command.Evaluates.whileNext loopConditionTrue bodyResult rest⟩
      · right
        refine ⟨finalCursor, ?_⟩
        rw [stepResult]
        exact Command.Evaluates.whileNext loopConditionTrue bodyResult rest
  · have atEnd : cursor = source.length :=
      Nat.le_antisymm cursorBound (Nat.le_of_not_gt inBounds)
    have loopCondition := beforeEnd_evaluates source start cursor
    have loopConditionFalse : Term.evaluate termMachine
        (runtime source start cursor).world
        (runtime source start cursor).environment beforeEnd =
        .ok (.boolean false, (runtime source start cursor).world) := by
      simpa [inBounds] using loopCondition
    left
    refine ⟨?_, ?_⟩
    · simp [atEnd, scanBlockBody]
    · simpa [loop, atEnd] using
        (Command.Evaluates.whileFalse (body := body) loopConditionFalse)
termination_by source.length - cursor
decreasing_by all_goals omega

private def parameterEnvironment (source : List Byte) (start : Nat) : Env 3
  | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)

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
  have loopResult := loop_evaluates source start initialCursor sourceBound
    initialCursorBound
  have bodyResult : ∃ finalCursor,
      Command.Evaluates termMachine statefulMachine
        (runtime source start initialCursor).world
        (runtime source start initialCursor).environment
        (.sequence loop
          (.sequence (.returnValue (some failedTerm)) .skip))
        (.returned (some
          (scanEndValue (scanBlockBody (source.drop initialCursor)
            initialCursor))))
        (runtime source start finalCursor).world
        (runtime source start finalCursor).environment := by
    rcases loopResult with ⟨resultEq, loopExecution⟩ |
        ⟨finalCursor, loopExecution⟩
    · refine ⟨source.length, ?_⟩
      have failedResult := failedTerm_evaluates source start source.length
      have returned : Command.Evaluates termMachine statefulMachine
          (runtime source start source.length).world
          (runtime source start source.length).environment
          (.returnValue (some failedTerm))
          (.returned (some
            (ScanEnd.value false 0 (Int.ofNat source.length))))
          (runtime source start source.length).world
          (runtime source start source.length).environment :=
        .returnSome failedResult
      have returnedWithSkip : Command.Evaluates termMachine statefulMachine
          (runtime source start source.length).world
          (runtime source start source.length).environment
          (.sequence (.returnValue (some failedTerm)) .skip)
          (.returned (some
            (ScanEnd.value false 0 (Int.ofNat source.length))))
          (runtime source start source.length).world
          (runtime source start source.length).environment :=
        .sequenceStop returned (by simp)
      rw [resultEq]
      change Command.Evaluates termMachine statefulMachine
        (runtime source start initialCursor).world
        (runtime source start initialCursor).environment
        (.sequence loop
          (.sequence (.returnValue (some failedTerm)) .skip))
        (.returned (some
          (ScanEnd.value false 0 (Int.ofNat source.length))))
        (runtime source start source.length).world
        (runtime source start source.length).environment
      exact .sequenceNext loopExecution returnedWithSkip
    · refine ⟨finalCursor, ?_⟩
      exact .sequenceStop loopExecution (by simp)
  obtain ⟨finalCursor, bodyExecution⟩ := bodyResult
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

private def localCells : Fin 3 → CellId :=
  fun index => index.val + 1

private theorem scannerParameterState_represents
    (source : List Byte) (start : Nat) :
    Representation identityLayout localCells (world source)
      (parameterEnvironment source start)
      (scannerParameterState source start) := by
  have wellFormed := scannerParameterState_well_formed source start
  refine {
    worldOwned := ?_
    localOwned := ?_
    localCellsInjective := ?_
    worldLocalsDisjoint := ?_
  }
  · change (World.owns
      (World.singleton 0 (sourceIntegers source))).holds
      (scannerParameterState source start)
    rw [World.owns_iff_represents wellFormed]
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
      · simp [world, World.singleton, same] at found
    subst cell
    obtain ⟨index, localZero⟩ := localMember
    have positive : 0 < localCells index := by
      simp [localCells]
    exact (Nat.ne_of_gt positive) localZero

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
