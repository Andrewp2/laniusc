import Lanius.Extraction.Lexer.Relational.SourceMemory
import Lanius.Relational.SemanticWP
import Lanius.Relational.OperationRegistry
import Lanius.Extraction.Lexer.Relational.PredicateContracts
import Lanius.Extraction.Lexer.Relational.IdentifierEndStructure

namespace Lanius.Extraction.Lexer.Relational.ScannerWP

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.Relational
open Lanius.Relational.Semantics
open Lanius.Relational.SemanticWP

private abbrev T (arity : Nat) := Term Core.signature arity
private abbrev C (arity : Nat) := Stateful.Command Core.signature Stateful.actions arity

def sourceTerm : T 4 := reference ⟨0, by omega⟩
def boundTerm : T 4 := reference ⟨1, by omega⟩
def cursorTerm : T 4 := reference ⟨3, by omega⟩

def predicateTerm
    (function : checkedFrontend.FnRef Functions.predicateSignature) : T 4 :=
  apply (.call function.function.id [i32Type] (.scalar .bool))
    [apply (.index (.slice i32Type) i32Type i32Type)
      [sourceTerm, cursorTerm]]

def loopCondition
    (function : checkedFrontend.FnRef Functions.predicateSignature) : T 4 :=
  logicalAnd
    (apply (.binary .less i32Type i32Type (.scalar .bool))
      [cursorTerm, boundTerm])
    (predicateTerm function)

def loopBody : C 4 :=
  .sequence
    (.updateLocal .add ⟨3, by omega⟩ (literal (.signed .i32 1)))
    .skip

def command
    (function : checkedFrontend.FnRef Functions.predicateSignature) : C 3 :=
  IdentifierEnd.Structure.proofCommand function.function.id

def parameterEnvironment (source : List Byte) (start : Nat) : Env 3
  | ⟨0, _⟩ => SourceMemory.sourceSlice source
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)

def loopEnvironment (source : List Byte) (start cursor : Nat) : Env 4
  | ⟨0, _⟩ => SourceMemory.sourceSlice source
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat cursor)

def entry (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    SpecEntry function where
  contract := PredicateContracts.contract source function accept
  sound := correct

def registry (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) : OperationRegistry :=
  OperationRegistry.readOnly (entry source function accept correct).callRelation

def machine (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :=
  (registry source function accept correct).machine checkedFrontend.core

def runtime (source : List Byte) (start cursor : Nat) :
    SemanticWP.Command.Runtime ReadOnly.World 4 :=
  (SourceMemory.sourceWorld source, loopEnvironment source start cursor)

def accepts (source : List Byte) (accept : Byte → Bool)
    (cursor : Nat) : Bool :=
  (source[cursor]?.map accept).getD false

theorem recurrence (source : List Byte) (accept : Byte → Bool) :
    Stateful.Loop.CursorScan.Recurrence source.length (accepts source accept)
      (scanAcceptedFrom accept source) := by
  constructor
  · exact scanAcceptedFrom_out_of_bounds accept source
  · intro cursor inBounds rejected
    apply scanAcceptedFrom_rejected accept source cursor inBounds
    simpa [accepts, List.getElem?_eq_getElem inBounds] using rejected
  · intro cursor inBounds accepted
    apply scanAcceptedFrom_accepted accept source cursor inBounds
    simpa [accepts, List.getElem?_eq_getElem inBounds] using accepted

theorem less_result
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat)
    (evaluated : TermEvaluates (machine source function accept correct)
      (SourceMemory.sourceWorld source) (loopEnvironment source start cursor)
      (apply (.binary .less i32Type i32Type (.scalar .bool))
        [cursorTerm, boundTerm]) value afterWorld) :
    value = .boolean (decide (cursor < source.length)) ∧
      afterWorld = SourceMemory.sourceWorld source := by
  obtain ⟨values, afterArguments, argumentsResult, operationResult⟩ :=
    evaluated.applyInversion
  obtain ⟨cursorValue, restValues, afterCursor, valuesEq, cursorResult,
      restResult⟩ := argumentsResult.consInversion
  obtain ⟨boundValue, tailValues, afterBound, restValuesEq, boundResult,
      tailResult⟩ := restResult.consInversion
  obtain ⟨tailValuesEq, afterBoundEq⟩ := tailResult.nilInversion
  obtain ⟨cursorValueEq, afterCursorEq⟩ := cursorResult.referenceInversion
  obtain ⟨boundValueEq, afterBoundWorldEq⟩ := boundResult.referenceInversion
  subst values
  subst restValues
  subst tailValues
  subst cursorValue
  subst boundValue
  subst afterCursor
  subst afterBound
  subst afterArguments
  simp [machine, registry, OperationRegistry.machine,
    loopEnvironment, Ref.evaluate, ReadOnly.evaluateOperation,
    Lanius.Semantics.evalBinaryValue,
    Lanius.Semantics.evalSignedBinary, bind, Except.bind] at operationResult
  exact ⟨operationResult.1.symm, operationResult.2.symm⟩

private theorem index_result
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) (inBounds : cursor < source.length)
    (evaluated : TermEvaluates (machine source function accept correct)
      (SourceMemory.sourceWorld source) (loopEnvironment source start cursor)
      (apply (.index (.slice i32Type) i32Type i32Type)
        [sourceTerm, cursorTerm]) value afterWorld) :
    value = .signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val) ∧
      afterWorld = SourceMemory.sourceWorld source := by
  obtain ⟨values, afterArguments, argumentsResult, operationResult⟩ :=
    evaluated.applyInversion
  obtain ⟨sourceValue, restValues, afterSource, valuesEq, sourceResult,
      restResult⟩ := argumentsResult.consInversion
  obtain ⟨cursorValue, tailValues, afterCursor, restValuesEq, cursorResult,
      tailResult⟩ := restResult.consInversion
  obtain ⟨tailValuesEq, afterCursorEq⟩ := tailResult.nilInversion
  obtain ⟨sourceValueEq, afterSourceEq⟩ := sourceResult.referenceInversion
  obtain ⟨cursorValueEq, afterCursorWorldEq⟩ := cursorResult.referenceInversion
  subst values
  subst restValues
  subst tailValues
  subst sourceValue
  subst cursorValue
  subst afterSource
  subst afterCursor
  subst afterArguments
  have cursorNonnegative : ¬ ((cursor : Int) < 0) := by
    exact Int.not_lt_of_ge (Int.natCast_nonneg cursor)
  simp [machine, registry, OperationRegistry.machine,
    loopEnvironment, Ref.evaluate,
    ReadOnly.evaluateOperation, ReadOnly.readI32Slice,
    SourceMemory.sourceSlice, SourceMemory.sourceIntegers, SourceMemory.sourceWorld_finds,
    inBounds, cursorNonnegative, bind, Except.bind]
    at operationResult
  exact ⟨operationResult.1.symm, operationResult.2.symm⟩

private theorem predicate_result
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) (inBounds : cursor < source.length)
    (evaluated : TermEvaluates (machine source function accept correct)
      (SourceMemory.sourceWorld source) (loopEnvironment source start cursor)
      (predicateTerm function) value afterWorld) :
    value = .boolean (accept (source.get ⟨cursor, inBounds⟩)) ∧
      afterWorld = SourceMemory.sourceWorld source := by
  obtain ⟨values, afterArguments, argumentsResult, operationResult⟩ :=
    evaluated.applyInversion
  obtain ⟨argumentValue, tailValues, afterArgument, valuesEq,
      actualArgument, tailResult⟩ := argumentsResult.consInversion
  obtain ⟨tailValuesEq, afterArgumentsEq⟩ := tailResult.nilInversion
  obtain ⟨argumentEq, argumentWorldEq⟩ :=
    index_result source function accept correct start cursor inBounds
      actualArgument
  subst values
  subst tailValues
  subst argumentValue
  subst afterArgument
  subst afterArguments
  simp only [machine, registry, OperationRegistry.machine] at operationResult
  rcases operationResult with ⟨_functionEq, byte, before, result, after,
    argumentsEq, valueEq, pre, beforeRep, post, frame, afterRep⟩
  change [Value.signed .i32
    (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)] =
      [Value.signed .i32 (Int.ofNat byte.val)] at argumentsEq
  change value = .boolean result at valueEq
  change before.2 = source at pre
  change before.1 = SourceMemory.sourceWorld source ∧
    (SourceMemory.sourceWorld source).i32Slice? 0 =
      some (SourceMemory.sourceIntegers before.2) at beforeRep
  change result = accept byte ∧ after = before at post
  change after = before at frame
  change after.1 = afterWorld ∧ afterWorld.i32Slice? 0 =
    some (SourceMemory.sourceIntegers after.2) at afterRep
  have byteValueEq : Int.ofNat (source.get ⟨cursor, inBounds⟩).val =
      Int.ofNat byte.val := by
    simpa using argumentsEq
  have byteEq : byte = source.get ⟨cursor, inBounds⟩ := by
    have natEq : (source.get ⟨cursor, inBounds⟩).val = byte.val := by
      exact Int.ofNat.inj byteValueEq
    exact Fin.ext natEq.symm
  subst byte
  obtain ⟨resultEq, afterEq⟩ := post
  subst result
  subst after
  obtain ⟨beforeWorldEq, _beforeFound⟩ := beforeRep
  obtain ⟨afterWorldEq, _afterFound⟩ := afterRep
  exact ⟨valueEq, afterWorldEq.symm.trans beforeWorldEq⟩

theorem condition_in_bounds
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) (inBounds : cursor < source.length) :
    SemanticWP.Term.WP (machine source function accept correct)
      (loopCondition function)
      (fun value afterWorld =>
        value = .boolean (accepts source accept cursor) ∧
        afterWorld = SourceMemory.sourceWorld source)
      (SourceMemory.sourceWorld source) (loopEnvironment source start cursor) := by
  intro value afterWorld evaluated
  rcases evaluated.logicalAndInversion with
    ⟨valueEq, leftResult⟩ | ⟨afterLeft, leftResult, rightResult⟩
  · obtain ⟨leftEq, _worldEq⟩ :=
      less_result source function accept correct start cursor leftResult
    have decided : decide (cursor < source.length) = true := by simp [inBounds]
    rw [decided] at leftEq
    simp at leftEq
  · obtain ⟨_leftEq, afterLeftEq⟩ :=
      less_result source function accept correct start cursor leftResult
    subst afterLeft
    obtain ⟨resultEq, worldEq⟩ :=
      predicate_result source function accept correct start cursor inBounds
        rightResult
    exact ⟨by
      simpa [accepts, List.getElem?_eq_getElem inBounds] using resultEq,
      worldEq⟩

theorem condition_out_of_bounds
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) (outOfBounds : ¬ cursor < source.length) :
    SemanticWP.Term.WP (machine source function accept correct)
      (loopCondition function)
      (fun value afterWorld =>
        value = .boolean false ∧ afterWorld = SourceMemory.sourceWorld source)
      (SourceMemory.sourceWorld source) (loopEnvironment source start cursor) := by
  intro value afterWorld evaluated
  rcases evaluated.logicalAndInversion with
    ⟨valueEq, leftResult⟩ | ⟨afterLeft, leftResult, rightResult⟩
  · obtain ⟨_leftEq, worldEq⟩ :=
      less_result source function accept correct start cursor leftResult
    exact ⟨valueEq, worldEq⟩
  · obtain ⟨leftEq, _worldEq⟩ :=
      less_result source function accept correct start cursor leftResult
    have decided : decide (cursor < source.length) = false := by
      simp [outOfBounds]
    rw [decided] at leftEq
    simp at leftEq

theorem body_wp
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length) :
    SemanticWP.Command.WP (machine source function accept correct) loopBody
      (fun completion afterWorld afterEnvironment =>
        completion = .next ∧
        afterWorld = SourceMemory.sourceWorld source ∧
        afterEnvironment = loopEnvironment source start (cursor + 1))
      (SourceMemory.sourceWorld source) (loopEnvironment source start cursor) := by
  apply SemanticWP.Command.sequence
  apply SemanticWP.Command.updateLocal
  intro right afterWorld rightResult
  obtain ⟨rightEq, afterWorldEq⟩ := rightResult.referenceInversion
  subst right
  subst afterWorld
  intro result updateResult
  have resultEq : result = .signed .i32 (Int.ofNat (cursor + 1)) := by
    change Lanius.Semantics.evalAssignValue checkedFrontend.core.target .add
      (some (.signed .i32 (Int.ofNat cursor))) (.signed .i32 1) =
        .ok result at updateResult
    simp only [Lanius.Semantics.evalAssignValue,
      Lanius.Semantics.assignOpBinary?, Lanius.Semantics.evalBinaryValue,
      beq_self_eq_true, if_true, Lanius.Semantics.evalSignedBinary]
      at updateResult
    have addition : Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) := by simp
    rw [addition] at updateResult
    rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _
      (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)] at updateResult
    exact (Except.ok.inj updateResult).symm
  subst result
  apply SemanticWP.Command.skip
  refine ⟨rfl, rfl, ?_⟩
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
    simp [loopEnvironment, Stateful.Env.set]

private theorem spec
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start : Nat) (sourceBound : source.length ≤ 2147483647) :
    SemanticWP.Command.CursorScan.Spec
      (machine source function accept correct)
      (loopCondition function) loopBody (runtime source start)
      source.length (accepts source accept) where
  conditionInBounds := fun cursor inBounds =>
    condition_in_bounds source function accept correct start cursor inBounds
  conditionOutOfBounds := fun cursor outOfBounds =>
    condition_out_of_bounds source function accept correct start cursor
      outOfBounds
  body := fun cursor inBounds _accepted =>
    body_wp source function accept correct start cursor sourceBound inBounds

theorem initializer_wp
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start : Nat) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    SemanticWP.Term.WP (machine source function accept correct)
      (apply (.binary .add i32Type i32Type i32Type)
        [reference ⟨2, by omega⟩, literal (.signed .i32 1)])
      (fun value afterWorld =>
        value = .signed .i32 (Int.ofNat (start + 1)) ∧
        afterWorld = SourceMemory.sourceWorld source)
      (SourceMemory.sourceWorld source) (parameterEnvironment source start) := by
  intro value afterWorld evaluated
  obtain ⟨values, afterArguments, argumentsResult, operationResult⟩ :=
    evaluated.applyInversion
  obtain ⟨startValue, restValues, afterStart, valuesEq, startResult,
      restResult⟩ := argumentsResult.consInversion
  obtain ⟨oneValue, tailValues, afterOne, restValuesEq, oneResult,
      tailResult⟩ := restResult.consInversion
  obtain ⟨tailValuesEq, afterArgumentsEq⟩ := tailResult.nilInversion
  obtain ⟨startValueEq, afterStartEq⟩ := startResult.referenceInversion
  obtain ⟨oneValueEq, afterOneEq⟩ := oneResult.referenceInversion
  subst values
  subst restValues
  subst tailValues
  subst startValue
  subst oneValue
  subst afterStart
  subst afterOne
  subst afterArguments
  change ReadOnly.evaluateOperation checkedFrontend.core
      (SourceMemory.sourceWorld source)
      (.binary .add i32Type i32Type i32Type)
      [.signed .i32 (Int.ofNat start), .signed .i32 1] =
    .ok (value, afterWorld) at operationResult
  simp only [ReadOnly.evaluateOperation,
    Lanius.Semantics.evalBinaryValue, Lanius.Semantics.evalSignedBinary]
    at operationResult
  have addition : Int.ofNat start + 1 = Int.ofNat (start + 1) := by simp
  rw [addition] at operationResult
  rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _
    (Nat.le_trans (Nat.succ_le_of_lt startInBounds) sourceBound)]
    at operationResult
  have pairEq := Except.ok.inj operationResult
  exact ⟨(congrArg Prod.fst pairEq).symm,
    (congrArg Prod.snd pairEq).symm⟩

/-- Reusable relational partial-correctness rule for both scanner pilots.
The predicate operation is supplied by a proved contract entry; no executable
call interpreter or whole-loop execution trace occurs in this theorem. -/
theorem command_wp
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start : Nat) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    SemanticWP.Command.WP (machine source function accept correct)
      (command function)
      (fun completion afterWorld _afterEnvironment =>
        completion = .returned (some (.signed .i32 (Int.ofNat
          (scanAcceptedFrom accept source (start + 1))))) ∧
        afterWorld = SourceMemory.sourceWorld source)
      (SourceMemory.sourceWorld source) (parameterEnvironment source start) := by
  unfold command IdentifierEnd.Structure.proofCommand
  apply SemanticWP.Command.letValue
  intro value initializedWorld evaluated
  obtain ⟨valueEq, worldEq⟩ :=
    initializer_wp source function accept correct start sourceBound
      startInBounds value initializedWorld evaluated
  subst value
  subst initializedWorld
  have pushed : (parameterEnvironment source start).push
      (.signed .i32 (Int.ofNat (start + 1))) =
      loopEnvironment source start (start + 1) := by
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
  rw [pushed]
  apply SemanticWP.Command.sequence
  intro completion loopWorld loopEnvironment' loopResult
  have loopWP := SemanticWP.Command.cursorScan
    (spec source function accept correct start sourceBound)
    (recurrence source accept) (start + 1)
  obtain ⟨completionEq, loopWorldEq, loopEnvironmentEq⟩ :=
    loopWP completion loopWorld loopEnvironment' loopResult
  subst completion
  subst loopWorld
  subst loopEnvironment'
  apply SemanticWP.Command.sequence
  apply SemanticWP.Command.returnSome
  intro result returnWorld returnResult
  obtain ⟨resultEq, returnWorldEq⟩ := returnResult.referenceInversion
  subst result
  subst returnWorld
  exact ⟨rfl, rfl⟩

theorem identifierView_wp
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    SemanticWP.Command.WP
      (machine source Functions.isIdentifierContinue isIdentifierContinue
        (PredicateContracts.identifier_returnsCorrectly source))
      Scanners.scanIdentifierEndView.command
      (fun completion afterWorld _afterEnvironment =>
        completion = .returned (some (.signed .i32
          (Int.ofNat (scanIdentifierEnd source start)))) ∧
        afterWorld = SourceMemory.sourceWorld source)
      (SourceMemory.sourceWorld source) (parameterEnvironment source start) := by
  rw [IdentifierEnd.Structure.identifierProofCommand]
  simpa [command, Functions.isIdentifierContinue, scanAcceptedFrom,
    Lanius.Compiler.Lexer.scanIdentifierEnd]
    using command_wp source Functions.isIdentifierContinue
      isIdentifierContinue
      (PredicateContracts.identifier_returnsCorrectly source)
      start sourceBound startInBounds

theorem whitespaceView_wp
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    SemanticWP.Command.WP
      (machine source Functions.isWhitespace isWhitespace
        (PredicateContracts.whitespace_returnsCorrectly source))
      Scanners.scanWhitespaceEndView.command
      (fun completion afterWorld _afterEnvironment =>
        completion = .returned (some (.signed .i32
          (Int.ofNat (scanWhitespaceEnd source start)))) ∧
        afterWorld = SourceMemory.sourceWorld source)
      (SourceMemory.sourceWorld source) (parameterEnvironment source start) := by
  rw [IdentifierEnd.Structure.whitespaceProofCommand]
  simpa [command, Functions.isWhitespace, scanAcceptedFrom,
    Lanius.Compiler.Lexer.scanWhitespaceEnd]
    using command_wp source Functions.isWhitespace isWhitespace
      (PredicateContracts.whitespace_returnsCorrectly source)
      start sourceBound startInBounds

end Lanius.Extraction.Lexer.Relational.ScannerWP
