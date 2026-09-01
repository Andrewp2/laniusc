import Lanius.FunctionalViewStateful

namespace Lanius.Relational.Semantics

open Lanius
open Lanius.Core
open Lanius.FunctionalView

/-! # Relational FunctionalView semantics

The executable FunctionalView machine maps every primitive operation to one
result. Compiler-function specifications instead describe every result and
state allowed by a relational contract. These judgments retain the existing
`Term` and `Stateful.Command` syntax while replacing only the primitive leaves
with relations. They describe successful behavior; safety and termination are
separate judgments.
-/

structure Machine (signature : Signature)
    (actions : Stateful.ActionSignature signature) where
  World : Type
  operation : World → (operation : signature.Op) → List Value →
    Value → World → Prop
  localUpdate : AssignOp → Value → Value → Value → Prop
  action : {arity : Nat} → World → Env arity →
    actions.Action arity → World → Prop

mutual

  inductive TermEvaluates
      (machine : Machine signature actions) {arity : Nat} :
      machine.World → Env arity → Term signature arity →
        Value → machine.World → Prop where
    | reference (reference : Ref arity) :
        TermEvaluates machine world environment (.reference reference)
          (reference.evaluate environment) world
    | apply
        (argumentsResult : TermsEvaluate machine world environment arguments
          values afterArguments)
        (operationResult : machine.operation afterArguments operation values
          result afterOperation) :
        TermEvaluates machine world environment (.apply operation arguments)
          result afterOperation
    | logicalAndFalse
        (leftResult : TermEvaluates machine world environment left
          (.boolean false) afterLeft) :
        TermEvaluates machine world environment (.logicalAnd left right)
          (.boolean false) afterLeft
    | logicalAndTrue
        (leftResult : TermEvaluates machine world environment left
          (.boolean true) afterLeft)
        (rightResult : TermEvaluates machine afterLeft environment right
          result afterRight) :
        TermEvaluates machine world environment (.logicalAnd left right)
          result afterRight
    | logicalOrTrue
        (leftResult : TermEvaluates machine world environment left
          (.boolean true) afterLeft) :
        TermEvaluates machine world environment (.logicalOr left right)
          (.boolean true) afterLeft
    | logicalOrFalse
        (leftResult : TermEvaluates machine world environment left
          (.boolean false) afterLeft)
        (rightResult : TermEvaluates machine afterLeft environment right
          result afterRight) :
        TermEvaluates machine world environment (.logicalOr left right)
          result afterRight

  inductive TermsEvaluate
      (machine : Machine signature actions) {arity : Nat} :
      machine.World → Env arity → List (Term signature arity) →
        List Value → machine.World → Prop where
    | nil : TermsEvaluate machine world environment [] [] world
    | cons
        (headResult : TermEvaluates machine world environment head
          value afterHead)
        (tailResult : TermsEvaluate machine afterHead environment tail
          values afterTail) :
        TermsEvaluate machine world environment (head :: tail)
          (value :: values) afterTail

end

/-- Constructor inversion for an application term. Kept beside the mutually
inductive judgments because Lean's generic `cases` tactic cannot always build
the dependent eliminator for this index shape. -/
theorem TermEvaluates.applyInversion
    (evaluated : TermEvaluates machine world environment
      (.apply operation arguments) value afterWorld) :
    ∃ values afterArguments,
      TermsEvaluate machine world environment arguments values afterArguments ∧
      machine.operation afterArguments operation values value afterWorld :=
  match evaluated with
  | .apply argumentsResult operationResult =>
      ⟨_, _, argumentsResult, operationResult⟩

/-- Constructor inversion for a reference term. -/
theorem TermEvaluates.referenceInversion
    (evaluated : TermEvaluates machine world environment
      (.reference ref) value afterWorld) :
    value = ref.evaluate environment ∧ afterWorld = world :=
  match evaluated with
  | .reference _ => ⟨rfl, rfl⟩

/-- Short-circuit inversion for logical conjunction. -/
theorem TermEvaluates.logicalAndInversion
    (evaluated : TermEvaluates machine world environment
      (.logicalAnd left right) value afterWorld) :
    (value = .boolean false ∧
      TermEvaluates machine world environment left (.boolean false) afterWorld) ∨
    (∃ afterLeft,
      TermEvaluates machine world environment left (.boolean true) afterLeft ∧
      TermEvaluates machine afterLeft environment right value afterWorld) :=
  match evaluated with
  | .logicalAndFalse leftResult => .inl ⟨rfl, leftResult⟩
  | .logicalAndTrue leftResult rightResult =>
      .inr ⟨_, leftResult, rightResult⟩

/-- Short-circuit inversion for logical disjunction. -/
theorem TermEvaluates.logicalOrInversion
    (evaluated : TermEvaluates machine world environment
      (.logicalOr left right) value afterWorld) :
    (value = .boolean true ∧
      TermEvaluates machine world environment left (.boolean true) afterWorld) ∨
    (∃ afterLeft,
      TermEvaluates machine world environment left (.boolean false) afterLeft ∧
      TermEvaluates machine afterLeft environment right value afterWorld) :=
  match evaluated with
  | .logicalOrTrue leftResult => .inl ⟨rfl, leftResult⟩
  | .logicalOrFalse leftResult rightResult =>
      .inr ⟨_, leftResult, rightResult⟩

/-- List-constructor inversion for relational argument evaluation. -/
theorem TermsEvaluate.consInversion
    (evaluated : TermsEvaluate machine world environment (head :: tail)
      values afterWorld) :
    ∃ value tailValues afterHead,
      values = value :: tailValues ∧
      TermEvaluates machine world environment head value afterHead ∧
      TermsEvaluate machine afterHead environment tail tailValues afterWorld :=
  match evaluated with
  | .cons headResult tailResult => ⟨_, _, _, rfl, headResult, tailResult⟩

/-- Empty-list inversion for relational argument evaluation. -/
theorem TermsEvaluate.nilInversion
    (evaluated : TermsEvaluate machine world environment [] values afterWorld) :
    values = [] ∧ afterWorld = world :=
  match evaluated with
  | .nil => ⟨rfl, rfl⟩

namespace Stateful

inductive CommandEvaluates
    (machine : Machine signature actions) :
    machine.World → Env arity →
      Lanius.FunctionalView.Stateful.Command signature actions arity →
      Lanius.FunctionalView.Stateful.Completion →
      machine.World → Env arity → Prop where
  | skip : CommandEvaluates machine world environment .skip .next
      world environment
  | sequenceNext
      (firstResult : CommandEvaluates machine world environment first .next
        afterFirst firstEnvironment)
      (secondResult : CommandEvaluates machine afterFirst firstEnvironment
        second completion afterSecond secondEnvironment) :
      CommandEvaluates machine world environment (.sequence first second)
        completion afterSecond secondEnvironment
  | sequenceStop
      (firstResult : CommandEvaluates machine world environment first
        completion afterFirst firstEnvironment)
      (stops : completion ≠ .next) :
      CommandEvaluates machine world environment (.sequence first second)
        completion afterFirst firstEnvironment
  | letValue
      (initializerResult : TermEvaluates machine world environment initializer
        value afterInitializer)
      (bodyResult : CommandEvaluates machine afterInitializer
        (environment.push value) body completion afterBody bodyEnvironment) :
      CommandEvaluates machine world environment
        (.letValue type initializer body) completion afterBody
        (Lanius.FunctionalView.Stateful.Env.pop bodyEnvironment)
  | setLocal
      (valueResult : TermEvaluates machine world environment value result
        afterValue) :
      CommandEvaluates machine world environment (.setLocal target value)
        .next afterValue
        (Lanius.FunctionalView.Stateful.Env.set environment target result)
  | updateLocal
      (valueResult : TermEvaluates machine world environment value right
        afterValue)
      (updateResult : machine.localUpdate operation (environment target) right
        result) :
      CommandEvaluates machine world environment
        (.updateLocal operation target value) .next afterValue
        (Lanius.FunctionalView.Stateful.Env.set environment target result)
  | action
      (actionResult : machine.action world environment operation afterWorld) :
      CommandEvaluates machine world environment (.action operation) .next
        afterWorld environment
  | ifTrue
      (conditionResult : TermEvaluates machine world environment condition
        (.boolean true) afterCondition)
      (branchResult : CommandEvaluates machine afterCondition environment
        thenBranch completion afterBranch branchEnvironment) :
      CommandEvaluates machine world environment
        (.ifThenElse condition thenBranch elseBranch) completion afterBranch
        branchEnvironment
  | ifFalse
      (conditionResult : TermEvaluates machine world environment condition
        (.boolean false) afterCondition)
      (branchResult : CommandEvaluates machine afterCondition environment
        elseBranch completion afterBranch branchEnvironment) :
      CommandEvaluates machine world environment
        (.ifThenElse condition thenBranch elseBranch) completion afterBranch
        branchEnvironment
  | whileFalse
      (conditionResult : TermEvaluates machine world environment condition
        (.boolean false) afterCondition) :
      CommandEvaluates machine world environment (.whileLoop condition body)
        .next afterCondition environment
  | whileNext
      (conditionResult : TermEvaluates machine world environment condition
        (.boolean true) afterCondition)
      (bodyResult : CommandEvaluates machine afterCondition environment body
        .next afterBody bodyEnvironment)
      (restResult : CommandEvaluates machine afterBody bodyEnvironment
        (.whileLoop condition body) completion afterLoop loopEnvironment) :
      CommandEvaluates machine world environment (.whileLoop condition body)
        completion afterLoop loopEnvironment
  | whileContinue
      (conditionResult : TermEvaluates machine world environment condition
        (.boolean true) afterCondition)
      (bodyResult : CommandEvaluates machine afterCondition environment body
        .continueLoop afterBody bodyEnvironment)
      (restResult : CommandEvaluates machine afterBody bodyEnvironment
        (.whileLoop condition body) completion afterLoop loopEnvironment) :
      CommandEvaluates machine world environment (.whileLoop condition body)
        completion afterLoop loopEnvironment
  | whileBreak
      (conditionResult : TermEvaluates machine world environment condition
        (.boolean true) afterCondition)
      (bodyResult : CommandEvaluates machine afterCondition environment body
        .breakLoop afterBody bodyEnvironment) :
      CommandEvaluates machine world environment (.whileLoop condition body)
        .next afterBody bodyEnvironment
  | whileReturn
      (conditionResult : TermEvaluates machine world environment condition
        (.boolean true) afterCondition)
      (bodyResult : CommandEvaluates machine afterCondition environment body
        (.returned value) afterBody bodyEnvironment) :
      CommandEvaluates machine world environment (.whileLoop condition body)
        (.returned value) afterBody bodyEnvironment
  | returnNone :
      CommandEvaluates machine world environment (.returnValue none)
        (.returned none) world environment
  | returnSome
      (valueResult : TermEvaluates machine world environment value result
        afterValue) :
      CommandEvaluates machine world environment (.returnValue (some value))
        (.returned (some result)) afterValue environment
  | breakLoop : CommandEvaluates machine world environment .breakLoop
      .breakLoop world environment
  | continueLoop : CommandEvaluates machine world environment .continueLoop
      .continueLoop world environment

end Stateful

end Lanius.Relational.Semantics
