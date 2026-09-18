import Lanius.Extraction.Allocation.Registry
import Lanius.Extraction.Allocation.Storage
import Lanius.Separation.HeapFrame

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

theorem Registry.bindLocals (initial : Registry before) (bindings : List (Lanius.VarId × Value)) :
    Registry (before.bindLocals bindings) := by
  induction bindings generalizing before with
  | nil => exact initial
  | cons binding rest ih =>
      exact ih (initial.bindLocal binding.1 binding.2)

theorem Registry.enterCall (initial : Registry before) (bindings : List (Lanius.VarId × Value)) :
    Registry (Lanius.Separation.enterCall before bindings) := by
  have cleared : Registry { before with locals := [] } :=
    ⟨clearLocals_preserves_wellFormed initial.wellFormed, initial.blocks,
      initial.roots, initial.distinct, initial.arrays, initial.addresses⟩
  exact cleared.bindLocals bindings

theorem Registry.restoreLocals (initial : Registry after) (caller : State)
    (wellFormed : StateWellFormed (Lanius.Semantics.restoreLocals caller after)) :
    Registry (Lanius.Semantics.restoreLocals caller after) :=
  ⟨wellFormed, initial.blocks, initial.roots, initial.distinct, initial.arrays, initial.addresses⟩

/-- Transport the registry through typed cell writes. Untouched registered
arrays are recovered from the frame; only modified roots need a new typing
and length proof. The heap/view frame rules out hidden registration changes. -/
theorem Registry.transport (initial : Registry before) (effect : CellEffect writes before after)
    (frame : HeapFrame before after)
    (changed : ∀ view ∈ before.i32ArrayViews, writes view.root → ∃ elements,
      readCellProjection after view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧ ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    Registry after := by
  refine ⟨effect.wellFormed, ?_, ?_, ?_, ?_, ?_⟩
  · simpa only [frame.views, frame.heap] using initial.blocks
  · simpa only [frame.views] using initial.roots
  · simpa only [frame.views] using initial.distinct
  · intro view member
    rw [frame.views] at member
    by_cases written : writes view.root
    · exact changed view member written
    · obtain ⟨elements, read, length, typed⟩ := initial.arrays view member
      have kept := effect.oldCells view.root (initial.root_lt_next member) written
      exact ⟨elements, by simpa only [readCellProjection, kept] using read, length, typed⟩
  · simpa only [frame.views] using initial.addresses

theorem Registry.unchanged (initial : Registry before) (effect : CellEffect CellSet.empty before after)
    (frame : HeapFrame before after) : Registry after :=
  initial.transport effect frame (fun _ _ impossible => False.elim impossible)

theorem Registry.arrayLength (initial : Registry before) (member : view ∈ before.i32ArrayViews)
    (contents : before.cellEntry? view.root = some {
      id := view.root, value := some (.array (signedI32Values values)) }) : values.length = view.length := by
  obtain ⟨stored, length, found⟩ := initial.storage member
  have lengths := congrArg (fun entry : Option Cell => entry.map fun cell =>
    match cell.value with | some (.array elements) => elements.length | _ => 0) (found.symm.trans contents)
  simp only [Option.map_some, signedI32Values, List.length_map, Option.some.injEq] at lengths
  exact lengths.symm.trans length

theorem Registry.notScalar (initial : Registry before) (member : view ∈ before.i32ArrayViews)
    (scalar : before.cellEntry? view.root = some { id := view.root, value := some (.signed type value) }) : False := by
  obtain ⟨stored, _, found⟩ := initial.storage member
  rw [scalar] at found
  cases found

/-- Updating one array and one scalar cursor preserves registration. The
cursor cannot be a registered array root, as shown by its original contents. -/
theorem Registry.updateArrayAndScalar (initial : Registry before)
    (effect : CellEffect (CellSet.union (CellSet.singleton arrayCell) (CellSet.singleton scalarCell)) before after)
    (frame : HeapFrame before after)
    (original : before.cellEntry? arrayCell = some { id := arrayCell, value := some (.array (signedI32Values values)) })
    (updated : after.cellEntry? arrayCell = some { id := arrayCell, value := some (.array (signedI32Values result)) })
    (length : result.length = values.length)
    (scalar : before.cellEntry? scalarCell = some { id := scalarCell, value := some (.signed type value) }) :
    Registry after := by
  apply initial.transport effect frame
  intro view member changed
  rcases changed with atArray | atScalar
  · change view.root = arrayCell at atArray
    have originalView : before.cellEntry? view.root = some {
        id := view.root, value := some (.array (signedI32Values values)) } := atArray.symm ▸ original
    refine ⟨signedI32Values result, ?_, ?_, ?_⟩
    · simp [readCellProjection, initial.roots view member, atArray, updated, projectedValue]
    · simpa only [signedI32Values, List.length_map, length] using initial.arrayLength member originalView
    · intro element present
      obtain ⟨value, _, rfl⟩ := List.mem_map.mp present
      exact ⟨value, rfl⟩
  · change view.root = scalarCell at atScalar
    exact False.elim (initial.notScalar member (atScalar.symm ▸ scalar))

end Lanius.Extraction.Allocation
