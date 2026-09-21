import Lanius.X86.StartupCheck

namespace Lanius.X86.StartupCheckTests

open Lanius.X86.StartupCheck
open Lanius.X86.Machine

example : startupBytes.length = 32 := by decide
example : programJumpBytes = [233, 0, 0, 0, 0] := by decide
example : check [] = none := by decide
example : checkJump [233, 0, 0, 0, 0] (BitVec.ofNat 32 0) = none := by decide
example : jumpTarget (BitVec.ofNat 32 0) = functionEntry := by rfl
example : (jumpBytes (BitVec.ofNat 32 7)).length = 5 := by decide

end Lanius.X86.StartupCheckTests
