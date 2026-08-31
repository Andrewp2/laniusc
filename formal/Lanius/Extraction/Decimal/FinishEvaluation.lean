import Lanius.Extraction.Decimal.FinishAtEnd
import Lanius.Extraction.Decimal.FinishFraction

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
open Lanius.Extraction.Decimal.FinishAtEnd

private abbrev sourceIntegers := EvaluationModel.sourceIntegers
private abbrev environment := EvaluationModel.environment
private abbrev encoded := EvaluationModel.encoded

theorem finishDecimal_run
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : integerEnd ≤ source.length) :
    Stateful.Acyclic.run? (termMachine source) (commandMachine source)
      world (environment source integerEnd) Commands.finishDecimalReadable =
      some (Stateful.Completion.returned
        (some (encoded (finishDecimal source integerEnd))),
        world, environment source integerEnd) := by
  have startI32 : integerEnd ≤ 2147483647 := by omega
  have initialCondition := greaterEqual_evaluates (source := source)
    (world := world) (environment source integerEnd)
    (Commands.slot 2) (Commands.slot 1) integerEnd source.length
    (by rfl) (by rfl)
  simp only [Commands.finishDecimalReadable, Stateful.Acyclic.run?]
  rw [initialCondition]
  by_cases inBounds : integerEnd < source.length
  · have notAtEnd : ¬ source.length ≤ integerEnd := by omega
    rw [decide_eq_false notAtEnd]
    simp only [bind, Except.bind]
    let next := source.get ⟨integerEnd, inBounds⟩
    have nextAt : source[integerEnd] = next := by rfl
    have nextResult := index_evaluates (source := source) (world := world)
      (environment source integerEnd) (Commands.slot 0) (Commands.slot 2)
      integerEnd inBounds sourceFound (by rfl) (by rfl)
    rw [nextResult]
    simp only [bind, Except.bind]
    have nextExponent := exponentFlag_evaluates source world
      ((environment source integerEnd).push (.signed .i32 next.val))
      (Commands.slot 3) next.val (by rfl)
    rw [nextExponent]
    let beginsExponent := decide (next.val = 101) || decide (next.val = 69)
    by_cases exponent : beginsExponent = true
    · rw [show (decide (next.val = 101) || decide (next.val = 69)) = true
          by exact exponent]
      simp only [Commands.returned, Stateful.Acyclic.run?, bind, Except.bind]
      have called := scanExponent_evaluates (source := source) (world := world)
        ((environment source integerEnd).push (.signed .i32 next.val))
        (Commands.slot 0) (Commands.slot 1) (Commands.slot 2) integerEnd
        sourceFound sourceBound inBounds (by rfl) (by rfl) (by rfl)
      rw [called]
      simp only [Env.pop_push]
      have exponentLogical : next.val = 101 ∨ next.val = 69 :=
        exponent_true (by simpa [beginsExponent] using exponent)
      simp [finishDecimal, byteValueAt,
        List.getElem?_eq_getElem inBounds, nextAt, exponentLogical]
      rfl
    · have exponentFalse : beginsExponent = false := Bool.eq_false_iff.mpr exponent
      rw [show (decide (next.val = 101) || decide (next.val = 69)) = false
          by exact exponentFalse]
      simp only [Stateful.Acyclic.run?, bind, Except.bind]
      have dotResult := notEqual_evaluates (source := source) (world := world)
        ((environment source integerEnd).push (.signed .i32 next.val))
        (Commands.slot 3) (Commands.i32 46) next.val 46 (by rfl) (by rfl)
      rw [dotResult]
      by_cases isDot : next.val = 46
      · rw [decide_eq_false (by simpa using isDot)]
        simp only [Stateful.Acyclic.run?, bind, Except.bind]
        let fractionStart := integerEnd + 1
        have fractionBound : fractionStart ≤ 2147483647 := by omega
        have fractionResult := add_evaluates (source := source) (world := world)
          ((environment source integerEnd).push (.signed .i32 next.val))
          (Commands.slot 2) (Commands.i32 1) integerEnd 1 fractionBound
          (by rfl) (by rfl)
        have fractionTest := less_evaluates (source := source) (world := world)
          ((environment source integerEnd).push (.signed .i32 next.val))
          (Commands.add (Commands.slot 2) (Commands.i32 1))
          (Commands.slot 1) fractionStart source.length fractionResult (by rfl)
        rw [fractionTest]
        by_cases fractionInBounds : fractionStart < source.length
        · rw [decide_eq_true fractionInBounds]
          simp only [bind, Except.bind]
          let first := source.get ⟨fractionStart, fractionInBounds⟩
          have firstAt : source[fractionStart] = first := by rfl
          have firstResult := index_evaluates (source := source) (world := world)
            ((environment source integerEnd).push (.signed .i32 next.val))
            (Commands.slot 0) (Commands.add (Commands.slot 2) (Commands.i32 1))
            fractionStart fractionInBounds sourceFound (by rfl) fractionResult
          have secondDot := equal_evaluates (source := source) (world := world)
            ((environment source integerEnd).push (.signed .i32 next.val))
            (Commands.index (Commands.slot 0)
              (Commands.add (Commands.slot 2) (Commands.i32 1)))
            (Commands.i32 46) first.val 46 firstResult (by rfl)
          rw [secondDot]
          by_cases twoDots : first.val = 46
          · rw [decide_eq_true twoDots]
            simp only [Commands.returned, Stateful.Acyclic.run?, bind,
              Except.bind]
            have returned := integerScan_evaluates (source := source)
              (world := world)
              ((environment source integerEnd).push (.signed .i32 next.val))
              (Commands.slot 2) integerEnd startI32 (by rfl)
            rw [returned]
            simp only [Env.pop_push]
            have noExponent := exponent_false
              (by simpa [beginsExponent] using exponentFalse)
            have secondFound : source[integerEnd + 1]? = some first := by
              rw [List.getElem?_eq_getElem (by
                simpa [fractionStart] using fractionInBounds)]
              exact congrArg some (by simpa [fractionStart] using firstAt)
            have dotted : ∃ byte,
                source[integerEnd + 1]? = some byte ∧ byte.val = 46 :=
              ⟨first, secondFound, twoDots⟩
            simp [finishDecimal, byteValueAt,
              List.getElem?_eq_getElem inBounds,
              List.getElem?_eq_getElem fractionInBounds,
              nextAt, firstAt, isDot, twoDots, noExponent, dotted]
            rfl
          · rw [decide_eq_false twoDots]
            simp only [Stateful.Acyclic.run?, bind, Except.bind]
            have tail := finishFraction source world integerEnd next first sourceFound
              sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
              exponentFalse isDot twoDots nextResult fractionResult
            unfold tailRun tailResult at tail
            rw [tail]
            simp only [Env.pop_push]
            rfl
        · rw [decide_eq_false fractionInBounds]
          simp only [Stateful.Acyclic.run?, bind, Except.bind]
          have tail := finishAtEnd source world integerEnd next inBounds nextAt
            fractionBound isDot fractionInBounds fractionResult
          unfold tailRun tailResult at tail
          rw [tail]
          simp only [Env.pop_push]
          rfl
      · rw [decide_eq_true isDot]
        simp only [Commands.returned, Stateful.Acyclic.run?, bind, Except.bind]
        have returned := integerScan_evaluates (source := source) (world := world)
          ((environment source integerEnd).push (.signed .i32 next.val))
          (Commands.slot 2) integerEnd startI32 (by rfl)
        rw [returned]
        simp only [Env.pop_push]
        have noExponent := exponent_false
          (by simpa [beginsExponent] using exponentFalse)
        simp [finishDecimal, byteValueAt,
          List.getElem?_eq_getElem inBounds, nextAt, isDot, noExponent]
        rfl
  · have atEnd : integerEnd = source.length := by omega
    subst integerEnd
    rw [decide_eq_true (by omega)]
    simp only [Commands.returned, Stateful.Acyclic.run?, bind, Except.bind]
    have returned := integerScan_evaluates (source := source) (world := world)
      (environment source source.length) (Commands.slot 2) source.length
      sourceBound
      (by rfl)
    rw [returned]
    simp [finishDecimal, byteValueAt]
    rfl

theorem finishDecimal_evaluates
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : integerEnd ≤ source.length) :
    Command.Evaluates (termMachine source) (commandMachine source)
      world (environment source integerEnd) Commands.finishDecimalReadable
      (.returned (some (encoded (finishDecimal source integerEnd)))) world
      (environment source integerEnd) :=
  Stateful.Acyclic.run?_sound
    (finishDecimal_run source world integerEnd sourceFound sourceBound startBound)

end Lanius.Extraction.Decimal.FinishEvaluation
