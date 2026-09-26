import Lanius.Compiler.DirectCallCheck

namespace Lanius.Compiler.VariantConstructorCheck

open Lanius
open Lanius.SurfaceElaboration

/-- A non-generic variant constructor and its unique instantiated enum. The
    source arguments are checked separately against `scheme.payload`. -/
structure Checked (context : Context) (path : Surface.Path)
    (typeId : TypeId) (variantId : VariantId) where
  scheme : VariantConstructorScheme
  selected : SelectsVariantConstructor context path scheme
  noArguments : PathHasNoGenericArguments path
  notIntrinsic : builtinIntrinsic? path = none
  nongeneric : scheme.genericParameters = []
  instanceRow : Static.NominalInstance
  instantiated : NominalConstructorInstantiates context
    scheme.nominalDeclaration scheme.sourceType .enumeration
    scheme.genericParameters scheme.requirements context.substitution instanceRow
  coreType : instanceRow.coreType = typeId
  variant : scheme.variant = variantId

def check (context : Context) (path : Surface.Path)
    (typeId : TypeId) (variantId : VariantId) :
    Option (Checked context path typeId variantId) :=
  if shadowed : DirectCallCheck.pathNotShadowed? context path = true then
    match global : NameResolutionCheck.checkGlobal context .value path with
    | none => none
    | some resolvedName =>
        match schemes : context.variantConstructors.filter
            (fun row => decide (row.declaration = resolvedName.symbol.declaration)) with
        | [scheme] =>
            if nongeneric : scheme.genericParameters = [] then
              if requirements : scheme.requirements = [] then
                if variant : scheme.variant = variantId then
                  if noArguments : FunctionInstanceCheck.noExplicitArguments path then
                    match instances : context.nominalInstances.filter
                        (fun row => decide (row.sourceType = scheme.sourceType ∧
                          row.typeArguments = [] ∧ row.constArguments = [])) with
                    | [instanceRow] =>
                        if declaration : instanceRow.declaration = scheme.nominalDeclaration then
                          if kind : instanceRow.kind = .enumeration then
                            if coreType : instanceRow.coreType = typeId then
                              have schemeFiltered : scheme ∈ context.variantConstructors.filter
                                  (fun row => decide (row.declaration =
                                    resolvedName.symbol.declaration)) := by
                                rw [schemes]
                                simp
                              have schemeMember := (List.mem_filter.mp schemeFiltered).1
                              have schemeDeclaration :
                                  scheme.declaration = resolvedName.symbol.declaration :=
                                of_decide_eq_true (List.mem_filter.mp schemeFiltered).2
                              have selected : SelectsVariantConstructor context path scheme := by
                                refine ⟨DirectCallCheck.pathNotShadowed_sound shadowed,
                                  resolvedName.symbol, resolvedName.resolved,
                                  schemeMember, schemeDeclaration, ?_⟩
                                intro candidate member sameDeclaration
                                have filtered : candidate ∈
                                    context.variantConstructors.filter
                                      (fun row => decide (row.declaration =
                                        resolvedName.symbol.declaration)) :=
                                  List.mem_filter.mpr ⟨member, by simp [sameDeclaration]⟩
                                rw [schemes] at filtered
                                simp only [List.mem_singleton] at filtered
                                subst candidate
                                exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
                              have instanceFiltered : instanceRow ∈
                                  context.nominalInstances.filter
                                    (fun row => decide (row.sourceType = scheme.sourceType ∧
                                      row.typeArguments = [] ∧ row.constArguments = [])) := by
                                rw [instances]
                                simp
                              have instanceMember := (List.mem_filter.mp instanceFiltered).1
                              have matching :=
                                of_decide_eq_true (List.mem_filter.mp instanceFiltered).2
                              have sourceType := matching.1
                              have typeArguments := matching.2.1
                              have constArguments := matching.2.2
                              have unique : ∀ candidate,
                                  candidate ∈ context.nominalInstances →
                                  candidate.sourceType = scheme.sourceType →
                                  candidate.typeArguments = instanceRow.typeArguments →
                                  candidate.constArguments = instanceRow.constArguments →
                                  candidate.coreType = instanceRow.coreType := by
                                intro candidate member sameSource sameTypes sameConstants
                                have filtered : candidate ∈
                                    context.nominalInstances.filter
                                      (fun row => decide (row.sourceType = scheme.sourceType ∧
                                        row.typeArguments = [] ∧ row.constArguments = [])) :=
                                  List.mem_filter.mpr ⟨member, by
                                    simp [sameSource, sameTypes, sameConstants,
                                      typeArguments, constArguments]⟩
                                rw [instances] at filtered
                                simp only [List.mem_singleton] at filtered
                                subst candidate
                                rfl
                              have instantiated : NominalConstructorInstantiates context
                                  scheme.nominalDeclaration scheme.sourceType .enumeration
                                  scheme.genericParameters scheme.requirements
                                  context.substitution instanceRow := by
                                refine ⟨instanceMember, declaration, sourceType, kind, ?_, ?_, unique⟩
                                · simpa [nongeneric, typeArguments, constArguments] using
                                    (Static.NominalArgumentsBound.nil :
                                      Static.NominalArgumentsBound context.substitution [] [] [])
                                · simpa [requirements] using
                                    (Static.RequirementsSatisfied.nil :
                                      Static.RequirementsSatisfied context.implementations
                                        context.substitution [])
                              if notIntrinsic : builtinIntrinsic? path = none then
                                some {
                                  scheme
                                  selected
                                  noArguments :=
                                    FunctionInstanceCheck.noExplicitArguments_sound noArguments
                                  notIntrinsic
                                  nongeneric
                                  instanceRow
                                  instantiated
                                  coreType
                                  variant }
                              else none
                            else none
                          else none
                        else none
                    | _ => none
                  else none
                else none
              else none
            else none
        | _ => none
  else none

end Lanius.Compiler.VariantConstructorCheck
