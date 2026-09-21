import Lanius.Compiler.FrontendArtifactCheck

namespace Lanius.Compiler.FrontendArtifactCheckTests

open Lanius
open Lanius.Compiler.FrontendArtifactCheck

/- Keep a focused kernel-reduction regression target for the concrete frontend
   artifact.  The first example intentionally repeats the small `rfl` gate;
   the second checks that callers receive the actual typing proposition. -/
example : frontendProgramCheck.isSome = true := frontendProgramCheck_accepted

example : Typing.ProgramWellTyped FrontendArtifact.frontendProgram :=
  Lanius.Compiler.FrontendArtifactCheck.frontendProgram_wellTyped

end Lanius.Compiler.FrontendArtifactCheckTests
