import Lanius.Extraction.CompactOutput.Text.Loop
import Lanius.Extraction.CanonicalTokens.Ascii.Entry
import Lanius.Extraction.Allocation.Borrowed

namespace Lanius.Extraction.CompactOutput.Text

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- A negative length returns the error sentinel before exposing a string
pointer or touching either buffer. No string-storage premise is needed. -/
theorem rejectsLength (program : Program) (byteId : FunctionId) (length : Int)
    (lengthRead : before.local? 4 = some (.signed .i32 length)) (negative : length ≤ -1) :
    Executes program before (body byteId) (.returned (some (.signed .i32 (-1)))) before := by
  core_exec []

/-- The complete text helper on its supported domain, including string
borrowing, all local initialization, the loop, and its final return. -/
theorem executes (byte : CheckedByte program) (before : State) (text : String)
    (bytes : List UInt8) (earlier untouched : List Int) (capacity : Nat)
    (wellFormed : StateWellFormed before)
    (textRead : before.local? 3 = some (.string text))
    (lengthRead : before.local? 4 = some (.signed .i32 bytes.length))
    (outputRead : before.local? 0 = some (.slice i32 outputCell [] 0 (earlier.length + untouched.length)))
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionRead : before.local? 2 = some (.signed .i32 earlier.length))
    (outputContents : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values (earlier ++ untouched))) })
    (positionBound : earlier.length ≤ capacity)
    (capacityBound : capacity ≤ earlier.length + untouched.length)
    (capacityFit : capacity ≤ 2147483647)
    (lengthFit : bytes.length + 3 ≤ 2147483647)
    (padded : (Lanius.World.utf8Bytes text).length = ((bytes.length + 3) / 4) * 4)
    (prefixBytes : (Lanius.World.utf8Bytes text).take bytes.length = bytes) :
    ∃ after, Executes program.core before (body byte.source.function.id)
        (.returned (some (.signed .i32 (finalPosition bytes.length earlier.length capacity)))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (Input.copiedBuffer earlier untouched (emitted bytes earlier.length capacity)))) } ∧
      CellEffect (CellSet.singleton outputCell) before after ∧
      (Allocation.Registry before → Allocation.Registry after) ∧
      (∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh) := by
  obtain ⟨words, ready, initializer, encoded, wordContents, readyWF, readyLocals,
      oldCells, readyNext, readyWorld, readyDomain, readyValues, viewResources⟩ :=
    CanonicalTokens.Ascii.evaluates_wordView program.core before text bytes.length 3 4
      wellFormed textRead lengthRead lengthFit padded
  let view := Value.slice i32 before.nextCell [] 0 words.length
  let packed := ready.bindLocal 5 view
  let positioned := packed.bindLocal 6 (.signed .i32 earlier.length)
  let entered := positioned.bindLocal 7 (.signed .i32 0)
  have packedWF := bindLocal_preserves_well_formed ready 5 view readyWF
  have positionedWF := bindLocal_preserves_well_formed packed 6 (.signed .i32 earlier.length) packedWF
  have enteredWF := bindLocal_preserves_well_formed positioned 7 (.signed .i32 0) positionedWF
  have outputOld := StateWellFormed.cell_lt_next_of_entry wellFormed outputContents
  have outputReady := (oldCells outputCell outputOld).trans outputContents
  have outputBelow : outputCell < ready.nextCell := by rw [readyNext]; exact Nat.lt_succ_of_lt outputOld
  have wordBelow : before.nextCell < ready.nextCell := by rw [readyNext]; exact Nat.lt_succ_self _
  have entryReads (id : VarId) (notPacked : 5 ≠ id) (notPosition : 6 ≠ id) (notIndex : 7 ≠ id) :
      entered.local? id = before.local? id :=
    (bindLocal_preserves_other_local positionedWF notIndex).trans
      ((bindLocal_preserves_other_local packedWF notPosition).trans
        ((bindLocal_preserves_other_local readyWF notPacked).trans (readyValues id)))
  have entryCells (cell : CellId) (old : cell < ready.nextCell) :
      entered.cellEntry? cell = ready.cellEntry? cell := by
    have packedOld : cell < packed.nextCell := Nat.lt_succ_of_lt old
    have positionOld : cell < positioned.nextCell := Nat.lt_succ_of_lt packedOld
    exact (bindCell_preserves_old_cell positioned 7 (some (.signed .i32 0)) cell positionOld).trans
      ((bindCell_preserves_old_cell packed 6 (some (.signed .i32 earlier.length)) cell packedOld).trans
        (bindCell_preserves_old_cell ready 5 (some view) cell old))
  let memory : Memory := {
    inputCell := before.nextCell, outputCell, positionCell := packed.nextCell,
    indexCell := positioned.nextCell, words, storage := Lanius.World.utf8Bytes text,
    bytes, earlier, untouched, capacity, encoded, sourceBytes := prefixBytes,
    capacityBound, capacityFit,
    distinctLocals := Nat.ne_of_lt (Nat.lt_succ_self _),
    inputOutput := Ne.symm (Nat.ne_of_lt outputOld),
    inputPosition := Nat.ne_of_lt (Nat.lt_succ_of_lt wordBelow),
    inputIndex := Nat.ne_of_lt (Nat.lt_succ_of_lt (Nat.lt_succ_of_lt wordBelow)) }
  have inputEntered : entered.local? 5 = some view :=
    (bindLocal_preserves_other_local positionedWF (show 7 ≠ 5 by decide)).trans
      ((bindLocal_preserves_other_local packedWF (show 6 ≠ 5 by decide)).trans
        (bindLocal_finds_local ready 5 view readyWF))
  have outputEntered := (entryReads 0 (by decide) (by decide) (by decide)).trans outputRead
  have capacityEntered := (entryReads 1 (by decide) (by decide) (by decide)).trans capacityRead
  have lengthEntered := (entryReads 4 (by decide) (by decide) (by decide)).trans lengthRead
  have contentsEntered := (entryCells outputCell outputBelow).trans outputReady
  have invariant : Invariant memory [] entered := by
    refine ⟨enteredWF, inputEntered, (entryCells before.nextCell wordBelow).trans wordContents,
      outputEntered, ?_, capacityEntered, lengthEntered, ?_, ?_, ?_, ?_⟩
    · simpa [Memory.output, Input.copiedBuffer, memory] using contentsEntered
    · exact bindLocal_preserves_localPointsTo_of_ne positioned 7 6 (.signed .i32 0) _ _
        positionedWF (by decide) (bindLocal_owns_fresh packed 6 (.signed .i32 earlier.length) packedWF)
    · exact bindLocal_owns_fresh positioned 7 (.signed .i32 0) positionedWF
    · intro id member cell found changed
      have notPosition : 6 ≠ id := by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl | rfl | rfl <;> decide
      have notIndex : 7 ≠ id := by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl | rfl | rfl <;> decide
      have packedBinding : packed.cellId? id = some cell := by
        simpa [entered, positioned, State.cellId?, State.bindLocal, State.bindCell,
          notPosition, notIndex] using found
      have old := StateWellFormed.cell_lt_next_of_local_binding id cell packedWF packedBinding
      have notOutput : cell ≠ outputCell := by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl | rfl | rfl
        · exact local_cell_ne_of_distinct_value outputEntered contentsEntered (by intro same; cases same) found
        · exact local_cell_ne_of_distinct_value capacityEntered contentsEntered (by intro same; cases same) found
        · exact local_cell_ne_of_distinct_value lengthEntered contentsEntered (by intro same; cases same) found
        · exact local_cell_ne_of_distinct_value inputEntered contentsEntered (by intro same; cases (show Value.slice i32 before.nextCell [] 0 words.length = _ from same)) found
      exact changed.elim (fun changed => changed.elim notOutput (Nat.ne_of_lt old))
        (Nat.ne_of_lt (Nat.lt_succ_of_lt old))
    · simpa only [List.length_nil, Nat.add_zero] using positionBound
  obtain ⟨completed, finished, completedOutput, effect, loopHeap⟩ :=
    executesLoopAndReturn byte memory entered invariant
  have positionInitializer := local_evaluates program.core
    ((bindLocal_preserves_other_local (value := view) readyWF (show 5 ≠ 2 by decide)).trans ((readyValues 2).trans positionRead))
  have scopedRun := executesLetLocal (id := 5) (type := .slice i32) initializer
    (executesLetLocal (id := 6) (type := i32) positionInitializer
      (executesLetLocal (id := 7) (type := i32)
        (show Evaluates program.core positioned (number 0) (.signed .i32 0) positioned from evaluatesValue) finished))
  have guard : Evaluates program.core before (binary .lessEqual (read 4) negativeOne)
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core lengthRead)
      (negativeOne_evaluates program.core before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have closedIndex := CellEffect.closeLocal positioned 7 (.signed .i32 0) positionedWF effect
  have closedPosition := CellEffect.closeLocal packed 6 (.signed .i32 earlier.length) packedWF closedIndex
  have closed := CellEffect.closeLocal ready 5 view readyWF closedPosition
  have narrowed : CellEffect (CellSet.singleton outputCell) ready
      (restoreLocals ready (restoreLocals packed (restoreLocals positioned completed))) := by
    apply closed.narrow
    intro cell old changed
    rcases changed with changed | changed
    · rcases changed with changed | changed
      · exact changed
      · exact False.elim ((Nat.ne_of_lt (Nat.lt_succ_of_lt old)) changed)
    · exact False.elim ((Nat.ne_of_lt (Nat.lt_succ_of_lt (Nat.lt_succ_of_lt old))) changed)
  have viewEffect : CellEffect (CellSet.singleton outputCell) before ready :=
    ⟨readyWF, readyLocals, readyWorld, fun cell old _ => oldCells cell old,
      by rw [readyNext]; exact Nat.le_succ _, readyDomain⟩
  refine ⟨_, executesSequence (executesIfFalse guard (executesSkip _ _)) scopedRun,
    completedOutput, viewEffect.trans narrowed, ?_, ?_⟩
  · intro initialRegistry
    have readyRegistry := initialRegistry.borrowed viewResources readyWF
    have enteredRegistry := ((readyRegistry.bindLocal 5 view).bindLocal 6 (.signed .i32 earlier.length)).bindLocal 7 (.signed .i32 0)
    have emittedFit : earlier.length + (emitted bytes earlier.length capacity).length ≤ capacity := by
      simp only [emitted, List.length_take]; omega
    have completedRegistry := preservesRegistry memory [] (emitted bytes earlier.length capacity)
      enteredRegistry invariant emittedFit completedOutput effect loopHeap
    exact ((completedRegistry.restoreLocals positioned closedIndex.wellFormed).restoreLocals packed
      closedPosition.wellFormed).restoreLocals ready closed.wellFormed
  · obtain ⟨address, elements, views, _⟩ := viewResources.storage
    refine ⟨[{ address, root := before.nextCell, projections := [], length := (bytes.length + 3) / 4 }], ?_⟩
    change completed.i32ArrayViews = _
    rw [loopHeap.views]
    exact views

end Lanius.Extraction.CompactOutput.Text
