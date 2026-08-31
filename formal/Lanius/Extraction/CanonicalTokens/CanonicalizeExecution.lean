import Lanius.Extraction.CanonicalTokens.CanonicalKind
import Lanius.Extraction.CanonicalTokens.CanonicalKindCallModel
import Lanius.Extraction.CanonicalTokens.CanonicalizeModel
import Lanius.Extraction.CanonicalTokens.CanonicalizeStructure
import Lanius.FunctionalViewLoop
import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.Extraction.CanonicalTokens.CanonicalizeExecution

set_option maxRecDepth 100000

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.Extraction.CanonicalTokens
open Lanius.Extraction.CanonicalTokens.Functions

def calls : Lanius.FunctionalView.Core.Effectful.CallModel where
  evaluate := (Lanius.FunctionalView.Core.Effectful.CallModel.route
    (fun function => function == canonicalKindFunction.id)
    CanonicalKindCallModel.calls Model.callModel).evaluate

private abbrev TM :=
  Lanius.FunctionalView.Core.Effectful.machine verifiedFrontendCore calls

private abbrev SM :=
  machineWith verifiedFrontendCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore calls)

def world (source records : List Int) : ReadOnly.World :=
  ReadOnly.World.pair 0 source 1 records

theorem calls_canonicalKind (source records : List Int)
    (kind start finish : Int)
    (startNonnegative : 0 ≤ start) (startLeFinish : start ≤ finish)
    (finishNonnegative : 0 ≤ finish)
    (spanInBounds : finish.toNat ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    calls.evaluate (world source records) canonicalKindFunction.id
        [.slice CanonicalizeStructure.i32 0 [] 0 source.length,
          .signed .i32 kind, .signed .i32 start, .signed .i32 finish] =
      .ok (.signed .i32
        (CanonicalKind.result source kind start.toNat finish.toNat),
        world source records) := by
  have finishLeSource : finish ≤ (source.length : Int) := by
    calc
      finish = Int.ofNat finish.toNat :=
        (Int.toNat_of_nonneg finishNonnegative).symm
      _ ≤ Int.ofNat source.length := Int.ofNat_le.mpr spanInBounds
  have finishFitsI32 : finish ≤ 2147483647 := by omega
  simp [calls, Lanius.FunctionalView.Core.Effectful.CallModel.route,
    CanonicalKindCallModel.calls, world, CanonicalizeStructure.i32,
    CanonicalizeStructure.sliceI32, startNonnegative, startLeFinish,
    spanInBounds, finishLeSource, finishFitsI32, sourceFitsI32]

def initialEnvironment (source records : List Int) (rawCount : Nat) : Env 3
  | ⟨0, _⟩ => .slice CanonicalizeStructure.i32 0 [] 0 source.length
  | ⟨1, _⟩ => .slice CanonicalizeStructure.i32 1 [] 0 records.length
  | ⟨2, _⟩ => .signed .i32 rawCount

def firstEnvironment (source records : List Int) (rawCount input output : Nat) :
    Env 5 :=
  ((initialEnvironment source records rawCount).push (.signed .i32 input)).push
    (.signed .i32 output)

def secondEnvironment (source records : List Int) (rawCount output range : Nat) :
    Env 6 :=
  (((initialEnvironment source records rawCount).push (.signed .i32 rawCount)).push
    (.signed .i32 output)).push (.signed .i32 range)

@[simp] theorem firstEnvironment_source (source records : List Int)
    (rawCount input output : Nat) :
    firstEnvironment source records rawCount input output ⟨0, by omega⟩ =
      .slice CanonicalizeStructure.i32 0 [] 0 source.length := by
  simp [firstEnvironment, initialEnvironment, Env.push]

@[simp] theorem firstEnvironment_records (source records : List Int)
    (rawCount input output : Nat) :
    firstEnvironment source records rawCount input output ⟨1, by omega⟩ =
      .slice CanonicalizeStructure.i32 1 [] 0 records.length := by
  simp [firstEnvironment, initialEnvironment, Env.push]

@[simp] theorem firstEnvironment_count (source records : List Int)
    (rawCount input output : Nat) :
    firstEnvironment source records rawCount input output ⟨2, by omega⟩ =
      .signed .i32 rawCount := by
  simp [firstEnvironment, initialEnvironment, Env.push]

@[simp] theorem firstEnvironment_input (source records : List Int)
    (rawCount input output : Nat) :
    firstEnvironment source records rawCount input output ⟨3, by omega⟩ =
      .signed .i32 input := by
  simp [firstEnvironment, Env.push]

@[simp] theorem firstEnvironment_output (source records : List Int)
    (rawCount input output : Nat) :
    firstEnvironment source records rawCount input output ⟨4, by omega⟩ =
      .signed .i32 output := by
  simp [firstEnvironment, Env.push]

theorem firstEnvironment_set_input (source records : List Int)
    (rawCount input output nextInput : Nat) :
    Env.set (firstEnvironment source records rawCount input output)
        ⟨3, by omega⟩ (.signed .i32 nextInput) =
      firstEnvironment source records rawCount nextInput output := by
  funext index
  have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
      index.val = 3 ∨ index.val = 4 := by omega
  rcases cases with h | h | h | h | h
  · have same : index = ⟨0, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]
  · have same : index = ⟨1, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]
  · have same : index = ⟨2, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]
  · have same : index = ⟨3, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]
  · have same : index = ⟨4, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]

theorem firstEnvironment_set_output (source records : List Int)
    (rawCount input output nextOutput : Nat) :
    Env.set (firstEnvironment source records rawCount input output)
        ⟨4, by omega⟩ (.signed .i32 nextOutput) =
      firstEnvironment source records rawCount input nextOutput := by
  funext index
  have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
      index.val = 3 ∨ index.val = 4 := by omega
  rcases cases with h | h | h | h | h
  · have same : index = ⟨0, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]
  · have same : index = ⟨1, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]
  · have same : index = ⟨2, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]
  · have same : index = ⟨3, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]
  · have same : index = ⟨4, by omega⟩ := Fin.ext h
    rw [same]
    simp [Env.set, firstEnvironment, initialEnvironment, Env.push]

theorem firstEnvironment_records_length_congr (source before after : List Int)
    (rawCount input output : Nat) (sameLength : before.length = after.length) :
    firstEnvironment source before rawCount input output =
      firstEnvironment source after rawCount input output := by
  funext index
  simp [firstEnvironment, initialEnvironment, Env.push, sameLength]

theorem popAfterKind_set_input (source records : List Int)
    (rawCount input output nextInput : Nat) (row kind : Int) :
    Env.pop (Env.pop (Env.set
      (((firstEnvironment source records rawCount input output).push
        (.signed .i32 row)).push (.signed .i32 kind))
      ⟨3, by omega⟩ (.signed .i32 nextInput))) =
      firstEnvironment source records rawCount nextInput output := by
  rw [Env.pop_set_of_lt _ _ _ (by decide : 3 < 6)]
  rw [Env.pop_set_of_lt _ _ _ (by decide : 3 < 5)]
  simp only [Env.pop_push]
  exact firstEnvironment_set_input source records rawCount input output nextInput

@[simp] theorem secondEnvironment_output (source records : List Int)
    (rawCount output range : Nat) :
    secondEnvironment source records rawCount output range ⟨4, by omega⟩ =
      .signed .i32 output := by
  simp [secondEnvironment, initialEnvironment, Env.push]

@[simp] theorem secondEnvironment_range (source records : List Int)
    (rawCount output range : Nat) :
    secondEnvironment source records rawCount output range ⟨5, by omega⟩ =
      .signed .i32 range := by
  simp [secondEnvironment, Env.push]

theorem secondEnvironment_set_range (source records : List Int)
    (rawCount output range nextRange : Nat) :
    Env.set (secondEnvironment source records rawCount output range)
        ⟨5, by omega⟩ (.signed .i32 nextRange) =
      secondEnvironment source records rawCount output nextRange := by
  funext index
  have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
      index.val = 3 ∨ index.val = 4 ∨ index.val = 5 := by omega
  rcases cases with h | h | h | h | h | h
  all_goals
    first
    | have same : index = ⟨0, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.set, secondEnvironment, initialEnvironment, Env.push]
    | have same : index = ⟨1, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.set, secondEnvironment, initialEnvironment, Env.push]
    | have same : index = ⟨2, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.set, secondEnvironment, initialEnvironment, Env.push]
    | have same : index = ⟨3, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.set, secondEnvironment, initialEnvironment, Env.push]
    | have same : index = ⟨4, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.set, secondEnvironment, initialEnvironment, Env.push]
    | have same : index = ⟨5, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.set, secondEnvironment, initialEnvironment, Env.push]

theorem secondEnvironment_records_length_congr (source before after : List Int)
    (rawCount output range : Nat) (sameLength : before.length = after.length) :
    secondEnvironment source before rawCount output range =
      secondEnvironment source after rawCount output range := by
  funext index
  simp [secondEnvironment, initialEnvironment, Env.push, sameLength]

@[simp] theorem world_source (source records : List Int) :
    (world source records).i32Slice? 0 = some source := by rfl

@[simp] theorem world_records (source records : List Int) :
    (world source records).i32Slice? 1 = some records := by rfl

@[simp] theorem set_records_world (source before after : List Int) :
    ReadOnly.World.setI32Slice (world source before) 1 after =
      world source after := by
  exact ReadOnly.World.setI32Slice_pair_second (by decide)

theorem firstCondition_evaluates (source records : List Int)
    (rawCount input output : Nat) :
    Term.evaluate TM (world source records)
        (firstEnvironment source records rawCount input output)
        CanonicalizeStructure.firstCondition =
      .ok (.boolean (input < rawCount), world source records) := by
  simp only [CanonicalizeStructure.firstCondition, CanonicalizeStructure.less,
    CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate, evaluateTerms]
  rw [firstEnvironment_input, firstEnvironment_count]
  simp [TM,
    Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    ReadOnly.evaluateOperation, Lanius.Semantics.evalBinaryValue,
    Lanius.Semantics.evalSignedBinary, bind, Except.bind]

theorem secondCondition_evaluates (source records : List Int)
    (rawCount output range : Nat) (outputFitsI32 : output ≤ 2147483647)
    (rangeSuccFitsI32 : range + 1 ≤ 2147483647) :
    Term.evaluate TM (world source records)
        (secondEnvironment source records rawCount output range)
        CanonicalizeStructure.secondCondition =
      .ok (.boolean (range + 1 < output), world source records) := by
  simp only [CanonicalizeStructure.secondCondition, CanonicalizeStructure.less,
    CanonicalizeStructure.add, CanonicalizeStructure.signed,
    CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate, evaluateTerms]
  rw [secondEnvironment_range, secondEnvironment_output]
  have wrapped :
      Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
          ((range : Int) + 1) = ((range + 1 : Nat) : Int) := by
    have addEq : (range : Int) + 1 = ((range + 1 : Nat) : Int) := by omega
    rw [addEq]
    exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ rangeSuccFitsI32
  simp [TM, Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    ReadOnly.evaluateOperation, Lanius.Semantics.evalBinaryValue,
    Lanius.Semantics.evalSignedBinary, bind, Except.bind, wrapped]
  omega

def isTriviaCode (kind : Int) : Bool :=
  kind = 3 || kind = 10 || kind = 11

def writeRecord (records : List Int) (output : Nat)
    (kind start finish : Int) : List Int :=
  let row := 3 * output
  Lanius.Semantics.setI32Value
    (Lanius.Semantics.setI32Value
      (Lanius.Semantics.setI32Value records row kind) (row + 1) start)
    (row + 2) finish

def firstStepRecords (source records : List Int) (output : Nat)
    (kind start finish : Int) : List Int :=
  if isTriviaCode kind then records
  else writeRecord records output
    (CanonicalKind.result source kind start.toNat finish.toNat) start finish

def firstStepOutput (output : Nat) (kind : Int) : Nat :=
  if isTriviaCode kind then output else output + 1

structure RowsValid (source records : List Int) (rawCount : Nat) : Prop where
  recordsLength : records.length = 3 * rawCount
  recordWordsFitI32 : 3 * rawCount ≤ 2147483647
  sourceFitsI32 : source.length ≤ 2147483647
  startNonnegative : ∀ row, row < rawCount → 0 ≤ records[3 * row + 1]!
  finishNonnegative : ∀ row, row < rawCount → 0 ≤ records[3 * row + 2]!
  spanOrdered : ∀ row, row < rawCount →
    records[3 * row + 1]!.toNat ≤ records[3 * row + 2]!.toNat
  spanInBounds : ∀ row, row < rawCount →
    records[3 * row + 2]!.toNat ≤ source.length

@[simp] theorem writeRecord_length (records : List Int) (output : Nat)
    (kind start finish : Int) :
    (writeRecord records output kind start finish).length = records.length := by
  simp [writeRecord]

theorem writeRecord_start_same (records : List Int) (rawCount output : Nat)
    (kind start finish : Int) (recordsLength : records.length = 3 * rawCount)
    (outputBound : output < rawCount) :
    (writeRecord records output kind start finish)[3 * output + 1]! = start := by
  have bound : 3 * output + 1 < records.length := by omega
  simp [writeRecord, Lanius.Semantics.setI32Value, getElem!_pos, bound]

theorem writeRecord_finish_same (records : List Int) (rawCount output : Nat)
    (kind start finish : Int) (recordsLength : records.length = 3 * rawCount)
    (outputBound : output < rawCount) :
    (writeRecord records output kind start finish)[3 * output + 2]! = finish := by
  have bound : 3 * output + 2 < records.length := by omega
  simp [writeRecord, Lanius.Semantics.setI32Value, getElem!_pos, bound]

theorem writeRecord_start_other (records : List Int) (rawCount output row : Nat)
    (kind start finish : Int) (recordsLength : records.length = 3 * rawCount)
    (rowBound : row < rawCount) (different : row ≠ output) :
    (writeRecord records output kind start finish)[3 * row + 1]! =
      records[3 * row + 1]! := by
  have bound : 3 * row + 1 < records.length := by omega
  have kindDifferent : 3 * output ≠ 3 * row + 1 := by omega
  have startDifferent : 3 * output + 1 ≠ 3 * row + 1 := by omega
  have finishDifferent : 3 * output + 2 ≠ 3 * row + 1 := by omega
  let updated := ((records.set (3 * output) kind).set
    (3 * output + 1) start).set (3 * output + 2) finish
  have updatedEq : writeRecord records output kind start finish = updated := rfl
  have updatedBound : 3 * row + 1 <
      (writeRecord records output kind start finish).length := by simp [bound]
  rw [updatedEq] at updatedBound ⊢
  rw [getElem!_pos updated
    (3 * row + 1) updatedBound, getElem!_pos records (3 * row + 1) bound]
  dsimp only [updated]
  rw [List.getElem_set_ne finishDifferent]
  rw [List.getElem_set_ne startDifferent]
  rw [List.getElem_set_ne kindDifferent]

theorem writeRecord_finish_other (records : List Int) (rawCount output row : Nat)
    (kind start finish : Int) (recordsLength : records.length = 3 * rawCount)
    (rowBound : row < rawCount) (different : row ≠ output) :
    (writeRecord records output kind start finish)[3 * row + 2]! =
      records[3 * row + 2]! := by
  have bound : 3 * row + 2 < records.length := by omega
  have kindDifferent : 3 * output ≠ 3 * row + 2 := by omega
  have startDifferent : 3 * output + 1 ≠ 3 * row + 2 := by omega
  have finishDifferent : 3 * output + 2 ≠ 3 * row + 2 := by omega
  let updated := ((records.set (3 * output) kind).set
    (3 * output + 1) start).set (3 * output + 2) finish
  have updatedEq : writeRecord records output kind start finish = updated := rfl
  have updatedBound : 3 * row + 2 <
      (writeRecord records output kind start finish).length := by simp [bound]
  rw [updatedEq] at updatedBound ⊢
  rw [getElem!_pos updated
    (3 * row + 2) updatedBound, getElem!_pos records (3 * row + 2) bound]
  dsimp only [updated]
  rw [List.getElem_set_ne finishDifferent]
  rw [List.getElem_set_ne startDifferent]
  rw [List.getElem_set_ne kindDifferent]

theorem firstStep_rowsValid (source records : List Int) (rawCount input output : Nat)
    (valid : RowsValid source records rawCount) (inputBound : input < rawCount)
    (outputBound : output ≤ input) :
    RowsValid source
      (firstStepRecords source records output records[3 * input]!
        records[3 * input + 1]! records[3 * input + 2]!) rawCount := by
  have rowIndexBound : 3 * input < records.length := by
    rw [valid.recordsLength]
    omega
  have kindStorage : records[3 * input]?.getD 0 = records[3 * input]! := by
    simp [getElem!_pos, rowIndexBound]
  by_cases trivia : isTriviaCode records[3 * input]! = true
  · simp only [firstStepRecords, kindStorage, trivia, if_true]
    exact valid
  · have outputInBounds : output < rawCount := by omega
    simp only [firstStepRecords, kindStorage, trivia, Bool.false_eq_true,
      if_false]
    constructor
    · simpa using valid.recordsLength
    · exact valid.recordWordsFitI32
    · exact valid.sourceFitsI32
    · intro row rowBound
      by_cases same : row = output
      · subst row
        rw [writeRecord_start_same records rawCount output _ _ _
          valid.recordsLength outputInBounds]
        exact valid.startNonnegative input inputBound
      · rw [writeRecord_start_other records rawCount output row _ _ _
          valid.recordsLength rowBound same]
        exact valid.startNonnegative row rowBound
    · intro row rowBound
      by_cases same : row = output
      · subst row
        rw [writeRecord_finish_same records rawCount output _ _ _
          valid.recordsLength outputInBounds]
        exact valid.finishNonnegative input inputBound
      · rw [writeRecord_finish_other records rawCount output row _ _ _
          valid.recordsLength rowBound same]
        exact valid.finishNonnegative row rowBound
    · intro row rowBound
      by_cases same : row = output
      · subst row
        rw [writeRecord_start_same records rawCount output _ _ _
          valid.recordsLength outputInBounds]
        rw [writeRecord_finish_same records rawCount output _ _ _
          valid.recordsLength outputInBounds]
        exact valid.spanOrdered input inputBound
      · rw [writeRecord_start_other records rawCount output row _ _ _
          valid.recordsLength rowBound same]
        rw [writeRecord_finish_other records rawCount output row _ _ _
          valid.recordsLength rowBound same]
        exact valid.spanOrdered row rowBound
    · intro row rowBound
      by_cases same : row = output
      · subst row
        rw [writeRecord_finish_same records rawCount output _ _ _
          valid.recordsLength outputInBounds]
        exact valid.spanInBounds input inputBound
      · rw [writeRecord_finish_other records rawCount output row _ _ _
          valid.recordsLength rowBound same]
        exact valid.spanInBounds row rowBound

theorem firstRow_evaluates (source records : List Int)
    (rawCount input output : Nat) (inputBound : input < rawCount)
    (recordWordsFitI32 : 3 * rawCount ≤ 2147483647) :
    Term.evaluate TM (world source records)
        (firstEnvironment source records rawCount input output)
        (CanonicalizeStructure.multiply
          (CanonicalizeStructure.slot ⟨3, by omega⟩)
          (CanonicalizeStructure.signed 3)) =
      .ok (.signed .i32 (3 * input), world source records) := by
  have rowBound : 3 * input ≤ 2147483647 := by omega
  have productEq : (input : Int) * 3 = ((3 * input : Nat) : Int) := by omega
  have wrapped :
      Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
          ((input : Int) * 3) = ((3 * input : Nat) : Int) := by
    rw [productEq]
    exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ rowBound
  simp only [CanonicalizeStructure.multiply, CanonicalizeStructure.slot,
    CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate, evaluateTerms]
  rw [firstEnvironment_input]
  simp [TM, Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    ReadOnly.evaluateOperation, Lanius.Semantics.evalBinaryValue,
    Lanius.Semantics.evalSignedBinary, bind, Except.bind, wrapped]

def afterRowEnvironment (source records : List Int)
    (rawCount input output : Nat) : Env 6 :=
  (firstEnvironment source records rawCount input output).push
    (.signed .i32 (3 * input))

@[simp] theorem afterRowEnvironment_records (source records : List Int)
    (rawCount input output : Nat) :
    afterRowEnvironment source records rawCount input output ⟨1, by omega⟩ =
      .slice CanonicalizeStructure.i32 1 [] 0 records.length := by
  calc
    _ = firstEnvironment source records rawCount input output
        ⟨1, by omega⟩ := Env.push_before _ _ ⟨1, by omega⟩
    _ = _ := firstEnvironment_records source records rawCount input output

@[simp] theorem afterRowEnvironment_row (source records : List Int)
    (rawCount input output : Nat) :
    afterRowEnvironment source records rawCount input output ⟨5, by omega⟩ =
      .signed .i32 (3 * input) := by
  exact Env.push_last _ _

theorem firstKind_evaluates (source records : List Int)
    (rawCount input output : Nat)
    (rowBound : 3 * input < records.length) :
    Term.evaluate TM (world source records)
        ((firstEnvironment source records rawCount input output).push
          (.signed .i32 (3 * (input : Int))))
        CanonicalizeStructure.firstKind =
      .ok (.signed .i32 (records.get ⟨3 * input, rowBound⟩),
        world source records) := by
  unfold CanonicalizeStructure.firstKind CanonicalizeStructure.index
  apply Term.evaluate_apply2
    (leftValue := .slice CanonicalizeStructure.i32 1 [] 0 records.length)
    (rightValue := .signed .i32 (3 * input))
    (afterLeft := world source records)
    (afterRight := world source records)
  · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    simp [Env.push, firstEnvironment, initialEnvironment]
  · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    simp [Env.push]
  · change Lanius.FunctionalView.Core.Effectful.evaluateOperation
        verifiedFrontendCore calls (world source records)
        (.index CanonicalizeStructure.sliceI32 CanonicalizeStructure.i32
          CanonicalizeStructure.i32)
        [.slice CanonicalizeStructure.i32 1 [] 0 records.length,
          .signed .i32 (3 * input)] = _
    rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl)]
    have indexed := ReadOnly.evaluateOperation_i32_index
      (program := verifiedFrontendCore) (world := world source records)
      (cell := 1) (values := records) (position := 3 * input)
      (baseType := CanonicalizeStructure.sliceI32)
      (indexType := CanonicalizeStructure.i32)
      (elementType := CanonicalizeStructure.i32)
      (world_records source records) rowBound
    change ReadOnly.evaluateOperation verifiedFrontendCore
      (world source records)
      (.index CanonicalizeStructure.sliceI32
        (.scalar (.signed .i32)) (.scalar (.signed .i32)))
      [.slice (.scalar (.signed .i32)) 1 [] 0 records.length,
        .signed .i32 (Int.ofNat (3 * input))] = _
    exact indexed

theorem firstIsKept_evaluates (source records : List Int)
    (rawCount input output : Nat) (kind : Int) :
    Term.evaluate TM (world source records)
        (((firstEnvironment source records rawCount input output).push
          (.signed .i32 (3 * (input : Int)))).push (.signed .i32 kind))
        CanonicalizeStructure.firstIsKept =
      .ok (.boolean (!isTriviaCode kind), world source records) := by
  have distinct : isTriviaFunction.id ≠ canonicalKindFunction.id := by
    native_decide
  unfold CanonicalizeStructure.firstIsKept CanonicalizeStructure.logicalNot
  apply Term.evaluate_apply1
    (argumentValue := .boolean (isTriviaCode kind))
    (afterArgument := world source records)
  · apply Term.evaluate_apply1
      (argumentValue := .signed .i32 kind)
      (afterArgument := world source records)
    · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate,
        Env.push]
      split <;> simp_all <;> omega
    · change calls.evaluate (world source records) isTriviaFunction.id
          [.signed .i32 kind] = _
      simp [calls, Model.callModel, isTriviaCode, distinct]
      rfl
  · change Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore calls (world source records)
      (.unary .logicalNot CanonicalizeStructure.bool
        CanonicalizeStructure.bool)
      [.boolean (isTriviaCode kind)] = _
    simp [Lanius.FunctionalView.Core.Effectful.evaluateOperation,
      ReadOnly.evaluateOperation, Lanius.Semantics.evalUnaryValue,
      bind, Except.bind]
    rfl

theorem afterKind_records (source records : List Int)
    (rawCount input output : Nat) (kind : Int) (index : Fin 7)
    (indexEq : index.val = 1) :
    (((firstEnvironment source records rawCount input output).push
      (.signed .i32 (3 * (input : Int)))).push (.signed .i32 kind)) index =
      .slice CanonicalizeStructure.i32 1 [] 0 records.length := by
  have same : index = ⟨1, by omega⟩ := Fin.ext indexEq
  rw [same]
  simp [Env.push, firstEnvironment, initialEnvironment]

theorem afterKind_row (source records : List Int)
    (rawCount input output : Nat) (kind : Int) (index : Fin 7)
    (indexEq : index.val = 5) :
    (((firstEnvironment source records rawCount input output).push
      (.signed .i32 (3 * (input : Int)))).push (.signed .i32 kind)) index =
      .signed .i32 (3 * (input : Int)) := by
  have same : index = ⟨5, by omega⟩ := Fin.ext indexEq
  rw [same]
  simp [Env.push]

theorem afterStart_row (source records : List Int)
    (rawCount input output : Nat) (kind start : Int) (index : Fin 8)
    (indexEq : index.val = 5) :
    ((((firstEnvironment source records rawCount input output).push
      (.signed .i32 (3 * (input : Int)))).push (.signed .i32 kind)).push
      (.signed .i32 start)) index = .signed .i32 (3 * (input : Int)) := by
  have same : index = ⟨5, by omega⟩ := Fin.ext indexEq
  rw [same]
  simp [Env.push]

theorem firstStart_evaluates (source records : List Int)
    (rawCount input output : Nat) (kind : Int)
    (startBound : 3 * input + 1 < records.length)
    (startFitsI32 : 3 * input + 1 ≤ 2147483647) :
    Term.evaluate TM (world source records)
        (((firstEnvironment source records rawCount input output).push
          (.signed .i32 (3 * (input : Int)))).push (.signed .i32 kind))
        CanonicalizeStructure.firstStart =
      .ok (.signed .i32 (records.get ⟨3 * input + 1, startBound⟩),
        world source records) := by
  change Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedFrontendCore calls)
      (world source records)
      (((firstEnvironment source records rawCount input output).push
        (.signed .i32 (3 * (input : Int)))).push (.signed .i32 kind))
      CanonicalizeStructure.firstStart = _
  have leftEq : Int.ofNat (3 * input) = 3 * (input : Int) := by
    calc
      _ = Int.ofNat 3 * Int.ofNat input := Int.natCast_mul 3 input
      _ = _ := rfl
  have resultEq : Int.ofNat (3 * input + 1) =
      3 * (input : Int) + 1 := by
    calc
      _ = Int.ofNat (3 * input) + Int.ofNat 1 :=
        Int.natCast_add (3 * input) 1
      _ = _ := by
        rw [leftEq]
        have one : Int.ofNat 1 = (1 : Int) := by decide
        rw [one]
  unfold CanonicalizeStructure.firstStart CanonicalizeStructure.index
  apply Term.evaluate_apply2
    (leftValue := .slice CanonicalizeStructure.i32 1 [] 0 records.length)
    (rightValue := .signed .i32 (3 * input + 1))
    (afterLeft := world source records) (afterRight := world source records)
  · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    rw [afterKind_records source records rawCount input output kind _ (by rfl)]
  · unfold CanonicalizeStructure.add
    apply Term.evaluate_apply2
      (leftValue := .signed .i32 (3 * (input : Int)))
      (rightValue := .signed .i32 1)
      (afterLeft := world source records) (afterRight := world source records)
    · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
      rw [afterKind_row source records rawCount input output kind _ (by rfl)]
    · simp [CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate]
    · change Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls (world source records)
          (.binary .add CanonicalizeStructure.i32 CanonicalizeStructure.i32
            CanonicalizeStructure.i32)
          [.signed .i32 (3 * (input : Int)), .signed .i32 1] = _
      change ReadOnly.evaluateOperation verifiedFrontendCore
          (world source records)
          (.binary .add CanonicalizeStructure.i32 CanonicalizeStructure.i32
            CanonicalizeStructure.i32)
          [.signed .i32 (3 * (input : Int)), .signed .i32 1] =
        .ok (.signed .i32 (3 * (input : Int) + 1), world source records)
      rw [← resultEq, ← leftEq]
      exact ReadOnly.evaluateOperation_i32_add
        (program := verifiedFrontendCore) (world := world source records)
        (leftType := CanonicalizeStructure.i32)
        (rightType := CanonicalizeStructure.i32)
        (outputType := CanonicalizeStructure.i32)
        (left := 3 * input) (right := 1) startFitsI32
  · change Lanius.FunctionalView.Core.Effectful.evaluateOperation
        verifiedFrontendCore calls (world source records)
        (.index CanonicalizeStructure.sliceI32 CanonicalizeStructure.i32
          CanonicalizeStructure.i32)
        [.slice CanonicalizeStructure.i32 1 [] 0 records.length,
          .signed .i32 (3 * input + 1)] = _
    change ReadOnly.evaluateOperation verifiedFrontendCore
        (world source records)
        (.index CanonicalizeStructure.sliceI32 CanonicalizeStructure.i32
          CanonicalizeStructure.i32)
        [.slice CanonicalizeStructure.i32 1 [] 0 records.length,
          .signed .i32 (3 * (input : Int) + 1)] = _
    rw [← resultEq]
    exact ReadOnly.evaluateOperation_i32_index
      (program := verifiedFrontendCore) (world := world source records)
      (cell := 1) (values := records) (position := 3 * input + 1)
      (baseType := CanonicalizeStructure.sliceI32)
      (indexType := CanonicalizeStructure.i32)
      (elementType := CanonicalizeStructure.i32)
      (world_records source records) startBound

theorem firstEnd_evaluates (source records : List Int)
    (rawCount input output : Nat) (kind start : Int)
    (finishBound : 3 * input + 2 < records.length)
    (finishFitsI32 : 3 * input + 2 ≤ 2147483647) :
    Term.evaluate TM (world source records)
        ((((firstEnvironment source records rawCount input output).push
          (.signed .i32 (3 * (input : Int)))).push
          (.signed .i32 kind)).push (.signed .i32 start))
        CanonicalizeStructure.firstEnd =
      .ok (.signed .i32 (records.get ⟨3 * input + 2, finishBound⟩),
        world source records) := by
  have leftEq : Int.ofNat (3 * input) = 3 * (input : Int) := by
    calc
      _ = Int.ofNat 3 * Int.ofNat input := Int.natCast_mul 3 input
      _ = _ := rfl
  have resultEq : Int.ofNat (3 * input + 2) =
      3 * (input : Int) + 2 := by
    calc
      _ = Int.ofNat (3 * input) + Int.ofNat 2 :=
        Int.natCast_add (3 * input) 2
      _ = _ := by
        rw [leftEq]
        have two : Int.ofNat 2 = (2 : Int) := by decide
        rw [two]
  unfold CanonicalizeStructure.firstEnd CanonicalizeStructure.index
  apply Term.evaluate_apply2
    (leftValue := .slice CanonicalizeStructure.i32 1 [] 0 records.length)
    (rightValue := .signed .i32 (3 * input + 2))
    (afterLeft := world source records) (afterRight := world source records)
  · simp [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate,
      Env.push, firstEnvironment, initialEnvironment]
  · unfold CanonicalizeStructure.add
    apply Term.evaluate_apply2
      (leftValue := .signed .i32 (3 * (input : Int)))
      (rightValue := .signed .i32 2)
      (afterLeft := world source records) (afterRight := world source records)
    · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
      rw [afterStart_row source records rawCount input output kind start _
        (by rfl)]
    · simp [CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate]
    · change ReadOnly.evaluateOperation verifiedFrontendCore
          (world source records)
          (.binary .add CanonicalizeStructure.i32 CanonicalizeStructure.i32
            CanonicalizeStructure.i32)
          [.signed .i32 (3 * (input : Int)), .signed .i32 2] =
        .ok (.signed .i32 (3 * (input : Int) + 2), world source records)
      rw [← resultEq, ← leftEq]
      exact ReadOnly.evaluateOperation_i32_add
        (program := verifiedFrontendCore) (world := world source records)
        (leftType := CanonicalizeStructure.i32)
        (rightType := CanonicalizeStructure.i32)
        (outputType := CanonicalizeStructure.i32)
        (left := 3 * input) (right := 2) finishFitsI32
  · change ReadOnly.evaluateOperation verifiedFrontendCore
        (world source records)
        (.index CanonicalizeStructure.sliceI32 CanonicalizeStructure.i32
          CanonicalizeStructure.i32)
        [.slice CanonicalizeStructure.i32 1 [] 0 records.length,
          .signed .i32 (3 * (input : Int) + 2)] = _
    rw [← resultEq]
    exact ReadOnly.evaluateOperation_i32_index
      (program := verifiedFrontendCore) (world := world source records)
      (cell := 1) (values := records) (position := 3 * input + 2)
      (baseType := CanonicalizeStructure.sliceI32)
      (indexType := CanonicalizeStructure.i32)
      (elementType := CanonicalizeStructure.i32)
      (world_records source records) finishBound

theorem afterEnd_output (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int) (index : Fin 9)
    (indexEq : index.val = 4) :
    (((((firstEnvironment source records rawCount input output).push
      (.signed .i32 (3 * (input : Int)))).push (.signed .i32 kind)).push
      (.signed .i32 start)).push (.signed .i32 finish)) index =
      .signed .i32 output := by
  have same : index = ⟨4, by omega⟩ := Fin.ext indexEq
  rw [same]
  simp [Env.push, firstEnvironment]

theorem firstOutputRow_evaluates (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int)
    (outputBound : output ≤ input) (inputBound : input < rawCount)
    (recordWordsFitI32 : 3 * rawCount ≤ 2147483647) :
    Term.evaluate TM (world source records)
        (((((firstEnvironment source records rawCount input output).push
          (.signed .i32 (3 * (input : Int)))).push
          (.signed .i32 kind)).push (.signed .i32 start)).push
          (.signed .i32 finish))
        CanonicalizeStructure.firstOutputRow =
      .ok (.signed .i32 (Int.ofNat (3 * output)), world source records) := by
  have outputWordsFit : 3 * output ≤ 2147483647 := by omega
  have productEq : (output : Int) * 3 = Int.ofNat (3 * output) := by
    rw [Nat.mul_comm, Int.ofNat_eq_coe, Int.natCast_mul]
    rfl
  have threeProductEq : 3 * (output : Int) = Int.ofNat (3 * output) := by
    rw [Int.ofNat_eq_coe, Int.natCast_mul]
    rfl
  have wrapped :
      Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
          ((output : Int) * 3) = ((3 * output : Nat) : Int) := by
    rw [productEq]
    exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ outputWordsFit
  have threeWrapped :
      Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
          (3 * (output : Int)) = 3 * (output : Int) := by
    rw [threeProductEq]
    exact Lanius.Semantics.wrapSigned_i32_ofNat verifiedFrontendCore.target
      (3 * output) outputWordsFit
  unfold CanonicalizeStructure.firstOutputRow CanonicalizeStructure.multiply
  apply Term.evaluate_apply2
    (leftValue := .signed .i32 output) (rightValue := .signed .i32 3)
    (afterLeft := world source records) (afterRight := world source records)
  · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    rw [afterEnd_output source records rawCount input output kind start finish
      _ (by rfl)]
  · simp [CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate]
  · change ReadOnly.evaluateOperation verifiedFrontendCore
        (world source records)
        (.binary .multiply CanonicalizeStructure.i32 CanonicalizeStructure.i32
          CanonicalizeStructure.i32)
        [.signed .i32 output, .signed .i32 3] =
      .ok (.signed .i32 (Int.ofNat (3 * output)), world source records)
    simp [ReadOnly.evaluateOperation, bind, Except.bind,
      Lanius.Semantics.evalBinaryValue, Lanius.Semantics.evalSignedBinary,
      productEq, threeWrapped]

def firstWritesEnvironment (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int) : Env 10 :=
  (((((firstEnvironment source records rawCount input output).push
    (.signed .i32 (3 * (input : Int)))).push (.signed .i32 kind)).push
    (.signed .i32 start)).push (.signed .i32 finish)).push
    (.signed .i32 (3 * (output : Int)))

@[simp] theorem firstWritesEnvironment_source (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int) :
    firstWritesEnvironment source records rawCount input output kind start finish
        ⟨0, by omega⟩ =
      .slice CanonicalizeStructure.i32 0 [] 0 source.length := by
  simp [firstWritesEnvironment, Env.push, firstEnvironment, initialEnvironment]

@[simp] theorem firstWritesEnvironment_records (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int) :
    firstWritesEnvironment source records rawCount input output kind start finish
        ⟨1, by omega⟩ =
      .slice CanonicalizeStructure.i32 1 [] 0 records.length := by
  simp [firstWritesEnvironment, Env.push, firstEnvironment, initialEnvironment]

@[simp] theorem firstWritesEnvironment_kind (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int) :
    firstWritesEnvironment source records rawCount input output kind start finish
        ⟨6, by omega⟩ = .signed .i32 kind := by
  simp [firstWritesEnvironment, Env.push]

@[simp] theorem firstWritesEnvironment_start (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int) :
    firstWritesEnvironment source records rawCount input output kind start finish
        ⟨7, by omega⟩ = .signed .i32 start := by
  simp [firstWritesEnvironment, Env.push]

@[simp] theorem firstWritesEnvironment_finish (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int) :
    firstWritesEnvironment source records rawCount input output kind start finish
        ⟨8, by omega⟩ = .signed .i32 finish := by
  simp [firstWritesEnvironment, Env.push]

@[simp] theorem firstWritesEnvironment_outputRow (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int) :
    firstWritesEnvironment source records rawCount input output kind start finish
        ⟨9, by omega⟩ = .signed .i32 (3 * (output : Int)) := by
  exact Env.push_last _ _

theorem firstCanonicalWrite_evaluates (source records : List Int)
    (rawCount input output : Nat) (kind start finish : Int)
    (outputBound : output ≤ input) (inputBound : input < rawCount)
    (recordsLength : records.length = 3 * rawCount)
    (sourceFitsI32 : source.length ≤ 2147483647)
    (startNonnegative : 0 ≤ start) (finishNonnegative : 0 ≤ finish)
    (spanOrdered : start.toNat ≤ finish.toNat)
    (spanInBounds : finish.toNat ≤ source.length) :
    evaluateActionWith
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls)
        (world source records)
        (firstWritesEnvironment source records rawCount input output kind start finish)
        (.setI32Index ⟨1, by omega⟩
          (CanonicalizeStructure.slot ⟨9, by omega⟩)
          (.apply (.call canonicalKindFunction.id
            [CanonicalizeStructure.sliceI32, CanonicalizeStructure.i32,
              CanonicalizeStructure.i32, CanonicalizeStructure.i32]
            CanonicalizeStructure.i32)
            [CanonicalizeStructure.slot ⟨0, by omega⟩,
              CanonicalizeStructure.slot ⟨6, by omega⟩,
              CanonicalizeStructure.slot ⟨7, by omega⟩,
              CanonicalizeStructure.slot ⟨8, by omega⟩])) =
      .ok (world source (Lanius.Semantics.setI32Value records (3 * output)
        (CanonicalKind.result source kind start.toNat finish.toNat))) := by
  have writeBound : 3 * output < records.length := by omega
  have startLeFinish : start ≤ finish := by
    calc
      start = Int.ofNat start.toNat :=
        (Int.toNat_of_nonneg startNonnegative).symm
      _ ≤ Int.ofNat finish.toNat := Int.ofNat_le.mpr spanOrdered
      _ = finish := Int.toNat_of_nonneg finishNonnegative
  have finishLeSource : finish ≤ Int.ofNat source.length := by
    calc
      finish = Int.ofNat finish.toNat :=
        (Int.toNat_of_nonneg finishNonnegative).symm
      _ ≤ Int.ofNat source.length := Int.ofNat_le.mpr spanInBounds
  have finishLeSource' : finish ≤ (source.length : Int) := by
    simpa only [Int.ofNat_eq_natCast] using finishLeSource
  let environment := firstWritesEnvironment source records rawCount input output
    kind start finish
  have indexResult :
      Term.evaluate
        (termMachine (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls))
        (world source records) environment
          (CanonicalizeStructure.slot ⟨9, by omega⟩) =
        .ok (.signed .i32 (3 * output), world source records) := by
    simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    rw [show environment ⟨9, by omega⟩ = .signed .i32 (3 * (output : Int)) by
      exact firstWritesEnvironment_outputRow source records rawCount input output
        kind start finish]
  have argumentsResult :
      evaluateTerms
        (termMachine (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls))
        (world source records) environment
          [CanonicalizeStructure.slot ⟨0, by omega⟩,
            CanonicalizeStructure.slot ⟨6, by omega⟩,
            CanonicalizeStructure.slot ⟨7, by omega⟩,
            CanonicalizeStructure.slot ⟨8, by omega⟩] =
        .ok ([.slice CanonicalizeStructure.i32 0 [] 0 source.length,
          .signed .i32 kind, .signed .i32 start, .signed .i32 finish],
          world source records) := by
    simp only [evaluateTerms, CanonicalizeStructure.slot, Term.evaluate,
      Ref.evaluate, bind, Except.bind]
    rw [show environment ⟨0, by omega⟩ =
      .slice CanonicalizeStructure.i32 0 [] 0 source.length by
        exact firstWritesEnvironment_source source records rawCount input output
          kind start finish]
    rw [show environment ⟨6, by omega⟩ = .signed .i32 kind by
      exact firstWritesEnvironment_kind source records rawCount input output
        kind start finish]
    rw [show environment ⟨7, by omega⟩ = .signed .i32 start by
      exact firstWritesEnvironment_start source records rawCount input output
        kind start finish]
    rw [show environment ⟨8, by omega⟩ = .signed .i32 finish by
      exact firstWritesEnvironment_finish source records rawCount input output
        kind start finish]
  have operationResult :
      Lanius.FunctionalView.Core.Effectful.evaluateOperation
        verifiedFrontendCore calls (world source records)
          (.call canonicalKindFunction.id
            [CanonicalizeStructure.sliceI32, CanonicalizeStructure.i32,
              CanonicalizeStructure.i32, CanonicalizeStructure.i32]
            CanonicalizeStructure.i32)
          [.slice CanonicalizeStructure.i32 0 [] 0 source.length,
            .signed .i32 kind, .signed .i32 start, .signed .i32 finish] =
        .ok (.signed .i32
          (CanonicalKind.result source kind start.toNat finish.toNat),
          world source records) := by
    simp only [Lanius.FunctionalView.Core.Effectful.evaluateOperation]
    exact calls_canonicalKind source records kind start finish startNonnegative
      startLeFinish finishNonnegative spanInBounds sourceFitsI32
  have valueResult :
      Term.evaluate
        (termMachine (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls))
        (world source records) environment
          (.apply (.call canonicalKindFunction.id
            [CanonicalizeStructure.sliceI32, CanonicalizeStructure.i32,
              CanonicalizeStructure.i32, CanonicalizeStructure.i32]
            CanonicalizeStructure.i32)
            [CanonicalizeStructure.slot ⟨0, by omega⟩,
              CanonicalizeStructure.slot ⟨6, by omega⟩,
              CanonicalizeStructure.slot ⟨7, by omega⟩,
              CanonicalizeStructure.slot ⟨8, by omega⟩]) =
        .ok (.signed .i32
          (CanonicalKind.result source kind start.toNat finish.toNat),
          world source records) :=
    Term.evaluate_apply argumentsResult operationResult
  simp only [evaluateActionWith]
  rw [indexResult]
  simp only [bind, Except.bind]
  rw [valueResult]
  simp only [bind, Except.bind]
  simp only [firstWritesEnvironment_records]
  have rowToNat : (3 * (output : Int)).toNat = 3 * output := by
    rw [Int.toNat_mul (by omega) (by omega), Int.toNat_natCast]
    rfl
  have indexNonnegative : ¬3 * (output : Int) < 0 := by omega
  have outputInBounds : output < rawCount := by omega
  simp (disch := omega) [writeI32Slice, CanonicalizeStructure.i32,
    world_records, recordsLength, rowToNat, indexNonnegative, outputInBounds,
    set_records_world]

/-- A later field write in the compacted token row.  The environment retains
the original slice length while the world contains the preceding writes, so
the explicit length equality is the resource-preservation obligation. -/
theorem firstFieldWrite_evaluates (source records current : List Int)
    (rawCount input output : Nat) (kind start finish : Int)
    (amount : Nat) (encodedAmount : Int) (valueSlot : Fin 10)
    (replacement : Int)
    (outputBound : output ≤ input) (inputBound : input < rawCount)
    (recordsLength : records.length = 3 * rawCount)
    (currentLength : current.length = records.length)
    (recordWordsFitI32 : 3 * rawCount ≤ 2147483647)
    (amountBound : amount ≤ 2)
    (amountEncoded : encodedAmount = Int.ofNat amount)
    (slotValue : firstWritesEnvironment source records rawCount input output
        kind start finish valueSlot = .signed .i32 replacement) :
    evaluateActionWith
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls)
        (world source current)
        (firstWritesEnvironment source records rawCount input output kind start finish)
        (.setI32Index ⟨1, by omega⟩
          (CanonicalizeStructure.add
            (CanonicalizeStructure.slot ⟨9, by omega⟩)
            (CanonicalizeStructure.signed encodedAmount))
          (CanonicalizeStructure.slot valueSlot)) =
      .ok (world source (Lanius.Semantics.setI32Value current
        (3 * output + amount) replacement)) := by
  subst encodedAmount
  have positionBound : 3 * output + amount < current.length := by omega
  have positionFitsI32 : 3 * output + amount ≤ 2147483647 := by omega
  have addition : 3 * (output : Int) + (amount : Int) =
      Int.ofNat (3 * output + amount) := by
    simp only [Int.ofNat_eq_natCast, Int.natCast_add, Int.natCast_mul]
    rfl
  have wrapped :
      Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
          (3 * (output : Int) + (amount : Int)) =
        Int.ofNat (3 * output + amount) := by
    rw [addition]
    exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ positionFitsI32
  have indexResult :
      Term.evaluate
          (termMachine (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedFrontendCore calls))
          (world source current)
          (firstWritesEnvironment source records rawCount input output
            kind start finish)
          (CanonicalizeStructure.add
            (CanonicalizeStructure.slot ⟨9, by omega⟩)
            (CanonicalizeStructure.signed (amount : Int))) =
        .ok (.signed .i32 (Int.ofNat (3 * output + amount)),
          world source current) := by
    apply Term.evaluate_apply2
      (leftValue := .signed .i32 (3 * (output : Int)))
      (rightValue := .signed .i32 (amount : Int))
      (afterLeft := world source current) (afterRight := world source current)
    · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
      exact congrArg (fun value => Except.ok (value, world source current))
        (firstWritesEnvironment_outputRow source records rawCount input output
          kind start finish)
    · rfl
    · change ReadOnly.evaluateOperation verifiedFrontendCore
          (world source current)
          (.binary .add CanonicalizeStructure.i32 CanonicalizeStructure.i32
            CanonicalizeStructure.i32)
          [.signed .i32 (3 * (output : Int)),
            .signed .i32 (amount : Int)] = _
      simp only [ReadOnly.evaluateOperation,
        Lanius.Semantics.evalBinaryValue,
        Lanius.Semantics.evalSignedBinary, bind, Except.bind,
        beq_self_eq_true, if_true]
      rw [wrapped]
      rfl
  have replacementResult :
      Term.evaluate
          (termMachine (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedFrontendCore calls))
          (world source current)
          (firstWritesEnvironment source records rawCount input output
            kind start finish)
          (CanonicalizeStructure.slot valueSlot) =
        .ok (.signed .i32 replacement, world source current) := by
    simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    rw [slotValue]
  simp only [evaluateActionWith]
  simp only [Int.ofNat_eq_natCast]
  rw [indexResult]
  simp only [bind, Except.bind]
  rw [replacementResult]
  simp only [bind, Except.bind]
  rw [show firstWritesEnvironment source records rawCount input output kind
      start finish ⟨1, by omega⟩ =
      .slice CanonicalizeStructure.i32 1 [] 0 records.length by
    exact firstWritesEnvironment_records source records rawCount input output
      kind start finish]
  have indexNonnegative : 0 ≤ Int.ofNat (3 * output + amount) :=
    Int.ofNat_nonneg _
  have indexToNat : (Int.ofNat (3 * output + amount)).toNat =
      3 * output + amount := by
    simpa only [Int.ofNat_eq_natCast] using
      Int.toNat_natCast (3 * output + amount)
  have sumNonnegative : ¬(3 * (output : Int) + (amount : Int)) < 0 := by
    omega
  have addition' : 3 * (output : Int) + (amount : Int) =
      Int.ofNat (3 * output + amount) := by
    simpa only [Int.ofNat_eq_natCast] using addition
  have sumToNat : (3 * (output : Int) + (amount : Int)).toNat =
      3 * output + amount := by
    rw [addition']
    exact indexToNat
  have positionRecordsBound : 3 * output + amount < records.length := by
    omega
  simp [writeI32Slice, CanonicalizeStructure.i32, sumNonnegative,
    sumToNat, currentLength, world_records, positionRecordsBound,
    set_records_world]

private def firstBodyRun (source records : List Int)
    (rawCount input output : Nat) :=
  Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
    (world source records)
    (firstEnvironment source records rawCount input output)
    CanonicalizeStructure.firstBody

/-- One exact compaction-loop iteration.  The hypotheses are precisely the
bounds needed by the three indexed reads and (for a kept token) writes. -/
theorem firstBody_runs (source records : List Int)
    (rawCount input output : Nat)
    (inputBound : input < rawCount)
    (outputBound : output ≤ input)
    (recordsLength : records.length = 3 * rawCount)
    (recordWordsFitI32 : 3 * rawCount ≤ 2147483647)
    (sourceFitsI32 : source.length ≤ 2147483647)
    (startNonnegative : 0 ≤ records[3 * input + 1]!)
    (finishNonnegative : 0 ≤ records[3 * input + 2]!)
    (spanOrdered : records[3 * input + 1]!.toNat ≤
      records[3 * input + 2]!.toNat)
    (spanInBounds : records[3 * input + 2]!.toNat ≤ source.length) :
    firstBodyRun source records rawCount input output = some
      (.next,
        world source (firstStepRecords source records output
          records[3 * input]! records[3 * input + 1]!
          records[3 * input + 2]!),
        firstEnvironment source
          (firstStepRecords source records output
            records[3 * input]! records[3 * input + 1]!
            records[3 * input + 2]!)
          rawCount (input + 1)
          (firstStepOutput output records[3 * input]!)) := by
  have rowBound : 3 * input < records.length := by omega
  have kindValueEq : records.get ⟨3 * input, rowBound⟩ =
      records[3 * input]! := by
    simp [getElem!_pos, rowBound]
  have triviaCanonicalDistinct :
      isTriviaFunction.id ≠ canonicalKindFunction.id := by native_decide
  by_cases trivia : isTriviaCode records[3 * input]!
  · have triviaGet :
        isTriviaCode (records.get ⟨3 * input, rowBound⟩) = true := by
      rw [kindValueEq]
      exact trivia
    have inputSuccBound : input + 1 ≤ 2147483647 := by omega
    have inputWrapped :
        Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
            ((input : Int) + 1) = ((input + 1 : Nat) : Int) := by
      have addEq : (input : Int) + 1 = ((input + 1 : Nat) : Int) := by omega
      rw [addEq]
      exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ inputSuccBound
    simp only [firstStepRecords, trivia, if_true]
    simp only [firstBodyRun, CanonicalizeStructure.firstBody,
      Lanius.FunctionalView.Stateful.Acyclic.run?]
    rw [firstRow_evaluates source records rawCount input output inputBound
      recordWordsFitI32]
    simp only
    simp only [CanonicalizeStructure.firstAfterRow,
      Lanius.FunctionalView.Stateful.Acyclic.run?]
    rw [firstKind_evaluates source records rawCount input output rowBound]
    simp only
    rw [firstIsKept_evaluates source records rawCount input output
      (records.get ⟨3 * input, rowBound⟩)]
    rw [triviaGet]
    simp [TM, SM,
      CanonicalizeStructure.firstAfterRow, CanonicalizeStructure.firstKept,
      CanonicalizeStructure.firstAfterStart,
      CanonicalizeStructure.firstAfterEnd, CanonicalizeStructure.firstWrites,
      CanonicalizeStructure.multiply, CanonicalizeStructure.index,
      CanonicalizeStructure.add, CanonicalizeStructure.logicalNot,
      CanonicalizeStructure.signed, CanonicalizeStructure.slot,
      Lanius.FunctionalView.Stateful.Acyclic.run?, Term.evaluate, Ref.evaluate,
      evaluateTerms, Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Effectful.evaluateOperation,
      ReadOnly.evaluateOperation, ReadOnly.readI32Slice,
      Lanius.Semantics.evalBinaryValue, Lanius.Semantics.evalSignedBinary,
      Lanius.Semantics.evalUnaryValue,
      calls, Model.callModel,
      firstStepRecords, firstStepOutput, trivia, triviaGet, kindValueEq,
      triviaCanonicalDistinct,
      world, firstEnvironment,
      initialEnvironment, Env.push, bind, Except.bind, recordsLength, inputBound,
      recordWordsFitI32, sourceFitsI32, machineWith,
      Lanius.Semantics.evalAssignValue, Lanius.Semantics.assignOpBinary?,
      inputWrapped]
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 ∨ index.val = 4 := by omega
    rcases cases with h | h | h | h | h
    · have same : index = ⟨0, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, trivia]
    · have same : index = ⟨1, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, trivia]
    · have same : index = ⟨2, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, trivia]
    · have same : index = ⟨3, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, trivia]
    · have same : index = ⟨4, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, trivia]
      split
      · rfl
      · rename_i notTriviaAtRow
        exfalso
        apply notTriviaAtRow
        simpa [getElem!_pos, rowBound] using trivia
  · have triviaFalse : isTriviaCode records[3 * input]! = false := by
      cases found : isTriviaCode records[3 * input]! <;> simp_all
    have triviaGetFalse :
        isTriviaCode (records.get ⟨3 * input, rowBound⟩) = false := by
      rw [kindValueEq]
      exact triviaFalse
    have startBound : 3 * input + 1 < records.length := by omega
    have startFitsI32 : 3 * input + 1 ≤ 2147483647 := by omega
    have startValueEq : records.get ⟨3 * input + 1, startBound⟩ =
        records[3 * input + 1]! := by
      simp [getElem!_pos, startBound]
    have finishBound : 3 * input + 2 < records.length := by omega
    have finishFitsI32 : 3 * input + 2 ≤ 2147483647 := by omega
    have finishValueEq : records.get ⟨3 * input + 2, finishBound⟩ =
        records[3 * input + 2]! := by
      simp [getElem!_pos, finishBound]
    simp only [firstStepRecords, triviaFalse, Bool.false_eq_true, if_false]
    simp only [firstBodyRun, CanonicalizeStructure.firstBody,
      Lanius.FunctionalView.Stateful.Acyclic.run?]
    rw [firstRow_evaluates source records rawCount input output inputBound
      recordWordsFitI32]
    simp only
    simp only [CanonicalizeStructure.firstAfterRow,
      Lanius.FunctionalView.Stateful.Acyclic.run?]
    rw [firstKind_evaluates source records rawCount input output rowBound]
    simp only
    rw [firstIsKept_evaluates source records rawCount input output
      (records.get ⟨3 * input, rowBound⟩)]
    rw [triviaGetFalse]
    simp only [Bool.not_false]
    simp only [CanonicalizeStructure.firstKept,
      Lanius.FunctionalView.Stateful.Acyclic.run?]
    rw [firstStart_evaluates source records rawCount input output
      (records.get ⟨3 * input, rowBound⟩) startBound startFitsI32]
    rw [startValueEq]
    simp only
    simp only [CanonicalizeStructure.firstAfterStart,
      Lanius.FunctionalView.Stateful.Acyclic.run?]
    rw [firstEnd_evaluates source records rawCount input output
      (records.get ⟨3 * input, rowBound⟩)
      records[3 * input + 1]! finishBound finishFitsI32]
    rw [finishValueEq]
    simp only
    simp only [CanonicalizeStructure.firstAfterEnd,
      Lanius.FunctionalView.Stateful.Acyclic.run?]
    rw [firstOutputRow_evaluates source records rawCount input output
      (records.get ⟨3 * input, rowBound⟩) records[3 * input + 1]!
      records[3 * input + 2]! outputBound inputBound recordWordsFitI32]
    simp only
    simp only [CanonicalizeStructure.firstWrites,
      Lanius.FunctionalView.Stateful.Acyclic.run?]
    rw [kindValueEq]
    have outputRowEq : Int.ofNat (3 * output) = 3 * (output : Int) := by
      rw [Int.ofNat_eq_natCast, Int.natCast_mul]
      rfl
    rw [outputRowEq]
    have environmentEq :
        (((((firstEnvironment source records rawCount input output).push
          (.signed .i32 (3 * (input : Int)))).push
          (.signed .i32 records[3 * input]!)).push
          (.signed .i32 records[3 * input + 1]!)).push
          (.signed .i32 records[3 * input + 2]!)).push
          (.signed .i32 (3 * (output : Int))) =
        firstWritesEnvironment source records rawCount input output
          records[3 * input]! records[3 * input + 1]!
          records[3 * input + 2]! := rfl
    rw [environmentEq]
    simp only [SM, machineWith]
    rw [firstCanonicalWrite_evaluates source records rawCount input output
      records[3 * input]! records[3 * input + 1]!
      records[3 * input + 2]! outputBound inputBound recordsLength
      sourceFitsI32 startNonnegative finishNonnegative spanOrdered spanInBounds]
    simp only
    rw [firstFieldWrite_evaluates source records
      (Lanius.Semantics.setI32Value records (3 * output)
        (CanonicalKind.result source records[3 * input]!
          records[3 * input + 1]!.toNat records[3 * input + 2]!.toNat))
      rawCount input output records[3 * input]! records[3 * input + 1]!
      records[3 * input + 2]! 1 1 ⟨7, by omega⟩ records[3 * input + 1]!
      outputBound inputBound recordsLength (by simp) recordWordsFitI32
      (by omega) rfl
      (firstWritesEnvironment_start source records rawCount input output
        records[3 * input]! records[3 * input + 1]!
        records[3 * input + 2]!)]
    simp only
    rw [firstFieldWrite_evaluates source records
      (Lanius.Semantics.setI32Value
        (Lanius.Semantics.setI32Value records (3 * output)
          (CanonicalKind.result source records[3 * input]!
            records[3 * input + 1]!.toNat records[3 * input + 2]!.toNat))
        (3 * output + 1) records[3 * input + 1]!)
      rawCount input output records[3 * input]! records[3 * input + 1]!
      records[3 * input + 2]! 2 2 ⟨8, by omega⟩ records[3 * input + 2]!
      outputBound inputBound recordsLength (by simp) recordWordsFitI32
      (by omega) rfl
      (firstWritesEnvironment_finish source records rawCount input output
        records[3 * input]! records[3 * input + 1]!
        records[3 * input + 2]!)]
    have outputSuccBound : output + 1 ≤ 2147483647 := by omega
    have outputWrapped :
        Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
            ((output : Int) + 1) = ((output + 1 : Nat) : Int) := by
      have addEq : (output : Int) + 1 = ((output + 1 : Nat) : Int) := by
        omega
      rw [addEq]
      exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ outputSuccBound
    have inputSuccBound : input + 1 ≤ 2147483647 := by omega
    have inputWrapped :
        Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
            ((input : Int) + 1) = ((input + 1 : Nat) : Int) := by
      have addEq : (input : Int) + 1 = ((input + 1 : Nat) : Int) := by omega
      rw [addEq]
      exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ inputSuccBound
    simp [TM, CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate,
      Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Effectful.evaluateOperation,
      ReadOnly.evaluateOperation, Lanius.Semantics.evalAssignValue,
      Lanius.Semantics.assignOpBinary?, Lanius.Semantics.evalBinaryValue,
      Lanius.Semantics.evalSignedBinary, bind, Except.bind, outputWrapped,
      inputWrapped, writeRecord, firstStepOutput, triviaFalse,
      firstWritesEnvironment, firstEnvironment, initialEnvironment, Env.push,
      Env.pop, Env.set]
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 ∨ index.val = 4 := by omega
    rcases cases with h | h | h | h | h
    · have same : index = ⟨0, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, triviaFalse]
    · have same : index = ⟨1, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, triviaFalse]
    · have same : index = ⟨2, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, triviaFalse]
    · have same : index = ⟨3, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, triviaFalse]
    · have same : index = ⟨4, by omega⟩ := Fin.ext h
      rw [same]
      simp [Env.pop, Env.set, Env.push, firstEnvironment, initialEnvironment,
        firstStepOutput, triviaFalse]
      rw [show isTriviaCode (records[3 * input]?.getD 0) = false by
        simpa [getElem!_pos, rowBound] using triviaFalse]
      rfl

def firstPass (source : List Int) (rawCount input : Nat)
    (records : List Int) (output : Nat) : List Int × Nat :=
  if inputBound : input < rawCount then
    let nextRecords := firstStepRecords source records output
      records[3 * input]! records[3 * input + 1]! records[3 * input + 2]!
    let nextOutput := firstStepOutput output records[3 * input]!
    firstPass source rawCount (input + 1) nextRecords nextOutput
  else
    (records, output)
termination_by rawCount - input
decreasing_by omega

theorem firstLoop_evaluates (source records : List Int)
    (rawCount input output : Nat) (inputAtMost : input ≤ rawCount)
    (outputBound : output ≤ input) (valid : RowsValid source records rawCount) :
    Command.Evaluates TM SM (world source records)
      (firstEnvironment source records rawCount input output)
      CanonicalizeStructure.firstLoop .next
      (world source (firstPass source rawCount input records output).1)
      (firstEnvironment source
        (firstPass source rawCount input records output).1 rawCount rawCount
        (firstPass source rawCount input records output).2) := by
  by_cases inBounds : input < rawCount
  · have condition :
        Term.evaluate TM (world source records)
            (firstEnvironment source records rawCount input output)
            CanonicalizeStructure.firstCondition =
          .ok (.boolean true, world source records) := by
      simpa [inBounds] using
        firstCondition_evaluates source records rawCount input output
    have bodyRun := firstBody_runs source records rawCount input output inBounds
      outputBound valid.recordsLength valid.recordWordsFitI32 valid.sourceFitsI32
      (valid.startNonnegative input inBounds)
      (valid.finishNonnegative input inBounds)
      (valid.spanOrdered input inBounds) (valid.spanInBounds input inBounds)
    have body :=
      Lanius.FunctionalView.Stateful.Acyclic.run?_sound bodyRun
    have nextValid := firstStep_rowsValid source records rawCount input output
      valid inBounds outputBound
    have nextOutputBound :
        firstStepOutput output records[3 * input]! ≤ input + 1 := by
      unfold firstStepOutput
      split <;> omega
    have rest := firstLoop_evaluates source
      (firstStepRecords source records output records[3 * input]!
        records[3 * input + 1]! records[3 * input + 2]!)
      rawCount (input + 1) (firstStepOutput output records[3 * input]!)
      (by omega) nextOutputBound nextValid
    rw [CanonicalizeStructure.firstLoop]
    rw [firstPass]
    simp only [inBounds, dite_true]
    exact .whileNext condition body rest
  · have inputEq : input = rawCount := by omega
    have condition :
        Term.evaluate TM (world source records)
            (firstEnvironment source records rawCount input output)
            CanonicalizeStructure.firstCondition =
          .ok (.boolean false, world source records) := by
      simpa [inBounds] using
        firstCondition_evaluates source records rawCount input output
    rw [CanonicalizeStructure.firstLoop]
    rw [firstPass]
    simp only [inBounds, dite_false]
    subst input
    exact .whileFalse condition
termination_by rawCount - input
decreasing_by omega

theorem firstPass_valid (source records : List Int)
    (rawCount input output : Nat) (inputAtMost : input ≤ rawCount)
    (outputBound : output ≤ input) (valid : RowsValid source records rawCount) :
    RowsValid source (firstPass source rawCount input records output).1 rawCount ∧
      (firstPass source rawCount input records output).2 ≤ rawCount := by
  by_cases inBounds : input < rawCount
  · have nextValid := firstStep_rowsValid source records rawCount input output
      valid inBounds outputBound
    have nextOutputBound :
        firstStepOutput output records[3 * input]! ≤ input + 1 := by
      unfold firstStepOutput
      split <;> omega
    have rest := firstPass_valid source
      (firstStepRecords source records output records[3 * input]!
        records[3 * input + 1]! records[3 * input + 2]!)
      rawCount (input + 1) (firstStepOutput output records[3 * input]!)
      (by omega) nextOutputBound nextValid
    rw [firstPass]
    simp only [inBounds, dite_true]
    exact rest
  · rw [firstPass]
    simp only [inBounds, dite_false]
    exact ⟨valid, by omega⟩
termination_by rawCount - input
decreasing_by omega

def secondMatches (records : List Int) (range : Nat) : Bool :=
  records[3 * range]! = 182 &&
    records[3 * (range + 1)]! = 8 &&
    records[3 * (range + 1) + 1]! = records[3 * range + 2]!

theorem secondMatches_eq_decide (records : List Int) (range : Nat) :
    secondMatches records range =
      (decide (records[3 * range]! = 182) &&
        decide (records[3 * (range + 1)]! = 8) &&
        decide (records[3 * (range + 1) + 1]! =
          records[3 * range + 2]!)) := by
  rfl

def secondStepRecords (records : List Int) (range : Nat) : List Int :=
  if secondMatches records range then
    Lanius.Semantics.setI32Value records (3 * range) 189
  else
    records

@[simp] theorem secondStepRecords_length (records : List Int) (range : Nat) :
    (secondStepRecords records range).length = records.length := by
  unfold secondStepRecords
  split <;> simp

def afterCurrentEnvironment (source records : List Int)
    (rawCount output range : Nat) : Env 7 :=
  (secondEnvironment source records rawCount output range).push
    (.signed .i32 (3 * (range : Int)))

def afterNextEnvironment (source records : List Int)
    (rawCount output range : Nat) : Env 8 :=
  (afterCurrentEnvironment source records rawCount output range).push
    (.signed .i32 (3 * ((range : Int) + 1)))

@[simp] theorem afterNextEnvironment_records (source records : List Int)
    (rawCount output range : Nat) :
    afterNextEnvironment source records rawCount output range ⟨1, by omega⟩ =
      .slice CanonicalizeStructure.i32 1 [] 0 records.length := by
  simp [afterNextEnvironment, afterCurrentEnvironment, secondEnvironment,
    initialEnvironment, Env.push]

@[simp] theorem afterNextEnvironment_current (source records : List Int)
    (rawCount output range : Nat) :
    afterNextEnvironment source records rawCount output range ⟨6, by omega⟩ =
      .signed .i32 (3 * (range : Int)) := by
  simp [afterNextEnvironment, afterCurrentEnvironment, Env.push]

@[simp] theorem afterNextEnvironment_next (source records : List Int)
    (rawCount output range : Nat) :
    afterNextEnvironment source records rawCount output range ⟨7, by omega⟩ =
      .signed .i32 (3 * ((range : Int) + 1)) := by
  exact Env.push_last _ _

theorem afterNext_set_range_pop (source before after : List Int)
    (rawCount output range nextRange : Nat)
    (sameLength : before.length = after.length) :
    Env.pop (Env.pop (Env.set
      (afterNextEnvironment source before rawCount output range)
      ⟨5, by omega⟩ (.signed .i32 nextRange))) =
      secondEnvironment source after rawCount output nextRange := by
  funext index
  have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
      index.val = 3 ∨ index.val = 4 ∨ index.val = 5 := by omega
  rcases cases with h | h | h | h | h | h
  · have same : index = ⟨0, by omega⟩ := Fin.ext h
    rw [same]
    simp [afterNextEnvironment, afterCurrentEnvironment, secondEnvironment,
      initialEnvironment, Env.push, Env.pop, Env.set, sameLength]
  · have same : index = ⟨1, by omega⟩ := Fin.ext h
    rw [same]
    simp [afterNextEnvironment, afterCurrentEnvironment, secondEnvironment,
      initialEnvironment, Env.push, Env.pop, Env.set, sameLength]
  · have same : index = ⟨2, by omega⟩ := Fin.ext h
    rw [same]
    simp [afterNextEnvironment, afterCurrentEnvironment, secondEnvironment,
      initialEnvironment, Env.push, Env.pop, Env.set, sameLength]
  · have same : index = ⟨3, by omega⟩ := Fin.ext h
    rw [same]
    simp [afterNextEnvironment, afterCurrentEnvironment, secondEnvironment,
      initialEnvironment, Env.push, Env.pop, Env.set, sameLength]
  · have same : index = ⟨4, by omega⟩ := Fin.ext h
    rw [same]
    simp [afterNextEnvironment, afterCurrentEnvironment, secondEnvironment,
      initialEnvironment, Env.push, Env.pop, Env.set, sameLength]
  · have same : index = ⟨5, by omega⟩ := Fin.ext h
    rw [same]
    simp [afterNextEnvironment, afterCurrentEnvironment, secondEnvironment,
      initialEnvironment, Env.push, Env.pop, Env.set, sameLength]

theorem secondCurrentRow_evaluates (source records : List Int)
    (rawCount output range : Nat) (rowFits : 3 * range ≤ 2147483647) :
    Term.evaluate TM (world source records)
        (secondEnvironment source records rawCount output range)
        (CanonicalizeStructure.multiply
          (CanonicalizeStructure.slot ⟨5, by omega⟩)
          (CanonicalizeStructure.signed 3)) =
      .ok (.signed .i32 (3 * range), world source records) := by
  have productEq : (range : Int) * 3 = ((3 * range : Nat) : Int) := by omega
  have wrapped :
      Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
          ((range : Int) * 3) = ((3 * range : Nat) : Int) := by
    rw [productEq]
    exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ rowFits
  simp only [CanonicalizeStructure.multiply, CanonicalizeStructure.slot,
    CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate, evaluateTerms]
  rw [secondEnvironment_range]
  simp [TM, Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    ReadOnly.evaluateOperation, Lanius.Semantics.evalBinaryValue,
    Lanius.Semantics.evalSignedBinary, bind, Except.bind, wrapped]

theorem secondNextRow_evaluates (source records : List Int)
    (rawCount output range : Nat)
    (nextFits : 3 * (range + 1) ≤ 2147483647) :
    Term.evaluate TM (world source records)
        (afterCurrentEnvironment source records rawCount output range)
        (CanonicalizeStructure.add
          (CanonicalizeStructure.slot ⟨6, by omega⟩)
          (CanonicalizeStructure.signed 3)) =
      .ok (.signed .i32 (3 * (range + 1)), world source records) := by
  have addition : (3 * range : Int) + 3 = ((3 * (range + 1) : Nat) : Int) := by
    omega
  have wrapped :
      Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
          ((3 * range : Int) + 3) = ((3 * (range + 1) : Nat) : Int) := by
    rw [addition]
    exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ nextFits
  simp only [CanonicalizeStructure.add, CanonicalizeStructure.slot,
    CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate, evaluateTerms]
  simp only [afterCurrentEnvironment, Env.push_last]
  simp [TM, Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    ReadOnly.evaluateOperation, Lanius.Semantics.evalBinaryValue,
    Lanius.Semantics.evalSignedBinary, bind, Except.bind, wrapped]

theorem recordsIndex_evaluates {arity : Nat} (source records : List Int)
    (environment : Env arity) (base : Fin arity) (position : Nat)
    (indexTerm : Term Core.signature arity)
    (baseValue : environment base =
      .slice CanonicalizeStructure.i32 1 [] 0 records.length)
    (indexValue : Term.evaluate TM (world source records) environment indexTerm =
      .ok (.signed .i32 (Int.ofNat position), world source records))
    (positionBound : position < records.length) :
    Term.evaluate TM (world source records) environment
        (CanonicalizeStructure.index
          (CanonicalizeStructure.slot base) indexTerm) =
      .ok (.signed .i32 (records.get ⟨position, positionBound⟩),
        world source records) := by
  unfold CanonicalizeStructure.index
  apply Term.evaluate_apply2
      (leftValue := .slice CanonicalizeStructure.i32 1 [] 0 records.length)
      (rightValue := .signed .i32 (Int.ofNat position))
      (afterLeft := world source records) (afterRight := world source records)
  · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    rw [baseValue]
  · exact indexValue
  · change Lanius.FunctionalView.Core.Effectful.evaluateOperation
        verifiedFrontendCore calls (world source records)
        (.index CanonicalizeStructure.sliceI32 CanonicalizeStructure.i32
          CanonicalizeStructure.i32)
        [.slice CanonicalizeStructure.i32 1 [] 0 records.length,
          .signed .i32 (Int.ofNat position)] = _
    rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl)]
    exact ReadOnly.evaluateOperation_i32_index
      (program := verifiedFrontendCore) (world := world source records)
      (cell := 1) (values := records) (position := position)
      (baseType := CanonicalizeStructure.sliceI32)
      (indexType := CanonicalizeStructure.i32)
      (elementType := CanonicalizeStructure.i32)
      (world_records source records) positionBound

theorem afterNext_currentIndex_evaluates (source records : List Int)
    (rawCount output range : Nat) (bound : 3 * range < records.length) :
    Term.evaluate TM (world source records)
        (afterNextEnvironment source records rawCount output range)
        (CanonicalizeStructure.index
          (CanonicalizeStructure.slot ⟨1, by omega⟩)
          (CanonicalizeStructure.slot ⟨6, by omega⟩)) =
      .ok (.signed .i32 (records.get ⟨3 * range, bound⟩),
        world source records) := by
  apply recordsIndex_evaluates source records _ _ (3 * range) _
      (afterNextEnvironment_records source records rawCount output range)
      _ bound
  simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
  rw [afterNextEnvironment_current]
  congr 2

theorem afterNext_nextIndex_evaluates (source records : List Int)
    (rawCount output range : Nat)
    (bound : 3 * (range + 1) < records.length) :
    Term.evaluate TM (world source records)
        (afterNextEnvironment source records rawCount output range)
        (CanonicalizeStructure.index
          (CanonicalizeStructure.slot ⟨1, by omega⟩)
          (CanonicalizeStructure.slot ⟨7, by omega⟩)) =
      .ok (.signed .i32 (records.get ⟨3 * (range + 1), bound⟩),
        world source records) := by
  apply recordsIndex_evaluates source records _ _ (3 * (range + 1)) _
      (afterNextEnvironment_records source records rawCount output range)
      _ bound
  simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
  rw [afterNextEnvironment_next]
  congr 2

private def signedI32ConstantValue? : Value → Option Int
  | .signed .i32 value => some value
  | _ => none

private theorem constant_eq_of_signed_i32_evidence
    (program : Program) (id : ConstantId) (value : Int)
    (evidence : (program.constant? id).map (fun declaration =>
      (declaration.id, declaration.type,
        signedI32ConstantValue? declaration.value)) =
      some (id, CanonicalizeStructure.i32, some value)) :
    program.constant? id = some {
      id := id
      type := CanonicalizeStructure.i32
      value := .signed .i32 value
    } := by
  cases found : program.constant? id with
  | none => simp [found] at evidence
  | some declaration =>
      simp only [found, Option.map_some, Option.some.injEq,
        Prod.mk.injEq] at evidence
      rcases evidence with ⟨idEqual, typeEqual, valueEqual⟩
      cases declaration with
      | mk declarationId declarationType declarationValue =>
          simp only at idEqual typeEqual valueEqual found
          subst declarationId
          subst declarationType
          cases declarationValue <;>
            simp [signedI32ConstantValue?] at valueEqual
          case signed signedType actualValue =>
            cases signedType <;> simp at valueEqual
            case i32 =>
              subst actualValue
              rfl

theorem canonicalize_constants :
    verifiedFrontendCore.constant? 87 = some {
        id := 87
        type := CanonicalizeStructure.i32
        value := .signed .i32 182
      } ∧
    verifiedFrontendCore.constant? 14 = some {
        id := 14
        type := CanonicalizeStructure.i32
        value := .signed .i32 8
      } ∧
    verifiedFrontendCore.constant? 88 = some {
        id := 88
        type := CanonicalizeStructure.i32
        value := .signed .i32 189
      } := by
  have evidence :
      (verifiedFrontendCore.constant? 87).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (87, CanonicalizeStructure.i32, some 182) ∧
      (verifiedFrontendCore.constant? 14).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (14, CanonicalizeStructure.i32, some 8) ∧
      (verifiedFrontendCore.constant? 88).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (88, CanonicalizeStructure.i32, some 189) := by
    native_decide
  exact ⟨
    constant_eq_of_signed_i32_evidence verifiedFrontendCore 87 182 evidence.1,
    constant_eq_of_signed_i32_evidence verifiedFrontendCore 14 8 evidence.2.1,
    constant_eq_of_signed_i32_evidence verifiedFrontendCore 88 189 evidence.2.2⟩

theorem canonicalizeConstant_evaluates (source records : List Int)
    (environment : Env arity) (id : ConstantId) (value : Int)
    (found : verifiedFrontendCore.constant? id = some {
      id := id
      type := CanonicalizeStructure.i32
      value := .signed .i32 value
    }) :
    Term.evaluate TM (world source records) environment
        (CanonicalizeStructure.constant id) =
      .ok (.signed .i32 value, world source records) := by
  unfold CanonicalizeStructure.constant
  apply Term.evaluate_apply0
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore calls (world source records)
      (.constant id CanonicalizeStructure.i32) [] = _
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
    (by rfl)]
  exact ReadOnly.evaluateOperation_constant found

theorem afterNext_addPosition_evaluates (source records : List Int)
    (rawCount output range amount position : Nat) (slot : Fin 8)
    (slotValue : afterNextEnvironment source records rawCount output range slot =
      .signed .i32 (Int.ofNat position))
    (resultFits : position + amount ≤ 2147483647) :
    Term.evaluate TM (world source records)
        (afterNextEnvironment source records rawCount output range)
        (CanonicalizeStructure.add (CanonicalizeStructure.slot slot)
          (CanonicalizeStructure.signed (Int.ofNat amount))) =
      .ok (.signed .i32 (Int.ofNat (position + amount)),
        world source records) := by
  apply Term.evaluate_apply2
      (leftValue := .signed .i32 (Int.ofNat position))
      (rightValue := .signed .i32 (Int.ofNat amount))
      (afterLeft := world source records) (afterRight := world source records)
  · simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    rw [slotValue]
  · simp [CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate]
  · change ReadOnly.evaluateOperation verifiedFrontendCore
        (world source records)
        (.binary .add CanonicalizeStructure.i32 CanonicalizeStructure.i32
          CanonicalizeStructure.i32)
        [.signed .i32 (Int.ofNat position),
          .signed .i32 (Int.ofNat amount)] = _
    exact ReadOnly.evaluateOperation_i32_add
      (program := verifiedFrontendCore) (world := world source records)
      (leftType := CanonicalizeStructure.i32)
      (rightType := CanonicalizeStructure.i32)
      (outputType := CanonicalizeStructure.i32)
      (left := position) (right := amount) resultFits

theorem afterNext_nextStartIndex_evaluates (source records : List Int)
    (rawCount output range : Nat)
    (positionFits : 3 * (range + 1) + 1 ≤ 2147483647)
    (bound : 3 * (range + 1) + 1 < records.length) :
    Term.evaluate TM (world source records)
        (afterNextEnvironment source records rawCount output range)
        (CanonicalizeStructure.index
          (CanonicalizeStructure.slot ⟨1, by omega⟩)
          (CanonicalizeStructure.add
            (CanonicalizeStructure.slot ⟨7, by omega⟩)
            (CanonicalizeStructure.signed 1))) =
      .ok (.signed .i32
        (records.get ⟨3 * (range + 1) + 1, bound⟩),
        world source records) := by
  apply recordsIndex_evaluates source records _ _ (3 * (range + 1) + 1) _
  · exact afterNextEnvironment_records source records rawCount output range
  · apply afterNext_addPosition_evaluates source records rawCount output range
        1 (3 * (range + 1)) ⟨7, by omega⟩
    · simpa only [Int.ofNat_eq_natCast, Int.natCast_mul,
          Int.natCast_add] using (show
        afterNextEnvironment source records rawCount output range
            ⟨7, by omega⟩ =
          .signed .i32 (Int.ofNat (3 * (range + 1))) by
        rw [afterNextEnvironment_next]
        congr 2)
    · exact positionFits

theorem afterNext_currentFinishIndex_evaluates (source records : List Int)
    (rawCount output range : Nat)
    (positionFits : 3 * range + 2 ≤ 2147483647)
    (bound : 3 * range + 2 < records.length) :
    Term.evaluate TM (world source records)
        (afterNextEnvironment source records rawCount output range)
        (CanonicalizeStructure.index
          (CanonicalizeStructure.slot ⟨1, by omega⟩)
          (CanonicalizeStructure.add
            (CanonicalizeStructure.slot ⟨6, by omega⟩)
            (CanonicalizeStructure.signed 2))) =
      .ok (.signed .i32 (records.get ⟨3 * range + 2, bound⟩),
        world source records) := by
  apply recordsIndex_evaluates source records _ _ (3 * range + 2) _
      (afterNextEnvironment_records source records rawCount output range) _ bound
  apply afterNext_addPosition_evaluates source records rawCount output range
      2 (3 * range) ⟨6, by omega⟩
  · show afterNextEnvironment source records rawCount output range
        ⟨6, by omega⟩ = .signed .i32 (Int.ofNat (3 * range))
    rw [afterNextEnvironment_current]
    congr 2
  · exact positionFits

theorem equalInt_evaluates (source records : List Int)
    (environment : Env arity) (left right : Term Core.signature arity)
    (leftValue rightValue : Int)
    (leftResult : Term.evaluate TM (world source records) environment left =
      .ok (.signed .i32 leftValue, world source records))
    (rightResult : Term.evaluate TM (world source records) environment right =
      .ok (.signed .i32 rightValue, world source records)) :
    Term.evaluate TM (world source records) environment
        (CanonicalizeStructure.equal left right) =
      .ok (.boolean (leftValue = rightValue), world source records) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change ReadOnly.evaluateOperation verifiedFrontendCore (world source records)
      (.binary .equal CanonicalizeStructure.i32 CanonicalizeStructure.i32
        CanonicalizeStructure.bool)
      [.signed .i32 leftValue, .signed .i32 rightValue] = _
  by_cases same : leftValue = rightValue
  · subst rightValue
    simp [ReadOnly.evaluateOperation, Lanius.Semantics.evalBinaryValue,
      Lanius.Semantics.scalarEqual, bind, Except.bind]
    rfl
  · simp [ReadOnly.evaluateOperation, Lanius.Semantics.evalBinaryValue,
      Lanius.Semantics.scalarEqual, same, bind, Except.bind]
    rw [beq_eq_false_iff_ne.mpr same]
    rfl

theorem logicalAnd_evaluates (source records : List Int)
    (environment : Env arity) (left right : Term Core.signature arity)
    (leftValue rightValue : Bool)
    (leftResult : Term.evaluate TM (world source records) environment left =
      .ok (.boolean leftValue, world source records))
    (rightResult : Term.evaluate TM (world source records) environment right =
      .ok (.boolean rightValue, world source records)) :
    Term.evaluate TM (world source records) environment (.logicalAnd left right) =
      .ok (.boolean (leftValue && rightValue), world source records) := by
  cases leftValue
  · simpa using Term.evaluate_logicalAnd_false leftResult
  · simpa using Term.evaluate_logicalAnd_true leftResult rightResult

theorem secondPredicate_evaluates (source records : List Int)
    (rawCount output range : Nat)
    (currentBound : 3 * range < records.length)
    (nextBound : 3 * (range + 1) < records.length)
    (nextStartBound : 3 * (range + 1) + 1 < records.length)
    (currentFinishBound : 3 * range + 2 < records.length)
    (nextStartFits : 3 * (range + 1) + 1 ≤ 2147483647)
    (currentFinishFits : 3 * range + 2 ≤ 2147483647) :
    Term.evaluate TM (world source records)
        (afterNextEnvironment source records rawCount output range)
        CanonicalizeStructure.secondPredicate =
      .ok (.boolean (secondMatches records range), world source records) := by
  let environment := afterNextEnvironment source records rawCount output range
  have currentRead := afterNext_currentIndex_evaluates source records
    rawCount output range currentBound
  have nextRead := afterNext_nextIndex_evaluates source records
    rawCount output range nextBound
  have nextStartRead := afterNext_nextStartIndex_evaluates source records
    rawCount output range nextStartFits nextStartBound
  have currentFinishRead := afterNext_currentFinishIndex_evaluates source records
    rawCount output range currentFinishFits currentFinishBound
  have dotDot := canonicalizeConstant_evaluates source records environment
    87 182 canonicalize_constants.1
  have assign := canonicalizeConstant_evaluates source records environment
    14 8 canonicalize_constants.2.1
  have currentEq := equalInt_evaluates source records environment _ _ _ _
    currentRead dotDot
  have nextEq := equalInt_evaluates source records environment _ _ _ _
    nextRead assign
  have spansEq := equalInt_evaluates source records environment _ _ _ _
    nextStartRead currentFinishRead
  have firstTwo := logicalAnd_evaluates source records environment _ _ _ _
    currentEq nextEq
  have allThree := logicalAnd_evaluates source records environment _ _ _ _
    firstTwo spansEq
  simpa [CanonicalizeStructure.secondPredicate, secondMatches,
    environment, getElem!_pos, currentBound, nextBound, nextStartBound,
    currentFinishBound] using allThree

theorem secondWrite_evaluates (source records : List Int)
    (rawCount output range : Nat)
    (recordsLength : records.length = 3 * rawCount)
    (rangeBound : range + 1 < output) (outputBound : output ≤ rawCount) :
    evaluateActionWith
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls)
        (world source records)
        (afterNextEnvironment source records rawCount output range)
        (.setI32Index ⟨1, by omega⟩
          (CanonicalizeStructure.slot ⟨6, by omega⟩)
          (CanonicalizeStructure.constant 88)) =
      .ok (world source
        (Lanius.Semantics.setI32Value records (3 * range) 189)) := by
  have positionBound : 3 * range < records.length := by omega
  have rangeRawBound : range < rawCount := by omega
  have indexResult :
      Term.evaluate
          (termMachine (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedFrontendCore calls))
          (world source records)
          (afterNextEnvironment source records rawCount output range)
          (CanonicalizeStructure.slot ⟨6, by omega⟩) =
        .ok (.signed .i32 (Int.ofNat (3 * range)), world source records) := by
    simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    rw [afterNextEnvironment_current]
    congr 2
  have valueResult :
      Term.evaluate
          (termMachine (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedFrontendCore calls))
          (world source records)
          (afterNextEnvironment source records rawCount output range)
          (CanonicalizeStructure.constant 88) =
        .ok (.signed .i32 189, world source records) := by
    exact canonicalizeConstant_evaluates source records
      (afterNextEnvironment source records rawCount output range)
      88 189 canonicalize_constants.2.2
  simp only [evaluateActionWith]
  rw [indexResult]
  simp only [bind, Except.bind]
  rw [valueResult]
  simp only [bind, Except.bind]
  rw [afterNextEnvironment_records]
  have indexNonnegative : ¬(3 * (range : Int)) < 0 := by omega
  have indexToNat : (3 * (range : Int)).toNat = 3 * range := by
    rw [Int.toNat_mul (by omega) (by omega), Int.toNat_natCast]
    rfl
  simp [writeI32Slice, CanonicalizeStructure.i32, world_records,
    recordsLength, positionBound, indexNonnegative, indexToNat,
    rangeRawBound, set_records_world]

private def secondBodyRun (source records : List Int)
    (rawCount output range : Nat) :=
  Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
    (world source records)
    (secondEnvironment source records rawCount output range)
    CanonicalizeStructure.secondBody

theorem secondBody_runs (source records : List Int)
    (rawCount output range : Nat)
    (rangeBound : range + 1 < output)
    (outputBound : output ≤ rawCount)
    (recordsLength : records.length = 3 * rawCount)
    (recordWordsFitI32 : 3 * rawCount ≤ 2147483647) :
    secondBodyRun source records rawCount output range = some
      (.next, world source (secondStepRecords records range),
        secondEnvironment source (secondStepRecords records range)
          rawCount output (range + 1)) := by
  have currentBound : 3 * range < records.length := by omega
  have nextBound : 3 * (range + 1) < records.length := by omega
  have nextStartBound : 3 * (range + 1) + 1 < records.length := by omega
  have currentFinishBound : 3 * range + 2 < records.length := by omega
  have currentFits : 3 * range ≤ 2147483647 := by omega
  have nextFits : 3 * (range + 1) ≤ 2147483647 := by omega
  have nextStartFits : 3 * (range + 1) + 1 ≤ 2147483647 := by omega
  have currentFinishFits : 3 * range + 2 ≤ 2147483647 := by omega
  have rangeSuccFits : range + 1 ≤ 2147483647 := by omega
  have rangeWrapped :
      Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
          ((range : Int) + 1) = ((range + 1 : Nat) : Int) := by
    have addEq : (range : Int) + 1 = ((range + 1 : Nat) : Int) := by omega
    rw [addEq]
    exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ rangeSuccFits
  simp only [secondBodyRun, CanonicalizeStructure.secondBody,
    Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [secondCurrentRow_evaluates source records rawCount output range currentFits]
  simp only
  have afterCurrentEq :
      (secondEnvironment source records rawCount output range).push
          (.signed .i32 (3 * (range : Int))) =
        afterCurrentEnvironment source records rawCount output range := rfl
  rw [afterCurrentEq]
  rw [secondNextRow_evaluates source records rawCount output range nextFits]
  simp only
  have afterNextEq :
      (afterCurrentEnvironment source records rawCount output range).push
          (.signed .i32 (3 * ((range : Int) + 1))) =
        afterNextEnvironment source records rawCount output range := rfl
  rw [afterNextEq]
  rw [secondPredicate_evaluates source records rawCount output range
    currentBound nextBound nextStartBound currentFinishBound
    nextStartFits currentFinishFits]
  have constant87 := canonicalize_constants.1
  have constant14 := canonicalize_constants.2.1
  have constant88 := canonicalize_constants.2.2
  by_cases matched : secondMatches records range
  · rw [matched]
    simp only
    simp only [SM, machineWith]
    rw [secondWrite_evaluates source records rawCount output range recordsLength
      rangeBound outputBound]
    simp [secondStepRecords, matched, TM, SM, machineWith,
      Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Effectful.evaluateOperation,
      ReadOnly.evaluateOperation, Lanius.Semantics.evalAssignValue,
      Lanius.Semantics.assignOpBinary?, Lanius.Semantics.evalBinaryValue,
      Lanius.Semantics.evalSignedBinary, Lanius.Semantics.setI32Value,
      CanonicalizeStructure.signed,
      Term.evaluate, Ref.evaluate, world, secondEnvironment,
      afterNextEnvironment, afterCurrentEnvironment, initialEnvironment,
      Env.push, Env.pop, Env.set, bind, Except.bind, rangeSuccFits,
      rangeWrapped]
    exact afterNext_set_range_pop source records
      (Lanius.Semantics.setI32Value records (3 * range) 189)
      rawCount output range (range + 1) (by simp)
  · have matchedFalse : secondMatches records range = false := by
      cases found : secondMatches records range <;> simp_all
    rw [matchedFalse]
    simp [secondStepRecords, matchedFalse, TM, SM, machineWith,
      Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Effectful.evaluateOperation,
      ReadOnly.evaluateOperation, Lanius.Semantics.evalAssignValue,
      Lanius.Semantics.assignOpBinary?, Lanius.Semantics.evalBinaryValue,
      Lanius.Semantics.evalSignedBinary, CanonicalizeStructure.signed,
      Term.evaluate, Ref.evaluate, world, secondEnvironment,
      afterNextEnvironment, afterCurrentEnvironment, initialEnvironment,
      Env.push, Env.pop, Env.set, bind, Except.bind, rangeSuccFits,
      rangeWrapped]
    exact afterNext_set_range_pop source records records rawCount output range
      (range + 1) rfl

def secondPass (records : List Int) (output range : Nat) : List Int × Nat :=
  if inBounds : range + 1 < output then
    secondPass (secondStepRecords records range) output (range + 1)
  else
    (records, range)
termination_by output - range
decreasing_by omega

theorem secondLoop_evaluates (source records : List Int)
    (rawCount output range : Nat) (rangeAtMost : range ≤ output)
    (outputBound : output ≤ rawCount)
    (recordsLength : records.length = 3 * rawCount)
    (recordWordsFitI32 : 3 * rawCount ≤ 2147483647) :
    Command.Evaluates TM SM (world source records)
      (secondEnvironment source records rawCount output range)
      CanonicalizeStructure.secondLoop .next
      (world source (secondPass records output range).1)
      (secondEnvironment source (secondPass records output range).1
        rawCount output (secondPass records output range).2) := by
  by_cases inBounds : range + 1 < output
  · have condition :
        Term.evaluate TM (world source records)
            (secondEnvironment source records rawCount output range)
            CanonicalizeStructure.secondCondition =
          .ok (.boolean true, world source records) := by
      simpa [inBounds] using secondCondition_evaluates source records rawCount
        output range (by omega) (by omega)
    have bodyRun := secondBody_runs source records rawCount output range
      inBounds outputBound recordsLength recordWordsFitI32
    have body :=
      Lanius.FunctionalView.Stateful.Acyclic.run?_sound bodyRun
    have rest := secondLoop_evaluates source (secondStepRecords records range)
      rawCount output (range + 1) (by omega) outputBound
      (by simpa using recordsLength) recordWordsFitI32
    rw [CanonicalizeStructure.secondLoop]
    rw [secondPass]
    simp only [inBounds, dite_true]
    exact .whileNext condition body rest
  · have condition :
        Term.evaluate TM (world source records)
            (secondEnvironment source records rawCount output range)
            CanonicalizeStructure.secondCondition =
          .ok (.boolean false, world source records) := by
      simpa [inBounds] using secondCondition_evaluates source records rawCount
        output range (by omega) (by omega)
    rw [CanonicalizeStructure.secondLoop]
    rw [secondPass]
    simp only [inBounds, dite_false]
    exact .whileFalse condition
termination_by output - range
decreasing_by omega

@[simp] theorem secondPass_length (records : List Int) (output range : Nat) :
    (secondPass records output range).1.length = records.length := by
  by_cases inBounds : range + 1 < output
  · rw [secondPass]
    simp only [inBounds, dite_true]
    rw [secondPass_length]
    exact secondStepRecords_length records range
  · rw [secondPass]
    simp only [inBounds, dite_false]
termination_by output - range
decreasing_by omega

def result (source records : List Int) (rawCount : Nat) : List Int × Nat :=
  let compacted := firstPass source rawCount 0 records 0
  let retagged := secondPass compacted.1 compacted.2 0
  (retagged.1, compacted.2)

theorem zero_evaluates (source records : List Int) (environment : Env arity) :
    Term.evaluate TM (world source records) environment
        (CanonicalizeStructure.signed 0) =
      .ok (.signed .i32 0, world source records) := by
  simp [CanonicalizeStructure.signed, Term.evaluate, Ref.evaluate]

theorem command_evaluates (source records : List Int) (rawCount : Nat)
    (valid : RowsValid source records rawCount) :
    Command.Evaluates TM SM (world source records)
      (initialEnvironment source records rawCount)
      CanonicalizeStructure.command
      (.returned (some (.signed .i32 (result source records rawCount).2)))
      (world source (result source records rawCount).1)
      (initialEnvironment source (result source records rawCount).1 rawCount) := by
  let compacted := firstPass source rawCount 0 records 0
  let retagged := secondPass compacted.1 compacted.2 0
  have compactedValid := firstPass_valid source records rawCount 0 0
    (by omega) (by omega) valid
  have first := firstLoop_evaluates source records rawCount 0 0
    (by omega) (by omega) valid
  have second := secondLoop_evaluates source compacted.1 rawCount compacted.2 0
    (by omega) compactedValid.2 compactedValid.1.recordsLength
    compactedValid.1.recordWordsFitI32
  have outputResult (currentRecords : List Int) (range : Nat) :
      Term.evaluate TM (world source currentRecords)
          (secondEnvironment source currentRecords rawCount compacted.2 range)
          (CanonicalizeStructure.slot ⟨4, by omega⟩) =
        .ok (.signed .i32 compacted.2, world source currentRecords) := by
    simp only [CanonicalizeStructure.slot, Term.evaluate, Ref.evaluate]
    exact congrArg (fun value : Value =>
      Except.ok (value, world source currentRecords))
      (secondEnvironment_output source currentRecords rawCount compacted.2 range)
  change Command.Evaluates TM SM (world source records)
      (initialEnvironment source records rawCount)
      CanonicalizeStructure.command
      (.returned (some (.signed .i32 compacted.2)))
      (world source retagged.1)
      (initialEnvironment source retagged.1 rawCount)
  rw [CanonicalizeStructure.command]
  have afterReturn :
      Command.Evaluates TM SM (world source retagged.1)
        (secondEnvironment source retagged.1 rawCount compacted.2 retagged.2)
        ((Command.returnValue
          (some (CanonicalizeStructure.slot ⟨4, by omega⟩))).sequence
          Command.skip)
        (.returned (some (.signed .i32 compacted.2)))
        (world source retagged.1)
        (secondEnvironment source retagged.1 rawCount compacted.2 retagged.2) := by
    have returned :
        Command.Evaluates TM SM (world source retagged.1)
          (secondEnvironment source retagged.1 rawCount compacted.2 retagged.2)
          (Command.returnValue
            (some (CanonicalizeStructure.slot ⟨4, by omega⟩)))
          (.returned (some (.signed .i32 compacted.2)))
          (world source retagged.1)
          (secondEnvironment source retagged.1 rawCount compacted.2 retagged.2) :=
      .returnSome (outputResult retagged.1 retagged.2)
    exact .sequenceStop returned (by simp)
  have afterSecond :
      Command.Evaluates TM SM (world source compacted.1)
        (secondEnvironment source compacted.1 rawCount compacted.2 0)
        (.sequence CanonicalizeStructure.secondLoop
          ((Command.returnValue
            (some (CanonicalizeStructure.slot ⟨4, by omega⟩))).sequence
            Command.skip))
        (.returned (some (.signed .i32 compacted.2)))
        (world source retagged.1)
        (secondEnvironment source retagged.1 rawCount compacted.2 retagged.2) :=
    .sequenceNext second afterReturn
  have rangeLet := Command.Evaluates.letValue
    (termMachine := TM) (machine := SM)
    (beforeEnvironment := firstEnvironment source compacted.1 rawCount
      rawCount compacted.2)
    (type := CanonicalizeStructure.i32)
    (initializer := CanonicalizeStructure.signed 0)
    (value := .signed .i32 0) (initializedWorld := world source compacted.1)
    (extendedEnvironment := secondEnvironment source retagged.1 rawCount
      compacted.2 retagged.2)
    (zero_evaluates source compacted.1 _) afterSecond
  have afterFirst :
      Command.Evaluates TM SM (world source records)
        (firstEnvironment source records rawCount 0 0)
        (.sequence CanonicalizeStructure.firstLoop
          (.letValue CanonicalizeStructure.i32 (CanonicalizeStructure.signed 0)
            (.sequence CanonicalizeStructure.secondLoop
              ((Command.returnValue
                (some (CanonicalizeStructure.slot ⟨4, by omega⟩))).sequence
                Command.skip))))
        (.returned (some (.signed .i32 compacted.2)))
        (world source retagged.1)
        (firstEnvironment source retagged.1 rawCount rawCount compacted.2) := by
    refine .sequenceNext first ?_
    simpa only [compacted, firstEnvironment, secondEnvironment,
      Env.pop_push] using rangeLet
  have outputLet := Command.Evaluates.letValue
    (termMachine := TM) (machine := SM)
    (beforeEnvironment :=
      (initialEnvironment source records rawCount).push (.signed .i32 0))
    (type := CanonicalizeStructure.i32)
    (initializer := CanonicalizeStructure.signed 0)
    (value := .signed .i32 0) (initializedWorld := world source records)
    (extendedEnvironment := firstEnvironment source retagged.1 rawCount
      rawCount compacted.2)
    (zero_evaluates source records _) afterFirst
  have inputBody :
      Command.Evaluates TM SM (world source records)
        ((initialEnvironment source records rawCount).push (.signed .i32 0))
        (.letValue CanonicalizeStructure.i32 (CanonicalizeStructure.signed 0)
          (.sequence CanonicalizeStructure.firstLoop
            (.letValue CanonicalizeStructure.i32 (CanonicalizeStructure.signed 0)
              (.sequence CanonicalizeStructure.secondLoop
                ((Command.returnValue
                  (some (CanonicalizeStructure.slot ⟨4, by omega⟩))).sequence
                  Command.skip)))))
        (.returned (some (.signed .i32 compacted.2)))
        (world source retagged.1)
        ((initialEnvironment source retagged.1 rawCount).push
          (.signed .i32 rawCount)) := by
    simpa only [firstEnvironment, Env.pop_push] using outputLet
  have inputLet := Command.Evaluates.letValue
    (termMachine := TM) (machine := SM)
    (beforeEnvironment := initialEnvironment source records rawCount)
    (type := CanonicalizeStructure.i32)
    (initializer := CanonicalizeStructure.signed 0)
    (value := .signed .i32 0) (initializedWorld := world source records)
    (extendedEnvironment :=
      (initialEnvironment source retagged.1 rawCount).push
        (.signed .i32 rawCount))
    (zero_evaluates source records _) inputBody
  simpa only [Env.pop_push] using inputLet

end Lanius.Extraction.CanonicalTokens.CanonicalizeExecution
