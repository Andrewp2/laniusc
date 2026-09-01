import Lanius.Relational.Semantics
import Lanius.FunctionalViewLoop

namespace Lanius.Relational.SemanticWP

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.Relational.Semantics

namespace Term

def WP (machine : Semantics.Machine signature actions)
    {arity : Nat} (term : FunctionalView.Term signature arity)
    (post : Value → machine.World → Prop)
    (world : machine.World) (environment : Env arity) : Prop :=
  ∀ value afterWorld,
    TermEvaluates machine world environment term value afterWorld →
    post value afterWorld

theorem intro
    (sound : ∀ value afterWorld,
      TermEvaluates machine world environment term value afterWorld →
      post value afterWorld) :
    WP machine term post world environment := sound

theorem apply
    (wp : WP machine term post world environment)
    (evaluated : TermEvaluates machine world environment term value afterWorld) :
    post value afterWorld := wp value afterWorld evaluated

end Term

namespace Command

variable {signature : Signature}
  {actions : FunctionalView.Stateful.ActionSignature signature}
  {arity : Nat}

abbrev Postcondition (World : Type) (arity : Nat) :=
  FunctionalView.Stateful.Completion → World → Env arity → Prop

abbrev Runtime (World : Type) (arity : Nat) := World × Env arity

def Runtime.world (runtime : Runtime World arity) : World := runtime.1

def Runtime.environment (runtime : Runtime World arity) : Env arity := runtime.2

def WP (machine : Semantics.Machine signature actions)
    {arity : Nat}
    (command : FunctionalView.Stateful.Command signature actions arity)
    (post : Postcondition machine.World arity)
    (world : machine.World) (environment : Env arity) : Prop :=
  ∀ completion afterWorld afterEnvironment,
    Semantics.Stateful.CommandEvaluates machine world environment command
      completion afterWorld afterEnvironment →
    post completion afterWorld afterEnvironment

theorem intro
    (sound : ∀ completion afterWorld afterEnvironment,
      Semantics.Stateful.CommandEvaluates machine world environment command
        completion afterWorld afterEnvironment →
      post completion afterWorld afterEnvironment) :
    WP machine command post world environment := sound

theorem apply
    (wp : WP machine command post world environment)
    (evaluated : Semantics.Stateful.CommandEvaluates machine world environment
      command completion afterWorld afterEnvironment) :
    post completion afterWorld afterEnvironment :=
  wp completion afterWorld afterEnvironment evaluated

theorem skip
    {machine : Semantics.Machine signature actions}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (next : post .next world environment) :
    WP machine .skip post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated
  exact next

theorem sequence
    {machine : Semantics.Machine signature actions}
    {firstCommand secondCommand :
      FunctionalView.Stateful.Command signature actions arity}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (hfirst : WP machine firstCommand
      (fun completion middleWorld middleEnvironment =>
        match completion with
        | .next => WP machine secondCommand post middleWorld middleEnvironment
        | stopped => post stopped middleWorld middleEnvironment)
      world environment) :
    WP machine (.sequence firstCommand secondCommand) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | sequenceNext firstResult secondResult =>
      exact hfirst _ _ _ firstResult _ _ _ secondResult
  | sequenceStop firstResult stops =>
      have stoppedPost := hfirst _ _ _ firstResult
      cases completion with
      | next => contradiction
      | returned | breakLoop | continueLoop => exact stoppedPost

theorem letValue
    {machine : Semantics.Machine signature actions}
    {type : Ty} {initializerTerm : FunctionalView.Term signature arity}
    {body : FunctionalView.Stateful.Command signature actions (arity + 1)}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (hinitializer : Term.WP machine initializerTerm
      (fun value initializedWorld =>
        WP machine body
          (fun completion afterWorld extendedEnvironment =>
            post completion afterWorld
              (FunctionalView.Stateful.Env.pop extendedEnvironment))
          initializedWorld (environment.push value))
      world environment) :
    WP machine (.letValue type initializerTerm body) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | letValue initializerResult bodyResult =>
      exact hinitializer _ _ initializerResult _ _ _ bodyResult

theorem setLocal
    {machine : Semantics.Machine signature actions}
    {target : Fin arity}
    {valueTerm : FunctionalView.Term signature arity}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (hvalue : Term.WP machine valueTerm
      (fun result afterWorld => post .next afterWorld
        (FunctionalView.Stateful.Env.set environment target result))
      world environment) :
    WP machine (.setLocal target valueTerm) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | setLocal valueResult => exact hvalue _ _ valueResult

theorem updateLocal
    {machine : Semantics.Machine signature actions}
    {operation : AssignOp} {target : Fin arity}
    {valueTerm : FunctionalView.Term signature arity}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (hvalue : Term.WP machine valueTerm
      (fun right afterWorld => ∀ result,
        machine.localUpdate operation (environment target) right result →
        post .next afterWorld
          (FunctionalView.Stateful.Env.set environment target result))
      world environment) :
    WP machine (.updateLocal operation target valueTerm) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | updateLocal valueResult updateResult =>
      exact hvalue _ _ valueResult _ updateResult

theorem action
    {machine : Semantics.Machine signature actions}
    {operation : actions.Action arity}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (effect : ∀ afterWorld,
      machine.action world environment operation afterWorld →
      post .next afterWorld environment) :
    WP machine (.action operation) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | action actionResult => exact effect _ actionResult

theorem ifThenElse
    {machine : Semantics.Machine signature actions}
    {condition : FunctionalView.Term signature arity}
    {thenBranch elseBranch :
      FunctionalView.Stateful.Command signature actions arity}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (hcondition : Term.WP machine condition
      (fun value conditionWorld =>
        (value = .boolean true →
          WP machine thenBranch post conditionWorld environment) ∧
        (value = .boolean false →
          WP machine elseBranch post conditionWorld environment))
      world environment) :
    WP machine (.ifThenElse condition thenBranch elseBranch) post world
      environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | ifTrue conditionResult branchResult =>
      exact (hcondition _ _ conditionResult).1 rfl _ _ _ branchResult
  | ifFalse conditionResult branchResult =>
      exact (hcondition _ _ conditionResult).2 rfl _ _ _ branchResult

theorem whileLoop
    {machine : Semantics.Machine signature actions}
    {condition : FunctionalView.Term signature arity}
    {body : FunctionalView.Stateful.Command signature actions arity}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (invariant : machine.World → Env arity → Prop)
    (initial : invariant world environment)
    (conditionFalse : ∀ beforeWorld beforeEnvironment afterWorld,
      invariant beforeWorld beforeEnvironment →
      TermEvaluates machine beforeWorld beforeEnvironment condition
        (.boolean false) afterWorld →
      post .next afterWorld beforeEnvironment)
    (conditionTrue : ∀ beforeWorld beforeEnvironment conditionWorld,
      invariant beforeWorld beforeEnvironment →
      TermEvaluates machine beforeWorld beforeEnvironment condition
        (.boolean true) conditionWorld →
      WP machine body
        (fun completion bodyWorld bodyEnvironment =>
          match completion with
          | .next | .continueLoop => invariant bodyWorld bodyEnvironment
          | .breakLoop => post .next bodyWorld bodyEnvironment
          | returned@(.returned _) => post returned bodyWorld bodyEnvironment)
        conditionWorld beforeEnvironment) :
    WP machine (.whileLoop condition body) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  generalize commandEq :
      (FunctionalView.Stateful.Command.whileLoop condition body) = command
      at evaluated
  induction evaluated with
  | skip => cases commandEq
  | sequenceNext _ _ _ _ => cases commandEq
  | sequenceStop _ _ _ => cases commandEq
  | letValue _ _ _ => cases commandEq
  | setLocal _ => cases commandEq
  | updateLocal _ _ => cases commandEq
  | action _ => cases commandEq
  | ifTrue _ _ _ => cases commandEq
  | ifFalse _ _ _ => cases commandEq
  | whileFalse conditionResult =>
      cases commandEq
      exact conditionFalse _ _ _ initial conditionResult
  | whileNext conditionResult bodyResult restResult bodyIH restIH =>
      cases commandEq
      have afterBody :=
        conditionTrue _ _ _ initial conditionResult _ _ _ bodyResult
      exact restIH invariant afterBody conditionFalse conditionTrue rfl
  | whileContinue conditionResult bodyResult restResult bodyIH restIH =>
      cases commandEq
      have afterBody :=
        conditionTrue _ _ _ initial conditionResult _ _ _ bodyResult
      exact restIH invariant afterBody conditionFalse conditionTrue rfl
  | whileBreak conditionResult bodyResult bodyIH =>
      cases commandEq
      exact conditionTrue _ _ _ initial conditionResult _ _ _ bodyResult
  | whileReturn conditionResult bodyResult bodyIH =>
      cases commandEq
      exact conditionTrue _ _ _ initial conditionResult _ _ _ bodyResult
  | returnNone => cases commandEq
  | returnSome _ => cases commandEq
  | breakLoop => cases commandEq
  | continueLoop => cases commandEq

theorem returnSome
    {machine : Semantics.Machine signature actions}
    {valueTerm : FunctionalView.Term signature arity}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (hvalue : Term.WP machine valueTerm
      (fun result afterWorld =>
        post (.returned (some result)) afterWorld environment)
      world environment) :
    WP machine (.returnValue (some valueTerm)) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | returnSome valueResult => exact hvalue _ _ valueResult

theorem returnNone
    {machine : Semantics.Machine signature actions}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (returned : post (.returned none) world environment) :
    WP machine (.returnValue none) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated
  exact returned

theorem breakLoop
    {machine : Semantics.Machine signature actions}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (stopped : post .breakLoop world environment) :
    WP machine .breakLoop post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated
  exact stopped

theorem continueLoop
    {machine : Semantics.Machine signature actions}
    {post : Postcondition machine.World arity}
    {world : machine.World} {environment : Env arity}
    (stopped : post .continueLoop world environment) :
    WP machine .continueLoop post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated
  exact stopped

namespace CursorScan

structure Spec
    (machine : Semantics.Machine signature actions)
    (condition : FunctionalView.Term signature arity)
    (body : FunctionalView.Stateful.Command signature actions arity)
    (runtime : Nat → Runtime machine.World arity)
    (limit : Nat) (accept : Nat → Bool) : Prop where
  conditionInBounds : ∀ cursor, cursor < limit →
    Term.WP machine condition
      (fun value afterWorld =>
        value = .boolean (accept cursor) ∧
        afterWorld = (runtime cursor).world)
      (runtime cursor).world (runtime cursor).environment
  conditionOutOfBounds : ∀ cursor, ¬ cursor < limit →
    Term.WP machine condition
      (fun value afterWorld =>
        value = .boolean false ∧ afterWorld = (runtime cursor).world)
      (runtime cursor).world (runtime cursor).environment
  body : ∀ cursor, cursor < limit → accept cursor = true →
    WP machine body
      (fun completion afterWorld afterEnvironment =>
        completion = .next ∧ afterWorld = (runtime (cursor + 1)).world ∧
        afterEnvironment = (runtime (cursor + 1)).environment)
      (runtime cursor).world (runtime cursor).environment

end CursorScan

theorem cursorScan
    {machine : Semantics.Machine signature actions}
    {condition : FunctionalView.Term signature arity}
    {body : FunctionalView.Stateful.Command signature actions arity}
    {limit : Nat} {accept : Nat → Bool} {finish : Nat → Nat}
    {runtime : Nat → Runtime machine.World arity}
    (spec : CursorScan.Spec machine condition body runtime limit accept)
    (recurrence : FunctionalView.Stateful.Loop.CursorScan.Recurrence
      limit accept finish)
    (initial : Nat) :
    WP machine (.whileLoop condition body)
      (fun completion afterWorld afterEnvironment =>
        completion = .next ∧
        afterWorld = (runtime (finish initial)).world ∧
        afterEnvironment = (runtime (finish initial)).environment)
      (runtime initial).world (runtime initial).environment := by
  apply whileLoop (machine := machine) (condition := condition) (body := body)
    (post := fun completion afterWorld afterEnvironment =>
      completion = .next ∧
      afterWorld = (runtime (finish initial)).world ∧
      afterEnvironment = (runtime (finish initial)).environment)
    (world := (runtime initial).world)
    (environment := (runtime initial).environment)
    (invariant := fun world environment =>
      ∃ cursor, world = (runtime cursor).world ∧
        environment = (runtime cursor).environment ∧
        finish cursor = finish initial)
  · exact ⟨initial, rfl, rfl, rfl⟩
  · intro beforeWorld beforeEnvironment afterWorld invariant evaluated
    obtain ⟨cursor, rfl, rfl, finishEq⟩ := invariant
    by_cases inBounds : cursor < limit
    · obtain ⟨valueEq, afterWorldEq⟩ :=
        spec.conditionInBounds cursor inBounds _ _ evaluated
      have rejected : accept cursor = false := by
        injection valueEq with same
        exact same.symm
      have cursorEq : cursor = finish initial :=
        (recurrence.rejected cursor inBounds rejected).symm.trans finishEq
      subst cursor
      exact ⟨rfl, afterWorldEq, rfl⟩
    · obtain ⟨_valueEq, afterWorldEq⟩ :=
        spec.conditionOutOfBounds cursor inBounds _ _ evaluated
      have cursorEq : cursor = finish initial :=
        (recurrence.outOfBounds cursor inBounds).symm.trans finishEq
      subst cursor
      exact ⟨rfl, afterWorldEq, rfl⟩
  · intro beforeWorld beforeEnvironment conditionWorld invariant evaluated
    obtain ⟨cursor, rfl, rfl, finishEq⟩ := invariant
    by_cases inBounds : cursor < limit
    · obtain ⟨valueEq, conditionWorldEq⟩ :=
        spec.conditionInBounds cursor inBounds _ _ evaluated
      have accepted : accept cursor = true := by
        injection valueEq with same
        exact same.symm
      subst conditionWorld
      intro completion afterWorld afterEnvironment bodyEvaluated
      obtain ⟨completionEq, afterWorldEq, afterEnvironmentEq⟩ :=
        spec.body cursor inBounds accepted _ _ _ bodyEvaluated
      subst completion
      subst afterWorld
      subst afterEnvironment
      exact ⟨cursor + 1, rfl, rfl,
        (recurrence.accepted cursor inBounds accepted).symm.trans finishEq⟩
    · obtain ⟨valueEq, _conditionWorldEq⟩ :=
        spec.conditionOutOfBounds cursor inBounds _ _ evaluated
      simp at valueEq

end Command

end Lanius.Relational.SemanticWP
