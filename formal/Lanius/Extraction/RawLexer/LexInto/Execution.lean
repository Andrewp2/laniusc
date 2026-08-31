import Lanius.Extraction.RawLexer.LexInto.Calls
import Lanius.Extraction.RawLexer.LexInto.Model
import Lanius.Extraction.RawLexer.LexInto.Structure
import Lanius.FunctionalViewLoop

namespace Lanius.Extraction.RawLexer.LexInto.Execution

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.Extraction.RawLexer

private abbrev TM (source : List Lexer.Byte) :=
  termMachine
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore (Calls.callModel source))

private abbrev SM (source : List Lexer.Byte) :=
  machineWith verifiedFrontendCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore (Calls.callModel source))

def world (source : List Lexer.Byte) (records : List Int) : ReadOnly.World :=
  ReadOnly.World.pair 0 (ScanOne.Model.sourceIntegers source) 1 records

def initialEnvironment (source : List Lexer.Byte) (records : List Int)
    (capacity : Nat) : Env 4
  | ⟨0, _⟩ => ScanOne.Model.sourceSlice source
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .slice Structure.i32Type 1 [] 0 records.length
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat capacity)

theorem initialEnvironment_length_congr
    (source : List Lexer.Byte) (left right : List Int) (capacity : Nat)
    (sameLength : left.length = right.length) :
    initialEnvironment source left capacity =
      initialEnvironment source right capacity := by
  funext index
  rcases index with ⟨index, bound⟩
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 := by
    omega
  rcases cases with rfl | rfl | rfl | rfl <;>
    simp [initialEnvironment, sameLength]

def loopEnvironment (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) : Env 6 :=
  ((initialEnvironment source records capacity).push
    (.signed .i32 (Int.ofNat offset))).push
    (.signed .i32 (Int.ofNat tokenCount))

theorem loopEnvironment_updated
    (source : List Lexer.Byte) (before after : List Int)
    (capacity oldOffset oldCount newOffset newCount : Nat)
    (sameLength : before.length = after.length) :
    Env.set
        (Env.set (loopEnvironment source before capacity oldOffset oldCount)
          (Structure.offset 6) (.signed .i32 (Int.ofNat newOffset)))
        (Structure.tokenCount 6) (.signed .i32 (Int.ofNat newCount)) =
      loopEnvironment source after capacity newOffset newCount := by
  funext index
  rcases index with ⟨index, bound⟩
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨
      index = 4 ∨ index = 5 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [loopEnvironment, initialEnvironment, Env.set, Env.push,
      Structure.offset,
      Structure.tokenCount, sameLength]

def scannedEnvironment (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (scan : OneTokenResult) : Env 7 :=
  (loopEnvironment source records capacity offset tokenCount).push
    (ScanOne.Model.encoded scan)

def rowEnvironment (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken) : Env 8 :=
  (scannedEnvironment source records capacity offset tokenCount (.token token)).push
    (.signed .i32 (Int.ofNat (3 * tokenCount)))

def afterKind (records : List Int) (tokenCount : Nat) (token : RawToken) :
    List Int :=
  setI32Value records (3 * tokenCount) (Int.ofNat token.kind.gpuCode)

def afterStart (records : List Int) (tokenCount : Nat) (token : RawToken) :
    List Int :=
  setI32Value (afterKind records tokenCount token) (3 * tokenCount + 1)
    (Int.ofNat token.start)

def afterToken (records : List Int) (tokenCount : Nat) (token : RawToken) :
    List Int :=
  setI32Value (afterStart records tokenCount token) (3 * tokenCount + 2)
    (Int.ofNat token.finish)

@[simp] theorem afterKind_length (records : List Int) (tokenCount : Nat)
    (token : RawToken) :
    (afterKind records tokenCount token).length = records.length := by
  simp [afterKind]

@[simp] theorem afterStart_length (records : List Int) (tokenCount : Nat)
    (token : RawToken) :
    (afterStart records tokenCount token).length = records.length := by
  simp [afterStart]

@[simp] theorem afterToken_length (records : List Int) (tokenCount : Nat)
    (token : RawToken) :
    (afterToken records tokenCount token).length = records.length := by
  simp [afterToken]

@[simp] theorem world_source (source : List Lexer.Byte) (records : List Int) :
    (world source records).i32Slice? 0 =
      some (ScanOne.Model.sourceIntegers source) := by
  rfl

@[simp] theorem world_output (source : List Lexer.Byte) (records : List Int) :
    (world source records).i32Slice? 1 = some records := by
  rfl

@[simp] theorem set_output_world (source : List Lexer.Byte)
    (before after : List Int) :
    ReadOnly.World.setI32Slice (world source before) 1 after =
      world source after := by
  exact ReadOnly.World.setI32Slice_pair_second (by decide)

theorem loopCondition_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) :
    Term.evaluate (TM source) (world source records)
        (loopEnvironment source records capacity offset tokenCount)
        Structure.loopCondition =
      .ok (.boolean (offset < source.length), world source records) := by
  have left : Term.evaluate (TM source) (world source records)
      (loopEnvironment source records capacity offset tokenCount)
      (Structure.slot (Structure.offset 6)) =
      .ok (.signed .i32 (Int.ofNat offset), world source records) := by
    rfl
  have right : Term.evaluate (TM source) (world source records)
      (loopEnvironment source records capacity offset tokenCount)
      (Structure.sourceLength 6) =
      .ok (.signed .i32 (Int.ofNat source.length), world source records) := by
    rfl
  apply Term.evaluate_apply2 left right
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
    verifiedFrontendCore (Calls.callModel source) (world source records)
      (.binary .less Structure.i32Type Structure.i32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat offset),
        .signed .i32 (Int.ofNat source.length)] = _
  change ReadOnly.evaluateOperation verifiedFrontendCore
    (world source records)
      (.binary .less Structure.i32Type Structure.i32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat offset),
        .signed .i32 (Int.ofNat source.length)] = _
  exact ReadOnly.evaluateOperation_i32_less
    (program := verifiedFrontendCore) (world := world source records)
    (leftType := Structure.i32Type) (rightType := Structure.i32Type)
    (outputType := .scalar .bool) offset source.length

def completionOf : Model.Outcome →
    Lanius.FunctionalView.Stateful.Completion
  | .completed _ => .next
  | outcome => .returned (some (Model.resultValue outcome))

@[simp] theorem afterToken_eq_writeToken
    (records : List Int) (tokenCount : Nat) (token : RawToken) :
    afterToken records tokenCount token =
      Model.writeToken records tokenCount token := by
  rfl

theorem scanOneTerm_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat)
    (sourceBound : source.length ≤ 2147483646)
    (offsetBound : offset ≤ 2147483647) :
    Term.evaluate (TM source) (world source records)
        (loopEnvironment source records capacity offset tokenCount)
        Structure.scanOneTerm =
      .ok (ScanOne.Model.encoded (Lexer.scanOne source offset),
        world source records) := by
  rw [Structure.scanOneTerm, Structure.call]
  apply Term.evaluate_apply
  · rfl
  · exact Calls.scanOne source (world source records) offset
      sourceBound offsetBound (world_source _ _)

theorem scanFailedCondition_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (scan : OneTokenResult) :
    Term.evaluate (TM source) (world source records)
        (scannedEnvironment source records capacity offset tokenCount scan)
        Structure.scanFailedCondition =
      .ok (.boolean (match scan with | .failure _ => true | .token _ => false),
        world source records) := by
  cases scan with
  | failure errorOffset =>
      apply Term.evaluate_apply1
      · apply Term.evaluate_apply1
        · rfl
        · exact Calls.succeeded source (world source records) false 0 0
            (Int.ofNat errorOffset)
      · change ReadOnly.evaluateOperation verifiedFrontendCore
          (world source records)
          (.unary .logicalNot (.scalar .bool) (.scalar .bool))
          [.boolean false] = _
        rfl
  | token token =>
      apply Term.evaluate_apply1
      · apply Term.evaluate_apply1
        · rfl
        · exact Calls.succeeded source (world source records) true
            (Int.ofNat token.kind.gpuCode) (Int.ofNat token.finish) 0
      · change ReadOnly.evaluateOperation verifiedFrontendCore
          (world source records)
          (.unary .logicalNot (.scalar .bool) (.scalar .bool))
          [.boolean true] = _
        rfl

theorem lexicalFailureTerm_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount error : Nat) :
    Term.evaluate (TM source) (world source records)
        (scannedEnvironment source records capacity offset tokenCount
          (.failure error)) Structure.lexicalFailureTerm =
      .ok (Results.Semantics.value 1 (Int.ofNat tokenCount)
        (Int.ofNat error), world source records) := by
  rw [Structure.lexicalFailureTerm, Structure.call]
  apply Term.evaluate_apply
  · apply evaluateTerms_cons
    · rfl
    · apply evaluateTerms_cons
      · rw [Structure.scanErrorTerm, Structure.call]
        apply Term.evaluate_apply1
        · rfl
        · exact Calls.errorOffset source (world source records) false 0 0
            (Int.ofNat error)
      · exact evaluateTerms_nil _ _ _
  · exact Calls.lexicalFailure source (world source records)
      (Int.ofNat tokenCount) (Int.ofNat error)

theorem outputFullTerm_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken) :
    Term.evaluate (TM source) (world source records)
        (scannedEnvironment source records capacity offset tokenCount
          (.token token)) Structure.outputFullTerm =
      .ok (Results.Semantics.value 2 (Int.ofNat tokenCount)
        (Int.ofNat offset), world source records) := by
  rw [Structure.outputFullTerm, Structure.call]
  apply Term.evaluate_apply
  · rfl
  · exact Calls.outputFull source (world source records)
      (Int.ofNat tokenCount) (Int.ofNat offset)

theorem completedTerm_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) :
    Term.evaluate (TM source) (world source records)
        (loopEnvironment source records capacity offset tokenCount)
        Structure.completedTerm =
      .ok (Results.Semantics.value 0 (Int.ofNat tokenCount) 0,
        world source records) := by
  rw [Structure.completedTerm, Structure.call]
  apply Term.evaluate_apply1
  · rfl
  · exact Calls.completed source (world source records)
      (Int.ofNat tokenCount)

theorem outputFullCondition_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (scan : OneTokenResult) :
    Term.evaluate (TM source) (world source records)
        (scannedEnvironment source records capacity offset tokenCount scan)
        Structure.outputFullCondition =
      .ok (.boolean (tokenCount ≥ capacity), world source records) := by
  have left : Term.evaluate (TM source) (world source records)
      (scannedEnvironment source records capacity offset tokenCount scan)
      (Structure.slot (Structure.tokenCount 7)) =
      .ok (.signed .i32 (Int.ofNat tokenCount), world source records) := by
    rfl
  have right : Term.evaluate (TM source) (world source records)
      (scannedEnvironment source records capacity offset tokenCount scan)
      (Structure.outputCapacity 7) =
      .ok (.signed .i32 (Int.ofNat capacity), world source records) := by
    rfl
  apply Term.evaluate_apply2 left right
  change ReadOnly.evaluateOperation verifiedFrontendCore
    (world source records)
      (.binary .greaterEqual Structure.i32Type Structure.i32Type
        (.scalar .bool))
      [.signed .i32 (Int.ofNat tokenCount),
        .signed .i32 (Int.ofNat capacity)] = _
  exact ReadOnly.evaluateOperation_i32_greaterEqual
    (program := verifiedFrontendCore) (world := world source records)
    (leftType := Structure.i32Type) (rightType := Structure.i32Type)
    (outputType := .scalar .bool) tokenCount capacity

theorem rowTerm_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken)
    (bounded : 3 * tokenCount ≤ 2147483647) :
    Term.evaluate (TM source) (world source records)
        (scannedEnvironment source records capacity offset tokenCount
          (.token token)) Structure.rowTerm =
      .ok (.signed .i32 (Int.ofNat (3 * tokenCount)),
        world source records) := by
  have left : Term.evaluate (TM source) (world source records)
      (scannedEnvironment source records capacity offset tokenCount
        (.token token))
      (Structure.slot (Structure.tokenCount 7)) =
      .ok (.signed .i32 (Int.ofNat tokenCount), world source records) := by
    rfl
  have right : Term.evaluate (TM source) (world source records)
      (scannedEnvironment source records capacity offset tokenCount
        (.token token)) (Structure.i32 3) =
      .ok (.signed .i32 3, world source records) := by
    rfl
  apply Term.evaluate_apply2 left right
  change ReadOnly.evaluateOperation verifiedFrontendCore
      (world source records)
      (.binary .multiply Structure.i32Type Structure.i32Type Structure.i32Type)
      [.signed .i32 (Int.ofNat tokenCount), .signed .i32 3] = _
  simp [ReadOnly.evaluateOperation, evalBinaryValue, evalSignedBinary, bind,
    Except.bind]
  have inputEq : (Int.ofNat tokenCount * 3) =
      Int.ofNat (3 * tokenCount) := by
    calc
      Int.ofNat tokenCount * 3 =
          Int.ofNat tokenCount * Int.ofNat 3 := rfl
      _ = Int.ofNat (tokenCount * 3) :=
        (Int.natCast_mul tokenCount 3).symm
      _ = Int.ofNat (3 * tokenCount) := by rw [Nat.mul_comm]
  have wrappedEq :
      wrapSigned verifiedFrontendCore.target .i32
          (Int.ofNat tokenCount * 3) = Int.ofNat (3 * tokenCount) :=
    (congrArg (wrapSigned verifiedFrontendCore.target .i32) inputEq).trans
      (wrapSigned_i32_ofNat verifiedFrontendCore.target _ bounded)
  have outputEq : Int.ofNat (3 * tokenCount) =
      3 * Int.ofNat tokenCount := by
    exact inputEq.symm.trans (Int.mul_comm _ _)
  have integerEq := wrappedEq.trans outputEq
  have valueEq :
      Value.signed .i32
          (wrapSigned verifiedFrontendCore.target .i32
            (Int.ofNat tokenCount * 3)) =
        Value.signed .i32 (3 * Int.ofNat tokenCount) :=
    congrArg (Value.signed .i32) integerEq
  have pairEq :
      (Value.signed .i32
          (wrapSigned verifiedFrontendCore.target .i32
            (Int.ofNat tokenCount * 3)), world source records) =
        (Value.signed .i32 (3 * Int.ofNat tokenCount), world source records) :=
    congrArg (fun value : Value => (value, world source records)) valueEq
  have resultEq :
      (Except.ok (Value.signed .i32
          (wrapSigned verifiedFrontendCore.target .i32
            (Int.ofNat tokenCount * 3)), world source records) :
          Except Trap (Value × ReadOnly.World)) =
        .ok (Value.signed .i32 (3 * Int.ofNat tokenCount),
          world source records) := congrArg Except.ok pairEq
  exact resultEq

theorem scanKindTerm_evaluates
    (source : List Lexer.Byte) (worldRecords environmentRecords : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken) :
    Term.evaluate (TM source) (world source worldRecords)
        (rowEnvironment source environmentRecords capacity offset tokenCount token)
        (Structure.scanKindTerm 8) =
      .ok (.signed .i32 (Int.ofNat token.kind.gpuCode),
        world source worldRecords) := by
  rw [Structure.scanKindTerm, Structure.call]
  apply Term.evaluate_apply1
  · rfl
  · exact Calls.kind source (world source worldRecords) true
      (Int.ofNat token.kind.gpuCode) (Int.ofNat token.finish) 0

theorem scanEndTerm_evaluates
    (source : List Lexer.Byte) (worldRecords environmentRecords : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken) :
    Term.evaluate (TM source) (world source worldRecords)
        (rowEnvironment source environmentRecords capacity offset tokenCount token)
        (Structure.scanEndTerm 8) =
      .ok (.signed .i32 (Int.ofNat token.finish), world source worldRecords) := by
  rw [Structure.scanEndTerm, Structure.call]
  apply Term.evaluate_apply1
  · rfl
  · exact Calls.endOffset source (world source worldRecords) true
      (Int.ofNat token.kind.gpuCode) (Int.ofNat token.finish) 0

theorem rowPlus_evaluates
    (source : List Lexer.Byte) (worldRecords environmentRecords : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken) (amount : Nat)
    (bounded : 3 * tokenCount + amount ≤ 2147483647) :
    Term.evaluate (TM source) (world source worldRecords)
        (rowEnvironment source environmentRecords capacity offset tokenCount token)
        (Structure.rowPlus (Int.ofNat amount)) =
      .ok (.signed .i32 (Int.ofNat (3 * tokenCount + amount)),
        world source worldRecords) := by
  have left : Term.evaluate (TM source) (world source worldRecords)
      (rowEnvironment source environmentRecords capacity offset tokenCount token)
      (Structure.slot Structure.row) =
      .ok (.signed .i32 (Int.ofNat (3 * tokenCount)),
        world source worldRecords) := by
    rfl
  have right : Term.evaluate (TM source) (world source worldRecords)
      (rowEnvironment source environmentRecords capacity offset tokenCount token)
      (Structure.i32 (Int.ofNat amount)) =
      .ok (.signed .i32 (Int.ofNat amount), world source worldRecords) := by
    rfl
  apply Term.evaluate_apply2 left right
  change ReadOnly.evaluateOperation verifiedFrontendCore
      (world source worldRecords)
      (.binary .add Structure.i32Type Structure.i32Type Structure.i32Type)
      [.signed .i32 (Int.ofNat (3 * tokenCount)),
        .signed .i32 (Int.ofNat amount)] = _
  exact ReadOnly.evaluateOperation_i32_add
    (program := verifiedFrontendCore) (world := world source worldRecords)
    (leftType := Structure.i32Type) (rightType := Structure.i32Type)
    (outputType := Structure.i32Type) (3 * tokenCount) amount bounded

theorem write_evaluates
    (source : List Lexer.Byte) (records : List Int) (environment : Env 8)
    (index replacement : Term Lanius.FunctionalView.Core.signature 8)
    (position : Nat) (replacementValue : Int)
    (baseValue : environment (Structure.output 8) =
      .slice Structure.i32Type 1 [] 0 records.length)
    (indexResult : Term.evaluate (TM source) (world source records) environment
      index = .ok (.signed .i32 (Int.ofNat position), world source records))
    (replacementResult : Term.evaluate (TM source) (world source records)
      environment replacement =
        .ok (.signed .i32 replacementValue, world source records))
    (inBounds : position < records.length) :
    Command.Evaluates (TM source) (SM source) (world source records)
      environment (Structure.write index replacement) .next
      (world source (Lanius.Semantics.setI32Value records position
        replacementValue))
      environment := by
  apply Command.Evaluates.action
  change evaluateActionWith
      (Lanius.FunctionalView.Core.Effectful.evaluateOperation
        verifiedFrontendCore (Calls.callModel source))
      (world source records) environment
      (.setI32Index (Structure.output 8) index replacement) = _
  simp only [evaluateActionWith, indexResult, replacementResult, bind,
    Except.bind]
  simp [writeI32Slice, Structure.i32Type, baseValue, world_output, inBounds,
    set_output_world]
  split
  · omega
  · rfl

theorem loopBody_lexicalFailure
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount error : Nat)
    (sourceBound : source.length ≤ 2147483646)
    (offsetBound : offset ≤ 2147483647)
    (scanned : Lexer.scanOne source offset = .failure error) :
    Command.Evaluates (TM source) (SM source) (world source records)
        (loopEnvironment source records capacity offset tokenCount)
        Structure.loopBody
        (.returned (some (Results.Semantics.value 1 (Int.ofNat tokenCount)
          (Int.ofNat error))))
        (world source records)
        (loopEnvironment source records capacity offset tokenCount) := by
  rw [Structure.loopBody]
  have body : Command.Evaluates (TM source) (SM source)
      (world source records)
      (scannedEnvironment source records capacity offset tokenCount
        (.failure error))
      Structure.loopBodyAfterScan
      (.returned (some (Results.Semantics.value 1 (Int.ofNat tokenCount)
        (Int.ofNat error))))
      (world source records)
      (scannedEnvironment source records capacity offset tokenCount
        (.failure error)) := by
    rw [Structure.loopBodyAfterScan]
    apply Command.Evaluates.sequenceStop
    · apply Command.Evaluates.ifTrue
      · exact scanFailedCondition_evaluates source records capacity offset
          tokenCount (.failure error)
      · apply Command.Evaluates.sequenceStop
        · exact Command.Evaluates.returnSome
            (lexicalFailureTerm_evaluates source records capacity offset
              tokenCount error)
        · simp
    · simp
  have total : Command.Evaluates (TM source) (SM source)
      (world source records)
      (loopEnvironment source records capacity offset tokenCount)
      (.letValue Structure.tokenScanType Structure.scanOneTerm
        Structure.loopBodyAfterScan)
      (.returned (some (Results.Semantics.value 1 (Int.ofNat tokenCount)
        (Int.ofNat error))))
      (world source records)
      (Env.pop (scannedEnvironment source records capacity offset tokenCount
        (.failure error))) :=
    Command.Evaluates.letValue
      (by simpa [scanned] using
        (scanOneTerm_evaluates source records capacity offset tokenCount
          sourceBound offsetBound)) body
  simpa only [scannedEnvironment, Env.pop_push] using total

theorem loopBody_outputFull
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken)
    (sourceBound : source.length ≤ 2147483646)
    (offsetBound : offset ≤ 2147483647)
    (scanned : Lexer.scanOne source offset = .token token)
    (full : capacity ≤ tokenCount) :
    Command.Evaluates (TM source) (SM source) (world source records)
        (loopEnvironment source records capacity offset tokenCount)
        Structure.loopBody
        (.returned (some (Results.Semantics.value 2 (Int.ofNat tokenCount)
          (Int.ofNat offset))))
        (world source records)
        (loopEnvironment source records capacity offset tokenCount) := by
  rw [Structure.loopBody]
  have body : Command.Evaluates (TM source) (SM source)
      (world source records)
      (scannedEnvironment source records capacity offset tokenCount
        (.token token))
      Structure.loopBodyAfterScan
      (.returned (some (Results.Semantics.value 2 (Int.ofNat tokenCount)
        (Int.ofNat offset))))
      (world source records)
      (scannedEnvironment source records capacity offset tokenCount
        (.token token)) := by
    rw [Structure.loopBodyAfterScan]
    apply Command.Evaluates.sequenceNext
    · apply Command.Evaluates.ifFalse
      · exact scanFailedCondition_evaluates source records capacity offset
          tokenCount (.token token)
      · exact .skip
    · apply Command.Evaluates.sequenceStop
      · apply Command.Evaluates.ifTrue
        · simpa [full] using outputFullCondition_evaluates source records
            capacity offset tokenCount (.token token)
        · apply Command.Evaluates.sequenceStop
          · exact .returnSome (outputFullTerm_evaluates source records
              capacity offset tokenCount token)
          · simp
      · simp
  have total : Command.Evaluates (TM source) (SM source)
      (world source records)
      (loopEnvironment source records capacity offset tokenCount)
      (.letValue Structure.tokenScanType Structure.scanOneTerm
        Structure.loopBodyAfterScan)
      (.returned (some (Results.Semantics.value 2 (Int.ofNat tokenCount)
        (Int.ofNat offset))))
      (world source records)
      (Env.pop (scannedEnvironment source records capacity offset tokenCount
        (.token token))) :=
    .letValue
      (by simpa [scanned] using
        (scanOneTerm_evaluates source records capacity offset tokenCount
          sourceBound offsetBound)) body
  simpa only [scannedEnvironment, Env.pop_push] using total

theorem loopBody_token
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken)
    (sourceBound : source.length ≤ 2147483646)
    (offsetBound : offset ≤ 2147483647)
    (scanned : Lexer.scanOne source offset = .token token)
    (startEq : token.start = offset)
    (room : tokenCount < capacity)
    (recordsLength : records.length = 3 * capacity)
    (capacityBound : 3 * capacity ≤ 2147483647) :
    Command.Evaluates (TM source) (SM source) (world source records)
        (loopEnvironment source records capacity offset tokenCount)
        Structure.loopBody .next
        (world source (afterToken records tokenCount token))
        (loopEnvironment source (afterToken records tokenCount token) capacity
          token.finish (tokenCount + 1)) := by
  have rowBound : 3 * tokenCount ≤ 2147483647 := by omega
  have rowOneBound : 3 * tokenCount + 1 ≤ 2147483647 := by omega
  have rowTwoBound : 3 * tokenCount + 2 ≤ 2147483647 := by omega
  have countBound : tokenCount + 1 ≤ 2147483647 := by omega
  have rowInBounds : 3 * tokenCount < records.length := by omega
  have rowOneInBounds : 3 * tokenCount + 1 < records.length := by omega
  have rowTwoInBounds : 3 * tokenCount + 2 < records.length := by omega
  let rowEnv := rowEnvironment source records capacity offset tokenCount token
  let records1 := afterKind records tokenCount token
  let records2 := afterStart records tokenCount token
  let records3 := afterToken records tokenCount token
  have writeKind : Command.Evaluates (TM source) (SM source)
      (world source records) rowEnv
      (Structure.write (Structure.slot Structure.row)
        (Structure.scanKindTerm 8)) .next
      (world source records1) rowEnv := by
    apply write_evaluates source records rowEnv _ _ (3 * tokenCount)
      (Int.ofNat token.kind.gpuCode)
    · rfl
    · rfl
    · exact scanKindTerm_evaluates source records records capacity offset
        tokenCount token
    · exact rowInBounds
  have writeStart : Command.Evaluates (TM source) (SM source)
      (world source records1) rowEnv
      (Structure.write (Structure.rowPlus 1)
        (Structure.slot (Structure.offset 8))) .next
      (world source records2) rowEnv := by
    apply write_evaluates source records1 rowEnv _ _ (3 * tokenCount + 1)
      (Int.ofNat token.start)
    · change Value.slice Structure.i32Type 1 [] 0 records.length =
        Value.slice Structure.i32Type 1 [] 0 records1.length
      simp [records1]
    · simpa [rowEnv] using rowPlus_evaluates source records1 records
        capacity offset tokenCount token 1 rowOneBound
    · change Term.evaluate (TM source) (world source records1)
        (rowEnvironment source records capacity offset tokenCount token)
        (Structure.slot (Structure.offset 8)) =
          .ok (.signed .i32 (Int.ofNat token.start), world source records1)
      rw [startEq]
      rfl
    · simpa [records1] using rowOneInBounds
  have writeEnd : Command.Evaluates (TM source) (SM source)
      (world source records2) rowEnv
      (Structure.write (Structure.rowPlus 2)
        (Structure.scanEndTerm 8)) .next
      (world source records3) rowEnv := by
    apply write_evaluates source records2 rowEnv _ _ (3 * tokenCount + 2)
      (Int.ofNat token.finish)
    · change Value.slice Structure.i32Type 1 [] 0 records.length =
        Value.slice Structure.i32Type 1 [] 0 records2.length
      simp [records2]
    · simpa [rowEnv] using rowPlus_evaluates source records2 records
        capacity offset tokenCount token 2 rowTwoBound
    · simpa [rowEnv] using scanEndTerm_evaluates source records2 records
        capacity offset tokenCount token
    · simpa [records2] using rowTwoInBounds
  have setOffset : Command.Evaluates (TM source) (SM source)
      (world source records3) rowEnv
      (.setLocal (Structure.offset 8) (Structure.scanEndTerm 8)) .next
      (world source records3)
      (Env.set rowEnv (Structure.offset 8)
        (.signed .i32 (Int.ofNat token.finish))) := by
    apply Command.Evaluates.setLocal
    simpa [rowEnv] using scanEndTerm_evaluates source records3 records
      capacity offset tokenCount token
  let offsetEnv := Env.set rowEnv (Structure.offset 8)
    (.signed .i32 (Int.ofNat token.finish))
  have oneResult : Term.evaluate (TM source) (world source records3) offsetEnv
      (Structure.i32 1) =
      .ok (.signed .i32 1, world source records3) := by rfl
  have currentCount : offsetEnv (Structure.tokenCount 8) =
      .signed .i32 (Int.ofNat tokenCount) := by
    dsimp [offsetEnv]
    have different : Structure.tokenCount 8 ≠ Structure.offset 8 := by
      intro equal
      have values := congrArg Fin.val equal
      change (5 : Nat) = 4 at values
      omega
    rw [Env.set_other _ _ _ _ different]
    rfl
  have updateResult : (SM source).evalLocalUpdate .add
      (offsetEnv (Structure.tokenCount 8)) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (tokenCount + 1))) := by
    have addition : Int.ofNat tokenCount + 1 =
        Int.ofNat (tokenCount + 1) := by simp
    rw [currentCount]
    change evalAssignValue verifiedFrontendCore.target .add
      (some (.signed .i32 (Int.ofNat tokenCount))) (.signed .i32 1) = _
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    rw [addition, wrapSigned_i32_ofNat _ _ countBound]
  have updateCount : Command.Evaluates (TM source) (SM source)
      (world source records3) offsetEnv
      (.updateLocal .add (Structure.tokenCount 8) (Structure.i32 1)) .next
      (world source records3)
      (Env.set offsetEnv (Structure.tokenCount 8)
        (.signed .i32 (Int.ofNat (tokenCount + 1)))) :=
    .updateLocal oneResult updateResult
  have afterRow : Command.Evaluates (TM source) (SM source)
      (world source records) rowEnv Structure.loopBodyAfterRow .next
      (world source records3)
      (Env.set offsetEnv (Structure.tokenCount 8)
        (.signed .i32 (Int.ofNat (tokenCount + 1)))) := by
    rw [Structure.loopBodyAfterRow]
    exact .sequenceNext writeKind (.sequenceNext writeStart
      (.sequenceNext writeEnd (.sequenceNext setOffset
        (.sequenceNext updateCount .skip))))
  have afterScan : Command.Evaluates (TM source) (SM source)
      (world source records)
      (scannedEnvironment source records capacity offset tokenCount
        (.token token))
      Structure.loopBodyAfterScan .next (world source records3)
      (Env.pop (Env.set offsetEnv (Structure.tokenCount 8)
        (.signed .i32 (Int.ofNat (tokenCount + 1))))) := by
    rw [Structure.loopBodyAfterScan]
    exact .sequenceNext
      (.ifFalse (scanFailedCondition_evaluates source records capacity offset
        tokenCount (.token token)) .skip)
      (.sequenceNext
        (.ifFalse
          (by
            have evaluated := outputFullCondition_evaluates source records
              capacity offset tokenCount (.token token)
            simpa [Nat.not_le.mpr room] using evaluated)
          .skip)
        (.letValue (rowTerm_evaluates source records capacity offset tokenCount
          token rowBound) afterRow))
  have total : Command.Evaluates (TM source) (SM source)
      (world source records)
      (loopEnvironment source records capacity offset tokenCount)
      Structure.loopBody .next (world source records3)
      (Env.pop (Env.pop (Env.set offsetEnv (Structure.tokenCount 8)
        (.signed .i32 (Int.ofNat (tokenCount + 1)))))) := by
    rw [Structure.loopBody]
    exact .letValue
      (by simpa [scanned] using
        (scanOneTerm_evaluates source records capacity offset tokenCount
          sourceBound offsetBound))
      afterScan
  have environmentEq :
      Env.pop (Env.pop (Env.set offsetEnv (Structure.tokenCount 8)
        (.signed .i32 (Int.ofNat (tokenCount + 1))))) =
      loopEnvironment source records3 capacity token.finish
        (tokenCount + 1) := by
    have popped :
        Env.pop (Env.pop (Env.set offsetEnv (Structure.tokenCount 8)
          (.signed .i32 (Int.ofNat (tokenCount + 1))))) =
        Env.set
          (Env.set (loopEnvironment source records capacity offset tokenCount)
            (Structure.offset 6) (.signed .i32 (Int.ofNat token.finish)))
          (Structure.tokenCount 6)
          (.signed .i32 (Int.ofNat (tokenCount + 1))) := by
      unfold offsetEnv rowEnv rowEnvironment scannedEnvironment
      rw [Env.pop_set_of_lt (before := by change 5 < 7; omega)]
      rw [Env.pop_set_of_lt (before := by change 5 < 6; omega)]
      rw [Env.pop_set_of_lt (before := by change 4 < 7; omega)]
      rw [Env.pop_set_of_lt (before := by change 4 < 6; omega)]
      rw [Env.pop_push]
      rw [Env.pop_push]
      congr 2 <;> apply Fin.ext <;> rfl
    exact popped.trans (loopEnvironment_updated source records records3
      capacity offset tokenCount token.finish (tokenCount + 1)
      (by
        simpa [records3] using
          (afterToken_length records tokenCount token).symm))
  rw [environmentEq] at total
  simpa only [records3] using total

theorem loop_evaluates_runFromFuel
    (source : List Lexer.Byte) (capacity fuel offset tokenCount : Nat)
    (accepted : List RawToken) (records : List Int)
    (sourceBound : source.length ≤ 2147483646)
    (enoughFuel : source.length - offset < fuel)
    (acceptedCount : accepted.length = tokenCount)
    (countFits : tokenCount ≤ capacity)
    (recordsLength : records.length = 3 * capacity)
    (capacityBound : 3 * capacity ≤ 2147483647) :
    let result := Model.runFromFuel source capacity fuel offset tokenCount
      accepted records
    Command.Evaluates (TM source) (SM source) (world source records)
      (loopEnvironment source records capacity offset tokenCount)
      Structure.loop (completionOf result.outcome)
      (world source result.records)
      (loopEnvironment source result.records capacity result.offset
        result.tokenCount) := by
  induction fuel generalizing offset tokenCount accepted records with
  | zero => omega
  | succ fuel induction =>
      rw [Model.runFromFuel]
      by_cases atEnd : source.length ≤ offset
      · simp only [if_pos atEnd, completionOf]
        rw [Structure.loop]
        exact .whileFalse (by
          simpa [show ¬offset < source.length by omega] using
            (loopCondition_evaluates source records capacity offset tokenCount))
      · have beforeEnd : offset < source.length := by omega
        have offsetBound : offset ≤ 2147483647 := by omega
        rw [if_neg atEnd]
        cases scanned : Lexer.scanOne source offset with
        | failure error =>
            simp only [completionOf, Model.resultValue]
            rw [acceptedCount]
            rw [Structure.loop]
            exact .whileReturn
              (by simpa [beforeEnd] using
                (loopCondition_evaluates source records capacity offset
                  tokenCount))
              (loopBody_lexicalFailure source records capacity offset
                tokenCount error sourceBound offsetBound scanned)
        | token token =>
            simp only [scanned]
            by_cases full : capacity ≤ tokenCount
            · simp only [if_pos full, completionOf, Model.resultValue]
              rw [acceptedCount]
              rw [Structure.loop]
              exact .whileReturn
                (by simpa [beforeEnd] using
                  (loopCondition_evaluates source records capacity offset
                    tokenCount))
                (loopBody_outputFull source records capacity offset tokenCount
                  token sourceBound offsetBound scanned full)
            · have room : tokenCount < capacity := by omega
              rw [if_neg full]
              have advances := Lexer.scanOne_token_advances scanned
              have tailFuel : source.length - token.finish < fuel := by omega
              have nextCountFits : tokenCount + 1 ≤ capacity := by omega
              have nextAcceptedCount :
                  (accepted ++ [token]).length = tokenCount + 1 := by
                simp [acceptedCount]
              have nextRecordsLength :
                  (afterToken records tokenCount token).length =
                    3 * capacity := by
                calc
                  (afterToken records tokenCount token).length = records.length :=
                    afterToken_length records tokenCount token
                  _ = 3 * capacity := recordsLength
              have rest := induction token.finish (tokenCount + 1)
                (accepted ++ [token])
                (afterToken records tokenCount token) tailFuel nextAcceptedCount
                nextCountFits nextRecordsLength
              rw [Structure.loop]
              exact .whileNext
                (by simpa [beforeEnd] using
                  (loopCondition_evaluates source records capacity offset
                    tokenCount))
                (loopBody_token source records capacity offset tokenCount token
                  sourceBound offsetBound scanned
                  (Model.scanOne_token_start scanned)
                  room recordsLength
                  capacityBound)
                (by simpa [afterToken_eq_writeToken, Structure.loop] using rest)

theorem loop_evaluates_run
    (source : List Lexer.Byte) (capacity : Nat) (records : List Int)
    (sourceBound : source.length ≤ 2147483646)
    (recordsLength : records.length = 3 * capacity)
    (capacityBound : 3 * capacity ≤ 2147483647) :
    let result := Model.run source capacity records
    Command.Evaluates (TM source) (SM source) (world source records)
      (loopEnvironment source records capacity 0 0)
      Structure.loop (completionOf result.outcome)
      (world source result.records)
      (loopEnvironment source result.records capacity result.offset
        result.tokenCount) := by
  exact loop_evaluates_runFromFuel source capacity (source.length + 1) 0 0
    [] records sourceBound (by simp) (by simp) (by simp) recordsLength
    capacityBound

theorem command_evaluates_run
    (source : List Lexer.Byte) (capacity : Nat) (records : List Int)
    (sourceBound : source.length ≤ 2147483646)
    (recordsLength : records.length = 3 * capacity)
    (capacityBound : 3 * capacity ≤ 2147483647) :
    let result := Model.run source capacity records
    Command.Evaluates (TM source) (SM source) (world source records)
      (initialEnvironment source records capacity) Structure.command
      (.returned (some (Model.resultValue result.outcome)))
      (world source result.records)
      (initialEnvironment source result.records capacity) := by
  let result := Model.run source capacity records
  have loopEvaluation : Command.Evaluates (TM source) (SM source)
      (world source records) (loopEnvironment source records capacity 0 0)
      Structure.loop (completionOf result.outcome)
      (world source result.records)
      (loopEnvironment source result.records capacity result.offset
        result.tokenCount) := by
    exact loop_evaluates_run source capacity records sourceBound recordsLength
      capacityBound
  change Command.Evaluates (TM source) (SM source) (world source records)
      (initialEnvironment source records capacity) Structure.command
      (.returned (some (Model.resultValue result.outcome)))
      (world source result.records)
      (initialEnvironment source result.records capacity)
  have resultLength : result.records.length = records.length := by
    exact Model.run_records_length source capacity records
  have countMatches : result.tokenCount =
      (Model.emittedTokens result.outcome).length := by
    exact Model.run_tokenCount source capacity records
  have logicalOutcome : result.outcome = Model.lexInto source capacity := by
    exact Model.run_outcome source capacity records
  have notImpossible : ∀ tokens exhaustedAt,
      result.outcome ≠ .impossibleFuelExhaustion tokens exhaustedAt := by
    intro tokens exhaustedAt impossible
    rw [logicalOutcome] at impossible
    exact Model.lexInto_ne_impossibleFuelExhaustion source capacity tokens
      exhaustedAt impossible
  have inner : Command.Evaluates (TM source) (SM source)
      (world source records)
      (loopEnvironment source records capacity 0 0)
      (.sequence Structure.loop
        (.sequence (.returnValue (some Structure.completedTerm)) .skip))
      (.returned (some (Model.resultValue result.outcome)))
      (world source result.records)
      (loopEnvironment source result.records capacity result.offset
        result.tokenCount) := by
    cases outcomeEq : result.outcome with
    | completed tokens =>
        have tokenCountEq : result.tokenCount = tokens.length := by
          simpa [outcomeEq, Model.emittedTokens] using countMatches
        apply Command.Evaluates.sequenceNext
        · simpa [outcomeEq, completionOf] using loopEvaluation
        · apply Command.Evaluates.sequenceStop
          · apply Command.Evaluates.returnSome
            simpa [outcomeEq, Model.resultValue, tokenCountEq,
              Results.Semantics.value] using
              (completedTerm_evaluates source result.records capacity result.offset
                result.tokenCount)
          · simp
    | lexicalFailure tokens errorOffset =>
        apply Command.Evaluates.sequenceStop
        · simpa [outcomeEq, completionOf, Model.resultValue] using
            loopEvaluation
        · simp
    | outputFull tokens sourceOffset =>
        apply Command.Evaluates.sequenceStop
        · simpa [outcomeEq, completionOf, Model.resultValue] using
            loopEvaluation
        · simp
    | impossibleFuelExhaustion tokens exhaustedAt =>
        exact False.elim (notImpossible tokens exhaustedAt outcomeEq)
  have secondLet : Command.Evaluates (TM source) (SM source)
      (world source records)
      ((initialEnvironment source records capacity).push
        (.signed .i32 (Int.ofNat 0)))
      (.letValue Structure.i32Type (Structure.i32 0)
        (.sequence Structure.loop
          (.sequence (.returnValue (some Structure.completedTerm)) .skip)))
      (.returned (some (Model.resultValue result.outcome)))
      (world source result.records)
      (Env.pop (loopEnvironment source result.records capacity result.offset
        result.tokenCount)) := by
    have zero : Term.evaluate (TM source) (world source records)
        ((initialEnvironment source records capacity).push
          (.signed .i32 (Int.ofNat 0)))
        (Structure.i32 0) =
      .ok (.signed .i32 (Int.ofNat 0), world source records) := by rfl
    apply Command.Evaluates.letValue
    · exact zero
    · simpa only [loopEnvironment] using inner
  have total : Command.Evaluates (TM source) (SM source)
      (world source records) (initialEnvironment source records capacity)
      Structure.command
      (.returned (some (Model.resultValue result.outcome)))
      (world source result.records)
      (Env.pop (Env.pop (loopEnvironment source result.records capacity
        result.offset result.tokenCount))) := by
    rw [Structure.command]
    have zero : Term.evaluate (TM source) (world source records)
        (initialEnvironment source records capacity) (Structure.i32 0) =
      .ok (.signed .i32 (Int.ofNat 0), world source records) := by rfl
    exact Command.Evaluates.letValue zero secondLet
  have environmentEq :
      Env.pop (Env.pop (loopEnvironment source result.records capacity
        result.offset result.tokenCount)) =
      initialEnvironment source result.records capacity := by
    simp [loopEnvironment]
  simpa only [environmentEq] using total

theorem command_evaluates_request
    (request : Model.Request) (records : List Int)
    (recordsLength : records.length = 3 * request.capacity) :
    let result := Model.run request.source request.capacity records
    Command.Evaluates (TM request.source) (SM request.source)
      (world request.source records)
      (initialEnvironment request.source records request.capacity)
      Structure.command
      (.returned (some (Model.resultValue result.outcome)))
      (world request.source result.records)
      (initialEnvironment request.source result.records request.capacity) := by
  exact command_evaluates_run request.source request.capacity records
    request.sourceFitsI32 recordsLength request.recordsFitI32

end Lanius.Extraction.RawLexer.LexInto.Execution
