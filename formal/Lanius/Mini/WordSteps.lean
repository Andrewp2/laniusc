import Lanius.Mini.HeapSteps

/-! The x86 runs of the heap word load and store, and the byte-level facts
they rest on: a 32- or 64-bit memory operand is its bytes, little-endian. -/

namespace Lanius.Mini
open Lanius.X86.Machine

/-- The `count` bytes of x86 memory from `address`, little-endian. -/
def memLE (memory : Memory) (address : BitVec 64) : Nat → Nat
  | 0 => 0
  | count + 1 => (memory address).toNat + 256 * memLE memory (address + 1) count

theorem memLE_lt (memory : Memory) : ∀ (address : BitVec 64) (count : Nat), memLE memory address count < 256 ^ count
  | _, 0 => by simp [memLE]
  | address, count + 1 => by
    have := memLE_lt memory (address + 1) count
    have := (memory address).toNat_lt
    simp only [memLE, Nat.pow_succ]
    omega

theorem memLE_add (memory : Memory) : ∀ (address : BitVec 64) (n k : Nat),
    memLE memory address (n + k) = memLE memory address n + 256 ^ n * memLE memory (address + BitVec.ofNat 64 n) k
  | address, 0, k => by simp [memLE]
  | address, n + 1, k => by
    rw [show n + 1 + k = (n + k) + 1 by omega, memLE, memLE, memLE_add memory (address + 1) n k,
      BitVec.add_assoc, show (1 : BitVec 64) + BitVec.ofNat 64 n = BitVec.ofNat 64 (n + 1) by
        rw [BitVec.ofNat_add, BitVec.add_comm]; rfl, Nat.pow_succ]
    rw [Nat.mul_add, Nat.mul_left_comm 256 (256 ^ n), Nat.mul_assoc, Nat.add_assoc]

theorem read32_toNat (memory : Memory) (address : BitVec 64) :
    (read32 memory address).toNat = memLE memory address 4 := by
  have h0 := (memory address).toNat_lt
  have h1 := (memory (address + 1)).toNat_lt
  have h2 := (memory (address + 2)).toNat_lt
  have h3 := (memory (address + 3)).toNat_lt
  have e2 : address + 1 + 1 = address + 2 := by rw [BitVec.add_assoc]; rfl
  have e3 : address + 2 + 1 = address + 3 := by rw [BitVec.add_assoc]; rfl
  simp only [read32, Lanius.X86.readBytes, BitVec.toNat_ofNat, memLE]
  rw [e2, e3]
  omega

theorem read64_eq (memory : Memory) (address : BitVec 64) :
    read64 memory address = BitVec.ofNat 64 (memLE memory address 8) := by
  rw [read64, read32_toNat, read32_toNat, show 8 = 4 + 4 from rfl, memLE_add]
  rfl

/-- Lane `k` of a 32-bit store is byte `k` of the value. -/
theorem write32_lane (memory : Memory) (address : BitVec 64) (value : BitVec 32) :
    ∀ k, k < 4 → write32 memory address value (address + BitVec.ofNat 64 k) = UInt8.ofNat (value.toNat / 256 ^ k)
  | 0, _ => by simp [write32, Lanius.X86.wordBytes, uint8_ofNat_mod]
  | 1, _ => by
    have : address + BitVec.ofNat 64 1 ≠ address := by bv_omega
    simp [write32, Lanius.X86.wordBytes, uint8_ofNat_mod, this]
  | 2, _ => by
    have a : address + BitVec.ofNat 64 2 ≠ address := by bv_omega
    simp [write32, Lanius.X86.wordBytes, uint8_ofNat_mod, a]
  | 3, _ => by
    have a : address + BitVec.ofNat 64 3 ≠ address := by bv_omega
    simp [write32, Lanius.X86.wordBytes, uint8_ofNat_mod, a]
  | k + 4, lt => absurd lt (by omega)

/-- Lane `k` of a 64-bit store is byte `k` of the value. -/
theorem write64_lane (memory : Memory) (address value : BitVec 64) (k : Nat) (lt : k < 8) :
    write64 memory address value (address + BitVec.ofNat 64 k) = UInt8.ofNat (value.toNat / 256 ^ k) := by
  have bound := value.isLt
  by_cases low : k < 4
  · have outside : ∀ j : Nat, j < 4 → address + BitVec.ofNat 64 k ≠ address + 4 + BitVec.ofNat 64 j := by
      intro j lane; bv_omega
    rw [write64, write32_frame _ _ _ _ ⟨by simpa using outside 0 (by decide), outside 1 (by decide),
      outside 2 (by decide), outside 3 (by decide)⟩, write32_lane _ _ _ k low]
    apply uint8_ofNat_congr
    simp only [BitVec.toNat_setWidth]
    rcases (show k = 0 ∨ k = 1 ∨ k = 2 ∨ k = 3 by omega) with rfl | rfl | rfl | rfl <;> omega
  · obtain ⟨j, rfl⟩ : ∃ j, k = 4 + j := ⟨k - 4, by omega⟩
    rw [show address + BitVec.ofNat 64 (4 + j) = address + 4 + BitVec.ofNat 64 j by
        rw [BitVec.add_assoc, BitVec.ofNat_add]; rfl, write64, write32_lane _ _ _ j (by omega)]
    apply uint8_ofNat_congr
    simp only [BitVec.toNat_setWidth, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
    rcases (show j = 0 ∨ j = 1 ∨ j = 2 ∨ j = 3 by omega) with rfl | rfl | rfl | rfl <;> omega

theorem Heap.writeLE_bytes : ∀ (heap : Heap) (address value count other : Nat),
    (heap.writeLE address value count).bytes other =
      if address ≤ other ∧ other < address + count then UInt8.ofNat (value / 256 ^ (other - address))
      else heap.bytes other
  | heap, address, value, 0, other => by simp only [Heap.writeLE]; rw [if_neg (by omega)]
  | heap, address, value, count + 1, other => by
    rw [Heap.writeLE, Heap.writeLE_bytes]
    by_cases same : other = address
    · subst same
      rw [if_neg (by omega), if_pos ⟨Nat.le_refl _, by omega⟩]
      simp [Heap.write]
    · by_cases inside : address + 1 ≤ other ∧ other < address + 1 + count
      · rw [if_pos inside, if_pos ⟨by omega, by omega⟩, Nat.div_div_eq_div_mul,
          show other - address = (other - (address + 1)) + 1 by omega, Nat.pow_succ, Nat.mul_comm 256]
      · rw [if_neg inside, if_neg (by omega)]
        simp [Heap.write, same]

/-- x86 memory from `base` that agrees with a mini heap reads its words. -/
theorem memLE_heap (memory : Memory) (base : BitVec 64) (heap : Heap) :
    ∀ (address count : Nat), (∀ k < count, memory (base + BitVec.ofNat 64 (address + k)) = heap.bytes (address + k)) →
      memLE memory (base + BitVec.ofNat 64 address) count = heap.readLE address count
  | _, 0, _ => rfl
  | address, count + 1, agree => by
    rw [memLE, Heap.readLE, show base + BitVec.ofNat 64 address + 1 = base + BitVec.ofNat 64 (address + 1) by
        rw [BitVec.add_assoc, BitVec.ofNat_add]; rfl,
      memLE_heap memory base heap (address + 1) count (fun k lt => by
        rw [show address + 1 + k = address + (k + 1) by omega]; exact agree (k + 1) (by omega))]
    have := agree 0 (by omega)
    rw [Nat.add_zero] at this
    rw [this]

theorem MemWidth.bytes_le (width : MemWidth) : width.bytes ≤ 8 := by cases width <;> decide

/-- The word `width` reads at `address`, zero-extended. -/
def wordRead : MemWidth → Memory → BitVec 64 → BitVec 64
  | .m32, memory, address => (read32 memory address).setWidth 64
  | .m64, memory, address => read64 memory address

/-- Memory after `width` stores the low bytes of `value` at `address`. -/
def wordWrite : MemWidth → Memory → BitVec 64 → BitVec 64 → Memory
  | .m32, memory, address, value => write32 memory address (value.setWidth 32)
  | .m64, memory, address, value => write64 memory address value

theorem wordRead_eq (width : MemWidth) (memory : Memory) (address : BitVec 64) :
    wordRead width memory address = BitVec.ofNat 64 (memLE memory address width.bytes) := by
  cases width with
  | m32 =>
    apply BitVec.eq_of_toNat_eq
    have := memLE_lt memory address 4
    simp only [wordRead, BitVec.toNat_setWidth, read32_toNat, BitVec.toNat_ofNat, MemWidth.bytes]
  | m64 => exact read64_eq memory address

theorem wordWrite_lane (width : MemWidth) (memory : Memory) (address value : BitVec 64) (k : Nat)
    (lt : k < width.bytes) :
    wordWrite width memory address value (address + BitVec.ofNat 64 k) = UInt8.ofNat (value.toNat / 256 ^ k) := by
  cases width with
  | m32 =>
    simp only [MemWidth.bytes] at lt
    rw [wordWrite, write32_lane _ _ _ k lt]
    apply uint8_ofNat_congr
    simp only [BitVec.toNat_setWidth]
    rcases (show k = 0 ∨ k = 1 ∨ k = 2 ∨ k = 3 by omega) with rfl | rfl | rfl | rfl <;> omega
  | m64 => exact write64_lane memory address value k lt

theorem wordWrite_outside (width : MemWidth) (memory : Memory) (address value other : BitVec 64)
    (outside : ∀ k, k < width.bytes → other ≠ address + BitVec.ofNat 64 k) :
    wordWrite width memory address value other = memory other := by
  cases width with
  | m32 =>
    exact write32_frame _ _ _ _ ⟨by simpa using outside 0 (by decide), outside 1 (by decide),
      outside 2 (by decide), outside 3 (by decide)⟩
  | m64 => exact write64_frame _ _ _ _ fun lane => outside lane.val lane.isLt

/-- The word load: rax becomes the heap word at offset rax. -/
theorem loadWord_steps (s : State) (width : MemWidth) (loaded : CodeAt s.memory s.rip (loadWordSpec width)) :
    ∃ s', Steps 2 s s' ∧ Det 2 s s' ∧ s'.io = s.io ∧ s'.memory = s.memory ∧
      s'.rip = s.rip + BitVec.ofNat 64 (Instr.loadWordAt width).size ∧
      s'.registers 0 = wordRead width s.memory (s.registers heapBaseRegister + s.registers 0) ∧
      ∀ register, register ≠ 0 → s'.registers register = s.registers register := by
  have c0 := loaded
  let s1 := s.alu64 .add 0 heapBaseRegister false (aluBytes .w64 .add 0 heapBaseRegister).length
  cases width with
  | m32 =>
    simp only [loadWordSpec, MemWidth.x86] at c0
    have t1 : Lanius.X86.Machine.Step s s1 := alu_step .w64 s s1 .add _ _ c0.prefix false rfl
    have c1 := c0.next (s' := s1) rfl rfl
    let s2 := s1.load32 0 0 (BitVec.ofInt 32 0) (memoryBytes .w32 true 0 0 0).length
    have t2 : Lanius.X86.Machine.Step s1 s2 :=
      Lanius.X86.Machine.Step.decoded _ (CodeAt.prefix (rest := []) (by simpa using c1)) _ _
        (by simpa [memoryInstruction] using memory_decodes .w32 true 0 0 0 []) rfl rfl
    refine ⟨s2, .cons t1 (.cons t2 (.refl _)),
      Det.cons t1 (alu_noRead c0.prefix)
        (Det.cons t2 (memory_noRead (CodeAt.prefix (rest := []) (by simpa using c1))) (Det.refl _)),
      rfl, rfl, ?_, ?_, ?_⟩
    · simp only [s2, s1, State.load32, State.immediate32, State.alu64, State.alu, Instr.size, MemWidth.prefix]
      rw [show (aluBytes .w64 .add 0 heapBaseRegister).length = 3 from rfl,
        show (memoryBytes .w32 true 0 0 0).length = 6 from rfl]
      bv_omega
    · simp only [s2, s1, State.load32, State.immediate32, State.alu64, State.alu, Alu.result, BitVec.setWidth_eq,
        if_pos, show (BitVec.ofInt 32 0).signExtend 64 = 0 from by decide, BitVec.add_comm (s.registers 0),
        wordRead]
      simp
    · intro register zero
      simp [s2, s1, State.load32, State.immediate32, State.alu64, State.alu, zero]
  | m64 =>
    simp only [loadWordSpec, MemWidth.x86] at c0
    have t1 : Lanius.X86.Machine.Step s s1 := alu_step .w64 s s1 .add _ _ c0.prefix false rfl
    have c1 := c0.next (s' := s1) rfl rfl
    let s2 := s1.load64 0 0 (BitVec.ofInt 32 0) (memoryBytes .w64 true 0 0 0).length
    have t2 : Lanius.X86.Machine.Step s1 s2 :=
      Lanius.X86.Machine.Step.decoded _ (CodeAt.prefix (rest := []) (by simpa using c1)) _ _
        (by simpa [memoryInstruction] using memory_decodes .w64 true 0 0 0 []) rfl rfl
    refine ⟨s2, .cons t1 (.cons t2 (.refl _)),
      Det.cons t1 (alu_noRead c0.prefix)
        (Det.cons t2 (memory_noRead (CodeAt.prefix (rest := []) (by simpa using c1))) (Det.refl _)),
      rfl, rfl, ?_, ?_, ?_⟩
    · simp only [s2, s1, State.load64, State.alu64, State.alu, Instr.size, MemWidth.prefix]
      rw [show (aluBytes .w64 .add 0 heapBaseRegister).length = 3 from rfl,
        show (memoryBytes .w64 true 0 0 0).length = 7 from rfl]
      bv_omega
    · simp only [s2, s1, State.load64, State.alu64, State.alu, Alu.result, BitVec.setWidth_eq,
        if_pos, show (BitVec.ofInt 32 0).signExtend 64 = 0 from by decide, BitVec.add_comm (s.registers 0),
        wordRead]
      simp
    · intro register zero
      simp [s2, s1, State.load64, State.alu64, State.alu, zero]

/-- The word store: the low bytes of rax go to the heap at the offset in `slot`. -/
theorem storeWord_steps (s : State) (width : MemWidth) (slot : Nat)
    (loaded : CodeAt s.memory s.rip (storeWordSpec width slot)) :
    ∃ s', Steps 3 s s' ∧ Det 3 s s' ∧ s'.io = s.io ∧ s'.rip = s.rip + BitVec.ofNat 64 (Instr.storeWordAt width slot).size ∧
      s'.memory = wordWrite width s.memory (s.registers heapBaseRegister +
          read64 s.memory (s.registers rbpRegister + (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64))
        (s.registers 0) ∧
      ∀ register, register ≠ rcxRegister → s'.registers register = s.registers register := by
  have c0 := loaded
  let s1 := s.load64 rcxRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement slot))
    (memoryBytes .w64 true rcxRegister rbpRegister (frameDisplacement slot)).length
  let s2 := s1.alu64 .add rcxRegister heapBaseRegister false (aluBytes .w64 .add rcxRegister heapBaseRegister).length
  cases width with
  | m32 =>
    simp only [storeWordSpec, MemWidth.x86] at c0
    have t1 : Lanius.X86.Machine.Step s s1 :=
      Lanius.X86.Machine.Step.decoded _ c0.prefix _ _
        (by simpa [memoryInstruction] using
          memory_decodes .w64 true rcxRegister rbpRegister (frameDisplacement slot) [])
        rfl rfl
    have c1 := c0.next (s' := s1) rfl rfl
    have t2 : Lanius.X86.Machine.Step s1 s2 := alu_step .w64 s1 s2 .add _ _ c1.prefix false rfl
    have c2 := c1.next (s' := s2) rfl rfl
    let s3 := s2.store32 0 rcxRegister (BitVec.ofInt 32 0) (memoryBytes .w32 false 0 rcxRegister 0).length
    have t3 : Lanius.X86.Machine.Step s2 s3 :=
      Lanius.X86.Machine.Step.decoded _ (CodeAt.prefix (rest := []) (by simpa using c2)) _ _
        (by simpa [memoryInstruction] using memory_decodes .w32 false 0 rcxRegister 0 []) rfl rfl
    refine ⟨s3, .cons t1 (.cons t2 (.cons t3 (.refl _))),
      Det.cons t1 (memory_noRead c0.prefix) (Det.cons t2 (alu_noRead c1.prefix)
        (Det.cons t3 (memory_noRead (CodeAt.prefix (rest := []) (by simpa using c2))) (Det.refl _))),
      rfl, ?_, ?_, ?_⟩
    · simp only [s3, s2, s1, State.store32, State.alu64, State.alu, State.load64, Instr.size, MemWidth.prefix]
      rw [show (memoryBytes .w64 true rcxRegister rbpRegister (frameDisplacement slot)).length = 7 from by
          simp only [memoryBytes, memoryHeader, Lanius.Semantics.i32Bytes, List.length_append, List.length_map,
            List.length_range]; decide,
        show (aluBytes .w64 .add rcxRegister heapBaseRegister).length = 3 from rfl,
        show (memoryBytes .w32 false 0 rcxRegister 0).length = 6 from rfl]
      bv_omega
    · simp only [s3, s2, s1, State.store32, State.alu64, State.alu, State.load64, Alu.result, BitVec.setWidth_eq,
        if_pos, show (BitVec.ofInt 32 0).signExtend 64 = 0 from by decide,
        if_neg (show (0 : Register) ≠ rcxRegister by decide),
        if_neg (show heapBaseRegister ≠ rcxRegister by decide), wordWrite]
      congr 1
      bv_omega
    · intro register one
      simp [s3, s2, s1, State.store32, State.alu64, State.alu, State.load64, one]
  | m64 =>
    simp only [storeWordSpec, MemWidth.x86] at c0
    have t1 : Lanius.X86.Machine.Step s s1 :=
      Lanius.X86.Machine.Step.decoded _ c0.prefix _ _
        (by simpa [memoryInstruction] using
          memory_decodes .w64 true rcxRegister rbpRegister (frameDisplacement slot) [])
        rfl rfl
    have c1 := c0.next (s' := s1) rfl rfl
    have t2 : Lanius.X86.Machine.Step s1 s2 := alu_step .w64 s1 s2 .add _ _ c1.prefix false rfl
    have c2 := c1.next (s' := s2) rfl rfl
    let s3 := s2.store64 0 rcxRegister (BitVec.ofInt 32 0) (memoryBytes .w64 false 0 rcxRegister 0).length
    have t3 : Lanius.X86.Machine.Step s2 s3 :=
      Lanius.X86.Machine.Step.decoded _ (CodeAt.prefix (rest := []) (by simpa using c2)) _ _
        (by simpa [memoryInstruction] using memory_decodes .w64 false 0 rcxRegister 0 []) rfl rfl
    refine ⟨s3, .cons t1 (.cons t2 (.cons t3 (.refl _))),
      Det.cons t1 (memory_noRead c0.prefix) (Det.cons t2 (alu_noRead c1.prefix)
        (Det.cons t3 (memory_noRead (CodeAt.prefix (rest := []) (by simpa using c2))) (Det.refl _))),
      rfl, ?_, ?_, ?_⟩
    · simp only [s3, s2, s1, State.store64, State.alu64, State.alu, State.load64, Instr.size, MemWidth.prefix]
      rw [show (memoryBytes .w64 true rcxRegister rbpRegister (frameDisplacement slot)).length = 7 from by
          simp only [memoryBytes, memoryHeader, Lanius.Semantics.i32Bytes, List.length_append, List.length_map,
            List.length_range]; decide,
        show (aluBytes .w64 .add rcxRegister heapBaseRegister).length = 3 from rfl,
        show (memoryBytes .w64 false 0 rcxRegister 0).length = 7 from rfl]
      bv_omega
    · simp only [s3, s2, s1, State.store64, State.alu64, State.alu, State.load64, Alu.result, BitVec.setWidth_eq,
        if_pos, show (BitVec.ofInt 32 0).signExtend 64 = 0 from by decide,
        if_neg (show (0 : Register) ≠ rcxRegister by decide),
        if_neg (show heapBaseRegister ≠ rcxRegister by decide), wordWrite]
      congr 1
      bv_omega
    · intro register one
      simp [s3, s2, s1, State.store64, State.alu64, State.alu, State.load64, one]

end Lanius.Mini
