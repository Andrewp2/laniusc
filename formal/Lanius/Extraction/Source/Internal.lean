import Lanius.Extraction.CoreSynthesis.Program
import Lanius.Core.Equality
import Lanius.CallContracts
import Lanius.Separation.CellEffect

namespace Lanius.Extraction.Source

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CoreSynthesis.Program

/-- Authenticate a complete internal function, including its signature. The
body is a specification of source shape, not an assumed execution result. -/
structure CheckedInternal (program : CheckedProgram artifacts) (modulePath : Names.ModulePath)
    (name : Surface.Name) (parameters : List (VarId × Ty)) (resultType : Ty) (body : Stmt) where
  source : CheckedSourceFunction program modulePath name
  signature : source.function.parameters = parameters ∧ source.function.returnType = resultType ∧
    source.function.external = none
  bodyExact : source.function.body = some body

def checkInternal? (program : CheckedProgram artifacts) (modulePath : Names.ModulePath)
    (name : Surface.Name) (parameters : List (VarId × Ty)) (resultType : Ty) (body : Stmt) :
    Option (CheckedInternal program modulePath name parameters resultType body) := do
  let source ← checkSourceFunction? program modulePath name
  if signature : source.function.parameters = parameters ∧ source.function.returnType = resultType ∧
      source.function.external = none then
    match present : source.function.body with
    | none => none
    | some actual => do
      let equal ← Core.Equality.statement? actual body
      pure ⟨source, signature, present.trans (congrArg some equal.equal)⟩
  else none

/-- Shared call administration for proved bodies: check argument binding,
execute the exact selected function, restore caller locals, and hide fresh
parameter cells. Component theorems discharge `execution` themselves. -/
theorem CheckedInternal.call (checked : CheckedInternal program modulePath name parameters resultType body)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments values before)
    (bound : bindParameters parameters values = some bindings)
    (execution : Executes program.core (enterCall before bindings) body (.returned (some value)) completed)
    (effect : CellEffect writes (enterCall before bindings) completed) :
    Evaluates program.core caller (.call checked.source.function.id arguments) value (restoreLocals before completed) ∧
      CellEffect writes before (restoreLocals before completed) := by
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  exact ⟨evaluatesCallReturned argumentsResult found
    (by simpa only [checked.signature.1] using bound) checked.bodyExact execution,
    CellEffect.closeCall before bindings wellFormed effect⟩

end Lanius.Extraction.Source
