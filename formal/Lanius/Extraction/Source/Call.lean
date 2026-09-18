import Lanius.Extraction.Source.Internal
import Lanius.FunctionalViewCoreSimulation
import Lanius.CallContracts.CellSpec

namespace Lanius.Extraction.Source

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

/-- Total cell-effect specification of the actual source-checked function. -/
abbrev CheckedInternal.Spec
    (checked : CheckedInternal program modulePath name parameters resultType body)
    (values : List Value) (result : Value)
    (requires : State → Prop := fun _ => True)
    (ensures : State → State → Prop := fun _ _ => True)
    (writes : CellSet := CellSet.empty) : Prop :=
  CellSpec program.core checked.source.function.id values result requires ensures writes

/-- Lift a body that updates one existing cell. Parameter allocation, backing
lookup, and caller restoration are shared by buffer writers and wrappers. -/
theorem CheckedInternal.specCell
    (checked : CheckedInternal program modulePath name parameters resultType body)
    (bound : bindParameters parameters values =
      some (parameterBindings (fun index : Fin values.length => values[index])))
    (execution : ∀ callee, StateWellFormed callee →
      (∀ index (within : index < values.length), callee.local? index = some values[index]) →
      callee.cellEntry? cell = some { id := cell, value := some original } →
      ∃ after, Executes program.core callee body (.returned (some value)) after ∧
        after.cellEntry? cell = some { id := cell, value := some written } ∧
        CellEffect (CellSet.singleton cell) callee after ∧ HeapFrame callee after) :
    checked.Spec values value
      (requires := fun before => before.cellEntry? cell = some { id := cell, value := some original })
      (ensures := fun _ after => after.cellEntry? cell = some { id := cell, value := some written })
      (writes := CellSet.singleton cell) := by
  constructor
  intro caller arguments before wellFormed argumentsResult backing
  let bindings := parameterBindings (fun index : Fin values.length => values[index])
  have calleeBacking := ((enterCall_effect before bindings).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, run, contents, effect, heapFrame⟩ := execution (enterCall before bindings)
    (enterCall_preserves_wellFormed wellFormed)
    (fun index within => enterCall_parameterBindings_matches wellFormed ⟨index, within⟩) calleeBacking
  have called := checked.call wellFormed argumentsResult bound run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2,
    HeapFrame.closeCall before bindings heapFrame⟩

/-- Effectful helper calls may allocate parameter cells without changing
existing caller storage. Close that frame once for all guarded wrappers. -/
theorem CheckedInternal.specFrame
    (checked : CheckedInternal program modulePath name parameters resultType body)
    (bound : bindParameters parameters values =
      some (parameterBindings (fun index : Fin values.length => values[index])))
    (execution : ∀ callee, StateWellFormed callee →
      (∀ index (within : index < values.length), callee.local? index = some values[index]) →
      ∃ after, Executes program.core callee body (.returned (some value)) after ∧
        CellEffect CellSet.empty callee after ∧ HeapFrame callee after) :
    checked.Spec values value := by
  constructor
  intro caller arguments before wellFormed argumentsResult _
  let bindings := parameterBindings (fun index : Fin values.length => values[index])
  obtain ⟨completed, run, effect, heap⟩ := execution (enterCall before bindings)
    (enterCall_preserves_wellFormed wellFormed)
    (fun index within => enterCall_parameterBindings_matches wellFormed ⟨index, within⟩)
  have called := checked.call wellFormed argumentsResult bound run effect
  exact ⟨restoreLocals before completed, called.1, trivial, called.2, HeapFrame.closeCall before bindings heap⟩

/-- Pure bodies are the reflexive case of the shared call-frame rule.
Argument effects end at `before`, not at the caller's initial state. -/
theorem CheckedInternal.specPure
    (checked : CheckedInternal program modulePath name parameters resultType body)
    (bound : bindParameters parameters values =
      some (parameterBindings (fun index : Fin values.length => values[index])))
    (execution : ∀ callee,
      (∀ index (within : index < values.length), callee.local? index = some values[index]) →
      Executes program.core callee body (.returned (some value)) callee) :
    checked.Spec values value := by
  apply checked.specFrame bound
  intro callee wellFormed locals
  exact ⟨callee, execution callee locals, CellEffect.refl wellFormed, HeapFrame.refl callee⟩

end Lanius.Extraction.Source
