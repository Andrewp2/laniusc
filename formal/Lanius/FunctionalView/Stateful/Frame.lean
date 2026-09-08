import Lanius.FunctionalView.Stateful.ActionFrame

namespace Lanius.FunctionalView.StatefulFrame

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView Lanius.FunctionalView.Core Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful Lanius.FunctionalView.FreshSimulation
open Lanius.FunctionalView.Core.Effectful

/-- Existing slice resources plus temporary callee cells are the complete
    physical write boundary. No anonymous existential write set is hidden. -/
def writes (world : ReadOnly.World) (frontier : CellId) : CellSet :=
  CellSet.union (ReadOnly.World.owns world).footprint (freshCells frontier)

private theorem writes_eq
    (same : (ReadOnly.World.owns afterWorld).footprint = (ReadOnly.World.owns beforeWorld).footprint) :
    writes afterWorld frontier = writes beforeWorld frontier :=
  congrArg (fun footprint => CellSet.union footprint (freshCells frontier)) same

def SimulatesFramed
    (program : Program) (frontier : CellId) (layout : Layout arity)
    (localCell : Fin arity → CellId)
    (beforeWorld : ReadOnly.World) (beforeEnvironment : Env arity)
    (before : State) (command : Command Core.signature actions arity)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (afterWorld : ReadOnly.World) (afterEnvironment : Env arity)
    (nextLocal : VarId) : Prop :=
  ∃ after,
    Executes program before
      (toCoreStmt actionAdapter layout nextLocal command)
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion) after ∧
    StateWellFormed after ∧
    Representation layout localCell afterWorld afterEnvironment after ∧
    ModifiesOnly (writes beforeWorld frontier) before after

theorem command_executes
    {arity : Nat} {program : Program} {calls : CallModel}
    {world afterWorld : ReadOnly.World}
    {environment afterEnvironment : Env arity}
    {command : Command Core.signature actions arity}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (registry : EffectfulStateful.CallSoundness program calls)
    (operations : FramePreservingOperationSoundness program calls)
    (evaluated : Command.Evaluates (Effectful.machine program calls)
      (machineWith program (Effectful.evaluateOperation program calls))
      world environment command completion afterWorld afterEnvironment) :
    ∀ {frontier : CellId} {layout : Layout arity} {state : State}
      {localCell : Fin arity → CellId} {nextLocal : VarId},
      Representation layout localCell world environment state →
      LayoutBelow layout nextLocal →
      StateWellFormed state →
      LocalsFresh frontier localCell →
      frontier ≤ state.nextCell →
      SimulatesFramed program frontier layout localCell world environment state
        command completion afterWorld afterEnvironment nextLocal := by
  let motive : {arity : Nat} →
      (world : ReadOnly.World) → (environment : Env arity) →
      (command : Command Core.signature actions arity) →
      (completion : Lanius.FunctionalView.Stateful.Completion) →
      (afterWorld : ReadOnly.World) → (afterEnvironment : Env arity) →
      Command.Evaluates (Effectful.machine program calls)
        (machineWith program (Effectful.evaluateOperation program calls))
        world environment command completion afterWorld afterEnvironment → Prop :=
    fun {arity} world environment command completion afterWorld
      afterEnvironment _ =>
      ∀ {frontier : CellId} {layout : Layout arity} {state : State}
        {localCell : Fin arity → CellId} {nextLocal : VarId},
        Representation layout localCell world environment state →
        LayoutBelow layout nextLocal →
        StateWellFormed state →
        LocalsFresh frontier localCell →
        frontier ≤ state.nextCell →
        SimulatesFramed program frontier layout localCell world environment state
          command completion afterWorld afterEnvironment nextLocal
  change motive world environment command completion afterWorld
    afterEnvironment evaluated
  apply @Command.Evaluates.rec Core.signature actions
    (Effectful.machine program calls)
    (machineWith program (Effectful.evaluateOperation program calls)) motive
  case skip =>
      intro _world _arity _environment  frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      exact ⟨state, executesSkip program state, wellFormed, represented,
        (ModifiesOnly.refl state).weaken CellSet.empty_subset⟩
  case sequenceNext =>
      intro _beforeWorld _arity _beforeEnvironment firstCommand _middleWorld
        _middleEnvironment secondCommand _completion _afterWorld
        _afterEnvironment _firstResult _secondResult firstInduction
        secondInduction  frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      obtain ⟨middle, firstExecution, middleWellFormed, middleRepresented,
        firstEffect⟩ := firstInduction represented below wellFormed
          localsFresh nextFresh
      have secondBelow := below.mono
        (Nat.le_add_right nextLocal (localCapacity actionAdapter firstCommand))
      obtain ⟨after, secondExecution, afterWellFormed, afterRepresented,
        secondEffect⟩ := secondInduction  middleRepresented secondBelow
          middleWellFormed localsFresh
          (Nat.le_trans nextFresh firstEffect.nextCell)
      rw [writes_eq (command_footprint registry _firstResult)] at secondEffect
      exact ⟨after, executesSequence firstExecution secondExecution,
        afterWellFormed, afterRepresented,
        firstEffect.trans_same secondEffect⟩
  case sequenceStop =>
      intro _beforeWorld _arity _beforeEnvironment firstCommand completion
        _afterWorld _afterEnvironment secondCommand _firstResult stops
        firstInduction  frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
        firstInduction represented below wellFormed localsFresh nextFresh
      exact ⟨after, executesSequenceNonNext execution (by
        intro same
        apply stops
        cases completion <;>
          simp_all [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]),
        afterWellFormed, afterRepresented, effect⟩
  case letValue =>
      intro beforeWorld branchArity beforeEnvironment initializer value
        initializedWorld body completion afterWorld extendedEnvironment type
        initializerResult bodyResult induction  frontier layout state
        localCell nextLocal represented below wellFormed localsFresh nextFresh
      obtain ⟨initialized, initializerExecution, initializedWellFormed,
          initializedRepresented, initializerEffect⟩ :=
        termSoundness operations wellFormed represented initializerResult
      let bound := initialized.bindLocal nextLocal value
      let boundCells := pushCells localCell initialized.nextCell
      have boundWellFormed := bindLocal_preserves_well_formed initialized
        nextLocal value initializedWellFormed
      have boundRepresented : Representation (Layout.push layout nextLocal)
          boundCells initializedWorld (beforeEnvironment.push value) bound := by
        simpa [bound, boundCells] using
          initializedRepresented.bindLocal below initializedWellFormed value
      have boundFresh : LocalsFresh frontier boundCells := by
        intro index
        simp only [boundCells, pushCells]
        split
        · exact localsFresh _
        · exact Nat.le_trans nextFresh initializerEffect.nextCell
      have boundNextFresh : frontier ≤ bound.nextCell := by
        simp [bound, State.bindLocal, State.bindCell]
        exact Nat.le_trans nextFresh
          (Nat.le_trans initializerEffect.nextCell (Nat.le_succ _))
      obtain ⟨completed, bodyExecution, completedWellFormed,
          completedRepresented, bodyEffect⟩ :=
        induction  boundRepresented below.push boundWellFormed boundFresh
          boundNextFresh
      let after := restoreLocals initialized completed
      have scopeEffect : ModifiesOnly (writes initializedWorld frontier) initialized after :=
        temporaryLocal_effect nextLocal value bodyEffect.toStoreEffect
      have afterWellFormed : StateWellFormed after := by
        have entered : StoreEffect (writes initializedWorld frontier) initialized bound :=
          (bindLocal_effect initialized nextLocal value).weaken
            CellSet.empty_subset
        simpa [after] using
          (entered.trans_same bodyEffect.toStoreEffect).restoreLocals_wellFormed
            initializedWellFormed completedWellFormed
      have afterRepresented : Representation layout localCell afterWorld
          (Env.pop extendedEnvironment) after := by
        refine {
          worldOwned := ?_
          localOwned := ?_
          localCellsInjective := initializedRepresented.localCellsInjective
          worldLocalsDisjoint := ?_
        }
        · intro cell values found
          simpa [after, restoreLocals, State.cellEntry?] using
            completedRepresented.worldOwned cell values found
        · intro index
          let lifted : Fin (branchArity + 1) :=
            ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
          have owned := completedRepresented.localOwned lifted
          constructor
          · simpa [after, restoreLocals, State.cellId?] using
              (initializedRepresented.localOwned index).1
          · simpa [after, restoreLocals, State.cellEntry?, boundCells,
              pushCells, lifted, Env.pop] using owned.2
        · intro cell worldMember localMember
          exact completedRepresented.worldLocalsDisjoint cell worldMember (by
            obtain ⟨index, same⟩ := localMember
            let lifted : Fin (branchArity + 1) :=
              ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
            exact ⟨lifted, by
              simpa [boundCells, pushCells, lifted] using same⟩)
      rw [writes_eq (term_footprint registry initializerResult)] at scopeEffect
      exact ⟨after, executesLetLocal initializerExecution bodyExecution,
        afterWellFormed, afterRepresented,
        (initializerEffect.weaken CellSet.empty_subset).trans_same scopeEffect⟩
  case setLocal =>
      intro _beforeWorld _arity _beforeEnvironment _value _result _afterWorld
        target valueResult  frontier layout state localCell nextLocal
       represented below wellFormed localsFresh nextFresh
      obtain ⟨afterRight, rightExecution, rightWellFormed, rightRepresented,
          rightEffect⟩ :=
        termSoundness operations wellFormed represented valueResult
      obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
       represented.setLocalAfterTerm rightRepresented rightExecution
          rightWellFormed rightEffect
      exact ⟨after, executesExpression execution, afterWellFormed,
        afterRepresented, effect.weaken (by
          intro cell member
          rcases member with impossible | written
          · exact False.elim impossible
          · simp [CellSet.singleton] at written
            subst cell
            exact Or.inr (localsFresh target))⟩
  case updateLocal =>
      intro _beforeWorld _arity _beforeEnvironment _value _right _afterWorld
        operation target _result valueResult updateResult  frontier layout
        state localCell nextLocal represented below wellFormed localsFresh
        nextFresh
      obtain ⟨afterRight, rightExecution, rightWellFormed, rightRepresented,
          rightEffect⟩ :=
        termSoundness operations wellFormed represented valueResult
      obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
       represented.updateLocalAfterTerm rightRepresented rightExecution
          rightWellFormed rightEffect updateResult
      exact ⟨after, executesExpression execution, afterWellFormed,
        afterRepresented, effect.weaken (by
          intro cell member
          rcases member with impossible | written
          · exact False.elim impossible
          · simp [CellSet.singleton] at written
            subst cell
            exact Or.inr (localsFresh target))⟩
  case action =>
      intro world arity environment operation afterWorld actionResult frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      obtain ⟨after, execution, afterWF, afterRepresented, effect⟩ :=
        action_executes registry operations wellFormed represented actionResult
      exact ⟨after, execution, afterWF, afterRepresented, effect.weaken CellSet.subset_union_left⟩
  case ifTrue =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        thenBranch _completion _afterWorld _afterEnvironment elseBranch
        conditionResult _branchResult induction  frontier layout state
        localCell nextLocal represented below wellFormed localsFresh nextFresh
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨after, branchExecution, afterWellFormed, afterRepresented,
          branchEffect⟩ :=
        induction  conditionRepresented below conditionWellFormed
          localsFresh (Nat.le_trans nextFresh conditionEffect.nextCell)
      rw [writes_eq (term_footprint registry conditionResult)] at branchEffect
      exact ⟨after, executesIfTrue conditionExecution branchExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same branchEffect⟩
  case ifFalse =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        elseBranch _completion _afterWorld _afterEnvironment thenBranch
        conditionResult _branchResult induction  frontier layout state
        localCell nextLocal represented below wellFormed localsFresh nextFresh
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨after, branchExecution, afterWellFormed, afterRepresented,
          branchEffect⟩ :=
        induction  conditionRepresented below conditionWellFormed
          localsFresh (Nat.le_trans nextFresh conditionEffect.nextCell)
      rw [writes_eq (term_footprint registry conditionResult)] at branchEffect
      exact ⟨after, executesIfFalse conditionExecution branchExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same branchEffect⟩
  case whileFalse =>
      intro _beforeWorld _arity _beforeEnvironment _condition _afterWorld body
        conditionResult  frontier layout state localCell nextLocal
       represented below wellFormed localsFresh nextFresh
      obtain ⟨after, conditionExecution, afterWellFormed, afterRepresented,
          conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      exact ⟨after, executesWhileFalse conditionExecution, afterWellFormed,
        afterRepresented, conditionEffect.weaken CellSet.empty_subset⟩
  case whileNext =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        body _bodyWorld _bodyEnvironment _completion _afterWorld
        _afterEnvironment conditionResult _bodyResult _restResult bodyInduction
        restInduction  frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨middle, bodyExecution, middleWellFormed, middleRepresented,
          bodyEffect⟩ := bodyInduction  conditionRepresented below
        conditionWellFormed localsFresh
        (Nat.le_trans nextFresh conditionEffect.nextCell)
      obtain ⟨after, restExecution, afterWellFormed, afterRepresented,
          restEffect⟩ := restInduction  middleRepresented below
        middleWellFormed localsFresh
        (Nat.le_trans nextFresh
          (Nat.le_trans conditionEffect.nextCell bodyEffect.nextCell))
      rw [writes_eq (command_footprint registry _bodyResult)] at restEffect
      rw [writes_eq (term_footprint registry conditionResult)] at bodyEffect restEffect
      exact ⟨after,
        executesWhileTrueThen conditionExecution bodyExecution restExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same
          (bodyEffect.trans_same restEffect)⟩
  case whileContinue =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        body _bodyWorld _bodyEnvironment _completion _afterWorld
        _afterEnvironment conditionResult _bodyResult _restResult bodyInduction
        restInduction  frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨middle, bodyExecution, middleWellFormed, middleRepresented,
          bodyEffect⟩ := bodyInduction  conditionRepresented below
        conditionWellFormed localsFresh
        (Nat.le_trans nextFresh conditionEffect.nextCell)
      obtain ⟨after, restExecution, afterWellFormed, afterRepresented,
          restEffect⟩ := restInduction  middleRepresented below
        middleWellFormed localsFresh
        (Nat.le_trans nextFresh
          (Nat.le_trans conditionEffect.nextCell bodyEffect.nextCell))
      rw [writes_eq (command_footprint registry _bodyResult)] at restEffect
      rw [writes_eq (term_footprint registry conditionResult)] at bodyEffect restEffect
      exact ⟨after,
        executesWhileContinueThen conditionExecution bodyExecution restExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same
          (bodyEffect.trans_same restEffect)⟩
  case whileBreak =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        body _afterWorld _afterEnvironment conditionResult _bodyResult induction
         frontier layout state localCell nextLocal represented below
        wellFormed localsFresh nextFresh
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨after, bodyExecution, afterWellFormed, afterRepresented,
          bodyEffect⟩ := induction  conditionRepresented below
        conditionWellFormed localsFresh
        (Nat.le_trans nextFresh conditionEffect.nextCell)
      rw [writes_eq (term_footprint registry conditionResult)] at bodyEffect
      exact ⟨after, executesWhileBreak conditionExecution bodyExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same bodyEffect⟩
  case whileReturn =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        body _value _afterWorld _afterEnvironment conditionResult _bodyResult
        induction  frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨after, bodyExecution, afterWellFormed, afterRepresented,
          bodyEffect⟩ := induction  conditionRepresented below
        conditionWellFormed localsFresh
        (Nat.le_trans nextFresh conditionEffect.nextCell)
      rw [writes_eq (term_footprint registry conditionResult)] at bodyEffect
      exact ⟨after, executesWhileReturned conditionExecution bodyExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same bodyEffect⟩
  case returnNone =>
      intro _world _arity _environment  frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      exact ⟨state, executesReturnNone program state, wellFormed, represented,
        (ModifiesOnly.refl state).weaken CellSet.empty_subset⟩
  case returnSome =>
      intro _beforeWorld _arity _beforeEnvironment _value _result _afterWorld
        valueResult  frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      obtain ⟨after, valueExecution, afterWellFormed, afterRepresented,
          effect⟩ := termSoundness operations wellFormed represented valueResult
      exact ⟨after, executesReturnValue valueExecution, afterWellFormed,
        afterRepresented, effect.weaken CellSet.empty_subset⟩
  case breakLoop =>
      intro _world _arity _environment  frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      exact ⟨state, executesBreak program state, wellFormed, represented,
        (ModifiesOnly.refl state).weaken CellSet.empty_subset⟩
  case continueLoop =>
      intro _world _arity _environment  frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      exact ⟨state, executesContinue program state, wellFormed, represented,
        (ModifiesOnly.refl state).weaken CellSet.empty_subset⟩
  case t => exact evaluated


end Lanius.FunctionalView.StatefulFrame
