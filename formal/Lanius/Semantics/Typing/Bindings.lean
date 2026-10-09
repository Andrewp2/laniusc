import Lanius.Typing
import Lanius.Semantics.MutableLocal

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing

/-- Runtime bindings agree with the static bindings in order, name and type.
    This is a library proposition, not emitted typing evidence. -/
inductive BindingsHaveTypes (program : Program) :
    List (VarId × Value) → List (VarId × Ty) → Prop where
  | nil : BindingsHaveTypes program [] []
  | cons {id : VarId} (typed : ValueHasType program value type)
      (rest : BindingsHaveTypes program values types) :
      BindingsHaveTypes program ((id, value) :: values) ((id, type) :: types)

theorem BindingsHaveTypes.append (left : BindingsHaveTypes program values types)
    (right : BindingsHaveTypes program moreValues moreTypes) :
    BindingsHaveTypes program (values ++ moreValues) (types ++ moreTypes) := by
  induction left with
  | nil => exact right
  | cons typed rest ih => exact .cons typed ih

/-- Each variable in the context has an initialized value of its declared type.
    This does not assert heap validity or the validity of reference targets. -/
def State.LocalsHaveTypes (state : State) (program : Program) (context : Context) : Prop :=
  ∀ id type, context id = some type →
    ∃ value, state.local? id = some value ∧ ValueHasType program value type

theorem State.LocalsHaveTypes.empty (state : State) (program : Program) :
    state.LocalsHaveTypes program Context.empty := by
  simp [State.LocalsHaveTypes, Context.empty]

theorem State.LocalsHaveTypes.bindLocal {state : State} {id : VarId}
    (locals : state.LocalsHaveTypes program context)
    (formed : state.CellsWellFormed) (typed : ValueHasType program value type) :
    (state.bindLocal id value).LocalsHaveTypes program (context.bind id type) := by
  intro queried declared found
  by_cases same : id = queried
  · subst queried
    have declaredEq : declared = type := by simpa [Context.bind] using found.symm
    subst declared
    exact ⟨value, formed.bindLocal_local id value, typed⟩
  · have old : context queried = some declared := by simpa [Context.bind, Ne.symm same] using found
    obtain ⟨previous, present, previousTyped⟩ := locals queried declared old
    exact ⟨previous, State.bindLocal_local?_of_ne state formed queried id previous value same present, previousTyped⟩

theorem BindingsHaveTypes.bindLocals {state : State} (bindings : BindingsHaveTypes program values types)
    (locals : state.LocalsHaveTypes program context) (formed : state.CellsWellFormed) :
    (state.bindLocals values).LocalsHaveTypes program (context.bindAll types) := by
  induction bindings generalizing state context with
  | nil => exact locals
  | cons typed rest ih =>
    exact ih (locals.bindLocal formed typed) (formed.bindLocal _ _)

/-- An initialized, typed local evaluates without a trap and retains its type. -/
theorem State.LocalsHaveTypes.evalLocal {state : State} {id : VarId}
    (locals : state.LocalsHaveTypes program context) (found : context id = some type)
    (fuel : Nat) :
    ∃ value, evalExpr fuel.succ program state (.local id) = .done value state ∧
      ValueHasType program value type := by
  obtain ⟨value, present, typed⟩ := locals id type found
  exact ⟨value, evalExpr_local_of_local? fuel program state id value present, typed⟩

#print axioms BindingsHaveTypes.bindLocals
#print axioms State.LocalsHaveTypes.evalLocal

end Lanius.Semantics
