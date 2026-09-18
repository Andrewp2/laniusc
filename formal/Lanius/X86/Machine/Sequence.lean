import Lanius.X86.Machine.Scalar

namespace Lanius.X86.Machine

/-- A decoded, straight-line instruction that does not write memory.
This proof combinator is not another compiler or an output validator. -/
structure ReadOnly where
  instruction : Instruction
  bytes : List UInt8
  decoded : decode bytes = some (instruction, bytes.length)
  memory : ∀ before, (execute instruction bytes.length before).memory = before.memory
  rip : ∀ before, (execute instruction bytes.length before).rip = before.rip + BitVec.ofNat 64 bytes.length

namespace ReadOnly

def code (instructions : List ReadOnly) : List UInt8 := instructions.flatMap (·.bytes)

def run : List ReadOnly → State → State
  | [], before => before
  | first :: rest, before => run rest (execute first.instruction first.bytes.length before)

theorem fields (instructions : List ReadOnly) (before : State) :
    (run instructions before).memory = before.memory ∧
      (run instructions before).rip = before.rip + BitVec.ofNat 64 (code instructions).length := by
  induction instructions generalizing before with
  | nil => simp [run, code]
  | cons first rest ih =>
    have tail := ih (execute first.instruction first.bytes.length before)
    simp only [run, code, List.flatMap_cons, List.length_append] at *
    exact ⟨tail.1.trans (first.memory before), by
      rw [tail.2, first.rip]; simp [BitVec.ofNat_add, BitVec.add_assoc]⟩

/-- Loaded instruction bytes compose into actual machine steps. Memory
preservation carries the remaining code through every intermediate state. -/
theorem steps (instructions : List ReadOnly) (before : State)
    (loaded : CodeAt before.memory before.rip (code instructions)) :
    Steps instructions.length before (run instructions before) := by
  induction instructions generalizing before with
  | nil => exact .refl _
  | cons first rest ih =>
    let middle := execute first.instruction first.bytes.length before
    have remaining : CodeAt middle.memory middle.rip (code rest) := by
      rw [show middle.memory = before.memory from first.memory before,
        show middle.rip = before.rip + BitVec.ofNat 64 first.bytes.length from first.rip before]
      exact loaded.suffix
    exact .cons (.decoded _ loaded.prefix _ _ first.decoded rfl) (ih middle remaining)

end ReadOnly
end Lanius.X86.Machine
