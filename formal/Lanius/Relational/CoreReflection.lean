import Lanius.Relational.CoreSuccess
import Lanius.Relational.OperationRegistry
import Lanius.Relational.SemanticWP
import Lanius.FunctionalViewCoreFreshSimulation

namespace Lanius.Relational.CoreReflection

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Relational.Semantics

/-! # Structural reflection of successful Core commands

`CoreSuccess.StmtExecutes` removes evaluator fuel from the proof surface.  This
module performs the remaining command-structural part of inverse adequacy.
Expression evaluation and assignment are the only leaves: a registry-backed
expression reflector supplies those without exposing them to algorithm proofs.
-/

/-- Inverse reflection for one concrete term occurrence under a logical
precondition.  Partial call contracts require this preconditioned form: the
loop invariant at the occurrence establishes the callee precondition. -/
def TermReflectsWhen
    (program : Program) (registry : OperationRegistry)
    {arity : Nat} (admissible : ReadOnly.World → Env arity → Prop)
    (term : Term Core.signature arity) : Prop :=
  ∀ {layout : Layout arity}
      {localCell : Fin arity → CellId}
      {world : ReadOnly.World} {environment : Env arity}
      {before after : State} {frontier : CellId}
      {value : Value},
    StateWellFormed before →
    Representation layout localCell world environment before →
    admissible world environment →
    Evaluates program before (Core.toCoreExpr layout term) value after →
    ∃ afterWorld,
      TermEvaluates (registry.machine program) world environment term value afterWorld ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld environment after ∧
      ModifiesOnly (freshCells frontier) before after

/-- Environment-independent leaf reflection.  This stronger specialization is
appropriate for total primitive specifications.  Partial call contracts use
`TermReflectsWhen` and an invariant-aware command certificate instead. -/
abbrev TermReflects
    (program : Program) (registry : OperationRegistry)
    {arity : Nat} (term : Term Core.signature arity) : Prop :=
  TermReflectsWhen program registry (fun _ _ => True) term

def SetLocalReflects
    (program : Program) (registry : OperationRegistry)
    {arity : Nat} (target : Fin arity)
    (term : Term Core.signature arity) : Prop :=
  ∀ {layout : Layout arity}
      {localCell : Fin arity → CellId}
      {world : ReadOnly.World} {environment : Env arity}
      {before after : State} {frontier : CellId}
      {value : Value},
    StateWellFormed before →
    Representation layout localCell world environment before →
    Evaluates program before
      (.assign .set (.local (layout target)) (Core.toCoreExpr layout term))
      value after →
    ∃ result afterWorld,
      TermEvaluates (registry.machine program) world environment term result afterWorld ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld
        (Stateful.Env.set environment target result) after ∧
      ModifiesOnly (freshCells frontier) before after

def UpdateLocalReflects
    (program : Program) (registry : OperationRegistry)
    {arity : Nat} (operation : AssignOp) (target : Fin arity)
    (term : Term Core.signature arity) : Prop :=
  ∀ {layout : Layout arity}
      {localCell : Fin arity → CellId}
      {world : ReadOnly.World} {environment : Env arity}
      {before after : State} {frontier : CellId}
      {value : Value},
    StateWellFormed before →
    Representation layout localCell world environment before →
    Evaluates program before
      (.assign operation (.local (layout target))
        (Core.toCoreExpr layout term)) value after →
    ∃ right result afterWorld,
      TermEvaluates (registry.machine program) world environment term right afterWorld ∧
      (registry.machine program).localUpdate operation
        (environment target) right result ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld
        (Stateful.Env.set environment target result) after ∧
      ModifiesOnly (freshCells frontier) before after

/-- A syntax-directed certificate that every expression/assignment occurrence
in one command has the inverse-reflection fact needed at that occurrence. -/
inductive CommandLeaves
    (program : Program) (registry : OperationRegistry) :
    Stateful.Command Core.signature Stateful.actions arity → Prop where
  | skip : CommandLeaves program registry .skip
  | sequence
      (first : CommandLeaves program registry firstCommand)
      (second : CommandLeaves program registry secondCommand) :
      CommandLeaves program registry (.sequence firstCommand secondCommand)
  | letValue
      (initializer : TermReflects program registry initializerTerm)
      (body : CommandLeaves program registry bodyCommand) :
      CommandLeaves program registry
        (.letValue type initializerTerm bodyCommand)
  | setLocal
      (value : SetLocalReflects program registry target valueTerm) :
      CommandLeaves program registry (.setLocal target valueTerm)
  | updateLocal
      (value : UpdateLocalReflects program registry operation target valueTerm) :
      CommandLeaves program registry
        (.updateLocal operation target valueTerm)
  | ifThenElse
      (condition : TermReflects program registry conditionTerm)
      (thenBranch : CommandLeaves program registry thenCommand)
      (elseBranch : CommandLeaves program registry elseCommand) :
      CommandLeaves program registry
        (.ifThenElse conditionTerm thenCommand elseCommand)
  | whileLoop
      (condition : TermReflects program registry conditionTerm)
      (body : CommandLeaves program registry bodyCommand) :
      CommandLeaves program registry (.whileLoop conditionTerm bodyCommand)
  | returnNone : CommandLeaves program registry (.returnValue none)
  | returnSome
      (value : TermReflects program registry valueTerm) :
      CommandLeaves program registry (.returnValue (some valueTerm))
  | breakLoop : CommandLeaves program registry .breakLoop
  | continueLoop : CommandLeaves program registry .continueLoop

theorem CommandLeaves.actionFree
    (leaves : CommandLeaves program registry command) :
    FreshSimulation.actionFree command = true := by
  induction leaves with
  | skip | setLocal | updateLocal | returnNone | returnSome |
      breakLoop | continueLoop => rfl
  | sequence _ _ firstIH secondIH => simp [FreshSimulation.actionFree, firstIH, secondIH]
  | letValue _ _ bodyIH => simpa [FreshSimulation.actionFree] using bodyIH
  | ifThenElse _ _ _ thenIH elseIH =>
      simp [FreshSimulation.actionFree, thenIH, elseIH]
  | whileLoop _ _ bodyIH => simpa [FreshSimulation.actionFree] using bodyIH

theorem supported_toCoreStmt
    {command : Stateful.Command Core.signature Stateful.actions arity}
    (actionFree : FreshSimulation.actionFree command = true) :
    CoreSuccess.Supported
      (Stateful.toCoreStmt actionAdapter layout nextLocal command) = true := by
  induction command generalizing nextLocal with
  | skip => rfl
  | sequence first second firstIH secondIH =>
      simp only [FreshSimulation.actionFree, Bool.and_eq_true] at actionFree
      simp [Stateful.toCoreStmt, CoreSuccess.Supported,
        firstIH actionFree.1, secondIH actionFree.2]
  | letValue type initializer body bodyIH =>
      simpa [Stateful.toCoreStmt, CoreSuccess.Supported] using bodyIH actionFree
  | setLocal target value => rfl
  | updateLocal operation target value => rfl
  | action operation => simp [FreshSimulation.actionFree] at actionFree
  | ifThenElse condition thenBranch elseBranch thenIH elseIH =>
      simp only [FreshSimulation.actionFree, Bool.and_eq_true] at actionFree
      simp [Stateful.toCoreStmt, CoreSuccess.Supported,
        thenIH actionFree.1, elseIH actionFree.2]
  | whileLoop condition body bodyIH =>
      simpa [Stateful.toCoreStmt, CoreSuccess.Supported] using bodyIH actionFree
  | returnValue value => cases value <;> rfl
  | breakLoop => rfl
  | continueLoop => rfl

/-- Result package of structural reflection. -/
def Reflects
    (program : Program) (registry : OperationRegistry)
    (layout : Layout arity) (localCell : Fin arity → CellId)
    (frontier : CellId) (world : ReadOnly.World) (environment : Env arity)
    (before after : State)
    (command : Stateful.Command Core.signature Stateful.actions arity)
    (coreCompletion : Lanius.Semantics.Completion) : Prop :=
  ∃ completion afterWorld afterEnvironment,
    Stateful.CommandEvaluates (registry.machine program) world environment command completion
      afterWorld afterEnvironment ∧
    Stateful.toCoreCompletion completion = coreCompletion ∧
    StateWellFormed after ∧
    Representation layout localCell afterWorld afterEnvironment after ∧
    ModifiesOnly (freshCells frontier) before after

/-- Invariant-aware structural reflection boundary.  The admissibility
predicate is available at the command entry, allowing a certificate to thread
source-level loop invariants to partial call sites. -/
def CommandReflectsWhen
    (program : Program) (registry : OperationRegistry)
    {arity : Nat}
    (command : Stateful.Command Core.signature Stateful.actions arity)
    (admissible : ReadOnly.World → Env arity → Prop) : Prop :=
  ∀ {layout : Layout arity} {localCell : Fin arity → CellId}
      {nextLocal frontier : CellId}
      {world : ReadOnly.World} {environment : Env arity}
      {before after : State} {coreCompletion : Lanius.Semantics.Completion},
    admissible world environment →
    FreshSimulation.actionFree command = true →
    Representation layout localCell world environment before →
    LayoutBelow layout nextLocal →
    StateWellFormed before →
    LocalsFresh frontier localCell →
    frontier ≤ before.nextCell →
    CoreSuccess.StmtExecutes program before
      (Stateful.toCoreStmt actionAdapter layout nextLocal command)
      coreCompletion after →
    Reflects program registry layout localCell frontier world environment before
      after command coreCompletion

/-! ## Invariant-aware structural composition

These rules compose reflection certificates while using relational weakest
preconditions solely to transport the source-level invariant between command
boundaries.  The execution itself is still reflected from the supplied
`CoreSuccess.StmtExecutes` tree.
-/

theorem CommandReflectsWhen.sequence
    {first second : Stateful.Command Core.signature Stateful.actions arity}
    {firstAdmissible secondAdmissible : ReadOnly.World → Env arity → Prop}
    (firstReflection : CommandReflectsWhen program registry first
      firstAdmissible)
    (firstWP : ∀ world environment,
      firstAdmissible world environment →
      SemanticWP.Command.WP (registry.machine program) first
        (fun completion afterWorld afterEnvironment =>
          completion = .next →
            secondAdmissible afterWorld afterEnvironment)
        world environment)
    (secondReflection : CommandReflectsWhen program registry second
      secondAdmissible) :
    CommandReflectsWhen program registry (.sequence first second)
      firstAdmissible := by
  intro layout localCell nextLocal frontier world environment before after
    coreCompletion inputAdmissible actionFree represented below wellFormed
    localsFresh nextFresh executed
  simp only [Stateful.toCoreStmt] at executed
  simp only [FreshSimulation.actionFree, Bool.and_eq_true] at actionFree
  cases executed with
  | sequenceNext firstResult secondResult =>
      obtain ⟨firstCompletion, middleWorld, middleEnvironment,
          firstEvaluated, firstCompletionEq, middleWellFormed,
          middleRepresented, firstEffect⟩ :=
        firstReflection inputAdmissible actionFree.1 represented below
          wellFormed localsFresh nextFresh firstResult
      have firstNext : firstCompletion = .next := by
        cases firstCompletion <;> simp_all [Stateful.toCoreCompletion]
      have middleAdmissible : secondAdmissible middleWorld middleEnvironment :=
        firstWP world environment inputAdmissible _ _ _ firstEvaluated firstNext
      subst firstCompletion
      have secondBelow := below.mono
        (Nat.le_add_right nextLocal (localCapacity actionAdapter first))
      obtain ⟨completion, afterWorld, afterEnvironment, secondEvaluated,
          completionEq, afterWellFormed, afterRepresented, secondEffect⟩ :=
        secondReflection middleAdmissible actionFree.2 middleRepresented
          secondBelow middleWellFormed localsFresh
          (Nat.le_trans nextFresh firstEffect.nextCell) secondResult
      exact ⟨completion, afterWorld, afterEnvironment,
        .sequenceNext firstEvaluated secondEvaluated, completionEq,
        afterWellFormed, afterRepresented,
        firstEffect.trans_same secondEffect⟩
  | sequenceStop firstResult stops =>
      obtain ⟨completion, afterWorld, afterEnvironment, firstEvaluated,
          completionEq, afterWellFormed, afterRepresented, effect⟩ :=
        firstReflection inputAdmissible actionFree.1 represented below
          wellFormed localsFresh nextFresh firstResult
      have completionStops : completion ≠ .next := by
        intro same
        subst completion
        apply stops
        simpa [Stateful.toCoreCompletion] using completionEq.symm
      exact ⟨completion, afterWorld, afterEnvironment,
        .sequenceStop firstEvaluated completionStops, completionEq,
        afterWellFormed, afterRepresented, effect⟩

theorem CommandReflectsWhen.letValue
    {initializer : Term Core.signature arity}
    {body : Stateful.Command Core.signature Stateful.actions (arity + 1)}
    {inputAdmissible : ReadOnly.World → Env arity → Prop}
    {bodyAdmissible : ReadOnly.World → Env (arity + 1) → Prop}
    (initializerReflection : TermReflectsWhen program registry
      inputAdmissible initializer)
    (initializerWP : ∀ world environment,
      inputAdmissible world environment →
      SemanticWP.Term.WP (registry.machine program) initializer
        (fun value afterWorld =>
          bodyAdmissible afterWorld (environment.push value))
        world environment)
    (bodyReflection : CommandReflectsWhen program registry body
      bodyAdmissible) :
    CommandReflectsWhen program registry (.letValue type initializer body)
      inputAdmissible := by
  intro layout localCell nextLocal frontier world environment before after
    coreCompletion admissible actionFree represented below wellFormed
    localsFresh nextFresh executed
  simp only [Stateful.toCoreStmt] at executed
  simp only [FreshSimulation.actionFree] at actionFree
  cases executed with
  | letLocal initializerResult bodyResult =>
      rename_i initValue initialized completed
      obtain ⟨initializedWorld, initializerEvaluated,
          initializedWellFormed, initializedRepresented,
          initializerEffect⟩ :=
        initializerReflection wellFormed represented admissible initializerResult
      have bodyInput : bodyAdmissible initializedWorld
          (environment.push initValue) :=
        initializerWP world environment admissible _ _ initializerEvaluated
      let bound := initialized.bindLocal nextLocal initValue
      let boundCells := pushCells localCell initialized.nextCell
      have boundWellFormed := bindLocal_preserves_well_formed initialized
        nextLocal initValue initializedWellFormed
      have boundRepresented : Representation (Layout.push layout nextLocal)
          boundCells initializedWorld (environment.push initValue) bound := by
        simpa [bound, boundCells] using
          initializedRepresented.bindLocal below initializedWellFormed initValue
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
      obtain ⟨completion, afterWorld, extendedEnvironment, bodyEvaluated,
          completionEq, completedWellFormed, completedRepresented,
          bodyEffect⟩ :=
        bodyReflection bodyInput actionFree boundRepresented below.push
          boundWellFormed boundFresh boundNextFresh bodyResult
      let restored := restoreLocals initialized completed
      have scopeEffect : ModifiesOnly (freshCells frontier) initialized
          restored :=
        temporaryLocal_effect nextLocal initValue bodyEffect.toStoreEffect
      have restoredWellFormed : StateWellFormed restored := by
        have entered : StoreEffect (freshCells frontier) initialized bound :=
          (bindLocal_effect initialized nextLocal initValue).weaken
            CellSet.empty_subset
        simpa [restored] using
          (entered.trans_same bodyEffect.toStoreEffect).restoreLocals_wellFormed
            initializedWellFormed completedWellFormed
      have restoredRepresented : Representation layout localCell afterWorld
          (Stateful.Env.pop extendedEnvironment) restored := by
        refine {
          worldOwned := ?_
          localOwned := ?_
          localCellsInjective := initializedRepresented.localCellsInjective
          worldLocalsDisjoint := ?_ }
        · intro cell values found
          simpa [restored, restoreLocals, State.cellEntry?] using
            completedRepresented.worldOwned cell values found
        · intro index
          let lifted : Fin (arity + 1) :=
            ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
          have owned := completedRepresented.localOwned lifted
          constructor
          · simpa [restored, restoreLocals, State.cellId?] using
              (initializedRepresented.localOwned index).1
          · simpa [restored, restoreLocals, State.cellEntry?, boundCells,
              pushCells, lifted, Stateful.Env.pop] using owned.2
        · intro cell worldMember localMember
          exact completedRepresented.worldLocalsDisjoint cell worldMember
            (by
              obtain ⟨index, same⟩ := localMember
              let lifted : Fin (arity + 1) :=
                ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
              exact ⟨lifted, by
                simpa [boundCells, pushCells, lifted] using same⟩)
      exact ⟨completion, afterWorld, Stateful.Env.pop extendedEnvironment,
        .letValue initializerEvaluated bodyEvaluated, completionEq,
        restoredWellFormed, restoredRepresented,
        initializerEffect.trans_same scopeEffect⟩

/-- Reflect a value return under the precondition required by its expression.
This small structural rule lets finite helper functions use the same
successful-execution boundary as loops without strengthening a partial call
contract into an environment-independent leaf certificate. -/
theorem CommandReflectsWhen.returnSome
    {admissible : ReadOnly.World → Env arity → Prop}
    {value : Term Core.signature arity}
    (valueReflection : TermReflectsWhen program registry admissible value) :
    CommandReflectsWhen program registry (.returnValue (some value))
      admissible := by
  intro layout localCell nextLocal frontier world environment before after
    coreCompletion inputAdmissible _actionFree represented _below wellFormed
    _localsFresh _nextFresh executed
  simp only [Stateful.toCoreStmt] at executed
  cases executed with
  | returnSome evaluated =>
      obtain ⟨afterWorld, valueEvaluated, afterWellFormed,
          afterRepresented, effect⟩ :=
        valueReflection (frontier := frontier) wellFormed represented
          inputAdmissible evaluated
      exact ⟨.returned (some _), afterWorld, environment,
        .returnSome valueEvaluated, rfl, afterWellFormed, afterRepresented,
        effect⟩

theorem CommandReflectsWhen.whileLoop
    {condition : Term Core.signature arity}
    {body : Stateful.Command Core.signature Stateful.actions arity}
    {invariant bodyAdmissible : ReadOnly.World → Env arity → Prop}
    (conditionReflection : TermReflectsWhen program registry invariant
      condition)
    (conditionWP : ∀ world environment,
      invariant world environment →
      SemanticWP.Term.WP (registry.machine program) condition
        (fun value afterWorld =>
          value = .boolean true → bodyAdmissible afterWorld environment)
        world environment)
    (bodyReflection : CommandReflectsWhen program registry body
      bodyAdmissible)
    (bodyWP : ∀ world environment,
      bodyAdmissible world environment →
      SemanticWP.Command.WP (registry.machine program) body
        (fun completion afterWorld afterEnvironment =>
          (completion = .next ∨ completion = .continueLoop) →
            invariant afterWorld afterEnvironment)
        world environment) :
    CommandReflectsWhen program registry (.whileLoop condition body)
      invariant := by
  intro layout localCell nextLocal frontier world environment before after
    coreCompletion inputInvariant actionFree represented below wellFormed
    localsFresh nextFresh executed
  simp only [Stateful.toCoreStmt] at executed
  simp only [FreshSimulation.actionFree] at actionFree
  have loopExecuted := executed.whileInversion
  induction loopExecuted generalizing world environment with
  | false conditionResult =>
      obtain ⟨afterWorld, conditionEvaluated, afterWellFormed,
          afterRepresented, effect⟩ :=
        conditionReflection wellFormed represented inputInvariant
          conditionResult
      exact ⟨.next, afterWorld, environment,
        .whileFalse conditionEvaluated, rfl, afterWellFormed,
        afterRepresented, effect⟩
  | next conditionResult bodyResult restResult restIH =>
      obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        conditionReflection wellFormed represented inputInvariant
          conditionResult
      have bodyInput : bodyAdmissible conditionWorld environment :=
        conditionWP world environment inputInvariant _ _ conditionEvaluated rfl
      obtain ⟨bodyCompletion, bodyWorld, bodyEnvironment, bodyEvaluated,
          bodyCompletionEq, bodyWellFormed, bodyRepresented, bodyEffect⟩ :=
        bodyReflection bodyInput actionFree conditionRepresented below
          conditionWellFormed localsFresh
          (Nat.le_trans nextFresh conditionEffect.nextCell) bodyResult
      have bodyNext : bodyCompletion = .next := by
        cases bodyCompletion <;> simp_all [Stateful.toCoreCompletion]
      have restInvariant : invariant bodyWorld bodyEnvironment :=
        bodyWP conditionWorld environment bodyInput _ _ _ bodyEvaluated
          (.inl bodyNext)
      subst bodyCompletion
      obtain ⟨completion, afterWorld, afterEnvironment, restEvaluated,
          completionEq, afterWellFormed, afterRepresented, restEffect⟩ :=
        restIH restInvariant bodyRepresented bodyWellFormed
          (Nat.le_trans nextFresh
            (Nat.le_trans conditionEffect.nextCell bodyEffect.nextCell))
          restResult.toStmtExecutes
      exact ⟨completion, afterWorld, afterEnvironment,
        .whileNext conditionEvaluated bodyEvaluated restEvaluated,
        completionEq, afterWellFormed, afterRepresented,
        conditionEffect.trans_same (bodyEffect.trans_same restEffect)⟩
  | «continue» conditionResult bodyResult restResult restIH =>
      obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        conditionReflection wellFormed represented inputInvariant
          conditionResult
      have bodyInput : bodyAdmissible conditionWorld environment :=
        conditionWP world environment inputInvariant _ _ conditionEvaluated rfl
      obtain ⟨bodyCompletion, bodyWorld, bodyEnvironment, bodyEvaluated,
          bodyCompletionEq, bodyWellFormed, bodyRepresented, bodyEffect⟩ :=
        bodyReflection bodyInput actionFree conditionRepresented below
          conditionWellFormed localsFresh
          (Nat.le_trans nextFresh conditionEffect.nextCell) bodyResult
      have bodyContinue : bodyCompletion = .continueLoop := by
        cases bodyCompletion <;> simp_all [Stateful.toCoreCompletion]
      have restInvariant : invariant bodyWorld bodyEnvironment :=
        bodyWP conditionWorld environment bodyInput _ _ _ bodyEvaluated
          (.inr bodyContinue)
      subst bodyCompletion
      obtain ⟨completion, afterWorld, afterEnvironment, restEvaluated,
          completionEq, afterWellFormed, afterRepresented, restEffect⟩ :=
        restIH restInvariant bodyRepresented bodyWellFormed
          (Nat.le_trans nextFresh
            (Nat.le_trans conditionEffect.nextCell bodyEffect.nextCell))
          restResult.toStmtExecutes
      exact ⟨completion, afterWorld, afterEnvironment,
        .whileContinue conditionEvaluated bodyEvaluated restEvaluated,
        completionEq, afterWellFormed, afterRepresented,
        conditionEffect.trans_same (bodyEffect.trans_same restEffect)⟩
  | «break» conditionResult bodyResult =>
      obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        conditionReflection wellFormed represented inputInvariant
          conditionResult
      have bodyInput : bodyAdmissible conditionWorld environment :=
        conditionWP world environment inputInvariant _ _ conditionEvaluated rfl
      obtain ⟨bodyCompletion, afterWorld, afterEnvironment, bodyEvaluated,
          bodyCompletionEq, afterWellFormed, afterRepresented, bodyEffect⟩ :=
        bodyReflection bodyInput actionFree conditionRepresented below
          conditionWellFormed localsFresh
          (Nat.le_trans nextFresh conditionEffect.nextCell) bodyResult
      have bodyBreak : bodyCompletion = .breakLoop := by
        cases bodyCompletion <;> simp_all [Stateful.toCoreCompletion]
      subst bodyCompletion
      exact ⟨.next, afterWorld, afterEnvironment,
        .whileBreak conditionEvaluated bodyEvaluated, rfl,
        afterWellFormed, afterRepresented,
        conditionEffect.trans_same bodyEffect⟩
  | returned conditionResult bodyResult =>
      obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        conditionReflection wellFormed represented inputInvariant
          conditionResult
      have bodyInput : bodyAdmissible conditionWorld environment :=
        conditionWP world environment inputInvariant _ _ conditionEvaluated rfl
      obtain ⟨bodyCompletion, afterWorld, afterEnvironment, bodyEvaluated,
          bodyCompletionEq, afterWellFormed, afterRepresented, bodyEffect⟩ :=
        bodyReflection bodyInput actionFree conditionRepresented below
          conditionWellFormed localsFresh
          (Nat.le_trans nextFresh conditionEffect.nextCell) bodyResult
      cases bodyCompletion with
      | returned returnedValue =>
          simp only [Stateful.toCoreCompletion] at bodyCompletionEq
          injection bodyCompletionEq with valueEq
          subst returnedValue
          exact ⟨.returned _, afterWorld, afterEnvironment,
            .whileReturn conditionEvaluated bodyEvaluated, rfl,
            afterWellFormed, afterRepresented,
            conditionEffect.trans_same bodyEffect⟩
      | next | breakLoop | continueLoop =>
          simp [Stateful.toCoreCompletion] at bodyCompletionEq

/-- Structural inverse adequacy, deliberately independent of termination and
determinism.  The induction is on the supplied successful Core proof tree, so
recursive loop iterations are already finite. -/
theorem command_reflects
    {command : Stateful.Command Core.signature Stateful.actions arity}
    (leaves : CommandLeaves program registry command)
    (actionFree : FreshSimulation.actionFree command = true)
    (represented : Representation layout localCell world environment before)
    (below : LayoutBelow layout nextLocal)
    (wellFormed : StateWellFormed before)
    (localsFresh : LocalsFresh frontier localCell)
    (nextFresh : frontier ≤ before.nextCell)
    (executed : CoreSuccess.StmtExecutes program before
      (Stateful.toCoreStmt actionAdapter layout nextLocal command)
      coreCompletion after) :
    Reflects program registry layout localCell frontier world environment before after
      command coreCompletion := by
  generalize statementEq :
      Stateful.toCoreStmt actionAdapter layout nextLocal command = statement
      at executed
  induction executed generalizing arity command layout localCell nextLocal
      world environment leaves with
  | skip =>
      cases command with
      | skip =>
          exact ⟨.next, world, environment, .skip, rfl, wellFormed,
            represented, ModifiesOnly.reflAny _ _⟩
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | expression evaluated =>
      cases command with
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target valueTerm =>
          cases leaves
          rename_i valueReflect
          simp only [Stateful.toCoreStmt] at statementEq
          have expressionEq := Stmt.expression.inj statementEq
          rw [← expressionEq] at evaluated
          obtain ⟨result, afterWorld, valueResult, afterWellFormed,
              afterRepresented, effect⟩ :=
            valueReflect (frontier := frontier) wellFormed represented
              evaluated
          exact ⟨.next, afterWorld, Stateful.Env.set environment target result,
            .setLocal valueResult, rfl, afterWellFormed, afterRepresented,
            effect⟩
      | updateLocal operation target valueTerm =>
          cases leaves
          rename_i valueReflect
          simp only [Stateful.toCoreStmt] at statementEq
          have expressionEq := Stmt.expression.inj statementEq
          rw [← expressionEq] at evaluated
          obtain ⟨right, result, afterWorld, valueResult, updateResult,
              afterWellFormed, afterRepresented, effect⟩ :=
            valueReflect (frontier := frontier) wellFormed represented
              evaluated
          exact ⟨.next, afterWorld, Stateful.Env.set environment target result,
            .updateLocal valueResult updateResult, rfl, afterWellFormed,
            afterRepresented, effect⟩
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | sequenceNext firstResult secondResult firstIH secondIH =>
      cases command with
      | sequence first second =>
          cases leaves
          rename_i firstLeaves secondLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl⟩ := Stmt.sequence.inj statementEq
          simp only [FreshSimulation.actionFree, Bool.and_eq_true] at actionFree
          obtain ⟨firstCompletion, middleWorld, middleEnvironment,
              firstEvaluated, firstCompletionEq, middleWellFormed,
              middleRepresented, firstEffect⟩ :=
            firstIH firstLeaves actionFree.1 represented below wellFormed localsFresh
              nextFresh rfl
          have firstNext : firstCompletion = .next := by
            cases firstCompletion <;>
              simp_all [Stateful.toCoreCompletion]
          subst firstCompletion
          have secondBelow := below.mono
            (Nat.le_add_right nextLocal
              (localCapacity actionAdapter first))
          obtain ⟨completion, afterWorld, afterEnvironment, secondEvaluated,
              completionEq, afterWellFormed, afterRepresented, secondEffect⟩ :=
            secondIH secondLeaves actionFree.2 middleRepresented secondBelow
              middleWellFormed localsFresh
              (Nat.le_trans nextFresh firstEffect.nextCell) rfl
          exact ⟨completion, afterWorld, afterEnvironment,
            .sequenceNext firstEvaluated secondEvaluated, completionEq,
            afterWellFormed, afterRepresented,
            firstEffect.trans_same secondEffect⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | sequenceStop firstResult stops firstIH =>
      cases command with
      | sequence first second =>
          cases leaves
          rename_i firstLeaves secondLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl⟩ := Stmt.sequence.inj statementEq
          simp only [FreshSimulation.actionFree, Bool.and_eq_true] at actionFree
          obtain ⟨completion, afterWorld, afterEnvironment, firstEvaluated,
              completionEq, afterWellFormed, afterRepresented, effect⟩ :=
            firstIH firstLeaves actionFree.1 represented below wellFormed localsFresh
              nextFresh rfl
          have completionStops : completion ≠ .next := by
            intro same
            subst completion
            apply stops
            simpa [Stateful.toCoreCompletion] using completionEq.symm
          exact ⟨completion, afterWorld, afterEnvironment,
            .sequenceStop firstEvaluated completionStops, completionEq,
            afterWellFormed, afterRepresented, effect⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | letLocal initializerResult bodyResult bodyIH =>
      rename_i beforeCore initializerExpr initValue initialized localId bodyStmt
        completionCore completed typeCore
      cases command with
      | letValue type initializer body =>
          cases leaves
          rename_i initializerReflect bodyLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl, rfl, rfl⟩ := Stmt.letLocal.inj statementEq
          simp only [FreshSimulation.actionFree] at actionFree
          obtain ⟨initializedWorld, initializerEvaluated,
              initializedWellFormed, initializedRepresented,
              initializerEffect⟩ :=
            initializerReflect (frontier := frontier) wellFormed represented
              trivial initializerResult
          let bound := initialized.bindLocal nextLocal initValue
          let boundCells := pushCells localCell initialized.nextCell
          have boundWellFormed := bindLocal_preserves_well_formed initialized
            nextLocal initValue initializedWellFormed
          have boundRepresented : Representation (Layout.push layout nextLocal)
              boundCells initializedWorld (environment.push initValue) bound := by
            simpa [bound, boundCells] using
              initializedRepresented.bindLocal below initializedWellFormed initValue
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
          obtain ⟨completion, afterWorld, extendedEnvironment, bodyEvaluated,
              completionEq, completedWellFormed, completedRepresented,
              bodyEffect⟩ :=
            bodyIH bodyLeaves actionFree boundRepresented below.push boundWellFormed
              boundFresh boundNextFresh rfl
          let restored := restoreLocals initialized completed
          have scopeEffect : ModifiesOnly (freshCells frontier) initialized
              restored :=
            temporaryLocal_effect nextLocal initValue bodyEffect.toStoreEffect
          have restoredWellFormed : StateWellFormed restored := by
            have entered : StoreEffect (freshCells frontier) initialized bound :=
              (bindLocal_effect initialized nextLocal initValue).weaken
                CellSet.empty_subset
            simpa [restored] using
              (entered.trans_same bodyEffect.toStoreEffect).restoreLocals_wellFormed
                initializedWellFormed completedWellFormed
          have restoredRepresented : Representation layout localCell afterWorld
              (Stateful.Env.pop extendedEnvironment) restored := by
            refine {
              worldOwned := ?_
              localOwned := ?_
              localCellsInjective := initializedRepresented.localCellsInjective
              worldLocalsDisjoint := ?_
            }
            · intro cell values found
              simpa [restored, restoreLocals, State.cellEntry?] using
                completedRepresented.worldOwned cell values found
            · intro index
              let lifted : Fin (arity + 1) :=
                ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
              have owned := completedRepresented.localOwned lifted
              constructor
              · simpa [restored, restoreLocals, State.cellId?] using
                  (initializedRepresented.localOwned index).1
              · simpa [restored, restoreLocals, State.cellEntry?, boundCells,
                  pushCells, lifted, Stateful.Env.pop] using owned.2
            · intro cell worldMember localMember
              exact completedRepresented.worldLocalsDisjoint cell worldMember
                (by
                  obtain ⟨index, same⟩ := localMember
                  let lifted : Fin (arity + 1) :=
                    ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
                  exact ⟨lifted, by
                    simpa [boundCells, pushCells, lifted] using same⟩)
          exact ⟨completion, afterWorld,
            Stateful.Env.pop extendedEnvironment,
            .letValue initializerEvaluated bodyEvaluated, completionEq,
            restoredWellFormed, restoredRepresented,
            initializerEffect.trans_same scopeEffect⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | ifTrue conditionResult branchResult branchIH =>
      cases command with
      | ifThenElse condition thenBranch elseBranch =>
          cases leaves
          rename_i conditionReflect thenLeaves elseLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl, rfl⟩ := Stmt.ifThenElse.inj statementEq
          simp only [FreshSimulation.actionFree, Bool.and_eq_true] at actionFree
          obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
              conditionRepresented, conditionEffect⟩ :=
            conditionReflect (frontier := frontier) wellFormed represented
              trivial conditionResult
          obtain ⟨completion, afterWorld, afterEnvironment, branchEvaluated,
              completionEq, afterWellFormed, afterRepresented, branchEffect⟩ :=
            branchIH thenLeaves actionFree.1 conditionRepresented below
              conditionWellFormed localsFresh
              (Nat.le_trans nextFresh conditionEffect.nextCell) rfl
          exact ⟨completion, afterWorld, afterEnvironment,
            .ifTrue conditionEvaluated branchEvaluated, completionEq,
            afterWellFormed, afterRepresented,
            conditionEffect.trans_same branchEffect⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | ifFalse conditionResult branchResult branchIH =>
      cases command with
      | ifThenElse condition thenBranch elseBranch =>
          cases leaves
          rename_i conditionReflect thenLeaves elseLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl, rfl⟩ := Stmt.ifThenElse.inj statementEq
          simp only [FreshSimulation.actionFree, Bool.and_eq_true] at actionFree
          obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
              conditionRepresented, conditionEffect⟩ :=
            conditionReflect (frontier := frontier) wellFormed represented
              trivial conditionResult
          obtain ⟨completion, afterWorld, afterEnvironment, branchEvaluated,
              completionEq, afterWellFormed, afterRepresented, branchEffect⟩ :=
            branchIH elseLeaves actionFree.2 conditionRepresented below
              conditionWellFormed localsFresh
              (Nat.le_trans nextFresh conditionEffect.nextCell) rfl
          exact ⟨completion, afterWorld, afterEnvironment,
            .ifFalse conditionEvaluated branchEvaluated, completionEq,
            afterWellFormed, afterRepresented,
            conditionEffect.trans_same branchEffect⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | whileFalse conditionResult =>
      cases command with
      | whileLoop condition body =>
          cases leaves
          rename_i conditionReflect bodyLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
          simp only [FreshSimulation.actionFree] at actionFree
          obtain ⟨afterWorld, conditionEvaluated, afterWellFormed,
              afterRepresented, effect⟩ :=
            conditionReflect (frontier := frontier) wellFormed represented
              trivial conditionResult
          exact ⟨.next, afterWorld, environment,
            .whileFalse conditionEvaluated, rfl, afterWellFormed,
            afterRepresented, effect⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | whileNext conditionResult bodyResult restResult bodyIH restIH =>
      cases command with
      | whileLoop condition body =>
          cases leaves
          rename_i conditionReflect bodyLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
          simp only [FreshSimulation.actionFree] at actionFree
          obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
              conditionRepresented, conditionEffect⟩ :=
            conditionReflect (frontier := frontier) wellFormed represented
              trivial conditionResult
          obtain ⟨bodyCompletion, bodyWorld, bodyEnvironment, bodyEvaluated,
              bodyCompletionEq, bodyWellFormed, bodyRepresented, bodyEffect⟩ :=
            bodyIH bodyLeaves actionFree conditionRepresented below conditionWellFormed
              localsFresh (Nat.le_trans nextFresh conditionEffect.nextCell) rfl
          have bodyNext : bodyCompletion = .next := by
            cases bodyCompletion <;> simp_all [Stateful.toCoreCompletion]
          subst bodyCompletion
          obtain ⟨completion, afterWorld, afterEnvironment, restEvaluated,
              completionEq, afterWellFormed, afterRepresented, restEffect⟩ :=
            restIH (command := .whileLoop condition body)
              (.whileLoop conditionReflect bodyLeaves)
              (by simpa [FreshSimulation.actionFree] using actionFree)
              bodyRepresented below bodyWellFormed localsFresh
              (Nat.le_trans nextFresh
                (Nat.le_trans conditionEffect.nextCell bodyEffect.nextCell)) rfl
          exact ⟨completion, afterWorld, afterEnvironment,
            .whileNext conditionEvaluated bodyEvaluated restEvaluated,
            completionEq, afterWellFormed, afterRepresented,
            conditionEffect.trans_same (bodyEffect.trans_same restEffect)⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | whileContinue conditionResult bodyResult restResult bodyIH restIH =>
      cases command with
      | whileLoop condition body =>
          cases leaves
          rename_i conditionReflect bodyLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
          simp only [FreshSimulation.actionFree] at actionFree
          obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
              conditionRepresented, conditionEffect⟩ :=
            conditionReflect (frontier := frontier) wellFormed represented
              trivial conditionResult
          obtain ⟨bodyCompletion, bodyWorld, bodyEnvironment, bodyEvaluated,
              bodyCompletionEq, bodyWellFormed, bodyRepresented, bodyEffect⟩ :=
            bodyIH bodyLeaves actionFree conditionRepresented below conditionWellFormed
              localsFresh (Nat.le_trans nextFresh conditionEffect.nextCell) rfl
          have bodyContinue : bodyCompletion = .continueLoop := by
            cases bodyCompletion <;> simp_all [Stateful.toCoreCompletion]
          subst bodyCompletion
          obtain ⟨completion, afterWorld, afterEnvironment, restEvaluated,
              completionEq, afterWellFormed, afterRepresented, restEffect⟩ :=
            restIH (command := .whileLoop condition body)
              (.whileLoop conditionReflect bodyLeaves)
              (by simpa [FreshSimulation.actionFree] using actionFree)
              bodyRepresented below bodyWellFormed localsFresh
              (Nat.le_trans nextFresh
                (Nat.le_trans conditionEffect.nextCell bodyEffect.nextCell)) rfl
          exact ⟨completion, afterWorld, afterEnvironment,
            .whileContinue conditionEvaluated bodyEvaluated restEvaluated,
            completionEq, afterWellFormed, afterRepresented,
            conditionEffect.trans_same (bodyEffect.trans_same restEffect)⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | whileBreak conditionResult bodyResult bodyIH =>
      cases command with
      | whileLoop condition body =>
          cases leaves
          rename_i conditionReflect bodyLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
          simp only [FreshSimulation.actionFree] at actionFree
          obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
              conditionRepresented, conditionEffect⟩ :=
            conditionReflect (frontier := frontier) wellFormed represented
              trivial conditionResult
          obtain ⟨bodyCompletion, afterWorld, afterEnvironment, bodyEvaluated,
              bodyCompletionEq, afterWellFormed, afterRepresented, bodyEffect⟩ :=
            bodyIH bodyLeaves actionFree conditionRepresented below conditionWellFormed
              localsFresh (Nat.le_trans nextFresh conditionEffect.nextCell) rfl
          have bodyBreak : bodyCompletion = .breakLoop := by
            cases bodyCompletion <;> simp_all [Stateful.toCoreCompletion]
          subst bodyCompletion
          exact ⟨.next, afterWorld, afterEnvironment,
            .whileBreak conditionEvaluated bodyEvaluated, rfl,
            afterWellFormed, afterRepresented,
            conditionEffect.trans_same bodyEffect⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | whileReturn conditionResult bodyResult bodyIH =>
      cases command with
      | whileLoop condition body =>
          cases leaves
          rename_i conditionReflect bodyLeaves
          simp only [Stateful.toCoreStmt] at statementEq
          obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
          simp only [FreshSimulation.actionFree] at actionFree
          obtain ⟨conditionWorld, conditionEvaluated, conditionWellFormed,
              conditionRepresented, conditionEffect⟩ :=
            conditionReflect (frontier := frontier) wellFormed represented
              trivial conditionResult
          obtain ⟨bodyCompletion, afterWorld, afterEnvironment, bodyEvaluated,
              bodyCompletionEq, afterWellFormed, afterRepresented, bodyEffect⟩ :=
            bodyIH bodyLeaves actionFree conditionRepresented below conditionWellFormed
              localsFresh (Nat.le_trans nextFresh conditionEffect.nextCell) rfl
          cases bodyCompletion with
          | returned returnedValue =>
              simp only [Stateful.toCoreCompletion] at bodyCompletionEq
              injection bodyCompletionEq with valueEq
              subst returnedValue
              exact ⟨.returned _, afterWorld, afterEnvironment,
                .whileReturn conditionEvaluated bodyEvaluated, rfl,
                afterWellFormed, afterRepresented,
                conditionEffect.trans_same bodyEffect⟩
          | next | breakLoop | continueLoop =>
              simp [Stateful.toCoreCompletion] at bodyCompletionEq
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | returnNone =>
      cases command with
      | returnValue value =>
          cases value with
          | none =>
              exact ⟨.returned none, world, environment, .returnNone, rfl,
                wellFormed, represented, ModifiesOnly.reflAny _ _⟩
          | some value => simp [Stateful.toCoreStmt] at statementEq
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | returnSome evaluated =>
      cases command with
      | returnValue valueOption =>
          cases valueOption with
          | none => simp [Stateful.toCoreStmt] at statementEq
          | some valueTerm =>
              cases leaves
              rename_i valueReflect
              simp only [Stateful.toCoreStmt] at statementEq
              obtain rfl := Option.some.inj (Stmt.returnValue.inj statementEq)
              obtain ⟨afterWorld, valueEvaluated, afterWellFormed,
                  afterRepresented, effect⟩ :=
                valueReflect (frontier := frontier) wellFormed represented
                  trivial evaluated
              exact ⟨.returned (some _), afterWorld, environment,
                .returnSome valueEvaluated, rfl, afterWellFormed,
                afterRepresented, effect⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | breakLoop =>
      cases command with
      | breakLoop =>
          exact ⟨.breakLoop, world, environment, .breakLoop, rfl, wellFormed,
            represented, ModifiesOnly.reflAny _ _⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | continueLoop => simp [Stateful.toCoreStmt] at statementEq
  | continueLoop =>
      cases command with
      | continueLoop =>
          exact ⟨.continueLoop, world, environment, .continueLoop, rfl,
            wellFormed, represented, ModifiesOnly.reflAny _ _⟩
      | skip => simp [Stateful.toCoreStmt] at statementEq
      | sequence first second => simp [Stateful.toCoreStmt] at statementEq
      | letValue type initializer body =>
          simp [Stateful.toCoreStmt] at statementEq
      | setLocal target value => simp [Stateful.toCoreStmt] at statementEq
      | updateLocal operation target value =>
          simp [Stateful.toCoreStmt] at statementEq
      | action operation => cases leaves
      | ifThenElse condition thenBranch elseBranch =>
          simp [Stateful.toCoreStmt] at statementEq
      | whileLoop condition body => simp [Stateful.toCoreStmt] at statementEq
      | returnValue value =>
          cases value <;> simp [Stateful.toCoreStmt] at statementEq
      | breakLoop => simp [Stateful.toCoreStmt] at statementEq

/-- A total leaf certificate is the invariant-free special case of the
invariant-aware boundary. -/
theorem CommandReflectsWhen.ofLeaves
    {command : Stateful.Command Core.signature Stateful.actions arity}
    (leaves : CommandLeaves program registry command) :
    CommandReflectsWhen program registry command (fun _ _ => True) := by
  intro layout localCell nextLocal frontier world environment before after
    coreCompletion _admissible actionFree represented below wellFormed
    localsFresh nextFresh executed
  exact command_reflects leaves actionFree represented below wellFormed
    localsFresh nextFresh executed

/-- Public evaluator-facing form: first derive the structural successful view,
then apply `command_reflects`. -/
theorem ofExecutes
    {command : Stateful.Command Core.signature Stateful.actions arity}
    (leaves : CommandLeaves program registry command)
    (actionFree : FreshSimulation.actionFree command = true)
    (represented : Representation layout localCell world environment before)
    (below : LayoutBelow layout nextLocal)
    (wellFormed : StateWellFormed before)
    (localsFresh : LocalsFresh frontier localCell)
    (nextFresh : frontier ≤ before.nextCell)
    (executed : Executes program before
      (Stateful.toCoreStmt actionAdapter layout nextLocal command)
      coreCompletion after) :
    Reflects program registry layout localCell frontier world environment before after
      command coreCompletion := by
  apply command_reflects leaves actionFree represented below wellFormed
    localsFresh nextFresh
  exact CoreSuccess.ofExecutes (supported_toCoreStmt actionFree) executed

/-- Evaluator-facing form of an invariant-aware reflection certificate. -/
theorem CommandReflectsWhen.ofExecutes
    {command : Stateful.Command Core.signature Stateful.actions arity}
    {admissible : ReadOnly.World → Env arity → Prop}
    (reflection : CommandReflectsWhen program registry command admissible)
    (inputAdmissible : admissible world environment)
    (actionFree : FreshSimulation.actionFree command = true)
    (represented : Representation layout localCell world environment before)
    (below : LayoutBelow layout nextLocal)
    (wellFormed : StateWellFormed before)
    (localsFresh : LocalsFresh frontier localCell)
    (nextFresh : frontier ≤ before.nextCell)
    (executed : Executes program before
      (Stateful.toCoreStmt actionAdapter layout nextLocal command)
      coreCompletion after) :
    Reflects program registry layout localCell frontier world environment before
      after command coreCompletion := by
  apply reflection inputAdmissible actionFree represented below wellFormed
    localsFresh nextFresh
  exact CoreSuccess.ofExecutes (supported_toCoreStmt actionFree) executed

end Lanius.Relational.CoreReflection
