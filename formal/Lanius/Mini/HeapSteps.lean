import Lanius.Mini.Flags
import Lanius.Mini.DetSteps

/-! The x86 runs of the heap instructions. The heap is the bytes from r12;
r13 holds the allocation cursor and r14 the limit, both offsets from r12. -/

namespace Lanius.Mini
open Lanius.X86.Machine

theorem lowHalf_highHalf (value : BitVec 64) :
    BitVec.ofNat 64 ((lowHalf value).toNat + 4294967296 * (highHalf value).toNat) = value := by
  apply BitVec.eq_of_toNat_eq
  simp only [lowHalf, highHalf, BitVec.toNat_ofNat, BitVec.toNat_setWidth, BitVec.toNat_ushiftRight,
    Nat.shiftRight_eq_div_pow]
  have := value.isLt
  omega

theorem _root_.Lanius.X86.Machine.CodeAt.next {s s' : State} {first rest : List UInt8} (loaded : CodeAt s.memory s.rip (first ++ rest))
    (memory : s'.memory = s.memory) (rip : s'.rip = s.rip + BitVec.ofNat 64 first.length) :
    CodeAt s'.memory s'.rip rest := by
  rw [memory, rip]
  exact loaded.suffix

theorem pow2_eq : ∀ shift, pow2 shift = BitVec.ofNat 64 (2 ^ shift)
  | 0 => by rw [pow2]; rfl
  | n + 1 => by
    rw [pow2, if_neg (by omega), Nat.add_sub_cancel, pow2_eq n]
    apply BitVec.eq_of_toNat_eq
    simp only [BitVec.toNat_add, BitVec.toNat_ofNat, Nat.pow_succ]
    omega

theorem nat_and_high (n k : Nat) (hk : k ≤ 64) (hn : n < 2 ^ 64) :
    n &&& (2 ^ 64 - 2 ^ k) = n / 2 ^ k * 2 ^ k := by
  apply Nat.eq_of_testBit_eq; intro i; rw [Nat.testBit_and]
  have hm : 2 ^ 64 - 2 ^ k = (2 ^ (64 - k) - 1) * 2 ^ k := by
    rw [Nat.sub_mul, Nat.one_mul, ← Nat.pow_add, Nat.sub_add_cancel hk]
  rw [hm, ← Nat.shiftLeft_eq, ← Nat.shiftLeft_eq, ← Nat.shiftRight_eq_div_pow,
    Nat.testBit_shiftLeft, Nat.testBit_shiftLeft, Nat.testBit_shiftRight]
  by_cases hi : k ≤ i
  · simp only [hi, decide_true, Bool.true_and, Nat.testBit_two_pow_sub_one]
    rw [Nat.add_sub_cancel' hi]
    by_cases h64 : i < 64
    · have : i - k < 64 - k := by omega
      simp [this]
    · have : ¬ i - k < 64 - k := by omega
      simp only [this, decide_false, Bool.and_false]; symm
      apply Nat.testBit_lt_two_pow
      calc n < 2 ^ 64 := hn
        _ ≤ 2 ^ i := Nat.pow_le_pow_right (by omega) (by omega)
  · simp [hi]

theorem alignUp_ge (n shift : Nat) : n ≤ alignUp n shift := by
  unfold alignUp
  have pos := Nat.two_pow_pos shift
  have split := Nat.div_add_mod (n + 2 ^ shift - 1) (2 ^ shift)
  have small := Nat.mod_lt (n + 2 ^ shift - 1) pos
  rw [Nat.mul_comm] at split
  omega

/-- Rounding up with the add-and-mask of `bumpBytes`. -/
theorem align_mask (cursor shift : Nat) (shiftSmall : shift < 32) (cursorSmall : cursor < 2 ^ 62) :
    (BitVec.ofNat 64 cursor + (pow2 shift - 1)) &&& (0 - pow2 shift) = BitVec.ofNat 64 (alignUp cursor shift) := by
  apply BitVec.eq_of_toNat_eq
  rw [pow2_eq]
  have pos := Nat.two_pow_pos shift
  have below : 2 ^ shift < 2 ^ 32 := Nat.pow_lt_pow_right (by omega) shiftSmall
  have one : (BitVec.ofNat 64 (2 ^ shift) - 1).toNat = 2 ^ shift - 1 := by
    rw [BitVec.toNat_sub, BitVec.toNat_ofNat]; simp; omega
  have mask : (0 - BitVec.ofNat 64 (2 ^ shift)).toNat = 2 ^ 64 - 2 ^ shift := by
    rw [BitVec.toNat_sub, BitVec.toNat_ofNat]; simp; omega
  have sum : (BitVec.ofNat 64 cursor + (BitVec.ofNat 64 (2 ^ shift) - 1)).toNat = cursor + 2 ^ shift - 1 := by
    rw [BitVec.toNat_add, one, BitVec.toNat_ofNat]; omega
  rw [BitVec.toNat_and, sum, mask, nat_and_high _ _ (by omega) (by omega), BitVec.toNat_ofNat, alignUp]
  have := Nat.div_mul_le_self (cursor + 2 ^ shift - 1) (2 ^ shift)
  rw [Nat.mod_eq_of_lt (by omega)]

/-- The allocation: rax ends as the rounded cursor and the cursor moves past
rax bytes, provided they fit below the limit. -/
theorem bump_steps (s : State) (shift : Nat) (shiftSmall : shift < 32)
    (loaded : CodeAt s.memory s.rip (bumpSpec shift)) {cursor limit : Nat}
    (atCursor : s.registers cursorRegister = BitVec.ofNat 64 cursor)
    (atLimit : (s.registers limitRegister).toNat = limit) (limitSmall : limit < 2 ^ 62)
    (room : alignUp cursor shift + (s.registers 0).toNat ≤ limit) :
    ∃ s', Steps 11 s s' ∧ Det 11 s s' ∧ s'.memory = s.memory ∧ s'.rip = s.rip + BitVec.ofNat 64 52 ∧
      s'.registers 0 = BitVec.ofNat 64 (alignUp cursor shift) ∧
      s'.registers cursorRegister = BitVec.ofNat 64 (alignUp cursor shift + (s.registers 0).toNat) ∧
      ∀ register, register ≠ 0 → register ≠ rcxRegister → register ≠ r11Register → register ≠ cursorRegister →
        s'.registers register = s.registers register := by
  have c0 := loaded
  simp only [bumpSpec] at c0
  let s1 := s.move64 rcxRegister cursorRegister (moveBytes .w64 rcxRegister cursorRegister).length
  have t1 : Lanius.X86.Machine.Step s s1 := move_step s s1 .w64 _ _ c0.prefix rfl
  have c1 := c0.next (s' := s1) rfl rfl
  let s2 := s1.immediate64 r11Register
    (BitVec.ofNat 64 ((lowHalf (pow2 shift - 1)).toNat + 4294967296 * (highHalf (pow2 shift - 1)).toNat))
    (r11Bytes (pow2 shift - 1)).length
  have t2 : Lanius.X86.Machine.Step s1 s2 := immediate_step s1 s2 .w64 r11Register _ _ c1.prefix rfl
  have c2 := c1.next (s' := s2) rfl rfl
  let s3 := s2.alu64 .add rcxRegister r11Register false (aluBytes .w64 .add rcxRegister r11Register).length
  have t3 : Lanius.X86.Machine.Step s2 s3 := alu_step .w64 s2 s3 .add _ _ c2.prefix false rfl
  have c3 := c2.next (s' := s3) rfl rfl
  let s4 := s3.immediate64 r11Register
    (BitVec.ofNat 64 ((lowHalf (0 - pow2 shift)).toNat + 4294967296 * (highHalf (0 - pow2 shift)).toNat))
    (r11Bytes (0 - pow2 shift)).length
  have t4 : Lanius.X86.Machine.Step s3 s4 := immediate_step s3 s4 .w64 r11Register _ _ c3.prefix rfl
  have c4 := c3.next (s' := s4) rfl rfl
  let s5 := s4.alu64 .and rcxRegister r11Register false (aluBytes .w64 .and rcxRegister r11Register).length
  have t5 : Lanius.X86.Machine.Step s4 s5 := alu_step .w64 s4 s5 .and _ _ c4.prefix false rfl
  have c5 := c4.next (s' := s5) rfl rfl
  let s6 := s5.move64 r11Register rcxRegister (moveBytes .w64 r11Register rcxRegister).length
  have t6 : Lanius.X86.Machine.Step s5 s6 := move_step s5 s6 .w64 _ _ c5.prefix rfl
  have c6 := c5.next (s' := s6) rfl rfl
  let s7 := s6.alu64 .add r11Register 0 false (aluBytes .w64 .add r11Register 0).length
  have t7 : Lanius.X86.Machine.Step s6 s7 := alu_step .w64 s6 s7 .add _ _ c6.prefix false rfl
  have c7 := c6.next (s' := s7) rfl rfl
  let s8 := s7.compare64 r11Register limitRegister limitCompareBytes.length
  have t8 : Lanius.X86.Machine.Step s7 s8 :=
    Lanius.X86.Machine.Step.decoded limitCompareBytes c7.prefix (.compare64 r11Register limitRegister) 3
      (by decide) rfl rfl
  have c8 := c7.next (s' := s8) rfl rfl
  -- the values
  have cursorSmall : cursor < 2 ^ 62 := by have := alignUp_ge cursor shift; omega
  have rounded : s5.registers rcxRegister = BitVec.ofNat 64 (alignUp cursor shift) := by
    simp only [s5, s4, s3, s2, s1, State.alu64, State.alu, State.immediate64, State.move64, Alu.result,
      lowHalf_highHalf, BitVec.setWidth_eq, rcxRegister, r11Register, cursorRegister]
    simp only [if_pos, if_neg (show (1 : Register) ≠ 11 by decide)]
    rw [show s.registers 13 = BitVec.ofNat 64 cursor from atCursor]
    exact align_mask cursor shift shiftSmall cursorSmall
  have accKept : s6.registers 0 = s.registers 0 := by
    simp [s6, s5, s4, s3, s2, s1, State.alu64, State.alu, State.immediate64, State.move64, rcxRegister,
      r11Register]
  have ended : s7.registers r11Register = BitVec.ofNat 64 (alignUp cursor shift) + s.registers 0 := by
    have moved : s6.registers r11Register = s5.registers rcxRegister := by simp [s6, State.move64]
    simp only [s7, State.alu64, State.alu, Alu.result, BitVec.setWidth_eq, if_pos, moved, rounded, accKept]
  have endedNat : (BitVec.ofNat 64 (alignUp cursor shift) + s.registers 0).toNat =
      alignUp cursor shift + (s.registers 0).toNat := by
    rw [BitVec.toNat_add, BitVec.toNat_ofNat]; omega
  have limitKept : s7.registers limitRegister = s.registers limitRegister := by
    simp [s7, s6, s5, s4, s3, s2, s1, State.alu64, State.alu, State.immediate64, State.move64, rcxRegister,
      r11Register, limitRegister]
  have taken : condition s8.flags 6 = true := by
    show condition (subtractFlags s7.flags (s7.registers r11Register) (s7.registers limitRegister))
      (CmpOp.code .u64 .le) = true
    rw [CmpOp.conditionU, ended, limitKept]
    simp only [CmpOp.holdsU, BitVec.ule, decide_eq_true_eq, endedNat, atLimit]
    exact room
  let s9 := s8.branch 6 2 6
  obtain ⟨t9, rip9⟩ := branch_step_rip s8 s9 6 2 c8.prefix taken rfl
  have c9 : CodeAt s9.memory s9.rip (moveBytes .w64 cursorRegister r11Register ++ moveBytes .w64 0 rcxRegister) := by
    have tail := c8.suffix.suffix
    rw [show s9.memory = s8.memory from rfl, rip9,
      show ((2 : BitVec 32).signExtend 64) = BitVec.ofNat 64 2 from by decide]
    exact tail
  let s10 := s9.move64 cursorRegister r11Register (moveBytes .w64 cursorRegister r11Register).length
  have t10 : Lanius.X86.Machine.Step s9 s10 := move_step s9 s10 .w64 _ _ c9.prefix rfl
  have c10 := c9.next (s' := s10) rfl rfl
  let s11 := s10.move64 0 rcxRegister (moveBytes .w64 0 rcxRegister).length
  have t11 : Lanius.X86.Machine.Step s10 s11 := move_step s10 s11 .w64 _ _ c10 rfl
  refine ⟨s11, .cons t1 (.cons t2 (.cons t3 (.cons t4 (.cons t5 (.cons t6 (.cons t7 (.cons t8 (.cons t9
    (.cons t10 (.cons t11 (.refl _))))))))))),
    Det.cons t1 (move_noRead c0.prefix) (Det.cons t2 (immediate_noRead c1.prefix)
      (Det.cons t3 (alu_noRead c2.prefix) (Det.cons t4 (immediate_noRead c3.prefix)
        (Det.cons t5 (alu_noRead c4.prefix) (Det.cons t6 (move_noRead c5.prefix)
          (Det.cons t7 (alu_noRead c6.prefix)
            (Det.pairCons t8 (Writes.of (i := .compare64 r11Register limitRegister) (k := 3) c7.prefix
              (by decide) rfl) t9
              (Det.cons t10 (move_noRead c9.prefix) (Det.cons t11 (move_noRead c10) (Det.refl _)))))))))),
    rfl, ?_, ?_, ?_, ?_⟩
  · have lengths : (moveBytes .w64 0 rcxRegister).length = 3 ∧ (moveBytes .w64 cursorRegister r11Register).length = 3 ∧
        (r11Bytes (pow2 shift - 1)).length = 10 ∧ (r11Bytes (0 - pow2 shift)).length = 10 ∧
        (aluBytes .w64 .add rcxRegister r11Register).length = 3 ∧
        (aluBytes .w64 .and rcxRegister r11Register).length = 3 ∧
        (moveBytes .w64 r11Register rcxRegister).length = 3 ∧ (aluBytes .w64 .add r11Register 0).length = 3 ∧
        (moveBytes .w64 rcxRegister cursorRegister).length = 3 := by
      refine ⟨rfl, rfl, ?_, ?_, rfl, rfl, rfl, rfl, rfl⟩ <;>
        simp only [r11Bytes, immediateBytes, displacementBytes, List.length_append, List.length_cons,
          List.length_nil, ↓reduceIte] <;> decide
    obtain ⟨l1, l2, l3, l4, l5, l6, l7, l8, l9⟩ := lengths
    simp only [s11, s10, State.move64, rip9, s8, s7, s6, s5, s4, s3, s2, s1, State.compare64, State.alu64,
      State.alu, State.immediate64, l1, l2, l3, l4, l5, l6, l7, l8, l9,
      show ((2 : BitVec 32).signExtend 64) = BitVec.ofNat 64 2 from by decide,
      show limitCompareBytes.length = 3 from rfl]
    bv_omega
  · have : s10.registers rcxRegister = s5.registers rcxRegister := by
      simp [s10, s9, s8, s7, s6, State.move64, State.branch, State.compare64, State.alu64, State.alu, rcxRegister,
        r11Register, cursorRegister]
    simp only [s11, State.move64, if_pos, this, rounded]
  · have : s10.registers cursorRegister = s7.registers r11Register := by
      simp [s10, s9, s8, State.move64, State.branch, State.compare64]
    simp only [s11, State.move64, if_neg (show cursorRegister ≠ 0 by decide), this, ended]
    rw [← endedNat, BitVec.ofNat_toNat, BitVec.setWidth_eq]
  · intro register zero one eleven thirteen
    simp [s11, s10, s9, s8, s7, s6, s5, s4, s3, s2, s1, State.move64, State.branch, State.compare64,
      State.alu64, State.alu, State.immediate64, zero, one, eleven, thirteen]

/-- The byte load: rax becomes the heap byte at offset rax. -/
theorem loadAt_steps (s : State) (loaded : CodeAt s.memory s.rip loadAtSpec) :
    ∃ s', Steps 2 s s' ∧ Det 2 s s' ∧ s'.memory = s.memory ∧ s'.rip = s.rip + BitVec.ofNat 64 10 ∧
      s'.registers 0 = BitVec.ofNat 64 (s.memory (s.registers heapBaseRegister + s.registers 0)).toNat ∧
      ∀ register, register ≠ 0 → s'.registers register = s.registers register := by
  have c0 := loaded
  simp only [loadAtSpec] at c0
  let s1 := s.alu64 .add 0 heapBaseRegister false (aluBytes .w64 .add 0 heapBaseRegister).length
  have t1 : Lanius.X86.Machine.Step s s1 := alu_step .w64 s s1 .add _ _ c0.prefix false rfl
  have c1 := c0.next (s' := s1) rfl rfl
  let s2 := s1.loadByte 0 0 (BitVec.ofInt 32 0) (loadByteBytes 0 0 0).length
  have t2 : Lanius.X86.Machine.Step s1 s2 := loadByte_step s1 s2 0 0 0 c1 rfl
  refine ⟨s2, .cons t1 (.cons t2 (.refl _)),
    Det.cons t1 (alu_noRead c0.prefix) (Det.cons t2 (loadByte_noRead c1) (Det.refl _)), rfl, ?_, ?_, ?_⟩
  · simp only [s2, s1, State.loadByte, State.alu64, State.alu]
    rw [show (aluBytes .w64 .add 0 heapBaseRegister).length = 3 from rfl,
      show (loadByteBytes 0 0 0).length = 7 from rfl]
    bv_omega
  · simp only [s2, s1, State.loadByte, State.alu64, State.alu, Alu.result, BitVec.setWidth_eq, if_pos,
      show (BitVec.ofInt 32 0).signExtend 64 = 0 from by decide, BitVec.add_comm (s.registers 0)]
    simp
  · intro register zero
    simp [s2, s1, State.loadByte, State.alu64, State.alu, zero]

/-- The byte store: the low byte of rax goes to the heap at the offset in `slot`. -/
theorem storeAt_steps (s : State) (slot : Nat) (loaded : CodeAt s.memory s.rip (storeAtSpec slot)) :
    ∃ s', Steps 3 s s' ∧ Det 3 s s' ∧ s'.rip = s.rip + BitVec.ofNat 64 16 ∧
      s'.memory = (fun address => if address = s.registers heapBaseRegister +
          read64 s.memory (s.registers rbpRegister + (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64)
        then lowByte (s.registers 0) else s.memory address) ∧
      ∀ register, register ≠ rcxRegister → s'.registers register = s.registers register := by
  have c0 := loaded
  simp only [storeAtSpec] at c0
  let s1 := s.load64 rcxRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement slot))
    (memoryBytes .w64 true rcxRegister rbpRegister (frameDisplacement slot)).length
  have t1 : Lanius.X86.Machine.Step s s1 :=
    Lanius.X86.Machine.Step.decoded _ c0.prefix _ _
      (by simpa [memoryInstruction] using
        memory_decodes .w64 true rcxRegister rbpRegister (frameDisplacement slot) [])
      rfl rfl
  have c1 := c0.next (s' := s1) rfl rfl
  let s2 := s1.alu64 .add rcxRegister heapBaseRegister false (aluBytes .w64 .add rcxRegister heapBaseRegister).length
  have t2 : Lanius.X86.Machine.Step s1 s2 := alu_step .w64 s1 s2 .add _ _ c1.prefix false rfl
  have c2 := c1.next (s' := s2) rfl rfl
  let s3 := s2.storeByte 0 rcxRegister (BitVec.ofInt 32 0) (storeByteBytes 0 rcxRegister 0).length
  have t3 : Lanius.X86.Machine.Step s2 s3 := storeByte_step s2 s3 0 rcxRegister 0 c2 rfl
  refine ⟨s3, .cons t1 (.cons t2 (.cons t3 (.refl _))),
    Det.cons t1 (memory_noRead c0.prefix) (Det.cons t2 (alu_noRead c1.prefix)
      (Det.cons t3 (storeByte_noRead c2) (Det.refl _))), ?_, ?_, ?_⟩
  · simp only [s3, s2, s1, State.storeByte, State.alu64, State.alu, State.load64]
    rw [show (memoryBytes .w64 true rcxRegister rbpRegister (frameDisplacement slot)).length = 7 from by
        simp only [memoryBytes, memoryHeader, Lanius.Semantics.i32Bytes, List.length_append, List.length_map,
          List.length_range]; decide,
      show (aluBytes .w64 .add rcxRegister heapBaseRegister).length = 3 from rfl,
      show (storeByteBytes 0 rcxRegister 0).length = 6 from rfl]
    bv_omega
  · funext address
    simp only [s3, s2, s1, State.storeByte, State.alu64, State.alu, State.load64, Alu.result, BitVec.setWidth_eq,
      if_pos, show (BitVec.ofInt 32 0).signExtend 64 = 0 from by decide, lowByte,
      if_neg (show (0 : Register) ≠ rcxRegister by decide),
      if_neg (show heapBaseRegister ≠ rcxRegister by decide)]
    rw [BitVec.add_comm (read64 _ _)]
    simp
  · intro register one
    simp [s3, s2, s1, State.storeByte, State.alu64, State.alu, State.load64, one]

/-- The state after a passing stack check: only the flags and rip change. -/
def stackChecked (s : State) : State := (s.compare64 stackRegister rspRegister 3).branch 6 2 6

/-- `cmp r15, rsp; jbe +2; ud2` jumps over the `ud2` when r15 is at most rsp. -/
theorem stackCheck_det (s : State)
    (loaded : CodeAt s.memory s.rip (stackCompareBytes ++ (branchBytes 6 2 ++ trapBytes)))
    (room : (s.registers stackRegister).toNat ≤ (s.registers rspRegister).toNat) :
    Steps 2 s (stackChecked s) ∧ Det 2 s (stackChecked s) ∧
      (stackChecked s).rip = s.rip + BitVec.ofNat 64 11 := by
  let s1 := s.compare64 stackRegister rspRegister stackCompareBytes.length
  have t1 : Lanius.X86.Machine.Step s s1 :=
    Lanius.X86.Machine.Step.decoded stackCompareBytes loaded.prefix (.compare64 stackRegister rspRegister) 3
      (by decide) rfl rfl
  have c1 := loaded.next (s' := s1) rfl rfl
  have taken : condition s1.flags 6 = true := by
    show condition (subtractFlags s.flags (s.registers stackRegister) (s.registers rspRegister))
      (CmpOp.code .u64 .le) = true
    rw [CmpOp.conditionU]
    simp only [CmpOp.holdsU, BitVec.ule, decide_eq_true_eq]
    exact room
  obtain ⟨t2, rip2⟩ := branch_step_rip s1 (stackChecked s) 6 2 c1.prefix taken rfl
  refine ⟨.cons t1 (.cons t2 (.refl _)),
    Det.pairCons t1 (Writes.of (i := .compare64 stackRegister rspRegister) (k := 3) loaded.prefix (by decide) rfl)
      t2 (Det.refl _), ?_⟩
  rw [rip2, show ((2 : BitVec 32).signExtend 64) = BitVec.ofNat 64 2 from by decide]
  simp only [s1, State.compare64, stackCompareBytes, List.length_cons, List.length_nil]
  bv_omega

/-- The check fails when rsp is below r15: the run stops at the `ud2`. -/
theorem stackCheck_fails (s : State)
    (loaded : CodeAt s.memory s.rip (stackCompareBytes ++ (branchBytes 6 2 ++ trapBytes)))
    (below : (s.registers rspRegister).toNat < (s.registers stackRegister).toNat) :
    Steps 2 s (stackChecked s) ∧ Det 2 s (stackChecked s) ∧ Fault (stackChecked s) := by
  let s1 := s.compare64 stackRegister rspRegister stackCompareBytes.length
  have t1 : Lanius.X86.Machine.Step s s1 :=
    Lanius.X86.Machine.Step.decoded stackCompareBytes loaded.prefix (.compare64 stackRegister rspRegister) 3
      (by decide) rfl rfl
  have c1 := loaded.next (s' := s1) rfl rfl
  have notTaken : condition s1.flags 6 = false := by
    show condition (subtractFlags s.flags (s.registers stackRegister) (s.registers rspRegister))
      (CmpOp.code .u64 .le) = false
    rw [CmpOp.conditionU]
    simp only [CmpOp.holdsU, BitVec.ule, decide_eq_false_iff_not]
    omega
  obtain ⟨t2, rip2⟩ := branch_step_rip_not_taken s1 (stackChecked s) 6 2 c1.prefix notTaken rfl
  refine ⟨.cons t1 (.cons t2 (.refl _)),
    Det.pairCons t1 (Writes.of (i := .compare64 stackRegister rspRegister) (k := 3) loaded.prefix (by decide) rfl)
      t2 (Det.refl _), .ud2 ?_⟩
  have tail := c1.suffix
  rw [show (stackChecked s).memory = s1.memory from rfl, rip2,
    show s1.rip + 6#64 + 0 = s1.rip + BitVec.ofNat 64 (branchBytes 6 2).length from by
      simp [branchBytes, displacementBytes]]
  exact tail

theorem stackChecked_registers (s : State) : (stackChecked s).registers = s.registers := rfl
theorem stackChecked_memory (s : State) : (stackChecked s).memory = s.memory := rfl

end Lanius.Mini
