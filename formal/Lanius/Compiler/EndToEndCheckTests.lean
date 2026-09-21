import Lanius.Compiler.EndToEndCheck

namespace Lanius.Compiler.EndToEndCheckTests

open Lanius
open Lanius.Compiler.EndToEndCheck
open Lanius.Compiler.CertificateLoweringCheck
open Lanius.X86.ProgramCheck

-- The outer checker reports the source/certificate boundary before attempting
-- to authenticate an image, and does not silently accept an unrelated image.
example :
    Lanius.Compiler.EndToEndCheck.check "" [] noExternalBehavior = .error (.certificate .decode) := by
  rfl

-- The conservative default resolver remains available for certificates with
-- no external behavior.
example :
    Lanius.Compiler.EndToEndCheck.check "" [] = .error (.certificate .decode) := by
  rfl

-- Keep the public composition result and its preservation consequence
-- type-checked as part of the focused checker tests.
#check check_sound
#check Soundness.entrypointPreserves
#check Soundness.programLoweringProgram
#check Soundness.programTarget
#check Soundness.enumerationsEmpty

end Lanius.Compiler.EndToEndCheckTests
