import Lanius.Typing

namespace Lanius.FunctionalView

open Lanius
open Lanius.Core
open Lanius.Typing

/-! # Functional reasoning view

`Core` is the faithful executable semantics of Lanius. Its lexical locals are
implemented by fresh physical cells, which is useful for defining calls and
aliasing but needlessly exposes allocation and scope restoration in proofs of
read-only computations.

This module defines a second, functional proof view. Local references
are intrinsically scoped `Fin` indices, environments are immutable functions,
and primitive operations are supplied by an effect signature. A separate
adapter proves that converting this representation back to structural Core
preserves its functional evaluation. FunctionalView does not replace Core
semantics; it is a verified reasoning view over Core.
-/

inductive EffectClass where
  | pure
  | read
  | write
  | external
deriving BEq, DecidableEq, Repr

def EffectClass.join : EffectClass → EffectClass → EffectClass
  | .pure, effect | effect, .pure => effect
  | .read, .read => .read
  | .external, _ | _, .external => .external
  | _, _ => .write

@[simp] theorem EffectClass.pure_join (effect : EffectClass) :
    EffectClass.join .pure effect = effect := by
  cases effect <;> rfl

@[simp] theorem EffectClass.join_pure (effect : EffectClass) :
    EffectClass.join effect .pure = effect := by
  cases effect <;> rfl

/-- A dialect supplies semantic operations without fixing how they are
    represented by structural Core or by a particular compiler backend. -/
structure Signature where
  Op : Type
  operandTypes : Op → List Ty
  resultType : Op → Ty
  effect : Op → EffectClass

/-- Intrinsically scoped reference into an immutable value environment. -/
inductive Ref (arity : Nat) where
  | slot (index : Fin arity)
  | literal (value : Value)
deriving Repr

abbrev Env (arity : Nat) := Fin arity → Value
abbrev TypeEnv (arity : Nat) := Fin arity → Ty

def Env.push (environment : Env arity) (value : Value) : Env (arity + 1) :=
  fun index =>
    if before : index.val < arity then
      environment ⟨index.val, before⟩
    else
      value

@[simp] theorem Env.push_last (environment : Env arity) (value : Value) :
    environment.push value ⟨arity, Nat.lt_succ_self arity⟩ = value := by
  simp [Env.push]

@[simp] theorem Env.push_before (environment : Env arity) (value : Value)
    (index : Fin arity) :
    environment.push value ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ =
      environment index := by
  simp [Env.push, index.isLt]

/-- Read an arbitrary non-final slot from an extended environment.  Unlike
    `push_before`, this form accepts the caller's existing `Fin (arity + 1)`
    index and an explicit numeric bound, avoiding proof-term-sensitive index
    rewrites in reified compiler layouts. -/
@[simp] theorem Env.push_of_lt (environment : Env arity) (value : Value)
    (index : Fin (arity + 1)) (before : index.val < arity) :
    environment.push value index = environment ⟨index.val, before⟩ := by
  simp [Env.push, before]

def TypeEnv.push (environment : TypeEnv arity) (type : Ty) :
    TypeEnv (arity + 1) :=
  fun index =>
    if before : index.val < arity then
      environment ⟨index.val, before⟩
    else
      type

def Ref.evaluate (environment : Env arity) : Ref arity → Value
  | .slot index => environment index
  | .literal value => value

/-- Pure syntax over immutable references. Effects belong to primitive
    operations; expression structure only sequences their value demands. -/
inductive Term (signature : Signature) (arity : Nat) where
  | reference (reference : Ref arity)
  | apply (operation : signature.Op)
      (arguments : List (Term signature arity))
  | logicalAnd (left right : Term signature arity)
  | logicalOr (left right : Term signature arity)

/-- Structured proof control. `letValue` extends only the immutable proof
    environment. No physical allocation identity appears in this view. -/
inductive Block (signature : Signature) : Nat → Type where
  | skip {arity : Nat} : Block signature arity
  | sequence {arity : Nat} (first second : Block signature arity) :
      Block signature arity
  | letValue {arity : Nat} (type : Ty) (initializer : Term signature arity)
      (body : Block signature (arity + 1)) : Block signature arity
  | ifThenElse {arity : Nat} (condition : Term signature arity)
      (thenBranch elseBranch : Block signature arity) : Block signature arity
  | returnValue {arity : Nat} (value : Option (Term signature arity)) :
      Block signature arity

inductive Completion where
  | next
  | returned (value : Option Value)
deriving BEq, Repr

inductive Result (world : Type) where
  | done (completion : Completion) (world : world)
  | trapped (reason : Trap) (world : world)
deriving Repr

/-- Executable semantics for one proof dialect. The world is explicit so the
    same view can grow from pure/read-only parser code to allocation and host
    effects without changing its control representation. -/
structure Machine (signature : Signature) where
  World : Type
  evalOperation : World → (operation : signature.Op) →
    List Value → Except Trap (Value × World)

mutual

  def Term.evaluate (machine : Machine signature) :
      machine.World → Env arity → Term signature arity →
        Except Trap (Value × machine.World)
    | world, environment, .reference reference =>
        .ok (reference.evaluate environment, world)
    | world, environment, .apply operation arguments => do
        let (values, nextWorld) ← evaluateTerms machine world environment arguments
        machine.evalOperation nextWorld operation values
    | world, environment, .logicalAnd left right => do
        let (leftValue, afterLeft) ← left.evaluate machine world environment
        match leftValue with
        | .boolean false => .ok (.boolean false, afterLeft)
        | .boolean true => right.evaluate machine afterLeft environment
        | _ => .error .typeMismatch
    | world, environment, .logicalOr left right => do
        let (leftValue, afterLeft) ← left.evaluate machine world environment
        match leftValue with
        | .boolean true => .ok (.boolean true, afterLeft)
        | .boolean false => right.evaluate machine afterLeft environment
        | _ => .error .typeMismatch

  def evaluateTerms (machine : Machine signature) :
      machine.World → Env arity → List (Term signature arity) →
        Except Trap (List Value × machine.World)
    | world, _, [] => .ok ([], world)
    | world, environment, argument :: arguments => do
        let (value, afterArgument) ← argument.evaluate machine world environment
        let (values, afterArguments) ←
          evaluateTerms machine afterArgument environment arguments
        .ok (value :: values, afterArguments)

end

def Block.evaluate (machine : Machine signature) :
    machine.World → Env arity → Block signature arity → Result machine.World
  | world, _, .skip => .done .next world
  | world, environment, .sequence first second =>
      match first.evaluate machine world environment with
      | .done .next afterFirst => second.evaluate machine afterFirst environment
      | .done returned@(.returned _) afterFirst => .done returned afterFirst
      | .trapped reason afterFirst => .trapped reason afterFirst
  | world, environment, .letValue _ initializer body =>
      match initializer.evaluate machine world environment with
      | .error reason => .trapped reason world
      | .ok (value, afterInitializer) =>
          body.evaluate machine afterInitializer (environment.push value)
  | world, environment, .ifThenElse condition thenBranch elseBranch =>
      match condition.evaluate machine world environment with
      | .error reason => .trapped reason world
      | .ok (.boolean true, afterCondition) =>
          thenBranch.evaluate machine afterCondition environment
      | .ok (.boolean false, afterCondition) =>
          elseBranch.evaluate machine afterCondition environment
      | .ok (_, afterCondition) => .trapped .typeMismatch afterCondition
  | world, _, .returnValue none => .done (.returned none) world
  | world, environment, .returnValue (some value) =>
      match value.evaluate machine world environment with
      | .error reason => .trapped reason world
      | .ok (result, afterValue) => .done (.returned (some result)) afterValue

/-- Construct a sequence without administrative `skip` nodes. This is a
    proof-view normalization, not a compiler lowering pass. -/
def Block.sequenceNormalized (first second : Block signature arity) :
    Block signature arity :=
  match first, second with
  | .skip, second => second
  | first, .skip => first
  | first, second => .sequence first second

/-- Remove administrative `skip` nodes recursively from a functional view. -/
def Block.normalize : Block signature arity → Block signature arity
  | .skip => .skip
  | .sequence first second =>
      sequenceNormalized first.normalize second.normalize
  | .letValue type initializer body =>
      .letValue type initializer body.normalize
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse condition thenBranch.normalize elseBranch.normalize
  | .returnValue value => .returnValue value

private theorem Block.evaluate_sequence_skip
    (machine : Machine signature) (world : machine.World)
    (environment : Env arity) (first : Block signature arity) :
    Block.evaluate machine world environment (.sequence first .skip) =
      Block.evaluate machine world environment first := by
  rw [Block.evaluate]
  generalize evaluated : Block.evaluate machine world environment first = result
  cases result with
  | trapped => rfl
  | done completion =>
      cases completion <;> simp only [Block.evaluate]

private theorem Block.evaluate_sequenceNormalized
    (machine : Machine signature) (world : machine.World)
    (environment : Env arity) (first second : Block signature arity) :
    Block.evaluate machine world environment
        (sequenceNormalized first second) =
      Block.evaluate machine world environment (.sequence first second) := by
  cases first <;> cases second <;> simp only [sequenceNormalized] <;>
    try rfl
  all_goals exact (evaluate_sequence_skip machine world environment _).symm

/-- Normalization changes presentation only; every machine observes the same
    completion, world, and trap. -/
theorem Block.evaluate_normalize
    (machine : Machine signature) (world : machine.World)
    (environment : Env arity) (block : Block signature arity) :
    Block.evaluate machine world environment block.normalize =
      Block.evaluate machine world environment block := by
  induction block generalizing world with
  | skip | returnValue => rfl
  | sequence first second firstInduction secondInduction =>
      rw [Block.normalize, evaluate_sequenceNormalized]
      simp only [Block.evaluate]
      rw [firstInduction]
      cases evaluated : Block.evaluate machine world environment first with
      | trapped => rfl
      | done completion afterFirst =>
          cases completion with
          | returned => rfl
          | next => exact secondInduction afterFirst environment
  | letValue type initializer body induction =>
      simp only [Block.normalize, Block.evaluate]
      cases evaluated : Term.evaluate machine world environment initializer with
      | error => rfl
      | ok result =>
          obtain ⟨value, afterInitializer⟩ := result
          exact induction afterInitializer (environment.push value)
  | ifThenElse condition thenBranch elseBranch thenInduction elseInduction =>
      simp only [Block.normalize, Block.evaluate]
      cases evaluated : Term.evaluate machine world environment condition with
      | error => rfl
      | ok result =>
          obtain ⟨value, afterCondition⟩ := result
          cases value with
          | boolean value =>
              cases value
              · exact elseInduction afterCondition environment
              · exact thenInduction afterCondition environment
          | _ => rfl

@[simp] theorem Term.evaluate_reference
    (machine : Machine signature) (world : machine.World)
    (environment : Env arity) (reference : Ref arity) :
    Term.evaluate machine world environment (.reference reference) =
      .ok (reference.evaluate environment, world) := by
  rfl

theorem Term.evaluate_slot
    (found : environment index = value) :
    Term.evaluate machine world environment (.reference (.slot index)) =
      .ok (value, world) := by
  simp only [Term.evaluate, Ref.evaluate, found]

theorem Term.evaluate_congr
    (evaluated : Term.evaluate machine world environment term =
      .ok (actual, afterWorld))
    (same : actual = expected) :
    Term.evaluate machine world environment term =
      .ok (expected, afterWorld) := by
  simpa [same] using evaluated

theorem Term.evaluate_apply
    (argumentsResult : evaluateTerms machine world environment arguments =
      .ok (values, afterArguments))
    (operationResult : machine.evalOperation afterArguments operation values =
      .ok (value, afterOperation)) :
    Term.evaluate machine world environment (.apply operation arguments) =
      .ok (value, afterOperation) := by
  rw [Term.evaluate]
  rw [argumentsResult]
  exact operationResult

@[simp] theorem evaluateTerms_nil
    (machine : Machine signature) (world : machine.World)
    (environment : Env arity) :
    evaluateTerms machine world environment [] = .ok ([], world) := by
  rfl

theorem evaluateTerms_cons
    (headResult : Term.evaluate machine world environment head =
      .ok (value, afterHead))
    (tailResult : evaluateTerms machine afterHead environment tail =
      .ok (values, afterTail)) :
    evaluateTerms machine world environment (head :: tail) =
      .ok (value :: values, afterTail) := by
  rw [evaluateTerms]
  rw [headResult]
  simp only [bind, Except.bind]
  rw [tailResult]

theorem Term.evaluate_apply0
    (operationResult : machine.evalOperation world operation [] =
      .ok (value, afterOperation)) :
    Term.evaluate machine world environment (.apply operation []) =
      .ok (value, afterOperation) :=
  Term.evaluate_apply (evaluateTerms_nil machine world environment)
    operationResult

theorem Term.evaluate_apply1
    (argumentResult : Term.evaluate machine world environment argument =
      .ok (argumentValue, afterArgument))
    (operationResult : machine.evalOperation afterArgument operation
      [argumentValue] = .ok (value, afterOperation)) :
    Term.evaluate machine world environment (.apply operation [argument]) =
      .ok (value, afterOperation) := by
  apply Term.evaluate_apply
    (evaluateTerms_cons argumentResult
      (evaluateTerms_nil machine afterArgument environment))
  exact operationResult

theorem Term.evaluate_apply2
    (leftResult : Term.evaluate machine world environment left =
      .ok (leftValue, afterLeft))
    (rightResult : Term.evaluate machine afterLeft environment right =
      .ok (rightValue, afterRight))
    (operationResult : machine.evalOperation afterRight operation
      [leftValue, rightValue] = .ok (value, afterOperation)) :
    Term.evaluate machine world environment
        (.apply operation [left, right]) =
      .ok (value, afterOperation) := by
  apply Term.evaluate_apply
    (evaluateTerms_cons leftResult
      (evaluateTerms_cons rightResult
        (evaluateTerms_nil machine afterRight environment)))
  exact operationResult

theorem Term.evaluate_logicalAnd_false
    (leftResult : Term.evaluate machine world environment left =
      .ok (.boolean false, afterLeft)) :
    Term.evaluate machine world environment (.logicalAnd left right) =
      .ok (.boolean false, afterLeft) := by
  rw [Term.evaluate, leftResult]
  rfl

theorem Term.evaluate_logicalAnd_true
    (leftResult : Term.evaluate machine world environment left =
      .ok (.boolean true, afterLeft))
    (rightResult : Term.evaluate machine afterLeft environment right =
      .ok (value, afterRight)) :
    Term.evaluate machine world environment (.logicalAnd left right) =
      .ok (value, afterRight) := by
  rw [Term.evaluate, leftResult]
  exact rightResult

theorem Term.evaluate_logicalOr_true
    (leftResult : Term.evaluate machine world environment left =
      .ok (.boolean true, afterLeft)) :
    Term.evaluate machine world environment (.logicalOr left right) =
      .ok (.boolean true, afterLeft) := by
  rw [Term.evaluate, leftResult]
  rfl

theorem Term.evaluate_logicalOr_false
    (leftResult : Term.evaluate machine world environment left =
      .ok (.boolean false, afterLeft))
    (rightResult : Term.evaluate machine afterLeft environment right =
      .ok (value, afterRight)) :
    Term.evaluate machine world environment (.logicalOr left right) =
      .ok (value, afterRight) := by
  rw [Term.evaluate, leftResult]
  exact rightResult

theorem Block.evaluate_sequence_next
    (firstResult : Block.evaluate machine world environment first =
      .done .next afterFirst)
    (secondResult : Block.evaluate machine afterFirst environment second =
      result) :
    Block.evaluate machine world environment (.sequence first second) =
      result := by
  rw [Block.evaluate, firstResult]
  exact secondResult

theorem Block.evaluate_sequence_returned
    (firstResult : Block.evaluate machine world environment first =
      .done (.returned value) afterFirst) :
    Block.evaluate machine world environment (.sequence first second) =
      .done (.returned value) afterFirst := by
  rw [Block.evaluate, firstResult]

theorem Block.evaluate_letValue
    (initializerResult : Term.evaluate machine world environment initializer =
      .ok (value, afterInitializer))
    (bodyResult : Block.evaluate machine afterInitializer
      (environment.push value) body = result) :
    Block.evaluate machine world environment
        (.letValue type initializer body) = result := by
  rw [Block.evaluate, initializerResult]
  exact bodyResult

theorem Block.evaluate_if_true
    (conditionResult : Term.evaluate machine world environment condition =
      .ok (.boolean true, afterCondition))
    (branchResult : Block.evaluate machine afterCondition environment
      thenBranch = result) :
    Block.evaluate machine world environment
        (.ifThenElse condition thenBranch elseBranch) = result := by
  rw [Block.evaluate, conditionResult]
  exact branchResult

theorem Block.evaluate_if_false
    (conditionResult : Term.evaluate machine world environment condition =
      .ok (.boolean false, afterCondition))
    (branchResult : Block.evaluate machine afterCondition environment
      elseBranch = result) :
    Block.evaluate machine world environment
        (.ifThenElse condition thenBranch elseBranch) = result := by
  rw [Block.evaluate, conditionResult]
  exact branchResult

@[simp] theorem Block.evaluate_skip
    (machine : Machine signature) (world : machine.World)
    (environment : Env arity) :
    Block.evaluate machine world environment (.skip : Block signature arity) =
      .done .next world := by
  rfl

theorem Block.evaluate_returnValue
    (valueResult : Term.evaluate machine world environment value =
      .ok (result, afterValue)) :
    Block.evaluate machine world environment (.returnValue (some value)) =
      .done (.returned (some result)) afterValue := by
  rw [Block.evaluate, valueResult]

def Term.effect : Term signature arity → EffectClass
  | .reference _ => .pure
  | .apply operation arguments =>
      arguments.foldl
        (fun accumulated argument => accumulated.join argument.effect)
        (signature.effect operation)
  | .logicalAnd left right | .logicalOr left right =>
      left.effect.join right.effect

def Block.effect : Block signature arity → EffectClass
  | .skip | .returnValue none => .pure
  | .sequence first second => first.effect.join second.effect
  | .letValue _ initializer body => initializer.effect.join body.effect
  | .ifThenElse condition thenBranch elseBranch =>
      (condition.effect.join thenBranch.effect).join elseBranch.effect
  | .returnValue (some value) => value.effect

inductive RefHasType (program : Program) (types : TypeEnv arity) :
    Ref arity → Ty → Prop where
  | slot : RefHasType program types (.slot index) (types index)
  | literal (typed : ValueHasType program value type)
      (literal : Typing.Value.isLiteral value = true := by decide) :
      RefHasType program types (.literal value) type

mutual

  inductive TermHasType (signature : Signature)
      (program : Program) (types : TypeEnv arity) :
      Term signature arity → Ty → Prop where
    | reference (typed : RefHasType program types reference type) :
        TermHasType signature program types (.reference reference) type
    | apply
        (arguments : TermsHaveTypes signature program types expressions
          (signature.operandTypes operation)) :
        TermHasType signature program types (.apply operation expressions)
          (signature.resultType operation)
    | logicalAnd
        (leftTyped : TermHasType signature program types left (.scalar .bool))
        (rightTyped : TermHasType signature program types right (.scalar .bool)) :
        TermHasType signature program types (.logicalAnd left right)
          (.scalar .bool)
    | logicalOr
        (leftTyped : TermHasType signature program types left (.scalar .bool))
        (rightTyped : TermHasType signature program types right (.scalar .bool)) :
        TermHasType signature program types (.logicalOr left right)
          (.scalar .bool)

  inductive TermsHaveTypes (signature : Signature)
      (program : Program) (types : TypeEnv arity) :
      List (Term signature arity) → List Ty → Prop where
    | nil : TermsHaveTypes signature program types [] []
    | cons
        (head : TermHasType signature program types expression type)
        (tail : TermsHaveTypes signature program types expressions types') :
        TermsHaveTypes signature program types
          (expression :: expressions) (type :: types')

end

inductive BlockHasType (signature : Signature)
    (program : Program) (returnType : Ty) :
    {arity : Nat} → TypeEnv arity → Block signature arity → Prop where
  | skip : BlockHasType signature program returnType types .skip
  | sequence
      (firstTyped : BlockHasType signature program returnType types first)
      (secondTyped : BlockHasType signature program returnType types second) :
      BlockHasType signature program returnType types (.sequence first second)
  | letValue
      (initializerTyped : TermHasType signature program types expression type)
      (bodyTyped : BlockHasType signature program returnType
        (types.push type) body) :
      BlockHasType signature program returnType types
        (.letValue type expression body)
  | ifThenElse
      (conditionTyped : TermHasType signature program types expression
        (.scalar .bool))
      (thenTyped : BlockHasType signature program returnType types thenBranch)
      (elseTyped : BlockHasType signature program returnType types elseBranch) :
      BlockHasType signature program returnType types
        (.ifThenElse expression thenBranch elseBranch)
  | returnNone (returnUnit : returnType = .unit) :
      BlockHasType signature program returnType types (.returnValue none)
  | returnSome
      (value : TermHasType signature program types expression returnType) :
      BlockHasType signature program returnType types
        (.returnValue (some expression))

end Lanius.FunctionalView
