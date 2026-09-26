import Lanius.Execution
import GeneratedDirectCore

private def returnsZero : Bool :=
  match Lanius.Execution.run 64
      { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 0) _ => true
  | _ => false

-- Main constructs a payload-bearing enum value before returning zero.
example : returnsZero = true := by decide
