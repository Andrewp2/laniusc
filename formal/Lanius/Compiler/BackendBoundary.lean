import Lanius.Compiler.BackendInputCheck
import Lanius.X86.TransportDecode

namespace Lanius.Compiler.BackendBoundary

open Lanius

inductive Failure where
  | decode
  | backend (failure : BackendInputCheck.Failure)
deriving DecidableEq, Repr

/-- Evidence returned after decoding and checking untrusted transport words. -/
structure Checked (words : List Int) where
  executable : Execution.Executable
  programTyped : Typing.Check.ProofOf (Typing.ProgramWellTyped executable.program)
  entrypointWellFormed : Execution.ExecutableWellFormed executable
  reencoded : X86.Transport.EncodesProgram executable.entrypoint executable.program words
  decoded : X86.Transport.decodeExecutable words = some executable

/-- Decode canonical words, then run the backend input checker on the result. -/
def check (words : List Int) : Except Failure (Checked words) :=
  match decoded : X86.Transport.decodeExecutable words with
  | none => .error .decode
  | some executable =>
      match _backend : BackendInputCheck.check executable with
      | .error failure => .error (.backend failure)
      | .ok checked =>
          .ok {
            executable := executable
            programTyped := checked.programTyped
            entrypointWellFormed := BackendInputCheck.executable_wellFormed checked
            reencoded := X86.Transport.decodeExecutable_sound decoded
            decoded := decoded }

theorem check_sound {words : List Int} {checked : Checked words}
    (_accepted : check words = .ok checked) :
    Typing.ProgramWellTyped checked.executable.program ∧
      Execution.ExecutableWellFormed checked.executable ∧
      X86.Transport.EncodesProgram checked.executable.entrypoint
        checked.executable.program words :=
  ⟨checked.programTyped.down, checked.entrypointWellFormed, checked.reencoded⟩

end Lanius.Compiler.BackendBoundary
