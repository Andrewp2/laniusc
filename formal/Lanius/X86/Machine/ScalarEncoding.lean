import Lanius.X86.Machine.Scalar
import Lanius.X86.Machine.ControlEncoding
import Lanius.X86.Encoding

namespace Lanius.X86.Machine

open Lanius.X86

def registerBytes (width : X86.Register.Width) (opcode : Nat) (reg rm : Register) (forceByte : Bool) : List UInt8 := let rex := X86.Register.value width reg rm forceByte; (if rex = 0 then [] else [UInt8.ofNat rex]) ++ [UInt8.ofNat opcode, UInt8.ofNat (Encoding.modRM reg rm)]

def moveBytes (width : X86.Register.Width) (destination source : Register) : List UInt8 := registerBytes width 137 source destination false

def moveInstruction (width : X86.Register.Width) (destination source : Register) : Instruction := match width with | .w32 => .move32 destination source | .w64 => .move64 destination source

def immediateBytes (width : X86.Register.Width) (destination : Register) (low high : BitVec 32) : List UInt8 := let rex := X86.Register.value width 0 destination false; (if rex = 0 then [] else [UInt8.ofNat rex]) ++ [184 + UInt8.ofNat (destination.val % 8)] ++ displacementBytes low ++ (if width = .w64 then displacementBytes high else [])

def immediateInstruction (width : X86.Register.Width) (destination : Register) (low high : BitVec 32) : Instruction := match width with | .w32 => .immediate32 destination low | .w64 => .immediate64 destination (BitVec.ofNat 64 (low.toNat + 4294967296 * high.toNat))

def signExtendBytes (destination source : Register) : List UInt8 := registerBytes .w64 99 destination source false

def zeroExtendByteBytes (destination source : Register) : List UInt8 := let rex := X86.Register.value .w32 destination source (decide (4 ≤ source.val)); (if rex = 0 then [] else [UInt8.ofNat rex]) ++ [15, 182, UInt8.ofNat (Encoding.modRM destination source)]

def setConditionBytes (code : Fin 16) (destination : Register) : List UInt8 := let rex := X86.Register.value .w32 0 destination (decide (4 ≤ destination.val)); (if rex = 0 then [] else [UInt8.ofNat rex]) ++ [15, UInt8.ofNat (144 + code.val), UInt8.ofNat (Encoding.modRM 0 destination)]

def compareBytes (left right : Register) : List UInt8 := registerBytes .w32 57 right left false

def stackBytes (opcode : Nat) (source : Register) : List UInt8 := (if 8 ≤ source.val then [65] else []) ++ [UInt8.ofNat opcode + UInt8.ofNat (source.val % 8)]

def pushBytes (source : Register) : List UInt8 := stackBytes 80 source

def popBytes (destination : Register) : List UInt8 := stackBytes 88 destination

def returnBytes : List UInt8 := [195]

private theorem extended (reg : Register) : extendRegister ⟨reg.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ reg.val)) = reg := by
  apply Fin.ext
  have bound := reg.isLt
  by_cases high : 8 ≤ reg.val <;> simp [extendRegister, high] <;> omega

private theorem modrm_byte (reg rm : Register) : (UInt8.ofNat (Encoding.modRM reg rm)).toNat = Encoding.modRM reg rm := by
  rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (Encoding.modRM_fields reg rm).2.2.2]

private theorem stack_opcode_byte (opcode : Nat) (reg : Register) (bound : opcode + reg.val % 8 < 256) : (UInt8.ofNat opcode + UInt8.ofNat (reg.val % 8)).toNat = opcode + reg.val % 8 := by
  simp only [UInt8.toNat_add, UInt8.toNat_ofNat']
  have opcode_mod : opcode % 256 = opcode := Nat.mod_eq_of_lt (by omega)
  have reg_mod : reg.val % 8 < 8 := Nat.mod_lt _ (by decide)
  simp [opcode_mod]
  omega

private theorem stack_byte (opcode : Nat) (reg : Register) (bound : opcode + reg.val % 8 < 256) : UInt8.ofNat opcode + UInt8.ofNat (reg.val % 8) = UInt8.ofNat (opcode + reg.val % 8) := by
  apply (UInt8.toNat_inj).mp
  rw [stack_opcode_byte opcode reg bound, UInt8.toNat_ofNat']
  simpa [show 2 ^ 8 = 256 by decide] using (Nat.mod_eq_of_lt bound).symm

theorem move_decodes (width : X86.Register.Width) (destination source : Register) : decode (moveBytes width destination source) = some (moveInstruction width destination source, (moveBytes width destination source).length) := by
  let rex := X86.Register.value width source destination false
  have modrm := Encoding.modRM_fields source destination
  have modrmByte := modrm_byte source destination
  have decodeNoRex (source_low : source.val < 8) (destination_low : destination.val < 8) :
      decodeOpcode ⟨false, false, false, false⟩ false
          [137, UInt8.ofNat (Encoding.modRM source destination)] =
        some (.move32 destination source, 2) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ false = destination := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : destination.val < 8)]
    have source_ext :
        extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩ false = source := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : source.val < 8)]
    simp [decodeOpcode, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
      destination_ext, source_ext]
  have decodeRex (present : rex ≠ 0) :
      decodeOpcode (X86.Register.fields width source destination) true
          [137, UInt8.ofNat (Encoding.modRM source destination)] =
        some (moveInstruction width destination source, 2) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width source destination).b = destination := by
      simpa [X86.Register.fields] using extended destination
    have source_ext :
        extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width source destination).r = source := by
      simpa [X86.Register.fields] using extended source
    cases width <;>
      simp [decodeOpcode, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
        moveInstruction, X86.Register.fields, extended]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width source destination false).mp absent
    have narrow := omitted.1
    subst width
    simpa [moveBytes, registerBytes, rex, absent, decode,
      X86.Register.Rex.decode?, moveInstruction] using
      decodeNoRex omitted.2.1 omitted.2.2.1
  · have parsed := X86.Register.present_decodes width source destination false absent
    have bounds := (X86.Register.value_bounds width source destination false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      change X86.Register.value width source destination false % 256 = _
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value width source destination false < 256)
    simp only [moveBytes, registerBytes, rex, if_neg absent, List.cons_append,
      List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width source destination) from parsed]
    simp [decodeRex absent]

private theorem immediate64_bytes (low high : BitVec 32) : immediate64? (displacementBytes low ++ displacementBytes high) = some (BitVec.ofNat 64 (low.toNat + 4294967296 * high.toNat)) := by
  simp [immediate64?, displacementBytes, Control.displacement?, readBytes]
  have low_read := congrArg BitVec.toNat (readBytes_wordBytes low)
  have high_read := congrArg BitVec.toNat (readBytes_wordBytes high)
  simp [readBytes] at low_read high_read
  rw [low_read, high_read]

theorem immediate_decodes (width : X86.Register.Width) (destination : Register) (low high : BitVec 32) : decode (immediateBytes width destination low high) = some (immediateInstruction width destination low high, (immediateBytes width destination low high).length) := by
  let rex := X86.Register.value width 0 destination false
  have opcodeByte' :
      (184 + UInt8.ofNat (destination.val % 8)).toNat = 184 + destination.val % 8 := by
    simp only [UInt8.toNat_add, UInt8.toNat_ofNat']
    have h184 : UInt8.toNat 184 = 184 := by decide
    simp [h184]
    omega
  have notRex : ¬(64 ≤ 184 + destination.val % 8 ∧ 184 + destination.val % 8 < 80) := by omega
  have not195 : 184 + destination.val % 8 ≠ 195 := by omega
  have not232 : 184 + destination.val % 8 ≠ 232 := by omega
  have not233 : 184 + destination.val % 8 ≠ 233 := by omega
  have notPush : ¬(80 ≤ 184 + destination.val % 8 ∧ 184 + destination.val % 8 < 88) := by omega
  have notPop : ¬(88 ≤ 184 + destination.val % 8 ∧ 184 + destination.val % 8 < 96) := by omega
  have immediateRange : 184 ≤ 184 + destination.val % 8 ∧
      184 + destination.val % 8 < 192 := by omega
  have decodeNoRex (destination_low : destination.val < 8) :
      decodeOpcode ⟨false, false, false, false⟩ false
          ([184 + UInt8.ofNat (destination.val % 8)] ++ displacementBytes low) =
        some (.immediate32 destination low, 5) := by
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ false = destination := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : destination.val < 8)]
    simpa [decodeOpcode, opcodeByte', not195, not232, not233, notPush, notPop, immediateRange, displacement_decodes, destination_ext, extended]
      
  have decodeRex (present : rex ≠ 0) :
      decodeOpcode (X86.Register.fields width 0 destination) true
          ([184 + UInt8.ofNat (destination.val % 8)] ++ displacementBytes low ++
            (if width = .w64 then displacementBytes high else [])) =
        some (immediateInstruction width destination low high,
          (if width = .w64 then 9 else 5)) := by
    cases width <;>
      simp [decodeOpcode, opcodeByte', not195, not232, not233, notPush, notPop, immediateRange, displacement_decodes, immediate64_bytes, immediateInstruction, X86.Register.fields, extended]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width 0 destination false).mp absent
    have narrow := omitted.1
    subst width
    have decoded := decodeNoRex omitted.2.2.1
    simp only [List.cons_append] at decoded
    simpa [immediateBytes, rex, absent, decode, X86.Register.Rex.decode?, opcodeByte',
      notRex, not195, not232, not233, notPush, notPop, immediateRange,
      immediateInstruction, displacementBytes, wordBytes] using decoded
  · have parsed := X86.Register.present_decodes width 0 destination false absent
    have bounds := (X86.Register.value_bounds width 0 destination false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      change X86.Register.value width 0 destination false % 256 = _
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value width 0 destination false < 256)
    simp only [immediateBytes, rex, if_neg absent, List.cons_append, List.nil_append,
      decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width 0 destination) from parsed]
    have decoded := decodeRex absent
    simp only [List.nil_append, List.cons_append] at decoded
    cases width with
    | w32 =>
      have d : decodeOpcode (X86.Register.fields .w32 0 destination) true ([184 + UInt8.ofNat (destination.val % 8)] ++ displacementBytes low) = some (.immediate32 destination low, 5) := by simpa [immediateInstruction] using decoded
      change Option.map (fun x : Instruction × Nat => (x.1, x.2 + 1)) (decodeOpcode (X86.Register.fields .w32 0 destination) true ([184 + UInt8.ofNat (destination.val % 8)] ++ displacementBytes low)) = _
      rw [d]; simp [immediateInstruction, displacementBytes, wordBytes]
    | w64 =>
      have d : decodeOpcode (X86.Register.fields .w64 0 destination) true ([184 + UInt8.ofNat (destination.val % 8)] ++ displacementBytes low ++ displacementBytes high) = some (.immediate64 destination (BitVec.ofNat 64 (low.toNat + 4294967296 * high.toNat)), 9) := by simpa [immediateInstruction] using decoded
      change Option.map (fun x : Instruction × Nat => (x.1, x.2 + 1)) (decodeOpcode (X86.Register.fields .w64 0 destination) true ([184 + UInt8.ofNat (destination.val % 8)] ++ displacementBytes low ++ displacementBytes high)) = _
      rw [d]; simp [immediateInstruction, displacementBytes, wordBytes]

theorem signExtend_decodes (destination source : Register) : decode (signExtendBytes destination source) = some (.signExtend32 destination source, (signExtendBytes destination source).length) := by
  let rex := X86.Register.value .w64 destination source false
  have present : rex ≠ 0 := by
    intro absent
    have impossible := (X86.Register.omitted_iff .w64 destination source false).mp absent
    cases impossible.1
  have parsed := X86.Register.present_decodes .w64 destination source false present
  have bounds := (X86.Register.value_bounds .w64 destination source false).resolve_left present
  have byte : (UInt8.ofNat rex).toNat = rex := by
    dsimp [rex]
    rw [UInt8.toNat_ofNat']
    change X86.Register.value .w64 destination source false % 256 = _
    exact Nat.mod_eq_of_lt (by omega : X86.Register.value .w64 destination source false < 256)
  have modrm := Encoding.modRM_fields destination source
  have modrmByte := modrm_byte destination source
  have raw : decodeOpcode (X86.Register.fields .w64 destination source) true
      [99, UInt8.ofNat (Encoding.modRM destination source)] =
      some (.signExtend32 destination source, 2) := by
    have alunone : Alu.ofOpcode? 99 = none := by decide
    simp [decodeOpcode, alunone, modrmByte, modrm.1, modrm.2.1, modrm.2.2, X86.Register.fields, extended]
  simp only [signExtendBytes, registerBytes, rex, if_neg present, List.cons_append,
    List.nil_append, decode, byte]
  rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields .w64 destination source) from parsed]
  simp [raw]

theorem zeroExtendByte_decodes (destination source : Register) : decode (zeroExtendByteBytes destination source) = some (.zeroExtendByte destination source, (zeroExtendByteBytes destination source).length) := by
  let force := decide (4 ≤ source.val)
  let rex := X86.Register.value .w32 destination source force
  have modrm := Encoding.modRM_fields destination source
  have modrmByte := modrm_byte destination source
  have raw (fields : X86.Register.Rex) (present : Bool)
      (destination_ext : extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ fields.r = destination)
      (source_ext : extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩ fields.b = source)
      (source_small : present = false → source.val < 4) :
      decodeOpcode fields present [15, 182, UInt8.ofNat (Encoding.modRM destination source)] =
        some (.zeroExtendByte destination source, 3) := by
    have alunone : Alu.ofOpcode? 15 = none := by decide
    cases present with
    | false =>
      have small := source_small rfl
      have small_mod : source.val % 8 < 4 := by omega
      simp [decodeOpcode, escapedForm, byteRegister?, alunone, modrmByte, modrm.1,
        modrm.2.1, modrm.2.2, destination_ext, source_ext, small_mod]
    | true =>
      simp [decodeOpcode, escapedForm, byteRegister?, alunone, modrmByte, modrm.1,
        modrm.2.1, modrm.2.2, destination_ext, source_ext]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff .w32 destination source force).mp absent
    have source_small : source.val < 4 := by
      have h := omitted.2.2.2
      simp [force] at h
      omega
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ false = destination := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : destination.val < 8)]
    have source_ext :
        extendRegister ⟨source.val % 8, Nat.mod_lt _ (by omega)⟩ false = source := by
      apply Fin.ext
      have bound := source.isLt
      have low : source.val < 8 := by omega
      simp [extendRegister, Nat.mod_eq_of_lt low]
    simpa [zeroExtendByteBytes, rex, absent, force, decode, X86.Register.Rex.decode?,
      modrmByte] using raw ⟨false, false, false, false⟩ false destination_ext source_ext
        (fun _ => source_small)
  · have parsed := X86.Register.present_decodes .w32 destination source force absent
    have bounds := (X86.Register.value_bounds .w32 destination source force).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value .w32 destination source force < 256)
    have destination_ext :
        extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields .w32 destination source).r = destination := by
      simpa [X86.Register.fields] using extended destination
    have source_ext :
        extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields .w32 destination source).b = source := by
      simpa [X86.Register.fields] using extended source
    simp only [zeroExtendByteBytes, rex, force, if_neg absent, List.cons_append,
      List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields .w32 destination source) from parsed]
    simp [raw, destination_ext, source_ext]

theorem setCondition_decodes (code : Fin 16) (destination : Register) :
    decode (setConditionBytes code destination) =
      some (.setCondition code destination, (setConditionBytes code destination).length) := by
  let force := decide (4 ≤ destination.val)
  let rex := X86.Register.value .w32 0 destination force
  have modrm := Encoding.modRM_fields 0 destination
  have modrmByte := modrm_byte 0 destination
  have opcode_mod : (144 + code.val) % 256 = 144 + code.val := by omega
  have raw (fields : X86.Register.Rex) (present : Bool) (destination_ext : extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ fields.b = destination) (small : present = false → destination.val < 4) :
      decodeOpcode fields present [15, UInt8.ofNat (144 + code.val), UInt8.ofNat (Encoding.modRM 0 destination)] =
        some (.setCondition code destination, 3) := by
    have code_range : 144 ≤ 144 + code.val ∧ 144 + code.val < 160 := by omega
    have alunone : Alu.ofOpcode? 15 = none := by decide
    cases present with
    | false =>
      have small' := small rfl
      have small_mod : destination.val % 8 < 4 := by omega
      simp [decodeOpcode, escapedForm, byteRegister?, alunone, code_range,
        opcode_mod, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
        destination_ext, small_mod]
    | true =>
      have byteReg : byteRegister? fields true
          (UInt8.ofNat (Encoding.modRM 0 destination)) = some destination := by
        simp [byteRegister?, modrmByte, modrm.2.2, destination_ext]
      simp [decodeOpcode, escapedForm, alunone, code_range, opcode_mod,
        modrmByte, modrm.1, modrm.2.1, modrm.2.2, destination_ext, byteReg]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff .w32 0 destination force).mp absent
    have destination_ext : extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩ false = destination := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : destination.val < 8)]
    have decoded := raw ⟨false, false, false, false⟩ false destination_ext (by
      have := omitted.2.2.2
      simp [force] at this
      omega)
    simpa [setConditionBytes, rex, force, absent, decode,
      X86.Register.Rex.decode?, opcode_mod] using decoded
  · have parsed := X86.Register.present_decodes .w32 0 destination force absent
    have bounds := (X86.Register.value_bounds .w32 0 destination force).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value .w32 0 destination force < 256)
    have destination_ext : extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩
        (X86.Register.fields .w32 0 destination).b = destination := by
      simpa [X86.Register.fields] using extended destination
    simp only [setConditionBytes, rex, force, if_neg absent, List.cons_append,
      List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields .w32 0 destination) from parsed]
    have byteReg : byteRegister? (X86.Register.fields .w32 0 destination) true
        (UInt8.ofNat (Encoding.modRM 0 destination)) = some destination := by
      simp [byteRegister?, modrmByte, modrm.2.2, destination_ext]
    simpa [byteReg] using raw (X86.Register.fields .w32 0 destination) true destination_ext (by simp)

theorem compare_decodes (left right : Register) :
    decode (compareBytes left right) =
      some (.compare32 left right, (compareBytes left right).length) := by
  let rex := X86.Register.value .w32 right left false
  have modrm := Encoding.modRM_fields right left
  have modrmByte := modrm_byte right left
  have raw (present : Bool) (fields : X86.Register.Rex)
      (left_ext : extendRegister ⟨left.val % 8, Nat.mod_lt _ (by decide)⟩ fields.b = left)
      (right_ext : extendRegister ⟨right.val % 8, Nat.mod_lt _ (by decide)⟩ fields.r = right)
      (noWidth : fields.w = false) :
      decodeOpcode fields present [57, UInt8.ofNat (Encoding.modRM right left)] =
        some (.compare32 left right, 2) := by
    simp [decodeOpcode, modrmByte, modrm.1, modrm.2.1, modrm.2.2,
      left_ext, right_ext, noWidth]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff .w32 right left false).mp absent
    have left_ext : extendRegister ⟨left.val % 8, Nat.mod_lt _ (by decide)⟩ false = left := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : left.val < 8)]
    have right_ext : extendRegister ⟨right.val % 8, Nat.mod_lt _ (by decide)⟩ false = right := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt (by omega : right.val < 8)]
    rcases omitted with ⟨_, right_low, left_low, _⟩
    simpa [compareBytes, registerBytes, rex, absent, decode, X86.Register.Rex.decode?] using
      raw false ⟨false, false, false, false⟩ left_ext right_ext rfl
  · have parsed := X86.Register.present_decodes .w32 right left false absent
    have bounds := (X86.Register.value_bounds .w32 right left false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value .w32 right left false < 256)
    have left_ext : extendRegister ⟨left.val % 8, Nat.mod_lt _ (by decide)⟩
        (X86.Register.fields .w32 right left).b = left := by
      simpa [X86.Register.fields] using extended left
    have right_ext : extendRegister ⟨right.val % 8, Nat.mod_lt _ (by decide)⟩
        (X86.Register.fields .w32 right left).r = right := by
      simpa [X86.Register.fields] using extended right
    simp only [compareBytes, registerBytes, rex, if_neg absent, List.cons_append,
      List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields .w32 right left) from parsed]
    simpa using raw true (X86.Register.fields .w32 right left) left_ext right_ext rfl

theorem compare32_flags (before : State) (left right : Register) (size : Nat) :
    (before.compare32 left right size).flags =
      subtractFlags before.flags ((before.registers left).setWidth 32)
        ((before.registers right).setWidth 32) := rfl

private theorem stack_decodes (opcode : Nat) (source : Register) (target : Instruction) (spec : (opcode = 80 ∧ target = .push64 source) ∨ (opcode = 88 ∧ target = .pop64 source)) : decode (stackBytes opcode source) = some (target, (stackBytes opcode source).length) := by
  rcases spec with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  · by_cases high : 8 ≤ source.val
    · have ext : extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩ true = source := by simpa [high] using extended source
      have range : 80 ≤ 80 + source.val % 8 ∧ 80 + source.val % 8 < 88 := by omega
      have opcodeMod : (80 + source.val % 8) % 256 = 80 + source.val % 8 := Nat.mod_eq_of_lt (by omega)
      have not195 : 80 + source.val % 8 ≠ 195 := by omega
      have not232 : 80 + source.val % 8 ≠ 232 := by omega
      have not233 : 80 + source.val % 8 ≠ 233 := by omega
      have parsed : X86.Register.Rex.decode? 65 = some ⟨false, false, false, true⟩ := by decide
      have raw : decodeOpcode ⟨false, false, false, true⟩ true [UInt8.ofNat 80 + UInt8.ofNat (source.val % 8)] = some (.push64 source, 1) := by
        rw [stack_byte 80 source (by omega)]
        simp [decodeOpcode, range, ext, opcodeMod, not195, not232, not233]
      simp only [stackBytes, if_pos high, List.cons_append, List.nil_append, decode]
      have parsed' : X86.Register.Rex.decode? (UInt8.toNat (65 : UInt8)) = some ⟨false, false, false, true⟩ := by simpa using parsed
      rw [parsed']; change Option.map (fun x : Instruction × Nat => (x.1, x.2 + 1)) (decodeOpcode ⟨false, false, false, true⟩ true [UInt8.ofNat 80 + UInt8.ofNat (source.val % 8)]) = _
      rw [raw]; rfl
    · have low : source.val < 8 := by omega
      have ext : extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩ false = source := by apply Fin.ext; simp [extendRegister, Nat.mod_eq_of_lt low]
      have range : 80 ≤ 80 + source.val % 8 ∧ 80 + source.val % 8 < 88 := by omega
      have opcodeMod : (80 + source.val % 8) % 256 = 80 + source.val % 8 := Nat.mod_eq_of_lt (by omega)
      have notRex : ¬(64 ≤ 80 + source.val % 8 ∧ 80 + source.val % 8 < 80) := by omega
      have not195 : 80 + source.val % 8 ≠ 195 := by omega
      have not232 : 80 + source.val % 8 ≠ 232 := by omega
      have not233 : 80 + source.val % 8 ≠ 233 := by omega
      have raw : decodeOpcode ⟨false, false, false, false⟩ false [UInt8.ofNat 80 + UInt8.ofNat (source.val % 8)] = some (.push64 source, 1) := by
        rw [stack_byte 80 source (by omega)]
        simp [decodeOpcode, range, ext, opcodeMod, not195, not232, not233]
      simp only [stackBytes, if_neg high, List.nil_append, decode]
      have sum : (UInt8.ofNat 80 + UInt8.ofNat (source.val % 8)).toNat = 80 + source.val % 8 := stack_opcode_byte 80 source (by omega)
      simp only [sum]
      have no_rex : X86.Register.Rex.decode? (80 + source.val % 8) = none := by simp [X86.Register.Rex.decode?, notRex]
      rw [no_rex]; exact raw
  · by_cases high : 8 ≤ source.val
    · have ext : extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩ true = source := by simpa [high] using extended source
      have range : 88 ≤ 88 + source.val % 8 ∧ 88 + source.val % 8 < 96 := by omega
      have opcodeMod : (88 + source.val % 8) % 256 = 88 + source.val % 8 := Nat.mod_eq_of_lt (by omega)
      have not195 : 88 + source.val % 8 ≠ 195 := by omega
      have not232 : 88 + source.val % 8 ≠ 232 := by omega
      have not233 : 88 + source.val % 8 ≠ 233 := by omega
      have notPush : ¬(80 ≤ 88 + source.val % 8 ∧ 88 + source.val % 8 < 88) := by omega
      have parsed : X86.Register.Rex.decode? 65 = some ⟨false, false, false, true⟩ := by decide
      have raw : decodeOpcode ⟨false, false, false, true⟩ true [UInt8.ofNat 88 + UInt8.ofNat (source.val % 8)] = some (.pop64 source, 1) := by
        rw [stack_byte 88 source (by omega)]
        simp [decodeOpcode, range, ext, opcodeMod, not195, not232, not233, notPush]
      simp only [stackBytes, if_pos high, List.cons_append, List.nil_append, decode]
      have parsed' : X86.Register.Rex.decode? (UInt8.toNat (65 : UInt8)) = some ⟨false, false, false, true⟩ := by simpa using parsed
      rw [parsed']; change Option.map (fun x : Instruction × Nat => (x.1, x.2 + 1)) (decodeOpcode ⟨false, false, false, true⟩ true [UInt8.ofNat 88 + UInt8.ofNat (source.val % 8)]) = _
      rw [raw]; rfl
    · have low : source.val < 8 := by omega
      have ext : extendRegister ⟨source.val % 8, Nat.mod_lt _ (by decide)⟩ false = source := by apply Fin.ext; simp [extendRegister, Nat.mod_eq_of_lt low]
      have range : 88 ≤ 88 + source.val % 8 ∧ 88 + source.val % 8 < 96 := by omega
      have opcodeMod : (88 + source.val % 8) % 256 = 88 + source.val % 8 := Nat.mod_eq_of_lt (by omega)
      have notRex : ¬(64 ≤ 88 + source.val % 8 ∧ 88 + source.val % 8 < 80) := by omega
      have not195 : 88 + source.val % 8 ≠ 195 := by omega
      have not232 : 88 + source.val % 8 ≠ 232 := by omega
      have not233 : 88 + source.val % 8 ≠ 233 := by omega
      have notPush : ¬(80 ≤ 88 + source.val % 8 ∧ 88 + source.val % 8 < 88) := by omega
      have raw : decodeOpcode ⟨false, false, false, false⟩ false [UInt8.ofNat 88 + UInt8.ofNat (source.val % 8)] = some (.pop64 source, 1) := by
        rw [stack_byte 88 source (by omega)]
        simp [decodeOpcode, range, ext, opcodeMod, not195, not232, not233, notPush]
      simp only [stackBytes, if_neg high, List.nil_append, decode]
      have sum : (UInt8.ofNat 88 + UInt8.ofNat (source.val % 8)).toNat = 88 + source.val % 8 := stack_opcode_byte 88 source (by omega)
      simp only [sum]
      have no_rex : X86.Register.Rex.decode? (88 + source.val % 8) = none := by simp [X86.Register.Rex.decode?, notRex]
      rw [no_rex]; exact raw

theorem push_decodes (source : Register) : decode (pushBytes source) = some (.push64 source, (pushBytes source).length) := stack_decodes 80 source (.push64 source) (Or.inl ⟨rfl, rfl⟩)

theorem pop_decodes (destination : Register) : decode (popBytes destination) = some (.pop64 destination, (popBytes destination).length) := stack_decodes 88 destination (.pop64 destination) (Or.inr ⟨rfl, rfl⟩)

theorem return_decodes : decode returnBytes = some (.returnNear, returnBytes.length) := by
  simp [returnBytes, decode, decodeOpcode, X86.Register.Rex.decode?]

private theorem decoded_step (before after : State) (bytes : List UInt8) (instruction : Instruction) (size : Nat) (loaded : CodeAt before.memory before.rip bytes) (decoded : decode bytes = some (instruction, size)) (result : after = execute instruction size before) : Step before after := Step.decoded bytes loaded instruction size decoded result

theorem move_step (before after : State) (width : X86.Register.Width) (destination source : Register) (loaded : CodeAt before.memory before.rip (moveBytes width destination source)) (result : after = execute (moveInstruction width destination source) (moveBytes width destination source).length before) : Step before after := by exact decoded_step before after _ _ _ loaded (move_decodes width destination source) result

theorem immediate_step (before after : State) (width : X86.Register.Width) (destination : Register) (low high : BitVec 32) (loaded : CodeAt before.memory before.rip (immediateBytes width destination low high)) (result : after = execute (immediateInstruction width destination low high) (immediateBytes width destination low high).length before) : Step before after := by exact decoded_step before after _ _ _ loaded (immediate_decodes width destination low high) result

theorem signExtend_step (before after : State) (destination source : Register) (loaded : CodeAt before.memory before.rip (signExtendBytes destination source)) (result : after = execute (.signExtend32 destination source) (signExtendBytes destination source).length before) : Step before after := by exact decoded_step before after _ _ _ loaded (signExtend_decodes destination source) result

theorem zeroExtendByte_step (before after : State) (destination source : Register) (loaded : CodeAt before.memory before.rip (zeroExtendByteBytes destination source)) (result : after = execute (.zeroExtendByte destination source) (zeroExtendByteBytes destination source).length before) : Step before after := by exact decoded_step before after _ _ _ loaded (zeroExtendByte_decodes destination source) result

theorem setCondition_step (before after : State) (code : Fin 16) (destination : Register)
    (loaded : CodeAt before.memory before.rip (setConditionBytes code destination))
    (result : after = execute (.setCondition code destination)
      (setConditionBytes code destination).length before) :
    Step before after := by
  exact decoded_step before after _ _ _ loaded (setCondition_decodes code destination) result

theorem compare_step (before after : State) (left right : Register)
    (loaded : CodeAt before.memory before.rip (compareBytes left right))
    (result : after = execute (.compare32 left right)
      (compareBytes left right).length before) :
    Step before after := by
  exact decoded_step before after _ _ _ loaded (compare_decodes left right) result

theorem push_step (before after : State) (source : Register) (loaded : CodeAt before.memory before.rip (pushBytes source)) (result : after = execute (.push64 source) (pushBytes source).length before) : Step before after := by exact decoded_step before after _ _ _ loaded (push_decodes source) result

theorem pop_step (before after : State) (destination : Register) (loaded : CodeAt before.memory before.rip (popBytes destination)) (result : after = execute (.pop64 destination) (popBytes destination).length before) : Step before after := by exact decoded_step before after _ _ _ loaded (pop_decodes destination) result

theorem return_step (before after : State) (loaded : CodeAt before.memory before.rip returnBytes) (result : after = execute .returnNear returnBytes.length before) : Step before after := by exact decoded_step before after _ _ _ loaded return_decodes result

end Lanius.X86.Machine
