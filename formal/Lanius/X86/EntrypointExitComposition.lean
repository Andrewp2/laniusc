import Lanius.X86.EntrypointRefinement
import Lanius.X86.StartupExitCheck

namespace Lanius.X86.EntrypointExitComposition

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ProgramCheck
open Lanius.X86.EntrypointRefinement
open Lanius.X86.StartupCheck
open Lanius.X86.ProcessLayoutCheck
open Lanius.X86.StartupExitCheck

/- The entrypoint result is consumed through its uniform state contract.  In
   particular, this theorem does not split on `FunctionCheck.Checked` or on
   the authenticated entrypoint constructor. -/
theorem entrypoint_to_exit
    {executable : Execution.Executable} {image : Image}
    {checked : Authenticated executable image}
    {elf : List UInt8} {coreBefore : Semantics.State}
    {machineBefore : Machine.State}
    (loaded : checked.Loaded machineBefore)
    (environment : PreservationEnvironment checked coreBefore machineBefore)
    (frame : EntrypointFrame checked machineBefore)
    (ripAtEntry : machineBefore.rip = checked.entrypoint.image.address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers rspRegister) = startupReturnAddress)
    (startup : StartupEvidence elf)
    (mapped : Machine.CodeAt machineBefore.memory base elf)
    (layoutSafe : StackCodeDisjoint machineBefore base elf.length
      checked.entrypoint.function) :
    ∃ coreAfter body value returned count bits,
      ReturnedState checked coreBefore machineBefore startupReturnAddress
        coreAfter body value returned count ∧
      ReturnExitResult returned (afterExitLoad returned) bits := by
  have entry := refines checked coreBefore machineBefore loaded environment frame
    ripAtEntry startupReturnAddress poppedReturn
  rcases entry with ⟨coreAfter, body, value, returned, count, state⟩
  have mappedAfter : Machine.CodeAt returned.memory base elf :=
    state.protectedCode mapped layoutSafe
  let bits : BitVec 32 := (returned.registers 0).setWidth 32
  have evidence : ReturnExitEvidence elf returned bits := {
    startup := startup
    mapped := mappedAfter
    ripAtReturn := state.rip
    raxAtReturn := rfl }
  exact ⟨coreAfter, body, value, returned, count, bits, state, reaches_syscall evidence⟩

end Lanius.X86.EntrypointExitComposition
