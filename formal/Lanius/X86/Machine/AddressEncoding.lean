import Lanius.X86.Machine.ControlEncoding

namespace Lanius.X86.Machine

open Lanius.X86

def addressModRM (reg rm : Register) : Nat := 128 + reg.val % 8 * 8 + rm.val % 8

def addressSIB (base index : Register) (scale : Fin 4) : Nat := scale.val * 64 + index.val % 8 * 8 + base.val % 8

def addressBytes (destination base : Register) (displacement : BitVec 32) : List UInt8 :=
  [UInt8.ofNat (X86.Register.fields .w64 destination base).encode, 141, UInt8.ofNat (addressModRM destination base)] ++ (if base.val % 8 = 4 then [36] else []) ++ displacementBytes displacement

def indexedFields (destination base index : Register) : X86.Register.Rex := ⟨true, decide (8 ≤ destination.val), decide (8 ≤ index.val), decide (8 ≤ base.val)⟩

def indexedAddressBytes (destination base index : Register) (scale : Fin 4) (displacement : BitVec 32) : List UInt8 :=
  [UInt8.ofNat (indexedFields destination base index).encode, 141, UInt8.ofNat (addressModRM destination ⟨4, by decide⟩), UInt8.ofNat (addressSIB base index scale)] ++ displacementBytes displacement

def ripRelativeBytes (destination : Register) (displacement : BitVec 32) : List UInt8 :=
  [UInt8.ofNat (X86.Register.fields .w64 destination ⟨0, by decide⟩).encode, 141, UInt8.ofNat (destination.val % 8 * 8 + 5)] ++ displacementBytes displacement

private theorem rex_byte (fields : X86.Register.Rex) : (UInt8.ofNat fields.encode).toNat = fields.encode := by
  have bound := fields.encode_bounds.2; rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]

private theorem address_modrm_byte_fields (reg rm : Register) : (UInt8.ofNat (addressModRM reg rm)).toNat / 64 = 2 ∧ (UInt8.ofNat (addressModRM reg rm)).toNat / 8 % 8 = reg.val % 8 ∧ (UInt8.ofNat (addressModRM reg rm)).toNat % 8 = rm.val % 8 := by
  rw [UInt8.toNat_ofNat']; unfold addressModRM; have := reg.isLt; have := rm.isLt; omega

private theorem address_extended (reg : Register) : extendRegister ⟨reg.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ reg.val)) = reg := by
  apply Fin.ext; have bound := reg.isLt; by_cases high : 8 ≤ reg.val <;> simp [extendRegister, high] <;> omega

private theorem modrm_reg_bound (modrm : UInt8) : modrm.toNat / 8 % 8 < 8 := by have bound := UInt8.toNat_lt modrm; omega

private theorem modrm_base_bound (modrm : UInt8) : modrm.toNat % 8 < 8 := by have bound := UInt8.toNat_lt modrm; omega

private theorem address_decode_base_raw (destination base : Register) (displacement : BitVec 32)
    (modrm : UInt8)
    (modrm_fields : modrm.toNat / 64 = 2 ∧ modrm.toNat / 8 % 8 = destination.val % 8 ∧
      modrm.toNat % 8 = base.val % 8) :
    decodeOpcode (X86.Register.fields .w64 destination base) true
      ([141, modrm] ++
        (if base.val % 8 = 4 then [36] else []) ++ displacementBytes displacement) =
      some (.address64
        (extendRegister ⟨modrm.toNat / 8 % 8, modrm_reg_bound modrm⟩
          (X86.Register.fields .w64 destination base).r)
        (extendRegister ⟨modrm.toNat % 8, modrm_base_bound modrm⟩
          (X86.Register.fields .w64 destination base).b)
        none 0 displacement,
        6 + if base.val % 8 = 4 then 1 else 0) := by
  have modrm_bound := UInt8.toNat_lt modrm
  by_cases sib : base.val % 8 = 4
  · simp [decodeOpcode, addressForm, X86.Register.fields, sib, displacement_decodes,
      Alu.ofOpcode?, modrm_fields.1, modrm_fields.2.1, modrm_fields.2.2] <;> omega
  · simp [decodeOpcode, addressForm, X86.Register.fields, sib, displacement_decodes,
      Alu.ofOpcode?, modrm_fields.1, modrm_fields.2.1, modrm_fields.2.2] <;> omega

private theorem address_decode_base (destination base : Register) (displacement : BitVec 32)
    (modrm : UInt8)
    (modrm_fields : modrm.toNat / 64 = 2 ∧ modrm.toNat / 8 % 8 = destination.val % 8 ∧
      modrm.toNat % 8 = base.val % 8) :
    decodeOpcode (X86.Register.fields .w64 destination base) true
      ([141, modrm] ++
        (if base.val % 8 = 4 then [36] else []) ++ displacementBytes displacement) =
      some (.address64 destination base none 0 displacement,
        6 + if base.val % 8 = 4 then 1 else 0) := by
  have destination_ext :
      extendRegister ⟨destination.val % 8, Nat.mod_lt _ (by decide)⟩
        (X86.Register.fields .w64 destination base).r = destination := by
    simpa [X86.Register.fields] using address_extended destination
  have base_ext :
      extendRegister ⟨base.val % 8, Nat.mod_lt _ (by decide)⟩
        (X86.Register.fields .w64 destination base).b = base := by
    simpa [X86.Register.fields] using address_extended base
  have destination_decoded :
      extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩
        (X86.Register.fields .w64 destination base).r = destination := by
    simpa only [modrm_fields.2.1] using destination_ext
  have base_decoded :
      extendRegister ⟨modrm.toNat % 8, by omega⟩
        (X86.Register.fields .w64 destination base).b = base := by
    simpa only [modrm_fields.2.2] using base_ext
  simpa only [destination_decoded, base_decoded] using
    address_decode_base_raw destination base displacement modrm modrm_fields

theorem address_decodes (destination base : Register) (displacement : BitVec 32) :
    decode (addressBytes destination base displacement) =
      some (.address64 destination base none 0 displacement,
        (addressBytes destination base displacement).length) := by
  let fields := X86.Register.fields .w64 destination base
  have parsed : X86.Register.Rex.decode? fields.encode = some fields :=
    X86.Register.Rex.decode_encode fields
  have rexByte := rex_byte fields
  by_cases sib : base.val % 8 = 4
  · rw [show addressBytes destination base displacement =
      [UInt8.ofNat fields.encode, 141, UInt8.ofNat (addressModRM destination base), 36] ++
        displacementBytes displacement by simp [addressBytes, fields, sib]]
    simp only [decode, List.cons_append, List.nil_append, rexByte]
    rw [show X86.Register.Rex.decode? fields.encode = some fields from parsed]
    simp only [Option.map]
    have run := address_decode_base destination base displacement
      (UInt8.ofNat (addressModRM destination base)) (address_modrm_byte_fields destination base)
    simp only [if_pos sib, List.cons_append, List.nil_append] at run
    simp [fields, run]
    rfl
  · rw [show addressBytes destination base displacement =
      [UInt8.ofNat fields.encode, 141, UInt8.ofNat (addressModRM destination base)] ++
        displacementBytes displacement by simp [addressBytes, fields, sib]]
    simp only [decode, List.cons_append, List.nil_append, rexByte]
    rw [show X86.Register.Rex.decode? fields.encode = some fields from parsed]
    simp only [Option.map]
    have run := address_decode_base destination base displacement
      (UInt8.ofNat (addressModRM destination base)) (address_modrm_byte_fields destination base)
    simp only [if_neg sib, List.cons_append, List.nil_append] at run
    simp [fields, run]
    rfl

private theorem address_sib_fields (base index : Register) (scale : Fin 4) :
    let byte := UInt8.ofNat (addressSIB base index scale)
    byte.toNat / 64 = scale.val ∧ byte.toNat / 8 % 8 = index.val % 8 ∧
      byte.toNat % 8 = base.val % 8 := by
  dsimp
  rw [UInt8.toNat_ofNat']
  unfold addressSIB
  have := base.isLt
  have := index.isLt
  omega

private theorem indexed_decode_raw (destination base index : Register) (scale : Fin 4) (displacement : BitVec 32)
    (modrm sib : UInt8) (mf : modrm.toNat / 64 = 2 ∧ modrm.toNat / 8 % 8 = destination.val % 8 ∧ modrm.toNat % 8 = 4)
    (sf : sib.toNat / 64 = scale.val ∧ sib.toNat / 8 % 8 = index.val % 8 ∧ sib.toNat % 8 = base.val % 8)
    (index_not_rsp : index.val ≠ 4) : decodeOpcode (indexedFields destination base index) true
      ([141, modrm, sib] ++ displacementBytes displacement) = some (.address64
        (extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ (indexedFields destination base index).r)
        (extendRegister ⟨sib.toNat % 8, by omega⟩ (indexedFields destination base index).b)
        (some (extendRegister ⟨sib.toNat / 8 % 8, by omega⟩ (indexedFields destination base index).x))
        ⟨sib.toNat / 64, by omega⟩ displacement, 7) := by
  have rule : ¬(index.val % 8 = 4 ∧ !(indexedFields destination base index).x) := by
    intro h
    by_cases high : 8 ≤ index.val
    · simp [indexedFields, high] at h
    · have bound := index.isLt
      simp [indexedFields, high] at h
      apply index_not_rsp
      omega
  simp [decodeOpcode, addressForm, indexedFields, Alu.ofOpcode?, mf.1, mf.2.1, mf.2.2, sf.1, sf.2.1, sf.2.2,
    rule, displacement_decodes] <;> omega

theorem indexed_decodes (destination base index : Register) (scale : Fin 4) (displacement : BitVec 32)
    (index_not_rsp : index.val ≠ 4) : decode (indexedAddressBytes destination base index scale displacement) =
      some (.address64 destination base (some index) scale displacement, (indexedAddressBytes destination base index scale displacement).length) := by
  let fields := indexedFields destination base index
  have parsed := X86.Register.Rex.decode_encode fields; have rexByte := rex_byte fields
  have modrm := address_modrm_byte_fields destination ⟨4, by decide⟩; have sib := address_sib_fields base index scale
  have sib_bound : addressSIB base index scale < 256 := by unfold addressSIB; have := base.isLt; have := index.isLt; omega
  have dr : extendRegister ⟨(UInt8.ofNat (addressModRM destination ⟨4, by decide⟩)).toNat / 8 % 8, by omega⟩ fields.r = destination := by
    simpa only [fields, indexedFields, modrm.2.1] using address_extended destination
  have br : extendRegister ⟨(UInt8.ofNat (addressSIB base index scale)).toNat % 8, by omega⟩ fields.b = base := by
    simpa only [fields, indexedFields, sib.2.2] using address_extended base
  have ir : extendRegister ⟨(UInt8.ofNat (addressSIB base index scale)).toNat / 8 % 8, by omega⟩ fields.x = index := by
    simpa only [fields, indexedFields, sib.2.1] using address_extended index
  have sr : (⟨(UInt8.ofNat (addressSIB base index scale)).toNat / 64, by omega⟩ : Fin 4) = scale := by apply Fin.ext; exact sib.1
  rw [show indexedAddressBytes destination base index scale displacement = [UInt8.ofNat fields.encode, 141,
    UInt8.ofNat (addressModRM destination ⟨4, by decide⟩), UInt8.ofNat (addressSIB base index scale)] ++ displacementBytes displacement by simp [indexedAddressBytes, fields]]
  simp only [decode, List.cons_append, List.nil_append, rexByte]
  rw [show X86.Register.Rex.decode? fields.encode = some fields from parsed]
  simp only [Option.map]
  have run := indexed_decode_raw destination base index scale displacement (UInt8.ofNat (addressModRM destination ⟨4, by decide⟩))
    (UInt8.ofNat (addressSIB base index scale)) modrm sib index_not_rsp
  simp only [List.cons_append, List.nil_append] at run
  have run_actual : decodeOpcode fields true (141 :: UInt8.ofNat (addressModRM destination ⟨4, by decide⟩) ::
      UInt8.ofNat (addressSIB base index scale) :: displacementBytes displacement) =
      some (.address64 destination base (some index) scale displacement, 7) := by
    simpa only [fields, dr, br, ir, sr] using run
  rw [run_actual]
  simp [displacementBytes]

private theorem rip_modrm_fields (destination : Register) :
    let byte := UInt8.ofNat (destination.val % 8 * 8 + 5)
    byte.toNat / 64 = 0 ∧ byte.toNat / 8 % 8 = destination.val % 8 ∧ byte.toNat % 8 = 5 := by
  dsimp; rw [UInt8.toNat_ofNat']; have := destination.isLt; omega

private theorem rip_decode_raw (destination : Register) (displacement : BitVec 32) (modrm : UInt8)
    (mf : modrm.toNat / 64 = 0 ∧ modrm.toNat / 8 % 8 = destination.val % 8 ∧ modrm.toNat % 8 = 5) :
    decodeOpcode (X86.Register.fields .w64 destination ⟨0, by decide⟩) true
      ([141, modrm] ++ displacementBytes displacement) =
      some (.ripRelative (extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩
        (X86.Register.fields .w64 destination ⟨0, by decide⟩).r) displacement, 6) := by
  have bound := UInt8.toNat_lt modrm
  simp [decodeOpcode, addressForm, X86.Register.fields, Alu.ofOpcode?, mf.1, mf.2.1, mf.2.2,
    displacement_decodes] <;> omega

theorem rip_relative_decodes (destination : Register) (displacement : BitVec 32) :
    decode (ripRelativeBytes destination displacement) =
      some (.ripRelative destination displacement, (ripRelativeBytes destination displacement).length) := by
  let fields := X86.Register.fields .w64 destination ⟨0, by decide⟩
  have parsed := X86.Register.Rex.decode_encode fields; have rexByte := rex_byte fields
  have mf := rip_modrm_fields destination
  have dr : extendRegister ⟨(UInt8.ofNat (destination.val % 8 * 8 + 5)).toNat / 8 % 8, modrm_reg_bound _⟩ fields.r = destination := by
    simpa only [fields, X86.Register.fields, mf.2.1] using address_extended destination
  rw [show ripRelativeBytes destination displacement = [UInt8.ofNat fields.encode, 141,
    UInt8.ofNat (destination.val % 8 * 8 + 5)] ++ displacementBytes displacement by simp [ripRelativeBytes, fields]]
  simp only [decode, List.cons_append, List.nil_append, rexByte]
  rw [show X86.Register.Rex.decode? fields.encode = some fields from parsed]
  simp only [Option.map]
  have run := rip_decode_raw destination displacement (UInt8.ofNat (destination.val % 8 * 8 + 5)) mf
  simp only [List.cons_append, List.nil_append] at run
  have run' : decodeOpcode fields true (141 :: UInt8.ofNat (destination.val % 8 * 8 + 5) :: displacementBytes displacement) =
      some (.ripRelative destination displacement, 6) := by simpa only [fields, dr] using run
  rw [run']; simp [displacementBytes]

theorem address_step (before after : State) (destination base : Register) (displacement : BitVec 32) (loaded : CodeAt before.memory before.rip (addressBytes destination base displacement)) (result : after = before.address64 destination base none 0 displacement (addressBytes destination base displacement).length) : Step before after := by exact Step.addressed _ loaded destination base none 0 displacement _ (address_decodes destination base displacement) result
theorem indexed_address_step (before after : State) (destination base index : Register) (scale : Fin 4) (displacement : BitVec 32) (index_not_rsp : index.val ≠ 4) (loaded : CodeAt before.memory before.rip (indexedAddressBytes destination base index scale displacement)) (result : after = before.address64 destination base (some index) scale displacement (indexedAddressBytes destination base index scale displacement).length) : Step before after := by exact Step.addressed _ loaded destination base (some index) scale displacement _ (indexed_decodes destination base index scale displacement index_not_rsp) result
theorem rip_relative_step (before after : State) (destination : Register) (displacement : BitVec 32) (loaded : CodeAt before.memory before.rip (ripRelativeBytes destination displacement)) (result : after = before.ripRelative destination displacement (ripRelativeBytes destination displacement).length) : Step before after := by exact Step.ripAddressed _ loaded destination displacement _ (rip_relative_decodes destination displacement) result

end Lanius.X86.Machine
