import Lanius.X86.Lower.Expression.Raw.Guard
import Lanius.X86.Lower.Expression.Raw.Finish

namespace Lanius.X86.Lower.Expression.Raw.Guard

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Source Lanius.X86.Buffer Lanius.X86.Control

variable {emitters : CheckedBuffer encoded sources}
  {literal : Source.Expression.Literal.Checked emitters}

@[simp] theorem bytes_length : bytes.length = 12 := by simp [bytes, testBytes]

/-- Compose the actual TEST/JGE/UD2/MOV32 statements and their descriptor
continuation. The captured slot is preserved by its physical cell identity,
which precedes the newly allocated cursor cell even when their values agree.
The cursor write footprint is hidden only after its actual scope is closed. -/
theorem finishes (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (slot capacity start : Nat)
    (inputPrefix : 5 ≤ bindings.length) (fresh : bindings.length ≤ checked.locals.next)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (slotLocal : before.local? checked.locals.slot = some (.signed .i32 slot))
    (positive : 1 ≤ slot) (slotBound : slot ≤ 1048576)
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes ++ Finish.bytes slot).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted,
      Executes emitters.pack.program.core before
        (Source.Expression.Raw.guardBody literal checked.constants checked.helpers.calls checked.locals
          (Source.Expression.Raw.finish literal checked.helpers.calls checked.locals))
        (.returned (some (.signed .i32 6))) after ∧
      Literal.Ready after bindings frontier input output work transport emitted
        (workspace.set 1 (start + (bytes ++ Finish.bytes slot).length : Nat)) ∧
      Emission values start (bytes ++ Finish.bytes slot) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have workEntry := ready.entry 2 (by omega) workLocal
  have outputEntry := ready.entry 3 (by omega) outputLocal
  have capacityEntry := ready.entry 4 (by omega) capacityLocal
  have guardRoom : start + 12 ≤ capacity := by
    simp only [List.length_append, bytes_length] at room
    omega
  have within : 1 < workspace.length := by
    by_cases inside : 1 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  obtain ⟨slotCell, ownedSlot⟩ := Assertion.exists_localPointsTo_of_local before checked.locals.slot _ slotLocal
  have slotOutput : slotCell ≠ output := local_cell_ne_of_distinct_value slotLocal ready.outputBacking
    (by intro equal; cases equal) ownedSlot.1
  have slotWork : slotCell ≠ work := local_cell_ne_of_distinct_value slotLocal ready.workBacking
    (by intro equal; cases equal) ownedSlot.1
  obtain ⟨tested, testRun, testedReady, testWindow, testEffect, testHeap⟩ := test checked ready capacity start
    workLocal outputLocal capacityLocal current (by omega) storage bounded
  have testedSlot := testEffect.preserves_localPointsTo ready.wellFormed ownedSlot slotOutput
  have scopedReady := testedReady.bind checked.locals.next fresh (.signed .i32 (start + 2 : Nat))
  have cursorOwned := bindLocal_owns_fresh tested checked.locals.next (.signed .i32 (start + 2 : Nat)) testedReady.wellFormed
  have cursorFresh : frontier ≤ tested.nextCell := testedReady.locals.frontierBound
  have slotCursor : slotCell ≠ tested.nextCell :=
    Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry testedReady.wellFormed testedSlot.2)
  have scopedSlot := bindLocal_preserves_localPointsTo_of_ne tested checked.locals.next checked.locals.slot
    (.signed .i32 (start + 2 : Nat)) slotCell _ testedReady.wellFormed
    (Nat.ne_of_gt checked.fresh.2) testedSlot
  have slotUntouched : ¬ cursorWrites output work tested.nextCell slotCell := by
    intro changed
    rcases changed with (out | work) | cursor
    · exact slotOutput out
    · exact slotWork work
    · exact slotCursor cursor
  obtain ⟨branched, branchRun, branchedReady, branchCursor, branchWindow, branchEffect, branchHeap⟩ :=
    branch checked scopedReady capacity (start + 2) cursorOwned cursorFresh
      (by simpa only [testWindow.length] using scopedReady.read 3 outputEntry)
      (scopedReady.read 4 capacityEntry) (by omega)
      (by simpa only [testWindow.length] using storage) bounded
  have branchedSlot := branchEffect.preserves_localPointsTo scopedReady.wellFormed scopedSlot slotUntouched
  have branchCursorExact : (Assertion.localPointsTo checked.locals.next tested.nextCell
      (some (.signed .i32 (start + 8 : Nat)))).holds branched := by
    simpa only [Nat.add_assoc] using branchCursor
  obtain ⟨trapped, trapRun, trappedReady, trapCursor, trapWindow, trapEffect, trapHeap⟩ :=
    trap checked branchedReady capacity (start + 8) branchCursorExact cursorFresh
      (by simpa only [branchWindow.length, testWindow.length] using branchedReady.read 3 outputEntry)
      (branchedReady.read 4 capacityEntry) (by omega)
      (by simpa only [branchWindow.length, testWindow.length] using storage) bounded
  have trappedSlot := trapEffect.preserves_localPointsTo branchedReady.wellFormed branchedSlot slotUntouched
  have trapCursorExact : trapped.local? checked.locals.next = some (.signed .i32 (start + 10 : Nat)) := by
    simpa only [Nat.add_assoc] using Assertion.localPointsTo_local checked.locals.next tested.nextCell _ trapped trapCursor
  obtain ⟨moved, moveRun, movedReady, moveWindow, moveEffect, moveHeap⟩ :=
    move checked trappedReady capacity (start + 10) trapCursorExact (trappedReady.read 2 workEntry)
      (by simpa only [trapWindow.length, branchWindow.length, testWindow.length] using trappedReady.read 3 outputEntry)
      (trappedReady.read 4 capacityEntry) within (by omega)
      (by simpa only [trapWindow.length, branchWindow.length, testWindow.length] using storage) bounded
  have movedSlot := moveEffect.preserves_localPointsTo trappedReady.wellFormed trappedSlot (by
    intro changed; rcases changed with out | work
    · exact slotOutput out
    · exact slotWork work)
  have finishRoom : start + 12 + (Finish.bytes slot).length ≤ capacity := by
    simpa only [List.length_append, bytes_length, Nat.add_assoc] using room
  have movedReadyExact := movedReady
  rw [show start + 10 + 2 = start + 12 by omega] at movedReadyExact
  obtain ⟨completed, emitted, finishRun, finalReady, finishWindow, finishEffect, finishHeap⟩ :=
    Finish.emits checked movedReadyExact slot capacity (start + 12) inputPrefix
      (by simpa only [List.length_set] using movedReadyExact.read 2 workEntry)
      (by simpa only [moveWindow.length, trapWindow.length, branchWindow.length, testWindow.length]
        using movedReadyExact.read 3 outputEntry)
      (movedReadyExact.read 4 capacityEntry)
      (Assertion.localPointsTo_local checked.locals.slot slotCell _ moved movedSlot)
      positive slotBound (List.getElem?_set_self within) finishRoom
      (by simpa only [moveWindow.length, trapWindow.length, branchWindow.length, testWindow.length] using storage) bounded
  have branchAppend := testWindow.append (by simpa only [testBytes, List.length_cons, List.length_nil] using branchWindow)
  have trapAppend := branchAppend.append (by
    simpa only [List.length_append, testBytes, List.length_cons, List.length_nil,
      Control.Require.branchBytes_length, Nat.add_assoc] using trapWindow)
  have moveAppend := trapAppend.append (by
    simpa only [List.length_append, testBytes, List.length_cons, List.length_nil,
      Control.Require.branchBytes_length, Nat.add_assoc] using moveWindow)
  have guardWindow := moveAppend
  simp only [List.append_assoc] at guardWindow
  change Emission values start bytes _ at guardWindow
  have fullWindow := guardWindow.append (by simpa only [bytes_length] using finishWindow)
  have insideEffect := branchEffect.trans (trapEffect.trans
    ((moveEffect.weaken CellSet.subset_union_left).trans (finishEffect.weaken CellSet.subset_union_left)))
  have closed := CellEffect.closeLocal tested checked.locals.next (.signed .i32 (start + 2 : Nat))
    testedReady.wellFormed insideEffect
  have visible : CellEffect (Literal.writes output work) tested (restoreLocals tested completed) :=
    closed.narrow (by
      intro cell old changed
      rcases changed with existing | cursor
      · exact existing
      · exact False.elim ((Nat.ne_of_lt old) cursor))
  have total := (testEffect.weaken CellSet.subset_union_left).trans visible
  have outputBacking := finalReady.outputBacking
  have workBacking : (restoreLocals tested completed).cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (start + (bytes ++ Finish.bytes slot).length : Nat)))) } := by
    change completed.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (start + (bytes ++ Finish.bytes slot).length : Nat)))) }
    simpa only [List.set_set, List.length_append, bytes_length, Nat.add_assoc] using finalReady.workBacking
  exact ⟨restoreLocals tested completed, emitted,
    executesLetLocal (id := checked.locals.next) (type := i32) testRun
      (executesSequence branchRun (executesSequence trapRun (executesSequence moveRun finishRun))),
    ready.frame total outputBacking workBacking, fullWindow, total,
    testHeap.trans (HeapFrame.closeLocal tested checked.locals.next (.signed .i32 (start + 2 : Nat))
      (branchHeap.trans (trapHeap.trans (moveHeap.trans finishHeap))))⟩

end Lanius.X86.Lower.Expression.Raw.Guard
