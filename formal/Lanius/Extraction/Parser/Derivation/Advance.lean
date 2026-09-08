import Lanius.Extraction.Parser.Derivation.Iteration

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

def ReaderRuntime.readonlyLocals (reader : ReaderRuntime) : List VarId :=
  [reader.stores.output, reader.stores.workspace, reader.stores.base, reader.offsetId, reader.tokenCountId]

/-- Source-local allocation must establish this separation; distinct names
    alone do not imply distinct cells in an arbitrary caller state. -/
def ReaderRuntime.StableLocals (reader : ReaderRuntime) (runtime : State) : Prop :=
  ∀ localId ∈ reader.readonlyLocals, ∀ cell, runtime.cellId? localId = some cell →
    cell ≠ reader.currentCell ∧ cell ≠ reader.remainingCell

def ReaderRuntime.writeChild (reader : ReaderRuntime) (child : Child) (remaining : Nat) : ReaderRuntime :=
  let slot := reader.offset + 4 + remaining * 3
  { reader with outputValues := ((reader.outputValues.set slot (childTag child)).set
    (slot + 1) (childPayload child)).set (slot + 2) (childKind child) }

theorem ReaderRuntime.writeChild_length (reader : ReaderRuntime) (child : Child) (remaining : Nat) :
    (reader.writeChild child remaining).outputValues.length = reader.outputValues.length := by
  simp [writeChild]

theorem ReaderRuntime.StableLocals.after_child {reader : ReaderRuntime}
    (stable : reader.StableLocals before)
    (effect : CellEffect writes before after) (child : Child) (remaining : Nat) :
    (reader.writeChild child remaining).StableLocals after := by
  intro localId member cell binding
  apply stable localId member cell
  simpa only [State.cellId?, effect.locals] using binding

/-- The concrete iteration result re-establishes every persistent runtime
    fact at the predecessor, with exactly the three output words updated. -/
theorem ReaderRuntime.At.after_child {reader : ReaderRuntime}
    (held : reader.At stateId (remaining + 1) before)
    (stable : reader.StableLocals before)
    (result : reader.ChildCells state remaining after)
    (pointer : state.previous = some previous)
    (effect : CellEffect (CellSet.union (CellSet.singleton reader.outputCell)
      (CellSet.union (CellSet.singleton reader.currentCell) (CellSet.singleton reader.remainingCell)))
      before after) :
    (reader.writeChild state.child remaining).At previous remaining after := by
  have preserve {localId : VarId} {value : Value}
      (member : localId ∈ reader.readonlyLocals)
      (found : before.local? localId = some value)
      (different : value ≠ .array (signedI32Values reader.outputValues)) :
      after.local? localId = some value := by
    apply effect.preserves_local held.wellFormed found
    intro cell binding written
    have bufferDifferent := local_cell_ne_of_distinct_value found held.backing different binding
    have cursorsDifferent := stable localId member cell binding
    exact written.elim bufferDifferent (fun cursor => cursor.elim cursorsDifferent.1 cursorsDifferent.2)
  refine ⟨effect.wellFormed, result.artifact, ?_,
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.writeChild]) held.workspaceLocal (by simp),
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.writeChild]) held.baseLocal (by simp),
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.writeChild]) held.offsetLocal (by simp),
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.writeChild]) held.tokenCountLocal (by simp),
    ⟨?_, ?_⟩, ⟨?_, result.remainingValue⟩, result.output⟩
  · simpa only [ReaderRuntime.writeChild, List.length_set] using
      preserve (by simp [ReaderRuntime.readonlyLocals]) held.outputLocal (by simp)
  · simpa only [ReaderRuntime.writeChild, State.cellId?, effect.locals] using held.currentOwned.1
  · simpa only [ReaderRuntime.writeChild, previousValue, pointer, encodeStateId] using result.current
  · simpa only [ReaderRuntime.writeChild, State.cellId?, effect.locals] using held.remainingOwned.1

/-- Synchronize the physical state update with the logical backpointer step.
    The fuel and remaining-child count both decrease, while the emitted
    logical suffix gains exactly the child whose three words were stored. -/
theorem ReaderRuntime.At.advance_cursor {reader : ReaderRuntime}
    (held : reader.At stateId (remaining + 1) before)
    (stable : reader.StableLocals before)
    (cursor : DerivationCursor reader.workspace root state (fuel + 1) stateId (remaining + 1) suffix children)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (result : reader.ChildCells state remaining after)
    (effect : CellEffect (CellSet.union (CellSet.singleton reader.outputCell)
      (CellSet.union (CellSet.singleton reader.currentCell) (CellSet.singleton reader.remainingCell)))
      before after) :
    ∃ previous previousState, previous < stateId ∧
      DerivationCursor reader.workspace root previousState fuel previous remaining
        (state.child :: suffix) children ∧
      (reader.writeChild state.child remaining).At previous remaining after ∧
      (reader.writeChild state.child remaining).StableLocals after := by
  obtain ⟨previous, previousState, pointer, earlier, next⟩ := cursor.advance sound
  exact ⟨previous, previousState, earlier, next, held.after_child stable result pointer effect,
    stable.after_child effect state.child remaining⟩

/-- The exact output layout advances with the logical suffix. Header words,
    unfinished earlier slots, and trailing capacity remain untouched. -/
theorem ReaderRuntime.writeChild_suffix (reader : ReaderRuntime)
    (layout : reader.outputValues = leading ++ [oldTag, oldPayload, oldKind] ++
      suffix.flatMap derivationChildWords ++ trailing)
    (slot : leading.length = reader.offset + 4 + remaining * 3) (child : Child) :
    (reader.writeChild child remaining).outputValues =
      leading ++ (child :: suffix).flatMap derivationChildWords ++ trailing := by
  simp only [ReaderRuntime.writeChild]
  rw [layout, ← slot]
  exact derivationChildWords_store leading trailing oldTag oldPayload oldKind child suffix

end Lanius.Extraction.ParserDerivation
