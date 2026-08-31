import Lanius.Extraction.CanonicalTokens.Model
import Lanius.Extraction.CanonicalTokens.TriviaCommand

namespace Lanius.Extraction.CanonicalTokens.IsTriviaSemantics

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful

def isTriviaCode (kind : Int) : Bool :=
  kind = 3 || kind = 10 || kind = 11

private def TM :=
  termMachine (evaluateOperation verifiedFrontendCore Model.noCalls)

private def SM :=
  machineWith verifiedFrontendCore
    (evaluateOperation verifiedFrontendCore Model.noCalls)

private def run (kind : Int) :=
  Lanius.FunctionalView.Stateful.Acyclic.run? TM SM Model.emptyWorld
    (Model.isTriviaEnvironment kind) TriviaCommand.command

private theorem whitespaceConstant : verifiedFrontendCore.constant? 9 = some {
    id := 9, type := TriviaCommand.i32, value := .signed .i32 3 } := by rfl

private theorem lineCommentConstant : verifiedFrontendCore.constant? 16 = some {
    id := 16, type := TriviaCommand.i32, value := .signed .i32 10 } := by rfl

private theorem blockCommentConstant : verifiedFrontendCore.constant? 17 = some {
    id := 17, type := TriviaCommand.i32, value := .signed .i32 11 } := by rfl

private theorem evaluateEqual (world : World) (left right : Int) :
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
        verifiedFrontendCore world
        (.binary .equal TriviaCommand.i32 TriviaCommand.i32
          TriviaCommand.bool)
        [.signed .i32 left, .signed .i32 right] =
      .ok (.boolean (decide (left = right)), world) := by
  by_cases same : left = right
  · subst right
    simp [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
      Lanius.Semantics.evalBinaryValue, Lanius.Semantics.scalarEqual,
      bind, Except.bind]
  · simp [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
      Lanius.Semantics.evalBinaryValue, Lanius.Semantics.scalarEqual,
      same, bind, Except.bind]

private theorem evaluateDirectEqual (world : World) (kind value : Int)
    (id : ConstantId)
    (found : verifiedFrontendCore.constant? id = some {
      id := id, type := TriviaCommand.i32, value := .signed .i32 value }) :
    Term.evaluate TM world (Model.isTriviaEnvironment kind)
        (TriviaCommand.directEqual (TriviaCommand.directConstant id)) =
      .ok (.boolean (decide (kind = value)), world) := by
  simp only [TM, termMachine, TriviaCommand.directEqual,
    TriviaCommand.directConstant, TriviaCommand.directSlot,
    Lanius.FunctionalView.Term.evaluate, Lanius.FunctionalView.evaluateTerms,
    Lanius.FunctionalView.Ref.evaluate, bind, Except.bind]
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl),
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_constant found]
  simp only [Model.isTriviaEnvironment]
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl)]
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
      verifiedFrontendCore world
      (.binary .equal TriviaCommand.i32 TriviaCommand.i32 TriviaCommand.bool)
      [.signed .i32 kind, .signed .i32 value] = _
  exact evaluateEqual world kind value

private theorem evaluatePredicate (world : World) (kind : Int) :
    Term.evaluate TM world (Model.isTriviaEnvironment kind)
        TriviaCommand.directPredicate =
      .ok (.boolean (isTriviaCode kind), world) := by
  simp only [TriviaCommand.directPredicate,
    Lanius.FunctionalView.Term.evaluate]
  rw [evaluateDirectEqual world kind 3 9 whitespaceConstant]
  by_cases whitespace : kind = 3
  · simp [isTriviaCode, whitespace, bind, Except.bind]
  · simp only [whitespace, decide_false, bind, Except.bind]
    rw [evaluateDirectEqual world kind 10 16 lineCommentConstant]
    by_cases lineComment : kind = 10
    · simp [isTriviaCode, lineComment]
    · simp only [lineComment, decide_false]
      rw [evaluateDirectEqual world kind 11 17 blockCommentConstant]
      simp [isTriviaCode, whitespace, lineComment]

/-- The mechanically recovered `is_trivia` function computes its source-level
predicate for every i32 argument, including non-token-kind values. -/
theorem isTriviaView_result (kind : Int) :
    Model.returnedBool? (run kind) = some (isTriviaCode kind) := by
  simp only [run, TriviaCommand.command, TriviaCommand.directCommand,
    Lanius.FunctionalView.Stateful.Acyclic.run?, Model.returnedBool?]
  rw [evaluatePredicate]

/-- Exact execution of the mechanically recovered `is_trivia` command in an
arbitrary read-only world. -/
theorem command_evaluates (world : World) (kind : Int) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world
        (Model.isTriviaEnvironment kind) TriviaCommand.command =
      some (.returned (some (.boolean (isTriviaCode kind))), world,
        Model.isTriviaEnvironment kind) := by
  simp only [TriviaCommand.command, TriviaCommand.directCommand,
    Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [evaluatePredicate]
  simp
  rfl

theorem recovered_command_evaluates (world : World) (kind : Int) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world
        (Model.isTriviaEnvironment kind) Functions.isTriviaView.command =
      some (.returned (some (.boolean (isTriviaCode kind))), world,
        Model.isTriviaEnvironment kind) := by
  rw [TriviaCommand.recovered]
  exact command_evaluates world kind

theorem recovered_view_result (kind : Int) :
    let recoveredRun :=
      Lanius.FunctionalView.Stateful.Acyclic.run?
        (termMachine (evaluateOperation verifiedFrontendCore Model.noCalls))
        (machineWith verifiedFrontendCore
          (evaluateOperation verifiedFrontendCore Model.noCalls))
        Model.emptyWorld (Model.isTriviaEnvironment kind)
        Functions.isTriviaView.command
    Model.returnedBool? recoveredRun = some (isTriviaCode kind) := by
  rw [TriviaCommand.recovered]
  exact isTriviaView_result kind

end Lanius.Extraction.CanonicalTokens.IsTriviaSemantics
