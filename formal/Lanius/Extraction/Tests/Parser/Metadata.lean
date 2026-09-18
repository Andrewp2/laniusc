import Lanius.Extraction.VerifiedFrontend.Parser.Symbolic
import Lanius.Extraction.VerifiedFrontend.Parser.Validation
import Lanius.Extraction.Parser.Recognize.State.Core
import Lanius.Extraction.Parser.Recognize.Root.Selection
import Lanius.Extraction.Parser.Recognize.Caller
import Lanius.Extraction.Parser.Recognize.Parent
import Lanius.Extraction.Parser.Recognize.Nullable
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Metadata

/- Audit the materialized data and its connection to the original derivation,
not only cheap projections whose hypotheses could conceal native trust. -/
run_elab do
  for name in #[``verifiedParser_scoped_surface_accepted,
      ``verifiedParser_symbolic_derivation_accepted,
      ``verifiedParserSymbolicFunctions, ``verifiedParser_symbolic_functions_derived,
      ``verifiedParser_symbolic_function_names,
      ``verifiedParserRecognizer_parameter_frame,
      ``verifiedParserRecognizer_parameter_core_ids,
      ``verifiedParserRangeValid_parameter_core_ids,
      ``verifiedParserRangeValid_root_frame,
      ``verifiedParserFindState_caller_frame,
      ``verifiedParserFindState_caller_frame_ids,
      ``verifiedParserScanTerminal_caller_frame,
      ``verifiedParserScanTerminal_caller_frame_ids,
      ``verifiedParserRecognizerSymbolic_matches_extracted,
      ``ParserValidation.parserGrammarProductionLoop_source_frame,
      ``ParserValidation.parserGrammarSymbolLoop_source_access_frame,
      ``ParserValidation.parserGrammarSymbolLoop_source_live_frame,
      ``ParserValidation.parserGrammarNonterminalLoop_source_frame,
      ``ParserValidation.parserGrammarNonterminalLoop_source_access_frame,
      ``ParserValidation.parserGrammarListedLoop_source_access_frame,
      ``ParserValidation.parserGrammarListedLoop_source_live_frame,
      ``ParserRecognize.parserRecognizeReification_exists,
      ``ParserRecognize.verifiedParser_position_loop_access_frame,
      ``ParserRecognize.verifiedParser_position_loop_live_frame,
      ``ParserRecognize.verifiedParser_position_loop_preserved_frame_ids,
      ``ParserRecognize.verifiedParser_state_loop_access_frame,
      ``ParserRecognize.verifiedParser_state_loop_live_frame,
      ``ParserRecognize.verifiedParser_state_loop_shared_frame_ids,
      ``ParserRecognize.verifiedParser_state_loop_preserved_frame_ids,
      ``ParserRecognize.verifiedParser_parent_loop_access_frame,
      ``ParserRecognize.verifiedParser_parent_loop_live_frame,
      ``ParserRecognize.verifiedParser_parent_loop_shared_frame_ids,
      ``ParserRecognize.verifiedParser_parent_loop_preserved_frame_ids,
      ``ParserRecognize.verifiedParser_nullable_loop_access_frame,
      ``ParserRecognize.verifiedParser_nullable_loop_live_frame,
      ``ParserRecognize.verifiedParser_nullable_loop_shared_frame_ids,
      ``ParserRecognize.verifiedParser_nullable_loop_preserved_frame_ids,
      ``ParserRecognize.stateBodyCommand,
      ``ParserRecognize.positionBodyCommand,
      ``ParserRecognize.stateLoopCommand_toCore,
      ``ParserRecognize.positionLoopCommand_toCore,
      ``ParserRecognize.initialLoopCommand_toCore,
      ``ParserRecognize.initialContinuationCommand_toCore,
      ``ParserRecognize.parserRecognizeRootLoopView_toCore_exactly] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Source-derived parser metadata {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Materialized parser metadata and its exact derivation equality use only standard Lean axioms."

  -- Resolve private declarations by their user names, not a generated private
  -- prefix. Audit every refactored shape and root reification/layout fact.
  let environment ← Lean.getEnv
  let shapes := #[`stateAfterBindingsCommand_shape, `stateTerminalFullCommand_shape,
    `stateTerminalSuccessCommand_shape, `stateIncompleteCommand_shape,
    `stateTerminalCommand_shape, `stateAdvanceCommand_shape, `stateBodyCommand_shape,
    `rootLoopReification_exists, `rootBodyReification_exists,
    `rootRejectedReification_exists, `rootStatementReification_exists,
    `rootRejectedCommand_shape, `rootStatementCommand_shape,
    `positionStatementCommand_shape, `rootIntoStatementLayout_extends,
    `rootStatementIntoPositionLayout_extends, `rootBodyCommand_shape,
    `rootLoop_calls_supported_in_state, `rootRejected_calls_supported_in_state]
  for shape in shapes do
    let expected := `Lanius.Extraction.ParserRecognize ++ shape
    let names := environment.constants.toList.filterMap fun (name, _) =>
      if Lean.privateToUserName name == expected then some name else none
    unless names.length == 1 do
      throwError "Expected exactly one source-shape theorem {expected}, found {names.length}"
    for assumption in ← Lean.collectAxioms names.head! do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Source-shape theorem {expected} adds unexpected axiom {assumption}"
  Lean.logInfo "Audited source shapes and root reification/layout facts use only standard Lean axioms."

  -- These semantic consumers are transitively kernel-only, including their
  -- imported constant, function-ID, and negative-sentinel facts. Checking just
  -- locally generated axioms would miss regressions in those dependencies.
  for name in #[``ParserRecognize.stateBodyCommand_evaluates_of_afterBindings,
      ``ParserRecognize.executeRecognitionRegion,
      ``ParserRecognize.recognition_region_evaluates,
      ``ParserRecognize.RecognizerStateLoopInvariant.bind_candidate_fields,
      ``ParserRecognize.RecognizerStateCandidateBindings.enter_parent,
      ``ParserAccessors.verifiedParser_accessor_constants,
      ``ParserAccessors.verifiedParser_rhs_symbol_constants,
      ``ParserRecognize.stateIncompleteCommand_evaluates_of_symbol,
      ``ParserRecognize.stateTerminalCommand_evaluates_miss,
      ``ParserRecognize.RecognizerTerminalAppendInvariant.functional_terminal_ok,
      ``ParserRecognize.RecognizerTerminalAppendInvariant.functional_terminal_full,
      ``ParserRecognize.RecognizerStateLoopInvariant.functional_advance,
      ``ParserRecognize.StateAfterBindingsEnvironment.after_workspace_update,
      ``ParserRecognize.stateSubtractTerm_evaluates,
      ``ParserRecognize.stateIndexAddTerm_evaluates,
      ``ParserRecognize.stateLhsTerm_evaluates,
      ``ParserRecognize.positionLoopCondition_evaluates,
      ``Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_lessEqual,
      ``Lanius.FunctionalView.Core.Effectful.Term.evaluate_call,
      ``ParserAccessors.FunctionalView.calls_at_lhs] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Parser semantic consumer {name} adds unexpected axiom {assumption}"
  Lean.logInfo "The audited parser-state semantic consumers and accessor routing use only standard Lean axioms."

end Lanius.Extraction.Tests.Parser.Metadata
