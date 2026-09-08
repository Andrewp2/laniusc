import Lanius.Extraction.Parser.Derivation.Transport
import Lanius.Separation.Relocation
import Lanius.Semantics.Relocation.Ownership

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Integer record words have no relocatable type tags. -/
theorem relocate_words (symbols : Core.Relocation.Symbols)
    (backing : before.cellEntry? buffer = some {
      id := buffer, value := some (.array (signedI32Values words)) }) :
    (Semantics.Relocation.state symbols before).cellEntry? buffer = some {
      id := buffer, value := some (.array (signedI32Values words)) } := by
  rw [Semantics.Relocation.cellEntry, backing]
  simp only [Option.map, Semantics.Relocation.cell, Core.Relocation.value,
    Semantics.Relocation.signedI32Values_fixed]

theorem relocate_workspace (symbols : Core.Relocation.Symbols)
    (artifact : RecognizerWorkspaceArtifact layout workspace words buffer before) :
    RecognizerWorkspaceArtifact layout workspace words buffer (Semantics.Relocation.state symbols before) :=
  ⟨artifact.workspaceLength, artifact.workspaceEncoded, relocate_words symbols artifact.workspaceBacking⟩

/-- Transport execution together with its exact output, retained workspace,
    and caller-visible write footprint. The logical derivation is unchanged. -/
theorem LinkedReader.record_result {reader : CheckedReader program}
    (checked : LinkedReader reader allowed symbols)
    (execution : Executes verifiedParserCore before reader.standaloneBody
      (.returned (some (.signed .i32 (Int.ofNat root.dot)))) after)
    (output : after.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values
        (leading ++ derivationRecordWords root children ++ trailing))) })
    (workspace : RecognizerWorkspaceArtifact layout logicalWorkspace workspaceValues workspaceCell after)
    (effect : CellEffect (CellSet.singleton outputCell) before after) :
    Executes program.core (Semantics.Relocation.state symbols before) reader.body
      (.returned (some (.signed .i32 (Int.ofNat root.dot)))) (Semantics.Relocation.state symbols after) ∧
    (Semantics.Relocation.state symbols after).cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values
        (leading ++ derivationRecordWords root children ++ trailing))) } ∧
    RecognizerWorkspaceArtifact layout logicalWorkspace workspaceValues workspaceCell
      (Semantics.Relocation.state symbols after) ∧
    CellEffect (CellSet.singleton outputCell) (Semantics.Relocation.state symbols before)
      (Semantics.Relocation.state symbols after) := by
  exact ⟨checked.executes execution, relocate_words symbols output,
    relocate_workspace symbols workspace, effect.relocate symbols⟩

end Lanius.Extraction.ParserDerivation
