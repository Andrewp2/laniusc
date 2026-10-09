import Lanius.Execution
import GeneratedDirectCore

open Lanius Lanius.TypedIR.Surface

-- A compound assignment erases to one Core operation. In particular, an
-- indexed destination must not be evaluated twice by a read/write expansion.
example (target : Place I32) (value : Expr I32) :
    (Expr.assign .add target value).core = .assign .add target.core value.core := rfl
example (condition : Expr Bool) (body : Lanius.Core.Stmt) :
    (Lanius.TypedIR.Surface.Stmt.whileLoop condition body) = Lanius.Core.Stmt.whileLoop condition.core body := rfl


-- Both the zero-iteration case and a loop mutating distinct record fields
-- are exercised through calls, not merely by checking syntax or typing.
example : (match Execution.run 512
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 15) _ => true
  | _ => false) = true := by decide
