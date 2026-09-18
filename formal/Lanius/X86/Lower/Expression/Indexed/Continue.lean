import Lanius.X86.Lower.Expression.Indexed.Prepare
import Lanius.X86.Lower.Index.Preservation

namespace Lanius.X86.Lower.Expression.Indexed

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The source-execution part of the recursive expression induction hypothesis.
It concerns exactly the recursive call, not the surrounding indexed helper.
The child's machine simulation is a separate obligation; this record does not
assert that arbitrary emitted child bytes preserve Core semantics. -/
structure RecursiveCall (checked : Source.Expression.Indexed.Checked emitters)
    (signed : Bool) (before after : State) (output work cursor oldWorkLength : Nat)
    (original emitted workspace : List Int) (code : List UInt8) : Prop where
  run : Evaluates emitters.pack.program.core before
    (.call checked.expression.function.id Source.Expression.Indexed.recurseArguments)
    (.signed .i32 (Index.Emission.kindValue signed)) after
  outputBacking : after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) }
  workBacking : after.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) }
  workspaceLength : workspace.length = oldWorkLength
  current : workspace[1]? = some ((cursor + code.length : Nat) : Int)
  window : Emission original cursor code emitted
  effect : CellEffect (writes output work) before after
  heap : HeapFrame before after

/-- Finish the actual indexed-expression source body after its descriptor
capture. Recursion is assumed only through `RecursiveCall`; argument reads,
the checked-address call, its boolean result, lexical-scope restoration, and
the complete emitted window are proved here. The returned address refinement
still requires the recursive machine simulation to preserve the saved
descriptor and establish the index representation. -/
theorem continues (checked : Source.Expression.Indexed.Checked emitters)
    (signed : Bool) (capacity : Nat)
    (ready : Prepared before inputs frontier output work top peak start values workspace preparedValues)
    (recursive : RecursiveCall checked signed before recursed output work
      (start + (saveBytes top).length) workspace.length preparedValues
      recursiveValues recursiveWorkspace recursiveBytes)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (distinct : output ≠ work) (slotBound : top ≤ 1048576)
    (room : start + (saveBytes top).length + recursiveBytes.length +
      (Machine.Index.bytes signed top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted,
      Executes emitters.pack.program.core before
        (Source.Expression.Indexed.continuation checked.expression.function.id checked.index.internal.source.function.id)
        (.returned (some (.boolean true))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (recursiveWorkspace.set 1 (start + (saveBytes top).length + recursiveBytes.length +
          (Machine.Index.bytes signed top).length : Nat)))) } ∧
      Emission values start (saveBytes top ++ recursiveBytes ++ Machine.Index.bytes signed top) emitted ∧
      Index.Emission.Refines signed top (byteSlice emitted
        (start + (saveBytes top).length + recursiveBytes.length) (Machine.Index.bytes signed top).length) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have untouched (id : Nat) (value : Value) (found : before.local? id = some value)
      (notOutput : value ≠ .array (signedI32Values preparedValues))
      (notWork : value ≠ .array (signedI32Values
        (workspaceAfter workspace top peak (start + (saveBytes top).length)))) :
      ∀ cell, before.cellId? id = some cell → ¬ writes output work cell := by
    intro cell binding changed
    rcases changed with out | work
    · exact local_cell_ne_of_distinct_value found ready.outputBacking notOutput binding out
    · exact local_cell_ne_of_distinct_value found ready.workBacking notWork binding work
  have kept (id : Nat) (value : Value) (found : before.local? id = some value)
      (notOutput : value ≠ .array (signedI32Values preparedValues))
      (notWork : value ≠ .array (signedI32Values
        (workspaceAfter workspace top peak (start + (saveBytes top).length)))) :
      recursed.local? id = some value :=
    recursive.effect.preserves_local ready.wellFormed found (untouched id value found notOutput notWork)
  have recursedWork := kept 2 _ workLocal (by intro same; cases same) (by intro same; cases same)
  have recursedOutput := kept 3 _ outputLocal (by intro same; cases same) (by intro same; cases same)
  have recursedCapacity := kept 4 _ capacityLocal (by intro same; cases same) (by intro same; cases same)
  have recursedSaved := kept 9 _ ready.saved (by intro same; cases same) (by intro same; cases same)
  let entered := recursed.bindLocal 10 (.signed .i32 (Index.Emission.kindValue signed))
  have enteredWF := bindLocal_preserves_well_formed recursed 10
    (.signed .i32 (Index.Emission.kindValue signed)) recursive.effect.wellFormed
  have enteredOutput := ((bindLocal_effect recursed 10 (.signed .i32 (Index.Emission.kindValue signed))).oldCells output
    (StateWellFormed.cell_lt_next_of_entry recursive.effect.wellFormed recursive.outputBacking)
    (by simp [CellSet.empty])).trans recursive.outputBacking
  have enteredWork := ((bindLocal_effect recursed 10 (.signed .i32 (Index.Emission.kindValue signed))).oldCells work
    (StateWellFormed.cell_lt_next_of_entry recursive.effect.wellFormed recursive.workBacking)
    (by simp [CellSet.empty])).trans recursive.workBacking
  have enteredWorkLocal := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 2)
    (value := .signed .i32 (Index.Emission.kindValue signed)) recursive.effect.wellFormed (by decide)).trans recursedWork
  have enteredOutputLocal := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 3)
    (value := .signed .i32 (Index.Emission.kindValue signed)) recursive.effect.wellFormed (by decide)).trans recursedOutput
  have enteredCapacity := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 4)
    (value := .signed .i32 (Index.Emission.kindValue signed)) recursive.effect.wellFormed (by decide)).trans recursedCapacity
  have enteredSaved := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 9)
    (value := .signed .i32 (Index.Emission.kindValue signed)) recursive.effect.wellFormed (by decide)).trans recursedSaved
  have enteredKind := bindLocal_finds_local recursed 10 (.signed .i32 (Index.Emission.kindValue signed)) recursive.effect.wellFormed
  have outputLength : recursiveValues.length = values.length := recursive.window.length.trans ready.window.length
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core entered
      [Source.read 3, Source.read 4, Source.read 2, Source.read 9, Source.read 10]
      (Index.Emission.inputValues output work recursiveValues.length recursiveWorkspace.length capacity top
        (Index.Emission.kindValue signed)) entered := by
    rw [outputLength, recursive.workspaceLength]
    exact .cons (local_evaluates _ enteredOutputLocal) (.cons (local_evaluates _ enteredCapacity)
      (.cons (local_evaluates _ enteredWorkLocal) (.cons (local_evaluates _ enteredSaved)
        (.cons (local_evaluates _ enteredKind) (.nil _ _)))))
  obtain ⟨completed, emitted, addressRun, finalOutput, finalWork, addressWindow, refinement, effect, heap⟩ :=
    Index.Emission.compiles checked.index signed capacity top
      (start + (saveBytes top).length + recursiveBytes.length) enteredWF distinct enteredOutput enteredWork
      recursive.current slotBound room (by simpa only [outputLength] using storage) bounded arguments
  have result : Evaluates emitters.pack.program.core entered
      (.binary .greaterEqual (.call checked.index.internal.source.function.id
        [Source.read 3, Source.read 4, Source.read 2, Source.read 9, Source.read 10]) (Source.number 0))
      (.boolean true) completed := by
    apply evaluatesEagerBinary (by decide) (by decide) addressRun
      (show Evaluates emitters.pack.program.core completed (Source.number 0) (.signed .i32 0) completed from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have allBytes := (ready.window.append recursive.window).append
    (by simpa only [List.length_append, Nat.add_assoc] using addressWindow)
  exact ⟨restoreLocals recursed completed, emitted,
    executesLetLocal recursive.run (executesSequenceReturned (executesReturnValue result)),
    finalOutput, finalWork, allBytes, refinement,
    recursive.effect.trans (CellEffect.closeLocal recursed 10 (.signed .i32 (Index.Emission.kindValue signed))
      recursive.effect.wellFormed effect),
    recursive.heap.trans (HeapFrame.closeLocal recursed 10 (.signed .i32 (Index.Emission.kindValue signed)) heap)⟩

end Lanius.X86.Lower.Expression.Indexed
