import Lanius.Extraction.Parser.Recognize.Position.Core

namespace Lanius.Extraction.ParserRecognize

set_option maxRecDepth 100000

open Lanius.Core
open Lanius.SymbolicCore
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Extraction.ParserScan
open Lanius.Extraction.ParserAppend
open Lanius.Extraction.ParserAccessors
open Lanius.Extraction.ParserFind
open Lanius.Extraction.ParserResult
open Lanius.Compiler.Parser
open Lanius.Typing
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification
/-! ## Artifact-derived FunctionalView for final root selection -/

private def rootLoopLayout : Layout 7 := fun index =>
  [0, 4, 8, 12, 18, 22, 41].get index

private def rootLoopContext : Context :=
  let c0 := Context.empty.bind 0 (.slice parserI32Type)
  let c1 := c0.bind 4 (.slice parserI32Type)
  let c2 := c1.bind 8 parserI32Type
  let c3 := c2.bind 12 parserI32Type
  let c4 := c3.bind 18 parserI32Type
  let c5 := c4.bind 22 parserI32Type
  c5.bind 41 parserI32Type

private def rootLoopReification? :=
  reifyCommand? verifiedParserCore (.structure 0) rootLoopContext true
    rootLoopLayout 42 parserRecognizeRootLoop

private theorem rootLoopReification_exists :
    rootLoopReification?.isSome := by
  native_decide

/-- Complete final-chart root search recovered from the checked recognizer. -/
def parserRecognizeRootLoopView :=
  rootLoopReification?.get rootLoopReification_exists

theorem parserRecognizeRootLoopView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      rootLoopLayout 42 parserRecognizeRootLoopView.command =
      parserRecognizeRootLoop :=
  parserRecognizeRootLoopView.toCoreExactly

private def rootBodyReification? :=
  reifyCommand? verifiedParserCore (.structure 0) rootLoopContext true
    rootLoopLayout 42 parserRecognizeRootLoopBody

private theorem rootBodyReification_exists :
    rootBodyReification?.isSome := by
  native_decide

private def parserRecognizeRootBodyView :=
  rootBodyReification?.get rootBodyReification_exists

private theorem parserRecognizeRootBodyView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      rootLoopLayout 42 parserRecognizeRootBodyView.command =
      parserRecognizeRootLoopBody :=
  parserRecognizeRootBodyView.toCoreExactly

private def rootRejectedReification? :=
  reifyCommand? verifiedParserCore (.structure 0) rootLoopContext false
    rootLoopLayout 42 parserRecognizeRejectedReturn

private theorem rootRejectedReification_exists :
    rootRejectedReification?.isSome := by
  native_decide

/-- Rejected-result continuation recovered directly from the checked
    recognizer after the final root loop. -/
private def parserRecognizeRejectedView :=
  rootRejectedReification?.get rootRejectedReification_exists

private theorem parserRecognizeRejectedView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      rootLoopLayout 42 parserRecognizeRejectedView.command =
      parserRecognizeRejectedReturn :=
  parserRecognizeRejectedView.toCoreExactly

/-! The root statement itself has one additional live source local: local `6`
    carries the final chart position used by the `root_state` initializer.
    Reifying the complete statement here prevents its lexical binding and
    continuation from being assembled only by the physical-state proof. -/

private def rootStatementLayout : Layout 7 := fun index =>
  [0, 4, 6, 8, 12, 18, 22].get index

private def rootStatementContext : Context :=
  let c0 := Context.empty.bind 0 (.slice parserI32Type)
  let c1 := c0.bind 4 (.slice parserI32Type)
  let c2 := c1.bind 6 parserI32Type
  let c3 := c2.bind 8 parserI32Type
  let c4 := c3.bind 12 parserI32Type
  let c5 := c4.bind 18 parserI32Type
  c5.bind 22 parserI32Type

private def rootStatementReification? :=
  reifyCommand? verifiedParserCore (.structure 0) rootStatementContext false
    rootStatementLayout 41 parserRecognizeRootStatement

private theorem rootStatementReification_exists :
    rootStatementReification?.isSome := by
  native_decide

/-- The complete final root-selection statement, mechanically recovered from
    the checked `parser.lani::recognize` body. -/
private def parserRecognizeRootStatementView :=
  rootStatementReification?.get rootStatementReification_exists

private theorem parserRecognizeRootStatementView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      rootStatementLayout 41 parserRecognizeRootStatementView.command =
      parserRecognizeRootStatement :=
  parserRecognizeRootStatementView.toCoreExactly

def rootLoopCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 7 :=
  stateGreaterEqualZeroTerm ⟨6, by omega⟩

def rootBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 7 :=
  parserRecognizeRootBodyView.command

def rootLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 7 :=
  .whileLoop rootLoopCondition rootBodyCommand

private theorem rootLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      rootLoopLayout 42 rootLoopCommand = parserRecognizeRootLoop := by
  rw [rootLoopCommand, Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    rootLoopCondition, stateGreaterEqualZeroTerm, rootBodyCommand,
    parserRecognizeRootBodyView_toCore_exactly]
  exact extractedParserRecognize_root_loop_shape.symm

def rootEqualTerm {arity : Nat}
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary .equal parserI32Type parserI32Type (.scalar .bool))
    [left, right]

def rootPredicateTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 8 :=
  .logicalAnd
    (.logicalAnd
      (rootEqualTerm
        (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩ 30)
        (stateLiteral 0))
      (rootEqualTerm
        (stateLhsTerm ⟨0, by omega⟩ ⟨7, by omega⟩)
        (stateSlot ⟨3, by omega⟩)))
    (rootEqualTerm
      (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩ 29)
      (stateRhsLengthTerm ⟨0, by omega⟩ ⟨7, by omega⟩))

def rootSuccessResultTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 8 :=
  .apply (.call extractedParserParseResultFunction.id
      [parserI32Type, parserI32Type, parserI32Type, parserI32Type]
      (.structure 0)) [
    .apply (.constant 0 parserI32Type) [],
    stateSlot ⟨4, by omega⟩,
    stateSlot ⟨6, by omega⟩,
    stateLiteral 0]

def rootSuccessCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 8 :=
  .sequence (.returnValue (some rootSuccessResultTerm)) .skip

def rootRejectedResultTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 7 :=
  .apply (.call extractedParserParseResultFunction.id
      [parserI32Type, parserI32Type, parserI32Type, parserI32Type]
      (.structure 0)) [
    .apply (.constant 1 parserI32Type) [],
    stateSlot ⟨4, by omega⟩,
    .apply (.unary .negate parserI32Type parserI32Type) [stateLiteral 1],
    stateSlot ⟨5, by omega⟩]

def rootRejectedCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 7 :=
  parserRecognizeRejectedView.command

def rootExpectedRejectedCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 7 :=
  .sequence (.returnValue (some rootRejectedResultTerm)) .skip

theorem rootRejectedCommand_shape :
    rootRejectedCommand = rootExpectedRejectedCommand := by
  apply stateCommandMatches_sound
  native_decide

/-- Layout after the source `root_state` binding has extended the root
    statement's seven-slot environment. -/
private def rootStatementBoundLayout : Layout 8 := fun index =>
  [0, 4, 6, 8, 12, 18, 22, 41].get index

/-- Placement of the compact root-loop environment inside the environment of
    the complete root statement.  Slot `2` in the larger environment is the
    final position; the compact loop does not use it. -/
def rootIntoStatementEmbedding :
    Lanius.FunctionalView.Embedding 7 8 where
  slot := fun index => [0, 1, 3, 4, 5, 6, 7].get index
  injective := by
    exact Lanius.FunctionalView.Embedding.listGetInjective
      ([0, 1, 3, 4, 5, 6, 7] : List (Fin 8)) (by decide)

private theorem rootIntoStatementLayout_extends :
    Layout.Extends rootIntoStatementEmbedding rootLoopLayout
      rootStatementBoundLayout := by
  apply Layout.Extends.ofFn
  native_decide

abbrev rootStatementLoopCommand :=
  Lanius.FunctionalView.Stateful.Command.rename
    Lanius.FunctionalView.Core.Stateful.actionRenamer
    rootIntoStatementEmbedding rootLoopCommand

abbrev rootStatementRejectedCommand :=
  Lanius.FunctionalView.Stateful.Command.rename
    Lanius.FunctionalView.Core.Stateful.actionRenamer
    rootIntoStatementEmbedding rootRejectedCommand

def rootStatementCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 7 :=
  parserRecognizeRootStatementView.command

def rootExpectedStatementCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 7 :=
  .letValue parserI32Type
    (stateChartHeadTerm ⟨1, by omega⟩ ⟨2, by omega⟩)
    (.sequence rootStatementLoopCommand rootStatementRejectedCommand)

/-- Constructor-level decomposition of the mechanically reified complete root
    statement.  In particular, the initializer, loop, and fallback are not a
    second manually maintained parser program. -/
theorem rootStatementCommand_shape :
    rootStatementCommand = rootExpectedStatementCommand := by
  apply stateCommandMatches_sound
  native_decide

/-! The root statement starts after both position counters are bound.  Its
    seven live values are a projection of the existing fifteen-slot position
    environment; the final `position` counter is deliberately framed out. -/

def rootStatementIntoPositionEmbedding :
    Lanius.FunctionalView.Embedding 7 15 where
  slot := fun index => [0, 3, 4, 5, 8, 12, 13].get index
  injective := by
    exact Lanius.FunctionalView.Embedding.listGetInjective
      ([0, 3, 4, 5, 8, 12, 13] : List (Fin 15)) (by decide)

private theorem rootStatementIntoPositionLayout_extends :
    Layout.Extends rootStatementIntoPositionEmbedding rootStatementLayout
      positionLoopLayout := by
  apply Layout.Extends.ofFn
  native_decide

abbrev positionStatementRootCommand :=
  Lanius.FunctionalView.Stateful.Command.rename
    Lanius.FunctionalView.Core.Stateful.actionRenamer
    rootStatementIntoPositionEmbedding rootStatementCommand

def positionStatementCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 13 :=
  parserRecognizePositionStatementView.command

def positionExpectedStatementCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 13 :=
  .letValue parserI32Type (stateLiteral 0)
    (.letValue parserI32Type (stateLiteral 0)
      (.sequence positionLoopCommand positionStatementRootCommand))

/-- Constructor-level decomposition of the one mechanically reified position
    continuation.  The loop and root statement remain their independently
    checked compact commands, placed by structural environment embeddings. -/
theorem positionStatementCommand_shape :
    positionStatementCommand = positionExpectedStatementCommand := by
  apply stateCommandMatches_sound
  native_decide


end Lanius.Extraction.ParserRecognize
