import Lanius.Compiler.ELFExecutionBridge
import Lanius.Compiler.CorrectnessBoundary

namespace Lanius.Compiler.VerifiedExecution

open Lanius
open Lanius.Compiler
open Lanius.Compiler.CertificateLoweringCheck
open Lanius.Compiler.ELFExecutionCheck
open Lanius.Compiler.ELFExecutionBridge
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ProgramCheck
open Lanius.X86.EntrypointRefinement
open Lanius.X86.ProcessLayoutCheck
open Lanius.X86.StartupExitCheck

abbrev check (encoded : String) (expectedSources : List Extraction.SourceFile) :=
  ELFExecutionCheck.check encoded expectedSources noExternalBehavior

/-- Accepted checker evidence and one actual runtime layout compose the existing
    source/Core soundness result with the authenticated startup-to-exit path. -/
theorem check_sound
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {checked : ELFExecutionCheck.Checked encoded expectedSources}
    (before : Machine.State) (runtime : RuntimeLayout checked before) :
    EndToEndCheck.Soundness encoded expectedSources noExternalBehavior checked.endToEnd ∧
      ∃ coreAfter body value returned count bits,
      Machine.Steps (8 + count + 2) before (afterExitLoad returned) ∧
        ReturnedState checked.endToEnd.program
          ({} : Semantics.State)
          (reachedState before checked.displacement) startupReturnAddress
          coreAfter body value returned count ∧
        ReturnExitResult returned (afterExitLoad returned) bits := by
  exact CorrectnessBoundary.sound before runtime

end Lanius.Compiler.VerifiedExecution
