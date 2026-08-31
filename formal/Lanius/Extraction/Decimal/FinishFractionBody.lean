import Lanius.Extraction.Decimal.FinishEvaluationFlags

namespace Lanius.Extraction.Decimal.FinishEvaluation

set_option maxRecDepth 200000

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.Extraction.Decimal
open Lanius.Extraction.Decimal.FinishEvaluationModel
open Lanius.Extraction.Decimal.FinishEvaluationTerms
open Lanius.Extraction.Decimal.EvaluationBounds
open Lanius.Extraction.Decimal.FinishEvaluationSupport

private abbrev sourceIntegers := EvaluationModel.sourceIntegers
private abbrev environment := EvaluationModel.environment
private abbrev encoded := EvaluationModel.encoded

theorem finishFraction_command_run
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (next first : Byte)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : integerEnd < source.length)
    (fractionInBounds : integerEnd + 1 < source.length)
    (nextAt : source[integerEnd] = next)
    (firstAt : source[integerEnd + 1] = first)
    (startI32 : integerEnd ≤ 2147483647)
    (fractionBound : integerEnd + 1 ≤ 2147483647)
    (noExponent : (decide (next.val = 101) || decide (next.val = 69)) = false)
    (isDot : next.val = 46) (notTwoDots : first.val ≠ 46)
    (nextResult : Term.evaluate (termMachine source) world
      (environment source integerEnd) (Commands.index (Commands.slot 0)
        (Commands.slot 2)) = .ok (.signed .i32 next.val, world))
    : fractionBodyRun source world integerEnd next =
      some (fractionBodyCompletion source integerEnd first,
        world,
        ((environment source integerEnd).push (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1))) := by
  unfold fractionBodyRun
  simp only [Commands.finishDecimalFractionBody, Stateful.Acyclic.run?]
  let fractionStart := integerEnd + 1
  let fractionEnvironment :=
    ((environment source integerEnd).push (.signed .i32 next.val)).push
      (.signed .i32 fractionStart)
  have firstResult := index_evaluates (source := source) (world := world)
    fractionEnvironment (Commands.slot 0) (Commands.slot 4)
    fractionStart (by simpa [fractionStart] using fractionInBounds)
    sourceFound (by rfl) (by rfl)
  let actualFirst := source.get ⟨fractionStart, by
    simpa [fractionStart] using fractionInBounds⟩
  have firstEq : actualFirst = first := by
    simpa [actualFirst, fractionStart] using firstAt
  dsimp [actualFirst, fractionStart] at firstEq
  have dotAt : byteValueAt source integerEnd = some 46 := by
    rw [byteValueAt_get source integerEnd inBounds]
    simp [nextAt, isDot]
  have firstValueAt : byteValueAt source (integerEnd + 1) = some first.val := by
    rw [byteValueAt_get source (integerEnd + 1) fractionInBounds]
    simp [firstAt]
  have notDoubleDot : byteValueAt source (integerEnd + 1) ≠ some 46 := by
    rw [firstValueAt]
    simp [notTwoDots]
  rw [show (source.get ⟨fractionStart, by
    simpa [fractionStart] using fractionInBounds⟩).val = first.val by
      exact congrArg Fin.val firstEq] at firstResult
  have digitTest := isDigit_evaluates (source := source) (world := world)
    fractionEnvironment
    (Commands.index (Commands.slot 0) (Commands.slot 4)) (Commands.i32 10)
    first 10 (by omega) firstResult (by rfl)
  dsimp [fractionStart, fractionEnvironment] at digitTest
  rw [digitTest]
  by_cases accepted : isDigitForBase first 10 = true
  · rw [accepted]
    have acceptedLogical : 48 ≤ first.val ∧ first.val ≤ 57 :=
      (isDigitForBase_decimal_iff first).mp accepted
    simp only [bind, Except.bind]
    have digitResult := digitRun_evaluates (source := source) (world := world)
      fractionEnvironment (Commands.slot 0) (Commands.slot 1)
      (Commands.slot 4) (Commands.i32 10) fractionStart 10 sourceFound
      sourceBound (by exact fractionBound) (by omega)
      (by rfl) (by rfl) (by rfl) (by rfl)
    dsimp [fractionStart, fractionEnvironment] at digitResult
    rw [digitResult]
    simp only [bind, Except.bind]
    cases resultEq : scanDigitRun source fractionStart 10 with
    | failure error =>
        have resultBound := digitRunResult_bound (source := source)
          (start := fractionStart) (base := 10) sourceBound fractionBound
        rw [resultEq] at resultBound digitResult
        let digitEnvironment := fractionEnvironment.push
          (digitScanValue (.failure error))
        have succeeded := digitSucceeded_evaluates (source := source)
          (world := world) digitEnvironment (Commands.slot 5)
          (.failure error) resultBound (by rfl)
        have failed := logicalNot_evaluates (source := source) digitEnvironment
          (Commands.digitSucceeded (Commands.slot 5)) false succeeded
        dsimp [fractionStart, fractionEnvironment, digitEnvironment] at failed
        rw [failed]
        simp only [Commands.returned, Stateful.Acyclic.run?, Bool.not_false,
          bind, Except.bind]
        have errorResult := digitError_evaluates (source := source)
          (world := world) digitEnvironment (Commands.slot 5) error
          resultBound (by rfl)
        have returned := numberFailure_evaluates (source := source)
          (world := world) digitEnvironment
          (Commands.digitError (Commands.slot 5)) error resultBound errorResult
        dsimp [fractionStart, fractionEnvironment, digitEnvironment] at returned
        dsimp [fractionStart, fractionEnvironment, digitEnvironment]
        rw [returned]
        simp only [Env.pop_push]
        have logicalNoExponent : (next.val == 101 || next.val == 69) = false := by
          simpa using noExponent
        simp only [fractionBodyCompletion, accepted, Bool.true_or, if_true]
        rw [finishDecimal_digitFailure source integerEnd first.val error dotAt
          notDoubleDot firstValueAt acceptedLogical (by
            simpa [fractionStart] using resultEq)]
        rfl
    | success finish =>
        have resultBound := digitRunResult_bound (source := source)
          (start := fractionStart) (base := 10) sourceBound fractionBound
        rw [resultEq] at resultBound digitResult
        let digitEnvironment := fractionEnvironment.push
          (digitScanValue (.success finish))
        have succeeded := digitSucceeded_evaluates (source := source)
          (world := world) digitEnvironment (Commands.slot 5)
          (.success finish) resultBound (by rfl)
        have notFailed := logicalNot_evaluates (source := source) digitEnvironment
          (Commands.digitSucceeded (Commands.slot 5)) true succeeded
        dsimp [fractionStart, fractionEnvironment, digitEnvironment] at notFailed
        rw [notFailed]
        simp only [Stateful.Acyclic.run?, Bool.not_true, bind, Except.bind]
        have endResult := digitEnd_evaluates (source := source) (world := world)
          digitEnvironment (Commands.slot 5) finish resultBound (by rfl)
        dsimp [fractionStart, fractionEnvironment, digitEnvironment] at endResult
        dsimp [fractionStart, fractionEnvironment, digitEnvironment]
        rw [endResult]
        simp only [bind, Except.bind]
        let endEnvironment := digitEnvironment.push (.signed .i32 finish)
        have endTest := less_evaluates (source := source) (world := world)
          endEnvironment (Commands.slot 6) (Commands.slot 1)
          finish source.length (by rfl) (by rfl)
        dsimp [fractionStart, fractionEnvironment, digitEnvironment,
          endEnvironment] at endTest
        rw [endTest]
        by_cases endInBounds : finish < source.length
        · rw [decide_eq_true endInBounds]
          simp only [bind, Except.bind]
          have exponentResult := index_evaluates (source := source)
            (world := world) endEnvironment (Commands.slot 0)
            (Commands.slot 6) finish endInBounds sourceFound (by rfl) (by rfl)
          dsimp [fractionStart, fractionEnvironment, digitEnvironment,
            endEnvironment] at exponentResult
          rw [exponentResult]
          simp only [bind, Except.bind]
          have exponentTest := exponentFlag_evaluates source world
            (endEnvironment.push
              (.signed .i32 (source.get ⟨finish, endInBounds⟩).val))
            (Commands.slot 7) (source.get ⟨finish, endInBounds⟩).val
            (by rfl)
          dsimp [fractionStart, fractionEnvironment, digitEnvironment,
            endEnvironment] at exponentTest
          rw [exponentTest]
          let hasExponent :=
            decide (source[finish].val = 101) ||
            decide (source[finish].val = 69)
          by_cases exponent : hasExponent = true
          · rw [show
                (decide (source[finish].val = 101) ||
                  decide (source[finish].val = 69)) = true
                by exact exponent]
            simp only [Commands.returned, Stateful.Acyclic.run?, bind,
              Except.bind]
            have returned := scanExponent_evaluates (source := source)
              (world := world)
              (endEnvironment.push
                (.signed .i32 (source.get ⟨finish, endInBounds⟩).val))
              (Commands.slot 0) (Commands.slot 1) (Commands.slot 6)
              finish sourceFound sourceBound endInBounds
              (by rfl) (by rfl) (by rfl)
            dsimp [fractionStart, fractionEnvironment, digitEnvironment,
              endEnvironment] at returned
            rw [returned]
            simp only [Env.pop_push]
            have exponentAt : byteValueAt source finish =
                some source[finish].val :=
              byteValueAt_get source finish endInBounds
            have exponentProp : isExponentByte source[finish].val := by
              apply (exponentFlag_eq_true_iff source[finish].val).mp
              simpa only [exponentFlag_eq_decideOr] using exponent
            simp only [fractionBodyCompletion, accepted, Bool.true_or, if_true]
            rw [finishDecimal_digitSuccessExponent source integerEnd first.val
              finish source[finish].val dotAt notDoubleDot firstValueAt
              acceptedLogical (by simpa [fractionStart] using resultEq)
              exponentAt exponentProp]
            rfl
          · have exponentFalse : hasExponent = false := Bool.eq_false_iff.mpr exponent
            rw [show
                (decide (source[finish].val = 101) ||
                  decide (source[finish].val = 69)) = false
                by exact exponentFalse]
            simp only [Commands.returned, Stateful.Acyclic.run?, Env.pop_push,
              bind, Except.bind]
            have returned := floatScan_evaluates (source := source)
              (world := world) endEnvironment (Commands.slot 6) finish
              resultBound (by rfl)
            dsimp [fractionStart, fractionEnvironment, digitEnvironment,
              endEnvironment] at returned
            rw [returned]
            simp only [Env.pop_push]
            have exponentAt : byteValueAt source finish =
                some source[finish].val :=
              byteValueAt_get source finish endInBounds
            have notExponent : ¬ isExponentByte source[finish].val := by
              apply (exponentFlag_eq_false_iff source[finish].val).mp
              simpa only [exponentFlag_eq_decideOr] using exponentFalse
            simp only [fractionBodyCompletion, accepted, Bool.true_or, if_true]
            rw [finishDecimal_digitSuccessNoExponent source integerEnd first.val
              finish source[finish].val dotAt notDoubleDot firstValueAt
              acceptedLogical (by simpa [fractionStart] using resultEq)
              exponentAt notExponent]
            rfl
        · rw [decide_eq_false endInBounds]
          simp only [Stateful.Acyclic.run?, bind, Except.bind]
          have returned := floatScan_evaluates (source := source)
            (world := world) endEnvironment (Commands.slot 6) finish
            resultBound (by rfl)
          dsimp [fractionStart, fractionEnvironment, digitEnvironment,
            endEnvironment] at returned
          simp only [Commands.returned, Stateful.Acyclic.run?, Env.pop_push,
            bind, Except.bind]
          rw [returned]
          simp only [Env.pop_push]
          have logicalNoExponent :
              (next.val == 101 || next.val == 69) = false := by
            simpa using noExponent
          simp only [fractionBodyCompletion, accepted, Bool.true_or, if_true]
          simp [finishDecimal, byteValueAt, inBounds, fractionInBounds,
            endInBounds, nextAt, firstAt, isDot, notTwoDots,
            logicalNoExponent, accepted, acceptedLogical, resultEq,
            fractionStart, firstEq]
          rfl
  · have rejected : isDigitForBase first 10 = false := by
      exact Bool.eq_false_iff.mpr accepted
    have rejectedLogical : ¬(48 ≤ first.val ∧ first.val ≤ 57) := by
      intro decimal
      exact accepted ((isDigitForBase_decimal_iff first).mpr decimal)
    rw [rejected]
    simp only [Stateful.Acyclic.run?, bind, Except.bind]
    have firstAgain := index_evaluates (source := source) (world := world)
      fractionEnvironment (Commands.slot 0) (Commands.slot 4)
      fractionStart (by simpa [fractionStart] using fractionInBounds)
      sourceFound (by rfl) (by rfl)
    rw [show (source.get ⟨fractionStart, by
      simpa [fractionStart] using fractionInBounds⟩).val = first.val by
        exact congrArg Fin.val firstEq] at firstAgain
    dsimp [fractionStart, fractionEnvironment] at firstAgain
    rw [firstAgain]
    simp only [bind, Except.bind]
    have exponentTest := exponentFlag_evaluates source world
      (fractionEnvironment.push (.signed .i32 first.val))
      (Commands.slot 5) first.val (by rfl)
    dsimp [fractionStart, fractionEnvironment] at exponentTest
    rw [exponentTest]
    let hasExponent := decide (first.val = 101) || decide (first.val = 69)
    by_cases exponent : hasExponent = true
    · rw [show (decide (first.val = 101) || decide (first.val = 69)) = true
          by exact exponent]
      simp only [Commands.returned, Stateful.Acyclic.run?, bind, Except.bind]
      have returned := scanExponent_evaluates (source := source) (world := world)
        (fractionEnvironment.push (.signed .i32 first.val))
        (Commands.slot 0) (Commands.slot 1) (Commands.slot 4)
        fractionStart sourceFound sourceBound
        (by simpa [fractionStart] using fractionInBounds)
        (by rfl) (by rfl) (by rfl)
      dsimp [fractionStart, fractionEnvironment] at returned
      dsimp [fractionStart, fractionEnvironment]
      rw [returned]
      simp only [Env.pop_push]
      have logicalNoExponent : (next.val == 101 || next.val == 69) = false := by
        simpa using noExponent
      have logicalExponent : (first.val == 101 || first.val == 69) = true := by
        simpa [hasExponent] using exponent
      simp only [fractionBodyCompletion, rejected, Bool.false_or,
        exponentFlag_eq_decideOr, exponent, if_true]
      simp [finishDecimal, byteValueAt, inBounds, fractionInBounds,
        nextAt, firstAt, isDot, notTwoDots, logicalNoExponent,
        logicalExponent, rejected, rejectedLogical, fractionStart, firstEq]
      have exponentProp : isExponentByte first.val := by
        apply (exponentFlag_eq_true_iff first.val).mp
        simpa only [exponentFlag_eq_decideOr] using exponent
      rw [if_pos (show first.val = 101 ∨ first.val = 69 from exponentProp)]
      rfl

    · have exponentFalse : hasExponent = false := Bool.eq_false_iff.mpr exponent
      rw [show (decide (first.val = 101) || decide (first.val = 69)) = false
          by exact exponentFalse]
      simp only [fractionBodyCompletion, rejected, Bool.false_or,
        exponentFlag_eq_decideOr, exponentFalse, Bool.false_eq_true, if_false]
      rw [if_neg (by simpa [hasExponent] using exponent)]
      simp only [Env.pop_push]
      rfl


end Lanius.Extraction.Decimal.FinishEvaluation
