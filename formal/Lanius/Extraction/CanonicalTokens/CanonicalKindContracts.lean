import Lanius.Extraction.CanonicalTokens.CanonicalKindCallModel
import Lanius.FunctionalViewCoreCallFrame
import Lanius.FunctionalViewCoreFreshSimulation

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
  let callee := enterCall afterArguments bindings
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) beforeWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  obtain ⟨afterEnvironment, functionalEvaluation⟩ :=
    CanonicalKind.view_executes_in_world beforeWorld cell source rawKind
      start finish sourceFound ordered inBounds sourceFitsI32
  let operations := operationSoundness verifiedFrontendCore Model.callModel
    helperSound
  have simulation := commandSoundness operations functionalEvaluation
    (by native_decide) calleeRepresented
    (LayoutBelow.identity (arity := 4)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by
      simpa [callee, bindings] using
        (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [canonicalKindView_toCore_exactly] at bodyExecution
  change Executes verifiedFrontendCore callee canonicalKindBody
    (.returned (some (.signed .i32
      (CanonicalKind.result source rawKind start finish)))) completed
    at bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call canonicalKindFunction.id (toCoreExprs layout sourceArguments))
      (.signed .i32 (CanonicalKind.result source rawKind start finish))
      (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned
      (bindings := bindings) (body := canonicalKindBody)
      argumentsExecution verifiedFrontendCore_finds_canonicalKind
    · simpa [bindings, calleeEnvironment, CanonicalKindCallModel.i32,
        CanonicalKind.sourceValueAt] using
        parameterBindingsMatch cell source rawKind start finish
    · exact canonicalKindFunction_has_body
    · simpa [callee, bindings] using bodyExecution
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed completedWellFormed
      (bindings := bindings) bodyEffect (by
        intro writtenCell written
        exact written)
  exact ⟨restoreLocals afterArguments completed, callExecution,
    afterWellFormed, afterRepresented,
    argumentsEffect.trans_same
      (callEffect.weaken CellSet.empty_subset)⟩

theorem worldPreserving : WorldPreserving CanonicalKindCallModel.calls :=
  CanonicalKindCallModel.worldPreserving

end Lanius.Extraction.CanonicalTokens.CanonicalKindContracts
