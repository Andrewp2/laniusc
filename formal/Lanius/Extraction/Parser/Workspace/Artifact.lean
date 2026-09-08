import Lanius.Compiler.ParserEncoding
import Lanius.ExecutionRules
import Lanius.Semantics.Relocation.Ownership

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core Lanius.Semantics Lanius.Compiler.Parser

/-- Caller-visible workspace representation, independent of recognizer
    execution proofs and callee-local parameter bindings. -/
structure RecognizerWorkspaceArtifact
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int) (workspaceCell : Lanius.CellId)
    (runtime : State) : Prop where
  workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength
  workspaceEncoded : EncodesWorkspace workspaceLayout workspace (listWords workspaceValues)
  workspaceBacking : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values workspaceValues))
  }

theorem RecognizerWorkspaceArtifact.transfer_cells
    (artifact : RecognizerWorkspaceArtifact workspaceLayout workspace
      workspaceValues workspaceCell before)
    (cells : after.cells = before.cells) :
    RecognizerWorkspaceArtifact workspaceLayout workspace workspaceValues
      workspaceCell after := {
  workspaceLength := artifact.workspaceLength
  workspaceEncoded := artifact.workspaceEncoded
  workspaceBacking := by
    simpa [State.cellEntry?, cells] using artifact.workspaceBacking
}

/-- Symbol relocation preserves the integer buffer and its physical cell. -/
theorem RecognizerWorkspaceArtifact.relocated
    (artifact : RecognizerWorkspaceArtifact workspaceLayout workspace
      workspaceValues workspaceCell before) (symbols : Core.Relocation.Symbols) :
    RecognizerWorkspaceArtifact workspaceLayout workspace workspaceValues workspaceCell
      (Semantics.Relocation.state symbols before) := {
  workspaceLength := artifact.workspaceLength
  workspaceEncoded := artifact.workspaceEncoded
  workspaceBacking := by
    rw [Semantics.Relocation.cellEntry, artifact.workspaceBacking]
    simp only [Option.map, Semantics.Relocation.cell, Core.Relocation.value,
      Semantics.Relocation.signedI32Values_fixed]
}

end Lanius.Extraction.ParserRecognize
