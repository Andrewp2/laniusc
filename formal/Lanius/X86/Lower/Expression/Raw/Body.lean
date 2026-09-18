import Lanius.X86.Lower.Expression.Raw.Prepare
import Lanius.X86.Lower.Expression.Raw.Guard.Body

namespace Lanius.X86.Lower.Expression.Raw

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Source Lanius.X86.Buffer

variable {emitters : CheckedBuffer encoded sources}
  {literal : Source.Expression.Literal.Checked emitters}

def tailBytes (slot : Nat) (lengthCode : List UInt8) : List UInt8 :=
  lengthCode ++ (Guard.bytes ++ Finish.bytes slot)

/-- The length recursion is the only induction obligation in this tail.
Its actual returned kind is checked before the proved guard and descriptor
emitters execute; the saved slot local is framed across the recursive call. -/
theorem tail
    (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (slot capacity cursor : Nat)
    (child : OperandCall checked 1 before recursed output work cursor workspace.length
      values childValues childWorkspace lengthCode)
    (inputPrefix : 5 ≤ bindings.length) (fresh : bindings.length ≤ checked.locals.next)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (slotLocal : before.local? checked.locals.slot = some (.signed .i32 slot))
    (positive : 1 ≤ slot) (slotBound : slot ≤ 1048576)
    (room : cursor + (tailBytes slot lengthCode).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted,
      Executes emitters.pack.program.core before
        (Source.Expression.Raw.tail literal checked.constants checked.helpers.calls checked.locals)
        (.returned (some (.signed .i32 6))) after ∧
      Literal.Ready after bindings frontier input output work transport emitted
        (childWorkspace.set 1 (cursor + (tailBytes slot lengthCode).length : Nat)) ∧
      Emission values cursor (tailBytes slot lengthCode) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have recursedReady := ready.frame child.effect child.outputBacking child.workBacking
  have workEntry := ready.entry 2 (by omega) workLocal
  have outputEntry := ready.entry 3 (by omega) outputLocal
  have capacityEntry := ready.entry 4 (by omega) capacityLocal
  have retainedSlot := child.effect.preserves_local ready.wellFormed slotLocal (by
    intro cell binding changed
    rcases changed with out | work
    · exact local_cell_ne_of_distinct_value slotLocal ready.outputBacking (by intro same; cases same) binding out
    · exact local_cell_ne_of_distinct_value slotLocal ready.workBacking (by intro same; cases same) binding work)
  have kind := literal.layout.signed.evaluates (before := recursed)
  rw [literal.layout.values.1] at kind
  have guard : Evaluates emitters.pack.program.core before
      (Source.Expression.Raw.lengthGuard literal checked.helpers.calls) (.boolean false) recursed := by
    apply evaluatesEagerBinary (by decide) (by decide) child.run kind
    simp [evalBinaryValue, scalarEqual]
  obtain ⟨after, emitted, run, afterReady, window, effect, heap⟩ := Guard.finishes checked recursedReady
    slot capacity (cursor + lengthCode.length) inputPrefix fresh
    (by simpa only [child.workspaceLength] using recursedReady.read 2 workEntry)
    (by simpa only [child.window.length] using recursedReady.read 3 outputEntry)
    (recursedReady.read 4 capacityEntry) retainedSlot positive slotBound child.current
    (by simpa only [tailBytes, List.length_append, Nat.add_assoc] using room)
    (by simpa only [child.window.length] using storage) bounded
  refine ⟨after, emitted, executesSequence (executesIfFalse guard (executesSkip _ _)) run,
    ?_, child.window.append window, child.effect.trans effect, child.heap.trans heap⟩
  simpa only [tailBytes, List.length_append, Nat.add_assoc] using afterReady

/-- Compile the complete authenticated raw branch. Both recursive calls are
explicit induction obligations; all intervening allocation, kind checks,
capture, signed guard, descriptor emission, and scope closure are derived.
The concrete pointer-local and literal rules discharge these obligations. -/
theorem body
    (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (top peak capacity start : Nat) (lengthCode : List UInt8)
    (pointer : OperandCall checked 4 before pointerState output work start workspace.length
      values pointerValues pointerWorkspace pointerCode)
    (inputPrefix : 5 ≤ bindings.length) (fresh : bindings.length ≤ checked.locals.slot)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (within : 6 < pointerWorkspace.length) (current : pointerWorkspace[6]? = some (top : Int))
    (watermark : pointerWorkspace[2]? = some (peak : Int))
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit)
    (slotRoom : top + 2 ≤ Frame.Allocate.limit)
    (room : start + (pointerCode ++ saveBytes top ++ tailBytes (top + 1) lengthCode).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (lengthCall : ∀ prepared preparedValues,
      Prepared prepared bindings frontier input output work checked.locals.slot top peak
        (start + pointerCode.length) transport pointerValues pointerWorkspace preparedValues →
      StoreEffect (Literal.writes output work) before prepared →
      ∃ recursed childValues,
        OperandCall checked 1 prepared recursed output work
          (start + pointerCode.length + (saveBytes top).length) pointerWorkspace.length
          preparedValues childValues childWorkspace lengthCode) :
    ∃ after emitted,
      Executes emitters.pack.program.core before
        (Source.Expression.Raw.branch literal checked.constants checked.helpers.calls checked.locals)
        (.returned (some (.signed .i32 6))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (childWorkspace.set 1 (start + (pointerCode ++ saveBytes top ++ tailBytes (top + 1) lengthCode).length : Nat)))) } ∧
      Emission values start (pointerCode ++ saveBytes top ++ tailBytes (top + 1) lengthCode) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  apply prepares checked ready top peak capacity start
    (Source.Expression.Raw.tail literal checked.constants checked.helpers.calls checked.locals)
    (tailBytes (top + 1) lengthCode) (.returned (some (.signed .i32 6))) pointer inputPrefix fresh
    workLocal outputLocal capacityLocal within current watermark ordered peakBound slotRoom
    (by simp only [List.length_append] at room; omega) storage bounded
  intro prepared preparedValues preparedReady preparedFrame
  obtain ⟨recursed, childValues, child⟩ := lengthCall prepared preparedValues preparedReady preparedFrame
  have workEntry := ready.entry 2 (by omega) workLocal
  have outputEntry := ready.entry 3 (by omega) outputLocal
  have capacityEntry := ready.entry 4 (by omega) capacityLocal
  have valueLength : preparedValues.length = values.length :=
    preparedReady.window.length.trans pointer.window.length
  have workspaceLength : (workspaceAfter pointerWorkspace top peak
      (start + pointerCode.length + (saveBytes top).length)).length = workspace.length := by
    simp only [workspaceAfter, List.length_set, Frame.Allocate.updated_length, pointer.workspaceLength]
  obtain ⟨after, emitted, run, afterReady, window, effect, heap⟩ := tail checked preparedReady.ready
    (top + 1) capacity (start + pointerCode.length + (saveBytes top).length)
    (by simpa only [workspaceAfter, List.length_set, Frame.Allocate.updated_length] using child)
    inputPrefix (Nat.le_trans fresh (Nat.le_of_lt checked.fresh.2))
    (by simpa only [workspaceLength] using preparedReady.ready.read 2 workEntry)
    (by simpa only [valueLength] using preparedReady.ready.read 3 outputEntry)
    (preparedReady.ready.read 4 capacityEntry) preparedReady.saved (by omega)
    (by unfold Frame.Allocate.limit at slotRoom; omega)
    (by simpa only [List.length_append, Nat.add_assoc] using room)
    (by simpa only [valueLength] using storage) bounded
  refine ⟨after, emitted, run, afterReady.outputBacking, ?_, window, effect, heap⟩
  simpa only [List.length_append, Nat.add_assoc] using afterReady.workBacking

end Lanius.X86.Lower.Expression.Raw
