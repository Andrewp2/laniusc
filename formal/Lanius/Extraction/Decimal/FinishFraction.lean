import Lanius.Extraction.Decimal.FinishFractionTail

namespace Lanius.Extraction.Decimal.FinishEvaluation

set_option maxRecDepth 4096

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

theorem finishFraction
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
    (fractionResult : Term.evaluate (termMachine source) world
      ((environment source integerEnd).push (.signed .i32 next.val))
      (Commands.add (Commands.slot 2) (Commands.i32 1)) =
        .ok (.signed .i32 (integerEnd + 1), world)) :
    tailRun source world integerEnd next =
      tailResult source world integerEnd next := by
  unfold tailRun tailResult
  simp only [Commands.finishDecimalTail, Stateful.Acyclic.run?]
  rw [fractionResult]
  simp only [bind, Except.bind]
  have body := finishFraction_body_run source world integerEnd next first
    sourceFound sourceBound inBounds fractionInBounds nextAt firstAt startI32
    fractionBound noExponent isDot notTwoDots nextResult
  unfold tailBodyRun at body
  rw [body]
  simp only [Env.pop_push]
  rfl

end Lanius.Extraction.Decimal.FinishEvaluation
