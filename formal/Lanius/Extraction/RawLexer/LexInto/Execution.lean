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
  apply Env.eq_ofFn
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
  apply Env.eq_ofFn
  simp [loopEnvironment, initialEnvironment, Env.set, Env.push,
    Structure.offset, Structure.tokenCount, sameLength]

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
  rw [Effectful.Term.evaluate_eq_readOnly_of_callFree _ (by rfl)]
  functional_eval

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
  rw [Effectful.Term.evaluate_eq_readOnly_of_callFree _ (by rfl)]
  functional_eval

theorem rowTerm_evaluates
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken)
    (bounded : 3 * tokenCount ≤ 2147483647) :
    Term.evaluate (TM source) (world source records)
        (scannedEnvironment source records capacity offset tokenCount
          (.token token)) Structure.rowTerm =
      .ok (.signed .i32 (Int.ofNat (3 * tokenCount)),
        world source records) := by
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendCore (world source records)
    (.binary .multiply Structure.i32Type Structure.i32Type Structure.i32Type)
    [.signed .i32 (Int.ofNat tokenCount), .signed .i32 3] = _
  simp [ReadOnly.evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]
  simpa [Int.natCast_mul, Nat.mul_comm, Int.mul_comm] using
    (wrapSigned_i32_ofNat verifiedFrontendCore.target (3 * tokenCount) bounded)

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
  rw [Effectful.Term.evaluate_eq_readOnly_of_callFree _ (by rfl)]
  functional_eval

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

private theorem loopBody_afterScan
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (scan : OneTokenResult)
    (sourceBound : source.length ≤ 2147483646)
    (offsetBound : offset ≤ 2147483647)
    (scanned : Lexer.scanOne source offset = scan)
    {completion : Lanius.FunctionalView.Stateful.Completion}
    {afterWorld : ReadOnly.World} {afterEnvironment : Env 7}
    (body : Command.Evaluates (TM source) (SM source)
      (world source records)
      (scannedEnvironment source records capacity offset tokenCount scan)
      Structure.loopBodyAfterScan completion afterWorld afterEnvironment) :
    Command.Evaluates (TM source) (SM source)
      (world source records)
      (loopEnvironment source records capacity offset tokenCount)
      Structure.loopBody completion afterWorld (Env.pop afterEnvironment) := by
  rw [Structure.loopBody]
  exact .letValue
    (by simpa [scanned] using
      (scanOneTerm_evaluates source records capacity offset tokenCount
        sourceBound offsetBound)) body

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
  have total := loopBody_afterScan source records capacity offset tokenCount
    (.failure error) sourceBound offsetBound scanned body
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
  have total := loopBody_afterScan source records capacity offset tokenCount
    (.token token) sourceBound offsetBound scanned body
  simpa only [scannedEnvironment, Env.pop_push] using total

theorem loopBody_token
    (source : List Lexer.Byte) (records : List Int)
    (capacity offset tokenCount : Nat) (token : RawToken)
    (sourceBound : source.length ≤ 2147483646)
    (offsetBound : offset ≤ 2147483647)
    (scanned : Lexer.scanOne source offset = .token token)
    (startEq : token.start = offset)
    (room : tokenCount < capacity)
    (recordsCapacity : 3 * capacity ≤ records.length)
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
  have total := loopBody_afterScan source records capacity offset tokenCount
    (.token token) sourceBound offsetBound scanned afterScan
  have environmentEq :
      Env.pop (Env.pop (Env.set offsetEnv (Structure.tokenCount 8)
        (.signed .i32 (Int.ofNat (tokenCount + 1))))) =
      loopEnvironment source records3 capacity token.finish
        (tokenCount + 1) := by
    refine Eq.trans ?_ (loopEnvironment_updated source records records3
      capacity offset tokenCount token.finish (tokenCount + 1) ?_)
    · unfold offsetEnv rowEnv rowEnvironment scannedEnvironment
      exact Env.eq_ofFn rfl
    · simpa [records3] using
        (afterToken_length records tokenCount token).symm
  rw [environmentEq] at total
  simpa only [records3] using total

theorem loop_evaluates_runFromFuel
    (source : List Lexer.Byte) (capacity fuel offset tokenCount : Nat)
    (accepted : List RawToken) (records : List Int)
    (sourceBound : source.length ≤ 2147483646)
    (enoughFuel : source.length - offset < fuel)
    (acceptedCount : accepted.length = tokenCount)
    (countFits : tokenCount ≤ capacity)
    (recordsCapacity : 3 * capacity ≤ records.length)
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
            simp only
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
              have nextRecordsCapacity : 3 * capacity ≤ (afterToken records tokenCount token).length := by
                simpa only [afterToken_length] using recordsCapacity
              have rest := induction token.finish (tokenCount + 1)
                (accepted ++ [token])
                (afterToken records tokenCount token) tailFuel nextAcceptedCount
                nextCountFits nextRecordsCapacity
              rw [Structure.loop]
              exact .whileNext
                (by simpa [beforeEnd] using
                  (loopCondition_evaluates source records capacity offset
                    tokenCount))
                (loopBody_token source records capacity offset tokenCount token
                  sourceBound offsetBound scanned
                  (Model.scanOne_token_start scanned)
                  room recordsCapacity
                  capacityBound)
                (by simpa [afterToken_eq_writeToken, Structure.loop] using rest)

theorem loop_evaluates_run
    (source : List Lexer.Byte) (capacity : Nat) (records : List Int)
    (sourceBound : source.length ≤ 2147483646)
    (recordsCapacity : 3 * capacity ≤ records.length)
    (capacityBound : 3 * capacity ≤ 2147483647) :
    let result := Model.run source capacity records
    Command.Evaluates (TM source) (SM source) (world source records)
      (loopEnvironment source records capacity 0 0)
      Structure.loop (completionOf result.outcome)
      (world source result.records)
      (loopEnvironment source result.records capacity result.offset
        result.tokenCount) := by
  exact loop_evaluates_runFromFuel source capacity (source.length + 1) 0 0
    [] records sourceBound (by simp) (by simp) (by simp) recordsCapacity
    capacityBound

theorem command_evaluates_run
    (source : List Lexer.Byte) (capacity : Nat) (records : List Int)
    (sourceBound : source.length ≤ 2147483646)
    (recordsCapacity : 3 * capacity ≤ records.length)
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
    exact loop_evaluates_run source capacity records sourceBound recordsCapacity
      capacityBound
  change Command.Evaluates (TM source) (SM source) (world source records)
      (initialEnvironment source records capacity) Structure.command
      (.returned (some (Model.resultValue result.outcome)))
      (world source result.records)
      (initialEnvironment source result.records capacity)
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
  simpa only [Structure.command, loopEnvironment, Env.pop_push] using
    (Command.Evaluates.letValue (type := Structure.i32Type)
      (initializer := Structure.i32 0) (by rfl)
      (Command.Evaluates.letValue (type := Structure.i32Type)
        (initializer := Structure.i32 0) (by rfl) inner))

theorem command_evaluates_request
    (request : Model.Request) (records : List Int)
    (recordsCapacity : 3 * request.capacity ≤ records.length) :
    let result := Model.run request.source request.capacity records
    Command.Evaluates (TM request.source) (SM request.source)
      (world request.source records)
      (initialEnvironment request.source records request.capacity)
      Structure.command
      (.returned (some (Model.resultValue result.outcome)))
      (world request.source result.records)
      (initialEnvironment request.source result.records request.capacity) := by
  exact command_evaluates_run request.source request.capacity records
    request.sourceFitsI32 recordsCapacity request.recordsFitI32

end Lanius.Extraction.RawLexer.LexInto.Execution
