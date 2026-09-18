import Lanius.Core.Dependencies

namespace Lanius.Core.Dependencies

/-- Candidate callees of a body. Consumers must independently check the
resulting closure; this discovery procedure is not part of their soundness. -/
def calls (program : Program) (body : Option Stmt) : List FunctionId :=
  (program.functions.filter fun candidate =>
    !Dependencies.body (fun called => called != candidate.id) body).map Function.id

private def discover (program : Program) : Nat → List FunctionId → List FunctionId → List FunctionId
  | 0, _, seen => seen
  | fuel + 1, pending, seen =>
    match pending.find? (fun id => !seen.contains id) with
    | none => seen
    | some id =>
      let callees := match program.function? id with
        | none => []
        | some declaration => calls program declaration.body
      discover program fuel (pending ++ callees) (id :: seen)

def closure (program : Program) (roots : List FunctionId) : List FunctionId :=
  discover program program.functions.length roots []

end Lanius.Core.Dependencies
