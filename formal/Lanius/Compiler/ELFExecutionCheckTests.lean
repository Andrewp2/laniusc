import Lanius.Compiler.ELFExecutionCheck

namespace Lanius.Compiler.ELFExecutionCheckTests

open Lanius Lanius.Compiler Lanius.Compiler.ELFExecutionCheck
open Lanius.X86 Lanius.X86.ProgramCheck Lanius.X86.StartupCheck
open Lanius.X86.EntrypointRefinement Lanius.X86.StartupExitCheck

/- The displacement is derived from the authenticated entry address, rather
   than supplied as an independent target premise. -/
example : startupJumpDisplacement? functionEntry = some (BitVec.ofNat 32 0) := by
  decide

example : imageEq
    ({ address := BitVec.ofNat 64 10, bytes := [1, 2] } : FunctionImage)
    { address := BitVec.ofNat 64 10, bytes := [1, 2] } = true := by
  decide

example : imageEq
    ({ address := BitVec.ofNat 64 10, bytes := [1, 2] } : FunctionImage)
    { address := BitVec.ofNat 64 11, bytes := [1, 2] } = false := by
  decide

#check startup_to_exit
#check Lanius.X86.EntrypointExitComposition.entrypoint_to_exit

end Lanius.Compiler.ELFExecutionCheckTests
