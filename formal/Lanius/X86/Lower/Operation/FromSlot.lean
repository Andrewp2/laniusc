import Lanius.X86.Source.Operation.FromSlot
import Lanius.X86.Encode.Direct.Contract
import Lanius.X86.Encode.Memory.Contract
import Lanius.X86.Lower.Operation.Arithmetic.Contract
import Lanius.X86.Frame.Contract
import Lanius.Extraction.Source.Expression
import Lanius.Automation.Contract
import Lanius.X86.Buffer.Emission
import Lanius.X86.Lower.Expression.Binary.Native

namespace Lanius.X86.Lower.Operation.FromSlot

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Buffer Lanius.X86.Source

def inputs (output : Value) (capacity start slot operation : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 slot, .signed .i32 operation]

def moved (capacity : Nat) (before : Writer.Result) : Writer.Result :=
  before.append capacity 2 (fun values start => writtenBytes values start (Encode.Direct.config .move .w32 1 0).bytes)
def loaded (slot capacity : Nat) (before : Writer.Result) : Writer.Result :=
  (moved capacity before).append capacity 6 (Encode.Memory.moveConfig .w32 true 0 5 (Frame.displacement slot)).written
def result (operation : Machine.Alu) (slot capacity : Nat) (before : Writer.Result) : Writer.Result :=
  (loaded slot capacity before).append capacity 2 (fun values start => writtenBytes values start (Encode.Arithmetic.config operation 0 1).bytes)

@[simp] theorem moved_length : (moved capacity before).values.length = before.values.length :=
  Writer.Result.append_length before (fun _ _ => writtenBytes_length)
@[simp] theorem loaded_length : (loaded slot capacity before).values.length = before.values.length :=
  (Writer.Result.append_length _ (fun _ _ => Encode.Memory.Config.written_length _ _)).trans moved_length

theorem result_success (operation : Machine.Alu) (slot capacity start : Nat)
    (values : List Int) (room : start + 10 ≤ capacity) :
    result operation slot capacity ⟨start, values⟩ =
      ⟨(start + 10 : Nat), writtenBytes
        ((Encode.Memory.moveConfig .w32 true 0 5 (Frame.displacement slot)).written
          (writtenBytes values start (Encode.Direct.config .move .w32 1 0).bytes) (start + 2))
        (start + 8) (Encode.Arithmetic.config operation 0 1).bytes⟩ := by
  unfold result loaded moved
  rw [Writer.Result.append_success (⟨start, values⟩ : Writer.Result) capacity 2 start _ rfl (by omega),
    Writer.Result.append_success _ capacity 6 (start + 2) _ rfl (by omega),
    Writer.Result.append_success _ capacity 2 (start + 2 + 6) _ rfl (by omega)]

/-- One source composition covers full emission and every partial-buffer
failure. The three atomic contracts supply their actual cursor and storage. -/
theorem write {parent : Source.Operation.Checked emitters} (checked : Source.Operation.FromSlot.Checked parent)
    (arithmetic : Source.Operation.Arithmetic.Checked parent) (operation : Machine.Alu) (slot capacity : Nat) (before : Writer.Result)
    (slotBound : slot ≤ 1048576) (storage : capacity ≤ before.values.length) (bounded : capacity ≤ 2147483647) :
    Writer.Spec emitters.pack.program.core checked.internal.source.function.id
      (inputs (.slice i32 cell [] 0 before.values.length) capacity before.cursor slot (Transport.binaryTag (Encode.Arithmetic.coreOp operation)))
      cell before (result operation slot capacity before) := by
  let env := inputs (.slice i32 cell [] 0 before.values.length) capacity before.cursor slot (Transport.binaryTag (Encode.Arithmetic.coreOp operation))
  have rax (state : State) := parent.rax.evaluates (before := state)
  have rcx (state : State) := parent.rcx.evaluates (before := state)
  have rbp (state : State) := checked.rbp.evaluates (before := state)
  simp only [parent.values.2.1] at rax
  simp only [parent.values.2.2] at rcx
  simp only [checked.base] at rbp
  have moving := Encode.Direct.attempt (cell := cell) (emitters.registerWrappers .move) .w32 1 0 capacity before storage bounded
  have displacement := (Frame.displacement_spec checked.offset slot slotBound).frameStorage
    (Storage.entry cell (some (.array (signedI32Values (moved capacity before).values))))
  have loading := Encode.Memory.attempt (cell := cell) checked.load .w32 0 5 (Frame.displacement slot) capacity
    (moved capacity before) (by simpa using storage) bounded
  have binary := Arithmetic.attempt (cell := cell) arithmetic operation capacity (loaded slot capacity before) (by simpa using storage) bounded
  simp only [moved_length, loaded_length] at loading binary
  simp only [Writer.Spec, Writer.Stored, State.cellEntry?] at moving loading binary
  unfold Writer.Spec Writer.Stored State.cellEntry?
  refine checked.internal.specExpressionCell (values := env) (cell := cell)
    (original := .array (signedI32Values before.values))
    (written := .array (signedI32Values (result operation slot capacity before).values))
    (result := .signed .i32 (result operation slot capacity before).cursor) rfl ?_ ?_
  · apply ExprSpec.call (callee := binary)
    · core_spec [env, inputs, Encode.Direct.inputs, Encode.Memory.moveValues, Arithmetic.inputs, Encode.Boolean.inputs]
    · exact fun _ held => held
  · intro value found
    cases value <;> simp_all [env, inputs]

def Output (target : Target) (operation : Machine.Alu) (slot : Nat)
    (cell : CellId) (values : List Int) (start : Nat) (cells : List Cell) : Prop :=
  ∃ emitted, cells.find? (fun entry => entry.id == cell) = some ⟨cell, some (.array (signedI32Values emitted))⟩ ∧
    Emission values start (Expression.Binary.finishBytes operation slot) emitted ∧
    ∀ tail before auxiliary, Machine.Block 3 (byteSlice emitted start 10) tail before
      (fun after => Expression.Binary.Finished target operation slot before after auxiliary)

theorem result_emission (operation : Machine.Alu) (slot capacity start : Nat)
    (values : List Int) (room : start + 10 ≤ capacity) (storage : capacity ≤ values.length) :
    Emission values start (Expression.Binary.finishBytes operation slot)
      (result operation slot capacity ⟨start, values⟩).values := by
  have moveRoom : start + 2 ≤ values.length := by omega
  have loadRoom : start + 2 + 6 ≤ values.length := by omega
  have arithmeticRoom : start + 8 + 2 ≤ values.length := by omega
  have first := writtenBytes_emission (values := values) (start := start)
    (bytes := (Encode.Direct.config .move .w32 1 0).bytes) (by
      have h : (Encode.Direct.config .move .w32 1 0).bytes.length = 2 := by decide
      simpa only [h] using moveRoom)
  let config := Encode.Memory.moveConfig .w32 true 0 5 (Frame.displacement slot)
  have configSize : config.size = 6 := rfl
  have second : Emission (writtenBytes values start (Encode.Direct.config .move .w32 1 0).bytes)
      (start + 2) config.bytes (config.written (writtenBytes values start
        (Encode.Direct.config .move .w32 1 0).bytes) (start + 2)) :=
    ⟨config.written_length _, config.emission (by
        simpa only [configSize, writtenBytes_length] using loadRoom),
      (by intro index outside
          have blen : config.bytes.length = config.size := by
            rw [(Encode.Memory.move_encoding .w32 true 0 5 (Frame.displacement slot)).1]
            exact (Encode.Memory.move_encoding .w32 true 0 5 (Frame.displacement slot)).2.symm
          rw [blen, configSize] at outside
          exact config.frame outside)⟩
  have third := writtenBytes_emission
    (values := config.written (writtenBytes values start (Encode.Direct.config .move .w32 1 0).bytes) (start + 2)) (start := start + 8)
    (bytes := (Encode.Arithmetic.config operation 0 1).bytes) (by
      have h : (Encode.Arithmetic.config operation 0 1).bytes.length = 2 := by cases operation <;> rfl
      simpa only [Encode.Memory.Config.written_length, writtenBytes_length, h] using arithmeticRoom)
  rw [result_success operation slot capacity start values room]
  simpa only [config,
    (Encode.Memory.move_encoding .w32 true 0 5 (Frame.displacement slot)).1,
    Expression.Binary.finishBytes, Expression.Binary.prepare, Machine.ReadOnly.code,
    Expression.Binary.arithmeticBytes, Frame.Slot.bytes, Source.Slot.Kind.width,
    Source.Slot.Kind.load, List.flatMap_cons, List.flatMap_nil,
    List.append_nil, List.append_assoc] using (first.append second).append third

/-- The actual Lanius helper emits operand preparation and arithmetic in
order. No successful source execution or proposed output is assumed. -/
theorem succeeds {parent : Source.Operation.Checked emitters} (checked : Source.Operation.FromSlot.Checked parent)
    (arithmetic : Source.Operation.Arithmetic.Checked parent) (operation : Machine.Alu) (slot capacity start : Nat)
    (slotBound : slot ≤ 1048576) (room : start + 10 ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    checked.internal.Spec (inputs (.slice i32 cell [] 0 values.length) capacity start slot
      (Transport.binaryTag (Encode.Arithmetic.coreOp operation))) (.signed .i32 (start + 10 : Nat))
      (fun before => (Storage.entry cell (some (.array (signedI32Values values)))).holds before.cells)
      (fun _ after => Output emitters.pack.program.core.target operation slot cell values start after.cells) (CellSet.singleton cell) := by
  let writer : Writer.Result := ⟨start, values⟩
  have composed := write (cell := cell) checked arithmetic operation slot capacity writer slotBound
    (by simpa [writer] using storage) bounded
  have bytes := result_emission operation slot capacity start values room storage
  have cursor : (result operation slot capacity writer).cursor = (start + 10 : Nat) := by
    rw [result_success operation slot capacity start values room]
  have mapped := composed.map (post := fun _ after => Output emitters.pack.program.core.target
      operation slot cell values start after.cells) (by
    intro before after output
    refine ⟨_, output, ?_, ?_⟩
    · simpa [writer] using bytes
    · intro tail machine auxiliary
      have size : (Expression.Binary.finishBytes operation slot).length = 10 := rfl
      rw [← size, bytes.bytes]
      exact Expression.Binary.finishes operation slot machine auxiliary)
  change CellSpec emitters.pack.program.core checked.internal.source.function.id _ _ (Writer.Stored cell values) _ _
  simpa only [writer, cursor] using mapped

/-- A failed initial reservation propagates through both following calls;
even a non-slice output is safe, and no caller storage is changed. -/
theorem rejects {parent : Source.Operation.Checked emitters} (checked : Source.Operation.FromSlot.Checked parent)
    (arithmetic : Source.Operation.Arithmetic.Checked parent) (operation : Machine.Alu) (slot : Nat)
    (slotBound : slot ≤ 1048576) (output : Value) (capacity start : Int)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 2 = false) :
    checked.internal.Spec (inputs output capacity start slot (Transport.binaryTag (Encode.Arithmetic.coreOp operation)))
      (.signed .i32 (-1)) := by
  have rax (state : State) := parent.rax.evaluates (before := state)
  have rcx (state : State) := parent.rcx.evaluates (before := state)
  have rbp (state : State) := checked.rbp.evaluates (before := state)
  simp only [parent.values.2.1] at rax
  simp only [parent.values.2.2] at rcx
  simp only [checked.base] at rbp
  have moving := Encode.Direct.rejects_capacity (emitters.registerWrappers .move) .w32 1 0 output capacity start bounded bad
  have displacement := Frame.displacement_spec checked.offset slot slotBound
  have loading := Encode.Memory.move_rejects_spec checked.load .w32 0 5
    (Frame.displacement slot) output capacity (-1) bounded (by simp [reserved])
  have binary := Arithmetic.rejects arithmetic operation output capacity (-1) bounded (by simp [reserved])
  refine checked.internal.specExpressionFrame rfl ?_
  apply ExprSpec.call (callee := binary)
  · core_spec [inputs, Encode.Direct.inputs, Encode.Memory.moveValues, Arithmetic.inputs, Encode.Boolean.inputs]
  · exact fun _ held => held

end Lanius.X86.Lower.Operation.FromSlot
