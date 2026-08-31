import Lanius.Extraction.Decimal.FinishEvaluationSupport

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

theorem exponentFlag_evaluates
    (source : List Byte) (world : ReadOnly.World) (environment : Env arity)
    (term : Term signature arity) (byte : Nat)
    (termResult : Term.evaluate (termMachine source) world environment term =
      .ok (.signed .i32 byte, world)) :
    Term.evaluate (termMachine source) world environment
      ((Commands.comparison .equal term (Commands.i32 101)).logicalOr
        (Commands.comparison .equal term (Commands.i32 69))) =
      .ok (.boolean (decide (byte = 101) || decide (byte = 69)), world) := by
  have e := equal_evaluates (source := source) (world := world) environment
    term (Commands.i32 101) byte 101 termResult (by rfl)
  have upperE := equal_evaluates (source := source) (world := world) environment
    term (Commands.i32 69) byte 69 termResult (by rfl)
  exact logicalOr_evaluates (source := source) (world := world) environment
    _ _ _ _ e upperE

theorem exponent_true {byte : Nat}
    (result : (decide (byte = 101) || decide (byte = 69)) = true) :
    byte = 101 ∨ byte = 69 := by
  rcases Bool.or_eq_true_iff.mp result with e | upperE
  · exact .inl (of_decide_eq_true e)
  · exact .inr (of_decide_eq_true upperE)

theorem exponent_false {byte : Nat}
    (result : (decide (byte = 101) || decide (byte = 69)) = false) :
    byte ≠ 101 ∧ byte ≠ 69 := by
  have parts := Bool.or_eq_false_iff.mp result
  exact ⟨of_decide_eq_false parts.1, of_decide_eq_false parts.2⟩

end Lanius.Extraction.Decimal.FinishEvaluation

