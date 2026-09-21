import Lanius.Compiler.ELFExecutionBridge

namespace Lanius.Compiler.CorrectnessBoundary

open Lanius
open Lanius.Compiler
open Lanius.Compiler.EndToEndCheck
open Lanius.Compiler.ELFExecutionCheck
open Lanius.X86
open Lanius.X86.EntrypointRefinement
open Lanius.X86.ProcessLayoutCheck
open Lanius.X86.ProgramCheck
open Lanius.X86.StartupExitCheck

/-!
The public correctness boundary is a projection of the checker-owned
certificates.  `EndToEndCheck.Soundness` carries exact source/Core identity,
typing, and authenticated ELF span facts; the bridge supplies the canonical
empty-Core startup-to-exit refinement.  Neither theorem rechecks a phase nor
takes a successful execution as a premise.
-/
theorem sound
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : ELFExecutionCheck.Checked encoded expectedSources resolver}
    (before : Machine.State) (runtime : RuntimeLayout checked before) :
    EndToEndCheck.Soundness encoded expectedSources resolver checked.endToEnd ∧
      ∃ coreAfter body value returned count bits,
        Machine.Steps (8 + count + 2) before (afterExitLoad returned) ∧
        ReturnedState checked.endToEnd.program ({ } : Semantics.State)
          (reachedState before checked.displacement) startupReturnAddress
          coreAfter body value returned count ∧
        ReturnExitResult returned (afterExitLoad returned) bits := by
  exact ⟨EndToEndCheck.check_sound checked.endToEnd,
    ELFExecutionBridge.canonical_startup_to_exit checked before runtime⟩

end Lanius.Compiler.CorrectnessBoundary
