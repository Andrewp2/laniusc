import Lanius.Extraction.Decimal.FinishAtEndReturn

namespace Lanius.Extraction.Decimal.FinishAtEndBody

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

/-- The final fraction-bound test selects the checked floating-point return
when the decimal point is the last source byte. -/
theorem finishAtEnd_body_run
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (next : Byte)
    (fractionBound : integerEnd + 1 ≤ 2147483647)
    (fractionAtEnd : ¬ integerEnd + 1 < source.length) :
    tailBodyRun source world integerEnd next =
      some (Stateful.Completion.returned
          (some (EvaluationModel.encoded
            (.success .float (integerEnd + 1)))),
        world,
        ((EvaluationModel.environment source integerEnd).push
          (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1))) := by
  unfold tailBodyRun
  simp only [Commands.finishDecimalTailBody, Stateful.Acyclic.run?]
  have test := less_evaluates (source := source) (world := world)
    (((EvaluationModel.environment source integerEnd).push
        (.signed .i32 next.val)).push
      (.signed .i32 (integerEnd + 1)))
    (Commands.slot 4) (Commands.slot 1) (integerEnd + 1) source.length
    (by rfl) (by rfl)
  rw [test, decide_eq_false fractionAtEnd]
  have returned := FinishAtEndReturn.finishAtEnd_return_run
    source world integerEnd next fractionBound
  unfold tailReturnRun at returned
  exact returned

end Lanius.Extraction.Decimal.FinishAtEndBody
