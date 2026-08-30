import Lanius.Extraction.Parser.Recognize.State.Core

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
/-- Reading and binding the next RHS symbol for an incomplete Earley item.
    The result retains the enclosing state-loop frame, including ownership of
    the current cursor and mutable state-count cell. -/
structure RecognizerStateSymbolBinding
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound) where
  afterRead : State
  evaluation : Evaluates verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    (.call extractedParserRhsSymbolFunction.id
      [.local 0, .local 25, .local 26])
    (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)))
    afterRead
  effect : ModifiesOnly CellSet.empty
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) afterRead
  afterReadWellFormed : StateWellFormed afterRead
  invariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell
    (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))
    position current remaining
  productionLocal :
    (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)))).local?
      25 = some (.signed .i32 (Int.ofNat candidate.production))
  productionOwned : (Assertion.localPointsTo 25 bindings.productionCell
    (some (.signed .i32 (Int.ofNat candidate.production)))).holds
      (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))
  dotLocal :
    (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)))).local?
      26 = some (.signed .i32 (Int.ofNat candidate.dot))
  dotOwned : (Assertion.localPointsTo 26 bindings.dotCell
    (some (.signed .i32 (Int.ofNat candidate.dot)))).holds
      (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))
  originLocal :
    (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)))).local?
      27 = some (.signed .i32 (Int.ofNat candidate.origin))
  originOwned : (Assertion.localPointsTo 27 bindings.originCell
    (some (.signed .i32 (Int.ofNat candidate.origin)))).holds
      (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))
  symbolCell : CellId
  symbolLocal :
    (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)))).local?
      29 = some (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)))
  symbolOwned : (Assertion.localPointsTo 29 symbolCell
    (some (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))).holds
      (afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))

noncomputable def RecognizerStateCandidateBindings.bind_incomplete_symbol
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length) :
    RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings := by
  let before := bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
    (Int.ofNat (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.length))
  have productionResult : Evaluates verifiedParserCore before (.local 25)
      (.signed .i32 (Int.ofNat candidate.production)) before :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore before 25 _
      (by simpa [before] using bindings.productionLocal)⟩
  have dotResult : Evaluates verifiedParserCore before (.local 26)
      (.signed .i32 (Int.ofNat candidate.dot)) before :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore before 26 _
      (by simpa [before] using bindings.dotLocal)⟩
  let rhsRead := bindings.invariant.chartCursor.read_rhs_symbol
    candidate.production productionBound candidate.dot dotBeforeEnd
    (.local 25) (.local 26) productionResult dotResult
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let bound := rhsRead.after.bindLocal 29
    (.signed .i32 (Int.ofNat symbol))
  let afterReadInvariant := bindings.invariant.after_empty_effect
    rhsRead.effect rhsRead.invariant.recognizer.wellFormed
  have preserveLocal (id : Nat) (value : Value) (different : 29 ≠ id)
      (source : before.local? id = some value) :
      bound.local? id = some value :=
    (bindLocal_preserves_other_local rhsRead.invariant.recognizer.wellFormed
      different).trans
      (rhsRead.effect.empty_preserves_local
        bindings.invariant.chartCursor.recognizer.wellFormed source)
  have preserveOwned (id : Nat) (cell : CellId) (value : Value)
      (different : 29 ≠ id)
      (source : (Assertion.localPointsTo id cell (some value)).holds before) :
      (Assertion.localPointsTo id cell (some value)).holds bound := by
    have afterReadOwned := rhsRead.effect.empty_preserves_assertion
      bindings.invariant.chartCursor.recognizer.wellFormed _ source
    simpa [bound] using bindLocal_preserves_localPointsTo_of_ne rhsRead.after
      29 id (.signed .i32 (Int.ofNat symbol)) cell (some value)
      rhsRead.invariant.recognizer.wellFormed different afterReadOwned
  let symbolCell := rhsRead.after.nextCell
  exact {
    afterRead := rhsRead.after
    evaluation := by simpa [before, symbol] using rhsRead.evaluation
    effect := by simpa [before] using rhsRead.effect
    afterReadWellFormed := rhsRead.invariant.recognizer.wellFormed
    invariant := by
      simpa [bound, symbol] using afterReadInvariant.after_bind_local 29
        (.signed .i32 (Int.ofNat symbol)) (by decide)
    productionLocal := by
      simpa [bound, symbol] using preserveLocal 25 _ (by decide)
        bindings.productionLocal
    productionOwned := by
      simpa [before, bound, symbol] using preserveOwned 25
        bindings.productionCell
        (.signed .i32 (Int.ofNat candidate.production)) (by decide)
        bindings.productionOwned
    dotLocal := by
      simpa [bound, symbol] using preserveLocal 26 _ (by decide)
        bindings.dotLocal
    dotOwned := by
      simpa [before, bound, symbol] using preserveOwned 26 bindings.dotCell
        (.signed .i32 (Int.ofNat candidate.dot)) (by decide)
        bindings.dotOwned
    originLocal := by
      simpa [bound, symbol] using preserveLocal 27 _ (by decide)
        bindings.originLocal
    originOwned := by
      simpa [before, bound, symbol] using preserveOwned 27
        bindings.originCell (.signed .i32 (Int.ofNat candidate.origin))
        (by decide) bindings.originOwned
    symbolCell := symbolCell
    symbolLocal := by
      simpa [bound, symbol] using bindLocal_finds_local rhsRead.after 29
        (.signed .i32 (Int.ofNat symbol))
        rhsRead.invariant.recognizer.wellFormed
    symbolOwned := by
      simpa [bound, symbolCell, symbol] using bindLocal_owns_fresh
        rhsRead.after 29 (.signed .i32 (Int.ofNat symbol))
        rhsRead.invariant.recognizer.wellFormed
  }

end Lanius.Extraction.ParserRecognize
