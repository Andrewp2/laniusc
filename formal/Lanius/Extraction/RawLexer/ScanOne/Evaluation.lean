import Lanius.Extraction.RawLexer.ScanOne.Commands
import Lanius.Extraction.RawLexer.ScanOne.Model
import Lanius.Extraction.Symbol.Value
import Lanius.FunctionalViewStatefulAcyclic

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

abbrev World := Lanius.FunctionalView.Core.ReadOnly.World

abbrev termMachine (calls : CallModel) : FunctionalView.Machine Core.signature :=
  Lanius.FunctionalView.Core.Stateful.termMachine
    (Effectful.evaluateOperation verifiedFrontendCore calls)

abbrev commandMachine (calls : CallModel) :=
  machineWith verifiedFrontendCore
    (Effectful.evaluateOperation verifiedFrontendCore calls)

structure HelperContract (calls : CallModel) (source : List Byte)
    (world : ReadOnly.World) : Prop where
  failed : ∀ offset : Nat,
    calls.evaluate world
        TokenScan.Functions.failedFunction.id [.signed .i32 offset] =
      .ok (Model.encoded (.failure offset), world)
  successful : ∀ (kind : Lanius.Compiler.TokenKind) (finish : Nat),
    calls.evaluate world
        TokenScan.Functions.successfulFunction.id
        [.signed .i32 (Lanius.Compiler.TokenKind.gpuCode kind),
          .signed .i32 finish] =
      .ok (TokenScan.Semantics.value true
          (Lanius.Compiler.TokenKind.gpuCode kind) finish 0,
        world)
  classifyStart : ∀ byte : Byte,
    calls.evaluate world
        Lexer.Functions.classifyStartFunction.id [.signed .i32 byte.val] =
      .ok (.signed .i32 (classifyStartCode byte), world)
  isDecimalDigit : ∀ byte : Byte,
    calls.evaluate world
        Lexer.Functions.isDecimalDigitFunction.id [.signed .i32 byte.val] =
      .ok (.boolean (Lanius.Compiler.Lexer.isDecimalDigit byte),
        world)
  scanIdentifierEnd : ∀ start : Nat, start < source.length →
    start ≤ 2147483647 →
    calls.evaluate world
        Lexer.Scanners.scanIdentifierEndFunction.id
        (Model.argumentValues source start) =
      .ok (.signed .i32 (Lanius.Compiler.Lexer.scanIdentifierEnd source start),
        world)
  scanWhitespaceEnd : ∀ start : Nat, start < source.length →
    start ≤ 2147483647 →
    calls.evaluate world
        Lexer.Scanners.scanWhitespaceEndFunction.id
        (Model.argumentValues source start) =
      .ok (.signed .i32 (Lanius.Compiler.Lexer.scanWhitespaceEnd source start),
        world)
  scanStringEnd : ∀ start : Nat, start < source.length →
    start ≤ 2147483647 →
    calls.evaluate world
        Lexer.Scanners.scanStringEndFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encodedScanEnd
        (scanQuotedEnd source start doubleQuote), world)
  scanCharacterEnd : ∀ start : Nat, start < source.length →
    start ≤ 2147483647 →
    calls.evaluate world
        Lexer.Scanners.scanCharacterEndFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encodedScanEnd
        (scanQuotedEnd source start singleQuote), world)
  scanLineCommentEnd : ∀ start : Nat, start + 1 < source.length →
    start ≤ 2147483647 →
    calls.evaluate world
        Lexer.Scanners.scanLineCommentEndFunction.id
        (Model.argumentValues source start) =
      .ok (.signed .i32 (Lanius.Compiler.Lexer.scanLineCommentEnd source start),
        world)
  scanBlockCommentEnd : ∀ start : Nat, start + 1 < source.length →
    start ≤ 2147483647 →
    calls.evaluate world
        Lexer.Scanners.scanBlockCommentEndFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encodedScanEnd
        (Lanius.Compiler.Lexer.scanBlockCommentEnd source start),
        world)
  scanSucceeded : ∀ result : ScanEnd,
    calls.evaluate world
        Lexer.Functions.scanSucceededFunction.id [Model.encodedScanEnd result] =
      .ok (.boolean (match result with
        | .success _ => true
        | .failure _ => false), world)
  scanEndOffset : ∀ finish : Nat,
    calls.evaluate world
        Lexer.Functions.scanEndOffsetFunction.id
        [Model.encodedScanEnd (.success finish)] =
      .ok (.signed .i32 finish, world)
  scanErrorOffset : ∀ error : Nat,
    calls.evaluate world
        Lexer.Functions.scanErrorOffsetFunction.id
        [Model.encodedScanEnd (.failure error)] =
      .ok (.signed .i32 error, world)
  scanNumber : ∀ start : Nat, start < source.length →
    start ≤ 2147483647 →
    calls.evaluate world
        Number.Functions.scanNumberFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encodedNumber
        (Lanius.Compiler.Lexer.scanNumber source start), world)
  scanLeadingDotNumber : ∀ start : Nat, start + 1 < source.length →
    start ≤ 2147483647 →
    calls.evaluate world
        Number.Functions.scanLeadingDotNumberFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encodedNumber
        (Lanius.Compiler.Lexer.scanLeadingDotNumber source start),
        world)
  matchSymbolHead : ∀ (start : Nat) (rule : SymbolRule),
    start < source.length → start ≤ 2147483647 →
    Lanius.Compiler.Lexer.matchSymbolHead (source.drop start) = some rule →
    calls.evaluate world
        Symbol.Functions.matchSymbolHeadFunction.id
        (Model.argumentValues source start) =
      .ok (Symbol.Semantics.value
          (Lanius.Compiler.TokenKind.gpuCode rule.kind)
          rule.spelling.length,
        world)
  tokenMatchKind : ∀ (kind length : Nat),
    calls.evaluate world
        Symbol.Functions.tokenMatchKindFunction.id
        [Symbol.Semantics.value kind length] =
      .ok (.signed .i32 kind, world)
  tokenMatchLength : ∀ (kind length : Nat),
    calls.evaluate world
        Symbol.Functions.tokenMatchLengthFunction.id
        [Symbol.Semantics.value kind length] =
      .ok (.signed .i32 length, world)

theorem failed_evaluates
    (contract : HelperContract calls source world)
    (environment : Env arity) (offsetTerm : Term signature arity)
    (offset : Nat)
    (offsetResult : Term.evaluate (termMachine calls) world
      environment offsetTerm =
        .ok (.signed .i32 (Int.ofNat offset), world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.failed offsetTerm) =
      .ok (Model.encoded (.failure offset), world) := by
  unfold Commands.failed Commands.call
  apply Term.evaluate_apply1 offsetResult
  change calls.evaluate world
    TokenScan.Functions.failedFunction.id [.signed .i32 offset] = _
  exact contract.failed offset

theorem successful_evaluates
    (contract : HelperContract calls source world)
    (environment : Env arity) (kindTerm finishTerm : Term signature arity)
    (kind : Lanius.Compiler.TokenKind) (finish : Nat)
    (kindResult : Term.evaluate (termMachine calls) world
      environment kindTerm =
        .ok (.signed .i32 (Int.ofNat kind.gpuCode), world))
    (finishResult : Term.evaluate (termMachine calls) world
      environment finishTerm =
        .ok (.signed .i32 (Int.ofNat finish), world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.successful kindTerm finishTerm) =
      .ok (Model.encoded (.token ⟨kind, 0, finish⟩),
        world) := by
  unfold Commands.successful Commands.call
  apply Term.evaluate_apply2 kindResult finishResult
  change calls.evaluate world
    TokenScan.Functions.successfulFunction.id
      [.signed .i32 kind.gpuCode, .signed .i32 finish] = _
  change calls.evaluate world
    TokenScan.Functions.successfulFunction.id
      [.signed .i32 kind.gpuCode, .signed .i32 finish] =
    .ok (TokenScan.Semantics.value true kind.gpuCode finish 0,
      world)
  exact contract.successful kind finish

theorem source_index_evaluates
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (startInBounds : start < source.length) :
    Term.evaluate (termMachine calls) world
        (Model.environment source start)
        (Commands.index (Commands.slot 0) (Commands.slot 2)) =
      .ok (.signed .i32 (Int.ofNat source[start].val),
        world) := by
  unfold Commands.index
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.index Commands.sliceType Commands.i32Type Commands.i32Type)
      [Model.sourceSlice source, .signed .i32 (Int.ofNat start)] = _
  have raw := Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_index
    (program := verifiedFrontendCore)
    (baseType := Commands.sliceType) (indexType := Commands.i32Type)
    (elementType := Commands.i32Type)
    (found := sourceFound)
    (inBounds := by simpa using startInBounds)
  rw [Model.sourceIntegers_get source start startInBounds] at raw
  rw [Model.sourceIntegers_length] at raw
  exact raw

theorem constant_evaluates
    (environment : Env arity) (id : ConstantId) (value : Nat)
    (found : verifiedFrontendCore.constant? id = some {
      id := id
      type := Commands.i32Type
      value := .signed .i32 (Int.ofNat value)
    }) :
    Term.evaluate (termMachine calls) world environment
        (Commands.constant id) =
      .ok (.signed .i32 (Int.ofNat value), world) := by
  unfold Commands.constant
  apply Term.evaluate_apply0
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world (.constant id Commands.i32Type) [] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_constant found

theorem equal_evaluates
    (left right : Term signature arity) (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine calls) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (termMachine calls) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.comparison .equal left right) =
      .ok (.boolean (decide (leftValue = rightValue)), world) := by
  unfold Commands.comparison Commands.binary
  apply Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.binary .equal Commands.i32Type Commands.i32Type Commands.boolType)
      [.signed .i32 (Int.ofNat leftValue),
        .signed .i32 (Int.ofNat rightValue)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_equal
    leftValue rightValue

theorem scanner_evaluates
    (environment : Env arity) (scanner : Function)
    (sourceTerm boundTerm startTerm : Term signature arity) (start finish : Nat)
    (sourceResult : Term.evaluate (termMachine calls) world
      environment sourceTerm = .ok (Model.sourceSlice source,
        world))
    (boundResult : Term.evaluate (termMachine calls) world
      environment boundTerm = .ok (.signed .i32 (Int.ofNat source.length),
        world))
    (startResult : Term.evaluate (termMachine calls) world
      environment startTerm = .ok (.signed .i32 (Int.ofNat start),
        world))
    (scannerResult : calls.evaluate world scanner.id
      (Model.argumentValues source start) =
        .ok (.signed .i32 (Int.ofNat finish), world)) :
    Term.evaluate (termMachine calls) world environment
        (Commands.call scanner [sourceTerm, boundTerm, startTerm]) =
      .ok (.signed .i32 (Int.ofNat finish), world) := by
  unfold Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceResult
      (evaluateTerms_cons boundResult
        (evaluateTerms_cons startResult
          (evaluateTerms_nil _ _ _)))
  · change calls.evaluate world scanner.id
      [Model.sourceSlice source, .signed .i32 source.length,
        .signed .i32 start] = _
    exact scannerResult

theorem identifierEnd_evaluates
    (contract : HelperContract calls source world)
    (environment : Env arity) (sourceTerm boundTerm startTerm : Term signature arity)
    (start : Nat)
    (startInBounds : start < source.length)
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
        (Commands.call Lexer.Scanners.scanIdentifierEndFunction
          [sourceTerm, boundTerm, startTerm]) =
      .ok (.signed .i32 (Int.ofNat (scanIdentifierEnd source start)),
        world) :=
  scanner_evaluates environment Lexer.Scanners.scanIdentifierEndFunction
    sourceTerm boundTerm startTerm start (scanIdentifierEnd source start)
    sourceResult boundResult startResult
      (contract.scanIdentifierEnd start startInBounds startBound)

theorem whitespaceEnd_evaluates
    (contract : HelperContract calls source world)
    (environment : Env arity) (sourceTerm boundTerm startTerm : Term signature arity)
    (start : Nat)
    (startInBounds : start < source.length)
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
        (Commands.call Lexer.Scanners.scanWhitespaceEndFunction
          [sourceTerm, boundTerm, startTerm]) =
      .ok (.signed .i32 (Int.ofNat (scanWhitespaceEnd source start)),
        world) :=
  scanner_evaluates environment Lexer.Scanners.scanWhitespaceEndFunction
    sourceTerm boundTerm startTerm start (scanWhitespaceEnd source start)
    sourceResult boundResult startResult
      (contract.scanWhitespaceEnd start startInBounds startBound)

theorem classify_evaluates
    (contract : HelperContract calls source world) (first : Byte) :
    Term.evaluate (termMachine calls) world
        ((Model.environment source start).push
          (.signed .i32 (Int.ofNat first.val)))
        (Commands.call Lexer.Functions.classifyStartFunction
          [Commands.slot 3]) =
      .ok (.signed .i32 (Int.ofNat (classifyStartCode first)),
        world) := by
  unfold Commands.call
  apply Term.evaluate_apply1 (by rfl)
  exact contract.classifyStart first

theorem start_condition_evaluates
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647) :
    Term.evaluate (termMachine calls) world
        (Model.environment source start)
        (Commands.comparison .greaterEqual (Commands.slot 2)
          (Commands.slot 1)) =
      .ok (.boolean (decide (start ≥ source.length)),
        world) := by
  unfold Commands.comparison Commands.binary
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.binary .greaterEqual Commands.i32Type Commands.i32Type
        Commands.boolType)
      [.signed .i32 (Int.ofNat start),
        .signed .i32 (Int.ofNat source.length)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_greaterEqual
    start source.length

theorem returned_run
    (valueTerm : Term signature arity) (value : Value)
    (evaluated : Term.evaluate (termMachine calls) world environment valueTerm =
      .ok (value, world)) :
    Stateful.Acyclic.run? (termMachine calls)
        (commandMachine calls)
        world environment (Commands.returned valueTerm) =
      some (.returned (some value), world, environment) := by
  unfold Commands.returned
  simp [Stateful.Acyclic.run?, evaluated]

end Lanius.Extraction.RawLexer.ScanOne.Evaluation
