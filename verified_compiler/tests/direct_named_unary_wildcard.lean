import Lanius.Execution
import GeneratedDirectCore

open Lanius Lanius.TypedIR.Surface

-- Unary operators must remain operators: erasing unary plus or folding a
-- negative literal would change source-to-Core agreement even when execution
-- happens to return the same value.
example (value : Expr I32) :
    (Expr.positive value).core = .unary .positive value.core := rfl
example (value : Expr I32) :
    (Expr.negate value).core = .unary .negate value.core := rfl
example (value : Expr Bool) :
    (Expr.logicalNot value).core = .unary .logicalNot value.core := rfl


-- Execute both enum branches and the Boolean early return.
example : (match Execution.run 256
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 7) _ => true
  | _ => false) = true := by decide
