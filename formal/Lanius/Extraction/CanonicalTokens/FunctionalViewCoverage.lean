import Lanius.Extraction.CanonicalTokens.CanonicalizeConcreteSemantics
import Lanius.Extraction.CanonicalTokens.CheckedCalls
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.CanonicalTokens.FunctionalViewCoverage

open Lanius.Core
open Lanius.Extraction
open Lanius.FunctionalView.Core
open Lanius.Extraction.CanonicalTokens
open Lanius.Extraction.CanonicalTokens.Functions
open Lanius.FunctionalView.FreshSimulation

def sourceText : String :=
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "canonical_tokens.lani"

def functionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendCanonicalTokensArtifact).map
    fun surface =>
      (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

/-- This declaration inventory is reconstructed from the checked Surface
    artifact, so adding, removing, or renaming a source function invalidates
    the four-function gate below. -/
theorem source_function_names :
    functionNames = some ["is_trivia", "keyword_kind", "canonical_kind",
      "canonicalize_in_place"] := by
  native_decide

theorem artifact_tracks_source :
    verifiedFrontendCanonicalTokensArtifact.sources.map (·.path) =
        ["verified_compiler/src/verified/canonical_tokens.lani"] ∧
      verifiedFrontendCanonicalTokensArtifact.sources.map (·.bytes) =
        [sourceTextBytes sourceText] := by
  native_decide

structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof :=
  ⟨proof⟩

structure ExactCoverage where
  sourceFunctions : TheoremReference source_function_names
  sourceBytes : TheoremReference artifact_tracks_source
  isTrivia :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter
        (identityLayout (arity := 1)) 1 isTriviaView.command = isTriviaBody
  keywordKind :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter
        (identityLayout (arity := 3)) 3 keywordKindView.command = keywordKindBody
  canonicalKind :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter
        (identityLayout (arity := 4)) 4 canonicalKindView.command =
      canonicalKindBody
  canonicalizeInPlace :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter
        (identityLayout (arity := 3)) 3 canonicalizeInPlaceView.command =
      canonicalizeInPlaceBody

theorem exact_complete : Nonempty ExactCoverage := by
  exact ⟨{
    sourceFunctions := reference source_function_names
    sourceBytes := reference artifact_tracks_source
    isTrivia := isTriviaView_toCore_exactly
    keywordKind := keywordKindView_toCore_exactly
    canonicalKind := canonicalKindView_toCore_exactly
    canonicalizeInPlace := canonicalizeInPlaceView_toCore_exactly
  }⟩

theorem canonicalKind_framePreservingCallSoundness :
    FramePreservingCallSoundness verifiedFrontendCore
      CanonicalKindCallModel.calls :=
  CanonicalKindContracts.framePreservingCallSoundness
    CheckedCalls.framePreservingCallSoundness

theorem canonicalize_framePreservingCallSoundness :
    FramePreservingCallSoundness verifiedFrontendCore
      CanonicalizeExecution.calls :=
  CanonicalizeHelperContracts.framePreservingCallSoundness
    CheckedCalls.framePreservingCallSoundness

theorem canonicalize_callSoundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore CanonicalizeExecution.calls :=
  CanonicalizeHelperContracts.callSoundness
    CheckedCalls.framePreservingCallSoundness

def canonicalizeInPlaceBody_executes :=
  CanonicalizeConcreteSemantics.request_body_executes
    CheckedCalls.framePreservingCallSoundness

def canonicalizeInPlaceCall_executes :=
  CanonicalizeConcreteSemantics.request_call_executes
    CheckedCalls.framePreservingCallSoundness

/-- Premise-free semantic coverage.  The first two functions share one exact
checked-call registry; `canonical_kind` composes that registry; and the
mutable compactor is connected through its explicit raw-token encoding
invariant to the independent lexer model, checked Core body, and real call. -/
structure SemanticCoverage where
  exact : ExactCoverage
  isTriviaResult :
    TheoremReference (@IsTriviaSemantics.recovered_command_evaluates)
  keywordKindResult :
    TheoremReference (@KeywordSpanSemantics.command_evaluates)
  triviaAndKeywordCalls :
    FramePreservingCallSoundness verifiedFrontendCore Model.callModel
  canonicalKindResult :
    TheoremReference (@CanonicalKind.view_executes_in_world)
  canonicalKindCalls :
    FramePreservingCallSoundness verifiedFrontendCore
      CanonicalKindCallModel.calls
  canonicalizeRows :
    TheoremReference (@CanonicalizeConcreteSemantics.request_rowsValid)
  canonicalizeResult :
    TheoremReference (@CanonicalizeAgreement.Model.result_agrees)
  canonicalizeCommand :
    TheoremReference (@CanonicalizeConcreteSemantics.request_command_evaluates)
  canonicalizeHelpers :
    FramePreservingCallSoundness verifiedFrontendCore
      CanonicalizeExecution.calls
  canonicalizeBody :
    TheoremReference (@canonicalizeInPlaceBody_executes)
  canonicalizeCall :
    TheoremReference (@canonicalizeInPlaceCall_executes)

/-- All four checked source functions have exact source recovery and concrete,
premise-free logical and checked-program semantics. -/
theorem semantics_complete : Nonempty SemanticCoverage := by
  exact ⟨{
    exact := Classical.choice exact_complete
    isTriviaResult :=
      reference (@IsTriviaSemantics.recovered_command_evaluates)
    keywordKindResult :=
      reference (@KeywordSpanSemantics.command_evaluates)
    triviaAndKeywordCalls := CheckedCalls.framePreservingCallSoundness
    canonicalKindResult :=
      reference (@CanonicalKind.view_executes_in_world)
    canonicalKindCalls := canonicalKind_framePreservingCallSoundness
    canonicalizeRows :=
      reference (@CanonicalizeConcreteSemantics.request_rowsValid)
    canonicalizeResult :=
      reference (@CanonicalizeAgreement.Model.result_agrees)
    canonicalizeCommand :=
      reference (@CanonicalizeConcreteSemantics.request_command_evaluates)
    canonicalizeHelpers := canonicalize_framePreservingCallSoundness
    canonicalizeBody := reference (@canonicalizeInPlaceBody_executes)
    canonicalizeCall := reference (@canonicalizeInPlaceCall_executes)
  }⟩

/- The logical `KeywordCommand.command` evaluator and its arbitrary-cell Span
   boundary are premise-free explicit-view proofs.  This audit deliberately
   excludes `CheckedCalls` and source recovery: those retain their existing
   native assumptions and are reported separately. -/
run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  let declarations := #[
    ``KeywordExecution.command_evaluates,
    ``KeywordSpanSemantics.command_evaluates]
  for declaration in declarations do
    let actual ← Lean.collectAxioms declaration
    let extra := actual.filter (fun assumption => !standard.contains assumption)
    unless extra.isEmpty do
      throwError "keyword dependency extends kernel trust: {declaration}: {extra}"
  Lean.logInfo m!"{declarations.size} keyword execution/world endpoints use only standard Lean axioms"

end Lanius.Extraction.CanonicalTokens.FunctionalViewCoverage
