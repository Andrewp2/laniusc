import Lanius.Semantics.Typing.Values

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Typing

/-- A path through a declared struct or bounded array. This is proof-library
    evidence about the existing path, not an emitted representation. -/
inductive ProjectionHasType (program : Program) : Ty → List ValueProjection → Ty → Prop where
  | root : ProjectionHasType program type [] type
  | field {id : TypeId} {field : FieldId} (declaration : StructDecl)
      (found : program.structure? id = some declaration)
      (fieldFound : declaration.fields[field]? = some fieldType)
      (rest : ProjectionHasType program fieldType projections type) :
      ProjectionHasType program (.structure id) (.field field :: projections) type
  | index (bounded : index < count)
      (rest : ProjectionHasType program elementType projections type) :
      ProjectionHasType program (.array elementType count) (.index index :: projections) type

/-- A statically valid path through a typed aggregate reads successfully. -/
theorem projectedValue_typed (path : ProjectionHasType program rootType projections type)
    (typed : ValueHasType program root rootType) :
    ∃ value, projectedValue root projections = .ok value ∧ ValueHasType program value type := by
  induction path generalizing root with
  | root => exact ⟨root, rfl, typed⟩
  | field declaration found fieldFound rest ih =>
    cases typed with
    | «structure» actual actualFound fieldsTyped =>
      have same : actual = declaration := Option.some.inj (actualFound.symm.trans found)
      subst actual
      obtain ⟨fieldValue, fieldValueFound, fieldTyped⟩ := fieldsTyped.get fieldFound
      obtain ⟨value, evaluated, valueTyped⟩ := ih fieldTyped
      exact ⟨value, by simpa [projectedValue, fieldValueFound] using evaluated, valueTyped⟩
  | @index index count elementType projections type bounded rest ih =>
    cases typed with
    | array values elementType length elementsTyped =>
      have elementFound : (List.replicate count elementType)[index]? = some elementType := by
        simp [bounded]
      obtain ⟨element, present, elementTyped⟩ := elementsTyped.get elementFound
      obtain ⟨value, evaluated, valueTyped⟩ := ih elementTyped
      exact ⟨value, by simpa [projectedValue, present] using evaluated, valueTyped⟩

/-- Typed replacement succeeds, preserves the root type and reads back exactly
    the replacement, at arbitrary nesting depth. -/
theorem replaceProjectedValue_typed (path : ProjectionHasType program rootType projections type)
    (typed : ValueHasType program root rootType)
    (replacementTyped : ValueHasType program replacement type) :
    ∃ updated, replaceProjectedValue root projections replacement = .ok updated ∧
      ValueHasType program updated rootType ∧ projectedValue updated projections = .ok replacement := by
  induction path generalizing root with
  | root => exact ⟨replacement, rfl, replacementTyped, rfl⟩
  | field declaration found fieldFound rest ih =>
    cases typed with
    | «structure» actual actualFound fieldsTyped =>
      have same : actual = declaration := Option.some.inj (actualFound.symm.trans found)
      subst actual
      obtain ⟨fieldValue, present, fieldTyped⟩ := fieldsTyped.get fieldFound
      obtain ⟨updated, evaluated, updatedTyped, readBack⟩ := ih fieldTyped replacementTyped
      obtain ⟨bound, _⟩ := List.getElem?_eq_some_iff.mp present
      refine ⟨.structure declaration.id (setValue _ _ updated),
        by simp [replaceProjectedValue, present, evaluated],
        .structure declaration found (fieldsTyped.set fieldFound updatedTyped), ?_⟩
      simpa [projectedValue, setValue_eq_set, List.getElem?_set_self bound] using readBack
  | @index index count elementType projections type bounded rest ih =>
    cases typed with
    | array values elementType length elementsTyped =>
      have elementFound : (List.replicate count elementType)[index]? = some elementType := by
        simp [bounded]
      obtain ⟨element, present, elementTyped⟩ := elementsTyped.get elementFound
      obtain ⟨updated, evaluated, updatedTyped, readBack⟩ := ih elementTyped replacementTyped
      obtain ⟨bound, _⟩ := List.getElem?_eq_some_iff.mp present
      refine ⟨.array (setValue values _ updated),
        by simp [replaceProjectedValue, present, evaluated],
        .array _ elementType (by simpa [setValue_eq_set] using length)
          (elementsTyped.set elementFound updatedTyped), ?_⟩
      simpa [projectedValue, setValue_eq_set, List.getElem?_set_self bound] using readBack

#print axioms projectedValue_typed
#print axioms replaceProjectedValue_typed

end Lanius.Semantics
