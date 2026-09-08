import Lanius.Extraction.Parser.Derivation.Count
import Lanius.Extraction.Parser.Derivation.Base

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Caller resources before the reader creates its internal base local. -/
structure ReaderRuntime.Entry (reader : ReaderRuntime) (runtime : State) : Prop where
  wellFormed : StateWellFormed runtime
  artifact : RecognizerWorkspaceArtifact reader.layout reader.workspace
    reader.workspaceValues reader.workspaceCell runtime
  outputLocal : runtime.local? reader.stores.output = some
    (.slice parserI32Type reader.outputCell [] 0 reader.outputValues.length)
  workspaceLocal : runtime.local? reader.stores.workspace = some
    (.slice parserI32Type reader.workspaceCell [] 0 reader.workspaceValues.length)
  offsetLocal : runtime.local? reader.offsetId = some (.signed .i32 (Int.ofNat reader.offset))
  tokenCountLocal : runtime.local? reader.tokenCountId = some (.signed .i32 (Int.ofNat reader.tokenCount))
  backing : runtime.cellEntry? reader.outputCell = some {
    id := reader.outputCell, value := some (.array (signedI32Values reader.outputValues)) }

def ReaderRuntime.baseValue (reader : ReaderRuntime) : Value :=
  .signed .i32 (Int.ofNat (stateBase reader.tokenCount))

def ReaderRuntime.baseExpression (reader : ReaderRuntime) : Expr :=
  .binary .multiply
    (.binary .add (.binary .multiply (.local reader.tokenCountId) (.value (.signed .i32 2)))
      (.value (.signed .i32 1))) (.constant 24)

theorem ReaderRuntime.Entry.bind_base {reader : ReaderRuntime}
    (entry : reader.Entry before) (layoutTokens : reader.layout.tokenCount = reader.tokenCount)
    (fresh : reader.stores.base ∉ [reader.stores.output, reader.stores.workspace, reader.offsetId, reader.tokenCountId]) :
    reader.BeforeCursor (before.bindLocal reader.stores.base reader.baseValue) := by
  have preserve {localId : VarId} {value : Value}
      (member : localId ∈ [reader.stores.output, reader.stores.workspace, reader.offsetId, reader.tokenCountId])
      (found : before.local? localId = some value) :
      (before.bindLocal reader.stores.base reader.baseValue).local? localId = some value := by
    have different : reader.stores.base ≠ localId := by intro same; exact fresh (same ▸ member)
    exact (bindLocal_preserves_other_local entry.wellFormed different).trans found
  refine ⟨bindLocal_preserves_well_formed _ _ _ entry.wellFormed,
    entry.artifact.bind_local entry.wellFormed _ _,
    preserve (by simp) entry.outputLocal, preserve (by simp) entry.workspaceLocal, ?_,
    preserve (by simp) entry.offsetLocal, preserve (by simp) entry.tokenCountLocal, ?_⟩
  · simpa only [ReaderRuntime.baseValue, layoutTokens] using
      bindLocal_finds_local before reader.stores.base reader.baseValue entry.wellFormed
  · exact ((bindLocal_effect before reader.stores.base reader.baseValue).oldCells reader.outputCell
      (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing)
      (by simp [CellSet.empty])).trans entry.backing

/-- Execute the source base initializer and hide its fresh local after the
    continuation. The caller need not assume the initializer's execution. -/
theorem ReaderRuntime.Entry.with_base {reader : ReaderRuntime} {post : List Cell → Prop}
    (entry : reader.Entry before) (layoutTokens : reader.layout.tokenCount = reader.tokenCount)
    (tokenBound : reader.tokenCount ≤ maxTokenCount)
    (fresh : reader.stores.base ∉ [reader.stores.output, reader.stores.workspace, reader.offsetId, reader.tokenCountId])
    (continuation : reader.BeforeCursor (before.bindLocal reader.stores.base reader.baseValue) →
      ∃ completed, Executes verifiedParserCore (before.bindLocal reader.stores.base reader.baseValue)
        body completion completed ∧ post completed.cells ∧
        CellEffect writes (before.bindLocal reader.stores.base reader.baseValue) completed) :
    ∃ after, Executes verifiedParserCore before
      (.letLocal reader.stores.base parserI32Type reader.baseExpression body) completion after ∧
      post after.cells ∧ CellEffect writes before after := by
  obtain ⟨completed, execution, result, effect⟩ := continuation (entry.bind_base layoutTokens fresh)
  exact ⟨_, executesLetLocal (base_expression entry.tokenCountLocal tokenBound) execution, result,
    CellEffect.closeLocal before reader.stores.base reader.baseValue entry.wellFormed effect⟩

end Lanius.Extraction.ParserDerivation
