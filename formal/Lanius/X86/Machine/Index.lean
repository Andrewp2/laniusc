import Lanius.X86.Machine.Sequence
import Lanius.X86.Frame.Execution

namespace Lanius.X86.Machine.Index

def normalize : ReadOnly := {
  instruction := .signExtend32 0 0
  bytes := [0x48, 0x63, 0xc0]
  decoded := by decide
  memory := fun _ => rfl
  rip := fun _ => rfl }

def load (destination base : Register) (displacement : Int) : ReadOnly := {
  instruction := .load64 destination base (BitVec.ofInt 32 displacement)
  bytes := memoryBytes .w64 true destination base displacement
  decoded := by simpa [memoryInstruction] using memory_decodes .w64 true destination base displacement []
  memory := fun _ => rfl
  rip := fun _ => rfl }

def compare : ReadOnly := {
  instruction := .compare64 0 10
  bytes := [0x4c, 0x39, 0xd0]
  decoded := by decide
  memory := fun _ => rfl
  rip := fun _ => rfl }

def address : ReadOnly := {
  instruction := .address64 0 11 (some 0) 2 0
  bytes := [0x49, 0x8d, 0x84, 0x83, 0, 0, 0, 0]
  decoded := by decide
  memory := fun _ => rfl
  rip := fun _ => rfl }

def prepare (signed : Bool) (slot : Nat) : List ReadOnly :=
  (if signed then [normalize] else []) ++
    [load 11 5 (Frame.displacement slot), load 10 11 8, load 11 11 0, compare]

def guard : List UInt8 := [0x0f, 0x82, 2, 0, 0, 0, 0x0f, 0x0b]

def bytes (signed : Bool) (slot : Nat) : List UInt8 :=
  ReadOnly.code (prepare signed slot) ++ guard ++ address.bytes

def word (signed : Bool) (raw : BitVec 64) : BitVec 64 :=
  if signed then (raw.setWidth 32).signExtend 64 else raw

theorem prepare_fields (before : State) (signed : Bool) (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576) (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (descriptor data : Address) (length : BitVec 64)
    (saved : read64 before.memory (layout.address slot) = descriptor)
    (pointer : read64 before.memory descriptor = data)
    (extent : read64 before.memory (descriptor + 8#64) = length) :
    let after := ReadOnly.run (prepare signed slot.val) before
    after.registers 0 = word signed (before.registers 0) ∧
      after.registers 10 = length ∧ after.registers 11 = data ∧
      (∀ register, register ≠ 0 → register ≠ 10 → register ≠ 11 →
        after.registers register = before.registers register) ∧
      after.flags = subtractFlags before.flags (word signed (before.registers 0)) length := by
  have operand := layout.operand slot bounded frame
  cases signed <;>
    simp [prepare, ReadOnly.run, normalize, load, compare, execute,
      State.signExtend32, State.load64, State.compare64, word, operand, saved, pointer, extent]
  all_goals
    intro register notZero notTen notEleven
    simp [notZero, notTen, notEleven]

theorem guard_decodes (tail : List UInt8) :
    decode (guard ++ tail) = some (.branch 2 2, 6) := by rfl

/-- The checked-address sequence reads only the saved descriptor, never an
array element. The unsigned comparison controls whether execution reaches
LEA or raises #UD; every unrelated register and every byte are preserved. -/
theorem correct (before : State) (signed : Bool) (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576) (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (descriptor data : Address) (length : BitVec 64)
    (saved : read64 before.memory (layout.address slot) = descriptor)
    (pointer : read64 before.memory descriptor = data)
    (extent : read64 before.memory (descriptor + 8#64) = length)
    (loaded : CodeAt before.memory before.rip (bytes signed slot.val)) :
    let index := word signed (before.registers 0)
    if index.toNat < length.toNat then
      ∃ after, Steps ((prepare signed slot.val).length + 2) before after ∧
        after.registers 0 = data + index * 4 ∧ after.memory = before.memory ∧
        after.rip = before.rip + BitVec.ofNat 64 (bytes signed slot.val).length ∧
        (∀ register, register ≠ 0 → register ≠ 10 → register ≠ 11 →
          after.registers register = before.registers register) ∧
        after.flags.getLsbD 10 = before.flags.getLsbD 10
    else
      ∃ after, Steps ((prepare signed slot.val).length + 1) before after ∧ Fault after ∧
        after.memory = before.memory ∧ after.registers 0 = index := by
  let middle := ReadOnly.run (prepare signed slot.val) before
  let branched := middle.branch 2 2 6
  have fields := prepare_fields before signed layout slot bounded frame descriptor data length saved pointer extent
  have memory := (ReadOnly.fields (prepare signed slot.val) before).1
  have rip := (ReadOnly.fields (prepare signed slot.val) before).2
  have start : Steps (prepare signed slot.val).length before middle :=
    ReadOnly.steps _ before (show CodeAt before.memory before.rip
      (ReadOnly.code (prepare signed slot.val)) from
        (show CodeAt before.memory before.rip (ReadOnly.code (prepare signed slot.val) ++
          (guard ++ address.bytes)) from by simpa [bytes, List.append_assoc] using loaded).prefix)
  have guardCode : CodeAt middle.memory middle.rip (guard ++ address.bytes) := by
    rw [memory, rip]
    exact (show CodeAt before.memory before.rip
      (ReadOnly.code (prepare signed slot.val) ++ (guard ++ address.bytes)) from by
        simpa [bytes, List.append_assoc] using loaded).suffix
  have branchStep : Step middle branched := .decoded _ guardCode _ _ (guard_decodes address.bytes) rfl
  have selected : condition middle.flags 2 = decide ((word signed (before.registers 0)).toNat < length.toNat) := by
    rw [fields.2.2.2.2]
    exact compare_below _ _ _
  dsimp only
  split <;> rename_i inside
  · let after := execute address.instruction address.bytes.length branched
    have branchRip : branched.rip = middle.rip + 8 := by
      simp [branched, State.branch, selected, inside, BitVec.add_assoc]
    have addressCode : CodeAt branched.memory branched.rip address.bytes := by
      rw [show branched.memory = middle.memory from rfl, branchRip]
      exact guardCode.suffix
    have addressStep : Step branched after := .decoded _ addressCode _ _ address.decoded rfl
    refine ⟨after, ?_, ?_, memory, ?_, ?_, ?_⟩
    · simpa using start.trans (.cons branchStep (.cons addressStep (.refl _)))
    · change middle.registers 11 + middle.registers 0 * 4 + 0 = _
      rw [fields.2.2.1, fields.1]
      simp
    · change branched.rip + BitVec.ofNat 64 address.bytes.length = _
      rw [branchRip, rip]
      simp [bytes, List.length_append, guard, address, BitVec.ofNat_add, BitVec.add_assoc]
    · intro register notZero notTen notEleven
      change (if register = 0 then _ else middle.registers register) = _
      rw [if_neg notZero]
      exact fields.2.2.2.1 register notZero notTen notEleven
    · change middle.flags.getLsbD 10 = _
      rw [fields.2.2.2.2]
      exact subtractFlags_direction _ _ _
  · have branchRip : branched.rip = middle.rip + 6 := by
      simp [branched, State.branch, selected, inside]
    have faultCode : CodeAt branched.memory branched.rip [15, 11] := by
      rw [show branched.memory = middle.memory from rfl, branchRip]
      exact (show CodeAt middle.memory middle.rip
        ([15, 130, 2, 0, 0, 0] ++ ([15, 11] ++ address.bytes)) from guardCode).suffix.prefix
    exact ⟨branched, by simpa using start.trans (.cons branchStep (.refl _)), .ud2 faultCode,
      memory, fields.1⟩

end Lanius.X86.Machine.Index
