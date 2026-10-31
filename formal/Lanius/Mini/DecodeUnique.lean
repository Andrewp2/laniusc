import Lanius.X86.Machine.Scalar

/-! `decode` reads only the bytes of the instruction it returns. So two byte
lists loaded at the same address that both decode give the same instruction
and size: `Step` has no freedom in what it decodes. -/

namespace Lanius.X86.Machine

/-- `f` returns a size `k` that counts `offset` bytes before its input and
reads only the first `k - offset` input bytes. -/
def Reads (f : List UInt8 → Option (α × Nat)) (offset : Nat) : Prop :=
  ∀ bytes x k, f bytes = some (x, k) →
    offset ≤ k ∧ k ≤ bytes.length + offset ∧ ∀ tail, f (bytes.take (k - offset) ++ tail) = some (x, k)

theorem displacement_reads {bytes : List UInt8} {d : BitVec 32}
    (h : Control.displacement? bytes = some d) :
    4 ≤ bytes.length ∧ ∀ tail, Control.displacement? (bytes.take 4 ++ tail) = some d := by
  rcases bytes with _ | ⟨a, _ | ⟨b, _ | ⟨c, _ | ⟨e, rest⟩⟩⟩⟩ <;>
    simp_all [Control.displacement?]

theorem displacement_take {bytes : List UInt8} {d : BitVec 32} {n : Nat} (big : 4 ≤ n)
    (h : Control.displacement? bytes = some d) (tail : List UInt8) :
    Control.displacement? (bytes.take n ++ tail) = some d := by
  rcases bytes with _ | ⟨a, _ | ⟨b, _ | ⟨c, _ | ⟨e, rest⟩⟩⟩⟩ <;>
    simp [Control.displacement?] at h
  obtain ⟨n, rfl⟩ : ∃ m, n = m + 4 := ⟨n - 4, by omega⟩
  simp [Control.displacement?, List.take_succ_cons, h]


theorem memoryForm_reads (rex : X86.Register.Rex) (op : Nat) (modrm : UInt8) :
    Reads (memoryForm rex op modrm) (if op = 4022 then 3 else 2) := by
  intro rest x k h
  have hm : modrm.toNat / 64 = 2 := by
    by_cases hm : modrm.toNat / 64 = 2
    · exact hm
    · simp [memoryForm, hm] at h
  by_cases hs : modrm.toNat % 8 = 4
  · rcases rest with _ | ⟨b, rem⟩
    · simp [memoryForm, hm, hs] at h
    by_cases hb : b = 36
    · subst hb
      have hx : rex.x = false := by
        cases hx : rex.x
        · rfl
        · simp [memoryForm, hm, hs, hx] at h
      cases hd : Control.displacement? rem with
      | none => simp [memoryForm, hm, hs, hx, hd] at h
      | some d =>
        obtain ⟨len, take⟩ := displacement_reads hd
        have same : ∀ t, memoryForm rex op modrm ((36 :: rem).take 5 ++ t) = memoryForm rex op modrm (36 :: rem) := by
          intro t
          simp [memoryForm, hm, hs, hx, hd, take]
        have h0 := h
        simp [memoryForm, hm, hs, hx, hd] at h
        have hk : k = 5 + (if op = 4022 then 3 else 2) := by
          repeat' split at h
          all_goals simp_all
        refine ⟨by rw [hk]; omega, by rw [hk, List.length_cons]; omega, fun t => ?_⟩
        rw [show k - (if op = 4022 then 3 else 2) = 5 by omega, same, h0]
    · simp [memoryForm, hm, hs, hb] at h
  · cases hd : Control.displacement? rest with
    | none => simp [memoryForm, hm, hs, hd] at h
    | some d =>
      obtain ⟨len, take⟩ := displacement_reads hd
      have same : ∀ t, memoryForm rex op modrm (rest.take 4 ++ t) = memoryForm rex op modrm rest := by
        intro t
        simp [memoryForm, hm, hs, hd, take]
      have h0 := h
      simp [memoryForm, hm, hs, hd] at h
      have hk : k = 4 + (if op = 4022 then 3 else 2) := by
        repeat' split at h
        all_goals simp_all
      refine ⟨by rw [hk]; omega, by rw [hk]; omega, fun t => ?_⟩
      rw [show k - (if op = 4022 then 3 else 2) = 4 by omega, same, h0]

theorem immediate64_reads {bytes : List UInt8} {v : BitVec 64} (h : immediate64? bytes = some v) :
    8 ≤ bytes.length ∧ ∀ tail, immediate64? (bytes.take 8 ++ tail) = some v := by
  rcases bytes with _ | ⟨a, _ | ⟨b, _ | ⟨c, _ | ⟨e, _ | ⟨f, _ | ⟨g, _ | ⟨i, _ | ⟨j, rest⟩⟩⟩⟩⟩⟩⟩⟩ <;>
    simp_all [immediate64?, Control.displacement?]

theorem addressForm_reads (rex : X86.Register.Rex) (modrm : UInt8) : Reads (addressForm rex modrm) 2 := by
  intro rest x k h
  have hw : rex.w = true := by
    cases hw : rex.w
    · simp [addressForm, hw] at h
    · rfl
  by_cases hr : modrm.toNat / 64 = 0 ∧ modrm.toNat % 8 = 5
  · cases hd : Control.displacement? rest with
    | none => simp [addressForm, hw, hr, hd] at h
    | some d =>
      obtain ⟨len, take⟩ := displacement_reads hd
      have h0 := h
      simp [addressForm, hw, hr, hd] at h
      obtain ⟨-, rfl⟩ := h
      refine ⟨by omega, by omega, fun t => ?_⟩
      rw [h0.symm]
      simp [addressForm, hw, hr, hd, take]
  · have hm : modrm.toNat / 64 = 2 := by
      by_cases hm : modrm.toNat / 64 = 2
      · exact hm
      · simp [addressForm, hw, hm] at h
        exact (hr ⟨by omega, h.1.2⟩).elim
    by_cases hs : modrm.toNat % 8 = 4
    · rcases rest with _ | ⟨sib, rem⟩
      · simp [addressForm, hw, hm, hs] at h
      cases hd : Control.displacement? rem with
      | none => simp [addressForm, hw, hm, hs, hd] at h
      | some d =>
        obtain ⟨len, take⟩ := displacement_reads hd
        have h0 := h
        simp [addressForm, hw, hm, hs, hd] at h
        obtain ⟨-, rfl⟩ := h
        refine ⟨by omega, by simp; omega, fun t => ?_⟩
        rw [h0.symm]
        simp [addressForm, hw, hm, hs, hd, take]
    · cases hd : Control.displacement? rest with
      | none => simp [addressForm, hw, hm, hs, hd] at h
      | some d =>
        obtain ⟨len, take⟩ := displacement_reads hd
        have h0 := h
        simp [addressForm, hw, hm, hs, hd] at h
        obtain ⟨-, rfl⟩ := h
        refine ⟨by omega, by omega, fun t => ?_⟩
        rw [h0.symm]
        simp [addressForm, hw, hm, hs, hd, take]


theorem bind_size {o : Option α} {f : α → Instruction} {n : Nat} {x : Instruction} {k : Nat}
    (h : (o.bind fun a => some (f a, n)) = some (x, k)) : k = n := by
  cases o <;> simp_all

theorem escapedForm_reads (rex : X86.Register.Rex) (present : Bool) : Reads (escapedForm rex present) 1 := by
  intro bytes x k h
  rcases bytes with _ | ⟨op, _ | ⟨modrm, rem⟩⟩
  · simp [escapedForm] at h
  · simp [escapedForm] at h
  have h0 := h
  by_cases cc : 144 ≤ op.toNat ∧ op.toNat < 160
  · have hk : k = 3 := by
      simp [escapedForm, cc] at h
      exact bind_size h.2
    subst hk
    refine ⟨by omega, by simp, fun t => ?_⟩
    rw [← h0]
    simp [escapedForm, cc]
  by_cases c182 : op.toNat = 182
  · by_cases reg : modrm.toNat / 64 = 3
    · have hk : k = 3 := by
        simp [escapedForm, c182, reg] at h
        exact bind_size h
      subst hk
      refine ⟨by omega, by simp, fun t => ?_⟩
      rw [← h0]
      simp [escapedForm, cc, c182, reg]
    · have inner : memoryForm rex 4022 modrm rem = some (x, k) := by
        simpa [escapedForm, cc, c182, reg] using h
      obtain ⟨low, high, take⟩ := memoryForm_reads rex 4022 modrm rem x k inner
      simp only [if_pos] at low high take
      refine ⟨by omega, by simp; omega, fun t => ?_⟩
      rw [← h0]
      have := take t
      simp only [show k - 1 = (k - 3) + 2 by omega, List.take_succ_cons, List.cons_append]
      simp [escapedForm, cc, c182, reg, this, inner]
  by_cases c175 : op.toNat = 175
  · have reg : modrm.toNat / 64 = 3 := by
      by_cases reg : modrm.toNat / 64 = 3
      · exact reg
      · simp [escapedForm, cc, c175, reg] at h
    have hk : k = 3 := by
      simp [escapedForm, cc, c175, reg] at h
      omega
    subst hk
    refine ⟨by omega, by simp, fun t => ?_⟩
    rw [← h0]
    simp [escapedForm, cc, c175, reg]
  · simp only [escapedForm, cc, c182, c175, dite_false, if_false] at h
    split at h
    · rename_i c d size branch
      simp at h
      obtain ⟨rfl, rfl⟩ := h
      simp [Control.decode] at branch
      have c5 : op.toNat ≠ 5 := by intro c5; simp [c5] at branch
      have c11 : op.toNat ≠ 11 := by intro c11; simp [c11] at branch
      have cond : 128 ≤ op.toNat ∧ op.toNat < 144 := by
        by_cases cond : 128 ≤ op.toNat ∧ op.toNat < 144
        · exact cond
        · simp [c5, c11, cond] at branch
      cases hd : Control.displacement? (modrm :: rem) with
      | none => simp [c5, c11, cond, hd] at branch
      | some w =>
        simp [c5, c11, cond, hd] at branch
        obtain ⟨-, -, rfl⟩ := branch
        obtain ⟨len, take⟩ := displacement_reads hd
        refine ⟨by omega, by simp at len ⊢; omega, fun t => ?_⟩
        rw [← h0]
        have := take t
        simp only [List.take_succ_cons, List.cons_append] at this
        simp [escapedForm, cc, c182, c175, Control.decode, c5, c11, cond, hd, this]
    · simp at h


theorem sseForm_reads (p : Nat) (rex : X86.Register.Rex) : Reads (sseForm p rex) 0 := by
  intro bytes x k h
  rcases bytes with _ | ⟨e, _ | ⟨o, _ | ⟨m, rest⟩⟩⟩
  · simp [sseForm] at h
  · simp [sseForm] at h
  · simp [sseForm] at h
  have h0 := h
  simp only [sseForm] at h
  split at h
  · cases h
  rename_i bad
  by_cases c194 : o.toNat = 194
  · rcases rest with _ | ⟨q, rest⟩
    · split at h <;> simp_all
    · have hk : k = 4 := by
        split at h
        · split at h <;> simp_all
        · split at h
          · simp_all
          · split at h
            · simp_all
            · simp only [c194] at h
              cases hp : SsePredicate.ofImm? q.toNat <;> simp_all
      subst hk
      refine ⟨by omega, by simp, fun t => ?_⟩
      rw [← h0]
      simp [sseForm]
  · have hk : k = 3 := by
      simp only [c194, if_false] at h
      repeat' (split at h)
      all_goals first
        | (simp at h; omega)
        | (simp at h; done)
        | (cases ha : SseArith.ofOpcode? o.toNat <;> simp_all)
    subst hk
    refine ⟨by omega, by simp, fun t => ?_⟩
    rw [← h0]
    simp [sseForm, c194]

theorem sseDecode_reads (p : Nat) : Reads (sseDecode p) 1 := by
  intro bytes x k h
  rcases bytes with _ | ⟨second, rest⟩
  · simp [sseDecode] at h
  cases hr : X86.Register.Rex.decode? second.toNat with
  | some rex =>
    cases inner : sseForm p rex rest with
    | none => simp [sseDecode, hr, inner] at h
    | some pair =>
      obtain ⟨y, j⟩ := pair
      simp [sseDecode, hr, inner] at h
      obtain ⟨rfl, rfl⟩ := h
      obtain ⟨-, high, take⟩ := sseForm_reads p rex rest y j inner
      simp only [Nat.sub_zero] at high take
      refine ⟨by omega, by simp; omega, fun t => ?_⟩
      simp [sseDecode, hr, take t]
  | none =>
    cases inner : sseForm p ⟨false, false, false, false⟩ (second :: rest) with
    | none => simp [sseDecode, hr, inner] at h
    | some pair =>
      obtain ⟨y, j⟩ := pair
      simp [sseDecode, hr, inner] at h
      obtain ⟨rfl, rfl⟩ := h
      obtain ⟨low, high, take⟩ := sseForm_reads p _ _ y j inner
      simp only [Nat.sub_zero] at low high take
      obtain ⟨i, rfl⟩ : ∃ i, j = i + 1 := ⟨j - 1, by
        cases j with
        | zero => have := take []; simp [sseForm] at this
        | succ i => simp⟩
      refine ⟨by omega, by simpa using high, fun t => ?_⟩
      have := take t
      simp only [Nat.add_sub_cancel, List.take_succ_cons, List.cons_append] at this ⊢
      simp [sseDecode, hr, this]
theorem decodeOpcode_reads (rex : X86.Register.Rex) (present : Bool) : Reads (decodeOpcode rex present) 0 := by
  intro bytes x k h
  rcases bytes with _ | ⟨opcode, rest⟩
  · simp [decodeOpcode] at h
  have h0 := h
  simp only [Nat.sub_zero, Nat.add_zero, Nat.zero_le, true_and]
  by_cases c195 : opcode.toNat = 195
  · have hk : k = 1 := by simp [decodeOpcode, c195] at h; omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195]
  by_cases c232 : opcode.toNat = 232
  · cases hd : Control.displacement? rest with
    | none => simp [decodeOpcode, c232, hd] at h
    | some d =>
      obtain ⟨len, take⟩ := displacement_reads hd
      have hk : k = 5 := by simp [decodeOpcode, c232, hd] at h; omega
      subst hk
      refine ⟨by simp; omega, fun t => ?_⟩
      rw [← h0]
      simp [decodeOpcode, c232, hd, take]
  by_cases c233 : opcode.toNat = 233
  · cases hd : Control.displacement? rest with
    | none => simp [decodeOpcode, c233, hd] at h
    | some d =>
      obtain ⟨len, take⟩ := displacement_reads hd
      have hk : k = 5 := by simp [decodeOpcode, c233, hd] at h; omega
      subst hk
      refine ⟨by simp; omega, fun t => ?_⟩
      rw [← h0]
      simp [decodeOpcode, c233, hd, take]

  by_cases push : 80 ≤ opcode.toNat ∧ opcode.toNat < 88
  · have hk : k = 1 := by simp [decodeOpcode, c195, c232, c233, push] at h; omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push]
  by_cases pop : 88 ≤ opcode.toNat ∧ opcode.toNat < 96
  · have hk : k = 1 := by simp [decodeOpcode, c195, c232, c233, push, pop] at h; omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push, pop]
  by_cases imm : 184 ≤ opcode.toNat ∧ opcode.toNat < 192
  · cases hw : rex.w
    · cases hd : Control.displacement? rest with
      | none => simp [decodeOpcode, c195, c232, c233, push, pop, imm, hw, hd] at h
      | some d =>
        obtain ⟨len, take⟩ := displacement_reads hd
        have hk : k = 5 := by simp [decodeOpcode, c195, c232, c233, push, pop, imm, hw, hd] at h; omega
        subst hk
        refine ⟨by simp; omega, fun t => ?_⟩
        rw [← h0]
        simp [decodeOpcode, c195, c232, c233, push, pop, imm, hw, hd, take]
    · cases hd : immediate64? rest with
      | none => simp [decodeOpcode, c195, c232, c233, push, pop, imm, hw, hd] at h
      | some d =>
        obtain ⟨len, take⟩ := immediate64_reads hd
        have hk : k = 9 := by simp [decodeOpcode, c195, c232, c233, push, pop, imm, hw, hd] at h; omega
        subst hk
        refine ⟨by simp; omega, fun t => ?_⟩
        rw [← h0]
        simp [decodeOpcode, c195, c232, c233, push, pop, imm, hw, hd, take]
  by_cases c136 : opcode.toNat = 136
  · rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136] at h
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136] at h
    obtain ⟨⟨n3, nlow⟩, inner⟩ := h
    obtain ⟨low, high, take⟩ := memoryForm_reads rex 136 modrm remaining x k inner
    simp only [show ¬(136 = 4022) by decide, if_false] at low high take
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 2 := ⟨k - 2, by omega⟩
    refine ⟨by simp; omega, fun t => ?_⟩
    rw [← h0]
    have := take t
    simp only [Nat.add_sub_cancel] at this
    simp only [List.take_succ_cons, List.cons_append]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, this, inner, n3, nlow]

  by_cases c137 : opcode.toNat = 137 ∨ opcode.toNat = 139
  · rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137] at h
    by_cases reg : modrm.toNat / 64 = 3
    · have hk : k = 2 := by simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, reg] at h; omega
      subst hk
      refine ⟨by simp, fun t => ?_⟩
      rw [← h0]
      simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, reg]
    · have inner : memoryForm rex opcode.toNat modrm remaining = some (x, k) := by
        simpa [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, reg] using h
      have small : ¬(opcode.toNat = 4022) := by have := opcode.toNat_lt; omega
      obtain ⟨low, high, take⟩ := memoryForm_reads rex opcode.toNat modrm remaining x k inner
      simp only [small, if_false] at low high take
      obtain ⟨j, rfl⟩ : ∃ j, k = j + 2 := ⟨k - 2, by omega⟩
      refine ⟨by simp; omega, fun t => ?_⟩
      rw [← h0]
      have := take t
      simp only [Nat.add_sub_cancel] at this
      simp only [List.take_succ_cons, List.cons_append]
      simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, reg, this, inner]
  by_cases c41 : (opcode.toNat = 41 ∧ rex.w = true) ∨ opcode.toNat = 57
  · rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41] at h
    have hk : k = 2 := by
      simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41] at h
      omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41]

  cases alu : Alu.ofOpcode? opcode.toNat with
  | some operation =>
    rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu] at h
    have hk : k = 2 := by simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu] at h; omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu]
  | none =>
  by_cases c133 : opcode.toNat = 133
  · rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133] at h
    have hk : k = 2 := by simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133] at h; omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133]
  by_cases c99 : opcode.toNat = 99
  · rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99] at h
    have hk : k = 2 := by simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99] at h; omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99]
  by_cases c247 : opcode.toNat = 247
  · rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247] at h
    have hk : k = 2 := by
      simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247] at h
      repeat' split at h
      all_goals simp at h
      all_goals omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247]
  by_cases c211 : opcode.toNat = 211
  · rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211] at h
    have hk : k = 2 := by
      simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211] at h
      obtain ⟨-, h⟩ := h
      exact bind_size h
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211]
  by_cases c141 : opcode.toNat = 141
  · rcases rest with _ | ⟨modrm, remaining⟩
    · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211, c141] at h
    have inner : addressForm rex modrm remaining = some (x, k) := by
      simpa [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211, c141] using h
    obtain ⟨low, high, take⟩ := addressForm_reads rex modrm remaining x k inner
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 2 := ⟨k - 2, by omega⟩
    refine ⟨by simp; omega, fun t => ?_⟩
    rw [← h0]
    have := take t
    simp only [Nat.add_sub_cancel] at this
    simp only [List.take_succ_cons, List.cons_append]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211, c141, this, inner]
  by_cases c153 : opcode.toNat = 153
  · have hk : k = 1 := by simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211, c141, c153] at h; omega
    subst hk
    refine ⟨by simp, fun t => ?_⟩
    rw [← h0]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211, c141, c153]
  by_cases c15 : opcode.toNat = 15
  · have inner : escapedForm rex present rest = some (x, k) := by
      simpa [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211, c141, c153, c15] using h
    obtain ⟨low, high, take⟩ := escapedForm_reads rex present rest x k inner
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
    refine ⟨by simp; omega, fun t => ?_⟩
    rw [← h0]
    have := take t
    simp only [Nat.add_sub_cancel] at this
    simp only [List.take_succ_cons, List.cons_append]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, Alu.ofOpcode?, c133, c99, c247, c211, c141, c153, c15, this, inner]
  by_cases sse : (!present && (opcode.toNat = 102 || opcode.toNat = 242 || opcode.toNat = 243)) = true
  · have inner : sseDecode opcode.toNat rest = some (x, k) := by
      simpa [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, c133, c99, c247, c211, c141, c153, c15, sse] using h
    obtain ⟨low, high, take⟩ := sseDecode_reads opcode.toNat rest x k inner
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
    refine ⟨by simp; omega, fun t => ?_⟩
    rw [← h0]
    have := take t
    simp only [Nat.add_sub_cancel] at this
    simp only [List.take_succ_cons, List.cons_append]
    simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, c133, c99, c247, c211, c141, c153, c15, sse, this, inner]
  · simp [decodeOpcode, c195, c232, c233, push, pop, imm, c136, c137, c41, alu, c133, c99, c247, c211, c141, c153, c15, sse] at h

theorem decode_reads : Reads decode 0 := by
  intro bytes x k h
  rcases bytes with _ | ⟨first, rest⟩
  · simp [decode] at h
  simp only [Nat.sub_zero, Nat.add_zero, Nat.zero_le, true_and]
  cases hr : X86.Register.Rex.decode? first.toNat with
  | some rex =>
    cases inner : decodeOpcode rex true rest with
    | none => simp [decode, hr, inner] at h
    | some pair =>
      obtain ⟨y, j⟩ := pair
      have h' := h
      simp [decode, hr, inner] at h'
      obtain ⟨rfl, rfl⟩ := h'
      obtain ⟨-, high, take⟩ := decodeOpcode_reads rex true rest y j inner
      simp only [Nat.sub_zero, Nat.add_zero] at high take
      refine ⟨by simp; omega, fun t => ?_⟩
      simp [decode, hr, take t]
  | none =>
    have inner : decodeOpcode ⟨false, false, false, false⟩ false (first :: rest) = some (x, k) := by
      simpa [decode, hr] using h
    obtain ⟨-, high, take⟩ := decodeOpcode_reads _ _ _ _ _ inner
    simp only [Nat.sub_zero, Nat.add_zero] at high take
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := by
      cases k with
      | zero => have := take []; simp [decodeOpcode] at this
      | succ j => exact ⟨j, rfl⟩
    refine ⟨high, fun t => ?_⟩
    have := take t
    simp only [List.take_succ_cons, List.cons_append] at this ⊢
    simp [decode, hr, this]

/-- Bytes loaded at `address` agree with memory, so a prefix of one is a prefix of the other. -/
theorem CodeAt.take_eq {memory : Memory} {address : Address} {first second : List UInt8} {n : Nat}
    (l1 : CodeAt memory address first) (l2 : CodeAt memory address second)
    (n1 : n ≤ first.length) (n2 : n ≤ second.length) : first.take n = second.take n := by
  apply List.ext_getElem (by simp; omega)
  intro j b1 b2
  simp only [List.getElem_take]
  simp only [List.length_take] at b1 b2
  rw [← l1 j (by omega), ← l2 j (by omega)]

theorem decode_unique_le {memory : Memory} {address : Address} {first second : List UInt8}
    {x y : Instruction} {j k : Nat}
    (l1 : CodeAt memory address first) (l2 : CodeAt memory address second)
    (d1 : decode first = some (x, j)) (d2 : decode second = some (y, k)) (le : j ≤ k) :
    (x, j) = (y, k) := by
  obtain ⟨-, h1, t1⟩ := decode_reads first x j d1
  obtain ⟨-, h2, t2⟩ := decode_reads second y k d2
  simp only [Nat.sub_zero, Nat.add_zero] at h1 h2 t1 t2
  have front : (second.take k).take j = first.take j := by
    rw [List.take_take, Nat.min_eq_left le]
    exact (CodeAt.take_eq l1 l2 h1 (by omega)).symm
  have split : second.take k = first.take j ++ (second.take k).drop j := by
    rw [← front]
    exact (List.take_append_drop _ _).symm
  have := t2 []
  rw [List.append_nil, split, t1] at this
  exact Option.some.inj this

/-- **Decoding is unique.** Two byte lists loaded at the same address that
both decode give the same instruction and the same size. -/
theorem decode_unique {memory : Memory} {address : Address} {first second : List UInt8}
    {p q : Instruction × Nat}
    (l1 : CodeAt memory address first) (l2 : CodeAt memory address second)
    (d1 : decode first = some p) (d2 : decode second = some q) : p = q := by
  obtain ⟨x, j⟩ := p
  obtain ⟨y, k⟩ := q
  rcases Nat.le_total j k with le | le
  · exact decode_unique_le l1 l2 d1 d2 le
  · exact (decode_unique_le l2 l1 d2 d1 le).symm

end Lanius.X86.Machine
