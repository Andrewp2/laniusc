import Lanius.Extraction.Lexer.Relational.SourceMemory
import Lanius.Relational.LeafMigration
import Lanius.Extraction.Lexer.Relational.ScannerWP

namespace Lanius.Extraction.Lexer.Relational.ScannerReflection

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Separation
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Relational
open Lanius.Relational.Semantics
open Lanius.CallContracts

private abbrev Initializer : Term Core.signature 3 :=
  apply (.binary .add i32Type i32Type i32Type)
    [reference ⟨2, by omega⟩, literal (.signed .i32 1)]

private def rejectingCalls : Effectful.CallModel where
  evaluate := fun _ _ _ => .error .invalidPointer

private theorem rejectingCalls_sound :
    FramePreservingCallSoundness checkedFrontend.core rejectingCalls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  simp [rejectingCalls] at evaluated

/-- Source-level entry condition used by the invariant-aware structural
reflector. It mentions only the read-only world and functional environment. -/
def Admissible (source : List Byte) (world : ReadOnly.World)
    (environment : Env 3) : Prop :=
  ∃ start : Nat,
    source.length ≤ 2147483647 ∧ start < source.length ∧
    world = SourceMemory.sourceWorld source ∧
    environment = ScannerWP.parameterEnvironment source start

private theorem initializer_executable
    (source : List Byte)
    (start : Nat) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    FunctionalView.Term.evaluate
      (Effectful.machine checkedFrontend.core rejectingCalls)
      (SourceMemory.sourceWorld source) (ScannerWP.parameterEnvironment source start)
      Initializer =
      .ok (.signed .i32 (Int.ofNat (start + 1)), SourceMemory.sourceWorld source) := by
  calc
    _ = FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core)
        (SourceMemory.sourceWorld source) (ScannerWP.parameterEnvironment source start)
        Initializer :=
      Effectful.Term.evaluate_eq_readOnly_of_callFree
        (program := checkedFrontend.core)
        (calls := rejectingCalls) _ (by rfl)
    _ = _ := by
      exact ReadOnly.Term.evaluate_i32_add
        (program := checkedFrontend.core) (world := SourceMemory.sourceWorld source)
        (environment := ScannerWP.parameterEnvironment source start)
        (leftType := i32Type) (rightType := i32Type)
        (outputType := i32Type)
        (left := reference ⟨2, by omega⟩)
        (right := literal (.signed .i32 1))
        (leftValue := start) (rightValue := 1) (by rfl) (by rfl)
        (Nat.le_trans (Nat.succ_le_of_lt startInBounds) sourceBound)

private theorem initializer_relational
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start : Nat) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    TermEvaluates (ScannerWP.machine source function accept correct)
      (SourceMemory.sourceWorld source) (ScannerWP.parameterEnvironment source start)
      Initializer (.signed .i32 (Int.ofNat (start + 1)))
      (SourceMemory.sourceWorld source) := by
  apply TermEvaluates.apply
  · exact .cons (.reference _) (.cons (.reference _) .nil)
  · change ReadOnly.evaluateOperation checkedFrontend.core
      (SourceMemory.sourceWorld source) (.binary .add i32Type i32Type i32Type)
      [.signed .i32 (Int.ofNat start), .signed .i32 1] =
        .ok (.signed .i32 (Int.ofNat (start + 1)), SourceMemory.sourceWorld source)
    simp only [ReadOnly.evaluateOperation, evalBinaryValue, evalSignedBinary,
      beq_self_eq_true, if_true, bind, Except.bind]
    have addition : Int.ofNat start + 1 = Int.ofNat (start + 1) := by simp
    rw [addition]
    rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _
      (Nat.le_trans (Nat.succ_le_of_lt startInBounds) sourceBound)]

theorem initializer_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.TermReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (Admissible source) Initializer := by
  apply LeafMigration.termReflectsWhen
    (FreshSimulation.operationSoundness checkedFrontend.core
      rejectingCalls rejectingCalls_sound)
  · intro world environment input
    obtain ⟨start, sourceBound, startInBounds, rfl, rfl⟩ := input
    exact ⟨_, _, initializer_executable source start
      sourceBound startInBounds⟩
  · intro world environment input value afterWorld evaluated
    obtain ⟨start, sourceBound, startInBounds, rfl, rfl⟩ := input
    have canonical := initializer_executable source start
      sourceBound startInBounds
    have same := evaluated.symm.trans canonical
    injection same with pairEq
    have valueEq := congrArg Prod.fst pairEq
    have worldEq := congrArg Prod.snd pairEq
    change value = .signed .i32 (Int.ofNat (start + 1)) at valueEq
    change afterWorld = SourceMemory.sourceWorld source at worldEq
    subst value
    subst afterWorld
    exact initializer_relational source function accept correct start sourceBound
      startInBounds

private theorem less_relational
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) :
    TermEvaluates (ScannerWP.machine source function accept correct)
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      (apply (.binary .less i32Type i32Type (.scalar .bool))
        [ScannerWP.cursorTerm, ScannerWP.boundTerm])
      (.boolean (decide (cursor < source.length)))
      (SourceMemory.sourceWorld source) := by
  apply TermEvaluates.apply
  · exact .cons (.reference _) (.cons (.reference _) .nil)
  · change ReadOnly.evaluateOperation checkedFrontend.core
      (SourceMemory.sourceWorld source) (.binary .less i32Type i32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat cursor),
        .signed .i32 (Int.ofNat source.length)] =
      .ok (.boolean (decide (cursor < source.length)), SourceMemory.sourceWorld source)
    simp [ReadOnly.evaluateOperation, evalBinaryValue, evalSignedBinary,
      bind, Except.bind]

private theorem index_relational
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) (inBounds : cursor < source.length) :
    TermEvaluates (ScannerWP.machine source function accept correct)
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      (apply (.index (.slice i32Type) i32Type i32Type)
        [ScannerWP.sourceTerm, ScannerWP.cursorTerm])
      (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))
      (SourceMemory.sourceWorld source) := by
  apply TermEvaluates.apply
  · exact .cons (.reference _) (.cons (.reference _) .nil)
  · change ReadOnly.evaluateOperation checkedFrontend.core
      (SourceMemory.sourceWorld source) (.index (.slice i32Type) i32Type i32Type)
      [SourceMemory.sourceSlice source, .signed .i32 (Int.ofNat cursor)] =
      .ok (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val),
        SourceMemory.sourceWorld source)
    have cursorNonnegative : ¬ ((cursor : Int) < 0) := by omega
    simp [ReadOnly.evaluateOperation, ReadOnly.readI32Slice,
      SourceMemory.sourceSlice, SourceMemory.sourceIntegers, SourceMemory.sourceWorld_finds,
      inBounds, cursorNonnegative, bind, Except.bind]

private theorem predicate_relational
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) (inBounds : cursor < source.length) :
    TermEvaluates (ScannerWP.machine source function accept correct)
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      (ScannerWP.predicateTerm function)
      (.boolean (accept (source.get ⟨cursor, inBounds⟩)))
      (SourceMemory.sourceWorld source) := by
  apply TermEvaluates.apply
  · exact .cons
      (index_relational source function accept correct start cursor inBounds) .nil
  · change (ScannerWP.entry source function accept correct).callRelation
      (SourceMemory.sourceWorld source) function.function.id
      [.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)]
      (.boolean (accept (source.get ⟨cursor, inBounds⟩)))
      (SourceMemory.sourceWorld source)
    refine ⟨rfl, ?_⟩
    refine ⟨source.get ⟨cursor, inBounds⟩,
      (SourceMemory.sourceWorld source, source),
      accept (source.get ⟨cursor, inBounds⟩),
      (SourceMemory.sourceWorld source, source), rfl, rfl, rfl, ?_, ?_, rfl, ?_⟩
    · exact ⟨rfl, SourceMemory.sourceWorld_finds source⟩
    · exact ⟨rfl, rfl⟩
    · exact ⟨rfl, SourceMemory.sourceWorld_finds source⟩

theorem condition_relational_in_bounds
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) (inBounds : cursor < source.length) :
    TermEvaluates (ScannerWP.machine source function accept correct)
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      (ScannerWP.loopCondition function)
      (.boolean (accept (source.get ⟨cursor, inBounds⟩)))
      (SourceMemory.sourceWorld source) := by
  apply TermEvaluates.logicalAndTrue
  · simpa [inBounds] using
      less_relational source function accept correct start cursor
  · exact predicate_relational source function accept correct start cursor
      inBounds

theorem condition_relational_out_of_bounds
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) (outOfBounds : ¬ cursor < source.length) :
    TermEvaluates (ScannerWP.machine source function accept correct)
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      (ScannerWP.loopCondition function) (.boolean false)
      (SourceMemory.sourceWorld source) := by
  apply TermEvaluates.logicalAndFalse
  simpa [outOfBounds] using
    less_relational source function accept correct start cursor

theorem condition_relational
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat) :
    ∃ value,
      TermEvaluates (ScannerWP.machine source function accept correct)
        (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
        (ScannerWP.loopCondition function) value (SourceMemory.sourceWorld source) := by
  by_cases inBounds : cursor < source.length
  · exact ⟨_, condition_relational_in_bounds source function accept correct
      start cursor inBounds⟩
  · exact ⟨_, condition_relational_out_of_bounds source function accept correct
      start cursor inBounds⟩


def LoopInvariant (source : List Byte) (world : ReadOnly.World)
    (environment : Env 4) : Prop :=
  ∃ start cursor : Nat,
    source.length ≤ 2147483647 ∧
    world = SourceMemory.sourceWorld source ∧
    environment = ScannerWP.loopEnvironment source start cursor

def BodyAdmissible (source : List Byte) (world : ReadOnly.World)
    (environment : Env 4) : Prop :=
  ∃ start cursor : Nat,
    source.length ≤ 2147483647 ∧ cursor < source.length ∧
    world = SourceMemory.sourceWorld source ∧
    environment = ScannerWP.loopEnvironment source start cursor

private theorem index_executable
    (source : List Byte) (start cursor : Nat)
    (inBounds : cursor < source.length) :
    FunctionalView.Term.evaluate
      (Effectful.machine checkedFrontend.core rejectingCalls)
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      (apply (.index (.slice i32Type) i32Type i32Type)
        [ScannerWP.sourceTerm, ScannerWP.cursorTerm]) =
      .ok (.signed .i32
        (Int.ofNat (source.get ⟨cursor, inBounds⟩).val),
        SourceMemory.sourceWorld source) := by
  calc
    _ = FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core)
        (SourceMemory.sourceWorld source)
        (ScannerWP.loopEnvironment source start cursor)
        (apply (.index (.slice i32Type) i32Type i32Type)
          [ScannerWP.sourceTerm, ScannerWP.cursorTerm]) :=
      Effectful.Term.evaluate_eq_readOnly_of_callFree
        (program := checkedFrontend.core) (calls := rejectingCalls) _
        (by decide +kernel)
    _ = _ := by
      apply ReadOnly.Term.evaluate_i32_index_as
        (cell := 0) (values := SourceMemory.sourceIntegers source)
        (position := cursor)
        (expected := Int.ofNat (source.get ⟨cursor, inBounds⟩).val)
      · change Except.ok (SourceMemory.sourceSlice source, SourceMemory.sourceWorld source) =
          Except.ok (.slice (.scalar (.signed .i32)) 0 [] 0
            (SourceMemory.sourceIntegers source).length, SourceMemory.sourceWorld source)
        simp [SourceMemory.sourceSlice, SourceMemory.sourceIntegers]
      · rfl
      · exact SourceMemory.sourceWorld_finds source
      · simp [SourceMemory.sourceIntegers]
      · simpa [SourceMemory.sourceIntegers] using inBounds

private theorem predicate_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.TermReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (BodyAdmissible source) (ScannerWP.predicateTerm function) := by
  intro layout localCell world environment before after frontier value
    wellFormed represented input actual
  obtain ⟨start, cursor, sourceBound, inBounds, rfl, rfl⟩ := input
  let byte := source.get ⟨cursor, inBounds⟩
  have indexEvaluation := index_executable source start cursor inBounds
  obtain ⟨afterArguments, argumentExecution, afterArgumentsWellFormed,
      afterArgumentsRepresented, argumentEffect⟩ :=
    FreshSimulation.termSoundness
      (FreshSimulation.operationSoundness checkedFrontend.core rejectingCalls
        rejectingCalls_sound)
      wellFormed represented indexEvaluation
  have argumentsExecution : ArgumentsEvaluateTo checkedFrontend.core before
      [Core.toCoreExpr layout
        (apply (.index (.slice i32Type) i32Type i32Type)
          [ScannerWP.sourceTerm, ScannerWP.cursorTerm])]
      [.signed .i32 (Int.ofNat byte.val)] afterArguments :=
    ArgumentsEvaluateTo.singleton argumentExecution
  have abstractBeforeRep :
      (PredicateContracts.contract source function accept).AbstractStateRep
        (SourceMemory.sourceWorld source, source) (SourceMemory.sourceWorld source) :=
    ⟨rfl, SourceMemory.sourceWorld_finds source⟩
  obtain ⟨result, abstractAfter, afterWorld, valueEq, abstractAfterRep,
      post, frame, afterWellFormed, afterRepresented, effect⟩ :=
    correct byte (SourceMemory.sourceWorld source, source) rfl abstractBeforeRep
      afterArgumentsWellFormed afterArgumentsRepresented argumentsExecution
      argumentEffect actual
  refine ⟨afterWorld, ?_, afterWellFormed, afterRepresented,
    effect.weaken CellSet.empty_subset⟩
  apply TermEvaluates.apply
  · exact .cons
      (index_relational source function accept correct start cursor inBounds)
      .nil
  · change (ScannerWP.entry source function accept correct).callRelation
      (SourceMemory.sourceWorld source) function.function.id
      [.signed .i32 (Int.ofNat byte.val)] value afterWorld
    exact ⟨rfl, byte, (SourceMemory.sourceWorld source, source), result,
      abstractAfter, rfl, valueEq, rfl, abstractBeforeRep, post, frame,
      abstractAfterRep⟩


private theorem less_executable
    (source : List Byte) (start cursor : Nat) :
    FunctionalView.Term.evaluate
      (Effectful.machine checkedFrontend.core rejectingCalls)
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      (apply (.binary .less i32Type i32Type (.scalar .bool))
        [ScannerWP.cursorTerm, ScannerWP.boundTerm]) =
      .ok (.boolean (decide (cursor < source.length)),
        SourceMemory.sourceWorld source) := by
  calc
    _ = FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core)
        (SourceMemory.sourceWorld source)
        (ScannerWP.loopEnvironment source start cursor)
        (apply (.binary .less i32Type i32Type (.scalar .bool))
          [ScannerWP.cursorTerm, ScannerWP.boundTerm]) :=
      Effectful.Term.evaluate_eq_readOnly_of_callFree
        (program := checkedFrontend.core) (calls := rejectingCalls) _
        (by decide +kernel)
    _ = _ := by
      exact ReadOnly.Term.evaluate_i32_less
        (program := checkedFrontend.core)
        (world := SourceMemory.sourceWorld source)
        (environment := ScannerWP.loopEnvironment source start cursor)
        (leftType := i32Type) (rightType := i32Type)
        (outputType := .scalar .bool)
        (left := ScannerWP.cursorTerm) (right := ScannerWP.boundTerm)
        (leftValue := cursor) (rightValue := source.length) (by rfl) (by rfl)

private theorem less_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.TermReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (LoopInvariant source)
      (apply (.binary .less i32Type i32Type (.scalar .bool))
        [ScannerWP.cursorTerm, ScannerWP.boundTerm]) := by
  apply LeafMigration.termReflectsWhen
    (FreshSimulation.operationSoundness checkedFrontend.core rejectingCalls
      rejectingCalls_sound)
  · intro world environment input
    obtain ⟨start, cursor, _sourceBound, rfl, rfl⟩ := input
    exact ⟨_, _, less_executable source start cursor⟩
  · intro world environment input value afterWorld evaluated
    obtain ⟨start, cursor, _sourceBound, rfl, rfl⟩ := input
    have canonical := less_executable source start cursor
    have same := evaluated.symm.trans canonical
    injection same with pairEq
    have valueEq : value = .boolean (decide (cursor < source.length)) := by
      simpa using congrArg Prod.fst pairEq
    have worldEq : afterWorld = SourceMemory.sourceWorld source := by
      simpa using congrArg Prod.snd pairEq
    subst value
    subst afterWorld
    exact less_relational source function accept correct start cursor

/-- Direct registry-backed condition reflection.  The predicate call is
discharged from its `ReturnsCorrectly` contract against the actual Core call;
no executable predicate model or callee termination theorem is used. -/
theorem condition_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.TermReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (LoopInvariant source) (ScannerWP.loopCondition function) := by
  intro layout localCell world environment before after frontier value
    wellFormed represented input actual
  obtain ⟨start, cursor, sourceBound, rfl, rfl⟩ := input
  have inputInvariant : LoopInvariant source (SourceMemory.sourceWorld source)
      (ScannerWP.loopEnvironment source start cursor) :=
    ⟨start, cursor, sourceBound, rfl, rfl⟩
  have actualCondition : Evaluates checkedFrontend.core before
      (.binary .logicalAnd
        (Core.toCoreExpr layout
          (apply (.binary .less i32Type i32Type (.scalar .bool))
            [ScannerWP.cursorTerm, ScannerWP.boundTerm]))
        (Core.toCoreExpr layout (ScannerWP.predicateTerm function)))
      value after := by
    simpa [ScannerWP.loopCondition, FunctionalView.Core.logicalAnd,
      Core.toCoreExpr,
      Core.Operation.toCoreExpr] using actual
  rcases CoreSuccess.evaluatesLogicalAndInversion actualCondition with
    ⟨valueEq, leftActual⟩ | ⟨middle, leftActual, rightActual⟩
  · subst value
    obtain ⟨afterWorld, leftEvaluated, afterWellFormed, afterRepresented,
        effect⟩ :=
      less_reflects source function accept correct wellFormed represented
        inputInvariant leftActual
    exact ⟨afterWorld, .logicalAndFalse leftEvaluated, afterWellFormed,
      afterRepresented, effect⟩
  · obtain ⟨leftWorld, leftEvaluated, middleWellFormed, middleRepresented,
        leftEffect⟩ :=
      less_reflects source function accept correct wellFormed represented
        inputInvariant leftActual
    obtain ⟨lessEq, leftWorldEq⟩ :=
      ScannerWP.less_result source function accept correct start cursor
        leftEvaluated
    have decided : decide (cursor < source.length) = true := by
      exact (Value.boolean.inj lessEq).symm
    have inBounds : cursor < source.length := by
      exact of_decide_eq_true decided
    subst leftWorld
    have bodyInput : BodyAdmissible source (SourceMemory.sourceWorld source)
        (ScannerWP.loopEnvironment source start cursor) :=
      ⟨start, cursor, sourceBound, inBounds, rfl, rfl⟩
    obtain ⟨afterWorld, rightEvaluated, afterWellFormed, afterRepresented,
        rightEffect⟩ :=
      predicate_reflects source function accept correct middleWellFormed
        middleRepresented bodyInput rightActual
    exact ⟨afterWorld, .logicalAndTrue leftEvaluated rightEvaluated,
      afterWellFormed, afterRepresented,
      leftEffect.trans_same rightEffect⟩

private theorem loopEnvironment_set
    (source : List Byte) (start cursor : Nat) :
    Stateful.Env.set (ScannerWP.loopEnvironment source start cursor)
      ⟨3, by omega⟩ (.signed .i32 (Int.ofNat (cursor + 1))) =
      ScannerWP.loopEnvironment source start (cursor + 1) := by
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
    simp [ScannerWP.loopEnvironment, Stateful.Env.set]

private theorem body_executable
    (source : List Byte)
    (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length) :
    Stateful.Command.Evaluates
      (Effectful.machine checkedFrontend.core rejectingCalls)
      (machineWith checkedFrontend.core
        (Effectful.evaluateOperation checkedFrontend.core rejectingCalls))
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      ScannerWP.loopBody .next (SourceMemory.sourceWorld source)
      (ScannerWP.loopEnvironment source start (cursor + 1)) := by
  rw [← loopEnvironment_set source start cursor]
  have updateResult : evalAssignValue checkedFrontend.core.target .add
      (some (.signed .i32 (Int.ofNat cursor))) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (cursor + 1))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    have addition : Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) := by simp
    rw [addition]
    rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _
      (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)]
  apply Stateful.Command.Evaluates.sequenceNext
  · exact Stateful.Command.Evaluates.updateLocal (by rfl) (by
      simpa [Stateful.machineWith, ScannerWP.loopEnvironment, Ref.evaluate]
        using updateResult)
  · exact .skip

private theorem body_relational
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length) :
    Stateful.CommandEvaluates
      (ScannerWP.machine source function accept correct)
      (SourceMemory.sourceWorld source) (ScannerWP.loopEnvironment source start cursor)
      ScannerWP.loopBody .next (SourceMemory.sourceWorld source)
      (ScannerWP.loopEnvironment source start (cursor + 1)) := by
  rw [← loopEnvironment_set source start cursor]
  apply Stateful.CommandEvaluates.sequenceNext
  · apply Stateful.CommandEvaluates.updateLocal
    · exact .reference _
    · change evalAssignValue checkedFrontend.core.target .add
        (some (.signed .i32 (Int.ofNat cursor))) (.signed .i32 1) =
        .ok (.signed .i32 (Int.ofNat (cursor + 1)))
      simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
        beq_self_eq_true, if_true, evalSignedBinary]
      have addition : Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) := by simp
      rw [addition]
      rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _
        (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)]
  · exact .skip

theorem body_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.CommandReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct) ScannerWP.loopBody
      (BodyAdmissible source) := by
  apply LeafMigration.commandReflectsWhen
    (FreshSimulation.operationSoundness checkedFrontend.core
      rejectingCalls rejectingCalls_sound)
  · intro world environment input
    obtain ⟨start, cursor, sourceBound, inBounds, rfl, rfl⟩ := input
    exact ⟨_, _, _, body_executable source start cursor
      sourceBound inBounds⟩
  · intro world environment input completion afterWorld afterEnvironment
      evaluated
    obtain ⟨start, cursor, sourceBound, inBounds, rfl, rfl⟩ := input
    have canonical := body_executable source start cursor
      sourceBound inBounds
    obtain ⟨completionEq, worldEq, environmentEq⟩ :=
      Stateful.Command.Evaluates.deterministic evaluated canonical
    subst completion
    subst afterWorld
    subst afterEnvironment
    exact body_relational source function accept correct start cursor
      sourceBound inBounds

private theorem condition_to_body_wp
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (world : ReadOnly.World) (environment : Env 4)
    (input : LoopInvariant source world environment) :
    SemanticWP.Term.WP (ScannerWP.machine source function accept correct)
      (ScannerWP.loopCondition function)
      (fun value afterWorld =>
        value = .boolean true → BodyAdmissible source afterWorld environment)
      world environment := by
  obtain ⟨start, cursor, sourceBound, rfl, rfl⟩ := input
  intro value afterWorld evaluated
  by_cases inBounds : cursor < source.length
  · obtain ⟨_valueEq, worldEq⟩ :=
      ScannerWP.condition_in_bounds source function accept correct start cursor
        inBounds value afterWorld evaluated
    subst afterWorld
    intro _true
    exact ⟨start, cursor, sourceBound, inBounds, rfl, rfl⟩
  · obtain ⟨valueEq, _worldEq⟩ :=
      ScannerWP.condition_out_of_bounds source function accept correct start
        cursor inBounds value afterWorld evaluated
    intro trueEq
    have impossible : Value.boolean false = Value.boolean true :=
      valueEq.symm.trans trueEq
    cases Value.boolean.inj impossible

private theorem body_to_loop_wp
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (world : ReadOnly.World) (environment : Env 4)
    (input : BodyAdmissible source world environment) :
    SemanticWP.Command.WP (ScannerWP.machine source function accept correct)
      ScannerWP.loopBody
      (fun completion afterWorld afterEnvironment =>
        (completion = .next ∨ completion = .continueLoop) →
          LoopInvariant source afterWorld afterEnvironment)
      world environment := by
  obtain ⟨start, cursor, sourceBound, inBounds, rfl, rfl⟩ := input
  intro completion afterWorld afterEnvironment evaluated
  obtain ⟨completionEq, worldEq, environmentEq⟩ :=
    ScannerWP.body_wp source function accept correct start cursor sourceBound
      inBounds completion afterWorld afterEnvironment evaluated
  subst completion
  subst afterWorld
  subst afterEnvironment
  intro _continues
  exact ⟨start, cursor + 1, sourceBound, rfl, rfl⟩

theorem loop_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.CommandReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (.whileLoop (ScannerWP.loopCondition function) ScannerWP.loopBody)
      (LoopInvariant source) := by
  exact CoreReflection.CommandReflectsWhen.whileLoop
    (condition_reflects source function accept correct)
    (condition_to_body_wp source function accept correct)
    (body_reflects source function accept correct)
    (body_to_loop_wp source function accept correct)

private theorem reference_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    {arity : Nat} (index : Fin arity) :
    CoreReflection.TermReflects checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (FunctionalView.Core.reference index) := by
  apply LeafMigration.termReflectsWhen
    (FreshSimulation.operationSoundness checkedFrontend.core
      rejectingCalls rejectingCalls_sound)
  · intro world environment _input
    exact ⟨environment index, world, rfl⟩
  · intro world environment _input value afterWorld evaluated
    simp only [FunctionalView.Core.reference, FunctionalView.Term.evaluate,
      Ref.evaluate] at evaluated
    obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
    exact .reference (.slot index)

private theorem tail_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.CommandReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (.sequence (.returnValue (some ScannerWP.cursorTerm)) .skip)
      (fun _ _ => True) := by
  apply CoreReflection.CommandReflectsWhen.ofLeaves
  exact .sequence
    (.returnSome (reference_reflects source function accept correct
      ⟨3, by omega⟩)) .skip

private theorem loop_then_tail_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.CommandReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (.sequence
        (.whileLoop (ScannerWP.loopCondition function) ScannerWP.loopBody)
        (.sequence (.returnValue (some ScannerWP.cursorTerm)) .skip))
      (LoopInvariant source) := by
  refine CoreReflection.CommandReflectsWhen.sequence
    (firstReflection := loop_reflects source function accept correct)
    (secondReflection :=
      tail_reflects source function accept correct) ?_
  intro world environment _input
  intro completion afterWorld afterEnvironment _evaluated _next
  trivial

private theorem pushed_loop_environment
    (source : List Byte) (start : Nat) :
    (ScannerWP.parameterEnvironment source start).push
      (.signed .i32 (Int.ofNat (start + 1))) =
      ScannerWP.loopEnvironment source start (start + 1) := by
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

private theorem initializer_to_loop_wp
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept))
    (world : ReadOnly.World) (environment : Env 3)
    (input : Admissible source world environment) :
    SemanticWP.Term.WP (ScannerWP.machine source function accept correct)
      Initializer
      (fun value afterWorld =>
        LoopInvariant source afterWorld (environment.push value))
      world environment := by
  obtain ⟨start, sourceBound, startInBounds, rfl, rfl⟩ := input
  intro value afterWorld evaluated
  obtain ⟨valueEq, worldEq⟩ :=
    ScannerWP.initializer_wp source function accept correct start sourceBound
      startInBounds value afterWorld evaluated
  subst value
  subst afterWorld
  rw [pushed_loop_environment source start]
  exact ⟨start, start + 1, sourceBound, rfl, rfl⟩

/-- Shared structural inverse-adequacy certificate for the identifier and
whitespace scanners.  The loop recursion follows the supplied successful Core
tree; executable semantics are used only for the condition and increment
leaves. -/
theorem command_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly
      (PredicateContracts.contract source function accept)) :
    CoreReflection.CommandReflectsWhen checkedFrontend.core
      (ScannerWP.registry source function accept correct)
      (ScannerWP.command function) (Admissible source) := by
  unfold ScannerWP.command IdentifierEnd.Structure.proofCommand
  exact CoreReflection.CommandReflectsWhen.letValue
    (initializer_reflects source function accept correct)
    (initializer_to_loop_wp source function accept correct)
    (loop_then_tail_reflects source function accept correct)

end Lanius.Extraction.Lexer.Relational.ScannerReflection
