import Lanius.Execution
import GeneratedDirectCore

private def returnsSeven : Bool :=
  match Lanius.Execution.run 64
      { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 7) _ => true
  | _ => false

-- The current generated direct-Core fixture returns seven.
example : returnsSeven = true := by decide
