import Lanius.X86.Lower.Expression.Raw.State
import Lanius.X86.Source.Expression.Raw
import Lanius.X86.Encode.Guarded
import Lanius.X86.Encode.Direct
import Lanius.X86.Control.Require

namespace Lanius.X86.Lower.Expression.Raw.Guard

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Source Lanius.X86.Buffer Lanius.X86.Control

variable {emitters : CheckedBuffer encoded sources}
  {literal : Source.Expression.Literal.Checked emitters}

def testChoice : Encode.Guarded.Choice .binary := ⟨133, by decide⟩
def testBytes : List UInt8 := [133, 192]
def bytes : List UInt8 := testBytes ++ Control.Require.bytes 13 ++ [137, 192]

/-- Execute the real binary emitter call selected by the raw constructor.
This proves TEST32 emission, not an assumed successful helper result. -/
theorem test (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (capacity start : Nat)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (cursor : workspace[1]? = some (start : Int))
    (room : start + 2 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after,
      Evaluates emitters.pack.program.core before
        (.call checked.helpers.calls.binary (Source.Expression.Raw.testArguments literal checked.constants))
        (.signed .i32 (start + 2 : Nat)) after ∧
      Literal.Ready after bindings frontier input output work transport
        (writtenBytes values start [133, 192]) workspace ∧
      Emission values start testBytes (writtenBytes values start [133, 192]) ∧
      CellEffect (CellSet.singleton output) before after ∧ HeapFrame before after := by
  have current := ready.field literal.constants.code 1 literal.constants.values.2.2.1 workLocal cursor
  have operation := checked.constants.test.evaluates (before := before)
  rw [checked.constants.values.2.1] at operation
  have rax := literal.constants.rax.evaluates (before := before)
  rw [literal.constants.values.2.2.2.2.2.1] at rax
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core before
      (Source.Expression.Raw.testArguments literal checked.constants)
      (Encode.Guarded.inputs .binary (.slice i32 output [] 0 values.length) capacity start 32 133 0 0) before :=
    .cons (local_evaluates _ outputLocal) (.cons (local_evaluates _ capacityLocal)
      (.cons current (.cons ⟨1, rfl⟩ (.cons operation (.cons rax (.cons rax (.nil _ _)))))))
  obtain ⟨after, run, backing, effect, heap⟩ := (Encode.Guarded.succeeds
    checked.helpers.binary testChoice .w32 0 0 capacity start room storage bounded).call
    ready.wellFormed arguments ready.outputBacking
  have window := (Encode.Guarded.config .binary testChoice .w32 0 0).emission (values := values) (Nat.le_trans room storage)
  refine ⟨after, run, ready.frame (effect.weaken CellSet.subset_union_left) backing
    (effect.preserves_entry ready.wellFormed ready.workBacking (Ne.symm ready.outputWork)),
    ⟨window.length, window.bytes, window.frame⟩, effect, heap⟩

/-- Emit the actual JGE and assign its returned cursor to the owned local.
The signed-add target is proved in range and skips exactly two trap bytes. -/
theorem branch (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (capacity cursor : Nat)
    (owned : (Assertion.localPointsTo checked.locals.next temporary
      (some (.signed .i32 cursor))).holds before)
    (fresh : frontier ≤ temporary)
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (room : cursor + 8 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after,
      Executes emitters.pack.program.core before
        (Source.Expression.Raw.setNext checked.locals
          (.call checked.helpers.calls.branch (Source.Expression.Raw.branchArguments checked.constants checked.locals))) .next after ∧
      Literal.Ready after bindings frontier input output work transport
        (Relative.emittedValues (.branch 13) values cursor (cursor + 8)) workspace ∧
      (Assertion.localPointsTo checked.locals.next temporary (some (.signed .i32 (cursor + 6 : Nat)))).holds after ∧
      Emission values cursor (Control.Require.branchBytes 13)
        (Relative.emittedValues (.branch 13) values cursor (cursor + 8)) ∧
      CellEffect (cursorWrites output work temporary) before after ∧ HeapFrame before after := by
  have position := local_evaluates emitters.pack.program.core
    (Assertion.localPointsTo_local checked.locals.next temporary _ before owned)
  have condition := checked.constants.greaterEqual.evaluates (before := before)
  rw [checked.constants.values.2.2] at condition
  have target := evaluatesNatI32Add position
    (show Evaluates emitters.pack.program.core before (number 8) (.signed .i32 (8 : Nat)) before from ⟨1, rfl⟩)
    (by omega)
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core before
      (Source.Expression.Raw.branchArguments checked.constants checked.locals)
      (branchValues (.slice i32 output [] 0 values.length) capacity cursor 13 (cursor + 8 : Nat)) before :=
    .cons (local_evaluates _ outputLocal) (.cons (local_evaluates _ capacityLocal)
      (.cons position (.cons condition (.cons target (.nil _ _)))))
  obtain ⟨middle, run, backing, window, effect, heap⟩ := branch_success emitters.branch 13 capacity cursor
    (cursor + 8) ready.wellFormed (by omega) storage bounded (by omega) ready.outputBacking arguments
  obtain ⟨after, assigned, nextReady, updated, total, updateHeap⟩ := update_cursor ready owned fresh run effect backing
  have emitted : Emission values cursor (Control.Require.branchBytes 13)
      (Relative.emittedValues (.branch 13) values cursor (cursor + 8)) := by
    refine ⟨window.length, ?_, window.frame⟩
    have displacement : relativeDisplacement (cursor + 6) (cursor + 8) = 2 := by
      simp only [relativeDisplacement]; omega
    have exactBytes := Relative.emittedValues_bytes (.branch 13)
      (show cursor + 6 ≤ values.length from by omega) (target := cursor + 8)
    change _ = (Transfer.branch 13).header.map UInt8.ofNat ++
      i32Bytes (relativeDisplacement (cursor + 6) (cursor + 8)) at exactBytes
    rw [displacement] at exactBytes
    exact exactBytes
  exact ⟨after, executesExpression assigned, nextReady, updated, emitted, total, heap.trans updateHeap⟩

/-- Emit UD2 and retain its actual returned cursor in the same fresh local. -/
theorem trap (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (capacity cursor : Nat)
    (owned : (Assertion.localPointsTo checked.locals.next temporary
      (some (.signed .i32 cursor))).holds before)
    (fresh : frontier ≤ temporary)
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (room : cursor + 2 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after,
      Executes emitters.pack.program.core before
        (Source.Expression.Raw.setNext checked.locals
          (.call checked.helpers.calls.trap [read 3, read 4, read checked.locals.next])) .next after ∧
      Literal.Ready after bindings frontier input output work transport
        (writtenBytes values cursor [15, 11]) workspace ∧
      (Assertion.localPointsTo checked.locals.next temporary (some (.signed .i32 (cursor + 2 : Nat)))).holds after ∧
      Emission values cursor [15, 11] (writtenBytes values cursor [15, 11]) ∧
      CellEffect (cursorWrites output work temporary) before after ∧ HeapFrame before after := by
  have position := local_evaluates emitters.pack.program.core
    (Assertion.localPointsTo_local checked.locals.next temporary _ before owned)
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core before
      [read 3, read 4, read checked.locals.next]
      (fixedValues (.slice i32 output [] 0 values.length) capacity cursor) before :=
    .cons (local_evaluates _ outputLocal) (.cons (local_evaluates _ capacityLocal) (.cons position (.nil _ _)))
  obtain ⟨middle, run, backing, effect, heap⟩ := fixed_success emitters.trap capacity cursor
    ready.wellFormed room storage bounded ready.outputBacking arguments
  obtain ⟨after, assigned, nextReady, updated, total, updateHeap⟩ := update_cursor ready owned fresh run effect backing
  exact ⟨after, executesExpression assigned, nextReady, updated,
    ⟨writtenBytes_length, writtenBytes_byteSlice (by change cursor + 2 ≤ values.length; omega),
      fun _ outside => writtenBytes_frame outside⟩,
    total, heap.trans updateHeap⟩

/-- Emit MOV EAX,EAX (zeroing the upper half) and update CODE through the real
workspace assignment. The guard cursor local is only read by this phase. -/
theorem move (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (capacity cursor : Nat)
    (position : before.local? checked.locals.next = some (.signed .i32 cursor))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (within : 1 < workspace.length)
    (room : cursor + 2 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after,
      Executes emitters.pack.program.core before
        (Source.Expression.Literal.assign literal.constants.code.id
          (.call checked.helpers.calls.move (Source.Expression.Raw.moveArguments literal checked.locals))) .next after ∧
      Literal.Ready after bindings frontier input output work transport
        (writtenBytes values cursor [137, 192]) (workspace.set 1 (cursor + 2 : Nat)) ∧
      Emission values cursor [137, 192] (writtenBytes values cursor [137, 192]) ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have rax := literal.constants.rax.evaluates (before := before)
  rw [literal.constants.values.2.2.2.2.2.1] at rax
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core before
      (Source.Expression.Raw.moveArguments literal checked.locals)
      (Encode.Direct.inputs .move (.slice i32 output [] 0 values.length) capacity cursor 32 0 0) before :=
    .cons (local_evaluates _ outputLocal) (.cons (local_evaluates _ capacityLocal)
      (.cons (local_evaluates _ position) (.cons ⟨1, rfl⟩ (.cons rax (.cons rax (.nil _ _))))))
  obtain ⟨middle, run, backing, effect, heap⟩ := (Encode.Direct.succeeds
    (emitters.registerWrappers .move) .w32 0 0 capacity cursor room storage bounded).call
    ready.wellFormed arguments ready.outputBacking
  have window := (Encode.Direct.config .move .w32 0 0).emission (values := values) (Nat.le_trans room storage)
  have code := literal.constants.code.evaluates (before := before)
  rw [literal.constants.values.2.2.1] at code
  obtain ⟨after, stored, workBacking, total, storeHeap, storeEffect⟩ := evaluatesFramedSliceStore
    emitters.pack.program.core before middle workspace 2 (.constant literal.constants.code.id)
    (.call checked.helpers.calls.move (Source.Expression.Raw.moveArguments literal checked.locals))
    work 1 (cursor + 2 : Nat) ready.wellFormed within workLocal code run effect
    (Ne.symm ready.outputWork) ready.workBacking
  have outputBacking := storeEffect.preserves_entry effect.wellFormed backing ready.outputWork
  exact ⟨after, executesExpression stored, ready.frame total outputBacking workBacking,
    ⟨window.length, window.bytes, window.frame⟩, total, heap.trans storeHeap⟩

end Lanius.X86.Lower.Expression.Raw.Guard
