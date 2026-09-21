import Lanius.Compiler.CorrectnessBoundary

namespace Lanius.Compiler.CorrectnessBoundaryTests

open Lanius Lanius.Compiler Lanius.Compiler.CorrectnessBoundary
open Lanius.Compiler.ELFExecutionCheck Lanius.X86 Lanius.X86.EntrypointRefinement
open Lanius.X86.Machine Lanius.X86.ProcessLayoutCheck Lanius.X86.StartupExitCheck

example {encoded : String} {expectedSources : List Extraction.SourceFile}
    {checked : ELFExecutionCheck.Checked encoded expectedSources
      CertificateLoweringCheck.noExternalBehavior}
    (before : Machine.State) (runtime : RuntimeLayout checked before) :
    ∃ coreAfter body value returned count bits,
      Machine.Steps (8 + count + 2) before (afterExitLoad returned) ∧
      ReturnedState checked.endToEnd.program ({ } : Semantics.State)
        (reachedState before checked.displacement) startupReturnAddress
        coreAfter body value returned count ∧
      ReturnExitResult returned (afterExitLoad returned) bits := by
  exact (CorrectnessBoundary.sound (checked := checked) before runtime).2

end Lanius.Compiler.CorrectnessBoundaryTests
