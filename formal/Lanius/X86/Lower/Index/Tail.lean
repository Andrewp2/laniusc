import Lanius.X86.Lower.Index.Calls
import Lanius.X86.Lower.Index.Workspace

namespace Lanius.X86.Lower.Index.Emission

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def writes (output work temporary : CellId) : CellSet :=
  CellSet.union (CellSet.singleton output) (CellSet.union (CellSet.singleton work) (CellSet.singleton temporary))

theorem writes_cursor : CellSet.Subset (CellSet.union (CellSet.singleton output) (CellSet.singleton temporary)) (writes output work temporary) := by
  intro cell member
  rcases member with out | cursor
  · exact Or.inl out
  · exact Or.inr (Or.inr cursor)

theorem writes_workspace : CellSet.Subset (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) (writes output work temporary) := by
  intro cell member
  rcases member with out | workspace
  · exact Or.inl out
  · exact Or.inr (Or.inl workspace)

def tailBytes : List UInt8 := Chunk.length.bytes ++ (Chunk.pointer.bytes ++
  (Chunk.compare.bytes ++ (Chunk.require.bytes ++ Machine.Index.address.bytes)))

@[simp] theorem tailBytes_length : tailBytes.length = 33 := rfl

/-- The complete suffix after loading the saved descriptor: both descriptor
fields, comparison, branch/trap, address calculation, and the real return. -/
theorem tail (checked : Source.Index.Checked emitters)
    (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace)
    (start : Nat) (current : workspace[1]? = some (start : Int))
    (room : start + tailBytes.length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before (Source.Index.tail checked.constants checked.helpers.calls)
        (.returned (some (.signed .i32 (start + tailBytes.length : Nat)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (start + tailBytes.length : Nat)))) } ∧
      Buffer.Emission values start tailBytes emitted ∧
      CellEffect (writes output work temporary) before after ∧ HeapFrame before after := by
  have within : 1 < workspace.length := by
    by_cases inside : 1 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  have code := Frame.Slot.code_read checked.constants.code checked.constants.values.1
    (ready.inputs.found ⟨2, by simp⟩) ready.workBacking current
  obtain ⟨lengthState, lengthValues, lengthRun, lengthReady, lengthBytes, lengthEffect, lengthHeap⟩ :=
    step .length checked ready start code (by change start + 7 ≤ capacity; rw [tailBytes_length] at room; omega) storage bounded
  obtain ⟨pointerState, pointerValues, pointerRun, pointerReady, pointerBytes, pointerEffect, pointerHeap⟩ :=
    step .pointer checked lengthReady (start + 7) (local_evaluates _ lengthReady.read)
      (by change start + 7 + 7 ≤ capacity; rw [tailBytes_length] at room; omega)
      (by rw [lengthBytes.length]; exact storage) bounded
  obtain ⟨compareState, compareValues, compareRun, compareReady, compareBytes, compareEffect, compareHeap⟩ :=
    step .compare checked pointerReady (start + 14) (local_evaluates _ pointerReady.read)
      (by change start + 14 + 3 ≤ capacity; rw [tailBytes_length] at room; omega)
      (by rw [pointerBytes.length, lengthBytes.length]; exact storage) bounded
  obtain ⟨guardState, guardValues, guardRun, guardReady, guardBytes, guardEffect, guardHeap⟩ :=
    step .require checked compareReady (start + 17) (local_evaluates _ compareReady.read)
      (by change start + 17 + 8 ≤ capacity; rw [tailBytes_length] at room; omega)
      (by rw [compareBytes.length, pointerBytes.length, lengthBytes.length]; exact storage) bounded
  obtain ⟨after, emitted, finishRun, afterReady, finalBytes, finishEffect, finishHeap⟩ :=
    finish checked guardReady within (by change start + 17 + 8 + 8 ≤ capacity; exact room)
      (by rw [guardBytes.length, compareBytes.length, pointerBytes.length, lengthBytes.length]; exact storage) bounded
  exact ⟨after, emitted,
    executesSequence lengthRun (executesSequence pointerRun (executesSequence compareRun (executesSequence guardRun finishRun))),
    afterReady.outputBacking, afterReady.workBacking,
    lengthBytes.append (pointerBytes.append (compareBytes.append (guardBytes.append finalBytes))),
    (lengthEffect.weaken writes_cursor).trans ((pointerEffect.weaken writes_cursor).trans
      ((compareEffect.weaken writes_cursor).trans ((guardEffect.weaken writes_cursor).trans (finishEffect.weaken writes_workspace)))),
    lengthHeap.trans (pointerHeap.trans (compareHeap.trans (guardHeap.trans finishHeap)))⟩

end Lanius.X86.Lower.Index.Emission
