import Lanius.X86.Machine.Encoding

namespace Lanius.X86.Machine.Copy

/-- The two instructions emitted for each internal value word by
`backend::value::copy`: RAX and R11 stay fixed; only R10 is scratched. -/
def wordBytes (index : Nat) : List UInt8 :=
  memoryBytes .w64 true 10 0 (index * 8) ++ memoryBytes .w64 false 10 11 (index * 8)

def bytes (start : Nat) : Nat → List UInt8
  | 0 => []
  | count + 1 => wordBytes start ++ bytes (start + 1) count

def address (base : Address) (index : Nat) : Address := base + BitVec.ofNat 64 (index * 8)

def word (before : State) (index : Nat) : State :=
  let loaded := before.load64 10 0 (BitVec.ofNat 32 (index * 8)) (memoryBytes .w64 true 10 0 (index * 8)).length
  loaded.store64 10 11 (BitVec.ofNat 32 (index * 8)) (memoryBytes .w64 false 10 11 (index * 8)).length

theorem offset (index : Nat) (bounded : index ≤ 4096) :
    (BitVec.ofNat 32 (index * 8)).signExtend 64 = BitVec.ofNat 64 (index * 8) := by
  have signed : (BitVec.ofNat 32 (index * 8)).toInt = (index * 8 : Nat) := by
    rw [← BitVec.ofInt_natCast]
    apply BitVec.toInt_ofInt_eq_self (by decide) <;> omega
  simp only [BitVec.signExtend, signed, BitVec.ofInt_natCast]

theorem word_fields (before : State) (index : Nat) (bounded : index ≤ 4096) :
    (word before index).memory = write64 before.memory (address (before.registers 11) index)
      (read64 before.memory (address (before.registers 0) index)) ∧
    (∀ register, register ≠ 10 → (word before index).registers register = before.registers register) ∧
    (word before index).flags = before.flags ∧
    (word before index).rip = before.rip + BitVec.ofNat 64 (wordBytes index).length := by
  simp [word, State.load64, State.store64, offset index bounded, address, wordBytes,
    List.length_append, BitVec.ofNat_add, BitVec.add_assoc]
  intro register different equal
  exact False.elim (different equal)

theorem word_steps (before : State) (index : Nat)
    (loaded : CodeAt before.memory before.rip (wordBytes index)) :
    Steps 2 before (word before index) := by
  let middle := before.load64 10 0 (BitVec.ofNat 32 (index * 8)) (memoryBytes .w64 true 10 0 (index * 8)).length
  have readStep : Step before middle := .decoded _ loaded.prefix _ _
    (by simpa only [List.append_nil, BitVec.ofInt_natCast] using memory_decodes .w64 true 10 0 (index * 8) []) rfl
  have writeCode : CodeAt middle.memory middle.rip (memoryBytes .w64 false 10 11 (index * 8)) := loaded.suffix
  have writeStep : Step middle (word before index) := .decoded _ writeCode _ _
    (by simpa only [List.append_nil, BitVec.ofInt_natCast] using memory_decodes .w64 false 10 11 (index * 8) []) rfl
  exact .cons readStep (.cons writeStep (.refl _))

/-- The final bytes outside the destination survive. This supplies source,
caller-frame, other-local, and code preservation from their separation facts. -/
def Outside (base : Address) (start count : Nat) (candidate : Address) : Prop :=
  ∀ index, index < count → ∀ lane : Fin 8,
    candidate ≠ address base (start + index) + BitVec.ofNat 64 lane.val

def Separated (source destination : Address) (start count : Nat) : Prop :=
  ∀ index, index < count → ∀ lane : Fin 8,
    Outside destination start count (address source (start + index) + BitVec.ofNat 64 lane.val)

structure Result (before after : State) (start count : Nat) : Prop where
  steps : Steps (count * 2) before after
  copied : ∀ index, index < count →
    read64 after.memory (address (before.registers 11) (start + index)) =
      read64 before.memory (address (before.registers 0) (start + index))
  frame : ∀ candidate, Outside (before.registers 11) start count candidate → after.memory candidate = before.memory candidate
  registers : ∀ register, register ≠ 10 → after.registers register = before.registers register
  flags : after.flags = before.flags
  rip : after.rip = before.rip + BitVec.ofNat 64 (bytes start count).length

private theorem different_words (base : Address) (left right : Nat) (different : left ≠ right)
    (leftBound : left ≤ 4096) (rightBound : right ≤ 4096) (i j : Fin 8) :
    address base left + BitVec.ofNat 64 i.val ≠ address base right + BitVec.ofNat 64 j.val := by
  have ib := i.isLt
  have jb := j.isLt
  simpa [address, BitVec.ofNat_add, BitVec.add_assoc] using
    offset_ne base (left * 8 + i.val) (right * 8 + j.val) (by omega) (by omega) (by omega)

/-- A whole aggregate copy executes decoded x86, preserves every source
word, and changes no byte outside its destination. The 4096-word bound is
the actual internal value-size limit; disjoint source/destination windows
are required, as in the Lanius compiler's snapshot allocation discipline.
This theorem does not yet prove the Lanius emitter produces these bytes. -/
theorem correct (count : Nat) (before : State) (start : Nat) (bounded : start + count ≤ 4096)
    (loaded : CodeAt before.memory before.rip (bytes start count))
    (separate : Separated (before.registers 0) (before.registers 11) start count)
    (codeSeparate : ∀ index, index < (bytes start count).length →
      Outside (before.registers 11) start count (before.rip + BitVec.ofNat 64 index)) :
    ∃ after, Result before after start count := by
  induction count generalizing before start with
  | zero =>
      refine ⟨before, ⟨.refl _, ?_, ?_, ?_, rfl, ?_⟩⟩
      · intro index bound; omega
      · intro candidate outside; rfl
      · intro register different; rfl
      · simp [bytes]
  | succ count ih =>
      let middle := word before start
      have fields := word_fields before start (by omega)
      have pointers : middle.registers 0 = before.registers 0 ∧ middle.registers 11 = before.registers 11 :=
        ⟨fields.2.1 0 (by decide), fields.2.1 11 (by decide)⟩
      have preserved : CodeAt middle.memory before.rip (bytes start (count + 1)) := by
        rw [fields.1]
        apply loaded.write64
        intro index indexBound lane
        simpa using codeSeparate index indexBound 0 (by omega) lane
      have nextCode : CodeAt middle.memory middle.rip (bytes (start + 1) count) := by
        rw [fields.2.2.2]
        exact preserved.suffix
      have nextSeparate : Separated (middle.registers 0) (middle.registers 11) (start + 1) count := by
        rw [pointers.1, pointers.2]
        intro index indexBound lane other otherBound otherLane
        simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
          separate (index + 1) (by omega) lane (other + 1) (by omega) otherLane
      have nextCodeSeparate : ∀ index, index < (bytes (start + 1) count).length →
          Outside (middle.registers 11) (start + 1) count (middle.rip + BitVec.ofNat 64 index) := by
        intro index indexBound other otherBound lane
        rw [pointers.2, fields.2.2.2]
        have disjoint := codeSeparate ((wordBytes start).length + index)
          (by simp only [bytes, List.length_append]; omega) (other + 1) (by omega) lane
        simpa only [Nat.add_assoc, Nat.add_comm other 1, BitVec.ofNat_add,
          BitVec.add_assoc] using disjoint
      obtain ⟨after, rest⟩ := ih middle (start + 1) (by omega) nextCode nextSeparate nextCodeSeparate
      refine ⟨after, ⟨?_, ?_, ?_, ?_, rest.flags.trans fields.2.2.1, ?_⟩⟩
      · have steps := (word_steps before start loaded.prefix).trans rest.steps
        simpa [Nat.add_mul, Nat.add_comm] using steps
      · intro index indexBound
        cases index with
        | zero =>
            simp only [Nat.add_zero]
            have same : read64 after.memory (address (before.registers 11) start) =
                read64 middle.memory (address (before.registers 11) start) := by
              apply read64_congr
              intro lane
              apply rest.frame
              rw [pointers.2]
              intro other otherBound otherLane
              exact different_words _ _ _ (by omega) (by omega) (by omega) lane otherLane
            rw [same, fields.1, read64_write64]
        | succ index =>
            have copied := rest.copied index (by omega)
            rw [pointers.1, pointers.2] at copied
            have unchanged : read64 middle.memory (address (before.registers 0) (start + 1 + index)) =
                read64 before.memory (address (before.registers 0) (start + 1 + index)) := by
              rw [fields.1]
              apply read64_frame
              intro lane otherLane
              simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
                separate (index + 1) (by omega) lane 0 (by omega) otherLane
            simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using copied.trans unchanged
      · intro candidate outside
        have tailOutside : Outside (middle.registers 11) (start + 1) count candidate := by
          rw [pointers.2]
          intro index bound lane
          simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using outside (index + 1) (by omega) lane
        rw [rest.frame candidate tailOutside, fields.1]
        apply write64_frame
        intro lane
        simpa using outside 0 (by omega) lane
      · intro register different
        exact (rest.registers register different).trans (fields.2.1 register different)
      · rw [rest.rip, fields.2.2.2]
        simp [bytes, List.length_append, BitVec.ofNat_add, BitVec.add_assoc]

end Lanius.X86.Machine.Copy
