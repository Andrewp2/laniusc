import Lanius.Typing
import GeneratedDirectCore




example : Extracted.«app::runtime».Functions.alloc.core.external =
    some (.host .alloc) := rfl

-- The runtime signature is checked, not assumed because a function is external.
example : ¬ Lanius.Typing.FunctionWellTyped extractedProgram
    { Extracted.«app::runtime».Functions.alloc.core with parameters := [] } := by
  intro typed
  cases typed.1

example : ¬ Lanius.Typing.FunctionWellTyped extractedProgram
    { Extracted.«app::runtime».Functions.alloc.core with returnType := .scalar .bool } := by
  intro typed
  cases typed.2

#print axioms extractedProgram
