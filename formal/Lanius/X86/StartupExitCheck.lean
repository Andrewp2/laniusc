import Lanius.X86.ProcessLayoutCheck

namespace Lanius.X86.StartupExitCheck

open Lanius Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.StartupCheck
open Lanius.X86.ProcessLayoutCheck

def afterResultMove (before : Machine.State) : Machine.State :=
  before.move32 rdi rax returnResult.length

def afterExitLoad (before : Machine.State) : Machine.State :=
  (afterResultMove before).immediate32 rax (BitVec.ofNat 32 60) loadExit.length

structure ReturnExitEvidence (elf : List UInt8) (before : Machine.State)
    (result : BitVec 32) : Type where
  startup : StartupEvidence elf
  mapped : CodeAt before.memory base elf
  ripAtReturn : before.rip = startupReturnAddress
  raxAtReturn : (before.registers rax).setWidth 32 = result

structure ReturnExitResult (before after : Machine.State) (result : BitVec 32) : Prop where
  steps : Steps 2 before after
  ripAtSyscall : after.rip = startupExitAddress
  rdiAtSyscall : after.registers rdi = result.setWidth 64
  raxAtSyscall : after.registers rax = BitVec.ofNat 64 60
  memoryPreserved : after.memory = before.memory
  syscallLoaded : CodeAt after.memory after.rip syscallBytes

theorem return_result_address :
    entry + BitVec.ofNat 64 startupPrefix.length = startupReturnAddress := by
  decide

theorem load_exit_address :
    startupReturnAddress + BitVec.ofNat 64 returnResult.length =
      entry + BitVec.ofNat 64 (startupPrefix.length + returnResult.length) := by
  rw [← return_result_address, BitVec.add_assoc, ← BitVec.ofNat_add]

theorem suffix_syscall_address :
    entry + BitVec.ofNat 64
        (startupPrefix.length + returnResult.length + loadExit.length) =
      startupExitAddress := by
  decide

theorem reaches_syscall {elf : List UInt8} {before : Machine.State}
    {result : BitVec 32} (evidence : ReturnExitEvidence elf before result) :
    ReturnExitResult before (afterExitLoad before) result := by
  have loaded := evidence.startup.loaded evidence.mapped
  have returnTail : CodeAt before.memory
      (entry + BitVec.ofNat 64 startupPrefix.length)
      (returnResult ++ loadExit ++ syscallBytes ++ ud2Bytes) := by
    exact CodeAt.suffix (first := startupPrefix)
      (rest := returnResult ++ loadExit ++ syscallBytes ++ ud2Bytes) loaded
  have returnLoaded : CodeAt before.memory before.rip returnResult := by
    rw [evidence.ripAtReturn, ← return_result_address]
    exact CodeAt.prefix (first := returnResult)
      (rest := loadExit ++ syscallBytes ++ ud2Bytes) returnTail
  have exitTail : CodeAt before.memory
      (entry + BitVec.ofNat 64
        (startupPrefix.length + returnResult.length + loadExit.length)) syscallBytes := by
    have tail := CodeAt.suffix
      (first := startupPrefix ++ returnResult ++ loadExit)
      (rest := syscallBytes ++ ud2Bytes) loaded
    exact CodeAt.prefix tail
  have exitLoaded : CodeAt (afterResultMove before).memory
      (afterResultMove before).rip loadExit := by
    have tail := CodeAt.suffix
      (first := startupPrefix ++ returnResult)
      (rest := loadExit ++ syscallBytes ++ ud2Bytes) loaded
    have loadLoaded : CodeAt before.memory
        (entry + BitVec.ofNat 64 (startupPrefix.length + returnResult.length))
        loadExit := CodeAt.prefix (first := loadExit)
          (rest := syscallBytes ++ ud2Bytes) tail
    change CodeAt before.memory
      (before.rip + BitVec.ofNat 64 returnResult.length) loadExit
    rw [evidence.ripAtReturn, load_exit_address]
    exact loadLoaded
  have moved : Step before (afterResultMove before) := by
    apply move_step before (afterResultMove before) .w32 rdi rax returnLoaded
    rfl
  have loadedAfterMove : CodeAt (afterExitLoad before).memory
      (afterExitLoad before).rip syscallBytes := by
    have address : (afterExitLoad before).rip = startupExitAddress := by
      simp [afterExitLoad, afterResultMove, Machine.State.immediate32,
        Machine.State.move32, evidence.ripAtReturn, startupExitAddress,
        BitVec.add_assoc]
      rw [← BitVec.ofNat_add]
    change CodeAt before.memory (afterExitLoad before).rip syscallBytes
    rw [address, ← suffix_syscall_address]
    exact exitTail
  have loadedStep : Step (afterResultMove before) (afterExitLoad before) := by
    apply immediate_step (afterResultMove before) (afterExitLoad before)
      .w32 rax (BitVec.ofNat 32 60) 0 exitLoaded
    rfl
  have allSteps : Steps 2 before (afterExitLoad before) :=
    Steps.cons moved (Steps.cons loadedStep (Steps.refl _))
  refine ⟨allSteps, ?_, ?_, ?_, ?_, loadedAfterMove⟩
  · simp [afterExitLoad, afterResultMove, Machine.State.immediate32,
      Machine.State.move32, evidence.ripAtReturn, startupExitAddress,
      BitVec.add_assoc]
    rw [← BitVec.ofNat_add]
  · simp [afterExitLoad, afterResultMove, Machine.State.immediate32,
      Machine.State.move32, rdi, rax]
    have hRax : (before.registers 0).setWidth 32 = result := by
      simpa [rax] using evidence.raxAtReturn
    rw [hRax]
  · simp [afterExitLoad, Machine.State.immediate32, rax]
  · rfl

/- The syscall itself remains a host transition.  This composition theorem
   exposes that boundary without assigning Linux-specific behavior to it. -/
theorem reaches_syscall_transition {Host World : Type}
    {elf : List UInt8} {before : Machine.State} {result : BitVec 32}
    (evidence : ReturnExitEvidence elf before result)
    (dispatch : SyscallHostRelation Host World) (host : Host) (world : World)
    (handler maskedFlags : BitVec 64) (after : Machine.State) (world' : World)
    (syscallResult : BitVec 64)
    (hostStep : dispatch host world (afterExitLoad before) syscallResult
      after.memory world')
    (rip : after.rip = handler) (flags : after.flags = maskedFlags)
    (raxAfter : after.registers 0 = syscallResult)
    (rcx : after.registers 1 = (afterExitLoad before).rip +
      BitVec.ofNat 64 syscallBytes.length)
    (r11 : after.registers 11 = (afterExitLoad before).flags)
    (preserved : ∀ register : Register, register ≠ 0 → register ≠ 1 →
      register ≠ 11 → after.registers register =
        (afterExitLoad before).registers register) :
    Steps 2 before (afterExitLoad before) ∧
      syscallTransition dispatch host world handler maskedFlags
        (afterExitLoad before) after world' := by
  have reached := reaches_syscall evidence
  refine ⟨reached.steps, ?_⟩
  exact syscallTransition_intro dispatch host world handler maskedFlags
    (afterExitLoad before) after world' syscallResult hostStep rip flags
    raxAfter rcx r11 preserved

end Lanius.X86.StartupExitCheck
