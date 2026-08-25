import Lanius.StatementFunctionality

namespace Lanius.ProgramElaboration

open Lanius

private theorem rows_unique_of_pairwise_key_ne
    {rows : List α} {key : α → κ}
    (distinct : rows.Pairwise fun left right => key left ≠ key right)
    (leftMember : left ∈ rows) (rightMember : right ∈ rows)
    (sameKey : key left = key right) : left = right := by
  induction rows with
  | nil => simp at leftMember
  | cons head tail induction =>
      cases distinct with
      | cons headDistinct tailDistinct =>
          simp only [List.mem_cons] at leftMember rightMember
          rcases leftMember with rfl | leftInTail
          · rcases rightMember with rfl | rightInTail
            · rfl
            · exact (headDistinct right rightInTail sameKey).elim
          · rcases rightMember with rfl | rightInTail
            · exact (headDistinct left leftInTail sameKey.symm).elim
            · exact induction tailDistinct leftInTail rightInTail

theorem CoreProgramIdsUnique.function_unique
    (unique : CoreProgramIdsUnique program)
    (leftMember : left ∈ program.functions)
    (rightMember : right ∈ program.functions)
    (sameId : left.id = right.id) : left = right :=
  rows_unique_of_pairwise_key_ne unique.1 leftMember rightMember sameId

/-- Once a complete program fixes unique core function IDs, two exact
    specializations of the same monomorphic source-function instance cannot
    emit different function definitions. -/
theorem FunctionSpecializes.core_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (left : FunctionSpecializes program baseContext surface scheme resolved
      leftCore)
    (right : FunctionSpecializes program baseContext surface scheme resolved
      rightCore) : leftCore = rightCore := by
  cases left with
  | intro leftSubstitution leftInstantiated leftBaseLocals leftSymbolicBindings
      leftSymbolicParameters leftCoreParameters leftBodyContext leftNextLocal
      leftParameters leftReturnRetained leftCoreReturnType leftReturnTypeCore
      leftCoreBody leftFinalLocal leftBody leftDefinition leftTarget leftMember
      leftTyped =>
      cases right with
      | intro rightSubstitution rightInstantiated rightBaseLocals
          rightSymbolicBindings rightSymbolicParameters rightCoreParameters
          rightBodyContext rightNextLocal rightParameters rightReturnRetained
          rightCoreReturnType rightReturnTypeCore rightCoreBody rightFinalLocal
          rightBody rightDefinition rightTarget rightMember rightTyped =>
          apply complete.coreIds.function_unique leftMember rightMember
          rw [leftDefinition, rightDefinition]

/-- The same emitted-function identity theorem for inherent methods. -/
theorem MethodSpecializes.core_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (left : MethodSpecializes program baseContext surface scheme resolved
      leftCore)
    (right : MethodSpecializes program baseContext surface scheme resolved
      rightCore) : leftCore = rightCore := by
  cases left with
  | intro leftSubstitution leftInstantiated leftBaseLocals leftSymbolicBindings
      leftSymbolicParameters leftCoreParameters leftBodyContext leftNextLocal
      leftParameters leftReturnRetained leftCoreReturnType leftReturnTypeCore
      leftCoreBody leftFinalLocal leftBody leftDefinition leftTarget leftMember
      leftTyped =>
      cases right with
      | intro rightSubstitution rightInstantiated rightBaseLocals
          rightSymbolicBindings rightSymbolicParameters rightCoreParameters
          rightBodyContext rightNextLocal rightParameters rightReturnRetained
          rightCoreReturnType rightReturnTypeCore rightCoreBody rightFinalLocal
          rightBody rightDefinition rightTarget rightMember rightTyped =>
          apply complete.coreIds.function_unique leftMember rightMember
          rw [leftDefinition, rightDefinition]

/-- Trait-implementation methods share the same monomorphic function-ID
    discipline as direct functions and inherent methods. -/
theorem TraitImplementationMethodSpecializes.core_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (left : TraitImplementationMethodSpecializes program baseContext surface
      implementation methodHeader symbolicParameterTypes symbolicReturnType
      resolved leftCore)
    (right : TraitImplementationMethodSpecializes program baseContext surface
      implementation methodHeader symbolicParameterTypes symbolicReturnType
      resolved rightCore) : leftCore = rightCore := by
  cases left with
  | intro leftSubstitution leftPattern leftGoal leftParametersBound
      leftImplements leftGoalInstantiated leftRequirements leftInstanceMember
      leftInstanceImplementation leftInstanceDeclaration leftSymbolicBindings
      leftSymbolicParameters leftInitialContexts leftParameterTypesGround
      leftCoreParameters leftBodyContext leftNextLocal leftParameters
      leftReturnRetained leftCoreReturnType leftReturnTypeCore leftCoreBody
      leftFinalLocal leftBody leftDefinition leftTarget leftMember leftTyped =>
      cases right with
      | intro rightSubstitution rightPattern rightGoal rightParametersBound
          rightImplements rightGoalInstantiated rightRequirements
          rightInstanceMember rightInstanceImplementation
          rightInstanceDeclaration rightSymbolicBindings rightSymbolicParameters
          rightInitialContexts rightParameterTypesGround rightCoreParameters
          rightBodyContext rightNextLocal rightParameters rightReturnRetained
          rightCoreReturnType rightReturnTypeCore rightCoreBody rightFinalLocal
          rightBody rightDefinition rightTarget rightMember rightTyped =>
          apply complete.coreIds.function_unique leftMember rightMember
          rw [leftDefinition, rightDefinition]

end Lanius.ProgramElaboration
