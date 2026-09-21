import Lanius.X86.Machine.Scalar
import Lanius.X86.Encoding

namespace Lanius.X86.Machine

open Lanius.X86

def registerFormBytes (width : X86.Register.Width) (opcode : Nat)
    (reg rm : Register) : List UInt8 :=
  let rex := X86.Register.value width reg rm false
  (if rex = 0 then [] else [UInt8.ofNat rex]) ++
    (if opcode > 255 then [15] else []) ++
      [UInt8.ofNat opcode, UInt8.ofNat (Encoding.modRM reg rm)]

def multiplyBytes (width : X86.Register.Width) (destination source : Register) : List UInt8 :=
  registerFormBytes width 4015 destination source

def negateBytes (width : X86.Register.Width) (destination : Register) : List UInt8 :=
  registerFormBytes width 247 3 destination

def shiftRegister (operation : Shift) : Register :=
  match operation with
  | .left => 4
  | .right => 5
  | .arithmeticRight => 7

def shiftBytes (width : X86.Register.Width) (operation : Shift)
    (destination : Register) : List UInt8 :=
  registerFormBytes width 211 (shiftRegister operation) destination

def nonDivInstruction (width : X86.Register.Width) (destination source : Register) : Instruction :=
  match width with
  | .w32 => .multiply32 destination source
  | .w64 => .multiply64 destination source

def negateInstruction (width : X86.Register.Width) (destination : Register) : Instruction :=
  match width with
  | .w32 => .negate32 destination
  | .w64 => .negate64 destination

def shiftInstruction (width : X86.Register.Width) (operation : Shift)
    (destination : Register) : Instruction :=
  match width with
  | .w32 => .shift32 operation destination
  | .w64 => .shift64 operation destination

private theorem extended (reg : Register) :
    extendRegister ⟨reg.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ reg.val)) = reg := by
  apply Fin.ext
  have bound := reg.isLt
  by_cases high : 8 ≤ reg.val <;> simp [extendRegister, high] <;> omega

private theorem modrm_byte (reg rm : Register) :
    (UInt8.ofNat (Encoding.modRM reg rm)).toNat = Encoding.modRM reg rm := by
  rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (Encoding.modRM_fields reg rm).2.2.2]

theorem multiply_decodes (width : X86.Register.Width) (destination source : Register) :
    decode (multiplyBytes width destination source) =
      some (nonDivInstruction width destination source,
        (multiplyBytes width destination source).length) := by
  let rex := X86.Register.value width destination source false
  have modrm := Encoding.modRM_fields destination source
  have modrmByte := modrm_byte destination source
  have rawNoRex (destination_low : destination.val < 8) (source_low : source.val < 8) :
      decodeOpcode ⟨false, false, false, false⟩ false [15, 175,
        UInt8.ofNat (Encoding.modRM destination source)] =
        some (.multiply32 destination source, 3) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ false = destination := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt destination_low]
    have source_ext :
        extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩ false = source := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt source_low]
    have alunone : Alu.ofOpcode? 15 = none := by decide
    simp [decodeOpcode, escapedForm, alunone, modrmByte, modrm.1, modrm.2.1,
      modrm.2.2, destination_ext, source_ext, nonDivInstruction]
  have rawRex (present : rex ≠ 0) :
      decodeOpcode (X86.Register.fields width destination source) true [15, 175,
        UInt8.ofNat (Encoding.modRM destination source)] =
        some (nonDivInstruction width destination source, 3) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width destination source).r = destination := by
      simpa [X86.Register.fields] using extended destination
    have source_ext :
        extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width destination source).b = source := by
      simpa [X86.Register.fields] using extended source
    have alunone : Alu.ofOpcode? 15 = none := by decide
    cases width <;>
      simp [decodeOpcode, escapedForm, alunone, modrmByte, modrm.1, modrm.2.1,
        modrm.2.2, destination_ext, source_ext, nonDivInstruction,
        X86.Register.fields, extended]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width destination source false).mp absent
    have opcode_mod : 4015 % 256 = 175 := by decide
    have opcode_escape : ¬(4015 ≤ 255) := by omega
    have absent' := absent
    dsimp [rex] at absent'
    rcases omitted with ⟨width_eq, destination_low, source_low, _⟩
    cases width_eq
    simpa [multiplyBytes, registerFormBytes, rex, absent, decode,
      X86.Register.Rex.decode?, opcode_mod, opcode_escape, absent', nonDivInstruction] using
      rawNoRex destination_low source_low
  · have parsed := X86.Register.present_decodes width destination source false absent
    have bounds := (X86.Register.value_bounds width destination source false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      change X86.Register.value width destination source false % 256 = _
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value width destination source false < 256)
    simp only [multiplyBytes, registerFormBytes, rex, if_neg absent, List.cons_append,
      List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width destination source) from parsed]
    simp [rawRex absent]

theorem negate_decodes (width : X86.Register.Width) (destination : Register) :
    decode (negateBytes width destination) =
      some (negateInstruction width destination,
        (negateBytes width destination).length) := by
  let rex := X86.Register.value width 3 destination false
  have modrm := Encoding.modRM_fields 3 destination
  have modrmByte := modrm_byte 3 destination
  have three_mod : ((3 : Register).val % 8) = 3 := by decide
  have rawNoRex (destination_low : destination.val < 8) :
      decodeOpcode ⟨false, false, false, false⟩ false
        [247, UInt8.ofNat (Encoding.modRM 3 destination)] =
        some (.negate32 destination, 2) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ false = destination := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt destination_low]
    have alunone : Alu.ofOpcode? 247 = none := by decide
    simp [decodeOpcode, alunone, modrmByte, modrm.1, modrm.2.1, modrm.2.2, destination_ext,
      negateInstruction, three_mod] <;> omega
  have rawRex (present : rex ≠ 0) :
      decodeOpcode (X86.Register.fields width 3 destination) true
        [247, UInt8.ofNat (Encoding.modRM 3 destination)] =
        some (negateInstruction width destination, 2) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width 3 destination).b = destination := by
      simpa [X86.Register.fields] using extended destination
    have alunone : Alu.ofOpcode? 247 = none := by decide
    cases width <;>
      simp [decodeOpcode, alunone, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
        destination_ext, negateInstruction, X86.Register.fields, extended, three_mod] <;> omega
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width 3 destination false).mp absent
    have absent' := absent
    dsimp [rex] at absent'
    rcases omitted with ⟨width_eq, _, destination_low, _⟩
    cases width_eq
    simpa [negateBytes, registerFormBytes, rex, absent, decode,
      X86.Register.Rex.decode?, absent', negateInstruction] using rawNoRex destination_low
  · have parsed := X86.Register.present_decodes width 3 destination false absent
    have bounds := (X86.Register.value_bounds width 3 destination false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      change X86.Register.value width 3 destination false % 256 = _
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value width 3 destination false < 256)
    simp only [negateBytes, registerFormBytes, rex, if_neg absent, List.cons_append,
      List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width 3 destination) from parsed]
    simp [rawRex absent]

private theorem shift_register_decodes (width : X86.Register.Width) (operation : Shift)
    (reg destination : Register)
    (operation_decode : Shift.ofModRM? (Encoding.modRM reg destination / 8 % 8) = some operation) :
    decode (registerFormBytes width 211 reg destination) =
      some (shiftInstruction width operation destination,
        (registerFormBytes width 211 reg destination).length) := by
  let rex := X86.Register.value width reg destination false
  have modrm := Encoding.modRM_fields reg destination
  have modrmByte := modrm_byte reg destination
  have operation_decode' : Shift.ofModRM? (reg.val % 8) = some operation := by
    simpa [modrm.2.1] using operation_decode
  have rawNoRex (destination_low : destination.val < 8) :
      decodeOpcode ⟨false, false, false, false⟩ false
        [211, UInt8.ofNat (Encoding.modRM reg destination)] =
        some (.shift32 operation destination, 2) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ false = destination := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt destination_low]
    have alunone : Alu.ofOpcode? 211 = none := by decide
    simp [decodeOpcode, alunone, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
      operation_decode', destination_ext, shiftInstruction]
  have rawRex (present : rex ≠ 0) :
      decodeOpcode (X86.Register.fields width reg destination) true
        [211, UInt8.ofNat (Encoding.modRM reg destination)] =
        some (shiftInstruction width operation destination, 2) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width reg destination).b = destination := by
      simpa [X86.Register.fields] using extended destination
    have alunone : Alu.ofOpcode? 211 = none := by decide
    cases width <;>
      simp [decodeOpcode, alunone, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
        operation_decode', destination_ext, shiftInstruction, X86.Register.fields,
        extended]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width reg destination false).mp absent
    have absent' := absent
    dsimp [rex] at absent'
    rcases omitted with ⟨width_eq, _, destination_low, _⟩
    cases width_eq
    simpa [registerFormBytes, rex, absent, decode, X86.Register.Rex.decode?, absent',
      shiftInstruction] using rawNoRex destination_low
  · have parsed := X86.Register.present_decodes width reg destination false absent
    have bounds := (X86.Register.value_bounds width reg destination false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      change X86.Register.value width reg destination false % 256 = _
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value width reg destination false < 256)
    simp only [registerFormBytes, rex, if_neg absent, List.cons_append, List.nil_append,
      decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width reg destination) from parsed]
    simp [rawRex absent]

theorem shift_decodes (width : X86.Register.Width) (operation : Shift)
    (destination : Register) :
    decode (shiftBytes width operation destination) =
      some (shiftInstruction width operation destination,
        (shiftBytes width operation destination).length) := by
  apply shift_register_decodes width operation (shiftRegister operation) destination
  cases operation with
  | left =>
    have fields := Encoding.modRM_fields (shiftRegister .left) destination
    rw [fields.2.1]
    simp [shiftRegister, Shift.ofModRM?] <;> decide
  | right =>
    have fields := Encoding.modRM_fields (shiftRegister .right) destination
    rw [fields.2.1]
    simp [shiftRegister, Shift.ofModRM?] <;> decide
  | arithmeticRight =>
    have fields := Encoding.modRM_fields (shiftRegister .arithmeticRight) destination
    rw [fields.2.1]
    simp [shiftRegister, Shift.ofModRM?] <;> decide

theorem multiply_step (width : X86.Register.Width) (before after : State)
    (destination source : Register)
    (loaded : CodeAt before.memory before.rip (multiplyBytes width destination source))
    (flags : BitVec 64)
    (result : after = before.multiply width.bits destination source flags
      (multiplyBytes width destination source).length) : Step before after := by
  exact Step.multiplied (multiplyBytes width destination source) loaded width destination source
    (multiplyBytes width destination source).length (multiply_decodes width destination source) flags result

theorem negate_step (width : X86.Register.Width) (before after : State)
    (destination : Register)
    (loaded : CodeAt before.memory before.rip (negateBytes width destination))
    (flags : BitVec 64)
    (result : after = before.negate width.bits destination flags
      (negateBytes width destination).length) : Step before after := by
  exact Step.negated (negateBytes width destination) loaded width destination
    (negateBytes width destination).length (negate_decodes width destination) flags result

theorem shift_step (width : X86.Register.Width) (before after : State)
    (operation : Shift) (destination : Register)
    (loaded : CodeAt before.memory before.rip (shiftBytes width operation destination))
    (flags : BitVec 64)
    (result : after = before.shift width.bits operation destination flags
      (shiftBytes width operation destination).length) : Step before after := by
  exact Step.shifted (shiftBytes width operation destination) loaded width operation destination
    (shiftBytes width operation destination).length (shift_decodes width operation destination) flags result

end Lanius.X86.Machine
