import Lanius.X86.Lower.Arguments
import Lanius.X86.Encode.Direct
import Lanius.X86.Buffer.Fixed

namespace Lanius.X86.Lower.Parameter

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Source.Lower Lanius.X86.Buffer

def moveConfig (position : Fin 6) : Encode.Config :=
  Encode.Direct.config .move .w32 ⟨0, by decide⟩ (argumentRegister position)

def code (position : Fin 6) : List Nat := (moveConfig position).bytes ++ [195]

def codeSize (position : Fin 6) : Nat := if 4 ≤ position.val then 4 else 3

theorem code_encoding (position : Fin 6) :
    (code position).map UInt8.ofNat = bytes position ∧
      (moveConfig position).size + 1 = codeSize position ∧
      (code position).length = codeSize position := by
  decide +revert

theorem nonnegative_guard (program : Program) (id : VarId) (value : Nat)
    (found : before.local? id = some (.signed .i32 value)) :
    Executes program before (rejectNegative id) .next before := by
  have guard : Evaluates program before (.binary .less (read id) (number 0)) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found)
      (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  exact executesIfFalse guard (executesSkip _ _)

/-- Execute the actual MOV call, bind its returned cursor, execute the RET
call, and close that local scope. Neither helper execution nor byte acceptance
is assumed: both follow from their source-linked implementation theorems. -/
theorem emit_return (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (outputRead : before.local? 2 = some (.slice i32 cell [] 0 values.length))
    (capacityRead : before.local? 3 = some (.signed .i32 capacity))
    (cursorRead : before.local? 4 = some (.signed .i32 start))
    (sourceRead : before.local? 6 = some (.signed .i32 (argumentRegister position).val))
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + codeSize position ≤ capacity) (storage : capacity ≤ values.length)
    (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes emitters.pack.program.core before
        (moveTail (emitters.registerWrappers .move).source.function.id emitters.returnNear.source.function.id checked.resultRegister.id)
        (.returned (some (.signed .i32 (start + codeSize position : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (writtenBytes values start (code position)))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have size := (code_encoding position).2.1
  have resultConstant := checked.resultRegister.evaluates (before := before)
  rw [checked.resultZero] at resultConstant
  have args : ArgumentsEvaluateTo emitters.pack.program.core before
      [read 2, read 3, read 4, number 32, .constant checked.resultRegister.id, read 6]
      (Encode.Direct.inputs .move (.slice i32 cell [] 0 values.length) capacity start 32 0
        (argumentRegister position).val) before :=
    .cons (local_evaluates _ outputRead) (.cons (local_evaluates _ capacityRead)
      (.cons (local_evaluates _ cursorRead) (.cons ⟨1, rfl⟩ (.cons resultConstant
        (.cons (local_evaluates _ sourceRead) (.nil _ _))))))
  obtain ⟨moved, moveRun, movedBacking, moveEffect, moveHeap⟩ :=
    (Encode.Direct.succeeds (emitters.registerWrappers .move) .w32 ⟨0, by decide⟩
      (argumentRegister position) capacity start (by change start + (moveConfig position).size ≤ capacity; omega)
      storage bounded).call wellFormed args backing
  let next := start + (moveConfig position).size
  let scope := moved.bindLocal 8 (.signed .i32 next)
  have scopeWF := bindLocal_preserves_well_formed moved 8 (.signed .i32 next) moveEffect.wellFormed
  have movedOutput := moveEffect.preserves_local_of_distinct_value wellFormed outputRead backing (by intro same; cases same)
  have movedCapacity := moveEffect.preserves_local_of_distinct_value wellFormed capacityRead backing (by intro same; cases same)
  have scopeOutput := (bindLocal_preserves_other_local (boundId := 8) (queriedId := 2)
    (value := .signed .i32 next) moveEffect.wellFormed (by decide)).trans movedOutput
  have scopeCapacity := (bindLocal_preserves_other_local (boundId := 8) (queriedId := 3)
    (value := .signed .i32 next) moveEffect.wellFormed (by decide)).trans movedCapacity
  have scopeNext := bindLocal_finds_local moved 8 (.signed .i32 next) moveEffect.wellFormed
  have scopeBacking := ((bindLocal_effect moved 8 (.signed .i32 next)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry moveEffect.wellFormed movedBacking) (by simp [CellSet.empty])).trans movedBacking
  have retArgs : ArgumentsEvaluateTo emitters.pack.program.core scope [read 2, read 3, read 8]
      (fixedValues (.slice i32 cell [] 0 (writtenBytes values start (moveConfig position).bytes).length) capacity next) scope := by
    simpa only [writtenBytes_length, fixedValues, Source.read, scope] using ArgumentsEvaluateTo.cons (local_evaluates _ scopeOutput)
      (.cons (local_evaluates _ scopeCapacity) (.cons (local_evaluates _ scopeNext) (.nil _ _)))
  obtain ⟨completed, retRun, contents, retEffect, retHeap⟩ := fixed_success emitters.returnNear capacity next scopeWF
    (by simp only [List.length_singleton]; dsimp [next]; omega) (by simpa only [writtenBytes_length] using storage)
    bounded scopeBacking retArgs
  have tail : Executes emitters.pack.program.core scope (returnTail emitters.returnNear.source.function.id)
      (.returned (some (.signed .i32 (start + codeSize position : Nat)))) completed := by
    have result : next + [195].length = start + codeSize position := by change start + (moveConfig position).size + 1 = _; omega
    rw [result] at retRun
    exact executesSequence (nonnegative_guard _ 8 next scopeNext) (executesSequenceReturned (executesReturnValue retRun))
  refine ⟨restoreLocals moved completed, executesLetLocal moveRun tail, ?_,
    moveEffect.trans (CellEffect.closeLocal moved 8 (.signed .i32 next) moveEffect.wellFormed retEffect),
    moveHeap.trans (HeapFrame.closeLocal moved 8 (.signed .i32 next) retHeap)⟩
  have length : (moveConfig position).bytes.length = (moveConfig position).size := Encoding.bytes_size _ _ _ _
  change completed.cellEntry? cell = _
  rw [code, writtenBytes_append, length]
  exact contents

theorem reserve_return (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (outputRead : before.local? 2 = some (.slice i32 cell [] 0 values.length))
    (capacityRead : before.local? 3 = some (.signed .i32 capacity))
    (cursorRead : before.local? 4 = some (.signed .i32 start))
    (sourceRead : before.local? 6 = some (.signed .i32 (argumentRegister position).val))
    (sizeRead : before.local? 7 = some (.signed .i32 (codeSize position)))
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + codeSize position ≤ capacity) (storage : capacity ≤ values.length)
    (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes emitters.pack.program.core before
        (reserveTail emitters.fits.source.function.id (emitters.registerWrappers .move).source.function.id
          emitters.returnNear.source.function.id checked.resultRegister.id)
        (.returned (some (.signed .i32 (start + codeSize position : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (writtenBytes values start (code position)))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo emitters.pack.program.core before [read 3, read 4, read 7]
      (fitsValues capacity start (codeSize position)) before :=
    .cons (local_evaluates _ capacityRead) (.cons (local_evaluates _ cursorRead)
      (.cons (local_evaluates _ sizeRead) (.nil _ _)))
  obtain ⟨guarded, fitRun, fitEffect, fitHeap⟩ := fits_call emitters.fits capacity start (codeSize position)
    wellFormed (Int.ofNat_le.mpr bounded) args
  have good : reserved capacity start (codeSize position) = true := by simp only [reserved, decide_eq_true_eq]; omega
  rw [good] at fitRun
  have guard := evaluatesUnary fitRun (show evalUnaryValue emitters.pack.program.core.target .logicalNot
    (.boolean true) = .ok (.boolean false) from rfl)
  obtain ⟨after, run, contents, effect, heap⟩ := emit_return checked position capacity start fitEffect.wellFormed
    (fitEffect.empty_preserves_local wellFormed outputRead) (fitEffect.empty_preserves_local wellFormed capacityRead)
    (fitEffect.empty_preserves_local wellFormed cursorRead) (fitEffect.empty_preserves_local wellFormed sourceRead)
    (fitEffect.empty_preserves_entry wellFormed backing) room storage bounded
  exact ⟨after, executesSequence (executesIfFalse guard (executesSkip _ _)) run, contents,
    (fitEffect.weaken CellSet.empty_subset).trans effect, fitHeap.trans heap⟩

end Lanius.X86.Lower.Parameter
