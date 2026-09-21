import Lanius.X86.Encoding
import Lanius.X86.Control.Decode
import Lanius.X86.Machine.Scalar

namespace Lanius.X86.Machine

open Lanius.X86

/-! Fixed control instructions used at the runtime boundary.  Their byte
    identity is shared with `Control.decode`; no operating-system behavior is
    placed in the pure machine `Step` relation. -/

def fixedBytes (instruction : Control.Fixed) : List UInt8 :=
  instruction.bytes.map UInt8.ofNat

def ud2Bytes : List UInt8 := fixedBytes .ud2

def syscallBytes : List UInt8 := fixedBytes .syscall

def controlDecode : List UInt8 → Option (Control.Instruction × Nat) := Control.decode

theorem ud2_decodes (tail : List UInt8) :
    controlDecode (ud2Bytes ++ tail) = some (.ud2, ud2Bytes.length) := by
  simpa [controlDecode, ud2Bytes, fixedBytes, Control.Fixed.bytes, Control.Fixed.instruction]
    using Control.Fixed.decode .ud2 tail

theorem syscall_decodes (tail : List UInt8) :
    controlDecode (syscallBytes ++ tail) = some (.syscall, syscallBytes.length) := by
  simpa [controlDecode, syscallBytes, fixedBytes, Control.Fixed.bytes, Control.Fixed.instruction]
    using Control.Fixed.decode .syscall tail

theorem ud2_decode_exact :
    controlDecode ud2Bytes = some (.ud2, ud2Bytes.length) := by
  simpa using ud2_decodes []

theorem syscall_decode_exact :
    controlDecode syscallBytes = some (.syscall, syscallBytes.length) := by
  simpa using syscall_decodes []

theorem ud2_fault (before : State)
    (loaded : CodeAt before.memory before.rip ud2Bytes) : Fault before := by
  simpa [ud2Bytes, fixedBytes, Control.Fixed.bytes] using Fault.ud2 loaded

theorem ud2_fault_bridge (before : State)
    (loaded : CodeAt before.memory before.rip ud2Bytes)
    (_decoded : controlDecode ud2Bytes = some (.ud2, ud2Bytes.length)) :
    Fault before :=
  ud2_fault before loaded

/- A host/world relation supplies exactly the effects that the CPU model
   cannot choose.  The host receives the complete user state and syscall
   result, and returns a memory and world state.  In particular, this does
   not mention Linux services or errno conventions. -/
abbrev SyscallHostRelation (Host World : Type) :=
  Host → World → State → BitVec 64 → Memory → World → Prop

/- The architectural names in this subset use RAX=0, RCX=1, RDX=2,
   RSP=4, and R11=11.  `syscallTransition` leaves the handler target and
   masked flags explicit, while the relation supplies the result and world
   effects. -/
def syscallTransition {Host World : Type}
    (dispatch : SyscallHostRelation Host World)
    (host : Host) (world : World) (handler : Address) (maskedFlags : BitVec 64)
    (before after : State) (world' : World) : Prop :=
  ∃ result : BitVec 64,
    dispatch host world before result after.memory world' ∧
    after.rip = handler ∧
    after.flags = maskedFlags ∧
    after.registers 0 = result ∧
    after.registers 1 = before.rip + BitVec.ofNat 64 syscallBytes.length ∧
    after.registers 11 = before.flags ∧
    ∀ register : Register, register ≠ 0 → register ≠ 1 → register ≠ 11 →
      after.registers register = before.registers register

theorem syscallTransition_intro {Host World : Type}
    (dispatch : SyscallHostRelation Host World)
    (host : Host) (world : World) (handler : Address) (maskedFlags : BitVec 64)
    (before after : State) (world' : World) (result : BitVec 64)
    (host_step : dispatch host world before result after.memory world')
    (rip : after.rip = handler) (flags : after.flags = maskedFlags)
    (rax : after.registers 0 = result)
    (rcx : after.registers 1 = before.rip + BitVec.ofNat 64 syscallBytes.length)
    (r11 : after.registers 11 = before.flags)
    (preserved : ∀ register : Register, register ≠ 0 → register ≠ 1 →
      register ≠ 11 → after.registers register = before.registers register) :
    syscallTransition dispatch host world handler maskedFlags before after world' := by
  exact ⟨result, host_step, rip, flags, rax, rcx, r11, preserved⟩

end Lanius.X86.Machine
