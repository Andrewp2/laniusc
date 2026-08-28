import Lanius.Typing

namespace Lanius.ProofIR

open Lanius
open Lanius.Core
open Lanius.Typing

/-! # Proof-oriented functional IR

`Core` is the faithful executable semantics of Lanius. Its lexical locals are
implemented by fresh physical cells, which is useful for defining calls and
aliasing but needlessly exposes allocation and scope restoration in proofs of
read-only computations.

This module defines a second, proof-oriented representation. Local references
are intrinsically scoped `Fin` indices, environments are immutable functions,
and primitive operations are supplied by an effect signature. A separate
adapter proves that lowering this representation to structural Core preserves
its functional evaluation. The IR therefore does not replace Core semantics;
it is a verified reasoning view over it.
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

/-- Structured proof control. `letValue` extends only the immutable proof
    environment. No physical allocation identity appears in this IR. -/
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
    same IR can grow from pure/read-only parser code to allocation and host
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

def Term.effect : Term signature arity → EffectClass
  | .reference _ => .pure
  | .apply operation arguments =>
      arguments.foldl
        (fun accumulated argument => accumulated.join argument.effect)
        (signature.effect operation)

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

end Lanius.ProofIR
