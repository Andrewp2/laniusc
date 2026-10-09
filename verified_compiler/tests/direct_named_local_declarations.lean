import Lanius.Execution
import GeneratedDirectCore


#print axioms extractedProgram

-- Both branches initialize the local; a void helper returns to its caller.
example : (match Lanius.Execution.run 128
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 16) _ => true
  | _ => false) = true := by decide
