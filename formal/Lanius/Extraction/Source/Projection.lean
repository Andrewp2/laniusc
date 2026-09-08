import Lanius.Extraction.CoreSynthesis.Program
import Lanius.Core.Equality
import Lanius.CallContracts
import Lanius.ExecutionRules
import Lanius.Separation.CellEffect

namespace Lanius.Extraction.Source

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CoreSynthesis.Program

def projectionBody (field : Lanius.FieldId) : Stmt :=
  .sequence (.returnValue (some (.field (.local 0) field))) .skip

/-- A current-source result accessor, checked independently of historical
    artifact coordinates. The same contract serves parser and tree results. -/
structure CheckedProjection (program : CheckedProgram artifacts) (modulePath : Names.ModulePath)
    (name : Surface.Name) (typeId : Lanius.TypeId) (field : Lanius.FieldId) where
  source : CheckedSourceFunction program modulePath name
  parameters : source.function.parameters = [(0, .structure typeId)]
  resultType : source.function.returnType = .scalar (.signed .i32)
  internal : source.function.external = none
  body : source.function.body = some (projectionBody field)

def checkProjection? (program : CheckedProgram artifacts) (modulePath : Names.ModulePath)
    (name : Surface.Name) (typeId : Lanius.TypeId) (field : Lanius.FieldId) :
    Option (CheckedProjection program modulePath name typeId field) := do
  let source ← checkSourceFunction? program modulePath name
  if shape : source.function.parameters = [(0, .structure typeId)] ∧
      source.function.returnType = .scalar (.signed .i32) ∧ source.function.external = none then
    match present : source.function.body with
    | none => none
    | some body => do
      let equal ← Lanius.Core.Equality.statement? body (projectionBody field)
      pure ⟨source, shape.1, shape.2.1, shape.2.2, present.trans (congrArg some equal.equal)⟩
  else none

theorem CheckedProjection.call (checked : CheckedProjection program modulePath name typeId field)
    (wellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments [.structure typeId fields] afterArguments)
    (selected : fields[field]? = some value) :
    ∃ after, Evaluates program.core before (.call checked.source.function.id arguments) value after ∧
      CellEffect CellSet.empty afterArguments after := by
  let bindings : List (Lanius.VarId × Value) := [(0, .structure typeId fields)]
  let callee := enterCall afterArguments bindings
  have calleeWF : StateWellFormed callee := enterCall_preserves_wellFormed wellFormed
  have argument : callee.local? 0 = some (.structure typeId fields) :=
    enterCall_local_of_binding afterArguments [] [] 0 (.structure typeId fields) wellFormed (by simp)
  have projected := evaluatesStructureField
    (show Evaluates program.core callee (.local 0) (.structure typeId fields) callee from
      ⟨1, evalLocal_of_local 0 program.core callee 0 _ argument⟩) selected
  have body : Executes program.core callee (projectionBody field) (.returned (some value)) callee :=
    executesSequenceReturned (executesReturnValue projected)
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  have bound : bindParameters checked.source.function.parameters [.structure typeId fields] = some bindings := by
    rw [checked.parameters]
    rfl
  exact ⟨restoreLocals afterArguments callee,
    evaluatesCallReturned argumentsResult found bound checked.body body,
    CellEffect.closeCall afterArguments bindings wellFormed (CellEffect.refl calleeWF)⟩

end Lanius.Extraction.Source
