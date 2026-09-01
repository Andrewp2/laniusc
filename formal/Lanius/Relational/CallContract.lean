import Lanius.Relational.CheckedProgram
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.Fuel

namespace Lanius.Relational

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Fuel
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Typing

/-! # Relational call contracts

The public contract describes successful calls.  It does not expose a
`CallModel`, a callee trace, physical call entry, or local restoration.  During
the migration, `ofFramePreservingModel` converts the repository's existing
constructive frame-preserving proof into this relational interface.  The
future structural WP-to-Core theorem can produce the same interface without
changing any client contract.
-/

/-- An algorithm-facing function contract.  `AbstractStateRep` is the sole
connection between logical state and the existing read-only FunctionalView
world. -/
structure FnContract
    (program : CheckedProgram) (signature : FnSignature)
    (function : program.FnRef signature) where
  Args : Type
  Result : Type
  AbstractState : Type
  Pre : Args → AbstractState → Prop
  Post : Args → Result → AbstractState → AbstractState → Prop
  Frame : AbstractState → AbstractState → Prop
  encodeArgs : Args → List Value
  encodeResult : Result → Value
  encodeArgs_typed : ∀ args abstract,
    Pre args abstract →
    ValuesHaveTypes program.core (encodeArgs args) signature.arguments
  encodeResult_typed : ∀ args result before after,
    Pre args before →
    Post args result before after →
    ValueHasType program.core (encodeResult result) signature.result
  AbstractStateRep : AbstractState → ReadOnly.World → Prop

/-- The algorithm-facing call rule.  It asks for the callee precondition and
then exposes only the callee's logical postcondition and frame to the
continuation. -/
def FnContract.callWP
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (contract : FnContract program signature function)
    (args : contract.Args) (before : contract.AbstractState)
    (continuation : contract.Result → contract.AbstractState → Prop) : Prop :=
  contract.Pre args before ∧
  ∀ result after,
    contract.Post args result before after →
    contract.Frame before after →
    continuation result after

/-- The successful primitive-call relation induced by a function contract.
It exposes only encoded arguments/results and the two abstract worlds.  A
registry's `ReturnsCorrectly` proof is what justifies this relation against an
actual checked Core call. -/
def FnContract.AllowsCall
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (contract : FnContract program signature function)
    (beforeWorld : ReadOnly.World) (arguments : List Value)
    (value : Value) (afterWorld : ReadOnly.World) : Prop :=
  ∃ args before result after,
    arguments = contract.encodeArgs args ∧
    value = contract.encodeResult result ∧
    contract.Pre args before ∧
    contract.AbstractStateRep before beforeWorld ∧
    contract.Post args result before after ∧
    contract.Frame before after ∧
    contract.AbstractStateRep after afterWorld

/-- Every successful checked Core call from a represented caller state returns
a result and logical state allowed by the contract.  Argument evaluation is
quantified internally so an algorithm theorem can expose only this named
property. -/
def ReturnsCorrectly
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (contract : FnContract program signature function) : Prop :=
  ∀ {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {environment : Env arity}
    {beforeWorld : ReadOnly.World}
    {before afterArguments actualAfter : State}
    {arguments : List (Term Core.signature arity)}
    {argumentWrites : CellSet}
    {actualValue : Value}
    (args : contract.Args) (abstractBefore : contract.AbstractState),
    contract.Pre args abstractBefore →
    contract.AbstractStateRep abstractBefore beforeWorld →
    StateWellFormed afterArguments →
    Representation layout localCell beforeWorld environment afterArguments →
    ArgumentsEvaluateTo program.core before (Core.toCoreExprs layout arguments)
      (contract.encodeArgs args) afterArguments →
    ModifiesOnly argumentWrites before afterArguments →
    Evaluates program.core before
      (.call function.function.id (Core.toCoreExprs layout arguments))
      actualValue actualAfter →
    ∃ result abstractAfter afterWorld,
      actualValue = contract.encodeResult result ∧
      contract.AbstractStateRep abstractAfter afterWorld ∧
      contract.Post args result abstractBefore abstractAfter ∧
      contract.Frame abstractBefore abstractAfter ∧
      StateWellFormed actualAfter ∧
      Representation layout localCell afterWorld environment actualAfter ∧
      ModifiesOnly argumentWrites before actualAfter

/-- A typed registry entry pairs a source-identified checked function with its
contract proof. Numeric dispatch remains an implementation detail of the
operation registry. -/
structure SpecEntry
    {program : CheckedProgram} {signature : FnSignature}
    (function : program.FnRef signature) where
  contract : FnContract program signature function
  sound : ReturnsCorrectly contract

/-- Primitive call relation contributed by one typed registry entry. -/
def SpecEntry.callRelation
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (entry : SpecEntry function) :
    ReadOnly.World → FunctionId → List Value → Value → ReadOnly.World → Prop :=
  fun beforeWorld candidate arguments value afterWorld =>
    candidate = function.function.id ∧
    entry.contract.AllowsCall beforeWorld arguments value afterWorld

/-- A relational contract implemented by an existing abstract call model.
This is a migration boundary, not part of `ReturnsCorrectly`: clients never
see the model or its constructive soundness proof. -/
structure ModelImplements
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (contract : FnContract program signature function)
    (calls : CallModel) : Prop where
  apply : ∀ (args : contract.Args)
      (abstractBefore : contract.AbstractState)
      (beforeWorld : ReadOnly.World),
    contract.Pre args abstractBefore →
    contract.AbstractStateRep abstractBefore beforeWorld →
    ∃ result abstractAfter afterWorld,
      calls.evaluate beforeWorld function.function.id
          (contract.encodeArgs args) =
        .ok (contract.encodeResult result, afterWorld) ∧
      contract.AbstractStateRep abstractAfter afterWorld ∧
      contract.Post args result abstractBefore abstractAfter ∧
      contract.Frame abstractBefore abstractAfter

/-- Bootstrap theorem: determinism turns a canonical execution supplied by
the old frame-preserving bridge into a statement about any successful actual
Core execution. -/
theorem ReturnsCorrectly.ofFramePreservingModel
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {contract : FnContract program signature function}
    {calls : CallModel}
    (implemented : ModelImplements contract calls)
    (sound : FramePreservingCallSoundness program.core calls) :
    ReturnsCorrectly contract := by
  intro arity layout localCell environment beforeWorld before afterArguments
    actualAfter arguments argumentWrites actualValue args abstractBefore
    pre abstractBeforeRep afterArgumentsWellFormed represented
    argumentsExecution argumentsEffect actualExecution
  obtain ⟨result, abstractAfter, afterWorld, modeled, abstractAfterRep,
      post, frame⟩ :=
    implemented.apply args abstractBefore beforeWorld pre abstractBeforeRep
  obtain ⟨modeledAfter, modeledExecution, modeledAfterWellFormed,
      modeledAfterRep, modeledEffect⟩ :=
    sound.call afterArgumentsWellFormed represented argumentsExecution
      argumentsEffect modeled
  obtain ⟨valueEq, stateEq⟩ :=
    evaluates_deterministic actualExecution modeledExecution
  subst actualValue
  subst actualAfter
  exact ⟨result, abstractAfter, afterWorld, rfl, abstractAfterRep, post, frame,
    modeledAfterWellFormed, modeledAfterRep, modeledEffect⟩

/-- Eliminate a successful checked call through the relational call rule.
The Core execution and representation evidence remain at this generic
boundary; a caller's algorithm proof receives only `continuation`. -/
theorem ReturnsCorrectly.applyCallWP
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {contract : FnContract program signature function}
    (correct : ReturnsCorrectly contract)
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {environment : Env arity}
    {beforeWorld : ReadOnly.World}
    {before afterArguments actualAfter : State}
    {arguments : List (Term Core.signature arity)}
    {argumentWrites : CellSet} {actualValue : Value}
    (args : contract.Args) (abstractBefore : contract.AbstractState)
    (continuation : contract.Result → contract.AbstractState → Prop)
    (callWP : contract.callWP args abstractBefore continuation)
    (representedAbstract : contract.AbstractStateRep abstractBefore beforeWorld)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (represented : Representation layout localCell beforeWorld environment
      afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo program.core before
      (Core.toCoreExprs layout arguments) (contract.encodeArgs args)
      afterArguments)
    (argumentsEffect : ModifiesOnly argumentWrites before afterArguments)
    (actualExecution : Evaluates program.core before
      (.call function.function.id (Core.toCoreExprs layout arguments))
      actualValue actualAfter) :
    ∃ result abstractAfter afterWorld,
      actualValue = contract.encodeResult result ∧
      contract.AbstractStateRep abstractAfter afterWorld ∧
      continuation result abstractAfter ∧
      StateWellFormed actualAfter ∧
      Representation layout localCell afterWorld environment actualAfter ∧
      ModifiesOnly argumentWrites before actualAfter := by
  obtain ⟨result, abstractAfter, afterWorld, valueEq, afterRep, post, frame,
      afterWellFormed, representedAfter, effect⟩ :=
    correct args abstractBefore callWP.1 representedAbstract
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      actualExecution
  exact ⟨result, abstractAfter, afterWorld, valueEq, afterRep,
    callWP.2 result abstractAfter post frame, afterWellFormed,
    representedAfter, effect⟩

end Lanius.Relational
