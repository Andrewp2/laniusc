import Lanius.FunctionalView

namespace Lanius.FunctionalView.Stateful

open Lanius
open Lanius.Core
open Lanius.FunctionalView

/-! # Stateful functional reasoning

`FunctionalView.Block` is deliberately immutable: it removes physical local
cells from proofs of read-only code.  Compiler loops also need mutation, but
putting Core cell identities back into `Block` would destroy that abstraction.

This module adds a store-passing command language.  An `Env` is still a pure
function, and assignment returns a new `Env`; dialect actions return a new
abstract world.  The only recursive control relation is a finite derivation of
`whileLoop`, so total-correctness arguments use an algorithmic measure rather
than evaluator fuel.  A separate Core adapter connects these transitions to
the repository's separation logic.
-/

/-- Pure functional update of one scoped local. -/
def Env.set (environment : Env arity) (index : Fin arity) (value : Value) :
    Env arity :=
  fun candidate => if candidate = index then value else environment candidate

@[simp] theorem Env.set_same
    (environment : Env arity) (index : Fin arity) (value : Value) :
    Env.set environment index value index = value := by
  simp [Env.set]

@[simp] theorem Env.set_other
    (environment : Env arity) (index candidate : Fin arity) (value : Value)
    (different : candidate ≠ index) :
    Env.set environment index value candidate = environment candidate := by
  simp [Env.set, different]

/-- Forget the lexical binding introduced at the end of an environment while
    retaining functional updates to every outer binding. -/
def Env.pop (environment : Env (arity + 1)) : Env arity :=
  fun index => environment ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩

@[simp] theorem Env.pop_push
    (environment : Env arity) (value : Value) :
    Env.pop (environment.push value) = environment := by
  funext index
  exact Env.push_before environment value index

/-- Updating an outer binding commutes with forgetting the final lexical
    binding. This keeps scoped mutation proofs independent of the function
    representation used by `Env`. -/
@[simp] theorem Env.pop_set
    (environment : Env (arity + 1)) (index : Fin arity) (value : Value) :
    Env.pop (Env.set environment
      ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ value) =
    Env.set (Env.pop environment) index value := by
  funext candidate
  simp [Env.pop, Env.set, Fin.ext_iff]

/-- General form of `Env.pop_set` for an index already expressed in the
    extended environment. The bound states that the updated binding belongs
    to the outer scope rather than the binding being popped. -/
@[simp] theorem Env.pop_set_of_lt
    (environment : Env (arity + 1)) (index : Fin (arity + 1)) (value : Value)
    (before : index.val < arity) :
    Env.pop (Env.set environment index value) =
    Env.set (Env.pop environment) ⟨index.val, before⟩ value := by
  funext candidate
  simp [Env.pop, Env.set, Fin.ext_iff]

/-- A dialect-specific mutation has intrinsically scoped operands.  Its
    semantics changes the abstract world, never the immutable local
    environment.  Local assignment is a separate built-in command. -/
structure ActionSignature (termSignature : Signature) where
  Action : Nat → Type
  effect : {arity : Nat} → Action arity → EffectClass

/-- Successful action semantics.  Traps remain in `Except`; command proofs
    normally establish the successful equation once and compose it. -/
structure Machine (termMachine : FunctionalView.Machine termSignature)
    (actions : ActionSignature termSignature) where
  evalLocalUpdate : AssignOp → Value → Value → Except Trap Value
  evalAction : {arity : Nat} → termMachine.World → Env arity →
    actions.Action arity → Except Trap termMachine.World

/-- Structured stateful proof control.  `setLocal` is functional assignment;
    dialect actions cover resource mutation such as an indexed array write. -/
inductive Command (termSignature : Signature)
    (actions : ActionSignature termSignature) : Nat → Type where
  | skip {arity : Nat} : Command termSignature actions arity
  | sequence {arity : Nat}
      (first second : Command termSignature actions arity) :
      Command termSignature actions arity
  | letValue {arity : Nat} (type : Ty)
      (initializer : Term termSignature arity)
      (body : Command termSignature actions (arity + 1)) :
      Command termSignature actions arity
  | setLocal {arity : Nat} (target : Fin arity)
      (value : Term termSignature arity) : Command termSignature actions arity
  | updateLocal {arity : Nat} (operation : AssignOp) (target : Fin arity)
      (value : Term termSignature arity) : Command termSignature actions arity
  | action {arity : Nat} (operation : actions.Action arity) :
      Command termSignature actions arity
  | ifThenElse {arity : Nat} (condition : Term termSignature arity)
      (thenBranch elseBranch : Command termSignature actions arity) :
      Command termSignature actions arity
  | whileLoop {arity : Nat} (condition : Term termSignature arity)
      (body : Command termSignature actions arity) :
      Command termSignature actions arity
  | returnValue {arity : Nat} (value : Option (Term termSignature arity)) :
      Command termSignature actions arity
  | breakLoop {arity : Nat} : Command termSignature actions arity
  | continueLoop {arity : Nat} : Command termSignature actions arity

inductive Completion where
  | next
  | returned (value : Option Value)
  | breakLoop
  | continueLoop
deriving BEq, Repr

/-- Big-step functional semantics.  The relation contains only finite loop
    derivations.  A termination proof therefore constructs a finite chain of
    `whileNext`/`whileContinue` steps ending in one of the exit rules. -/
inductive Command.Evaluates
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions) :
    termMachine.World → Env arity → Command termSignature actions arity →
      Completion → termMachine.World → Env arity → Prop where
  | skip : Evaluates termMachine machine world environment .skip .next
      world environment
  | sequenceNext
      (firstResult : Evaluates termMachine machine beforeWorld
        beforeEnvironment firstCommand .next middleWorld middleEnvironment)
      (secondResult : Evaluates termMachine machine middleWorld
        middleEnvironment secondCommand completion afterWorld
        afterEnvironment) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.sequence firstCommand secondCommand) completion afterWorld
        afterEnvironment
  | sequenceStop
      (first : Evaluates termMachine machine beforeWorld beforeEnvironment
        firstCommand completion afterWorld afterEnvironment)
      (stops : completion ≠ .next) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.sequence firstCommand secondCommand) completion afterWorld
        afterEnvironment
  | letValue
      (initializerResult : Term.evaluate termMachine beforeWorld
        beforeEnvironment initializer = .ok (value, initializedWorld))
      (bodyResult : Evaluates termMachine machine initializedWorld
        (beforeEnvironment.push value) body completion afterWorld
        extendedEnvironment) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.letValue type initializer body) completion afterWorld
        (Env.pop extendedEnvironment)
  | setLocal
      (valueResult : Term.evaluate termMachine beforeWorld beforeEnvironment
        value = .ok (result, afterWorld)) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.setLocal target value) .next afterWorld
        (Env.set beforeEnvironment target result)
  | updateLocal
      (valueResult : Term.evaluate termMachine beforeWorld beforeEnvironment
        value = .ok (right, afterWorld))
      (updateResult : machine.evalLocalUpdate operation
        (beforeEnvironment target) right = .ok result) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.updateLocal operation target value) .next afterWorld
        (Env.set beforeEnvironment target result)
  | action
      (actionResult : machine.evalAction beforeWorld beforeEnvironment
        operation = .ok afterWorld) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.action operation) .next afterWorld beforeEnvironment
  | ifTrue
      (conditionResult : Term.evaluate termMachine beforeWorld
        beforeEnvironment condition = .ok (.boolean true, conditionWorld))
      (branchResult : Evaluates termMachine machine conditionWorld
        beforeEnvironment thenBranch completion afterWorld afterEnvironment) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.ifThenElse condition thenBranch elseBranch) completion afterWorld
        afterEnvironment
  | ifFalse
      (conditionResult : Term.evaluate termMachine beforeWorld
        beforeEnvironment condition = .ok (.boolean false, conditionWorld))
      (branchResult : Evaluates termMachine machine conditionWorld
        beforeEnvironment elseBranch completion afterWorld afterEnvironment) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.ifThenElse condition thenBranch elseBranch) completion afterWorld
        afterEnvironment
  | whileFalse
      (conditionResult : Term.evaluate termMachine beforeWorld
        beforeEnvironment condition = .ok (.boolean false, afterWorld)) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.whileLoop condition body) .next afterWorld beforeEnvironment
  | whileNext
      (conditionResult : Term.evaluate termMachine beforeWorld
        beforeEnvironment condition = .ok (.boolean true, conditionWorld))
      (bodyResult : Evaluates termMachine machine conditionWorld
        beforeEnvironment body .next bodyWorld bodyEnvironment)
      (restResult : Evaluates termMachine machine bodyWorld bodyEnvironment
        (.whileLoop condition body) completion afterWorld afterEnvironment) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.whileLoop condition body) completion afterWorld afterEnvironment
  | whileContinue
      (conditionResult : Term.evaluate termMachine beforeWorld
        beforeEnvironment condition = .ok (.boolean true, conditionWorld))
      (bodyResult : Evaluates termMachine machine conditionWorld
        beforeEnvironment body .continueLoop bodyWorld bodyEnvironment)
      (restResult : Evaluates termMachine machine bodyWorld bodyEnvironment
        (.whileLoop condition body) completion afterWorld afterEnvironment) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.whileLoop condition body) completion afterWorld afterEnvironment
  | whileBreak
      (conditionResult : Term.evaluate termMachine beforeWorld
        beforeEnvironment condition = .ok (.boolean true, conditionWorld))
      (bodyResult : Evaluates termMachine machine conditionWorld
        beforeEnvironment body .breakLoop afterWorld afterEnvironment) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.whileLoop condition body) .next afterWorld afterEnvironment
  | whileReturn
      (conditionResult : Term.evaluate termMachine beforeWorld
        beforeEnvironment condition = .ok (.boolean true, conditionWorld))
      (bodyResult : Evaluates termMachine machine conditionWorld
        beforeEnvironment body (.returned value) afterWorld afterEnvironment) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.whileLoop condition body) (.returned value) afterWorld
        afterEnvironment
  | returnNone :
      Evaluates termMachine machine world environment (.returnValue none)
        (.returned none) world environment
  | returnSome
      (valueResult : Term.evaluate termMachine beforeWorld beforeEnvironment
        value = .ok (result, afterWorld)) :
      Evaluates termMachine machine beforeWorld beforeEnvironment
        (.returnValue (some value)) (.returned (some result)) afterWorld
        beforeEnvironment
  | breakLoop :
      Evaluates termMachine machine world environment .breakLoop .breakLoop
        world environment
  | continueLoop :
      Evaluates termMachine machine world environment .continueLoop
        .continueLoop world environment

/-- Stateful FunctionalView commands have at most one successful result.
    This lets simulation proofs construct the canonical functional execution
    and identify any supplied derivation with it, instead of repeatedly
    inverting implementation-shaped sequencing trees. -/
theorem Command.Evaluates.deterministic
    (left : Command.Evaluates termMachine machine world environment command
      leftCompletion leftWorld leftEnvironment)
    (right : Command.Evaluates termMachine machine world environment command
      rightCompletion rightWorld rightEnvironment) :
    leftCompletion = rightCompletion ∧ leftWorld = rightWorld ∧
      leftEnvironment = rightEnvironment := by
  induction left generalizing rightCompletion rightWorld with
  | skip => cases right; exact ⟨rfl, rfl, rfl⟩
  | sequenceNext firstResult secondResult firstIH secondIH =>
      cases right with
      | sequenceNext rightFirst rightSecond =>
          obtain ⟨completionEq, worldEq, environmentEq⟩ :=
            firstIH rightFirst
          cases completionEq
          cases worldEq
          cases environmentEq
          exact secondIH rightSecond
      | sequenceStop rightFirst stops =>
          obtain ⟨completionEq, _, _⟩ := firstIH rightFirst
          exact False.elim (stops completionEq.symm)
  | sequenceStop firstResult stops firstIH =>
      cases right with
      | sequenceNext rightFirst rightSecond =>
          obtain ⟨completionEq, _, _⟩ := firstIH rightFirst
          exact False.elim (stops completionEq)
      | sequenceStop rightFirst rightStops => exact firstIH rightFirst
  | letValue initializerResult bodyResult bodyIH =>
      cases right with
      | letValue rightInitializer rightBody =>
          have initialized := initializerResult.symm.trans rightInitializer
          cases initialized
          obtain ⟨completionEq, worldEq, environmentEq⟩ := bodyIH rightBody
          exact ⟨completionEq, worldEq, congrArg Env.pop environmentEq⟩
  | setLocal valueResult =>
      cases right with
      | setLocal rightValue =>
          have resultEq := valueResult.symm.trans rightValue
          cases resultEq
          exact ⟨rfl, rfl, rfl⟩
  | updateLocal valueResult updateResult =>
      cases right with
      | updateLocal rightValue rightUpdate =>
          have valueEq := valueResult.symm.trans rightValue
          cases valueEq
          have updateEq := updateResult.symm.trans rightUpdate
          cases updateEq
          exact ⟨rfl, rfl, rfl⟩
  | action actionResult =>
      cases right with
      | action rightAction =>
          have resultEq := actionResult.symm.trans rightAction
          cases resultEq
          exact ⟨rfl, rfl, rfl⟩
  | ifTrue conditionResult branchResult branchIH =>
      cases right with
      | ifTrue rightCondition rightBranch =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          exact branchIH rightBranch
      | ifFalse rightCondition rightBranch =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
  | ifFalse conditionResult branchResult branchIH =>
      cases right with
      | ifTrue rightCondition rightBranch =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
      | ifFalse rightCondition rightBranch =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          exact branchIH rightBranch
  | whileFalse conditionResult =>
      cases right with
      | whileFalse rightCondition =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          exact ⟨rfl, rfl, rfl⟩
      | whileNext rightCondition _ _ =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
      | whileContinue rightCondition _ _ =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
      | whileBreak rightCondition _ =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
      | whileReturn rightCondition _ =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
  | whileNext conditionResult bodyResult restResult bodyIH restIH =>
      cases right with
      | whileFalse rightCondition =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
      | whileNext rightCondition rightBody rightRest =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, bodyWorldEq, bodyEnvironmentEq⟩ :=
            bodyIH rightBody
          cases bodyCompletionEq
          cases bodyWorldEq
          cases bodyEnvironmentEq
          exact restIH rightRest
      | whileContinue rightCondition rightBody rightRest =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileBreak rightCondition rightBody =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileReturn rightCondition rightBody =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
  | whileContinue conditionResult bodyResult restResult bodyIH restIH =>
      cases right with
      | whileFalse rightCondition =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
      | whileNext rightCondition rightBody rightRest =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileContinue rightCondition rightBody rightRest =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, bodyWorldEq, bodyEnvironmentEq⟩ :=
            bodyIH rightBody
          cases bodyCompletionEq
          cases bodyWorldEq
          cases bodyEnvironmentEq
          exact restIH rightRest
      | whileBreak rightCondition rightBody =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileReturn rightCondition rightBody =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
  | whileBreak conditionResult bodyResult bodyIH =>
      cases right with
      | whileFalse rightCondition =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
      | whileNext rightCondition rightBody _ =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileContinue rightCondition rightBody _ =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileBreak rightCondition rightBody =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, bodyWorldEq, bodyEnvironmentEq⟩ :=
            bodyIH rightBody
          cases bodyCompletionEq
          exact ⟨rfl, bodyWorldEq, bodyEnvironmentEq⟩
      | whileReturn rightCondition rightBody =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
  | whileReturn conditionResult bodyResult bodyIH =>
      cases right with
      | whileFalse rightCondition =>
          have impossible := conditionResult.symm.trans rightCondition
          simp at impossible
      | whileNext rightCondition rightBody _ =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileContinue rightCondition rightBody _ =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileBreak rightCondition rightBody =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          obtain ⟨bodyCompletionEq, _, _⟩ := bodyIH rightBody
          cases bodyCompletionEq
      | whileReturn rightCondition rightBody =>
          have conditionEq := conditionResult.symm.trans rightCondition
          cases conditionEq
          exact bodyIH rightBody
  | returnNone => cases right; exact ⟨rfl, rfl, rfl⟩
  | returnSome valueResult =>
      cases right with
      | returnSome rightValue =>
          have resultEq := valueResult.symm.trans rightValue
          cases resultEq
          exact ⟨rfl, rfl, rfl⟩
  | breakLoop => cases right; exact ⟨rfl, rfl, rfl⟩
  | continueLoop => cases right; exact ⟨rfl, rfl, rfl⟩

def Command.effect : Command termSignature actions arity → EffectClass
  | .skip | .breakLoop | .continueLoop | .returnValue none => .pure
  | .sequence first second => first.effect.join second.effect
  | .letValue _ initializer body => initializer.effect.join body.effect
  | .setLocal _ value | .updateLocal _ _ value => value.effect.join .write
  | .action operation => actions.effect operation
  | .ifThenElse condition thenBranch elseBranch =>
      (condition.effect.join thenBranch.effect).join elseBranch.effect
  | .whileLoop condition body => condition.effect.join body.effect
  | .returnValue (some value) => value.effect

end Lanius.FunctionalView.Stateful
