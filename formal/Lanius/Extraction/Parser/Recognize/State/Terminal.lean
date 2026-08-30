import Lanius.Extraction.Parser.Recognize.State.Symbol

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

/-- A terminal RHS symbol supplies exactly the precondition expected by the
    separately verified scanner/append operation. -/
theorem RecognizerStateSymbolBinding.to_terminal_ready
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isTerminal :
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds) :
    RecognizerTerminalReadyInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (binding.afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))
      position
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)
      candidate.production candidate.dot candidate.origin current := by
  let after := binding.afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
    ((grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)))
  have dotSuccI32 : candidate.dot + 1 ≤ 2147483647 := by
    have rowRange :=
      binding.invariant.chartCursor.recognizer.grammarWellFormed
        |>.production_validation.rhsRange
          ⟨candidate.production, productionBound⟩
    have tableFits :=
      binding.invariant.chartCursor.recognizer.grammarEncoded.rhsSymbols.2.1
    have wordsFit := binding.invariant.chartCursor.recognizer.wordsI32
    omega
  exact {
    terminal := {
      recognizer := binding.invariant.chartCursor.recognizer
      positionAdvanceI32 := binding.invariant.positionAdvanceI32
      semanticKindBound := by
        rw [binding.invariant.chartCursor.recognizer.grammarWellFormed
          |>.canonicalKindCount]
        exact isTerminal
      positionLocal := binding.invariant.positionLocal
      semanticKindLocal := binding.symbolLocal
    }
    seedDerivation := by
      intro nextPosition scanned
      have symbolFound :
          (grammar.productionAt
            ⟨candidate.production, productionBound⟩).rhs[candidate.dot]? =
            some ((grammar.productionAt
              ⟨candidate.production, productionBound⟩).rhs.get
                ⟨candidate.dot, dotBeforeEnd⟩) := by
        exact List.getElem?_eq_getElem dotBeforeEnd
      have recognized : RecognizesSymbol grammar tokens
          ((grammar.productionAt
            ⟨candidate.production, productionBound⟩).rhs.get
              ⟨candidate.dot, dotBeforeEnd⟩)
          position nextPosition :=
        RecognizesSymbol.terminal isTerminal scanned
      have candidatePosition : candidate.position = position := by
        obtain ⟨cursorState, cursorFound, cursorPosition⟩ :=
          binding.invariant.chartCursor.state_at_cursor
        rw [found] at cursorFound
        injection cursorFound with stateEqual
        subst cursorState
        exact cursorPosition
      exact {
        languageSound := by
          have candidateSound :=
            binding.invariant.chartCursor.recognizer.languageSound current
              candidate found
          have recognizedAtCandidate : RecognizesSymbol grammar tokens
              ((grammar.productionAt
                ⟨candidate.production, productionBound⟩).rhs.get
                  ⟨candidate.dot, dotBeforeEnd⟩)
              candidate.position nextPosition := by
            simpa [candidatePosition] using recognized
          have advanced := candidateSound.advance symbolFound
            recognizedAtCandidate current
            (.token (position / 2)
              ((grammar.productionAt
                ⟨candidate.production, productionBound⟩).rhs.get
                  ⟨candidate.dot, dotBeforeEnd⟩))
          simpa [candidatePosition, recognizerTerminalSeed,
            EarleyState.advanceSeed] using advanced
        backpointer := by
          have currentBefore : current < workspace.states.length :=
            List.getElem?_eq_some_iff.mp found |>.1
          have scannedAtCandidate : scanTerminal grammar tokens
              candidate.position
              ((grammar.productionAt
                ⟨candidate.production, productionBound⟩).rhs.get
                  ⟨candidate.dot, dotBeforeEnd⟩) = some nextPosition := by
            simpa [candidatePosition] using scanned
          have step := EarleyBackpointerStep.terminal
            (grammar := grammar) (tokens := tokens) (workspace := workspace)
            (stateId := workspace.states.length) found currentBefore
            productionBound symbolFound isTerminal scannedAtCandidate
          simpa [candidatePosition, recognizerTerminalSeed,
            EarleyState.advanceSeed] using step
      }
    dotSuccI32 := dotSuccI32
    originBound :=
      binding.invariant.chartCursor.recognizer.workspaceEncoded.originsBound
        current candidate found
    stateBaseLocal := binding.invariant.appendFrame.stateBaseLocal
    stateCapacityLocal := binding.invariant.appendFrame.stateCapacityLocal
    stateCountLocal := binding.invariant.appendFrame.stateCountLocal
    stateCountOwned := binding.invariant.appendFrame.stateCountOwned
    stateCountBackingDistinct :=
      binding.invariant.appendFrame.stateCountBackingDistinct
    stateCountParameterSeparate :=
      binding.invariant.appendFrame.stateCountParameterSeparate
    stateIdLocal := Assertion.localPointsTo_local 24 cursorCell _ after
      binding.invariant.chartCursor.cursorOwned
    productionLocal := binding.productionLocal
    dotLocal := binding.dotLocal
    originLocal := binding.originLocal
  }

/-- Functional execution of the exact incomplete-state branch when a terminal
    scanner misses.  The symbol binding and scanner binding are both closed,
    leaving the decoded-state environment unchanged. -/
private theorem RecognizerStateSymbolBinding.functional_terminal_miss
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (environment : Lanius.FunctionalView.Env 17)
    (locals : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment)
    (isTerminal :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      symbol < grammar.grammar.n_kinds)
    (miss :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      scanTerminal grammar tokens position symbol = none) :
    let symbol := (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
    let world := stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateIncompleteCommand .next world environment := by
  dsimp only
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let afterSymbol := environment.push (.signed .i32 (Int.ofNat symbol))
  have lift (index : Fin 17) (value : Value)
      (valueEq : environment index = value) :
      afterSymbol ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ = value := by
    calc
      afterSymbol ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ =
          environment index := by
        exact Lanius.FunctionalView.Env.push_before environment
          (.signed .i32 (Int.ofNat symbol)) index
      _ = value := valueEq
  have symbolLocal : afterSymbol ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol) := by
    exact Lanius.FunctionalView.Env.push_last environment
      (.signed .i32 (Int.ofNat symbol))
  have isTerminal' : symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isTerminal
  have miss' : scanTerminal grammar tokens position symbol = none := by
    simpa [symbol] using miss
  let ready := binding.to_terminal_ready isTerminal'
  have terminalResult := stateTerminalCommand_evaluates_miss workspaceLayout
    grammar words tokens grammarCell tokensCell world afterSymbol position symbol
    (lift ⟨0, by omega⟩ _ locals.grammarEq)
    (lift ⟨1, by omega⟩ _ locals.tokensEq)
    (lift ⟨2, by omega⟩ _ locals.tokenCountEq)
    (lift ⟨11, by omega⟩ _ locals.positionEq) symbolLocal
    stateWorld_finds_grammar
    (stateWorld_finds_tokens ready.terminal.recognizer) miss'
  have terminalSelected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world afterSymbol stateTerminalCommand .next world afterSymbol := by
    simpa [world, afterSymbol] using terminalResult
  have branchResult := stateIncompleteCommand_evaluates_of_symbol
    workspaceLayout grammar words tokens grammarCell tokensCell world
    environment candidate.production candidate.dot symbol productionBound
    dotBeforeEnd rfl grammar.grammar.n_kinds locals.grammarEq locals.productionEq
    locals.dotEq locals.kindCountEq stateWorld_finds_grammar true
    (by simp [isTerminal']) terminalSelected
  simpa [afterSymbol, world, symbol] using branchResult

/-- Functional execution of the complete incomplete-state branch when a
    terminal scan appends successfully. -/
private theorem RecognizerStateSymbolBinding.functional_terminal_ok
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (environment : Lanius.FunctionalView.Env 17)
    (locals : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment)
    (isTerminal :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      symbol < grammar.grammar.n_kinds)
    (nextPosition : Nat)
    (scanResult :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      scanTerminal grammar tokens position symbol = some nextPosition)
    (nextPositionBound : nextPosition ≤
      finalPosition workspaceLayout.tokenCount)
    (statusOk :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      let seed := recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position symbol
      (appendLogical workspaceLayout.capacity nextPosition seed
        workspace).1.status = .ok) :
    let symbol := (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
    let seed := recognizerTerminalSeed candidate.production candidate.dot
      candidate.origin current position symbol
    let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace nextPosition
      seed workspaceValues
    let beforeWorld := stateWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment stateIncompleteCommand .next afterWorld
      (Lanius.FunctionalView.Stateful.Env.set environment ⟨10, by omega⟩
        (.signed .i32 (Int.ofNat outcome.stateCount))) := by
  dsimp only
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let seed := recognizerTerminalSeed candidate.production candidate.dot
    candidate.origin current position symbol
  let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace nextPosition
    seed workspaceValues
  let beforeWorld := stateWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
    workspaceCell
  let afterSymbol := environment.push (.signed .i32 (Int.ofNat symbol))
  have lift (index : Fin 17) (value : Value)
      (valueEq : environment index = value) :
      afterSymbol ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ = value := by
    calc
      afterSymbol ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ =
          environment index := by
        exact Lanius.FunctionalView.Env.push_before environment
          (.signed .i32 (Int.ofNat symbol)) index
      _ = value := valueEq
  have symbolLocal : afterSymbol ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol) :=
    Lanius.FunctionalView.Env.push_last environment
      (.signed .i32 (Int.ofNat symbol))
  have isTerminal' : symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isTerminal
  have scanResult' : scanTerminal grammar tokens position symbol =
      some nextPosition := by simpa [symbol] using scanResult
  have statusOk' : (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1.status = .ok := by simpa [seed, symbol] using statusOk
  let ready := binding.to_terminal_ready isTerminal'
  let matched := ready.bind_scan_match nextPosition scanResult'
    nextPositionBound
  have terminalResult := matched.invariant.functional_terminal_ok afterSymbol
    (lift ⟨0, by omega⟩ _ locals.grammarEq)
    (lift ⟨1, by omega⟩ _ locals.tokensEq)
    (lift ⟨2, by omega⟩ _ locals.tokenCountEq)
    (lift ⟨3, by omega⟩ _ locals.workspaceEq)
    (lift ⟨4, by omega⟩ _ locals.stateBaseEq)
    (lift ⟨5, by omega⟩ _ locals.capacityEq)
    (lift ⟨10, by omega⟩ _ locals.stateCountEq)
    (lift ⟨11, by omega⟩ _ locals.positionEq)
    (lift ⟨12, by omega⟩ _ locals.currentEq)
    (lift ⟨13, by omega⟩ _ locals.productionEq)
    (lift ⟨14, by omega⟩ _ locals.dotEq)
    (lift ⟨15, by omega⟩ _ locals.originEq) symbolLocal statusOk'
  have branchResult := stateIncompleteCommand_evaluates_of_symbol
    workspaceLayout grammar words tokens grammarCell tokensCell beforeWorld
    environment candidate.production candidate.dot symbol productionBound
    dotBeforeEnd rfl grammar.grammar.n_kinds locals.grammarEq
    locals.productionEq locals.dotEq locals.kindCountEq stateWorld_finds_grammar
    true (by simp [isTerminal']) terminalResult
  have environmentResult :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.set afterSymbol ⟨10, by omega⟩
          (.signed .i32 (Int.ofNat outcome.stateCount))) =
      Lanius.FunctionalView.Stateful.Env.set environment ⟨10, by omega⟩
        (.signed .i32 (Int.ofNat outcome.stateCount)) := by
    funext index
    simp [afterSymbol, Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, Fin.ext_iff]
    rfl
  rw [environmentResult] at branchResult
  simpa [beforeWorld, afterWorld, nextValues, seed, outcome, symbol] using
    branchResult

/-- Functional execution of the complete incomplete-state branch when the
    terminal append reports capacity exhaustion. -/
private theorem RecognizerStateSymbolBinding.functional_terminal_full
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (environment : Lanius.FunctionalView.Env 17)
    (locals : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment)
    (isTerminal :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      symbol < grammar.grammar.n_kinds)
    (nextPosition : Nat)
    (scanResult :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      scanTerminal grammar tokens position symbol = some nextPosition)
    (nextPositionBound : nextPosition ≤
      finalPosition workspaceLayout.tokenCount)
    (statusFull :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      let seed := recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position symbol
      (appendLogical workspaceLayout.capacity nextPosition seed
        workspace).1.status = .full) :
    let symbol := (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
    let seed := recognizerTerminalSeed candidate.production candidate.dot
      candidate.origin current position symbol
    let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace nextPosition
      seed workspaceValues
    let beforeWorld := stateWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment stateIncompleteCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld environment := by
  dsimp only
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let seed := recognizerTerminalSeed candidate.production candidate.dot
    candidate.origin current position symbol
  let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace nextPosition
    seed workspaceValues
  let beforeWorld := stateWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
    workspaceCell
  let afterSymbol := environment.push (.signed .i32 (Int.ofNat symbol))
  have lift (index : Fin 17) (value : Value)
      (valueEq : environment index = value) :
      afterSymbol ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ = value := by
    calc
      afterSymbol ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ =
          environment index := by
        exact Lanius.FunctionalView.Env.push_before environment
          (.signed .i32 (Int.ofNat symbol)) index
      _ = value := valueEq
  have symbolLocal : afterSymbol ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol) :=
    Lanius.FunctionalView.Env.push_last environment
      (.signed .i32 (Int.ofNat symbol))
  have isTerminal' : symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isTerminal
  have scanResult' : scanTerminal grammar tokens position symbol =
      some nextPosition := by simpa [symbol] using scanResult
  have statusFull' : (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1.status = .full := by simpa [seed, symbol] using statusFull
  let ready := binding.to_terminal_ready isTerminal'
  let matched := ready.bind_scan_match nextPosition scanResult'
    nextPositionBound
  have terminalResult := matched.invariant.functional_terminal_full afterSymbol
    (lift ⟨0, by omega⟩ _ locals.grammarEq)
    (lift ⟨1, by omega⟩ _ locals.tokensEq)
    (lift ⟨2, by omega⟩ _ locals.tokenCountEq)
    (lift ⟨3, by omega⟩ _ locals.workspaceEq)
    (lift ⟨4, by omega⟩ _ locals.stateBaseEq)
    (lift ⟨5, by omega⟩ _ locals.capacityEq)
    (lift ⟨10, by omega⟩ _ locals.stateCountEq)
    (lift ⟨11, by omega⟩ _ locals.positionEq)
    (lift ⟨12, by omega⟩ _ locals.currentEq)
    (lift ⟨13, by omega⟩ _ locals.productionEq)
    (lift ⟨14, by omega⟩ _ locals.dotEq)
    (lift ⟨15, by omega⟩ _ locals.originEq) symbolLocal statusFull'
  have branchResult := stateIncompleteCommand_evaluates_of_symbol
    workspaceLayout grammar words tokens grammarCell tokensCell beforeWorld
    environment candidate.production candidate.dot symbol productionBound
    dotBeforeEnd rfl grammar.grammar.n_kinds locals.grammarEq
    locals.productionEq locals.dotEq locals.kindCountEq stateWorld_finds_grammar
    true (by simp [isTerminal']) terminalResult
  simpa [afterSymbol, beforeWorld, afterWorld, nextValues, seed, outcome,
    symbol] using branchResult

structure RecognizerStateTerminalMissResult
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
  after : State
  execution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    parserRecognizeStateIncompleteBranch .next after
  effect : ModifiesOnly CellSet.empty
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) after
  invariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position current remaining

/-- Execute the entire extracted incomplete-state branch when its terminal
    scanner does not match.  No workspace or scalar cell changes, and local 29
    is removed again before the enclosing state loop resumes. -/
noncomputable def RecognizerStateSymbolBinding.execute_terminal_miss
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isTerminal :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      symbol < grammar.grammar.n_kinds)
    (miss :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      scanTerminal grammar tokens position symbol = none) :
    RecognizerStateTerminalMissResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings := by
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let source := bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
    (Int.ofNat (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.length))
  let bound := binding.afterRead.bindLocal 29
    (.signed .i32 (Int.ofNat symbol))
  have isTerminal' : symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isTerminal
  have miss' : scanTerminal grammar tokens position symbol = none := by
    simpa [symbol] using miss
  let ready := binding.to_terminal_ready isTerminal'
  let terminalProof := ready.terminal.executes_no_match miss'
  let terminalAfter := Classical.choose terminalProof
  have terminalFacts := Classical.choose_spec terminalProof
  have terminalExecution := terminalFacts.1
  have terminalEffect := terminalFacts.2.1
  have terminalWellFormed := terminalFacts.2.2.1
  have symbolResult : Evaluates verifiedParserCore bound (.local 29)
      (.signed .i32 (Int.ofNat symbol)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 29 _
      (by simpa [bound, symbol] using binding.symbolLocal)⟩
  have kindCountResult : Evaluates verifiedParserCore bound (.local 11)
      (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 11 _
      (by simpa [bound, symbol] using binding.invariant.kindCountLocal)⟩
  have terminalTest : Evaluates verifiedParserCore bound
      (.binary .less (.local 29) (.local 11)) (.boolean true) bound := by
    have compared := evaluatesNatLessThreaded bound bound bound
      (.local 29) (.local 11) symbol grammar.grammar.n_kinds
      symbolResult kindCountResult
    simpa [isTerminal'] using compared
  have selected : Executes verifiedParserCore bound
      (.ifThenElse (.binary .less (.local 29) (.local 11))
        parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
      .next terminalAfter :=
    executesIfTrue terminalTest terminalExecution
  have body : Executes verifiedParserCore bound
      (.sequence
        (.ifThenElse (.binary .less (.local 29) (.local 11))
          parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
        .skip) .next terminalAfter :=
    executesSequence selected (executesSkip verifiedParserCore terminalAfter)
  let after := restoreLocals binding.afterRead terminalAfter
  have execution : Executes verifiedParserCore source
      parserRecognizeStateIncompleteBranch .next after := by
    rw [extractedParserRecognize_state_incomplete_shape]
    simpa [source, bound, after, symbol] using
      executesLetLocal (type := parserI32Type) binding.evaluation body
  have entered : StoreEffect CellSet.empty binding.afterRead bound := by
    simpa [bound] using bindLocal_effect binding.afterRead 29
      (.signed .i32 (Int.ofNat symbol))
  have scopedStore : StoreEffect CellSet.empty binding.afterRead terminalAfter :=
    entered.trans_same terminalEffect.toStoreEffect
  have closed : ModifiesOnly CellSet.empty binding.afterRead after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly CellSet.empty source after := by
    simpa [source] using binding.effect.trans_same closed
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed
      binding.afterReadWellFormed terminalWellFormed
  exact {
    after := after
    execution := execution
    effect := effect
    invariant := bindings.invariant.after_empty_effect effect afterWellFormed
  }

structure RecognizerStateTerminalSuccessResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current nextPosition : Nat)
    (remaining : List Nat)
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
  after : State
  execution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    parserRecognizeStateIncompleteBranch .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) after
  recognizer : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))
      workspace).2
    (appendResultValues workspaceLayout workspace nextPosition
      (recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))
      workspaceValues)
    grammarCell tokensCell workspaceCell after
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat
      (appendLogical workspaceLayout.capacity nextPosition
        (recognizerTerminalSeed candidate.production candidate.dot
          candidate.origin current position
          ((grammar.productionAt ⟨candidate.production,
            productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))
        workspace).2.states.length)))).holds after
  growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
    (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))
      workspace).2
  workspaceWithinGrammar : WorkspaceWithinGrammar grammar
    (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position
        ((grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))
      workspace).2

/-- Execute a successful terminal scan and append, close local 29, and expose
    the new logical workspace with both its append certificate and grammar-
    domain invariant. -/
noncomputable def RecognizerStateSymbolBinding.execute_terminal_success
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isTerminal :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      symbol < grammar.grammar.n_kinds)
    (nextPosition : Nat)
    (scanResult :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      scanTerminal grammar tokens position symbol = some nextPosition)
    (nextPositionBound : nextPosition ≤
      finalPosition workspaceLayout.tokenCount)
    (statusOk :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      (appendLogical workspaceLayout.capacity nextPosition
        (recognizerTerminalSeed candidate.production candidate.dot
          candidate.origin current position symbol) workspace).1.status =
        .ok) :
    RecognizerStateTerminalSuccessResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current
      nextPosition remaining beforeInvariant candidate found productionBound
      dotBeforeEnd bindings := by
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let source := bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
    (Int.ofNat (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.length))
  let bound := binding.afterRead.bindLocal 29
    (.signed .i32 (Int.ofNat symbol))
  have isTerminal' : symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isTerminal
  have scanResult' : scanTerminal grammar tokens position symbol =
      some nextPosition := by
    simpa [symbol] using scanResult
  have statusOk' : (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position symbol) workspace).1.status = .ok := by
    simpa [symbol] using statusOk
  let ready := binding.to_terminal_ready isTerminal'
  let matched := ready.execute_match nextPosition scanResult'
    nextPositionBound statusOk'
  have symbolResult : Evaluates verifiedParserCore bound (.local 29)
      (.signed .i32 (Int.ofNat symbol)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 29 _
      (by simpa [bound, symbol] using binding.symbolLocal)⟩
  have kindCountResult : Evaluates verifiedParserCore bound (.local 11)
      (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 11 _
      (by simpa [bound, symbol] using binding.invariant.kindCountLocal)⟩
  have terminalTest : Evaluates verifiedParserCore bound
      (.binary .less (.local 29) (.local 11)) (.boolean true) bound := by
    have compared := evaluatesNatLessThreaded bound bound bound
      (.local 29) (.local 11) symbol grammar.grammar.n_kinds
      symbolResult kindCountResult
    simpa [isTerminal'] using compared
  have selected : Executes verifiedParserCore bound
      (.ifThenElse (.binary .less (.local 29) (.local 11))
        parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
      .next matched.after :=
    executesIfTrue terminalTest matched.execution
  have body : Executes verifiedParserCore bound
      (.sequence
        (.ifThenElse (.binary .less (.local 29) (.local 11))
          parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
        .skip) .next matched.after :=
    executesSequence selected (executesSkip verifiedParserCore matched.after)
  let after := restoreLocals binding.afterRead matched.after
  have execution : Executes verifiedParserCore source
      parserRecognizeStateIncompleteBranch .next after := by
    rw [extractedParserRecognize_state_incomplete_shape]
    simpa [source, bound, after, symbol] using
      executesLetLocal (type := parserI32Type) binding.evaluation body
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  have entered : StoreEffect CellSet.empty binding.afterRead bound := by
    simpa [bound] using bindLocal_effect binding.afterRead 29
      (.signed .i32 (Int.ofNat symbol))
  have scopedStore : StoreEffect writes binding.afterRead matched.after :=
    (entered.weaken CellSet.empty_subset).trans_same matched.effect.toStoreEffect
  have closed : ModifiesOnly writes binding.afterRead after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly writes source after :=
    (binding.effect.weaken CellSet.empty_subset).trans_same closed
  have preservedCellId (id : VarId) (different : 29 ≠ id) :
      bound.cellId? id = binding.afterRead.cellId? id := by
    simp [bound, State.bindLocal, State.bindCell, State.cellId?, different]
  have parameterCellId : ∀ id, id ∈ verifiedParserRecognizerParameterIds →
      bound.cellId? id = binding.afterRead.cellId? id := by
    intro id idBound
    have idLe := (mem_verifiedParserRecognizerParameterIds_iff id).mp idBound
    exact preservedCellId id
      (Nat.ne_of_gt (Nat.lt_of_le_of_lt idLe (by decide : 5 < 29)))
  have recognizer := RecognizerInvariant.restore_temporary
    binding.afterRead bound matched.after binding.afterReadWellFormed entered
    matched.effect parameterCellId matched.invariant
  have countOwned := localPointsTo_restore_temporary binding.afterRead bound
    matched.after 18 stateCountCell
    (some (.signed .i32 (Int.ofNat
      (appendLogical workspaceLayout.capacity nextPosition
        (recognizerTerminalSeed candidate.production candidate.dot
          candidate.origin current position symbol) workspace).2.states.length)))
    matched.effect (preservedCellId 18 (by decide)) matched.stateCountOwned
  let seed := recognizerTerminalSeed candidate.production candidate.dot
    candidate.origin current position symbol
  let logical := appendLogical workspaceLayout.capacity nextPosition seed
    workspace
  let appended := appendLogical_refines logical rfl
  have seedWithin : StateKeyWithinGrammar grammar seed.key := {
    productionBound := by
      simpa [seed, recognizerTerminalSeed, StateSeed.key] using productionBound
    dotBound := by
      simpa [seed, recognizerTerminalSeed, StateSeed.key] using
        Nat.succ_le_of_lt dotBeforeEnd
  }
  exact {
    after := after
    execution := execution
    effect := by simpa [source, writes] using effect
    recognizer := by simpa [logical, seed, symbol] using recognizer
    stateCountOwned := by
      simpa [logical, seed, symbol] using countOwned
    growth := by
      simpa [logical, seed, symbol] using
        WorkspaceAppendClosure.single workspaceLayout.capacity nextPosition seed
          workspace
    workspaceWithinGrammar := by
      simpa [logical, seed, symbol] using appended.preserves_withinGrammar
        binding.invariant.chartCursor.workspaceWithinGrammar seedWithin
  }

structure RecognizerStateTerminalFullResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current nextPosition : Nat)
    (remaining : List Nat)
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
  after : State
  execution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    parserRecognizeStateIncompleteBranch
    (.returned (some (parseResultValue 2
      (Int.ofNat
        (appendLogical workspaceLayout.capacity nextPosition
          (recognizerTerminalSeed candidate.production candidate.dot
            candidate.origin current position
            ((grammar.productionAt ⟨candidate.production,
              productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))
          workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell)
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerStateSymbolBinding.execute_terminal_full
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isTerminal :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      symbol < grammar.grammar.n_kinds)
    (nextPosition : Nat)
    (scanResult :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      scanTerminal grammar tokens position symbol = some nextPosition)
    (nextPositionBound : nextPosition ≤
      finalPosition workspaceLayout.tokenCount)
    (statusFull :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      (appendLogical workspaceLayout.capacity nextPosition
        (recognizerTerminalSeed candidate.production candidate.dot
          candidate.origin current position symbol) workspace).1.status =
        .full) :
    RecognizerStateTerminalFullResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current
      nextPosition remaining beforeInvariant candidate found productionBound
      dotBeforeEnd bindings := by
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let source := bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
    (Int.ofNat (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.length))
  let bound := binding.afterRead.bindLocal 29
    (.signed .i32 (Int.ofNat symbol))
  have isTerminal' : symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isTerminal
  have scanResult' : scanTerminal grammar tokens position symbol =
      some nextPosition := by
    simpa [symbol] using scanResult
  have statusFull' : (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position symbol) workspace).1.status =
      .full := by
    simpa [symbol] using statusFull
  let ready := binding.to_terminal_ready isTerminal'
  let full := ready.execute_match_full nextPosition scanResult'
    nextPositionBound statusFull'
  have symbolResult : Evaluates verifiedParserCore bound (.local 29)
      (.signed .i32 (Int.ofNat symbol)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 29 _
      (by simpa [bound, symbol] using binding.symbolLocal)⟩
  have kindCountResult : Evaluates verifiedParserCore bound (.local 11)
      (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 11 _
      (by simpa [bound, symbol] using binding.invariant.kindCountLocal)⟩
  have terminalTest : Evaluates verifiedParserCore bound
      (.binary .less (.local 29) (.local 11)) (.boolean true) bound := by
    have compared := evaluatesNatLessThreaded bound bound bound
      (.local 29) (.local 11) symbol grammar.grammar.n_kinds
      symbolResult kindCountResult
    simpa [isTerminal'] using compared
  have selected : Executes verifiedParserCore bound
      (.ifThenElse (.binary .less (.local 29) (.local 11))
        parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
      (.returned (some (parseResultValue 2
        (Int.ofNat
          (appendLogical workspaceLayout.capacity nextPosition
            (recognizerTerminalSeed candidate.production candidate.dot
              candidate.origin current position symbol) workspace).1.stateCount)
        (-1) (Int.ofNat position)))) full.after :=
    executesIfTrue terminalTest full.execution
  have body : Executes verifiedParserCore bound
      (.sequence
        (.ifThenElse (.binary .less (.local 29) (.local 11))
          parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
        .skip)
      (.returned (some (parseResultValue 2
        (Int.ofNat
          (appendLogical workspaceLayout.capacity nextPosition
            (recognizerTerminalSeed candidate.production candidate.dot
              candidate.origin current position symbol) workspace).1.stateCount)
        (-1) (Int.ofNat position)))) full.after :=
    executesSequenceReturned selected
  let after := restoreLocals binding.afterRead full.after
  have execution : Executes verifiedParserCore source
      parserRecognizeStateIncompleteBranch
      (.returned (some (parseResultValue 2
        (Int.ofNat
          (appendLogical workspaceLayout.capacity nextPosition
            (recognizerTerminalSeed candidate.production candidate.dot
              candidate.origin current position symbol) workspace).1.stateCount)
        (-1) (Int.ofNat position)))) after := by
    rw [extractedParserRecognize_state_incomplete_shape]
    simpa [source, bound, after, symbol] using
      executesLetLocal (type := parserI32Type) binding.evaluation body
  have entered : StoreEffect CellSet.empty binding.afterRead bound := by
    simpa [bound] using bindLocal_effect binding.afterRead 29
      (.signed .i32 (Int.ofNat symbol))
  have scopedStore : StoreEffect (CellSet.singleton workspaceCell)
      binding.afterRead full.after :=
    (entered.weaken CellSet.empty_subset).trans_same full.effect.toStoreEffect
  have closed : ModifiesOnly (CellSet.singleton workspaceCell)
      binding.afterRead after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly (CellSet.singleton workspaceCell) source after :=
    (binding.effect.weaken CellSet.empty_subset).trans_same closed
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed binding.afterReadWellFormed
      full.wellFormed
  have parameterCellId : ∀ id,
      id ∈ verifiedParserRecognizerParameterIds →
      bound.cellId? id = binding.afterRead.cellId? id := by
    intro id member
    apply bindLocal_preserves_other_cellId
    exact Nat.ne_of_gt (Nat.lt_of_le_of_lt
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp member)
      (by decide : 5 < 29))
  have restoredInvariant : RecognizerInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell after := by
    simpa [after] using RecognizerInvariant.restore_temporary
      binding.afterRead bound full.after binding.afterReadWellFormed entered
      full.effect parameterCellId full.invariant
  exact {
    after := after
    execution := by simpa [source, symbol] using execution
    effect := by simpa [source] using effect
    wellFormed := afterWellFormed
    invariant := restoredInvariant
  }

structure RecognizerStateTerminalExecution
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
  after : State
  completion : Completion
  execution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    parserRecognizeStateIncompleteBranch completion after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) after
  outcome : RecognizerStateOperationOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position current remaining after completion

/-- Total terminal branch of one Earley state.  It decides the mathematical
    scanner and append result, selecting exactly one of miss, successful
    append, or capacity return. -/
noncomputable def RecognizerStateSymbolBinding.execute_terminal
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isTerminal :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      symbol < grammar.grammar.n_kinds) :
    RecognizerStateTerminalExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint
        (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
          (grammar.productionAt ⟨candidate.production,
            productionBound⟩).rhs.length)))
        verifiedParserStateLoopPreservedBindings) writes := by
    intro cell framed written
    apply bindings.invariant.persistentSeparate cell framed
    rcases written with workspaceWritten | countWritten
    · exact Or.inl workspaceWritten
    · exact Or.inr (Or.inl countWritten)
  have cursorNotWritten : ¬ writes cursorCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨bindings.invariant.chartCursor.cursorBackingDistinct.2.2,
        bindings.invariant.cursorStateCountDistinct⟩
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  have isTerminal' : symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isTerminal
  cases scanEq : scanTerminal grammar tokens position symbol with
  | none =>
      let miss := binding.execute_terminal_miss isTerminal' scanEq
      let terminalEffect : ModifiesOnly writes
          (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
            (grammar.productionAt ⟨candidate.production,
              productionBound⟩).rhs.length))) miss.after :=
        miss.effect.weaken CellSet.empty_subset
      exact {
        after := miss.after
        completion := .next
        execution := miss.execution
        effect := terminalEffect
        outcome := .completed workspace workspaceValues miss.after
          (.refl workspace)
          (bindings.invariant.reframe_growth workspace workspaceValues
            miss.after (.refl workspace)
            miss.invariant.chartCursor.recognizer
            miss.invariant.chartCursor.workspaceWithinGrammar
            miss.invariant.appendFrame.stateCountOwned writes terminalEffect
            frameDisjoint cursorNotWritten)
      }
  | some nextPosition =>
      have nextPositionBound : nextPosition ≤
          finalPosition workspaceLayout.tokenCount := by
        have bounded := scanTerminal_some_le_finalPosition grammar tokens
          position symbol nextPosition scanEq
        simpa [binding.invariant.chartCursor.recognizer.workspaceTokenCount]
          using bounded
      let seed := recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position symbol
      let logical := appendLogical workspaceLayout.capacity nextPosition seed
        workspace
      cases statusEq : logical.1.status with
      | ok =>
          let success := binding.execute_terminal_success isTerminal'
            nextPosition scanEq nextPositionBound (by
              simpa [logical, seed, symbol] using statusEq)
          exact {
            after := success.after
            completion := .next
            execution := success.execution
            effect := success.effect
            outcome := .completed logical.2
              (appendResultValues workspaceLayout workspace nextPosition seed
                workspaceValues)
              success.after
              (by simpa [logical, seed, symbol] using success.growth)
              (bindings.invariant.reframe_growth logical.2
                (appendResultValues workspaceLayout workspace nextPosition seed
                  workspaceValues)
                success.after
                (by simpa [logical, seed, symbol] using success.growth)
                (by simpa [logical, seed, symbol] using success.recognizer)
                (by simpa [logical, seed, symbol] using
                  success.workspaceWithinGrammar)
                (by simpa [logical, seed, symbol] using success.stateCountOwned)
                writes (by simpa [writes] using success.effect)
                frameDisjoint cursorNotWritten)
          }
      | full =>
          let full := binding.execute_terminal_full isTerminal' nextPosition
            scanEq nextPositionBound (by
              simpa [logical, seed, symbol] using statusEq)
          exact {
            after := full.after
            completion := .returned (some (parseResultValue 2
              (Int.ofNat logical.1.stateCount) (-1) (Int.ofNat position)))
            execution := by simpa [logical, seed, symbol] using full.execution
            effect := full.effect.weaken (by
              intro cell written
              exact Or.inl written)
            outcome := .full workspace workspaceValues full.after
              (.refl workspace) full.invariant logical.1.stateCount
              full.wellFormed
          }

/-- One terminal branch execution viewed simultaneously through the immutable
    FunctionalView model and the physical Core store.  The shared outcome
    prevents the two refinements from choosing unrelated workspace witnesses. -/
structure RecognizerStateTerminalFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current
      remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound)
    (environment : Lanius.FunctionalView.Env 17) where
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 17
  completion : Lanius.FunctionalView.Stateful.Completion
  physicalAfter : State
  functionalExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (stateTermMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell)
    environment stateIncompleteCommand completion afterWorld afterEnvironment
  physicalExecution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    parserRecognizeStateIncompleteBranch
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  physicalEffect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) physicalAfter
  outcome : RecognizerStateBranchSynchronizedOutcome grammarLayout grammar
    words tokens workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position current remaining candidate.production
    candidate.dot candidate.origin
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
    afterWorld afterEnvironment physicalAfter
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)

/-- Execute the source-derived terminal branch once and retain both semantic
    views.  Miss, append, and capacity exhaustion are decided from the same
    scanner/append result, so synchronization is true by construction rather
    than a later determinism argument. -/
noncomputable def
    RecognizerStateSymbolBinding.functional_execute_terminal
    (binding : RecognizerStateSymbolBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (environment : Lanius.FunctionalView.Env 17)
    (locals : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment)
    (isTerminal :
      let symbol := (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
      symbol < grammar.grammar.n_kinds) :
    RecognizerStateTerminalFunctionalExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      environment := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint
        (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
          (grammar.productionAt ⟨candidate.production,
            productionBound⟩).rhs.length)))
        verifiedParserStateLoopPreservedBindings) writes := by
    intro cell framed written
    apply bindings.invariant.persistentSeparate cell framed
    rcases written with workspaceWritten | countWritten
    · exact Or.inl workspaceWritten
    · exact Or.inr (Or.inl countWritten)
  have cursorNotWritten : ¬ writes cursorCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨bindings.invariant.chartCursor.cursorBackingDistinct.2.2,
        bindings.invariant.cursorStateCountDistinct⟩
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  have isTerminal' : symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isTerminal
  cases scanEq : scanTerminal grammar tokens position symbol with
  | none =>
      let miss := binding.execute_terminal_miss isTerminal' scanEq
      let terminalEffect : ModifiesOnly writes
          (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
            (grammar.productionAt ⟨candidate.production,
              productionBound⟩).rhs.length))) miss.after :=
        miss.effect.weaken CellSet.empty_subset
      exact {
        afterWorld := stateWorld words tokens workspaceValues grammarCell
          tokensCell workspaceCell
        afterEnvironment := environment
        completion := .next
        physicalAfter := miss.after
        functionalExecution := by
          simpa [symbol] using binding.functional_terminal_miss environment
            locals isTerminal' scanEq
        physicalExecution := by
          simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
            miss.execution
        physicalEffect := terminalEffect
        outcome := .completed workspace workspaceValues miss.after
          (.refl workspace)
          (bindings.invariant.reframe_growth workspace workspaceValues
            miss.after (.refl workspace)
            miss.invariant.chartCursor.recognizer
            miss.invariant.chartCursor.workspaceWithinGrammar
            miss.invariant.appendFrame.stateCountOwned writes terminalEffect
            frameDisjoint cursorNotWritten)
          rfl locals
      }
  | some nextPosition =>
      have nextPositionBound : nextPosition ≤
          finalPosition workspaceLayout.tokenCount := by
        have bounded := scanTerminal_some_le_finalPosition grammar tokens
          position symbol nextPosition scanEq
        simpa [binding.invariant.chartCursor.recognizer.workspaceTokenCount]
          using bounded
      let seed := recognizerTerminalSeed candidate.production candidate.dot
        candidate.origin current position symbol
      let logical := appendLogical workspaceLayout.capacity nextPosition seed
        workspace
      let nextValues := appendResultValues workspaceLayout workspace
        nextPosition seed workspaceValues
      cases statusEq : logical.1.status with
      | ok =>
          have statusOk : (appendLogical workspaceLayout.capacity nextPosition
              seed workspace).1.status = .ok := by simpa [logical]
          let success := binding.execute_terminal_success isTerminal'
            nextPosition scanEq nextPositionBound (by
              simpa [seed, symbol] using statusOk)
          let afterEnvironment := Lanius.FunctionalView.Stateful.Env.set
            environment 10 (.signed .i32 (Int.ofNat logical.1.stateCount))
          have valuesLength : nextValues.length = workspaceValues.length := by
            simpa [nextValues] using appendResultValues_length workspaceLayout
              workspace nextPosition seed workspaceValues
          have afterLocals : StateAfterBindingsEnvironment grammarLayout grammar
              words tokens workspaceLayout logical.2 nextValues grammarCell
              tokensCell workspaceCell position current candidate.production
              candidate.dot candidate.origin
              (grammar.productionAt ⟨candidate.production,
                productionBound⟩).rhs.length afterEnvironment := by
            simpa [afterEnvironment, logical,
              appendLogical_stateCount_eq] using
              locals.after_workspace_update logical.2 nextValues valuesLength
          exact {
            afterWorld := stateWorld words tokens nextValues grammarCell
              tokensCell workspaceCell
            afterEnvironment := afterEnvironment
            completion := .next
            physicalAfter := success.after
            functionalExecution := by
              simpa [afterEnvironment, logical, nextValues, seed, symbol] using
                binding.functional_terminal_ok environment locals isTerminal'
                  nextPosition scanEq nextPositionBound (by
                    simpa [seed, symbol] using statusOk)
            physicalExecution := by
              simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
                success.execution
            physicalEffect := by simpa [writes] using success.effect
            outcome := .completed logical.2 nextValues success.after
              (by simpa [logical, seed, symbol] using success.growth)
              (bindings.invariant.reframe_growth logical.2 nextValues
                success.after
                (by simpa [logical, seed, symbol] using success.growth)
                (by simpa [logical, nextValues, seed, symbol] using
                  success.recognizer)
                (by simpa [logical, seed, symbol] using
                  success.workspaceWithinGrammar)
                (by simpa [logical, seed, symbol] using success.stateCountOwned)
                writes (by simpa [writes] using success.effect)
                frameDisjoint cursorNotWritten)
              rfl afterLocals
          }
      | full =>
          have statusFull : (appendLogical workspaceLayout.capacity nextPosition
              seed workspace).1.status = .full := by simpa [logical]
          let full := binding.execute_terminal_full isTerminal' nextPosition
            scanEq nextPositionBound (by simpa [seed, symbol] using statusFull)
          have valuesEq : nextValues = workspaceValues := by
            simpa [nextValues] using appendResultValues_eq_of_full
              (layout := workspaceLayout) (workspace := workspace)
              (position := nextPosition) (seed := seed)
              (values := workspaceValues) statusFull
          exact {
            afterWorld := stateWorld words tokens workspaceValues grammarCell
              tokensCell workspaceCell
            afterEnvironment := environment
            completion := .returned (some (parseResultValue 2
              (Int.ofNat logical.1.stateCount) (-1) (Int.ofNat position)))
            physicalAfter := full.after
            functionalExecution := by
              have evaluated := binding.functional_terminal_full environment
                locals isTerminal' nextPosition scanEq nextPositionBound (by
                  simpa [seed, symbol] using statusFull)
              dsimp only at evaluated
              dsimp only [nextValues] at valuesEq
              rw [valuesEq] at evaluated
              simpa [logical, seed, symbol] using evaluated
            physicalExecution := by
              simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
                logical, seed, symbol] using full.execution
            physicalEffect := full.effect.weaken (by
              intro cell written
              exact Or.inl written)
            outcome := .full workspace workspaceValues full.after
              (.refl workspace) full.invariant logical.1.stateCount
              full.wellFormed
          }


end Lanius.Extraction.ParserRecognize
