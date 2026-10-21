import Lanius.Typing.Check
import GeneratedDirectCore


private def wrongResultProgram : Lanius.Core.Program :=
  { extractedProgram with
    functions := extractedProgram.functions.map fun function =>
      if function.id == extractedEntrypoint then
        { function with returnType := .scalar .bool }
      else function }

-- The independent checker remains a test oracle, not an emission dependency.
example : Lanius.Typing.Check.checkProgramWellTyped wrongResultProgram = none := by decide
