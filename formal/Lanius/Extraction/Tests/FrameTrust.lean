import Lanius.Extraction.Parser.Recognize.ChartClear
import Lanius.Extraction.Parser.Recognize.ChartCursor
import Lanius.Extraction.Parser.Recognize.Position.Core
import Lean.Util.CollectAxioms

/-! The numeric projection of a union of source frames is a structural list
identity. It must not extend the trust required to construct the input frames.
This checks the actual public proofs, including their transitive dependencies;
it does not claim that every inherited frontend dependency is kernel-only. -/

open Lanius.Extraction.ParserRecognize

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  let kernelOnly := #[
    ``Lanius.Extraction.ParserBasics.Proof.parameterBindings_eq,
    ``verifiedParserChartClearAccessFrame,
    ``verifiedParserChartClearLiveFrame,
    ``verifiedParser_chart_clear_access_frame,
    ``verifiedParser_chart_clear_live_frame,
    ``verifiedParser_chart_clear_shared_frame_ids,
    ``verifiedParserInitialLoopAccessFrame,
    ``verifiedParserInitialLoopLiveFrame,
    ``verifiedParser_initial_loop_access_frame,
    ``verifiedParser_initial_loop_live_frame,
    ``verifiedParser_initial_loop_shared_frame_ids,
    ``verifiedParserPredictionLoopAccessFrame,
    ``verifiedParserPredictionLoopLiveFrame,
    ``verifiedParser_prediction_loop_access_frame,
    ``verifiedParser_prediction_loop_access_frame_ids,
    ``verifiedParser_prediction_loop_live_frame,
    ``verifiedParser_prediction_loop_live_frame_ids,
    ``verifiedParser_prediction_loop_shared_frame_ids,
    ``verifiedParser_prediction_loop_preserved_frame_ids,
    ``verifiedParserRootLoopAccessFrame,
    ``verifiedParserRootLoopLiveFrame,
    ``verifiedParser_root_loop_access_frame,
    ``verifiedParser_root_loop_live_frame,
    ``verifiedParser_root_loop_shared_frame_ids]
  for declaration in kernelOnly do
    let actual ← Lean.collectAxioms declaration
    let extra := actual.filter fun assumption => !standard.contains assumption
    unless extra.isEmpty do
      throwError "source frame retains nonstandard assumptions: {declaration}: {extra}"
    Lean.logInfo m!"{declaration}: kernel-only source-frame computation"
  let pairs := #[
    (``verifiedParserChartCursorBindings_core_ids,
      ``verifiedParserChartCursorBindings),
    (``verifiedParserChartClearPersistentBindings_core_ids,
      ``verifiedParserChartClearPersistentBindings),
    (``verifiedParserInitialLoopPersistentBindings_core_ids,
      ``verifiedParserInitialLoopPersistentBindings),
    (``verifiedParserPredictionLoopPersistentBindings_core_ids,
      ``verifiedParserPredictionLoopPersistentBindings),
    (``verifiedParserPredictionLoopPreservedBindings_core_ids,
      ``verifiedParserPredictionLoopPreservedBindings),
    (``verifiedParserRootLoopBindings_core_ids,
      ``verifiedParserRootLoopBindings)]
  for (proof, frame) in pairs do
    let inherited ← Lean.collectAxioms frame
    let actual ← Lean.collectAxioms proof
    let added := actual.filter fun assumption =>
      !standard.contains assumption && !inherited.contains assumption
    unless added.isEmpty do
      throwError "frame projection adds trust dependencies: {proof}: {added}"
    Lean.logInfo m!"{proof}: no assumptions beyond the source frame"
  -- The transition still calls inherited frontend helpers. Its two former
  -- native cursor-freshness checks must not survive as local trust obligations.
  let transition := ``RecognizerStatePredictionCompletedFrame.enter_nullable
  let transitionAxioms ← Lean.collectAxioms transition
  let localAssumptions := transitionAxioms.filter transition.isPrefixOf
  unless localAssumptions.isEmpty do
    throwError "nullable transition retains local assumptions: {localAssumptions}"
  Lean.logInfo m!"{transition}: no locally generated assumptions"
