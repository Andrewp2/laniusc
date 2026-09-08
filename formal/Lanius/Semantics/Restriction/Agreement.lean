import Lanius.Core.Dependencies
import Lanius.Semantics

namespace Lanius.Semantics.Restriction

open Lanius.Core

/-- Programs agree on every callable dependency of the retained functions.
Other function declarations may differ or be absent. -/
structure Agreement (allowed : FunctionId → Bool) (original restricted : Program) : Prop where
  target : original.target = restricted.target
  constants : ∀ id, original.constant? id = restricted.constant? id
  functions : ∀ id, allowed id = true → original.function? id = restricted.function? id
  body : ∀ id declaration code, allowed id = true → original.function? id = some declaration →
    declaration.body = some code → Dependencies.statement allowed code = true

theorem Agreement.functionFound (matching : Agreement allowed original restricted)
    {id : FunctionId} {declaration : Function}
    (retained : allowed id = true) (found : original.function? id = some declaration) :
    restricted.function? id = some declaration := (matching.functions id retained).symm.trans found

theorem Agreement.constantFound (matching : Agreement allowed original restricted)
    {id : ConstantId} {declaration : Constant}
    (found : original.constant? id = some declaration) : restricted.constant? id = some declaration :=
  (matching.constants id).symm.trans found

private theorem find_filtered (functions : List Function) (allowed : FunctionId → Bool)
    (id : FunctionId) (retained : allowed id = true) :
    (functions.filter (fun function => allowed function.id)).find? (fun function => function.id == id) =
      functions.find? (fun function => function.id == id) := by
  induction functions with
  | nil => rfl
  | cons declaration rest ih =>
      by_cases same : declaration.id = id
      · simp [same, retained]
      · cases kept : allowed declaration.id <;> simp [kept, same, ih]

theorem ofClosed (program : Program) (allowed : FunctionId → Bool)
    (closed : Dependencies.closed program allowed = true) :
    Agreement allowed program (Dependencies.restrict program allowed) := by
  refine ⟨rfl, fun _ => rfl, ?_, ?_⟩
  · intro id retained
    exact (find_filtered program.functions allowed id retained).symm
  · intro id declaration code retained found codeFound
    have member : declaration ∈ program.functions := List.mem_of_find?_eq_some found
    have same : declaration.id = id := beq_iff_eq.mp
      (List.find?_some (p := fun entry : Function => entry.id == id) found)
    have checked := List.all_eq_true.mp closed declaration member
    simpa [same, retained, codeFound, Dependencies.body] using checked

def check? (program : Program) (allowed : FunctionId → Bool) :
    Option (PLift (Agreement allowed program (Dependencies.restrict program allowed))) :=
  if closed : Dependencies.closed program allowed then some ⟨ofClosed program allowed closed⟩ else none

end Lanius.Semantics.Restriction
