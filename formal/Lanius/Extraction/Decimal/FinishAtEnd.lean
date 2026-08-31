import Lanius.Extraction.Decimal.FinishAtEndBody

namespace Lanius.Extraction.Decimal.FinishAtEnd

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
open Lanius.Extraction.Decimal.FinishEvaluationSupport

private theorem finishAtEnd_run
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (next : Byte)
    (fractionBound : integerEnd + 1 ≤ 2147483647)
    (fractionAtEnd : ¬ integerEnd + 1 < source.length)
    (fractionResult : Term.evaluate (termMachine source) world
      ((EvaluationModel.environment source integerEnd).push
        (.signed .i32 next.val))
      (Commands.add (Commands.slot 2) (Commands.i32 1)) =
        .ok (.signed .i32 (integerEnd + 1), world)) :
    tailRun source world integerEnd next =
      some (Stateful.Completion.returned
          (some (EvaluationModel.encoded
            (.success .float (integerEnd + 1)))),
        world,
        (EvaluationModel.environment source integerEnd).push
          (.signed .i32 next.val)) := by
  unfold tailRun
  simp only [Commands.finishDecimalTail, Stateful.Acyclic.run?]
  rw [fractionResult]
  simp only
  have body := FinishAtEndBody.finishAtEnd_body_run
    source world integerEnd next fractionBound fractionAtEnd
  unfold tailBodyRun at body
  rw [body]
  simp only [Env.pop_push]
  rfl

/-- The exact checked decimal tail agrees with `finishDecimal` when the byte
after the decimal point is out of bounds. -/
theorem finishAtEnd
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (next : Byte)
    (inBounds : integerEnd < source.length)
    (nextAt : source[integerEnd] = next)
    (fractionBound : integerEnd + 1 ≤ 2147483647)
    (isDot : next.val = 46)
    (fractionAtEnd : ¬ integerEnd + 1 < source.length)
    (fractionResult : Term.evaluate (termMachine source) world
      ((EvaluationModel.environment source integerEnd).push
        (.signed .i32 next.val))
      (Commands.add (Commands.slot 2) (Commands.i32 1)) =
        .ok (.signed .i32 (integerEnd + 1), world)) :
    tailRun source world integerEnd next =
      tailResult source world integerEnd next := by
  rw [finishAtEnd_run source world integerEnd next fractionBound fractionAtEnd
    fractionResult]
  unfold tailResult
  rw [finishDecimal_fractionAtEnd source integerEnd next inBounds nextAt
    isDot fractionAtEnd]

end Lanius.Extraction.Decimal.FinishAtEnd
