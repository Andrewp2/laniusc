import Lanius.Relational.Semantics
import Lanius.FunctionalViewCoreStateful

namespace Lanius.Relational

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful

/-! # Relational primitive-operation registry

Ordinary Core operations retain the existing read-only interpretation. Calls
and stateful actions are relations supplied by a registry. In particular, no
`CallModel` is needed to state or prove a command WP.
-/

abbrev CallRelation := ReadOnly.World → FunctionId → List Value →
  Value → ReadOnly.World → Prop

abbrev ActionRelation := {arity : Nat} → ReadOnly.World → Env arity →
  Stateful.actions.Action arity → ReadOnly.World → Prop

structure OperationRegistry where
  call : CallRelation
  action : ActionRelation

/-- Relational machine used by structurally reified Core commands. -/
abbrev OperationRegistry.machine (program : Program)
    (registry : OperationRegistry) :
    Semantics.Machine Core.signature Stateful.actions where
  World := ReadOnly.World
  operation := fun world operation arguments result afterWorld =>
    match operation with
    | .call function _ _ =>
        registry.call world function arguments result afterWorld
    | operation =>
        ReadOnly.evaluateOperation program world operation arguments =
          .ok (result, afterWorld)
  localUpdate := fun operation left right result =>
    Lanius.Semantics.evalAssignValue program.target operation (some left) right =
      .ok result
  action := registry.action

/-- A registry for read-only pilots. Any action is rejected explicitly; action
freedom is then a structural obligation of the reified command. -/
def OperationRegistry.readOnly (calls : CallRelation) : OperationRegistry where
  call := calls
  action := fun _ _ _ _ => False

end Lanius.Relational
