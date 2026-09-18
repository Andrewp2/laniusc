import Lanius.X86.Encode.Guarded

namespace Lanius.X86.Encode.Arithmetic

open Lanius.Core Lanius.Semantics Lanius.Separation Lanius.CallContracts Lanius.X86.Buffer

def coreOp : Machine.Alu → BinaryOp
  | .add => .add | .subtract => .subtract | .and => .bitAnd | .or => .bitOr | .xor => .bitXor

def choice (operation : Machine.Alu) : Guarded.Choice .binary :=
  ⟨operation.opcode, by cases operation <;> decide⟩

def config (operation : Machine.Alu) (destination source : Fin 16) : Config :=
  Guarded.config .binary (choice operation) .w32 destination source

private theorem extended (register : Fin 16) :
    Machine.extendRegister ⟨register.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ register.val)) = register := by
  apply Fin.ext
  have := register.isLt
  by_cases high : 8 ≤ register.val <;> simp [Machine.extendRegister, high] <;> omega

private theorem opcode_decodes (operation : Machine.Alu) (destination source : Fin 16) (present : Bool) :
    Machine.decodeOpcode (Register.fields .w32 source destination) present
      [UInt8.ofNat operation.opcode, UInt8.ofNat (Encoding.modRM source destination)] =
      some (.alu32 operation destination source, 2) := by
  have fields := Encoding.modRM_fields source destination
  have byte : (UInt8.ofNat (Encoding.modRM source destination)).toNat = Encoding.modRM source destination :=
    by rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt fields.2.2.2]
  cases operation <;> simp [Machine.decodeOpcode, Machine.Alu.opcode, Machine.Alu.ofOpcode?,
    Register.fields, byte, fields.1, fields.2.1, fields.2.2.1, extended]

theorem decodes (operation : Machine.Alu) (destination source : Fin 16) :
    Machine.decode ((config operation destination source).bytes.map UInt8.ofNat) =
      some (.alu32 operation destination source, (config operation destination source).size) := by
  let rex := Register.value .w32 source destination false
  have shape : (config operation destination source).bytes.map UInt8.ofNat =
      (if rex = 0 then [] else [UInt8.ofNat rex]) ++
        [UInt8.ofNat operation.opcode, UInt8.ofNat (Encoding.modRM source destination)] := by
    simp [config, Guarded.config, choice, Config.bytes, Config.rex, Encoding.bytes, Encoding.header,
      Encoding.Opcode.extended, Encoding.Opcode.byte, rex]
    split <;> simp_all
  have size : (config operation destination source).size = 2 + if rex = 0 then 0 else 1 := rfl
  rw [shape, size]
  by_cases absent : rex = 0
  · have omitted := (Register.omitted_iff .w32 source destination false).mp absent
    have fields : Register.fields .w32 source destination = ⟨false, false, false, false⟩ := by
      simp [Register.fields, show ¬ 8 ≤ source.val by omega, show ¬ 8 ≤ destination.val by omega]
    have decoded := opcode_decodes operation destination source false
    rw [fields] at decoded
    have noPrefix : Register.Rex.decode? (UInt8.ofNat operation.opcode).toNat = none := by cases operation <;> rfl
    simpa only [if_pos absent, List.nil_append, Machine.decode, noPrefix, Nat.add_zero] using decoded
  · have bounds := (Register.value_bounds .w32 source destination false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
    have rexDecoded : Register.Rex.decode? rex = some (Register.fields .w32 source destination) :=
      Register.present_decodes .w32 source destination false absent
    simp only [if_neg absent, List.cons_append, List.nil_append, Machine.decode, byte,
      rexDecoded, opcode_decodes]
    rfl

private theorem wrap32 (value : Int) : wrapSigned target .i32 value = (BitVec.ofInt 32 value).toInt := by
  simp only [wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits, BitVec.toInt_ofInt, Int.bmod_def]
  omega

/-- The five native operations agree with Core for every pair of i32 bit
patterns, including signed overflow and negative bitwise operands. -/
theorem core_result (operation : Machine.Alu) (left right : BitVec 32) :
    evalBinaryValue target (coreOp operation) (.signed .i32 left.toInt) (.signed .i32 right.toInt) =
      .ok (.signed .i32 (operation.result left right).toInt) := by
  have bits (value : BitVec 32) : (value.toInt % 4294967296).toNat = value.toNat := by
    simpa using (BitVec.toNat_ofInt (n := 32) value.toInt).symm
  cases operation
  case add =>
    change (Except.ok (Value.signed .i32 (wrapSigned target .i32 (left.toInt + right.toInt))) : Except Lanius.Trap Value) = _
    simp only [wrap32, Machine.Alu.result, BitVec.toInt_ofInt, BitVec.toInt_add]
  case subtract =>
    change (Except.ok (Value.signed .i32 (wrapSigned target .i32 (left.toInt - right.toInt))) : Except Lanius.Trap Value) = _
    simp only [wrap32, Machine.Alu.result, BitVec.toInt_ofInt, BitVec.toInt_sub]
  case and =>
    change (Except.ok (Value.signed .i32 (wrapSigned target .i32
      (↑((left.toInt % 4294967296).toNat &&& (right.toInt % 4294967296).toNat)))) : Except Lanius.Trap Value) = _
    simp only [bits, wrap32, Machine.Alu.result, BitVec.toInt_ofInt, BitVec.toInt_and]
  case or =>
    change (Except.ok (Value.signed .i32 (wrapSigned target .i32
      (↑((left.toInt % 4294967296).toNat ||| (right.toInt % 4294967296).toNat)))) : Except Lanius.Trap Value) = _
    simp only [bits, wrap32, Machine.Alu.result, BitVec.toInt_ofInt, BitVec.toInt_or]
  case xor =>
    change (Except.ok (Value.signed .i32 (wrapSigned target .i32
      (↑((left.toInt % 4294967296).toNat ^^^ (right.toInt % 4294967296).toNat)))) : Except Lanius.Trap Value) = _
    simp only [bits, wrap32, Machine.Alu.result, BitVec.toInt_ofInt, BitVec.toInt_xor]

/-- Correctness of an actual instruction window. AF is universally chosen;
logical operations must work for either architectural outcome. -/
def NativeRefines (target : Target) (operation : Machine.Alu) (destination source : Fin 16)
    (bytes : List UInt8) : Prop :=
  ∀ (before : Machine.State) (auxiliary : Bool), Machine.CodeAt before.memory before.rip bytes →
    ∃ after, Machine.Step before after ∧
      evalBinaryValue target (coreOp operation)
        (.signed .i32 ((before.registers destination).setWidth 32).toInt)
        (.signed .i32 ((before.registers source).setWidth 32).toInt) =
          .ok (.signed .i32 ((after.registers destination).setWidth 32).toInt) ∧
      after.registers destination = ((after.registers destination).setWidth 32).setWidth 64 ∧
      (∀ register, register ≠ destination → after.registers register = before.registers register) ∧
      after.flags = operation.flags before.flags ((before.registers destination).setWidth 32)
        ((before.registers source).setWidth 32) auxiliary ∧
      after.memory = before.memory ∧ after.rip = before.rip + BitVec.ofNat 64 bytes.length

theorem native (operation : Machine.Alu) (destination source : Fin 16) :
    NativeRefines target operation destination source ((config operation destination source).bytes.map UInt8.ofNat) := by
  intro before auxiliary loaded
  refine ⟨before.alu32 operation destination source auxiliary (config operation destination source).size,
    .arithmetic _ loaded _ _ _ _ (decodes operation destination source) auxiliary rfl, ?_⟩
  simp only [Machine.State.alu32, Machine.State.immediate32, ↓reduceIte, BitVec.setWidth_setWidth_of_le _ (by decide : 32 ≤ 64),
    BitVec.setWidth_eq, core_result, List.length_map, Config.bytes, Encoding.bytes_size, Config.size,
    true_and, and_true]
  intro register different
  simp [different]

theorem preserves (window : (config operation destination source).Emission values start emitted) :
    NativeRefines target operation destination source
      (byteSlice emitted start (config operation destination source).size) := by
  rw [window.bytes]
  exact native operation destination source

/-- Exact output storage and native correctness of that same byte window. -/
def Output (target : Target) (operation : Machine.Alu) (destination source : Fin 16)
    (cell : CellId) (values : List Int) (start : Nat) (cells : List Cell) : Prop :=
  cells.find? (fun entry => entry.id == cell) = some { id := cell, value := some (.array (signedI32Values
    (writtenBytes values start (config operation destination source).bytes))) } ∧
  NativeRefines target operation destination source (byteSlice
    (writtenBytes values start (config operation destination source).bytes) start (config operation destination source).size)

/-- Source-call contract retaining the proved output, not independently
proposed bytes. The result predicate is shared by emitter and dispatcher. -/
def Produces (checked : Lanius.Extraction.Source.CheckedInternal program path name parameters resultType body)
    (arguments : List Value) (operation : Machine.Alu) (destination source : Fin 16)
    (cell : CellId) (values : List Int) (start : Nat) : Prop :=
  checked.Spec arguments
    (.signed .i32 (start + (config operation destination source).size : Nat))
    (requires := fun before => before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (ensures := fun _ after => Output program.core.target operation destination source cell values start after.cells)
    (writes := CellSet.singleton cell)

theorem succeeds (checked : Source.CheckedGuardedRegister program form .binary) (operation : Machine.Alu)
    (destination source : Fin 16) (capacity start : Nat) (room : start + (config operation destination source).size ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    Produces checked.internal (Guarded.inputs .binary (.slice Source.i32 cell [] 0 values.length)
      capacity start 32 operation.opcode destination.val source.val) operation destination source cell values start :=
  CellSpec.withFact (Guarded.succeeds checked (choice operation) .w32 destination source capacity start room storage bounded)
    (preserves ((config operation destination source).emission (by omega)))

end Lanius.X86.Encode.Arithmetic
