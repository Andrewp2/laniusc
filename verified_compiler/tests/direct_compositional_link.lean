import GeneratedCompositional

example : (extractedProgram.function? extractedEntrypoint).isSome = true := by decide

-- A mismatched result type cannot acquire the same typing evidence.
example :
    (Lanius.Typing.Check.checkFunctionWellTyped extractedProgram
      { extractedProgram.functions.head (by decide) with
        returnType := .unit }).isSome = false := by decide
