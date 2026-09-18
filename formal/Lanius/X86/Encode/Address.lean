import Lanius.X86.Source.Address
import Lanius.X86.Encode.Memory

namespace Lanius.X86.Encode.Address

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer Lanius.X86.Encoding

def config (reg base : Fin 16) (displacement : Int) : Memory.Config :=
  ⟨.w64, .primary ⟨141, by decide⟩, reg, base, displacement, false⟩
def bytes (reg base : Fin 16) (displacement : Int) : List UInt8 := (config reg base displacement).bytes
def inputValues (output : Value) (capacity start : Int) (reg base : Fin 16) (displacement : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 reg.val,
    .signed .i32 base.val, .signed .i32 displacement]

theorem rex_present (reg base : Fin 16) : Register.value .w64 reg base false ≠ 0 := by
  intro absent
  have impossible := (Register.omitted_iff .w64 reg base false).mp absent
  cases impossible.1

theorem size_eq (reg base : Fin 16) (displacement : Int) :
    (config reg base displacement).size = (bytes reg base displacement).length := by
  have header := (config reg base displacement).header_size
  simpa only [bytes, Memory.Config.bytes, List.length_append, List.length_map, i32Bytes_length] using header.symm

@[simp] theorem bytes_length (reg base : Fin 16) (displacement : Int) :
    (bytes reg base displacement).length = 7 + if base.val % 8 = 4 then 1 else 0 := by
  rw [← size_eq]
  by_cases sib : base.val % 8 = 4 <;>
    simp [Memory.Config.size, Memory.Config.rex, Memory.Config.sib, config, rex_present, sib, Opcode.extended]

private theorem extended (reg : Machine.Register) :
    Machine.extendRegister ⟨reg.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ reg.val)) = reg := by
  apply Fin.ext
  have bound := reg.isLt
  by_cases high : 8 ≤ reg.val <;> simp [Machine.extendRegister, high] <;> omega

private theorem opcode_decodes (reg base : Fin 16) (displacement : Int) (tail : List UInt8) :
    Machine.decodeOpcode (Register.fields .w64 reg base) true
      (([141, UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)] ++
        (if base.val % 8 = 4 then [36] else [])) ++ i32Bytes displacement ++ tail) =
    some (.address64 reg base none 0 (BitVec.ofInt 32 displacement), 6 + if base.val % 8 = 4 then 1 else 0) := by
  have fields : let byte := UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)
      byte.toNat / 64 = 2 ∧ byte.toNat / 8 % 8 = reg.val % 8 ∧ byte.toNat % 8 = base.val % 8 := by
    dsimp
    rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
    omega
  generalize hbyte : UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8) = byte at fields ⊢
  by_cases sib : base.val % 8 = 4 <;>
    simp [Machine.decodeOpcode, Machine.addressForm, Register.fields, fields.1, fields.2.1, fields.2.2,
      sib, Control.displacement?_i32Bytes, extended]
  apply Fin.ext
  have bound := base.isLt
  by_cases high : 8 ≤ base.val <;> simp [Machine.extendRegister, high] <;> omega

/-- Decode the shared memory-form bytes as the existing LEA instruction,
including RSP/R12's no-index SIB and extended destination/base registers. -/
theorem decodes (reg base : Fin 16) (displacement : Int) (tail : List UInt8) :
    Machine.decode (bytes reg base displacement ++ tail) =
      some (.address64 reg base none 0 (BitVec.ofInt 32 displacement), (bytes reg base displacement).length) := by
  have present := rex_present reg base
  have bounds := (Register.value_bounds .w64 reg base false).resolve_left present
  have byte : (UInt8.ofNat (Register.value .w64 reg base false)).toNat = Register.value .w64 reg base false := by
    rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
  have parsed := Register.present_decodes .w64 reg base false present
  have run := opcode_decodes reg base displacement tail
  by_cases sib : base.val % 8 = 4 <;>
    simpa [bytes, config, Memory.Config.bytes, Memory.Config.header, Memory.Config.tailHeader,
      Memory.Config.rex, Memory.Config.modRM, Memory.Config.sib, Encoding.header, Opcode.extended, Opcode.byte,
      present, Machine.decode, byte, parsed, List.append_assoc, sib, i32Bytes_length,
      show UInt8.ofFin (141 : Fin 256) = (141 : UInt8) from rfl] using run

theorem arguments (program : Program)
    (locals : ∀ index : Fin 6, before.local? index.val =
      some ((inputValues output capacity start reg base displacement).get index)) :
    ArgumentsEvaluateTo program before Source.Address.arguments
      ((config reg base displacement).arguments output capacity start) before := by
  simp only [Source.Address.arguments, config, Memory.Config.arguments, Register.Width.bits,
    Opcode.packed, Opcode.extended, Opcode.byte, Bool.false_eq_true, ↓reduceIte]
  (repeat' apply ArgumentsEvaluateTo.cons (afterHead := before)) <;>
    first
    | exact .nil _ _
    | exact local_evaluates program (locals ⟨0, by decide⟩)
    | exact local_evaluates program (locals ⟨1, by decide⟩)
    | exact local_evaluates program (locals ⟨2, by decide⟩)
    | exact local_evaluates program (locals ⟨3, by decide⟩)
    | exact local_evaluates program (locals ⟨4, by decide⟩)
    | exact local_evaluates program (locals ⟨5, by decide⟩)
    | exact ⟨1, rfl⟩

/-- Execute the actual public address emitter, reusing the proved complete
memory_form execution rather than assuming helper success or output bytes. -/
theorem emits (checked : Source.Address.Checked program form) (reg base : Fin 16) (displacement : Int)
    (capacity start : Nat) (wellFormed : StateWellFormed before)
    (room : start + (bytes reg base displacement).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller expressions
      (inputValues (.slice i32 cell [] 0 values.length) capacity start reg base displacement) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.source.function.id expressions)
        (.signed .i32 (start + (bytes reg base displacement).length : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values emitted)) } ∧
      byteSlice emitted start (bytes reg base displacement).length = bytes reg base displacement ∧
      (∀ machine, Machine.CodeAt machine.memory machine.rip (byteSlice emitted start (bytes reg base displacement).length) →
        Machine.Step machine (machine.address64 reg base none 0 (BitVec.ofInt 32 displacement) (bytes reg base displacement).length)) ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes reg base displacement).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 6 =>
    (inputValues (.slice i32 cell [] 0 values.length) capacity start reg base displacement).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have locals (index : Fin 6) : callee.local? index.val = some
      ((inputValues (.slice i32 cell [] 0 values.length) capacity start reg base displacement).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have args := arguments program.core locals
  have initial := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, run, contents, effect, heap⟩ := Memory.succeeds form (config reg base displacement)
    capacity start calleeWF (by simpa only [size_eq] using room) storage bounded initial args
  have exactBytes : byteSlice ((config reg base displacement).written values start) start
      (bytes reg base displacement).length = bytes reg base displacement := by
    rw [← size_eq]
    exact (config reg base displacement).emission (by simpa only [size_eq] using Nat.le_trans room storage)
  rw [size_eq] at run
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequenceReturned (executesReturnValue run)) effect
  refine ⟨restoreLocals before completed, (config reg base displacement).written values start,
    called.1, contents, exactBytes, ?_, (config reg base displacement).written_length values, ?_, called.2,
    HeapFrame.closeCall before params heap⟩
  · intro machine loaded
    rw [exactBytes] at loaded
    exact .decoded _ loaded _ _ (by simpa only [List.append_nil] using decodes reg base displacement []) rfl
  · intro index outside
    exact (config reg base displacement).frame (by simpa only [size_eq] using outside)

theorem rejects_capacity (checked : Source.Address.Checked program form) (reg base : Fin 16) (displacement : Int)
    (output : Value) (capacity start : Int) (wellFormed : StateWellFormed before) (bounded : capacity ≤ 2147483647)
    (bad : reserved capacity start (bytes reg base displacement).length = false)
    (argumentsResult : ArgumentsEvaluateTo program.core caller expressions
      (inputValues output capacity start reg base displacement) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id expressions) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 6 => (inputValues output capacity start reg base displacement).get index)
  let callee := enterCall before params
  have locals (index : Fin 6) : callee.local? index.val =
      some ((inputValues output capacity start reg base displacement).get index) := enterCall_parameterBindings_matches wellFormed index
  obtain ⟨rejected, run, effect, heap⟩ := Memory.rejects_capacity form (config reg base displacement) output capacity start
    (enterCall_preserves_wellFormed wellFormed) bounded (by simpa only [size_eq] using bad) (arguments program.core locals)
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequenceReturned (executesReturnValue run)) effect
  exact ⟨restoreLocals before rejected, called.1, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Encode.Address
