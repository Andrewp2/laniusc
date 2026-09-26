import Lanius.Compiler.SourceCoreBoundary
import Lanius.Execution

namespace Lanius.Compiler.ExecutableBoundary

open Lanius

structure MainSelection (lowering : ProgramLowering.ProgramLowering) where
  body : ProgramLowering.FunctionBodyLowering
    lowering.pack lowering.catalog lowering.program lowering.environment
      lowering.context lowering.declarations
  bodyMember : body ∈ lowering.functionBodies
  sourceName : body.row.header.name = some "main"
  sourceValueNamespace : body.row.header.lookupNamespace = some .value
  zeroParameters : body.core.parameters = []
  allowedReturn : Execution.EntrypointReturnType body.core.returnType

structure ExecutableBoundary
    (encoded : String) (expectedSources : List Extraction.SourceFile)
    (checked : Extraction.SyntaxCheck.CheckedSourcePack encoded expectedSources) where
  source : SourceCoreBoundary.SourceCoreBoundary encoded expectedSources checked
  main : MainSelection source.lowering

def executable {encoded : String} {expectedSources : List Extraction.SourceFile}
    {checked : Extraction.SyntaxCheck.CheckedSourcePack encoded expectedSources}
    (boundary : ExecutableBoundary encoded expectedSources checked) : Execution.Executable :=
  { program := boundary.source.lowering.program,
    entrypoint := boundary.main.body.core.id }

private theorem findFunction_of_mem_unique
    {functions : List Core.Function} {function : Core.Function}
    (unique : (functions.map fun candidate => candidate.id).Nodup)
    (member : function ∈ functions) :
    functions.find? (fun candidate => candidate.id == function.id) = some function := by
  induction functions with
  | nil => simp at member
  | cons head tail inductionHypothesis =>
      simp only [List.map_cons, List.nodup_cons] at unique
      by_cases same : head.id == function.id
      · have sameId : head.id = function.id := by simpa using same
        have headEq : head = function := by
          rcases List.mem_cons.mp member with headMember | tailMember
          · exact headMember.symm
          · exfalso
            apply unique.1
            exact List.mem_map.mpr ⟨function, tailMember, sameId.symm⟩
        simp [headEq]
      · have different : head.id ≠ function.id := by
          intro equality
          apply same
          simp [equality]
        have tailMember : function ∈ tail := by
          rcases List.mem_cons.mp member with headMember | tailMember
          · exfalso
            apply different
            simp [headMember]
          · exact tailMember
        have sameFalse : (head.id == function.id) = false :=
          by
            cases h : (head.id == function.id) with
            | false => rfl
            | true => exact (same h).elim
        simp [List.find?, sameFalse,
          inductionHypothesis unique.2 tailMember]

theorem selected_wellFormed (lowering : ProgramLowering.ProgramLowering)
    (selection : MainSelection lowering) :
    Execution.ExecutableWellFormed
      { program := lowering.program, entrypoint := selection.body.core.id } := by
  have member := selection.body.row.member
  rw [selection.body.coreMap] at member
  have found : lowering.program.function?
      selection.body.core.id = some selection.body.core := by
    unfold Core.Program.function?
    exact findFunction_of_mem_unique lowering.functionsUnique member
  have typed : Typing.FunctionWellTyped lowering.program
      selection.body.core :=
    lowering.wellTyped.2 selection.body.core member
  exact ⟨selection.body.core, found, selection.zeroParameters,
    selection.allowedReturn, typed⟩

theorem executable_wellFormed
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {checked : Extraction.SyntaxCheck.CheckedSourcePack encoded expectedSources}
    (boundary : ExecutableBoundary encoded expectedSources checked) :
    Execution.ExecutableWellFormed (executable boundary) :=
  selected_wellFormed boundary.source.lowering boundary.main

end Lanius.Compiler.ExecutableBoundary
