import Lanius.Extraction.CanonicalTokens.CallModelContracts
import Lanius.Extraction.CanonicalTokens.KeywordWorldSemantics
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.CanonicalTokens.CheckedCalls

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

private theorem isTriviaParameters :
    isTriviaFunction.parameters = [(0, i32)] := by
  native_decide

private theorem keywordKindParameters :
    keywordKindFunction.parameters =
      [(0, .slice i32), (1, i32), (2, i32)] := by
  native_decide

private theorem isTriviaBindings (kind : Int) :
    bindParameters isTriviaFunction.parameters [.signed .i32 kind] =
      some (parameterBindings (Model.isTriviaEnvironment kind)) := by
  rw [isTriviaParameters]
  simp [bindParameters, parameterBindings, Model.isTriviaEnvironment,
    List.finRange, i32]

private theorem keywordKindBindings (cell : CellId) (source : List Int)
    (start finish : Nat) :
    bindParameters keywordKindFunction.parameters [
        .slice i32 cell [] 0 source.length,
        .signed .i32 start, .signed .i32 finish] =
      some (parameterBindings
        (KeywordWorldSemantics.environment cell source start finish)) := by
  rw [keywordKindParameters]
  simp [bindParameters, parameterBindings,
    KeywordWorldSemantics.environment, List.finRange, i32]

private theorem noCallsSound :
    FramePreservingCallSoundness verifiedFrontendCore Model.noCalls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values value argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  simp [Model.noCalls] at evaluated

/-- Project the caller's full read-only world to the one source slice used by
`keyword_kind`.  The full representation is retained separately and restored
after the fresh call frame closes. -/
private theorem projectSingleton
    (represented : Representation layout localCell world environment state)
    (sourceFound : world.i32Slice? sourceCell = some source) :
    Representation layout localCell
      (ReadOnly.World.singleton sourceCell source) environment state := {
  worldOwned := by
    intro cell values found
    simp only [ReadOnly.World.singleton] at found
    split at found
    next same =>
      subst cell
      obtain rfl := Option.some.inj found
      exact represented.worldOwned sourceCell source sourceFound
    next => contradiction
  localOwned := represented.localOwned
  localCellsInjective := represented.localCellsInjective
  worldLocalsDisjoint := by
    intro cell singletonMember localMember
    obtain ⟨values, found⟩ := singletonMember
    simp only [ReadOnly.World.singleton] at found
    split at found
    next same =>
      subst cell
      exact represented.worldLocalsDisjoint sourceCell
        ⟨source, sourceFound⟩ localMember
    next => contradiction
}

private theorem isTriviaCall_executes
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {beforeWorld : ReadOnly.World} {callerEnvironment : Env arity}
    {before afterArguments : State}
    {sourceArguments : List (Term Core.signature arity)}
    {argumentWrites : CellSet} (kind : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (represented : Representation layout localCell beforeWorld
      callerEnvironment afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore before
      (Core.toCoreExprs layout sourceArguments) [.signed .i32 kind]
      afterArguments)
    (argumentsEffect : ModifiesOnly argumentWrites before afterArguments) :
    ∃ after,
      Evaluates verifiedFrontendCore before
        (.call isTriviaFunction.id (Core.toCoreExprs layout sourceArguments))
        (.boolean (IsTriviaSemantics.isTriviaCode kind)) after ∧
      StateWellFormed after ∧
      Representation layout localCell beforeWorld callerEnvironment after ∧
      ModifiesOnly argumentWrites before after := by
  let calleeEnvironment := Model.isTriviaEnvironment kind
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
  have functionalRun :=
    IsTriviaSemantics.recovered_command_evaluates beforeWorld kind
  have functionalEvaluation :=
    Lanius.FunctionalView.Stateful.Acyclic.run?_sound functionalRun
  let operations := operationSoundness verifiedFrontendCore Model.noCalls
    noCallsSound
  have simulation := commandSoundness operations functionalEvaluation
    (by native_decide) calleeRepresented
    (LayoutBelow.identity (arity := 1)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by
      simpa [callee, bindings] using
        (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [isTriviaView_toCore_exactly] at bodyExecution
  change Executes verifiedFrontendCore callee isTriviaBody
    (.returned (some (.boolean (IsTriviaSemantics.isTriviaCode kind))))
    completed at bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call isTriviaFunction.id (Core.toCoreExprs layout sourceArguments))
      (.boolean (IsTriviaSemantics.isTriviaCode kind))
      (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned
      (bindings := bindings) (body := isTriviaBody)
      argumentsExecution verifiedFrontendCore_finds_isTrivia
    · simpa [bindings, calleeEnvironment] using isTriviaBindings kind
    · exact isTriviaFunction_has_body
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

private theorem keywordKindCall_executes
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {beforeWorld : ReadOnly.World} {callerEnvironment : Env arity}
    {before afterArguments : State}
    {sourceArguments : List (Term Core.signature arity)}
    {argumentWrites : CellSet} (source : List Int) (cell : CellId)
    (start finish : Nat)
    (sourceFound : beforeWorld.i32Slice? cell = some source)
    (ordered : start ≤ finish) (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (represented : Representation layout localCell beforeWorld
      callerEnvironment afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore before
      (Core.toCoreExprs layout sourceArguments) [
        .slice i32 cell [] 0 source.length,
        .signed .i32 start, .signed .i32 finish] afterArguments)
    (argumentsEffect : ModifiesOnly argumentWrites before afterArguments) :
    ∃ after,
      Evaluates verifiedFrontendCore before
        (.call keywordKindFunction.id
          (Core.toCoreExprs layout sourceArguments))
        (.signed .i32 (Model.keywordKind source start finish)) after ∧
      StateWellFormed after ∧
      Representation layout localCell beforeWorld callerEnvironment after ∧
      ModifiesOnly argumentWrites before after := by
  let calleeEnvironment :=
    KeywordWorldSemantics.environment cell source start finish
  let bindings := parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have singletonRepresented : Representation layout localCell
      (ReadOnly.World.singleton cell source) callerEnvironment
      afterArguments := projectSingleton represented sourceFound
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) (ReadOnly.World.singleton cell source)
      calleeEnvironment callee := by
    simpa [callee, bindings] using
      singletonRepresented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  have functionalRun :=
    KeywordWorldSemantics.command_evaluates_singleton cell source start finish
      ordered inBounds sourceFitsI32
  have functionalEvaluation :=
    Lanius.FunctionalView.Stateful.Acyclic.run?_sound functionalRun
  let operations := operationSoundness verifiedFrontendCore Model.noCalls
    noCallsSound
  have simulation := commandSoundness operations functionalEvaluation
    (by native_decide) calleeRepresented
    (LayoutBelow.identity (arity := 3)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by
      simpa [callee, bindings] using
        (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [← KeywordCommand.recovered] at bodyExecution
  rw [keywordKindView_toCore_exactly] at bodyExecution
  change Executes verifiedFrontendCore callee keywordKindBody
    (.returned (some (.signed .i32
      (Model.keywordKind source start finish)))) completed at bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call keywordKindFunction.id (Core.toCoreExprs layout sourceArguments))
      (.signed .i32 (Model.keywordKind source start finish))
      (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned
      (bindings := bindings) (body := keywordKindBody)
      argumentsExecution verifiedFrontendCore_finds_keywordKind
    · simpa [bindings, calleeEnvironment] using
        keywordKindBindings cell source start finish
    · exact keywordKindFunction_has_body
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

/-- Premise-free checked-call correctness for the two canonical-token query
functions.  Each route is tied to the exact recovered source function. -/
theorem framePreservingCallSoundness :
    FramePreservingCallSoundness verifiedFrontendCore Model.callModel := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values value argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  rcases CallModelContracts.success evaluated with trivia | keyword
  · obtain ⟨kind, rfl, rfl, rfl, rfl⟩ := trivia
    exact isTriviaCall_executes kind afterArgumentsWellFormed represented
      argumentsExecution argumentsEffect
  · obtain ⟨source, cell, start, finish, sourceFound, rfl, rfl,
        ordered, inBounds, sourceFitsI32, rfl, rfl⟩ := keyword
    exact keywordKindCall_executes source cell start finish sourceFound ordered
      inBounds sourceFitsI32 afterArgumentsWellFormed represented
      argumentsExecution argumentsEffect

theorem callSoundness :
    EffectfulStateful.CallSoundness verifiedFrontendCore Model.callModel :=
  framePreservingCallSoundness.toCallSoundness
    CallModelContracts.worldPreserving

end Lanius.Extraction.CanonicalTokens.CheckedCalls
