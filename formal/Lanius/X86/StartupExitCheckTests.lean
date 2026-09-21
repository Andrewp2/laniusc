import Lanius.X86.StartupExitCheck

namespace Lanius.X86.StartupExitCheckTests

open Lanius.X86.Machine
open Lanius.X86.StartupCheck
open Lanius.X86.StartupExitCheck

example : returnResult.length = 2 := by decide
example : loadExit.length = 5 := by decide
example : syscallBytes = [15, 5] := by decide

#check ReturnExitEvidence
#check ReturnExitResult
#check reaches_syscall
#check reaches_syscall_transition

end Lanius.X86.StartupExitCheckTests
