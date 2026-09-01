import Lanius.FunctionalViewStateful
import Lanius.FunctionalViewLoop

namespace Lanius.Relational

open Lanius
open Lanius.Core
open Lanius.FunctionalView

/-! # Relational weakest preconditions for FunctionalView

These definitions state partial correctness directly over the existing
FunctionalView semantics. The constructor rules are the stable API intended
for VC generation; proof clients do not construct `Command.Evaluates` trees.
The Core adequacy layer remains separate.
-/

namespace Term

def WP {signature : Signature} (machine : FunctionalView.Machine signature)
    {arity : Nat} (term : FunctionalView.Term signature arity)
    (post : Value → machine.World → Prop)
    (world : machine.World) (environment : Env arity) : Prop :=
  ∀ value afterWorld,
    FunctionalView.Term.evaluate machine world environment term =
      .ok (value, afterWorld) →
    post value afterWorld

theorem intro {signature : Signature}
    {machine : FunctionalView.Machine signature}
    {arity : Nat} {term : FunctionalView.Term signature arity}
    {post : Value → machine.World → Prop}
    {world : machine.World} {environment : Env arity}
    (sound : ∀ value afterWorld,
      FunctionalView.Term.evaluate machine world environment term =
        .ok (value, afterWorld) →
      post value afterWorld) :
    WP machine term post world environment :=
  sound

theorem apply {signature : Signature}
    {machine : FunctionalView.Machine signature}
    {arity : Nat} {term : FunctionalView.Term signature arity}
    {post : Value → machine.World → Prop}
    {world afterWorld : machine.World} {environment : Env arity}
    {value : Value}
    (wp : WP machine term post world environment)
    (evaluated : FunctionalView.Term.evaluate machine world environment term =
      .ok (value, afterWorld)) :
    post value afterWorld :=
  wp value afterWorld evaluated

end Term

namespace Command

abbrev Postcondition (World : Type) (arity : Nat) :=
  Stateful.Completion → World → Env arity → Prop

def WP {termSignature : Signature}
    (termMachine : FunctionalView.Machine termSignature)
    {actions : Stateful.ActionSignature termSignature}
    (machine : Stateful.Machine termMachine actions)
    {arity : Nat}
    (command : Stateful.Command termSignature actions arity)
    (post : Postcondition termMachine.World arity)
    (world : termMachine.World) (environment : Env arity) : Prop :=
  ∀ completion afterWorld afterEnvironment,
    Stateful.Command.Evaluates termMachine machine world environment command
      completion afterWorld afterEnvironment →
    post completion afterWorld afterEnvironment

theorem intro {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat}
    {command : Stateful.Command termSignature actions arity}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (sound : ∀ completion afterWorld afterEnvironment,
      Stateful.Command.Evaluates termMachine machine world environment command
        completion afterWorld afterEnvironment →
      post completion afterWorld afterEnvironment) :
    WP termMachine machine command post world environment :=
  sound

theorem apply {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat}
    {command : Stateful.Command termSignature actions arity}
    {post : Postcondition termMachine.World arity}
    {world afterWorld : termMachine.World}
    {environment afterEnvironment : Env arity}
    {completion : Stateful.Completion}
    (wp : WP termMachine machine command post world environment)
    (evaluated : Stateful.Command.Evaluates termMachine machine world
      environment command completion afterWorld afterEnvironment) :
    post completion afterWorld afterEnvironment :=
  wp completion afterWorld afterEnvironment evaluated

@[simp] theorem skip {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat} {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity} :
    WP termMachine machine
      (.skip : Stateful.Command termSignature actions arity)
      post world environment ↔ post .next world environment := by
  constructor
  · intro wp
    exact wp _ _ _ Stateful.Command.Evaluates.skip
  · intro result _ _ _ evaluated
    cases evaluated
    exact result

theorem sequence {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat}
    {firstCommand secondCommand :
      Stateful.Command termSignature actions arity}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (hfirst : WP termMachine machine firstCommand
      (fun completion middleWorld middleEnvironment =>
        match completion with
        | .next => WP termMachine machine secondCommand post
            middleWorld middleEnvironment
        | stopped => post stopped middleWorld middleEnvironment)
      world environment) :
    WP termMachine machine (.sequence firstCommand secondCommand)
      post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | sequenceNext firstResult secondResult =>
      exact hfirst _ _ _ firstResult _ _ _ secondResult
  | sequenceStop firstResult stops =>
      have stoppedPost := hfirst _ _ _ firstResult
      cases completion with
      | next => contradiction
      | returned | breakLoop | continueLoop => exact stoppedPost

theorem letValue {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat} {type : Ty}
    {initializerTerm : FunctionalView.Term termSignature arity}
    {body : Stateful.Command termSignature actions (arity + 1)}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (hinitializer : Term.WP termMachine initializerTerm
      (fun value initializedWorld =>
        WP termMachine machine body
          (fun completion afterWorld
              (extendedEnvironment : Env (arity + 1)) =>
            post completion afterWorld (Stateful.Env.pop extendedEnvironment))
          initializedWorld (environment.push value))
      world environment) :
    WP termMachine machine (.letValue type initializerTerm body)
      post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | letValue initializerResult bodyResult =>
      exact hinitializer _ _ initializerResult _ _ _ bodyResult

theorem setLocal {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat} {target : Fin arity}
    {valueTerm : FunctionalView.Term termSignature arity}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (hvalue : Term.WP termMachine valueTerm
      (fun result afterWorld => post .next afterWorld
        (Stateful.Env.set environment target result))
      world environment) :
    WP termMachine machine (.setLocal target valueTerm)
      post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | setLocal valueResult => exact hvalue _ _ valueResult

theorem updateLocal {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat} {operation : AssignOp} {target : Fin arity}
    {valueTerm : FunctionalView.Term termSignature arity}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (hvalue : Term.WP termMachine valueTerm
      (fun right afterWorld => ∀ result,
        machine.evalLocalUpdate operation (environment target) right =
          .ok result →
        post .next afterWorld (Stateful.Env.set environment target result))
      world environment) :
    WP termMachine machine (.updateLocal operation target valueTerm)
      post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | updateLocal valueResult updateResult =>
      exact hvalue _ _ valueResult _ updateResult

theorem action {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat} {operation : actions.Action arity}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (effect : ∀ afterWorld,
      machine.evalAction world environment operation = .ok afterWorld →
      post .next afterWorld environment) :
    WP termMachine machine (.action operation) post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | action actionResult => exact effect _ actionResult

theorem ifThenElse {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat}
    {conditionTerm : FunctionalView.Term termSignature arity}
    {thenBranch elseBranch : Stateful.Command termSignature actions arity}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (hcondition : Term.WP termMachine conditionTerm
      (fun value conditionWorld =>
        (value = .boolean true →
          WP termMachine machine thenBranch post conditionWorld environment) ∧
        (value = .boolean false →
          WP termMachine machine elseBranch post conditionWorld environment))
      world environment) :
    WP termMachine machine
      (.ifThenElse conditionTerm thenBranch elseBranch)
      post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | ifTrue conditionResult branchResult =>
      exact (hcondition _ _ conditionResult).1 rfl _ _ _ branchResult
  | ifFalse conditionResult branchResult =>
      exact (hcondition _ _ conditionResult).2 rfl _ _ _ branchResult

/-- Partial-correctness loop rule. A decreasing measure is unnecessary here:
the supplied successful evaluation is finite, while the invariant accounts
for every possible normal, `continue`, `break`, and returned completion. -/
theorem whileLoop {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat}
    {condition : FunctionalView.Term termSignature arity}
    {body : Stateful.Command termSignature actions arity}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (invariant : termMachine.World → Env arity → Prop)
    (initial : invariant world environment)
    (conditionFalse : ∀ beforeWorld beforeEnvironment afterWorld,
      invariant beforeWorld beforeEnvironment →
      FunctionalView.Term.evaluate termMachine beforeWorld beforeEnvironment
        condition = .ok (.boolean false, afterWorld) →
      post .next afterWorld beforeEnvironment)
    (conditionTrue : ∀ beforeWorld beforeEnvironment conditionWorld,
      invariant beforeWorld beforeEnvironment →
      FunctionalView.Term.evaluate termMachine beforeWorld beforeEnvironment
        condition = .ok (.boolean true, conditionWorld) →
      WP termMachine machine body
        (fun completion bodyWorld bodyEnvironment =>
          match completion with
          | .next | .continueLoop => invariant bodyWorld bodyEnvironment
          | .breakLoop => post .next bodyWorld bodyEnvironment
          | returned@(.returned _) =>
              post returned bodyWorld bodyEnvironment)
        conditionWorld beforeEnvironment) :
    WP termMachine machine (.whileLoop condition body)
      post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  generalize commandEq :
      (Stateful.Command.whileLoop condition body) = command at evaluated
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

/-- Invariant-based partial correctness for a bounded cursor scan. Unlike
`FunctionalView.Stateful.Loop.CursorScan.run`, this theorem does not construct
a complete trace or require termination: it characterizes any supplied finite
successful loop execution from the three recurrence equations. -/
theorem cursorScan
    {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat}
    {condition : FunctionalView.Term termSignature arity}
    {body : Stateful.Command termSignature actions arity}
    {runtime : Nat → Stateful.Loop.Runtime termMachine arity}
    {limit : Nat} {accept : Nat → Bool} {finish : Nat → Nat}
    (spec : Stateful.Loop.CursorScan.Spec termMachine machine condition body
      runtime limit accept)
    (recurrence : Stateful.Loop.CursorScan.Recurrence limit accept finish)
    (initial : Nat) :
    WP termMachine machine (.whileLoop condition body)
      (fun completion afterWorld afterEnvironment =>
        completion = .next ∧
        afterWorld = (runtime (finish initial)).world ∧
        afterEnvironment = (runtime (finish initial)).environment)
      (runtime initial).world (runtime initial).environment := by
  apply whileLoop (termMachine := termMachine) (machine := machine)
    (condition := condition) (body := body)
    (post := fun completion afterWorld afterEnvironment =>
      completion = .next ∧
      afterWorld = (runtime (finish initial)).world ∧
      afterEnvironment = (runtime (finish initial)).environment)
    (world := (runtime initial).world)
    (environment := (runtime initial).environment)
    (invariant := fun world environment =>
      ∃ cursor,
        world = (runtime cursor).world ∧
        environment = (runtime cursor).environment ∧
        finish cursor = finish initial)
  · exact ⟨initial, rfl, rfl, rfl⟩
  · intro beforeWorld beforeEnvironment afterWorld invariant evaluated
    obtain ⟨cursor, beforeWorldEq, beforeEnvironmentEq, finishEq⟩ := invariant
    subst beforeWorld
    subst beforeEnvironment
    by_cases inBounds : cursor < limit
    · have canonical := spec.conditionInBounds cursor inBounds
      have same := evaluated.symm.trans canonical
      injection same with pairEq
      have rejected : accept cursor = false := by
        have valueEq := congrArg Prod.fst pairEq
        exact (Value.boolean.inj valueEq).symm
      have afterWorldEq : afterWorld = (runtime cursor).world := by
        exact congrArg Prod.snd pairEq
      have cursorEq : cursor = finish initial := by
        exact (recurrence.rejected cursor inBounds rejected).symm.trans finishEq
      subst cursor
      exact ⟨rfl, afterWorldEq, rfl⟩
    · have canonical := spec.conditionOutOfBounds cursor inBounds
      have same := evaluated.symm.trans canonical
      injection same with pairEq
      have afterWorldEq : afterWorld = (runtime cursor).world := by
        exact congrArg Prod.snd pairEq
      have cursorEq : cursor = finish initial := by
        exact (recurrence.outOfBounds cursor inBounds).symm.trans finishEq
      subst cursor
      exact ⟨rfl, afterWorldEq, rfl⟩
  · intro beforeWorld beforeEnvironment conditionWorld invariant evaluated
    obtain ⟨cursor, beforeWorldEq, beforeEnvironmentEq, finishEq⟩ := invariant
    subst beforeWorld
    subst beforeEnvironment
    by_cases inBounds : cursor < limit
    · have canonical := spec.conditionInBounds cursor inBounds
      have same := evaluated.symm.trans canonical
      injection same with pairEq
      have accepted : accept cursor = true := by
        have valueEq := congrArg Prod.fst pairEq
        exact (Value.boolean.inj valueEq).symm
      have conditionWorldEq : conditionWorld = (runtime cursor).world := by
        exact congrArg Prod.snd pairEq
      subst conditionWorld
      intro completion bodyWorld bodyEnvironment bodyEvaluated
      have canonicalBody := spec.body cursor inBounds accepted
      obtain ⟨completionEq, bodyWorldEq, bodyEnvironmentEq⟩ :=
        Stateful.Command.Evaluates.deterministic bodyEvaluated canonicalBody
      subst completion
      subst bodyWorld
      subst bodyEnvironment
      exact ⟨cursor + 1, rfl, rfl,
        (recurrence.accepted cursor inBounds accepted).symm.trans finishEq⟩
    · have canonical := spec.conditionOutOfBounds cursor inBounds
      have same := evaluated.symm.trans canonical
      injection same with pairEq
      have valueEq := congrArg Prod.fst pairEq
      cases Value.boolean.inj valueEq

@[simp] theorem returnNone {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat} {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity} :
    WP termMachine machine
      (.returnValue none : Stateful.Command termSignature actions arity)
      post world environment ↔
      post (.returned none) world environment := by
  constructor
  · intro wp
    exact wp _ _ _ Stateful.Command.Evaluates.returnNone
  · intro result _ _ _ evaluated
    cases evaluated
    exact result

theorem returnSome {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat}
    {valueTerm : FunctionalView.Term termSignature arity}
    {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity}
    (hvalue : Term.WP termMachine valueTerm
      (fun result afterWorld =>
        post (.returned (some result)) afterWorld environment)
      world environment) :
    WP termMachine machine (.returnValue (some valueTerm))
      post world environment := by
  intro completion afterWorld afterEnvironment evaluated
  cases evaluated with
  | returnSome valueResult => exact hvalue _ _ valueResult

@[simp] theorem breakLoop {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat} {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity} :
    WP termMachine machine
      (.breakLoop : Stateful.Command termSignature actions arity)
      post world environment ↔ post .breakLoop world environment := by
  constructor
  · intro wp
    exact wp _ _ _ Stateful.Command.Evaluates.breakLoop
  · intro result _ _ _ evaluated
    cases evaluated
    exact result

@[simp] theorem continueLoop {termSignature : Signature}
    {termMachine : FunctionalView.Machine termSignature}
    {actions : Stateful.ActionSignature termSignature}
    {machine : Stateful.Machine termMachine actions}
    {arity : Nat} {post : Postcondition termMachine.World arity}
    {world : termMachine.World} {environment : Env arity} :
    WP termMachine machine
      (.continueLoop : Stateful.Command termSignature actions arity)
      post world environment ↔ post .continueLoop world environment := by
  constructor
  · intro wp
    exact wp _ _ _ Stateful.Command.Evaluates.continueLoop
  · intro result _ _ _ evaluated
    cases evaluated
    exact result

end Command

end Lanius.Relational
