import Lanius.Relational.CheckedProgram
import Lanius.FunctionalViewCoreStatefulSimulation

namespace Lanius.Relational

open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful

/-! # Exact command reification

This record keeps artifact identity and semantic adequacy as separate facts.
It certifies only that translating an existing FunctionalView command produces
the exact body carried by a checked typed function handle.
-/

structure Reifies
    {program : CheckedProgram} {signature : FnSignature}
    (function : program.FnRef signature)
    {actions : Stateful.ActionSignature Core.signature}
    {arity : Nat}
    (command : Stateful.Command Core.signature actions arity) where
  layout : Layout arity
  nextLocal : VarId
  adapter : ActionAdapter actions
  argumentCount : arity = signature.arguments.length
  below : LayoutBelow layout nextLocal
  exact : Stateful.toCoreStmt adapter layout nextLocal command = function.body

end Lanius.Relational
