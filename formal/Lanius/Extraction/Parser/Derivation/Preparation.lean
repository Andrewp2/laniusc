import Lanius.Extraction.Parser.Derivation.Allocate

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

theorem ReaderRuntime.BeforeCursor.after_read {reader : ReaderRuntime}
    (entry : reader.BeforeCursor before) (effect : CellEffect CellSet.empty before after) :
    reader.BeforeCursor after := by
  refine ⟨effect.wellFormed, ?_,
    effect.empty_preserves_local entry.wellFormed entry.outputLocal,
    effect.empty_preserves_local entry.wellFormed entry.workspaceLocal,
    effect.empty_preserves_local entry.wellFormed entry.baseLocal,
    effect.empty_preserves_local entry.wellFormed entry.offsetLocal,
    effect.empty_preserves_local entry.wellFormed entry.tokenCountLocal,
    effect.empty_preserves_entry entry.wellFormed entry.backing⟩
  exact ⟨entry.artifact.workspaceLength, entry.artifact.workspaceEncoded,
    effect.empty_preserves_entry entry.wellFormed entry.artifact.workspaceBacking⟩

theorem ReaderRuntime.BeforeCursor.bind {reader : ReaderRuntime}
    (entry : reader.BeforeCursor before) (fresh : localId ∉ reader.readonlyLocals) (value : Value) :
    reader.BeforeCursor (before.bindLocal localId value) := by
  have preserve {queriedId : VarId} {word : Value} (member : queriedId ∈ reader.readonlyLocals)
      (found : before.local? queriedId = some word) :
      (before.bindLocal localId value).local? queriedId = some word := by
    have different : localId ≠ queriedId := by intro same; exact fresh (same ▸ member)
    exact (bindLocal_preserves_other_local entry.wellFormed different).trans found
  refine ⟨bindLocal_preserves_well_formed _ _ _ entry.wellFormed,
    entry.artifact.bind_local entry.wellFormed localId value,
    preserve (by simp [ReaderRuntime.readonlyLocals]) entry.outputLocal,
    preserve (by simp [ReaderRuntime.readonlyLocals]) entry.workspaceLocal,
    preserve (by simp [ReaderRuntime.readonlyLocals]) entry.baseLocal,
    preserve (by simp [ReaderRuntime.readonlyLocals]) entry.offsetLocal,
    preserve (by simp [ReaderRuntime.readonlyLocals]) entry.tokenCountLocal, ?_⟩
  exact ((bindLocal_effect before localId value).oldCells reader.outputCell
    (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing)
    (by simp [CellSet.empty])).trans entry.backing

end Lanius.Extraction.ParserDerivation
