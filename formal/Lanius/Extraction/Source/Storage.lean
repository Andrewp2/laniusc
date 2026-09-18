import Lanius.Extraction.Source.Call

namespace Lanius.CallContracts

open Lanius.Core Lanius.Semantics

/-- Storage facts survive allocation when every existing entry is retained.
They cannot observe local bindings, allocation counters, or absent cells. -/
structure Storage where
  holds : List Cell → Prop
  stable : ∀ {before after : State},
    (∀ {cell value}, before.cellEntry? cell = some { id := cell, value := value } →
      after.cellEntry? cell = some { id := cell, value := value }) →
    holds before.cells → holds after.cells

def Storage.pure (fact : Prop) : Storage := ⟨fun _ => fact, fun _ held => held⟩

def Storage.entry (cell : Lanius.CellId) (value : Option Value) : Storage :=
  ⟨fun cells => cells.find? (fun entry => entry.id == cell) = some ⟨cell, value⟩,
    fun retained held => retained held⟩

/-- A read-only call retains a proved storage predicate through fresh
parameter allocation. The predicate cannot inspect absent or fresh cells. -/
theorem CellSpec.frameStorage (spec : CellSpec program function values result) (storage : Storage) :
    CellSpec program function values result (fun before => storage.holds before.cells)
      (fun _ after => storage.holds after.cells) := by
  constructor
  intro caller arguments before wellFormed evaluated held
  obtain ⟨after, run, _, effect, heap⟩ := spec.call wellFormed evaluated
  exact ⟨after, run, storage.stable (fun found => effect.empty_preserves_entry wellFormed found) held, effect, heap⟩

end Lanius.CallContracts

namespace Lanius.Extraction.Source

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

/-- Lift a body contract once, preserving storage through parameter allocation
and hiding caller restoration from function-level composition proofs. -/
theorem CheckedInternal.specStorage (checked : CheckedInternal program path name parameters resultType body)
    {pre : Storage} {post : List Cell → Prop}
    (bound : bindParameters parameters values = some (parameterBindings (fun index : Fin values.length => values[index])))
    (execution : ∀ callee, StateWellFormed callee →
      (∀ index (within : index < values.length), callee.local? index = some values[index]) → pre.holds callee.cells →
      ∃ after, Executes program.core callee body (.returned (some result)) after ∧
        post after.cells ∧ CellEffect writes callee after ∧ HeapFrame callee after) :
    checked.Spec values result (fun before => pre.holds before.cells) (fun _ after => post after.cells) writes := by
  constructor
  intro caller arguments before wellFormed argumentsResult held
  let bindings := parameterBindings (fun index : Fin values.length => values[index])
  have retained := pre.stable (fun found => ((enterCall_effect before bindings).oldCells _
    (StateWellFormed.cell_lt_next_of_entry wellFormed found) (by simp [CellSet.empty])).trans found) held
  obtain ⟨completed, run, contents, effect, heap⟩ := execution (enterCall before bindings)
    (enterCall_preserves_wellFormed wellFormed)
    (fun index within => enterCall_parameterBindings_matches wellFormed ⟨index, within⟩) retained
  have called := checked.call wellFormed argumentsResult bound run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2, HeapFrame.closeCall before bindings heap⟩

end Lanius.Extraction.Source
