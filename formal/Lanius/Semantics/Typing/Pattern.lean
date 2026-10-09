import Lanius.Semantics.Typing.Bindings

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing

/-- Successful matching of a typed value produces exactly the declared bindings,
    with each payload value retaining its type. Nested patterns are included. -/
theorem matchPattern_types (typed : PatternHasType program pattern type declarations)
    (valueTyped : ValueHasType program value type)
    (matched : matchPattern pattern value = some bindings) :
    BindingsHaveTypes program bindings declarations := by
  induction typed using PatternHasType.rec
      (motive_2 := fun patterns types declarations _ => ∀ values bindings,
        ValuesHaveTypes program values types → matchPatterns patterns values = some bindings →
          BindingsHaveTypes program bindings declarations)
      generalizing value bindings with
  | wildcard =>
    simp [matchPattern] at matched
    subst bindings
    exact .nil
  | bind id =>
    simp [matchPattern] at matched
    subst bindings
    exact .cons valueTyped .nil
  | literal expected =>
    simp only [matchPattern] at matched
    split at matched <;> simp_all
    exact .nil
  | enumVariant declaration found variantFound payload ih =>
    cases valueTyped with
    | enumeration actual actualFound actualVariantFound valuesTyped =>
      have same : actual = declaration := Option.some.inj (actualFound.symm.trans found)
      subst actual
      simp only [matchPattern, Bool.and_eq_true, beq_iff_eq, true_and] at matched
      split at matched
      · rename_i guard
        subst guard
        have sameTypes := Option.some.inj (actualVariantFound.symm.trans variantFound)
        subst sameTypes
        exact ih _ _ valuesTyped matched
      · cases matched
  | nil =>
    rename_i values bindings valuesTyped matched
    cases valuesTyped
    simp [matchPatterns] at matched
    subst bindings
    exact .nil
  | @cons pattern type headDeclarations patterns types tailDeclarations head tail ihHead ihTail =>
    rename_i values bindings valuesTyped matched
    cases valuesTyped with
    | @cons value _ remaining _ valueTyped valuesTyped =>
      simp only [matchPatterns] at matched
      cases first : matchPattern pattern value with
      | none => simp [first] at matched
      | some headBindings =>
        cases rest : matchPatterns patterns remaining with
        | none => simp [first, rest] at matched
        | some tailBindings =>
          simp only [first, rest, Option.some.injEq] at matched
          subst bindings
          exact (ihHead valueTyped first).append (ihTail _ _ valuesTyped rest)

/-- The actual installation step supplies the environment expected by a typed
    match arm. Repeated names shadow in the same order on both sides. -/
theorem matchPattern_locals {state : State} (typed : PatternHasType program pattern type declarations)
    (valueTyped : ValueHasType program value type)
    (matched : matchPattern pattern value = some bindings)
    (locals : state.LocalsHaveTypes program context) (formed : state.CellsWellFormed) :
    (state.bindLocals bindings).LocalsHaveTypes program (context.bindAll declarations) :=
  (matchPattern_types typed valueTyped matched).bindLocals locals formed

#print axioms matchPattern_types
#print axioms matchPattern_locals

end Lanius.Semantics
