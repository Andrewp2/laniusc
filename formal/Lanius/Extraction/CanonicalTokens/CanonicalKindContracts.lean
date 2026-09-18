import Lanius.Extraction.CanonicalTokens.CanonicalKindCallModel
import Lanius.FunctionalViewCoreCallFrame
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCheckedSimulation

namespace Lanius.Extraction.CanonicalTokens.CanonicalKindContracts

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.CanonicalTokens.Functions

private def i32 : Ty := .scalar (.signed .i32)

private theorem functionParameters :
    canonicalKindFunction.parameters =
      [(0, .slice i32), (1, i32), (2, i32), (3, i32)] := by
  native_decide

private theorem parameterBindingsMatch (cell : CellId) (source : List Int)
    (rawKind : Int) (start finish : Nat) :
    bindParameters canonicalKindFunction.parameters
        [CanonicalKind.sourceValueAt cell source, .signed .i32 rawKind,
          .signed .i32 start, .signed .i32 finish] =
      some (parameterBindings
        (CanonicalKind.environmentInWorld cell source rawKind start finish)) := by
  rw [functionParameters]
  simp [bindParameters, parameterBindings,
    CanonicalKind.environmentInWorld, CanonicalKind.sourceValueAt,
    List.finRange, i32]
  rfl

/-- Concrete checked-call semantics for `canonical_kind`, parameterized only
by the already-independent `is_trivia`/`keyword_kind` helper registry. -/
theorem framePreservingCallSoundness
    (helperSound : FramePreservingCallSoundness verifiedFrontendCore
      Model.callModel) :
    FramePreservingCallSoundness verifiedFrontendCore
      CanonicalKindCallModel.calls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values value argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨source, cell, rawKind, start, finish, sourceFound, functionEq,
      valuesEq, ordered, inBounds, sourceFitsI32, resultEq, afterWorldEq⟩ :=
    CanonicalKindCallModel.success evaluated
  subst function
  subst values
  subst value
  subst afterWorld
  let calleeEnvironment :=
    CanonicalKind.environmentInWorld cell source rawKind start finish
  let bindings := parameterBindings calleeEnvironment
  obtain ⟨afterEnvironment, functionalEvaluation⟩ :=
    CanonicalKind.view_executes_in_world beforeWorld cell source rawKind
      start finish sourceFound ordered inBounds sourceFitsI32
  exact CheckedSimulation.callPreservesFrame
    helperSound argumentsExecution argumentsEffect
    verifiedFrontendCore_finds_canonicalKind
    (by
      simpa [bindings, calleeEnvironment, CanonicalKindCallModel.i32,
        CanonicalKind.sourceValueAt, Model.keywordSource] using
        parameterBindingsMatch cell source rawKind start finish)
    canonicalKindFunction_has_body functionalEvaluation
    (by native_decide) canonicalKindView_toCore_exactly
    afterArgumentsWellFormed represented

theorem worldPreserving : WorldPreserving CanonicalKindCallModel.calls :=
  CanonicalKindCallModel.worldPreserving

end Lanius.Extraction.CanonicalTokens.CanonicalKindContracts
