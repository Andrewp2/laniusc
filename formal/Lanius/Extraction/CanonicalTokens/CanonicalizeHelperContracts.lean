import Lanius.Extraction.CanonicalTokens.CanonicalKindContracts
import Lanius.Extraction.CanonicalTokens.CanonicalizeExecution

namespace Lanius.Extraction.CanonicalTokens.CanonicalizeHelperContracts

open Lanius
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation

/-- The exact helper registry used by `canonicalize_in_place`: the checked
`canonical_kind` body followed by its checked trivia/keyword dependencies. -/
theorem framePreservingCallSoundness
    (baseSound : FramePreservingCallSoundness verifiedFrontendCore
      Model.callModel) :
    FramePreservingCallSoundness verifiedFrontendCore
      CanonicalizeExecution.calls := by
  simpa [CanonicalizeExecution.calls] using
    FramePreservingCallSoundness.route
      (selectFirst := fun function =>
        function == Functions.canonicalKindFunction.id)
      (CanonicalKindContracts.framePreservingCallSoundness baseSound)
      baseSound

theorem worldPreserving : WorldPreserving CanonicalizeExecution.calls := by
  have baseWorldPreserving : WorldPreserving Model.callModel := by
    intro beforeWorld afterWorld function values value evaluated
    simp only [Model.callModel] at evaluated
    split at evaluated <;> try contradiction
    · split at evaluated <;> try contradiction
      exact (congrArg Prod.snd (Except.ok.inj evaluated)).symm
    · split at evaluated <;> try contradiction
      split at evaluated <;> try contradiction
      split at evaluated <;> try contradiction
      split at evaluated <;> try contradiction
      split at evaluated <;> try contradiction
      exact (congrArg Prod.snd (Except.ok.inj evaluated)).symm
  intro beforeWorld afterWorld function values value evaluated
  change (CallModel.route
    (fun function => function == Functions.canonicalKindFunction.id)
    CanonicalKindCallModel.calls Model.callModel).evaluate beforeWorld function
      values = .ok (value, afterWorld) at evaluated
  exact (WorldPreserving.route
      (selectFirst := fun function =>
        function == Functions.canonicalKindFunction.id)
      CanonicalKindContracts.worldPreserving
      baseWorldPreserving) evaluated

theorem callSoundness
    (baseSound : FramePreservingCallSoundness verifiedFrontendCore
      Model.callModel) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore CanonicalizeExecution.calls :=
  (framePreservingCallSoundness baseSound).toCallSoundness worldPreserving

end Lanius.Extraction.CanonicalTokens.CanonicalizeHelperContracts
