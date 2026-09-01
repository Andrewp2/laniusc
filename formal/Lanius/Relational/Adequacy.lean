import Lanius.Relational.Reification
import Lanius.Relational.WP
import Lanius.Relational.SemanticWP
import Lanius.Relational.CoreReflection
import Lanius.Relational.ExecutableRefinement
import Lanius.Relational.CallContract
import Lanius.Relational.CallInversion
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCallFrame
import Lanius.Fuel

namespace Lanius.Relational

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Relational.Semantics

/-! # Inverse Core adequacy boundary

The existing generic simulator proves FunctionalView execution can be
implemented by Core. Partial correctness of an *actual successful* Core call
also needs this inverse direction. This module fixes that obligation's public
shape before its structural proof is implemented.
-/

/-- Successful execution of an exactly reified Core body can be reflected
back into the existing FunctionalView big-step semantics. This property is
deliberately body-local: generic call entry and restoration belong in the
separate checked-call inversion layer. -/
structure SuccessfulCoreRefinement
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {actions : Stateful.ActionSignature Core.signature}
    {arity : Nat}
    {command : Stateful.Command Core.signature actions arity}
    (reification : Reifies function command)
    (evaluateOperation : OperationEvaluator)
    (machine : Stateful.Machine (termMachine evaluateOperation) actions)
    (admissible : ReadOnly.World → Env arity → Prop) : Prop where
  refine : ∀ {beforeWorld : ReadOnly.World}
      {beforeEnvironment : Env arity}
      {before after : State}
      {localCell : Fin arity → CellId}
      {frontier : CellId}
      {coreCompletion : Lanius.Semantics.Completion},
    Representation reification.layout localCell beforeWorld
      beforeEnvironment before →
    admissible beforeWorld beforeEnvironment →
    StateWellFormed before →
    LocalsFresh frontier localCell →
    frontier ≤ before.nextCell →
    Executes program.core before function.body coreCompletion after →
    ∃ (completion : Stateful.Completion)
        (afterWorld : ReadOnly.World)
        (afterEnvironment : Env arity),
      Stateful.Command.Evaluates (termMachine evaluateOperation) machine beforeWorld
        beforeEnvironment command completion afterWorld afterEnvironment ∧
      Stateful.toCoreCompletion completion = coreCompletion ∧
      StateWellFormed after ∧
      Representation reification.layout localCell afterWorld afterEnvironment
        after ∧
      ModifiesOnly (freshCells frontier) before after

/-- The existing forward fresh-cell simulation yields inverse adequacy for
successful executions once the proof semantics can produce a canonical
execution.  Core and FunctionalView determinism identify the supplied actual
execution with that canonical run.  Unlike the migration call bridge, this is
body-generic and does not assume a function-specific Core call theorem. -/
theorem SuccessfulCoreRefinement.ofFreshSimulation
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {arity : Nat}
    {command : Stateful.Command Core.signature Stateful.actions arity}
    {calls : Effectful.CallModel}
    (reification : Reifies function command)
    (admissible : ReadOnly.World → Env arity → Prop)
    (adapterExact : reification.adapter = actionAdapter)
    (operations : FramePreservingOperationSoundness program.core
      calls)
    (actionFree : FreshSimulation.actionFree command = true)
    (terminates : ∀ (world : ReadOnly.World) (environment : Env arity),
      admissible world environment →
      ∃ completion afterWorld afterEnvironment,
        Stateful.Command.Evaluates
          (termMachine (Effectful.evaluateOperation program.core calls))
          (machineWith program.core
            (Effectful.evaluateOperation program.core calls))
          world environment command completion afterWorld afterEnvironment) :
    SuccessfulCoreRefinement reification
      (Effectful.evaluateOperation program.core calls)
      (machineWith program.core
        (Effectful.evaluateOperation program.core calls)) admissible := by
  constructor
  intro beforeWorld beforeEnvironment before after localCell frontier
    coreCompletion represented inputAdmissible wellFormed localsFresh nextFresh
    executed
  obtain ⟨completion, afterWorld, afterEnvironment, evaluated⟩ :=
    terminates beforeWorld beforeEnvironment inputAdmissible
  have simulated := FreshSimulation.commandSoundness operations evaluated
    actionFree represented reification.below wellFormed localsFresh nextFresh
  obtain ⟨canonicalAfter, canonicalExecution, canonicalWellFormed,
      canonicalRepresented, canonicalEffect⟩ := simulated
  have exactBody : Stateful.toCoreStmt actionAdapter reification.layout
      reification.nextLocal command = function.body := by
    simpa [adapterExact] using reification.exact
  rw [exactBody] at canonicalExecution
  obtain ⟨completionEq, stateEq⟩ :=
    Lanius.Fuel.executes_deterministic canonicalExecution executed
  subst coreCompletion
  subst after
  exact ⟨completion, afterWorld, afterEnvironment, evaluated, rfl,
    canonicalWellFormed, canonicalRepresented, canonicalEffect⟩

/-- Once inverse adequacy exists, the semantic WP immediately yields the
postcondition for every successful execution of the exact checked body. -/
theorem wp_toCore_sound
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {actions : Stateful.ActionSignature Core.signature}
    {arity : Nat}
    {command : Stateful.Command Core.signature actions arity}
    {evaluateOperation : OperationEvaluator}
    {machine : Stateful.Machine (termMachine evaluateOperation) actions}
    {admissible : ReadOnly.World → Env arity → Prop}
    {post : Command.Postcondition ReadOnly.World arity}
    (reification : Reifies function command)
    (adequate : SuccessfulCoreRefinement reification evaluateOperation machine
      admissible)
    {beforeWorld : ReadOnly.World} {beforeEnvironment : Env arity}
    {before after : State} {localCell : Fin arity → CellId}
    {frontier : CellId}
    {coreCompletion : Lanius.Semantics.Completion}
    (wp : Command.WP (termMachine evaluateOperation) machine command post beforeWorld
      beforeEnvironment)
    (represented : Representation reification.layout localCell beforeWorld
      beforeEnvironment before)
    (inputAdmissible : admissible beforeWorld beforeEnvironment)
    (wellFormed : StateWellFormed before)
    (localsFresh : LocalsFresh frontier localCell)
    (nextFresh : frontier ≤ before.nextCell)
    (executed : Executes program.core before function.body coreCompletion
      after) :
    ∃ (completion : Stateful.Completion)
        (afterWorld : ReadOnly.World)
        (afterEnvironment : Env arity),
      Stateful.toCoreCompletion completion = coreCompletion ∧
      StateWellFormed after ∧
      Representation reification.layout localCell afterWorld afterEnvironment
        after ∧
      ModifiesOnly (freshCells frontier) before after ∧
      post completion afterWorld afterEnvironment := by
  obtain ⟨completion, afterWorld, afterEnvironment, evaluated,
      completionEq, afterWellFormed, afterRepresented, effect⟩ :=
    adequate.refine represented inputAdmissible wellFormed localsFresh nextFresh
      executed
  exact ⟨completion, afterWorld, afterEnvironment, completionEq,
    afterWellFormed, afterRepresented, effect, wp _ _ _ evaluated⟩

/-! ## Structural relational adequacy

The executable-semantics bridge above remains available during migration.
New proofs use the relational bridge below. It reflects the supplied successful
Core run structurally and therefore needs neither a termination witness nor a
determinism argument.
-/

structure RelationalSuccessfulCoreRefinement
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {arity : Nat}
    {command : Stateful.Command Core.signature Stateful.actions arity}
    (reification : Reifies function command)
    (registry : OperationRegistry)
    (admissible : ReadOnly.World → Env arity → Prop) : Prop where
  refine : ∀ {beforeWorld : ReadOnly.World}
      {beforeEnvironment : Env arity}
      {before after : State}
      {localCell : Fin arity → CellId}
      {frontier : CellId}
      {coreCompletion : Lanius.Semantics.Completion},
    Representation reification.layout localCell beforeWorld
      beforeEnvironment before →
    admissible beforeWorld beforeEnvironment →
    StateWellFormed before →
    LocalsFresh frontier localCell →
    frontier ≤ before.nextCell →
    Executes program.core before function.body coreCompletion after →
    CoreReflection.Reflects program.core registry reification.layout localCell
      frontier beforeWorld beforeEnvironment before after command coreCompletion

theorem RelationalSuccessfulCoreRefinement.structural
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {arity : Nat}
    {command : Stateful.Command Core.signature Stateful.actions arity}
    {registry : OperationRegistry}
    (reification : Reifies function command)
    (adapterExact : reification.adapter = actionAdapter)
    (leaves : CoreReflection.CommandLeaves program.core registry command) :
    RelationalSuccessfulCoreRefinement reification registry
      (fun _ _ => True) := by
  constructor
  intro beforeWorld beforeEnvironment before after localCell frontier
    coreCompletion represented _admissible wellFormed localsFresh nextFresh
      executed
  have exactBody : Stateful.toCoreStmt actionAdapter reification.layout
      reification.nextLocal command = function.body := by
    simpa [adapterExact] using reification.exact
  rw [← exactBody] at executed
  exact CoreReflection.ofExecutes leaves leaves.actionFree represented
    reification.below wellFormed localsFresh nextFresh executed

/-- Invariant-aware structural adequacy for partial operation contracts.  The
certificate is still command-structural, but unlike `CommandLeaves` it may use
the entry invariant to justify the contracts reached inside loops. -/
theorem RelationalSuccessfulCoreRefinement.structuralWhen
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {arity : Nat}
    {command : Stateful.Command Core.signature Stateful.actions arity}
    {registry : OperationRegistry}
    {admissible : ReadOnly.World → Env arity → Prop}
    (reification : Reifies function command)
    (adapterExact : reification.adapter = actionAdapter)
    (actionFree : FreshSimulation.actionFree command = true)
    (reflection : CoreReflection.CommandReflectsWhen program.core registry
      command admissible) :
    RelationalSuccessfulCoreRefinement reification registry admissible := by
  constructor
  intro beforeWorld beforeEnvironment before after localCell frontier
    coreCompletion represented inputAdmissible wellFormed localsFresh nextFresh
    executed
  have exactBody : Stateful.toCoreStmt actionAdapter reification.layout
      reification.nextLocal command = function.body := by
    simpa [adapterExact] using reification.exact
  rw [← exactBody] at executed
  exact reflection.ofExecutes inputAdmissible actionFree represented
    reification.below wellFormed localsFresh nextFresh executed

/-- Explicit migration adapter for proofs that still obtain inverse adequacy
through the executable FunctionalView semantics.  New structural proofs should
use `RelationalSuccessfulCoreRefinement.structural`; keeping this conversion
named and isolated prevents `CallModel` and executable command derivations from
escaping into algorithm proofs. -/
theorem RelationalSuccessfulCoreRefinement.ofExecutable
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {arity : Nat}
    {command : Stateful.Command Core.signature Stateful.actions arity}
    {calls : Effectful.CallModel}
    {registry : OperationRegistry}
    {admissible : ReadOnly.World → Env arity → Prop}
    (reification : Reifies function command)
    (executable : SuccessfulCoreRefinement reification
      (Effectful.evaluateOperation program.core calls)
      (machineWith program.core
        (Effectful.evaluateOperation program.core calls)) admissible)
    (agreement : ExecutableRefinement.MachinesAgree program.core calls
      registry) :
    RelationalSuccessfulCoreRefinement reification registry admissible := by
  constructor
  intro beforeWorld beforeEnvironment before after localCell frontier
    coreCompletion represented inputAdmissible wellFormed localsFresh nextFresh
    executed
  obtain ⟨completion, afterWorld, afterEnvironment, evaluated, completionEq,
      afterWellFormed, afterRepresented, effect⟩ :=
    executable.refine represented inputAdmissible wellFormed localsFresh
      nextFresh executed
  exact ⟨completion, afterWorld, afterEnvironment,
    ExecutableRefinement.command agreement evaluated, completionEq,
    afterWellFormed, afterRepresented, effect⟩

theorem relational_wp_toCore_sound
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {arity : Nat}
    {command : Stateful.Command Core.signature Stateful.actions arity}
    {registry : OperationRegistry}
    {admissible : ReadOnly.World → Env arity → Prop}
    {post : SemanticWP.Command.Postcondition ReadOnly.World arity}
    (reification : Reifies function command)
    (adequate : RelationalSuccessfulCoreRefinement reification registry
      admissible)
    {beforeWorld : ReadOnly.World} {beforeEnvironment : Env arity}
    {before after : State} {localCell : Fin arity → CellId}
    {frontier : CellId}
    {coreCompletion : Lanius.Semantics.Completion}
    (wp : SemanticWP.Command.WP (registry.machine program.core) command post
      beforeWorld beforeEnvironment)
    (represented : Representation reification.layout localCell beforeWorld
      beforeEnvironment before)
    (inputAdmissible : admissible beforeWorld beforeEnvironment)
    (wellFormed : StateWellFormed before)
    (localsFresh : LocalsFresh frontier localCell)
    (nextFresh : frontier ≤ before.nextCell)
    (executed : Executes program.core before function.body coreCompletion after) :
    ∃ completion afterWorld afterEnvironment,
      Stateful.toCoreCompletion completion = coreCompletion ∧
      StateWellFormed after ∧
      Representation reification.layout localCell afterWorld afterEnvironment
        after ∧
      ModifiesOnly (freshCells frontier) before after ∧
      post completion afterWorld afterEnvironment := by
  obtain ⟨completion, afterWorld, afterEnvironment, evaluated, completionEq,
      afterWellFormed, afterRepresented, effect⟩ :=
    adequate.refine represented inputAdmissible wellFormed localsFresh nextFresh
      executed
  exact ⟨completion, afterWorld, afterEnvironment, completionEq,
    afterWellFormed, afterRepresented, effect, wp _ _ _ evaluated⟩

/-- Checked call-entry data kept at the generic adequacy boundary.  The
algorithm-facing contract never mentions parameter variable IDs or physical
callee cells. -/
structure CallABI
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {actions : Stateful.ActionSignature Core.signature}
    {arity : Nat} {command : Stateful.Command Core.signature actions arity}
    (contract : FnContract program signature function)
    (reification : Reifies function command) where
  environment : contract.Args → Env arity
  proofWorld : contract.Args → contract.AbstractState → ReadOnly.World →
    ReadOnly.World
  parametersBound : ∀ args,
    bindParameters function.function.parameters (contract.encodeArgs args) =
      some (parameterBindings (environment args))
  projectCallee : ∀ {callerArity : Nat} {layout : Layout callerArity}
      {localCell : Fin callerArity → CellId}
      {callerEnvironment : Env callerArity}
      {beforeWorld : ReadOnly.World} {afterArguments : State}
      (args : contract.Args) (abstractBefore : contract.AbstractState),
    contract.Pre args abstractBefore →
    contract.AbstractStateRep abstractBefore beforeWorld →
    StateWellFormed afterArguments →
    Representation layout localCell beforeWorld callerEnvironment
      afterArguments →
    Representation reification.layout (callLocalCells afterArguments)
      (proofWorld args abstractBefore beforeWorld) (environment args)
      (enterCall afterArguments (parameterBindings (environment args)))

/-- Generic partial-correctness bridge for successful, value-returning checked
read-only calls. It inverts the actual Core call, applies inverse body adequacy
and the command WP, and closes the fresh callee frame. Mutable contracts need
the analogous owned-world frame rule rather than this read-only specialization.
-/
theorem ReturnsCorrectly.ofReadOnlyWP
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {contract : FnContract program signature function}
    {actions : Stateful.ActionSignature Core.signature}
    {arity : Nat} {command : Stateful.Command Core.signature actions arity}
    {evaluateOperation : OperationEvaluator}
    {machine : Stateful.Machine (termMachine evaluateOperation) actions}
    {admissible : ReadOnly.World → Env arity → Prop}
    (reification : Reifies function command)
    (abi : CallABI contract reification)
    (resultNotUnit : signature.result ≠ .unit)
    (adequate : SuccessfulCoreRefinement reification evaluateOperation machine
      admissible)
    (bodyAdmissible : ∀ (args : contract.Args)
        (abstractBefore : contract.AbstractState)
        (beforeWorld : ReadOnly.World),
      contract.Pre args abstractBefore →
      contract.AbstractStateRep abstractBefore beforeWorld →
      admissible (abi.proofWorld args abstractBefore beforeWorld)
        (abi.environment args))
    (postRep : ∀ (args : contract.Args)
        (result : contract.Result)
        (abstractBefore abstractAfter : contract.AbstractState)
        (beforeWorld : ReadOnly.World),
      contract.Pre args abstractBefore →
      contract.AbstractStateRep abstractBefore beforeWorld →
      contract.Post args result abstractBefore abstractAfter →
      contract.Frame abstractBefore abstractAfter →
      contract.AbstractStateRep abstractAfter beforeWorld)
    (bodyWP : ∀ (args : contract.Args)
        (abstractBefore : contract.AbstractState)
        (beforeWorld : ReadOnly.World),
      contract.Pre args abstractBefore →
      contract.AbstractStateRep abstractBefore beforeWorld →
      Command.WP (termMachine evaluateOperation) machine command
        (fun completion afterWorld _afterEnvironment =>
          ∃ result abstractAfter,
            completion = .returned (some (contract.encodeResult result)) ∧
            afterWorld = abi.proofWorld args abstractBefore beforeWorld ∧
            contract.AbstractStateRep abstractAfter afterWorld ∧
            contract.Post args result abstractBefore abstractAfter ∧
            contract.Frame abstractBefore abstractAfter)
        (abi.proofWorld args abstractBefore beforeWorld)
        (abi.environment args)) :
    ReturnsCorrectly contract := by
  intro callerArity layout localCell callerEnvironment beforeWorld before
    afterArguments actualAfter arguments argumentWrites actualValue args
    abstractBefore pre abstractBeforeRep afterArgumentsWellFormed represented
    argumentsExecution argumentsEffect actualExecution
  have returnsValue : function.function.returnType ≠ .unit := by
    rw [function.resultType]
    exact resultNotUnit
  obtain ⟨actualArguments, actualAfterArguments, bindings, completed,
      actualArgumentsExecution, parametersBound, bodyExecution,
      actualAfterEq⟩ := evaluatesCallReturned_invert function.found
        function.bodyFound returnsValue actualExecution
  obtain ⟨argumentsEq, afterArgumentsEq⟩ :=
    argumentsEvaluateTo_deterministic actualArgumentsExecution
      argumentsExecution
  subst actualArguments
  subst actualAfterArguments
  have bindingsEq : bindings = parameterBindings (abi.environment args) := by
    rw [abi.parametersBound args] at parametersBound
    exact Option.some.inj parametersBound.symm
  subst bindings
  have calleeRepresented : Representation reification.layout
      (callLocalCells afterArguments)
      (abi.proofWorld args abstractBefore beforeWorld) (abi.environment args)
      (enterCall afterArguments (parameterBindings (abi.environment args))) := by
    exact abi.projectCallee args abstractBefore pre abstractBeforeRep
      afterArgumentsWellFormed represented
  have calleeWellFormed : StateWellFormed
      (enterCall afterArguments (parameterBindings (abi.environment args))) :=
    enterCall_preserves_wellFormed afterArgumentsWellFormed
  have localsFresh : LocalsFresh afterArguments.nextCell
      (callLocalCells (arity := arity) afterArguments) := by
    intro index
    simp [callLocalCells]
  have nextFresh : afterArguments.nextCell ≤
      (enterCall afterArguments
        (parameterBindings (abi.environment args))).nextCell := by
    exact (enterCall_effect afterArguments
      (parameterBindings (abi.environment args))).nextCell
  obtain ⟨completion, afterWorld, afterEnvironment, completionEq,
      completedWellFormed, completedRepresented, bodyEffect,
      result, abstractAfter, completionShape, afterWorldEq, abstractAfterRep,
      post, frame⟩ :=
    wp_toCore_sound reification adequate (bodyWP args abstractBefore beforeWorld
      pre abstractBeforeRep) calleeRepresented
      (bodyAdmissible args abstractBefore beforeWorld pre abstractBeforeRep)
      calleeWellFormed localsFresh nextFresh bodyExecution
  rw [completionShape] at completionEq
  have valueEq : actualValue = contract.encodeResult result := by
    injection completionEq with same
    exact Option.some.inj same.symm
  have abstractAfterRepAtCaller :
      contract.AbstractStateRep abstractAfter beforeWorld :=
    postRep args result abstractBefore abstractAfter beforeWorld pre
      abstractBeforeRep post frame
  obtain ⟨restoredWellFormed, restoredRepresented, restoredEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed completedWellFormed
      bodyEffect (by intro _ written; exact written)
  subst actualAfter
  exact ⟨result, abstractAfter, beforeWorld, valueEq,
    abstractAfterRepAtCaller, post,
    frame, restoredWellFormed, restoredRepresented,
    argumentsEffect.trans_same
      (restoredEffect.weaken CellSet.empty_subset)⟩

/-- Relational counterpart of `ofReadOnlyWP`.  This is the default bridge for
new proofs: the body WP ranges over relational calls and the adequacy proof is
structural, so neither executable call models nor command termination enter the
function theorem. -/
theorem ReturnsCorrectly.ofRelationalReadOnlyWP
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {contract : FnContract program signature function}
    {arity : Nat}
    {command : Stateful.Command Core.signature Stateful.actions arity}
    {registry : OperationRegistry}
    {admissible : ReadOnly.World → Env arity → Prop}
    (reification : Reifies function command)
    (abi : CallABI contract reification)
    (resultNotUnit : signature.result ≠ .unit)
    (adequate : RelationalSuccessfulCoreRefinement reification registry
      admissible)
    (bodyAdmissible : ∀ (args : contract.Args)
        (abstractBefore : contract.AbstractState)
        (beforeWorld : ReadOnly.World),
      contract.Pre args abstractBefore →
      contract.AbstractStateRep abstractBefore beforeWorld →
      admissible (abi.proofWorld args abstractBefore beforeWorld)
        (abi.environment args))
    (postRep : ∀ (args : contract.Args)
        (result : contract.Result)
        (abstractBefore abstractAfter : contract.AbstractState)
        (beforeWorld : ReadOnly.World),
      contract.Pre args abstractBefore →
      contract.AbstractStateRep abstractBefore beforeWorld →
      contract.Post args result abstractBefore abstractAfter →
      contract.Frame abstractBefore abstractAfter →
      contract.AbstractStateRep abstractAfter beforeWorld)
    (bodyWP : ∀ (args : contract.Args)
        (abstractBefore : contract.AbstractState)
        (beforeWorld : ReadOnly.World),
      contract.Pre args abstractBefore →
      contract.AbstractStateRep abstractBefore beforeWorld →
      SemanticWP.Command.WP (registry.machine program.core) command
        (fun completion afterWorld _afterEnvironment =>
          ∃ result abstractAfter,
            completion = .returned (some (contract.encodeResult result)) ∧
            afterWorld = abi.proofWorld args abstractBefore beforeWorld ∧
            contract.AbstractStateRep abstractAfter afterWorld ∧
            contract.Post args result abstractBefore abstractAfter ∧
            contract.Frame abstractBefore abstractAfter)
        (abi.proofWorld args abstractBefore beforeWorld)
        (abi.environment args)) :
    ReturnsCorrectly contract := by
  intro callerArity layout localCell callerEnvironment beforeWorld before
    afterArguments actualAfter arguments argumentWrites actualValue args
    abstractBefore pre abstractBeforeRep afterArgumentsWellFormed represented
    argumentsExecution argumentsEffect actualExecution
  have returnsValue : function.function.returnType ≠ .unit := by
    rw [function.resultType]
    exact resultNotUnit
  obtain ⟨actualArguments, actualAfterArguments, bindings, completed,
      actualArgumentsExecution, parametersBound, bodyExecution,
      actualAfterEq⟩ := evaluatesCallReturned_invert function.found
        function.bodyFound returnsValue actualExecution
  obtain ⟨argumentsEq, afterArgumentsEq⟩ :=
    argumentsEvaluateTo_deterministic actualArgumentsExecution
      argumentsExecution
  subst actualArguments
  subst actualAfterArguments
  have bindingsEq : bindings = parameterBindings (abi.environment args) := by
    rw [abi.parametersBound args] at parametersBound
    exact Option.some.inj parametersBound.symm
  subst bindings
  have calleeRepresented : Representation reification.layout
      (callLocalCells afterArguments)
      (abi.proofWorld args abstractBefore beforeWorld) (abi.environment args)
      (enterCall afterArguments (parameterBindings (abi.environment args))) := by
    exact abi.projectCallee args abstractBefore pre abstractBeforeRep
      afterArgumentsWellFormed represented
  have calleeWellFormed : StateWellFormed
      (enterCall afterArguments (parameterBindings (abi.environment args))) :=
    enterCall_preserves_wellFormed afterArgumentsWellFormed
  have localsFresh : LocalsFresh afterArguments.nextCell
      (callLocalCells (arity := arity) afterArguments) := by
    intro index
    simp [callLocalCells]
  have nextFresh : afterArguments.nextCell ≤
      (enterCall afterArguments
        (parameterBindings (abi.environment args))).nextCell := by
    exact (enterCall_effect afterArguments
      (parameterBindings (abi.environment args))).nextCell
  obtain ⟨completion, afterWorld, afterEnvironment, completionEq,
      completedWellFormed, completedRepresented, bodyEffect,
      result, abstractAfter, completionShape, afterWorldEq, abstractAfterRep,
      post, frame⟩ :=
    relational_wp_toCore_sound reification adequate
      (bodyWP args abstractBefore beforeWorld pre abstractBeforeRep)
      calleeRepresented
      (bodyAdmissible args abstractBefore beforeWorld pre abstractBeforeRep)
      calleeWellFormed localsFresh nextFresh bodyExecution
  rw [completionShape] at completionEq
  have valueEq : actualValue = contract.encodeResult result := by
    injection completionEq with same
    exact Option.some.inj same.symm
  have abstractAfterRepAtCaller :
      contract.AbstractStateRep abstractAfter beforeWorld :=
    postRep args result abstractBefore abstractAfter beforeWorld pre
      abstractBeforeRep post frame
  obtain ⟨restoredWellFormed, restoredRepresented, restoredEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed completedWellFormed
      bodyEffect (by intro _ written; exact written)
  subst actualAfter
  exact ⟨result, abstractAfter, beforeWorld, valueEq,
    abstractAfterRepAtCaller, post, frame, restoredWellFormed,
    restoredRepresented, argumentsEffect.trans_same
      (restoredEffect.weaken CellSet.empty_subset)⟩

end Lanius.Relational
