import Lanius.Extraction.Decimal.FinishEvaluationSupport

namespace Lanius.Extraction.Decimal.FinishAtEndReturn

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

private theorem returned_run
    (source : List Byte) (world : ReadOnly.World)
    (currentEnvironment : Env arity) (valueTerm : Term signature arity)
    (value : Value)
    (evaluated : Term.evaluate (termMachine source) world currentEnvironment
      valueTerm = .ok (value, world)) :
    Stateful.Acyclic.run? (termMachine source) (commandMachine source)
        world currentEnvironment (Commands.returned valueTerm) =
      some (.returned (some value), world, currentEnvironment) := by
  unfold Commands.returned
  simp [Stateful.Acyclic.run?, evaluated]
  rfl

/-- The checked return command at the end of a fractional literal produces
the logical floating-point scan result without changing the source world. -/
theorem finishAtEnd_return_run
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (next : Byte)
    (fractionBound : integerEnd + 1 ≤ 2147483647) :
    tailReturnRun source world integerEnd next =
      some (Stateful.Completion.returned
          (some (EvaluationModel.encoded
            (.success .float (integerEnd + 1)))),
        world,
        ((EvaluationModel.environment source integerEnd).push
          (.signed .i32 next.val)).push
          (.signed .i32 (integerEnd + 1))) := by
  have returned := floatScan_evaluates (source := source) (world := world)
    (((EvaluationModel.environment source integerEnd).push
        (.signed .i32 next.val)).push
      (.signed .i32 (integerEnd + 1)))
    (Commands.slot 4) (integerEnd + 1) fractionBound (by rfl)
  unfold tailReturnRun
  exact returned_run source world _ _ _ returned

end Lanius.Extraction.Decimal.FinishAtEndReturn
