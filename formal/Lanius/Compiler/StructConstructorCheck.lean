import Lanius.Compiler.SelectionCheck
import Lanius.Compiler.DirectCallCheck

namespace Lanius.Compiler.StructConstructorCheck

open Lanius SurfaceElaboration

structure Checked (context : Context) (path : Surface.Path) (typeId : TypeId) where
  scheme : StructConstructorScheme
  selected : SelectsStructConstructor context path scheme
  noArguments : PathHasNoGenericArguments path
  nongeneric : scheme.genericParameters = []
  instanceRow : Static.NominalInstance
  instantiated : NominalConstructorInstantiates context scheme.declaration
    scheme.sourceType .structure scheme.genericParameters scheme.requirements
    context.substitution instanceRow
  coreType : instanceRow.coreType = typeId

def check (context : Context) (path : Surface.Path) (typeId : TypeId) :
    Option (Checked context path typeId) := do
  let global ← NameResolutionCheck.checkGlobal context .type path
  let selected ← SelectionCheck.check context.structConstructors
    (fun row => decide (row.declaration = global.symbol.declaration))
  let scheme := selected.value
  if generic : scheme.genericParameters = [] ∧ scheme.requirements = [] then
    if noArguments : FunctionInstanceCheck.noExplicitArguments path then
      let chosen ← SelectionCheck.check context.nominalInstances
        (fun row => decide (row.sourceType = scheme.sourceType ∧
          row.typeArguments = [] ∧ row.constArguments = []))
      let row := chosen.value
      if identity : row.declaration = scheme.declaration ∧
          row.kind = .structure ∧ row.coreType = typeId then
        have matching : row.sourceType = scheme.sourceType ∧
            row.typeArguments = [] ∧ row.constArguments = [] :=
          of_decide_eq_true chosen.accepted
        return {
          scheme, instanceRow := row, coreType := identity.2.2
          nongeneric := generic.1
          noArguments := FunctionInstanceCheck.noExplicitArguments_sound noArguments
          selected := by
            refine ⟨global.symbol, global.resolved, selected.member,
              of_decide_eq_true selected.accepted, ?_⟩
            intro other member declaration
            have equal := selected.unique other member (by simp [declaration])
            subst other
            exact ⟨rfl, rfl, rfl, rfl⟩
          instantiated := by
            refine ⟨chosen.member, identity.1, matching.1, identity.2.1, ?_, ?_, ?_⟩
            · simpa [generic.1, matching.2.1, matching.2.2] using
                (Static.NominalArgumentsBound.nil :
                  Static.NominalArgumentsBound context.substitution [] [] [])
            · simpa [generic.2] using
                (Static.RequirementsSatisfied.nil :
                  Static.RequirementsSatisfied context.implementations context.substitution [])
            · intro other member source types constants
              have equal := chosen.unique other member (by
                simp [source, types, constants, matching.2.1, matching.2.2])
              exact congrArg Static.NominalInstance.coreType equal }
      else none
    else none
  else none

end Lanius.Compiler.StructConstructorCheck
