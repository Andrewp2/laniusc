import Lanius.Execution
import GeneratedDirectCore


example : (match Lanius.Execution.run 64
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 7) _ => true
  | _ => false) = true := by decide
