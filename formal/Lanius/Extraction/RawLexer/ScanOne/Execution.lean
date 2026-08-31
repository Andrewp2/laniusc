import Lanius.Extraction.RawLexer.ScanOne.Evaluation

namespace Lanius.Extraction.RawLexer.ScanOne.Evaluation

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful

def dispatchEnvironment (source : List Byte) (start : Nat) (first : Byte) :
    Env 5 :=
  ((Model.environment source start).push
    (.signed .i32 (Int.ofNat first.val))).push
      (.signed .i32 (Int.ofNat (classifyStartCode first)))

theorem number_evaluates
    (contract : HelperContract calls source world)
    (start : Nat) (first : Byte)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    Term.evaluate (termMachine calls) world
        (dispatchEnvironment source start first)
        (Commands.call Number.Functions.scanNumberFunction
          [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
      .ok (Model.encodedNumber (scanNumber source start),
        world) := by
  unfold Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons (by rfl)
      (evaluateTerms_cons (by rfl)
        (evaluateTerms_cons (by rfl) (evaluateTerms_nil _ _ _)))
  · change calls.evaluate world
      Number.Functions.scanNumberFunction.id (Model.argumentValues source start) = _
    exact contract.scanNumber start startInBounds startBound

theorem classTest_evaluates
    (classCode : classifyStartCode first = actual)
    (found : verifiedFrontendCore.constant? constant = some {
      id := constant
      type := Commands.i32Type
      value := .signed .i32 (Int.ofNat expected)
    }) :
    Term.evaluate (termMachine calls) world
        (dispatchEnvironment source start first)
        (Commands.comparison .equal (Commands.slot 4)
          (Commands.constant constant)) =
      .ok (.boolean (decide (actual = expected)), world) := by
  apply equal_evaluates (leftValue := actual) (rightValue := expected)
  · change Except.ok (Value.signed .i32 (Int.ofNat (classifyStartCode first)),
      world) = _
    rw [classCode]
  · exact constant_evaluates _ constant expected found

theorem scanEndScanner_evaluates
    (scanner : Function) (scan : ScanEnd)
    (evaluated : calls.evaluate world scanner.id
      (Model.argumentValues source start) =
        .ok (Model.encodedScanEnd scan, world)) :
    Term.evaluate (termMachine calls) world
        (dispatchEnvironment source start first)
        (Commands.call scanner
          [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
      .ok (Model.encodedScanEnd scan, world) := by
  unfold Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons (by rfl)
      (evaluateTerms_cons (by rfl)
        (evaluateTerms_cons (by rfl) (evaluateTerms_nil _ _ _)))
  · change calls.evaluate world scanner.id
      (Model.argumentValues source start) = _
    exact evaluated

theorem scanSucceeded_evaluates
    (contract : HelperContract calls source world)
    (environment : Env arity) (term : Term signature arity) (result : ScanEnd)
    (termResult : Term.evaluate (termMachine calls) world
      environment term = .ok (Model.encodedScanEnd result,
        world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.scanSucceeded term) =
      .ok (.boolean (match result with
        | .success _ => true
        | .failure _ => false), world) := by
  unfold Commands.scanSucceeded Commands.call
  apply Term.evaluate_apply1 termResult
  change calls.evaluate world
    Lexer.Functions.scanSucceededFunction.id [Model.encodedScanEnd result] = _
  cases result <;> exact contract.scanSucceeded _

theorem logicalNot_evaluates
    (environment : Env arity) (term : Term signature arity) (value : Bool)
    (termResult : Term.evaluate (termMachine calls) world environment term =
      .ok (.boolean value, world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.logicalNot term) = .ok (.boolean (!value), world) := by
  unfold Commands.logicalNot
  apply Term.evaluate_apply1 termResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.unary .logicalNot Commands.boolType Commands.boolType)
      [.boolean value] = _
  simp [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    Lanius.Semantics.evalUnaryValue]
  rfl

theorem scanEndOffset_evaluates
    (contract : HelperContract calls source world) (environment : Env arity)
    (term : Term signature arity) (finish : Nat)
    (termResult : Term.evaluate (termMachine calls) world
      environment term = .ok (Model.encodedScanEnd (.success finish),
        world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.scanEndOffset term) =
      .ok (.signed .i32 (Int.ofNat finish), world) := by
  unfold Commands.scanEndOffset Commands.call
  apply Term.evaluate_apply1 termResult
  change calls.evaluate world
    Lexer.Functions.scanEndOffsetFunction.id
      [Model.encodedScanEnd (.success finish)] = _
  exact contract.scanEndOffset finish

theorem scanErrorOffset_evaluates
    (contract : HelperContract calls source world) (environment : Env arity)
    (term : Term signature arity) (error : Nat)
    (termResult : Term.evaluate (termMachine calls) world
      environment term = .ok (Model.encodedScanEnd (.failure error),
        world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.scanErrorOffset term) =
      .ok (.signed .i32 (Int.ofNat error), world) := by
  unfold Commands.scanErrorOffset Commands.call
  apply Term.evaluate_apply1 termResult
  change calls.evaluate world
    Lexer.Functions.scanErrorOffsetFunction.id
      [Model.encodedScanEnd (.failure error)] = _
  exact contract.scanErrorOffset error

theorem delimitedBranch_run
    (contract : HelperContract calls source world) (scanner : Function)
    (kind : Lanius.Compiler.TokenKind) (kindConstant : ConstantId)
    (scan : ScanEnd)
    (scannerResult : Term.evaluate (termMachine calls) world
      environment (Commands.call scanner
        [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
      .ok (Model.encodedScanEnd scan, world))
    (kindResult : Term.evaluate (termMachine calls) world
      (environment.push (Model.encodedScanEnd scan))
      (Commands.constant kindConstant) =
      .ok (.signed .i32 (Int.ofNat kind.gpuCode), world)) :
    Stateful.Acyclic.run? (termMachine calls) (commandMachine calls)
        world environment
        (Commands.delimitedBranch scanner kindConstant) =
      some (.returned (some (Model.encodedDelimited kind scan)),
        world, environment) := by
  cases scan with
  | failure error =>
      have scanSlot : Term.evaluate (termMachine calls) world
          (environment.push (Model.encodedScanEnd (.failure error)))
          (Commands.slot (5 : Fin 6)) =
        .ok (Model.encodedScanEnd (.failure error), world) := by
        rfl
      have succeeded := scanSucceeded_evaluates contract _ _ (.failure error)
        scanSlot
      have condition : Term.evaluate (termMachine calls) world
          (environment.push (Model.encodedScanEnd (.failure error)))
          (Commands.logicalNot (Commands.scanSucceeded
            (Commands.slot (5 : Fin 6)))) =
        .ok (.boolean true, world) := by
        simpa using logicalNot_evaluates _ _ false succeeded
      have errorOffset := scanErrorOffset_evaluates contract _ _ error scanSlot
      have failedResult := failed_evaluates contract _
        (Commands.scanErrorOffset (Commands.slot (5 : Fin 6))) error errorOffset
      have failureRun := returned_run
        (Commands.failed (Commands.scanErrorOffset (Commands.slot (5 : Fin 6))))
        (Model.encoded (.failure error)) failedResult
      unfold Commands.delimitedBranch
      simp only [Stateful.Acyclic.run?]
      rw [scannerResult]
      simp only [bind, Except.bind]
      rw [condition]
      simp only [bind, Except.bind]
      rw [failureRun]
      simp only [bind, Except.bind]
      simp [Model.encoded, Model.encodedDelimited]
      rfl

  | success finish =>
      have scanSlot : Term.evaluate (termMachine calls) world
          (environment.push (Model.encodedScanEnd (.success finish)))
          (Commands.slot (5 : Fin 6)) =
        .ok (Model.encodedScanEnd (.success finish), world) := by
        rfl
      have succeeded := scanSucceeded_evaluates contract _ _ (.success finish)
        scanSlot
      have condition : Term.evaluate (termMachine calls) world
          (environment.push (Model.encodedScanEnd (.success finish)))
          (Commands.logicalNot (Commands.scanSucceeded
            (Commands.slot (5 : Fin 6)))) =
        .ok (.boolean false, world) := by
        simpa using logicalNot_evaluates _ _ true succeeded
      have endOffset := scanEndOffset_evaluates contract _ _ finish scanSlot
      have resultTerm := successful_evaluates contract _
        (Commands.constant kindConstant)
        (Commands.scanEndOffset (Commands.slot (5 : Fin 6)))
        kind finish kindResult endOffset
      have successRun := returned_run
        (Commands.successful (Commands.constant kindConstant)
          (Commands.scanEndOffset (Commands.slot (5 : Fin 6))))
        (Model.encoded (.token ⟨kind, 0, finish⟩)) resultTerm
      unfold Commands.delimitedBranch
      simp only [Stateful.Acyclic.run?]
      rw [scannerResult]
      simp only [bind, Except.bind]
      rw [condition]
      simp only [bind, Except.bind]
      rw [successRun]
      simp only [bind, Except.bind]
      simp [Model.encoded, Model.encodedDelimited]
      rfl

theorem symbolRule_exists (byte : Byte)
    (symbol : isSymbolStart byte = true) :
    ∃ rule, rule ∈ symbolRules ∧ rule.spelling = [byte.val] := by
  have exhaustive : ∀ candidate : Fin 256,
      symbolBytes.contains candidate.val = true →
      ∃ rule, rule ∈ symbolRules ∧ rule.spelling = [candidate.val] := by
    native_decide
  exact exhaustive byte symbol

theorem matchSymbolHead_exists
    (source : List Byte) (start : Nat)
    (startInBounds : start < source.length)
    (symbol : isSymbolStart source[start] = true) :
    ∃ rule, matchSymbolHead (source.drop start) = some rule := by
  obtain ⟨candidate, member, spelling⟩ := symbolRule_exists source[start] symbol
  unfold matchSymbolHead
  apply bestMatching_exists_of_match (candidate := candidate) member
  unfold SymbolRule.matches
  rw [List.drop_eq_getElem_cons startInBounds, List.map_cons, spelling]
  simp [startsWith]

def symbolMatchEnvironment (source : List Byte) (start : Nat) (first : Byte)
    (rule : SymbolRule) : Env 6 :=
  (dispatchEnvironment source start first).push
    (Symbol.Semantics.value (Int.ofNat rule.kind.gpuCode)
      (Int.ofNat rule.spelling.length))

def symbolKindEnvironment (source : List Byte) (start : Nat) (first : Byte)
    (rule : SymbolRule) : Env 7 :=
  (symbolMatchEnvironment source start first rule).push
    (.signed .i32 (Int.ofNat rule.kind.gpuCode))

theorem matchSymbol_evaluates
    (contract : HelperContract calls source world)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647)
    (matched : matchSymbolHead (source.drop start) = some rule) :
    Term.evaluate (termMachine calls) world
        (dispatchEnvironment source start first)
        (Commands.call Symbol.Functions.matchSymbolHeadFunction
          [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
      .ok (Symbol.Semantics.value (Int.ofNat rule.kind.gpuCode)
        (Int.ofNat rule.spelling.length), world) := by
  unfold Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons (by rfl)
      (evaluateTerms_cons (by rfl)
        (evaluateTerms_cons (by rfl) (evaluateTerms_nil _ _ _)))
  · change calls.evaluate world
      Symbol.Functions.matchSymbolHeadFunction.id
      (Model.argumentValues source start) = _
    exact contract.matchSymbolHead start rule startInBounds startBound matched

theorem tokenMatchKind_evaluates
    (contract : HelperContract calls source world) (rule : SymbolRule) :
    Term.evaluate (termMachine calls) world
        (symbolMatchEnvironment source start first rule)
        (Commands.call Symbol.Functions.tokenMatchKindFunction
          [Commands.slot 5]) =
      .ok (.signed .i32 (Int.ofNat rule.kind.gpuCode),
        world) := by
  unfold Commands.call
  apply Term.evaluate_apply1 (by rfl)
  change calls.evaluate world
    Symbol.Functions.tokenMatchKindFunction.id
    [Symbol.Semantics.value rule.kind.gpuCode rule.spelling.length] = _
  exact contract.tokenMatchKind rule.kind.gpuCode rule.spelling.length

theorem tokenMatchLength_evaluates
    (contract : HelperContract calls source world) (rule : SymbolRule) :
    Term.evaluate (termMachine calls) world
        (symbolKindEnvironment source start first rule)
        (Commands.call Symbol.Functions.tokenMatchLengthFunction
          [Commands.slot 5]) =
      .ok (.signed .i32 (Int.ofNat rule.spelling.length),
        world) := by
  unfold Commands.call
  apply Term.evaluate_apply1 (by rfl)
  change calls.evaluate world
    Symbol.Functions.tokenMatchLengthFunction.id
    [Symbol.Semantics.value rule.kind.gpuCode rule.spelling.length] = _
  exact contract.tokenMatchLength rule.kind.gpuCode rule.spelling.length

theorem add_evaluates
    (left right : Term signature arity) (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine calls) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (termMachine calls) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world))
    (bounded : leftValue + rightValue ≤ 2147483647) :
    Term.evaluate (termMachine calls) world environment
        (Commands.add left right) =
      .ok (.signed .i32 (Int.ofNat (leftValue + rightValue)), world) := by
  unfold Commands.add Commands.binary
  apply Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.binary .add Commands.i32Type Commands.i32Type Commands.i32Type)
      [.signed .i32 (Int.ofNat leftValue),
        .signed .i32 (Int.ofNat rightValue)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_add
    leftValue rightValue bounded

theorem less_evaluates
    (left right : Term signature arity) (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine calls) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (termMachine calls) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.comparison .less left right) =
      .ok (.boolean (decide (leftValue < rightValue)), world) := by
  unfold Commands.comparison Commands.binary
  apply Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.binary .less Commands.i32Type Commands.i32Type Commands.boolType)
      [.signed .i32 (Int.ofNat leftValue),
        .signed .i32 (Int.ofNat rightValue)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_less
    leftValue rightValue

theorem symbolCondition_evaluates
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start < source.length) :
    Term.evaluate (termMachine calls) world
        (dispatchEnvironment source start first)
        ((Commands.comparison .equal (Commands.slot 3) (Commands.i32 46)).logicalAnd
          (Commands.comparison .less
            (Commands.add (Commands.slot 2) (Commands.i32 1))
            (Commands.slot 1))) =
      .ok (.boolean ((decide (first.val = 46)) &&
        decide (start + 1 < source.length)), world) := by
  have byteTest := equal_evaluates (calls := calls)
    (world := world)
    (environment := dispatchEnvironment source start first)
    (Commands.slot 3) (Commands.i32 46) first.val 46 (by rfl) (by rfl)
  have addResult := add_evaluates (calls := calls)
    (world := world)
    (environment := dispatchEnvironment source start first)
    (Commands.slot 2) (Commands.i32 1) start 1 (by rfl) (by rfl)
    (by omega)
  have boundsTest := less_evaluates (calls := calls)
    (world := world)
    (environment := dispatchEnvironment source start first)
    (Commands.add (Commands.slot 2) (Commands.i32 1)) (Commands.slot 1)
    (start + 1) source.length addResult (by rfl)
  by_cases dot : first.val = 46
  · simp only [dot, decide_true, true_and]
    apply Term.evaluate_logicalAnd_true
    · simpa [dot] using byteTest
    · exact boundsTest
  · simp only [dot, decide_false, false_and]
    apply Term.evaluate_logicalAnd_false
    simpa [dot] using byteTest

theorem nextIndex_evaluates
    (sourceBound : source.length ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (nextInBounds : start + 1 < source.length) :
    Term.evaluate (termMachine calls) world
        (dispatchEnvironment source start first)
        (Commands.index (Commands.slot 0)
          (Commands.add (Commands.slot 2) (Commands.i32 1))) =
      .ok (.signed .i32 (Int.ofNat source[start + 1].val),
        world) := by
  have addResult := add_evaluates (calls := calls)
    (world := world)
    (environment := dispatchEnvironment source start first)
    (Commands.slot 2) (Commands.i32 1) start 1 (by rfl) (by rfl) (by omega)
  unfold Commands.index
  apply Term.evaluate_apply2 (by rfl) addResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.index Commands.sliceType Commands.i32Type Commands.i32Type)
      [Model.sourceSlice source, .signed .i32 (Int.ofNat (start + 1))] = _
  have raw := Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_index
    (program := verifiedFrontendCore) (baseType := Commands.sliceType)
    (indexType := Commands.i32Type) (elementType := Commands.i32Type)
    (found := sourceFound)
    (inBounds := by simpa using nextInBounds)
  rw [Model.sourceIntegers_get source (start + 1) nextInBounds] at raw
  rw [Model.sourceIntegers_length] at raw
  exact raw

theorem decimalDigit_evaluates
    (contract : HelperContract calls source world) (environment : Env arity)
    (term : Term signature arity) (byte : Byte)
    (termResult : Term.evaluate (termMachine calls) world
      environment term = .ok (.signed .i32 (Int.ofNat byte.val),
        world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.call Lexer.Functions.isDecimalDigitFunction [term]) =
      .ok (.boolean (isDecimalDigit byte), world) := by
  unfold Commands.call
  apply Term.evaluate_apply1 termResult
  exact contract.isDecimalDigit byte

theorem leadingDotNumber_evaluates
    (contract : HelperContract calls source world)
    (environment : Env arity) (sourceTerm boundTerm startTerm : Term signature arity)
    (start : Nat)
    (nextInBounds : start + 1 < source.length)
    (startBound : start ≤ 2147483647)
    (sourceResult : Term.evaluate (termMachine calls) world
      environment sourceTerm = .ok (Model.sourceSlice source,
        world))
    (boundResult : Term.evaluate (termMachine calls) world
      environment boundTerm = .ok (.signed .i32 (Int.ofNat source.length),
        world))
    (startResult : Term.evaluate (termMachine calls) world
      environment startTerm = .ok (.signed .i32 (Int.ofNat start),
        world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.call Number.Functions.scanLeadingDotNumberFunction
          [sourceTerm, boundTerm, startTerm]) =
      .ok (Model.encodedNumber (scanLeadingDotNumber source start),
        world) := by
  unfold Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceResult
      (evaluateTerms_cons boundResult
        (evaluateTerms_cons startResult (evaluateTerms_nil _ _ _)))
  · change calls.evaluate world
      Number.Functions.scanLeadingDotNumberFunction.id
      (Model.argumentValues source start) = _
    exact contract.scanLeadingDotNumber start nextInBounds startBound

theorem scanEndCall_evaluates
    (environment : Env arity) (scanner : Function)
    (sourceTerm boundTerm startTerm : Term signature arity) (start : Nat)
    (scan : ScanEnd)
    (sourceResult : Term.evaluate (termMachine calls) world
      environment sourceTerm = .ok (Model.sourceSlice source,
        world))
    (boundResult : Term.evaluate (termMachine calls) world
      environment boundTerm = .ok (.signed .i32 (Int.ofNat source.length),
        world))
    (startResult : Term.evaluate (termMachine calls) world
      environment startTerm = .ok (.signed .i32 (Int.ofNat start),
        world))
    (callResult : calls.evaluate world scanner.id
      (Model.argumentValues source start) =
        .ok (Model.encodedScanEnd scan, world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.call scanner [sourceTerm, boundTerm, startTerm]) =
      .ok (Model.encodedScanEnd scan, world) := by
  unfold Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceResult
      (evaluateTerms_cons boundResult
        (evaluateTerms_cons startResult (evaluateTerms_nil _ _ _)))
  · change calls.evaluate world scanner.id
      (Model.argumentValues source start) = _
    exact callResult

theorem startsWith_length_le
    (expected actual : List Nat) (accepted : startsWith expected actual = true) :
    expected.length ≤ actual.length := by
  induction expected generalizing actual with
  | nil => simp
  | cons head tail inductionHypothesis =>
      cases actual with
      | nil => simp [startsWith] at accepted
      | cons actualHead actualTail =>
          simp only [startsWith, Bool.and_eq_true] at accepted
          simp only [List.length_cons, Nat.succ_le_succ_iff]
          exact inductionHypothesis actualTail accepted.2

theorem commentRule_spelling_length
    (rule : SymbolRule) (member : rule ∈ symbolRules)
    (comment : rule.kind = Lanius.Compiler.TokenKind.lineComment ∨
      rule.kind = Lanius.Compiler.TokenKind.blockComment) :
    rule.spelling.length = 2 := by
  rcases comment with line | block
  · cases rule with
    | mk spelling kind =>
        simp only at line
        subst kind
        simp [symbolRules] at member
        simp [member]
  · cases rule with
    | mk spelling kind =>
        simp only at block
        subst kind
        simp [symbolRules] at member
        simp [member]

theorem blockCommentBranch_run
    (contract : HelperContract calls source world) (rule : SymbolRule)
    (openingInBounds : start + 1 < source.length)
    (startBound : start ≤ 2147483647)
    (block : rule.kind = Lanius.Compiler.TokenKind.blockComment) :
    Stateful.Acyclic.run? (termMachine calls) (commandMachine calls)
        world (symbolKindEnvironment source start first rule)
        Commands.blockCommentBranch =
      some (.returned (some (Model.encodedDelimited rule.kind
          (scanBlockCommentEnd source start))), world,
        symbolKindEnvironment source start first rule) := by
  let scan := scanBlockCommentEnd source start
  have scannerResult : Term.evaluate (termMachine calls)
      world (symbolKindEnvironment source start first rule)
      (Commands.call Lexer.Scanners.scanBlockCommentEndFunction
        [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
    .ok (Model.encodedScanEnd scan, world) := by
    exact scanEndCall_evaluates _ Lexer.Scanners.scanBlockCommentEndFunction
      _ _ _ start scan (by rfl) (by rfl) (by rfl)
      (contract.scanBlockCommentEnd start openingInBounds startBound)
  cases scanResult : scan with
  | failure error =>
      have scanSlot : Term.evaluate (termMachine calls) world
          ((symbolKindEnvironment source start first rule).push
            (Model.encodedScanEnd (.failure error))) (Commands.slot (7 : Fin 8)) =
        .ok (Model.encodedScanEnd (.failure error), world) := by
        rfl
      have succeeded := scanSucceeded_evaluates contract _ _ (.failure error)
        scanSlot
      have condition : Term.evaluate (termMachine calls) world
          ((symbolKindEnvironment source start first rule).push
            (Model.encodedScanEnd (.failure error)))
          (Commands.logicalNot (Commands.scanSucceeded
            (Commands.slot (7 : Fin 8)))) =
        .ok (.boolean true, world) := by
        simpa using logicalNot_evaluates _ _ false succeeded
      have errorOffset := scanErrorOffset_evaluates contract _ _ error scanSlot
      have failedResult := failed_evaluates contract _
        (Commands.scanErrorOffset (Commands.slot (7 : Fin 8))) error errorOffset
      have failureRun := returned_run
        (Commands.failed (Commands.scanErrorOffset (Commands.slot (7 : Fin 8))))
        (Model.encoded (.failure error)) failedResult
      unfold Commands.blockCommentBranch
      simp only [Stateful.Acyclic.run?]
      rw [scannerResult]
      simp only [bind, Except.bind]
      rw [scanResult]
      rw [condition]
      simp only [bind, Except.bind]
      rw [failureRun]
      simp only [bind, Except.bind]
      simp [scanResult, Model.encoded, Model.encodedDelimited]
      rw [show scanBlockCommentEnd source start = .failure error by
        simpa [scan] using scanResult]
      rfl
  | success finish =>
      have scanSlot : Term.evaluate (termMachine calls) world
          ((symbolKindEnvironment source start first rule).push
            (Model.encodedScanEnd (.success finish))) (Commands.slot (7 : Fin 8)) =
        .ok (Model.encodedScanEnd (.success finish), world) := by
        rfl
      have succeeded := scanSucceeded_evaluates contract _ _ (.success finish)
        scanSlot
      have condition : Term.evaluate (termMachine calls) world
          ((symbolKindEnvironment source start first rule).push
            (Model.encodedScanEnd (.success finish)))
          (Commands.logicalNot (Commands.scanSucceeded
            (Commands.slot (7 : Fin 8)))) =
        .ok (.boolean false, world) := by
        simpa using logicalNot_evaluates _ _ true succeeded
      have endOffset := scanEndOffset_evaluates contract _ _ finish scanSlot
      have tokenResult := successful_evaluates contract _
        (Commands.slot 6) (Commands.scanEndOffset (Commands.slot (7 : Fin 8)))
        rule.kind finish (by rfl) endOffset
      have successRun := returned_run
        (Commands.successful (Commands.slot 6)
          (Commands.scanEndOffset (Commands.slot (7 : Fin 8))))
        (Model.encoded (.token ⟨rule.kind, 0, finish⟩)) tokenResult
      unfold Commands.blockCommentBranch
      simp only [Stateful.Acyclic.run?]
      rw [scannerResult]
      simp only [bind, Except.bind]
      rw [scanResult]
      rw [condition]
      simp only [bind, Except.bind]
      rw [successRun]
      simp only [bind, Except.bind]
      simp [scanResult, Model.encoded, Model.encodedDelimited]
      rw [show scanBlockCommentEnd source start = .success finish by
        simpa [scan] using scanResult]
      rfl

theorem symbolTail_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (matched : matchSymbolHead (source.drop start) = some rule) :
    Stateful.Acyclic.run? (termMachine calls) (commandMachine calls)
        world (dispatchEnvironment source start first)
        Commands.symbolTail =
      some (.returned (some (Model.encoded
        (scanFixedSymbol source start))), world,
        dispatchEnvironment source start first) := by
  have startBound : start ≤ 2147483647 := by omega
  have matchResult := matchSymbol_evaluates contract (first := first)
    startInBounds startBound matched
  have kindResult := tokenMatchKind_evaluates contract
    (start := start) (first := first) rule
  have selected := matchSymbolHead_spec matched
  have spellingFits : rule.spelling.length ≤ (source.drop start).length := by
    have raw := startsWith_length_le rule.spelling
      ((source.drop start).map Fin.val) selected.2.1
    simpa using raw
  by_cases line : rule.kind = Lanius.Compiler.TokenKind.lineComment
  · have kindCode : rule.kind.gpuCode = 10 := by
      rw [line]
      rfl
    have openingInBounds : start + 1 < source.length := by
      have ruleLength := commentRule_spelling_length rule selected.1 (Or.inl line)
      simp [ruleLength, List.length_drop] at spellingFits
      omega
    have lineTest : Term.evaluate (termMachine calls) world
        (symbolKindEnvironment source start first rule)
        (Commands.comparison .equal (Commands.slot 6) (Commands.constant 16)) =
      .ok (.boolean true, world) := by
      apply equal_evaluates (leftValue := 10) (rightValue := 10)
      · change Except.ok (Value.signed .i32 (Int.ofNat rule.kind.gpuCode),
          world) = _
        rw [kindCode]
        rfl
      · exact constant_evaluates _ 16 10 (by rfl)
    have finishResult : Term.evaluate (termMachine calls)
        world (symbolKindEnvironment source start first rule)
        (Commands.call Lexer.Scanners.scanLineCommentEndFunction
          [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
      .ok (.signed .i32 (Int.ofNat (scanLineCommentEnd source start)),
        world) := by
      exact scanner_evaluates _ Lexer.Scanners.scanLineCommentEndFunction
        _ _ _ start (scanLineCommentEnd source start) (by rfl) (by rfl) (by rfl)
        (contract.scanLineCommentEnd start openingInBounds startBound)
    have tokenResult := successful_evaluates contract _
      (Commands.slot 6)
      (Commands.call Lexer.Scanners.scanLineCommentEndFunction
        [Commands.slot 0, Commands.slot 1, Commands.slot 2])
      rule.kind (scanLineCommentEnd source start) (by rfl) finishResult
    have lineRun := returned_run
      (Commands.successful (Commands.slot 6)
        (Commands.call Lexer.Scanners.scanLineCommentEndFunction
          [Commands.slot 0, Commands.slot 1, Commands.slot 2]))
      (Model.encoded (.token ⟨rule.kind, 0, scanLineCommentEnd source start⟩))
      tokenResult
    unfold symbolMatchEnvironment at kindResult
    unfold symbolKindEnvironment symbolMatchEnvironment at lineTest finishResult lineRun
    unfold Commands.symbolTail
    simp only [Stateful.Acyclic.run?]
    rw [matchResult]
    simp only [bind, Except.bind]
    rw [kindResult]
    simp only [bind, Except.bind]
    rw [lineTest]
    simp only [bind, Except.bind]
    rw [lineRun]
    simp only [bind, Except.bind]
    have logical : scanFixedSymbol source start =
        .token ⟨rule.kind, start, scanLineCommentEnd source start⟩ := by
      simp [scanFixedSymbol, matched, line]
    rw [logical]
    simp [Model.encoded]
    rfl
  · by_cases block : rule.kind = Lanius.Compiler.TokenKind.blockComment
    · have lineCodeNe : rule.kind.gpuCode ≠ 10 := by
        intro same
        apply line
        exact Lanius.Compiler.TokenKind.gpuCode_injective (same.trans (by rfl :
          10 = Lanius.Compiler.TokenKind.lineComment.gpuCode))
      have blockCode : rule.kind.gpuCode = 11 := by
        rw [block]
        rfl
      have openingInBounds : start + 1 < source.length := by
        have ruleLength := commentRule_spelling_length rule selected.1 (Or.inr block)
        simp [ruleLength, List.length_drop] at spellingFits
        omega
      have lineTest : Term.evaluate (termMachine calls) world
          (symbolKindEnvironment source start first rule)
          (Commands.comparison .equal (Commands.slot 6) (Commands.constant 16)) =
        .ok (.boolean false, world) := by
        have evaluated := equal_evaluates (calls := calls)
          (world := world)
          (environment := symbolKindEnvironment source start first rule)
          (Commands.slot 6) (Commands.constant 16) rule.kind.gpuCode 10
          (by rfl) (constant_evaluates _ 16 10 (by rfl))
        simpa [lineCodeNe] using evaluated
      have blockTest : Term.evaluate (termMachine calls) world
          (symbolKindEnvironment source start first rule)
          (Commands.comparison .equal (Commands.slot 6) (Commands.constant 17)) =
        .ok (.boolean true, world) := by
        apply equal_evaluates (leftValue := 11) (rightValue := 11)
        · change Except.ok (Value.signed .i32
            (Int.ofNat rule.kind.gpuCode), world) = _
          rw [blockCode]
          rfl
        · exact constant_evaluates _ 17 11 (by rfl)
      have branchRun := blockCommentBranch_run contract rule openingInBounds
        startBound block (start := start) (first := first)
      unfold symbolMatchEnvironment at kindResult
      unfold symbolKindEnvironment symbolMatchEnvironment at lineTest blockTest branchRun
      unfold Commands.symbolTail
      simp only [Stateful.Acyclic.run?]
      rw [matchResult]
      simp only [bind, Except.bind]
      rw [kindResult]
      simp only [bind, Except.bind]
      rw [lineTest]
      simp only [bind, Except.bind]
      rw [blockTest]
      simp only [bind, Except.bind]
      rw [branchRun]
      simp only [bind, Except.bind]
      have logical : scanFixedSymbol source start = tokenFromDelimited rule.kind start
          (scanBlockCommentEnd source start) := by
        simp [scanFixedSymbol, matched, line, block]
      rw [logical, Model.encoded_tokenFromDelimited]
      simp
      rfl
    · have lineCodeNe : rule.kind.gpuCode ≠ 10 := by
        intro same
        apply line
        exact Lanius.Compiler.TokenKind.gpuCode_injective (same.trans (by rfl : 10 =
          Lanius.Compiler.TokenKind.lineComment.gpuCode))
      have blockCodeNe : rule.kind.gpuCode ≠ 11 := by
        intro same
        apply block
        exact Lanius.Compiler.TokenKind.gpuCode_injective (same.trans (by rfl : 11 =
          Lanius.Compiler.TokenKind.blockComment.gpuCode))
      have lineTest : Term.evaluate (termMachine calls) world
          (symbolKindEnvironment source start first rule)
          (Commands.comparison .equal (Commands.slot 6) (Commands.constant 16)) =
        .ok (.boolean false, world) := by
        have evaluated := equal_evaluates (calls := calls)
          (world := world)
          (environment := symbolKindEnvironment source start first rule)
          (Commands.slot 6) (Commands.constant 16) rule.kind.gpuCode 10
          (by rfl) (constant_evaluates _ 16 10 (by rfl))
        simpa [lineCodeNe] using evaluated
      have blockTest : Term.evaluate (termMachine calls) world
          (symbolKindEnvironment source start first rule)
          (Commands.comparison .equal (Commands.slot 6) (Commands.constant 17)) =
        .ok (.boolean false, world) := by
        have evaluated := equal_evaluates (calls := calls)
          (world := world)
          (environment := symbolKindEnvironment source start first rule)
          (Commands.slot 6) (Commands.constant 17) rule.kind.gpuCode 11
          (by rfl) (constant_evaluates _ 17 11 (by rfl))
        simpa [blockCodeNe] using evaluated
      have lengthResult := tokenMatchLength_evaluates contract
        (start := start) (first := first) rule
      have selected := (matchSymbolHead_spec matched).2.1
      unfold SymbolRule.matches at selected
      have lengthLeDrop := startsWith_length_le rule.spelling
        ((source.drop start).map Fin.val) selected
      have finishLeSource : start + rule.spelling.length ≤ source.length := by
        simp only [List.length_map, List.length_drop] at lengthLeDrop
        omega
      have finishBound : start + rule.spelling.length ≤ 2147483647 :=
        Nat.le_trans finishLeSource sourceBound
      have finishResult := add_evaluates (calls := calls)
        (world := world)
        (environment := symbolKindEnvironment source start first rule)
        (Commands.slot 2)
        (Commands.call Symbol.Functions.tokenMatchLengthFunction
          [Commands.slot 5]) start rule.spelling.length
        (by rfl) lengthResult finishBound
      have tokenResult := successful_evaluates contract _
        (Commands.slot 6)
        (Commands.add (Commands.slot 2)
          (Commands.call Symbol.Functions.tokenMatchLengthFunction
            [Commands.slot 5]))
        rule.kind (start + rule.spelling.length) (by rfl) finishResult
      have normalRun := returned_run
        (Commands.successful (Commands.slot 6)
          (Commands.add (Commands.slot 2)
            (Commands.call Symbol.Functions.tokenMatchLengthFunction
              [Commands.slot 5])))
        (Model.encoded (.token ⟨rule.kind, 0,
          start + rule.spelling.length⟩)) tokenResult
      unfold symbolMatchEnvironment at kindResult
      unfold symbolKindEnvironment symbolMatchEnvironment at lineTest blockTest lengthResult finishResult normalRun
      unfold Commands.symbolTail
      simp only [Stateful.Acyclic.run?]
      rw [matchResult]
      simp only [bind, Except.bind]
      rw [kindResult]
      simp only [bind, Except.bind]
      rw [lineTest]
      simp only [bind, Except.bind]
      rw [blockTest]
      simp only [bind, Except.bind]
      rw [normalRun]
      simp only [bind, Except.bind]
      have logical : scanFixedSymbol source start =
          .token ⟨rule.kind, start, start + rule.spelling.length⟩ := by
        simp [scanFixedSymbol, matched, line, block]
      rw [logical]
      simp [Model.encoded]
      rfl

theorem symbolBranch_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (startInBounds : start < source.length)
    (symbolClass : classifyStart source[start] = .symbol) :
    Stateful.Acyclic.run? (termMachine calls) (commandMachine calls)
        world
        (dispatchEnvironment source start source[start]) Commands.symbolBranch =
      some (.returned (some (Model.encoded (scanSymbol source start))),
        world,
        dispatchEnvironment source start source[start]) := by
  have symbolStart : isSymbolStart source[start] = true :=
    ((classifyStart_spec source[start] .symbol).mp symbolClass).2.2.2.2.2
  obtain ⟨rule, matched⟩ := matchSymbolHead_exists source start
    startInBounds symbolStart
  have tailRun := symbolTail_run (first := source[start]) (rule := rule)
    contract sourceBound startInBounds matched
  have rawCondition := symbolCondition_evaluates (calls := calls)
    (world := world) (source := source) (start := start) (first := source[start])
    sourceBound startInBounds
  by_cases dot : source[start].val = 46
  · by_cases nextInBounds : start + 1 < source.length
    · have condition : Term.evaluate (termMachine calls)
          world
          (dispatchEnvironment source start source[start])
          ((Commands.comparison .equal (Commands.slot 3) (Commands.i32 46)).logicalAnd
            (Commands.comparison .less
              (Commands.add (Commands.slot 2) (Commands.i32 1))
              (Commands.slot 1))) =
        .ok (.boolean true, world) := by
        simpa [dot, nextInBounds] using rawCondition
      have nextResult := nextIndex_evaluates (calls := calls)
        (world := world) (source := source) (start := start)
        (first := source[start]) sourceBound sourceFound nextInBounds
      let nextEnvironment :=
        (dispatchEnvironment source start source[start]).push
          (.signed .i32 (Int.ofNat source[start + 1].val))
      have decimalResult := decimalDigit_evaluates contract
        nextEnvironment (Commands.slot (5 : Fin 6)) source[start + 1] (by rfl)
      by_cases decimal : isDecimalDigit source[start + 1] = true
      · have decimalTrue : Term.evaluate (termMachine calls)
            world nextEnvironment
            (Commands.call Lexer.Functions.isDecimalDigitFunction
              [Commands.slot (5 : Fin 6)]) =
          .ok (.boolean true, world) := by
          simpa [decimal] using decimalResult
        have numberResult := leadingDotNumber_evaluates contract
          nextEnvironment (Commands.slot 0) (Commands.slot 1) (Commands.slot 2)
          start nextInBounds (by omega) (by rfl) (by rfl) (by rfl)
        have numberRun := returned_run
          (Commands.call Number.Functions.scanLeadingDotNumberFunction
            [Commands.slot 0, Commands.slot 1, Commands.slot 2])
          (Model.encodedNumber (scanLeadingDotNumber source start)) numberResult
        unfold nextEnvironment at decimalTrue numberRun
        unfold Commands.symbolBranch Commands.dotNumberBranch Commands.statement
        simp only [Stateful.Acyclic.run?]
        rw [condition]
        simp only [bind, Except.bind]
        rw [nextResult]
        simp only [bind, Except.bind]
        rw [decimalTrue]
        simp only [bind, Except.bind]
        rw [numberRun]
        simp only [Env.pop_push, bind, Except.bind]
        have logical : scanSymbol source start =
            tokenFromNumber start (scanLeadingDotNumber source start) := by
          simp [scanSymbol, List.getElem?_eq_getElem startInBounds, dot,
            List.getElem?_eq_getElem nextInBounds, decimal]
        rw [logical, Model.encoded_tokenFromNumber]
        rfl
      · have decimalFalse : Term.evaluate (termMachine calls)
            world nextEnvironment
            (Commands.call Lexer.Functions.isDecimalDigitFunction
              [Commands.slot (5 : Fin 6)]) =
          .ok (.boolean false, world) := by
          simpa [decimal] using decimalResult
        unfold nextEnvironment at decimalFalse
        unfold Commands.symbolBranch Commands.dotNumberBranch Commands.statement
        simp only [Stateful.Acyclic.run?]
        rw [condition]
        simp only [bind, Except.bind]
        rw [nextResult]
        simp only [bind, Except.bind]
        rw [decimalFalse]
        simp only [Env.pop_push, bind, Except.bind]
        rw [tailRun]
        have logical : scanSymbol source start = scanFixedSymbol source start := by
          simp [scanSymbol, List.getElem?_eq_getElem startInBounds, dot,
            List.getElem?_eq_getElem nextInBounds, decimal]
        rw [logical]
    · have condition : Term.evaluate (termMachine calls)
          world
          (dispatchEnvironment source start source[start])
          ((Commands.comparison .equal (Commands.slot 3) (Commands.i32 46)).logicalAnd
            (Commands.comparison .less
              (Commands.add (Commands.slot 2) (Commands.i32 1))
              (Commands.slot 1))) =
        .ok (.boolean false, world) := by
        simpa [dot, nextInBounds] using rawCondition
      unfold Commands.symbolBranch
      simp only [Stateful.Acyclic.run?]
      rw [condition]
      simp only [bind, Except.bind]
      rw [tailRun]
      have nextMissing : source[start + 1]? = none := by
        exact List.getElem?_eq_none (by omega)
      have logical : scanSymbol source start = scanFixedSymbol source start := by
        simp [scanSymbol, List.getElem?_eq_getElem startInBounds, dot, nextMissing]
      rw [logical]
  · have condition : Term.evaluate (termMachine calls)
        world
        (dispatchEnvironment source start source[start])
        ((Commands.comparison .equal (Commands.slot 3) (Commands.i32 46)).logicalAnd
          (Commands.comparison .less
            (Commands.add (Commands.slot 2) (Commands.i32 1))
            (Commands.slot 1))) =
      .ok (.boolean false, world) := by
      simpa [dot] using rawCondition
    unfold Commands.symbolBranch
    simp only [Stateful.Acyclic.run?]
    rw [condition]
    simp only [bind, Except.bind]
    rw [tailRun]
    have logical : scanSymbol source start = scanFixedSymbol source start := by
      simp [scanSymbol, List.getElem?_eq_getElem startInBounds, dot]
    rw [logical]

theorem dispatch_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (startBound : start ≤ 2147483647)
    (startInBounds : start < source.length) :
    Stateful.Acyclic.run? (termMachine calls) (commandMachine calls)
        world
        (dispatchEnvironment source start source[start]) Commands.dispatch =
      some (.returned (some (Model.encoded
          (Lanius.Compiler.Lexer.scanOne source start))),
        world, dispatchEnvironment source start source[start]) := by
  cases startClass : classifyStart source[start] with
  | identifier =>
      have classCode : classifyStartCode source[start] = 1 := by
        simp [classifyStartCode, startClass, StartClass.code]
      have firstTest : Term.evaluate (termMachine calls)
          world (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4)
            (Commands.constant 0)) =
        .ok (.boolean true, world) := by
        apply equal_evaluates (leftValue := 1) (rightValue := 1)
        · change Except.ok (Value.signed .i32 (Int.ofNat
              (classifyStartCode source[start])), world) = _
          rw [classCode]
          rfl
        · exact constant_evaluates _ 0 1 (by rfl)
      have finishResult : Term.evaluate (termMachine calls)
          world (dispatchEnvironment source start source[start])
          (Commands.call Lexer.Scanners.scanIdentifierEndFunction
            [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
        .ok (.signed .i32 (Int.ofNat (scanIdentifierEnd source start)),
          world) := by
        exact identifierEnd_evaluates contract _ _ _ _ start
          startInBounds startBound (by rfl) (by rfl) (by rfl)
      have kindResult : Term.evaluate (termMachine calls)
          world (dispatchEnvironment source start source[start])
          (Commands.constant 7) =
        .ok (.signed .i32 (Int.ofNat
          Lanius.Compiler.TokenKind.identifier.gpuCode),
          world) := by
        exact constant_evaluates _ 7 1 (by rfl)
      have resultTerm := successful_evaluates contract
        (dispatchEnvironment source start source[start])
        (Commands.constant 7)
        (Commands.call Lexer.Scanners.scanIdentifierEndFunction
          [Commands.slot 0, Commands.slot 1, Commands.slot 2])
        Lanius.Compiler.TokenKind.identifier (scanIdentifierEnd source start)
        kindResult finishResult
      have branchRun := returned_run
        (Commands.successful (Commands.constant 7)
          (Commands.call Lexer.Scanners.scanIdentifierEndFunction
            [Commands.slot 0, Commands.slot 1, Commands.slot 2]))
        (Model.encoded (.token ⟨Lanius.Compiler.TokenKind.identifier, 0,
          scanIdentifierEnd source start⟩)) resultTerm
      unfold Commands.dispatch
      simp only [Stateful.Acyclic.run?]
      rw [firstTest]
      simp only [bind, Except.bind]
      rw [branchRun]
      have logical : Lanius.Compiler.Lexer.scanOne source start =
          .token ⟨Lanius.Compiler.TokenKind.identifier, start,
            scanIdentifierEnd source start⟩ := by
        simp [Lanius.Compiler.Lexer.scanOne, startInBounds, startClass]
      rw [logical]
      rfl
  | decimalNumber =>
      have classCode : classifyStartCode source[start] = 2 := by
        simp [classifyStartCode, startClass, StartClass.code]
      have test0 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 0)) =
        .ok (.boolean false, world) := by
        have evaluated := equal_evaluates (calls := calls)
          (world := world)
          (environment := dispatchEnvironment source start source[start])
          (Commands.slot 4) (Commands.constant 0) 2 1
          (by
            change Except.ok (Value.signed .i32 (Int.ofNat
              (classifyStartCode source[start])), world) = _
            rw [classCode]
            rfl)
          (constant_evaluates _ 0 1 (by rfl))
        simpa using evaluated
      have test1 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 1)) =
        .ok (.boolean true, world) := by
        have evaluated := equal_evaluates (calls := calls)
          (world := world)
          (environment := dispatchEnvironment source start source[start])
          (Commands.slot 4) (Commands.constant 1) 2 2
          (by
            change Except.ok (Value.signed .i32 (Int.ofNat
              (classifyStartCode source[start])), world) = _
            rw [classCode]
            rfl)
          (constant_evaluates _ 1 2 (by rfl))
        simpa using evaluated
      have numberResult := number_evaluates contract
        start source[start] startInBounds startBound
      have branchRun := returned_run
        (Commands.call Number.Functions.scanNumberFunction
          [Commands.slot 0, Commands.slot 1, Commands.slot 2])
        (Model.encodedNumber (scanNumber source start)) numberResult
      unfold Commands.dispatch
      simp only [Stateful.Acyclic.run?]
      rw [test0]
      simp only [bind, Except.bind]
      rw [test1]
      simp only [bind, Except.bind]
      rw [branchRun]
      have logical : Lanius.Compiler.Lexer.scanOne source start =
          tokenFromNumber start (scanNumber source start) := by
        simp [Lanius.Compiler.Lexer.scanOne, startInBounds, startClass]
      rw [logical, Model.encoded_tokenFromNumber]
      rfl
  | whitespace =>
      have classCode : classifyStartCode source[start] = 3 := by
        simp [classifyStartCode, startClass, StartClass.code]
      have test0 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 0)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 0) (expected := 1) (by rfl)
      have test1 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 1)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 1) (expected := 2) (by rfl)
      have test2 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 2)) =
        .ok (.boolean true, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 2) (expected := 3) (by rfl)
      have finishResult : Term.evaluate (termMachine calls)
          world (dispatchEnvironment source start source[start])
          (Commands.call Lexer.Scanners.scanWhitespaceEndFunction
            [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
        .ok (.signed .i32 (Int.ofNat (scanWhitespaceEnd source start)),
          world) := by
        exact whitespaceEnd_evaluates contract _ _ _ _ start
          startInBounds startBound (by rfl) (by rfl) (by rfl)
      have kindResult : Term.evaluate (termMachine calls)
          world (dispatchEnvironment source start source[start])
          (Commands.constant 9) =
        .ok (.signed .i32 (Int.ofNat
          Lanius.Compiler.TokenKind.whitespace.gpuCode),
          world) :=
        constant_evaluates _ 9 3 (by rfl)
      have resultTerm := successful_evaluates contract
        (dispatchEnvironment source start source[start])
        (Commands.constant 9)
        (Commands.call Lexer.Scanners.scanWhitespaceEndFunction
          [Commands.slot 0, Commands.slot 1, Commands.slot 2])
        Lanius.Compiler.TokenKind.whitespace (scanWhitespaceEnd source start)
        kindResult finishResult
      have branchRun := returned_run
        (Commands.successful (Commands.constant 9)
          (Commands.call Lexer.Scanners.scanWhitespaceEndFunction
            [Commands.slot 0, Commands.slot 1, Commands.slot 2]))
        (Model.encoded (.token ⟨Lanius.Compiler.TokenKind.whitespace, 0,
          scanWhitespaceEnd source start⟩)) resultTerm
      unfold Commands.dispatch
      simp only [Stateful.Acyclic.run?]
      rw [test0]
      simp only [bind, Except.bind]
      rw [test1]
      simp only [bind, Except.bind]
      rw [test2]
      simp only [bind, Except.bind]
      rw [branchRun]
      have logical : Lanius.Compiler.Lexer.scanOne source start =
          .token ⟨Lanius.Compiler.TokenKind.whitespace, start,
            scanWhitespaceEnd source start⟩ := by
        simp [Lanius.Compiler.Lexer.scanOne, startInBounds, startClass]
      rw [logical]
      rfl
  | symbol =>
      have classCode : classifyStartCode source[start] = 4 := by
        simp [classifyStartCode, startClass, StartClass.code]
      have test0 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 0)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 0) (expected := 1) (by rfl)
      have test1 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 1)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 1) (expected := 2) (by rfl)
      have test2 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 2)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 2) (expected := 3) (by rfl)
      have test4 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 4)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 4) (expected := 5) (by rfl)
      have test5 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 5)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 5) (expected := 6) (by rfl)
      have test3 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 3)) =
        .ok (.boolean true, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 3) (expected := 4) (by rfl)
      have branchRun := symbolBranch_run contract sourceBound sourceFound
        startInBounds startClass
      unfold Commands.dispatch
      simp only [Stateful.Acyclic.run?]
      rw [test0]
      simp only [bind, Except.bind]
      rw [test1]
      simp only [bind, Except.bind]
      rw [test2]
      simp only [bind, Except.bind]
      rw [test4]
      simp only [bind, Except.bind]
      rw [test5]
      simp only [bind, Except.bind]
      rw [test3]
      simp only [bind, Except.bind]
      rw [branchRun]
      have logical : Lanius.Compiler.Lexer.scanOne source start =
          scanSymbol source start := by
        simp [Lanius.Compiler.Lexer.scanOne, startInBounds, startClass]
      rw [logical]
      rfl
  | stringLiteral =>
      have classCode : classifyStartCode source[start] = 5 := by
        simp [classifyStartCode, startClass, StartClass.code]
      have test0 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 0)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 0) (expected := 1) (by rfl)
      have test1 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 1)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 1) (expected := 2) (by rfl)
      have test2 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 2)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 2) (expected := 3) (by rfl)
      have test4 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 4)) =
        .ok (.boolean true, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 4) (expected := 5) (by rfl)
      let scan := scanQuotedEnd source start doubleQuote
      have scannerResult : Term.evaluate (termMachine calls)
          world (dispatchEnvironment source start source[start])
          (Commands.call Lexer.Scanners.scanStringEndFunction
            [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
        .ok (Model.encodedScanEnd scan, world) := by
        exact scanEndScanner_evaluates Lexer.Scanners.scanStringEndFunction scan
          (contract.scanStringEnd start startInBounds startBound)
      have kindResult : Term.evaluate (termMachine calls)
          world
          ((dispatchEnvironment source start source[start]).push
            (Model.encodedScanEnd scan)) (Commands.constant 34) =
        .ok (.signed .i32 (Int.ofNat
          Lanius.Compiler.TokenKind.string.gpuCode), world) :=
        constant_evaluates _ 34 32 (by rfl)
      have branchRun := delimitedBranch_run contract
        Lexer.Scanners.scanStringEndFunction Lanius.Compiler.TokenKind.string 34
        scan scannerResult kindResult
      unfold Commands.dispatch
      simp only [Stateful.Acyclic.run?]
      rw [test0]
      simp only [bind, Except.bind]
      rw [test1]
      simp only [bind, Except.bind]
      rw [test2]
      simp only [bind, Except.bind]
      rw [test4]
      simp only [bind, Except.bind]
      rw [branchRun]
      have logical : Lanius.Compiler.Lexer.scanOne source start =
          tokenFromDelimited Lanius.Compiler.TokenKind.string start scan := by
        simp [Lanius.Compiler.Lexer.scanOne, startInBounds, startClass, scan]
      rw [logical, Model.encoded_tokenFromDelimited]
      rfl
  | characterLiteral =>
      have classCode : classifyStartCode source[start] = 6 := by
        simp [classifyStartCode, startClass, StartClass.code]
      have test0 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 0)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 0) (expected := 1) (by rfl)
      have test1 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 1)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 1) (expected := 2) (by rfl)
      have test2 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 2)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 2) (expected := 3) (by rfl)
      have test4 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 4)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 4) (expected := 5) (by rfl)
      have test5 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 5)) =
        .ok (.boolean true, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 5) (expected := 6) (by rfl)
      let scan := scanQuotedEnd source start singleQuote
      have scannerResult : Term.evaluate (termMachine calls)
          world (dispatchEnvironment source start source[start])
          (Commands.call Lexer.Scanners.scanCharacterEndFunction
            [Commands.slot 0, Commands.slot 1, Commands.slot 2]) =
        .ok (Model.encodedScanEnd scan, world) := by
        exact scanEndScanner_evaluates Lexer.Scanners.scanCharacterEndFunction scan
          (contract.scanCharacterEnd start startInBounds startBound)
      have kindResult : Term.evaluate (termMachine calls)
          world
          ((dispatchEnvironment source start source[start]).push
            (Model.encodedScanEnd scan)) (Commands.constant 36) =
        .ok (.signed .i32 (Int.ofNat
          Lanius.Compiler.TokenKind.character.gpuCode), world) :=
        constant_evaluates _ 36 34 (by rfl)
      have branchRun := delimitedBranch_run contract
        Lexer.Scanners.scanCharacterEndFunction
        Lanius.Compiler.TokenKind.character 36 scan scannerResult kindResult
      unfold Commands.dispatch
      simp only [Stateful.Acyclic.run?]
      rw [test0]
      simp only [bind, Except.bind]
      rw [test1]
      simp only [bind, Except.bind]
      rw [test2]
      simp only [bind, Except.bind]
      rw [test4]
      simp only [bind, Except.bind]
      rw [test5]
      simp only [bind, Except.bind]
      rw [branchRun]
      have logical : Lanius.Compiler.Lexer.scanOne source start =
          tokenFromDelimited Lanius.Compiler.TokenKind.character start scan := by
        simp [Lanius.Compiler.Lexer.scanOne, startInBounds, startClass, scan]
      rw [logical, Model.encoded_tokenFromDelimited]
      rfl
  | invalid =>
      have classCode : classifyStartCode source[start] = 7 := by
        simp [classifyStartCode, startClass, StartClass.code]
      have test0 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 0)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 0) (expected := 1) (by rfl)
      have test1 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 1)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 1) (expected := 2) (by rfl)
      have test2 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 2)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 2) (expected := 3) (by rfl)
      have test4 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 4)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 4) (expected := 5) (by rfl)
      have test5 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 5)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 5) (expected := 6) (by rfl)
      have test3 : Term.evaluate (termMachine calls) world
          (dispatchEnvironment source start source[start])
          (Commands.comparison .equal (Commands.slot 4) (Commands.constant 3)) =
        .ok (.boolean false, world) := by
        simpa using classTest_evaluates (calls := calls) (source := source)
          (start := start) classCode (constant := 3) (expected := 4) (by rfl)
      have resultTerm := failed_evaluates contract
        (dispatchEnvironment source start source[start]) (Commands.slot 2) start
        (by rfl)
      have branchRun := returned_run (Commands.failed (Commands.slot 2))
        (Model.encoded (.failure start)) resultTerm
      unfold Commands.dispatch
      simp only [Stateful.Acyclic.run?]
      rw [test0]
      simp only [bind, Except.bind]
      rw [test1]
      simp only [bind, Except.bind]
      rw [test2]
      simp only [bind, Except.bind]
      rw [test4]
      simp only [bind, Except.bind]
      rw [test5]
      simp only [bind, Except.bind]
      rw [test3]
      simp only [bind, Except.bind]
      rw [branchRun]
      have logical : Lanius.Compiler.Lexer.scanOne source start = .failure start := by
        simp [Lanius.Compiler.Lexer.scanOne, startInBounds, startClass]
      rw [logical]
      rfl

theorem scanOne_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (startBound : start ≤ 2147483647) :
    Stateful.Acyclic.run? (termMachine calls) (commandMachine calls)
        world (Model.environment source start)
        Commands.scanOne =
      some (.returned (some (Model.encoded
          (Lanius.Compiler.Lexer.scanOne source start))),
        world, Model.environment source start) := by
  have rawCondition := start_condition_evaluates (calls := calls)
    (world := world) (source := source) (start := start) sourceBound startBound
  by_cases startInBounds : start < source.length
  · have condition : Term.evaluate (termMachine calls)
        world (Model.environment source start)
        (Commands.comparison .greaterEqual (Commands.slot 2)
          (Commands.slot 1)) =
      .ok (.boolean false, world) := by
      simpa [show ¬ start ≥ source.length by omega] using rawCondition
    have firstResult := source_index_evaluates (calls := calls)
      (world := world) (source := source) (start := start)
      sourceFound startInBounds
    have classResult := classify_evaluates (start := start) contract source[start]
    have branchRun := dispatch_run contract sourceBound sourceFound startBound
      startInBounds
    unfold dispatchEnvironment at branchRun
    unfold Commands.scanOne
    simp only [Stateful.Acyclic.run?]
    rw [condition]
    simp only [bind, Except.bind]
    rw [firstResult]
    simp only [bind, Except.bind]
    rw [classResult]
    simp only [bind, Except.bind]
    rw [branchRun]
    simp only [Env.pop_push, bind, Except.bind]
    rfl
  · have condition : Term.evaluate (termMachine calls)
        world (Model.environment source start)
        (Commands.comparison .greaterEqual (Commands.slot 2)
          (Commands.slot 1)) =
      .ok (.boolean true, world) := by
      simpa [show start ≥ source.length by omega] using rawCondition
    have failedResult := failed_evaluates contract
      (Model.environment source start) (Commands.slot 2) start (by rfl)
    have failureRun := returned_run (Commands.failed (Commands.slot 2))
      (Model.encoded (.failure start)) failedResult
    unfold Commands.scanOne
    simp only [Stateful.Acyclic.run?]
    rw [condition]
    simp only [bind, Except.bind]
    rw [failureRun]
    have missing : source[start]? = none := List.getElem?_eq_none (by omega)
    have logical : Lanius.Compiler.Lexer.scanOne source start = .failure start := by
      simp [Lanius.Compiler.Lexer.scanOne, missing]
    rw [logical]
    rfl
