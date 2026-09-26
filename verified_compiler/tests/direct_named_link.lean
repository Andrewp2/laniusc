import GeneratedDirectCore
import Lanius.TypedIR.Checked

-- The generated Core value is already source-shaped through Named.Function.
-- Linking must add kernel-checked typing and entry evidence, not an axiom.
def linkedProgram : Lanius.TypedIR.Program :=
  Lanius.TypedIR.require extractedEntrypoint extractedProgram
    (by decide) (by decide)

example : linkedProgram.core = extractedProgram := rfl

example : extractedTypedProgram.isSome = true := by decide

example (linked : Lanius.TypedIR.Program)
    (accepted : extractedTypedProgram = some linked) :
    linked.core = extractedProgram :=
  Lanius.TypedIR.link?_core extractedEntrypoint extractedProgram accepted

private def mistypedProgram : Lanius.Core.Program :=
  { extractedProgram with
    functions := extractedProgram.functions.map fun function =>
      { function with returnType := .unit } }

example : (Lanius.TypedIR.link? extractedEntrypoint mistypedProgram).isNone = true :=
  by decide
