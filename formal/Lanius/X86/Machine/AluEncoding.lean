import Lanius.X86.Machine.Scalar
import Lanius.X86.Encoding

namespace Lanius.X86.Machine

open Lanius.X86

/-- The register form emitted for a 32/64-bit ALU operation (two bytes without
REX, three with REX). The source is ModRM `reg`; the destination is `r/m`. -/
def aluBytes (width : X86.Register.Width) (operation : Alu)
    (destination source : Register) : List UInt8 :=
  let rex := X86.Register.value width source destination false
  (if rex = 0 then [] else [UInt8.ofNat rex]) ++
    [UInt8.ofNat operation.opcode, UInt8.ofNat (Encoding.modRM source destination)]

def aluInstruction (width : X86.Register.Width) (operation : Alu)
    (destination source : Register) : Instruction :=
  match width with
  | .w32 => .alu32 operation destination source
  | .w64 => .alu64 operation destination source

def testBytes (width : X86.Register.Width) (left right : Register) : List UInt8 :=
  let rex := X86.Register.value width right left false
  (if rex = 0 then [] else [UInt8.ofNat rex]) ++
    [133, UInt8.ofNat (Encoding.modRM right left)]

def testInstruction (width : X86.Register.Width) (left right : Register) : Instruction :=
  match width with
  | .w32 => .test32 left right
  | .w64 => .test64 left right

private theorem extended (reg : Register) :
    extendRegister ⟨reg.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ reg.val)) = reg := by
  apply Fin.ext
  have bound := reg.isLt
  by_cases high : 8 ≤ reg.val <;> simp [extendRegister, high] <;> omega

private theorem modrm_byte (reg rm : Register) :
    (UInt8.ofNat (Encoding.modRM reg rm)).toNat = Encoding.modRM reg rm := by
  rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (Encoding.modRM_fields reg rm).2.2.2]

theorem alu_decodes (width : X86.Register.Width) (operation : Alu)
    (destination source : Register) :
    decode (aluBytes width operation destination source) =
      some (aluInstruction width operation destination source,
        (aluBytes width operation destination source).length) := by
  let rex := X86.Register.value width source destination false
  have modrm := Encoding.modRM_fields source destination
  have modrmByte := modrm_byte source destination
  have decodeNoRex (source_low : source.val < 8) (destination_low : destination.val < 8) :
      decodeOpcode ⟨false, false, false, false⟩ false
          [UInt8.ofNat operation.opcode, UInt8.ofNat (Encoding.modRM source destination)] =
        some (.alu32 operation destination source, 2) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ false = destination := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : destination.val < 8)]
    have source_ext :
        extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩ false = source := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : source.val < 8)]
    cases operation <;>
    simp [decodeOpcode, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
      destination_ext, source_ext, Alu.opcode, Alu.ofOpcode?]
  have decodeRex (present : rex ≠ 0) :
      decodeOpcode (X86.Register.fields width source destination) true
          [UInt8.ofNat operation.opcode, UInt8.ofNat (Encoding.modRM source destination)] =
        some (aluInstruction width operation destination source, 2) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width source destination).b = destination := by
      simpa [X86.Register.fields] using extended destination
    have source_ext :
        extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width source destination).r = source := by
      simpa [X86.Register.fields] using extended source
    cases width <;> cases operation <;>
    simp [decodeOpcode, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
      aluInstruction, X86.Register.fields, extended, Alu.opcode, Alu.ofOpcode?]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width source destination false).mp absent
    have opcode_low : operation.opcode < 64 := by cases operation <;> decide
    have opcode_mod : operation.opcode % 256 = operation.opcode := Nat.mod_eq_of_lt (by omega)
    have opcode_no_rex : ¬(64 ≤ operation.opcode ∧ operation.opcode < 80) := by omega
    have narrow := omitted.1
    subst width
    simpa [aluBytes, rex, absent, decode, X86.Register.Rex.decode?, opcode_low, opcode_mod,
      opcode_no_rex, aluInstruction] using
      decodeNoRex omitted.2.1 omitted.2.2.1
  · have parsed := X86.Register.present_decodes width source destination false absent
    have bounds := (X86.Register.value_bounds width source destination false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      change X86.Register.value width source destination false % 256 = _
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value width source destination false < 256)
    simp only [aluBytes, rex, if_neg absent, List.cons_append, List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width source destination) from parsed]
    simp only [Option.map, decodeRex absent]
    rfl

theorem test_decodes (width : X86.Register.Width) (left right : Register) :
    decode (testBytes width left right) =
      some (testInstruction width left right, (testBytes width left right).length) := by
  let rex := X86.Register.value width right left false
  have modrm := Encoding.modRM_fields right left
  have modrmByte := modrm_byte right left
  have decodeNoRex (left_low : left.val < 8) (right_low : right.val < 8) :
      decodeOpcode ⟨false, false, false, false⟩ false
          [133, UInt8.ofNat (Encoding.modRM right left)] =
        some (.test32 left right, 2) := by
    have left_ext :
        extendRegister ⟨left.val % 8, Nat.mod_lt _ (by decide)⟩ false = left := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : left.val < 8)]
    have right_ext :
        extendRegister ⟨right.val % 8, Nat.mod_lt _ (by decide)⟩ false = right := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : right.val < 8)]
    simp [decodeOpcode, modrmByte, modrm.1, modrm.2.1, modrm.2.2, left_ext, right_ext,
      Alu.ofOpcode?]
  have decodeRex (present : rex ≠ 0) :
      decodeOpcode (X86.Register.fields width right left) true
          [133, UInt8.ofNat (Encoding.modRM right left)] =
        some (testInstruction width left right, 2) := by
    have left_ext :
        extendRegister ⟨left.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width right left).b = left := by
      simpa [X86.Register.fields] using extended left
    have right_ext :
        extendRegister ⟨right.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width right left).r = right := by
      simpa [X86.Register.fields] using extended right
    cases width <;>
      simp [decodeOpcode, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
        X86.Register.fields, extended, testInstruction, Alu.ofOpcode?]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width right left false).mp absent
    have narrow := omitted.1
    subst width
    simpa [testBytes, rex, absent, decode, X86.Register.Rex.decode?, testInstruction] using
      decodeNoRex omitted.2.2.1 omitted.2.1
  · have parsed := X86.Register.present_decodes width right left false absent
    have bounds := (X86.Register.value_bounds width right left false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      change X86.Register.value width right left false % 256 = _
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value width right left false < 256)
    simp only [testBytes, rex, if_neg absent, List.cons_append, List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width right left) from parsed]
    simp only [Option.map, decodeRex absent]
    rfl

theorem alu_step (width : X86.Register.Width) (before after : State) (operation : Alu)
    (destination source : Register)
    (loaded : CodeAt before.memory before.rip (aluBytes width operation destination source))
    (auxiliary : Bool)
    (result : after = match width with
      | .w32 => before.alu32 operation destination source auxiliary
          (aluBytes width operation destination source).length
      | .w64 => before.alu64 operation destination source auxiliary
          (aluBytes width operation destination source).length) :
    Step before after := by
  cases width
  · exact Step.arithmetic (aluBytes .w32 operation destination source) loaded operation destination source
      (aluBytes .w32 operation destination source).length
      (alu_decodes .w32 operation destination source) auxiliary result
  · exact Step.arithmetic64 (aluBytes .w64 operation destination source) loaded operation destination source
      (aluBytes .w64 operation destination source).length
      (alu_decodes .w64 operation destination source) auxiliary result

theorem test_step (width : X86.Register.Width) (before after : State)
    (left right : Register)
    (loaded : CodeAt before.memory before.rip (testBytes width left right))
    (auxiliary : Bool)
    (result : after = match width with
      | .w32 => before.test32 left right auxiliary (testBytes width left right).length
      | .w64 => before.test64 left right auxiliary (testBytes width left right).length) :
    Step before after := by
  cases width
  · exact Step.tested (testBytes .w32 left right) loaded left right
      (testBytes .w32 left right).length (test_decodes .w32 left right) auxiliary result
  · exact Step.tested64 (testBytes .w64 left right) loaded left right
      (testBytes .w64 left right).length (test_decodes .w64 left right) auxiliary result

end Lanius.X86.Machine
