import GeneratedDirectCore
import Lanius.Execution

#print axioms extractedProgram


-- Signed -1 widens modulo 2^64, and signed/unsigned pointer offsets retain
-- the same address arithmetic. This executes the actual generated program.
example : (match Lanius.Execution.run 256
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 37) _ => true
  | _ => false) = true := by decide
