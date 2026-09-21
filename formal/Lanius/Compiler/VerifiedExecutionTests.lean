import Lanius.Compiler.VerifiedExecution

namespace Lanius.Compiler.VerifiedExecutionTests

open Lanius.Compiler
open Lanius.Compiler.CertificateLoweringCheck
open Lanius.Compiler.VerifiedExecution

example :
    VerifiedExecution.check "" [] =
      Except.error (.endToEnd (.certificate .decode)) := by
  rfl

#check VerifiedExecution.check
#check check_sound

end Lanius.Compiler.VerifiedExecutionTests
