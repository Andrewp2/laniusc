import Lanius.Extraction.Parser.Derivation.Scopes
import Lanius.Extraction.Parser.Derivation.Source

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Fixed inputs to a reader iteration. Mutable cursor values are indices of
    `At`, so entering a temporary scope does not silently advance the cursor. -/
structure ReaderRuntime where
  stores : ChildStores
  tail : CheckedCursorTail stores
  offsetId : VarId
  tokenCountId : VarId
  layout : WorkspaceLayout
  workspace : LogicalWorkspace
  workspaceValues : List Int
  outputValues : List Int
  workspaceCell : CellId
  outputCell : CellId
  currentCell : CellId
  remainingCell : CellId
  offset : Nat
  tokenCount : Nat

def ReaderRuntime.liveLocals (reader : ReaderRuntime) : List VarId :=
  [reader.stores.output, reader.stores.workspace, reader.stores.base,
    reader.offsetId, reader.tokenCountId, reader.stores.current, reader.tail.remaining]

/-- Ownership and local bindings needed throughout child-field extraction.
    Temporary child fields are deliberately outside this persistent frame. -/
structure ReaderRuntime.At (reader : ReaderRuntime) (stateId remaining : Nat)
    (runtime : State) : Prop where
  wellFormed : StateWellFormed runtime
  artifact : RecognizerWorkspaceArtifact reader.layout reader.workspace
    reader.workspaceValues reader.workspaceCell runtime
  outputLocal : runtime.local? reader.stores.output = some
    (.slice parserI32Type reader.outputCell [] 0 reader.outputValues.length)
  workspaceLocal : runtime.local? reader.stores.workspace = some
    (.slice parserI32Type reader.workspaceCell [] 0 reader.workspaceValues.length)
  baseLocal : runtime.local? reader.stores.base = some
    (.signed .i32 (Int.ofNat (stateBase reader.layout.tokenCount)))
  offsetLocal : runtime.local? reader.offsetId = some (.signed .i32 (Int.ofNat reader.offset))
  tokenCountLocal : runtime.local? reader.tokenCountId = some (.signed .i32 (Int.ofNat reader.tokenCount))
  currentOwned : (Assertion.localPointsTo reader.stores.current reader.currentCell
    (some (.signed .i32 (Int.ofNat stateId)))).holds runtime
  remainingOwned : (Assertion.localPointsTo reader.tail.remaining reader.remainingCell
    (some (.signed .i32 (Int.ofNat remaining)))).holds runtime
  backing : runtime.cellEntry? reader.outputCell = some {
    id := reader.outputCell, value := some (.array (signedI32Values reader.outputValues)) }

theorem ReaderRuntime.At.after_read {reader : ReaderRuntime} (held : reader.At stateId remaining before)
    (effect : CellEffect CellSet.empty before after) : reader.At stateId remaining after := by
  refine ⟨effect.wellFormed, ?_, effect.empty_preserves_local held.wellFormed held.outputLocal,
    effect.empty_preserves_local held.wellFormed held.workspaceLocal,
    effect.empty_preserves_local held.wellFormed held.baseLocal,
    effect.empty_preserves_local held.wellFormed held.offsetLocal,
    effect.empty_preserves_local held.wellFormed held.tokenCountLocal,
    effect.preserves_localPointsTo held.wellFormed held.currentOwned (by simp [CellSet.empty]),
    effect.preserves_localPointsTo held.wellFormed held.remainingOwned (by simp [CellSet.empty]),
    effect.empty_preserves_entry held.wellFormed held.backing⟩
  exact ⟨held.artifact.workspaceLength, held.artifact.workspaceEncoded,
    effect.empty_preserves_entry held.wellFormed held.artifact.workspaceBacking⟩

theorem ReaderRuntime.At.bind {reader : ReaderRuntime} (held : reader.At stateId remaining before)
    (fresh : localId ∉ reader.liveLocals) (value : Value) :
    reader.At stateId remaining (before.bindLocal localId value) := by
  have different {queriedId : VarId} (member : queriedId ∈ reader.liveLocals) : localId ≠ queriedId := by
    intro same
    exact fresh (same ▸ member)
  have preserve {queriedId : VarId} {word : Value}
      (member : queriedId ∈ reader.liveLocals) (h : before.local? queriedId = some word) :
      (before.bindLocal localId value).local? queriedId = some word :=
    (bindLocal_preserves_other_local held.wellFormed (different member)).trans h
  refine ⟨bindLocal_preserves_well_formed _ _ _ held.wellFormed,
    held.artifact.bind_local held.wellFormed localId value,
    preserve (by simp [ReaderRuntime.liveLocals]) held.outputLocal,
    preserve (by simp [ReaderRuntime.liveLocals]) held.workspaceLocal,
    preserve (by simp [ReaderRuntime.liveLocals]) held.baseLocal,
    preserve (by simp [ReaderRuntime.liveLocals]) held.offsetLocal,
    preserve (by simp [ReaderRuntime.liveLocals]) held.tokenCountLocal,
    bindLocal_preserves_localPointsTo_of_ne _ _ _ _ _ _ held.wellFormed
      (different (by simp [ReaderRuntime.liveLocals])) held.currentOwned,
    bindLocal_preserves_localPointsTo_of_ne _ _ _ _ _ _ held.wellFormed
      (different (by simp [ReaderRuntime.liveLocals])) held.remainingOwned, ?_⟩
  exact ((bindLocal_effect before localId value).oldCells reader.outputCell
    (StateWellFormed.cell_lt_next_of_entry held.wellFormed held.backing)
    (by simp [CellSet.empty])).trans held.backing

end Lanius.Extraction.ParserDerivation
