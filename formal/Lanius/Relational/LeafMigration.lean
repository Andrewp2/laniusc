import Lanius.Relational.CoreReflection
import Lanius.Relational.ExecutableRefinement
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.Fuel

namespace Lanius.Relational.LeafMigration

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Relational.Semantics

/-! # Migration implementation for semantic leaves

This adapter is intentionally limited to expressions and small command
leaves. It uses an existing executable primitive model to produce one
canonical leaf result, then identifies that result with the supplied actual
Core leaf execution. The enclosing command and loop remain reflected from the
actual `CoreSuccess.StmtExecutes` tree, so no whole-command termination witness
or determinism argument is introduced.

The permanent replacement is direct registry-backed inversion at these same
leaf boundaries. Keeping this adapter in its own module makes that remaining
dependency explicit and mechanically searchable.
-/

theorem termReflectsWhen
    {program : Program} {calls : CallModel} {registry : OperationRegistry}
    {arity : Nat} {admissible : ReadOnly.World → Env arity → Prop}
    {expression : Term Core.signature arity}
    (operations : FramePreservingOperationSoundness program calls)
    (canonical : ∀ world environment,
      admissible world environment →
      ∃ value afterWorld,
        FunctionalView.Term.evaluate (Effectful.machine program calls)
          world environment expression = .ok (value, afterWorld))
    (relational : ∀ world environment
        (inputAdmissible : admissible world environment)
        value afterWorld,
      FunctionalView.Term.evaluate (Effectful.machine program calls)
          world environment expression = .ok (value, afterWorld) →
      TermEvaluates (registry.machine program) world environment expression
        value afterWorld) :
    CoreReflection.TermReflectsWhen program registry admissible expression := by
  intro layout localCell world environment before after frontier value wellFormed
    represented inputAdmissible actual
  obtain ⟨canonicalValue, afterWorld, evaluated⟩ :=
    canonical world environment inputAdmissible
  obtain ⟨canonicalAfter, canonicalExecution, afterWellFormed,
      afterRepresented, effect⟩ :=
    FreshSimulation.termSoundness operations wellFormed represented evaluated
  obtain ⟨valueEq, stateEq⟩ :=
    Lanius.Fuel.evaluates_deterministic actual canonicalExecution
  subst value
  subst after
  exact ⟨afterWorld,
    relational world environment inputAdmissible canonicalValue afterWorld
      evaluated,
    afterWellFormed, afterRepresented,
    effect.weaken CellSet.empty_subset⟩

/-- The analogous adapter for a small action-free command fragment. It is
useful for assignment leaves while the surrounding loop is reflected
structurally from the actual Core success tree. -/
theorem commandReflectsWhen
    {program : Program} {calls : CallModel} {registry : OperationRegistry}
    {arity : Nat} {admissible : ReadOnly.World → Env arity → Prop}
    {statement : Stateful.Command Core.signature Stateful.actions arity}
    (operations : FramePreservingOperationSoundness program calls)
    (canonical : ∀ world environment,
      admissible world environment →
      ∃ completion afterWorld afterEnvironment,
        Stateful.Command.Evaluates (Effectful.machine program calls)
          (machineWith program (Effectful.evaluateOperation program calls))
          world environment statement completion afterWorld afterEnvironment)
    (relational : ∀ world environment
        (inputAdmissible : admissible world environment)
        completion afterWorld afterEnvironment,
      Stateful.Command.Evaluates (Effectful.machine program calls)
          (machineWith program (Effectful.evaluateOperation program calls))
          world environment statement completion afterWorld afterEnvironment →
      Stateful.CommandEvaluates (registry.machine program) world environment
        statement completion afterWorld afterEnvironment) :
    CoreReflection.CommandReflectsWhen program registry statement admissible := by
  intro layout localCell nextLocal frontier world environment before after
    coreCompletion inputAdmissible actionFree represented below wellFormed
    localsFresh nextFresh actual
  obtain ⟨completion, afterWorld, afterEnvironment, evaluated⟩ :=
    canonical world environment inputAdmissible
  obtain ⟨canonicalAfter, canonicalExecution, afterWellFormed,
      afterRepresented, effect⟩ :=
    FreshSimulation.commandSoundness operations evaluated actionFree represented
      below wellFormed localsFresh nextFresh
  obtain ⟨completionEq, stateEq⟩ :=
    Lanius.Fuel.executes_deterministic actual.toExecutes canonicalExecution
  subst coreCompletion
  subst after
  exact ⟨completion, afterWorld, afterEnvironment,
    relational world environment inputAdmissible completion afterWorld
      afterEnvironment evaluated,
    rfl, afterWellFormed,
    afterRepresented, effect⟩

/-- Convenience specialization when executable and relational operations agree
globally. Partial contracts should normally use `termReflectsWhen` directly. -/
theorem termReflectsWhenOfAgreement
    {program : Program} {calls : CallModel} {registry : OperationRegistry}
    {arity : Nat} {admissible : ReadOnly.World → Env arity → Prop}
    {expression : Term Core.signature arity}
    (operations : FramePreservingOperationSoundness program calls)
    (agreement : ExecutableRefinement.OperationsAgree program calls registry)
    (canonical : ∀ world environment,
      admissible world environment →
      ∃ value afterWorld,
        FunctionalView.Term.evaluate (Effectful.machine program calls)
          world environment expression = .ok (value, afterWorld)) :
    CoreReflection.TermReflectsWhen program registry admissible expression :=
  termReflectsWhen operations canonical fun _ _ _ _ _ evaluated =>
    ExecutableRefinement.term agreement evaluated

/-- Command-fragment specialization for globally agreeing machines. -/
theorem commandReflectsWhenOfAgreement
    {program : Program} {calls : CallModel} {registry : OperationRegistry}
    {arity : Nat} {admissible : ReadOnly.World → Env arity → Prop}
    {statement : Stateful.Command Core.signature Stateful.actions arity}
    (operations : FramePreservingOperationSoundness program calls)
    (agreement : ExecutableRefinement.MachinesAgree program calls registry)
    (canonical : ∀ world environment,
      admissible world environment →
      ∃ completion afterWorld afterEnvironment,
        Stateful.Command.Evaluates (Effectful.machine program calls)
          (machineWith program (Effectful.evaluateOperation program calls))
          world environment statement completion afterWorld afterEnvironment) :
    CoreReflection.CommandReflectsWhen program registry statement admissible :=
  commandReflectsWhen operations canonical fun _ _ _ _ _ _ evaluated =>
    ExecutableRefinement.command agreement evaluated

end Lanius.Relational.LeafMigration
