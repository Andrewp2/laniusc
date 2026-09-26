import Lanius.TypedIR.Checked
import GeneratedDirectCore

def linkedTypedProgram : Lanius.TypedIR.Program :=
  Lanius.TypedIR.require extractedEntrypoint extractedProgram
    (by decide) (by decide)

example : linkedTypedProgram.core = extractedProgram := rfl

private def wrongResultProgram : Lanius.Core.Program :=
  { extractedProgram with
    functions := extractedProgram.functions.map fun function =>
      if function.id == extractedEntrypoint then
        { function with returnType := .scalar .bool }
      else function }

example : Lanius.Typing.Check.checkProgramWellTyped wrongResultProgram = none := by
  decide
