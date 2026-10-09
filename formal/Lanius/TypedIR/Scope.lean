import Lanius.Typing

namespace Lanius.TypedIR.Intrinsic

/-- Logical scopes are erased during compilation, unlike lookup functions
    returning data. They still enforce each local's identity and exact type. -/
abbrev Scope := VarId → Core.Ty → Prop

def Scope.ofContext (context : Typing.Context) : Scope :=
  fun id type => context id = some type

def Scope.empty : Scope := Scope.ofContext Typing.Context.empty

def Scope.bind (scope : Scope) (id : VarId) (type : Core.Ty) : Scope :=
  fun candidate actual => if candidate == id then type = actual else scope candidate actual

def Scope.bindAll (scope : Scope) (bindings : List (VarId × Core.Ty)) : Scope :=
  bindings.foldl (fun result binding => result.bind binding.1 binding.2) scope

def Scope.parameters (parameters : List (VarId × Core.Ty)) : Scope :=
  Scope.ofContext (Typing.parameterContext parameters)

/-- Every binding admitted by the logical scope is present in the Core scope. -/
def Scope.Realizes (scope : Scope) (context : Typing.Context) : Prop :=
  ∀ id type, scope id type → context id = some type

theorem Scope.realizes (context : Typing.Context) : (ofContext context).Realizes context :=
  fun _ _ found => found

theorem Scope.Realizes.bind (valid : Scope.Realizes scope context) (id : VarId) (type : Core.Ty) :
    (scope.bind id type).Realizes (context.bind id type) := by
  intro candidate actual found
  cases same : candidate == id with
  | false =>
      simp only [Scope.bind, same, Bool.false_eq_true, ite_false] at found
      simpa only [Typing.Context.bind, same, Bool.false_eq_true, ite_false] using valid _ _ found
  | true =>
      simp only [Scope.bind, same, ite_true] at found
      simpa only [Typing.Context.bind, same, ite_true] using congrArg some found

theorem Scope.Realizes.bindAll (valid : Scope.Realizes scope context) (bindings : List (VarId × Core.Ty)) :
    (scope.bindAll bindings).Realizes (context.bindAll bindings) := by
  induction bindings generalizing scope context with
  | nil => exact valid
  | cons head tail ih => exact ih (valid.bind head.1 head.2)

end Lanius.TypedIR.Intrinsic
