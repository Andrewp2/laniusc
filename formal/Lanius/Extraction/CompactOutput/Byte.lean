import Lanius.Extraction.CompactOutput.Source
import Lanius.Extraction.Source.Call
import Lanius.Automation.Execute
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

theorem local_evaluates (program : Program) {id : VarId} (found : before.local? id = some value) :
    Evaluates program before (read id) value before :=
  Lanius.Semantics.evaluatesLocal found

theorem negativeOne_evaluates (program : Program) (state : State) :
    Evaluates program state negativeOne (.signed .i32 (-1)) state := by
  core_eval []

def byteBad (capacity position value : Int) : Bool :=
  decide (position ≤ -1) || decide (capacity ≤ position) || decide (value ≤ -1) || decide (256 ≤ value)

theorem byte_guard (program : Program)
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionRead : before.local? 2 = some (.signed .i32 position))
    (valueRead : before.local? 3 = some (.signed .i32 value)) :
    Evaluates program before byteGuard (.boolean (byteBad capacity position value)) before := by
  core_eval [byteBad]

/-- One byte changes one cell element. Logical capacity may be smaller than
the backing allocation; both sides of the written element are preserved. -/
theorem byte_body (program : Program) (position capacity value : Nat)
    (wellFormed : StateWellFormed before) (room : position < capacity)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (byteBound : value < 256)
    (sliceRead : before.local? 0 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionRead : before.local? 2 = some (.signed .i32 position))
    (valueRead : before.local? 3 = some (.signed .i32 value))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Executes program before byteBody (.returned (some (.signed .i32 (position + 1 : Nat)))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (original.set position value))) } ∧
      CellEffect (CellSet.singleton outputCell) before after ∧ HeapFrame before after := by
  have guard := byte_guard program capacityRead positionRead valueRead
  have passed : byteBad capacity position value = false := by
    simp [byteBad]
    omega
  rw [passed] at guard
  obtain ⟨after, store, contents, effect, storeHeapFrame, _⟩ := evaluatesSliceStore program before before original 0
    (read 2) (read 3) outputCell position value wellFormed (by omega) sliceRead
    (local_evaluates program positionRead) (local_evaluates program valueRead)
    (CellEffect.refl wellFormed) backing
  have positionAfter := effect.preserves_local_of_distinct_value wellFormed positionRead backing
    (by intro same; cases same)
  have next := evaluatesNatI32Add (leftValue := position) (rightValue := 1) (local_evaluates program positionAfter)
    (show Evaluates program after (number 1) (.signed .i32 1) after from evaluatesValue) (by omega)
  exact ⟨after, by core_exec [], contents, effect, storeHeapFrame⟩

def byteValues (output : Value) (capacity position value : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 position, .signed .i32 value]

def byteBindings (output : Value) (capacity position value : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 4 => (byteValues output capacity position value).get index)

theorem CheckedByte.append (checked : CheckedByte program) (position capacity value : Nat)
    (room : position < capacity)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (byteBound : value < 256) :
    checked.Spec (byteValues (.slice i32 outputCell [] 0 original.length) capacity position value)
      (.signed .i32 (position + 1 : Nat))
      (requires := fun before => before.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values original)) })
      (ensures := fun _ after => after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (original.set position value))) })
      (writes := CellSet.singleton outputCell) := by
  apply checked.specCell rfl
  intro callee wellFormed locals backing
  exact byte_body program.core position capacity value wellFormed room capacityBound capacityFit byteBound
    (locals 0 (by simp [byteValues])) (locals 1 (by simp [byteValues]))
    (locals 2 (by simp [byteValues])) (locals 3 (by simp [byteValues])) backing

/-- Invalid positions (including the sticky -1 sentinel), capacity exhaustion,
and invalid byte values return -1 before any buffer access or write. -/
theorem CheckedByte.reject (checked : CheckedByte program) (output : Value) (capacity position value : Int)
    (bad : byteBad capacity position value = true) :
    checked.Spec (byteValues output capacity position value) (.signed .i32 (-1)) := by
  apply checked.specPure rfl
  intro callee locals
  core_exec [byteValues, byteBad]

end Lanius.Extraction.CompactOutput
