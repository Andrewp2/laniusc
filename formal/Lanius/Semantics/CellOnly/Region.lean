import Lanius.Semantics.CellOnly.Execution
import Lanius.Core.Dependencies.Closure

namespace Lanius.Semantics.CellOnly

open Lanius.Core Lanius.Separation

/-- Checked source syntax and its entire transitive call set. There is no
execution, heap shape, typing, or success premise in this static certificate. -/
structure Region (program : Program) (body : Stmt) where
  allowed : FunctionId → Bool
  functions : Checked program allowed
  supported : statement allowed body = true

def checkRegion? (program : Program) (body : Stmt) : Option (Region program body) := do
  let reachable := Dependencies.closure program (Dependencies.calls program (some body))
  let allowed := fun id => reachable.contains id
  if supported : statement allowed body = true then
    if accepted : check program allowed = true then
      pure ⟨allowed, checked accepted, supported⟩
    else none
  else none

theorem Region.executes (region : Region program body)
    (executed : Executes program before body result after) : HeapFrame before after :=
  region.functions.executes region.supported executed

theorem Region.evaluates (region : Region program (.expression input))
    (evaluated : Evaluates program before input result after) : HeapFrame before after :=
  region.functions.evaluates (by simpa only [statement] using region.supported) evaluated

end Lanius.Semantics.CellOnly
