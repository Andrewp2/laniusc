import Lanius.Extraction.Decimal.FinishFractionBody
import Lanius.Extraction.Decimal.FinishAtEndReturn

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
open Lanius.Extraction.Decimal.FinishEvaluationSupport

private abbrev sourceIntegers := EvaluationModel.sourceIntegers
private abbrev environment := EvaluationModel.environment
private abbrev encoded := EvaluationModel.encoded

private theorem tailBody_after_fraction
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (next : Byte) (completion : Stateful.Completion)
    (fractionInBounds : integerEnd + 1 < source.length)
    (body : fractionBodyRun source world integerEnd next =
      some (completion, world,
        ((environment source integerEnd).push (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1)))) :
    tailBodyRun source world integerEnd next =
      tailBodyResult source world integerEnd next completion := by
  unfold tailBodyRun
  simp only [Commands.finishDecimalTailBody, Stateful.Acyclic.run?]
  have fractionTest := less_evaluates (source := source) (world := world)
    (((environment source integerEnd).push (.signed .i32 next.val)).push
      (.signed .i32 (integerEnd + 1)))
    (Commands.slot 4) (Commands.slot 1) (integerEnd + 1) source.length
    (by rfl) (by rfl)
  rw [fractionTest, decide_eq_true fractionInBounds]
  simp only
  unfold fractionBodyRun at body
  rw [body]
  cases completion <;> rfl

section

variable
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

include sourceFound sourceBound inBounds fractionInBounds nextAt firstAt
  startI32 fractionBound noExponent isDot notTwoDots nextResult

private theorem finishFraction_staged :
    tailBodyRun source world integerEnd next =
      tailBodyResult source world integerEnd next
        (fractionBodyCompletion source integerEnd first) := by
  have body := finishFraction_command_run source world integerEnd next first
    sourceFound sourceBound inBounds fractionInBounds nextAt firstAt startI32
    fractionBound noExponent isDot notTwoDots nextResult
  exact tailBody_after_fraction source world integerEnd next
    (fractionBodyCompletion source integerEnd first) fractionInBounds body

private theorem finishFraction_digit
    (accepted : isDigitForBase first 10 = true) :
    tailBodyRun source world integerEnd next =
      some (Stateful.Completion.returned
          (some (encoded (finishDecimal source integerEnd))),
        world,
        ((environment source integerEnd).push (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1))) := by
  rw [finishFraction_staged source world integerEnd next first sourceFound
    sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
    noExponent isDot notTwoDots nextResult]
  simp [tailBodyResult, fractionBodyCompletion, accepted]

private theorem finishFraction_exponent
    (rejected : isDigitForBase first 10 = false)
    (exponent : isExponentByte first.val) :
    tailBodyRun source world integerEnd next =
      some (Stateful.Completion.returned
          (some (encoded (finishDecimal source integerEnd))),
        world,
        ((environment source integerEnd).push (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1))) := by
  rw [finishFraction_staged source world integerEnd next first sourceFound
    sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
    noExponent isDot notTwoDots nextResult]
  simp [tailBodyResult, fractionBodyCompletion, rejected, exponent, exponentFlag]

private theorem finishFraction_boundary_stage
    (accepted : ¬ isDigitForBase first 10 = true)
    (rejected : isDigitForBase first 10 = false)
    (exponent : ¬ isExponentByte first.val) :
    tailBodyRun source world integerEnd next =
      tailReturnRun source world integerEnd next := by
  rw [finishFraction_staged source world integerEnd next first sourceFound
    sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
    noExponent isDot notTwoDots nextResult]
  simp only [tailBodyResult, fractionBodyCompletion, rejected, exponent,
    exponentFlag, decide_false, Bool.or_false, Bool.false_eq_true, if_false]

private theorem finishFraction_boundary_run
    (accepted : ¬ isDigitForBase first 10 = true)
    (rejected : isDigitForBase first 10 = false)
    (exponent : ¬ isExponentByte first.val) :
    tailBodyRun source world integerEnd next =
      some (Stateful.Completion.returned
          (some (encoded (.success .float (integerEnd + 1)))),
        world,
        ((environment source integerEnd).push (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1))) := by
  rw [finishFraction_boundary_stage source world integerEnd next first sourceFound
    sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
    noExponent isDot notTwoDots nextResult accepted rejected exponent]
  exact FinishAtEndReturn.finishAtEnd_return_run source world integerEnd next
    fractionBound

private theorem finishFraction_boundary
    (accepted : ¬ isDigitForBase first 10 = true)
    (rejected : isDigitForBase first 10 = false)
    (exponent : ¬ isExponentByte first.val) :
    tailBodyRun source world integerEnd next =
      some (Stateful.Completion.returned
          (some (encoded (finishDecimal source integerEnd))),
        world,
        ((environment source integerEnd).push (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1))) := by
  rw [finishFraction_boundary_run source world integerEnd next first sourceFound
    sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
    noExponent isDot notTwoDots nextResult accepted rejected exponent]
  have dotAt : byteValueAt source integerEnd = some 46 := by
    rw [byteValueAt_get source integerEnd inBounds]
    simp [nextAt, isDot]
  have firstValueAt : byteValueAt source (integerEnd + 1) = some first.val := by
    rw [byteValueAt_get source (integerEnd + 1) fractionInBounds]
    simp [firstAt]
  have notDoubleDot : byteValueAt source (integerEnd + 1) ≠ some 46 := by
    rw [firstValueAt]
    simp [notTwoDots]
  have rejectedLogical : ¬(48 ≤ first.val ∧ first.val ≤ 57) := by
    intro decimal
    exact accepted ((isDigitForBase_decimal_iff first).mpr decimal)
  rw [finishDecimal_nonDigitNoExponent source integerEnd first.val dotAt
    notDoubleDot firstValueAt rejectedLogical exponent]

theorem finishFraction_body_run :
    tailBodyRun source world integerEnd next =
      some (Stateful.Completion.returned
          (some (encoded (finishDecimal source integerEnd))),
        world,
        ((environment source integerEnd).push (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1))) := by
  by_cases accepted : isDigitForBase first 10 = true
  · exact finishFraction_digit source world integerEnd next first sourceFound
      sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
      noExponent isDot notTwoDots nextResult accepted
  · have rejected : isDigitForBase first 10 = false :=
      Bool.eq_false_iff.mpr accepted
    by_cases exponent : isExponentByte first.val
    · exact finishFraction_exponent source world integerEnd next first sourceFound
        sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
        noExponent isDot notTwoDots nextResult rejected exponent
    · exact finishFraction_boundary source world integerEnd next first sourceFound
        sourceBound inBounds fractionInBounds nextAt firstAt startI32 fractionBound
        noExponent isDot notTwoDots nextResult accepted rejected exponent

end

end Lanius.Extraction.Decimal.FinishEvaluation
