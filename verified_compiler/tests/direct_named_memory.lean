import GeneratedDirectCore
import Lanius.Execution


-- The emitted nominal-slice constructor, pointer offset, indexed stores,
-- and loads execute together with the existing allocator semantics.
example : (match Lanius.Execution.run 256
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 30) _ => true
  | _ => false) = true := by decide
