import Lanius.Execution
import Lanius.Semantics.Constant
import GeneratedDirectCore

open Lanius


example : (match Execution.run 256
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 7) _ => true
  | _ => false) = true := by decide

#print axioms Semantics.ConstantEvaluates.evaluates
#print axioms extractedProgram
