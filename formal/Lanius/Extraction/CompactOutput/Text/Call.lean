import Lanius.Extraction.CompactOutput.Text.Entry

namespace Lanius.Extraction.CompactOutput.Text

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

def arguments (output : Value) (capacity position : Nat) (text : String) (length : Nat) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 position, .string text, .signed .i32 length]

/-- Call-level total correctness for the source-checked Lanius text helper.
Only the output cell may change; padding is borrowed but never appended. -/
theorem Checked.append (checked : Checked program byte) (before caller : State)
    (text : String) (bytes : List UInt8) (earlier untouched : List Int) (capacity : Nat)
    (wellFormed : StateWellFormed before)
    (outputContents : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values (earlier ++ untouched))) })
    (positionBound : earlier.length ≤ capacity)
    (capacityBound : capacity ≤ earlier.length + untouched.length)
    (capacityFit : capacity ≤ 2147483647)
    (lengthFit : bytes.length + 3 ≤ 2147483647)
    (padded : (Lanius.World.utf8Bytes text).length = ((bytes.length + 3) / 4) * 4)
    (prefixBytes : (Lanius.World.utf8Bytes text).take bytes.length = bytes)
    (evaluated : ArgumentsEvaluateTo program.core caller expressions
      (arguments (.slice i32 outputCell [] 0 (earlier.length + untouched.length))
        capacity earlier.length text bytes.length) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id expressions)
        (.signed .i32 (finalPosition bytes.length earlier.length capacity)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (Input.copiedBuffer earlier untouched (emitted bytes earlier.length capacity)))) } ∧
      CellEffect (CellSet.singleton outputCell) before after ∧
      (Allocation.Registry before → Allocation.Registry after) ∧
      (∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh) := by
  let values := arguments (.slice i32 outputCell [] 0 (earlier.length + untouched.length))
    capacity earlier.length text bytes.length
  let bindings := parameterBindings (fun index : Fin 5 => values.get index)
  have locals (index : Fin 5) : (enterCall before bindings).local? index.val = some (values.get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have contents := ((enterCall_effect before bindings).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed outputContents) (by simp [CellSet.empty])).trans outputContents
  obtain ⟨completed, run, output, effect, registered, views⟩ := executes byte (enterCall before bindings) text bytes earlier untouched
    capacity (enterCall_preserves_wellFormed wellFormed) (locals ⟨3, by decide⟩) (locals ⟨4, by decide⟩)
    (locals ⟨0, by decide⟩) (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩)
    contents positionBound capacityBound capacityFit lengthFit padded prefixBytes
  have called := checked.call wellFormed evaluated (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before completed, called.1, output, called.2,
    (fun initial => (registered (initial.enterCall bindings)).restoreLocals before called.2.wellFormed),
    by simpa only [restoreLocals, (enterCall_effect before bindings).views] using views⟩

end Lanius.Extraction.CompactOutput.Text
