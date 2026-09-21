import Lanius.X86.Machine.AluEncoding
import Lanius.X86.Machine.ScalarEncoding
import Lanius.X86.Machine.ControlEncoding
import Lanius.X86.Machine.RuntimeEncoding
import Lanius.X86.Machine.AddressEncoding
import Lanius.X86.Machine.NonDivEncoding
import Lanius.X86.Machine.DivisionEncoding
import Lanius.X86.Machine.Scalar
import Lanius.X86.Control.Decode
import Lanius.Semantics

namespace Lanius.X86.Machine

open Lanius.Semantics

/-- The disp32 MOV form emitted by `x86::encode::memory_form`, with a
32/64-bit operand and a 64-bit base. This describes bytes, not another compiler. -/
def memoryHeader (width : X86.Register.Width) (load : Bool) (reg base : Register) : List UInt8 :=
  let rex := X86.Register.value width reg base false
  (if rex = 0 then [] else [UInt8.ofNat rex]) ++
    [if load then 139 else 137, UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)] ++
    (if base.val % 8 = 4 then [36] else [])

def memoryBytes (width : X86.Register.Width) (load : Bool) (reg base : Register) (displacement : Int) : List UInt8 :=
  memoryHeader width load reg base ++ i32Bytes displacement

def memoryInstruction (width : X86.Register.Width) (load : Bool) (reg base : Register) (displacement : BitVec 32) : Instruction :=
  match width with
  | .w32 => if load then .load32 reg base displacement else .store32 reg base displacement
  | .w64 => if load then .load64 reg base displacement else .store64 reg base displacement

def byteMemoryBytes (load : Bool) (reg base : Register) (displacement : Int) : List UInt8 :=
  let force := if load then false else decide (4 ≤ reg.val)
  let rex := X86.Register.value .w32 reg base force
  (if rex = 0 then [] else [UInt8.ofNat rex]) ++
    (if load then [15, 182] else [136]) ++
    [UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)] ++
    (if base.val % 8 = 4 then [36] else []) ++ i32Bytes displacement

def byteMemoryInstruction (load : Bool) (reg base : Register) (displacement : BitVec 32) : Instruction :=
  if load then .loadByte reg base displacement else .storeByte reg base displacement

def loadByteBytes (destination base : Register) (displacement : Int) : List UInt8 :=
  byteMemoryBytes true destination base displacement

def storeByteBytes (source base : Register) (displacement : Int) : List UInt8 :=
  byteMemoryBytes false source base displacement

private theorem extended (reg : Register) :
    extendRegister ⟨reg.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ reg.val)) = reg := by
  apply Fin.ext
  have bound := reg.isLt
  by_cases high : 8 ≤ reg.val <;> simp [extendRegister, high] <;> omega

private theorem modrm (reg base : Register) :
    let byte := UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)
    byte.toNat / 64 = 2 ∧ byte.toNat / 8 % 8 = reg.val % 8 ∧ byte.toNat % 8 = base.val % 8 := by
  dsimp
  rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
  omega

private theorem displacement_i32Bytes (value : Int) (tail : List UInt8) :
    Control.displacement? (i32Bytes value ++ tail) =
      some (BitVec.ofInt 32 value) := by
  have byteRoundTrip (byte : Fin 256) :
      (UInt8.ofNat byte.val).toFin = byte := by
    apply Fin.ext
    change byte.val % 256 = byte.val
    exact Nat.mod_eq_of_lt byte.isLt
  simp [i32Bytes, List.range_succ, Control.displacement?, readBytes]
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ofNat, BitVec.toNat_ofInt]
  have nonnegative : 0 ≤ value % (2 ^ (32 : Nat)) :=
    Int.emod_nonneg _ (by decide)
  have below : value % (2 ^ (32 : Nat)) < (2 ^ (32 : Nat)) :=
    Int.emod_lt_of_pos _ (by decide)
  have bitsBound : (value % (2 ^ (32 : Nat))).toNat < 2 ^ (32 : Nat) := by
    have cast := Int.toNat_of_nonneg nonnegative
    omega
  have first := Nat.mod_add_div (value % (2 ^ (32 : Nat))).toNat 256
  have second := Nat.mod_add_div
    ((value % (2 ^ (32 : Nat))).toNat / 256) 256
  have third := Nat.mod_add_div
    (((value % (2 ^ (32 : Nat))).toNat / 256) / 256) 256
  simp
  omega

private theorem opcode_memory (width : X86.Register.Width) (load : Bool) (reg base : Register) (displacement : Int) (tail : List UInt8) (rexPresent : Bool) :
    decodeOpcode (X86.Register.fields width reg base) rexPresent
      (([if load then 139 else 137, UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)] ++
        (if base.val % 8 = 4 then [36] else [])) ++ i32Bytes displacement ++ tail) =
    some (memoryInstruction width load reg base (BitVec.ofInt 32 displacement),
      6 + if base.val % 8 = 4 then 1 else 0) := by
  have fields := modrm reg base
  generalize hbyte : UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8) = byte at fields ⊢
  cases width <;> cases load <;> by_cases sib : base.val % 8 = 4 <;>
    simp [decodeOpcode, memoryForm, X86.Register.fields, fields.1, fields.2.1, fields.2.2,
      sib, displacement_i32Bytes, memoryInstruction, extended]
  all_goals
    apply Fin.ext
    have bound := base.isLt
    by_cases high : 8 ≤ base.val <;> simp [extendRegister, high] <;> omega

private theorem byte_opcode_memory (load : Bool) (reg base : Register) (displacement : Int)
    (tail : List UInt8) (rexPresent : Bool) :
    decodeOpcode (X86.Register.fields .w32 reg base) rexPresent
      (((if load then [15, 182] else [136]) ++
        [UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)] ++
        (if base.val % 8 = 4 then [36] else [])) ++ i32Bytes displacement ++ tail) =
    some (byteMemoryInstruction load reg base (BitVec.ofInt 32 displacement),
      (if load then 7 else 6) + if base.val % 8 = 4 then 1 else 0) := by
  have fields := modrm reg base
  have alunone : Alu.ofOpcode? 15 = none := by decide
  generalize hbyte : UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8) = byte at fields ⊢
  cases load <;> by_cases sib : base.val % 8 = 4 <;>
    simp [decodeOpcode, escapedForm, memoryForm, alunone, X86.Register.fields, fields.1, fields.2.1, fields.2.2,
      sib, displacement_i32Bytes, byteMemoryInstruction, extended]
  all_goals
    apply Fin.ext
    have bound := base.isLt
    by_cases high : 8 ≤ base.val <;> simp [extendRegister, high] <;> omega

theorem memory_decodes (width : X86.Register.Width) (load : Bool) (reg base : Register) (displacement : Int) (tail : List UInt8) :
    decode (memoryBytes width load reg base displacement ++ tail) =
      some (memoryInstruction width load reg base (BitVec.ofInt 32 displacement), (memoryBytes width load reg base displacement).length) := by
  let rex := X86.Register.value width reg base false
  have wordLength : (i32Bytes displacement).length = 4 := by simp [i32Bytes]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width reg base false).mp absent
    have narrow := omitted.1
    subst width
    have noRex : X86.Register.fields .w32 reg base = ⟨false, false, false, false⟩ := by
      simp [X86.Register.fields, show ¬ 8 ≤ reg.val by omega, show ¬ 8 ≤ base.val by omega]
    have run := opcode_memory .w32 load reg base displacement tail false
    rw [noRex] at run
    have absent' : X86.Register.value .w32 reg base false = 0 := absent
    cases load <;> by_cases sib : base.val % 8 = 4 <;>
      simpa [memoryBytes, memoryHeader, absent', decode, X86.Register.Rex.decode?,
        wordLength, List.append_assoc, sib] using run
  · have bounds := (X86.Register.value_bounds width reg base false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
    have parsed := X86.Register.present_decodes width reg base false absent
    have run := opcode_memory width load reg base displacement tail true
    simp only [memoryBytes, memoryHeader, show X86.Register.value width reg base false = rex from rfl,
      if_neg absent, List.cons_append, List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width reg base) from parsed]
    simp only [List.append_assoc, List.cons_append, List.nil_append] at run ⊢
    rw [run]
    by_cases sib : base.val % 8 = 4 <;> simp [wordLength, sib]

theorem byte_memory_decodes (load : Bool) (reg base : Register) (displacement : Int) (tail : List UInt8) :
    decode (byteMemoryBytes load reg base displacement ++ tail) =
      some (byteMemoryInstruction load reg base (BitVec.ofInt 32 displacement),
        (byteMemoryBytes load reg base displacement).length) := by
  let force := if load then false else decide (4 ≤ reg.val)
  let rex := X86.Register.value .w32 reg base force
  have wordLength : (i32Bytes displacement).length = 4 := by simp [i32Bytes]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff .w32 reg base force).mp absent
    have narrow := omitted.1
    have force_absent : force = false := by
      have h := omitted.2.2.2
      simp [force] at h ⊢
      omega
    have noRex : X86.Register.fields .w32 reg base = ⟨false, false, false, false⟩ := by
      simp [X86.Register.fields, show ¬ 8 ≤ reg.val by omega, show ¬ 8 ≤ base.val by omega]
    have run := byte_opcode_memory load reg base displacement tail false
    rw [noRex] at run
    have absent' : X86.Register.value .w32 reg base force = 0 := absent
    have absent_noforce : X86.Register.value .w32 reg base false = 0 := by
      simpa [force, force_absent] using absent'
    cases load with
    | false =>
      have force_decide : decide (4 ≤ reg.val) = false := by
        have h := omitted.2.2.2
        simpa [force] using h
      by_cases sib : base.val % 8 = 4
      · simpa [byteMemoryBytes, force, force_decide, absent', absent_noforce, decode, X86.Register.Rex.decode?, wordLength, List.append_assoc, sib] using run
      · simpa [byteMemoryBytes, force, force_decide, absent', absent_noforce, decode, X86.Register.Rex.decode?, wordLength, List.append_assoc, sib] using run
    | true =>
      by_cases sib : base.val % 8 = 4
      · simpa [byteMemoryBytes, force, absent', absent_noforce, decode, X86.Register.Rex.decode?, wordLength, List.append_assoc, sib] using run
      · simpa [byteMemoryBytes, force, absent', absent_noforce, decode, X86.Register.Rex.decode?, wordLength, List.append_assoc, sib] using run
  · have bounds := (X86.Register.value_bounds .w32 reg base force).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
    have parsed := X86.Register.present_decodes .w32 reg base force absent
    have run := byte_opcode_memory load reg base displacement tail true
    simp only [byteMemoryBytes, force, show X86.Register.value .w32 reg base force = rex from rfl,
      if_neg absent, List.cons_append, List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields .w32 reg base) from parsed]
    simp only [List.append_assoc, List.cons_append, List.nil_append] at run ⊢
    rw [run]
    cases load <;> by_cases sib : base.val % 8 = 4 <;> simp [wordLength, sib]

theorem loadByte_decodes (destination base : Register) (displacement : Int) (tail : List UInt8) :
    decode (loadByteBytes destination base displacement ++ tail) =
      some (.loadByte destination base (BitVec.ofInt 32 displacement),
        (loadByteBytes destination base displacement).length) := by
  simpa [loadByteBytes, byteMemoryInstruction] using byte_memory_decodes true destination base displacement tail

theorem storeByte_decodes (source base : Register) (displacement : Int) (tail : List UInt8) :
    decode (storeByteBytes source base displacement ++ tail) =
      some (.storeByte source base (BitVec.ofInt 32 displacement),
        (storeByteBytes source base displacement).length) := by
  simpa [storeByteBytes, byteMemoryInstruction] using byte_memory_decodes false source base displacement tail

private theorem byte_decoded_step (before after : State) (bytes : List UInt8)
    (instruction : Instruction) (size : Nat) (loaded : CodeAt before.memory before.rip bytes)
    (decoded : decode bytes = some (instruction, size))
    (result : after = execute instruction size before) : Step before after :=
  Step.decoded bytes loaded instruction size decoded result

theorem loadByte_step (before after : State) (destination base : Register) (displacement : Int)
    (loaded : CodeAt before.memory before.rip (loadByteBytes destination base displacement))
    (result : after = execute (.loadByte destination base (BitVec.ofInt 32 displacement))
      (loadByteBytes destination base displacement).length before) : Step before after := by
  have decoded : decode (loadByteBytes destination base displacement) =
      some (.loadByte destination base (BitVec.ofInt 32 displacement),
        (loadByteBytes destination base displacement).length) := by
    simpa using loadByte_decodes destination base displacement []
  exact byte_decoded_step before after _ _ _ loaded decoded result

theorem storeByte_step (before after : State) (source base : Register) (displacement : Int)
    (loaded : CodeAt before.memory before.rip (storeByteBytes source base displacement))
    (result : after = execute (.storeByte source base (BitVec.ofInt 32 displacement))
      (storeByteBytes source base displacement).length before) : Step before after := by
  have decoded : decode (storeByteBytes source base displacement) =
      some (.storeByte source base (BitVec.ofInt 32 displacement),
        (storeByteBytes source base displacement).length) := by
    simpa using storeByte_decodes source base displacement []
  exact byte_decoded_step before after _ _ _ loaded decoded result

end Lanius.X86.Machine
