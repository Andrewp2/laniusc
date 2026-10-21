import Lanius.Execution
import GeneratedDirectCore

-- The emitted program must execute the source fixture's result.
example : (match Lanius.Execution.run 1024
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 1) _ => true
  | _ => false) = true := by decide
