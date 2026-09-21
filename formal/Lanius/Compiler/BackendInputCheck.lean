import Lanius.Compiler.EntrypointCheck
import Lanius.Typing.Check
import Lanius.X86.Transport

namespace Lanius.Compiler.BackendInputCheck

open Lanius

inductive Failure where
  | illTyped
  | missingEntrypoint
  | entrypointParameters
  | entrypointReturn
  | unsupportedTransport
deriving DecidableEq, Repr

structure Checked (executable : Execution.Executable) where
  programTyped : Typing.Check.ProofOf (Typing.ProgramWellTyped executable.program)
  programAccepted : Typing.Check.checkProgramWellTyped executable.program = some programTyped
  entrypoint : Core.Function
  entrypointFound : executable.program.function? executable.entrypoint = some entrypoint
  noParameters : entrypoint.parameters = []
  returnAccepted : EntrypointCheck.returnSupported entrypoint.returnType = true
  words : List Int
  encoded : X86.Transport.encodeProgram executable.entrypoint executable.program = some words

def check (executable : Execution.Executable) : Except Failure (Checked executable) :=
  match programAccepted : Typing.Check.checkProgramWellTyped executable.program with
  | none => .error .illTyped
  | some programTyped =>
      match entrypointFound : executable.program.function? executable.entrypoint with
      | none => .error .missingEntrypoint
      | some entrypoint =>
          if noParameters : entrypoint.parameters = [] then
            if returnAccepted : EntrypointCheck.returnSupported entrypoint.returnType = true then
              match encoded : X86.Transport.encodeProgram executable.entrypoint executable.program with
              | none => .error .unsupportedTransport
              | some words => .ok {
                  programTyped
                  programAccepted
                  entrypoint
                  entrypointFound
                  noParameters
                  returnAccepted
                  words
                  encoded
                }
            else .error .entrypointReturn
          else .error .entrypointParameters

theorem executable_wellFormed {executable : Execution.Executable}
    (checked : Checked executable) : Execution.ExecutableWellFormed executable := by
  have member : checked.entrypoint ∈ executable.program.functions := by
    exact List.mem_of_find?_eq_some checked.entrypointFound
  exact ⟨checked.entrypoint, checked.entrypointFound, checked.noParameters,
    EntrypointCheck.returnSupported_sound checked.returnAccepted,
    checked.programTyped.down.2 checked.entrypoint member⟩

theorem check_sound {executable : Execution.Executable} {checked : Checked executable}
    (_accepted : check executable = .ok checked) :
    Execution.ExecutableWellFormed executable ∧
      X86.Transport.EncodesProgram executable.entrypoint executable.program checked.words :=
  ⟨executable_wellFormed checked, checked.encoded⟩

end Lanius.Compiler.BackendInputCheck
