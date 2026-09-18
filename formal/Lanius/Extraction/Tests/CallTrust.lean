import Lanius.Extraction.Lexer.Calls
import Lanius.Extraction.Lexer.DigitAccessorContracts
import Lanius.Extraction.Number.Calls
import Lanius.Extraction.Frontend.Canonicalize
import Lanius.FunctionalViewCoreCheckedSimulation
import Lanius.Relational.ExecutableRefinement
import Lean.Util.CollectAxioms

/-! Scanner calls, the linked raw lexer, and frontend tokenization through canonicalization
must depend only on standard Lean axioms, including their source metadata and
independently consumed routes.
Audit all transitive assumptions: local-module budgets could miss inherited
native computations. This boundary includes execution, failures, emitted records,
and frame preservation, but not the enclosing extractor or its concrete self-instance.
-/

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  let declarations := #[
    ``Lanius.FunctionalView.Block.evaluate_if_bool,
    ``Lanius.Extraction.Lexer.Predicates.isIdentifierStartView_evaluates,
    ``Lanius.Extraction.Lexer.Predicates.isDecimalDigitView_evaluates,
    ``Lanius.Extraction.Lexer.Predicates.isWhitespaceView_evaluates,
    ``Lanius.Extraction.Lexer.Predicates.isSymbolStartView_evaluates,
    ``Lanius.Extraction.Lexer.Predicates.classifyStartView_evaluates,
    ``Lanius.Extraction.Lexer.Predicates.IdentifierContinue.view_evaluates,
    ``Lanius.Extraction.Lexer.LineComment.loop_evaluates,
    ``Lanius.Extraction.Lexer.LineComment.command_evaluates,
    ``Lanius.Extraction.Lexer.LineComment.core_body_executes,
    ``Lanius.Extraction.Lexer.LineComment.call_executes,
    ``Lanius.Extraction.Lexer.BlockComment.command_evaluates,
    ``Lanius.Extraction.Lexer.BlockComment.core_body_executes,
    ``Lanius.Extraction.Lexer.BlockComment.call_executes,
    ``Lanius.Extraction.Lexer.Quoted.command_evaluates,
    ``Lanius.Extraction.Lexer.Quoted.core_body_executes,
    ``Lanius.Extraction.Lexer.Quoted.call_executes,
    ``Lanius.Extraction.Lexer.Quoted.call_from_scanner_parameters_executes,
    ``Lanius.Extraction.Lexer.QuotedWrappers.stringCall_executes,
    ``Lanius.Extraction.Lexer.QuotedWrappers.characterCall_executes,
    ``Lanius.Extraction.Lexer.Calls.identifierView_evaluates,
    ``Lanius.Extraction.Lexer.Calls.identifierView_wp,
    ``Lanius.Extraction.Lexer.Calls.whitespaceView_evaluates,
    ``Lanius.Extraction.Lexer.Calls.whitespaceView_wp,
    ``Lanius.Extraction.Lexer.Calls.scannerFramePreservingCallSoundness,
    ``Lanius.Extraction.Lexer.Calls.framePreservingCallSoundness,
    ``Lanius.Extraction.Lexer.Calls.callSoundness,
    ``Lanius.FunctionalView.Core.Stateful.Command.Evaluates.changeCallModel,
    ``Lanius.FunctionalView.Stateful.Command.Evaluates.whileNextSequence,
    ``Lanius.FunctionalView.Core.Stateful.Representation.callReturned,
    ``Lanius.FunctionalView.Core.CheckedSimulation.callPreservesFrame,
    ``Lanius.Relational.Semantics.TermEvaluates.apply2ReferencesInversion,
    ``Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_index_map,
    ``Lanius.Relational.ExecutableRefinement.OperationsAgree.ofCalls,
    ``Lanius.Extraction.Lexer.DigitAccessorContracts.digitScanSucceededCall_evaluates,
    ``Lanius.Extraction.Lexer.DigitAccessorContracts.digitScanEndOffsetCall_evaluates,
    ``Lanius.Extraction.Lexer.DigitAccessorContracts.digitScanErrorOffsetCall_evaluates,
    ``Lanius.Extraction.Number.Calls.numberFramePreservingCallSoundness,
    ``Lanius.Extraction.Symbol.CompilerAgreement.compilerValue_eq_behaviorValue,
    ``Lanius.Extraction.Symbol.MainCalls.mainFramePreservingCallSoundness,
    ``Lanius.Extraction.RawLexer.ScanOne.Evaluation.symbolRule_exists,
    ``Lanius.Extraction.RawLexer.ScanOne.Evaluation.scanOne_run,
    ``Lanius.Extraction.RawLexer.LexInto.Execution.loopCondition_evaluates,
    ``Lanius.Extraction.RawLexer.LexInto.Execution.outputFullCondition_evaluates,
    ``Lanius.Extraction.RawLexer.LexInto.Execution.rowTerm_evaluates,
    ``Lanius.Extraction.RawLexer.LexInto.Execution.rowPlus_evaluates,
    ``Lanius.Extraction.RawLexer.LexInto.Execution.command_evaluates_request,
    ``Lanius.Extraction.RawLexer.LexInto.Caller.callee_executes,
    ``Lanius.Extraction.RawLexer.LexInto.Linked.call_evaluates_at,
    ``Lanius.Extraction.Frontend.lex_then_count,
    ``Lanius.Extraction.Frontend.lex_to_canonical,
    ``Lanius.Extraction.BufferCopy.copy_emitted_then_canonicalize,
    ``Lanius.Extraction.CanonicalTokens.Compaction.CheckedSource.evaluates_call,
    ``Lanius.Extraction.CanonicalTokens.Compaction.checkSource?,
    ``Lanius.Extraction.Number.Calls.numberCalls_scanNumber,
    ``Lanius.Extraction.Number.Calls.numberCalls_scanLeadingDotNumber,
    ``Lanius.Extraction.Number.Model.numberCalls_scanNumber,
    ``Lanius.Extraction.Number.Model.numberCalls_scanLeadingDotNumber,
    ``Lanius.Extraction.Number.Functions.scanNumber_body_present,
    ``Lanius.Extraction.Number.Functions.scanLeadingDotNumber_body_present,
    ``Lanius.Extraction.Decimal.Functions.integerScan_body_present,
    ``Lanius.Extraction.Decimal.Functions.floatScan_body_present,
    ``Lanius.Extraction.Decimal.Functions.numberFailure_body_present,
    ``Lanius.Extraction.Decimal.Functions.scanExponent_body_present,
    ``Lanius.Extraction.Decimal.Functions.finishDecimal_body_present,
    ``Lanius.Extraction.Decimal.Dependencies.successfulTokenScan_body_present,
    ``Lanius.Extraction.Decimal.Dependencies.failedTokenScan_body_present,
    ``Lanius.Extraction.Lexer.Digits.digitScanSucceededFunction_body_present,
    ``Lanius.Extraction.Lexer.Digits.digitScanEndOffsetFunction_body_present,
    ``Lanius.Extraction.Lexer.Digits.digitScanErrorOffsetFunction_body_present,
    ``Lanius.Extraction.Lexer.Digits.successfulDigitsFunction_body_present,
    ``Lanius.Extraction.Lexer.Digits.failedDigitsFunction_body_present,
    ``Lanius.Extraction.Lexer.Digits.isDigitForBaseFunction_body_present,
    ``Lanius.Extraction.Lexer.Digits.scanDigitRunFunction_body_present,
    ``Lanius.Extraction.Decimal.DigitRunModel.helperCallModel_successful,
    ``Lanius.Extraction.Decimal.DigitRunModel.helperCallModel_failed,
    ``Lanius.Extraction.Decimal.ConstructorCalls.floatScan,
    ``Lanius.Extraction.Decimal.ConstructorCalls.numberFailure,
    ``Lanius.Extraction.Decimal.EvaluationModel.integerScan,
    ``Lanius.Extraction.Decimal.EvaluationModel.floatScan,
    ``Lanius.Extraction.Decimal.EvaluationModel.numberFailure,
    ``Lanius.Extraction.Decimal.FinishEvaluationModel.scanDigitRun,
    ``Lanius.Extraction.Decimal.FinishEvaluationModel.isDigit,
    ``Lanius.Extraction.Decimal.FinishEvaluationModel.digitSucceeded,
    ``Lanius.Extraction.Decimal.FinishEvaluationModel.digitEnd,
    ``Lanius.Extraction.Decimal.FinishEvaluationModel.digitError,
    ``Lanius.Extraction.Decimal.FinishEvaluationModel.integerScan,
    ``Lanius.Extraction.Decimal.FinishEvaluationModel.floatScan,
    ``Lanius.Extraction.Decimal.FinishEvaluationModel.numberFailure,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.finishDecimal,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.scanExponent,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.scanDigitRun,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.digitSucceeded,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.digitEnd,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.digitError,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.integerScan,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.floatScan,
    ``Lanius.Extraction.Decimal.ConcreteSemantics.numberFailure,
    ``Lanius.Extraction.Decimal.DigitRunSemantics.scanDigitRunFunction_parameters,
    ``Lanius.Extraction.Decimal.ScanExponentSemantics.scanExponentFunction_parameters,
    ``Lanius.Extraction.Decimal.FinishSemantics.finishDecimalFunction_parameters]
  for declaration in declarations do
    let actual ← Lean.collectAxioms declaration
    let extra := actual.filter (fun assumption => !standard.contains assumption)
    unless extra.isEmpty do
      throwError "scanner dependency extends kernel trust: {declaration}: {extra}"
  Lean.logInfo m!"{declarations.size} scanner constructors, source projections, and routes use only standard Lean axioms"
