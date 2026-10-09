import Lanius.Semantics.Typing.Bindings

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing

/-- Typed arguments have the required arity and retain their parameter names
    and types through the actual parameter-binding computation. -/
theorem bindParameters_types
    (typed : ValuesHaveTypes program arguments (parameters.map Prod.snd)) :
    ∃ bindings, bindParameters parameters arguments = some bindings ∧
      BindingsHaveTypes program bindings parameters := by
  induction parameters generalizing arguments with
  | nil =>
    cases typed
    exact ⟨[], rfl, .nil⟩
  | cons parameter parameters ih =>
    cases typed with
    | @cons value _ values _ valueTyped valuesTyped =>
      obtain ⟨bindings, matched, bindingsTyped⟩ := ih valuesTyped
      have lengthEq : parameters.length = values.length := by
        unfold bindParameters at matched
        split at matched
        · simpa using ‹(parameters.length == values.length) = true›
        · cases matched
      refine ⟨(parameter.1, value) :: bindings, ?_, .cons valueTyped bindingsTyped⟩
      simpa [bindParameters, lengthEq] using matched

/-- Internal calls clear lexical bindings and then bind arguments. This proves
    the resulting initialized context, without assuming a successful call. -/
theorem bindParameters_locals {state : State}
    (typed : ValuesHaveTypes program arguments (parameters.map Prod.snd))
    (formed : state.CellsWellFormed) :
    ∃ bindings, bindParameters parameters arguments = some bindings ∧
      (({ state with locals := [] }).bindLocals bindings).LocalsHaveTypes program
        (parameterContext parameters) := by
  obtain ⟨bindings, matched, bindingsTyped⟩ := bindParameters_types typed
  exact ⟨bindings, matched,
    bindingsTyped.bindLocals (.empty _ _) (show ({ state with locals := [] }).CellsWellFormed from formed)⟩

#print axioms bindParameters_types
#print axioms bindParameters_locals

end Lanius.Semantics
