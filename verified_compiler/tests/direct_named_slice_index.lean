import GeneratedDirectCore
import Lanius.Execution

open Lanius.TypedIR.Surface


example [Code α] (reference : Constant α) :
    (Expr.constant reference).core = .constant reference.id := rfl

example [Code α] (base : Expr (Slice α)) (index : Expr I32) :
    (Expr.indexSlice base index).core = .index base.core index.core := rfl

example [Code α] (base : Place (Slice α)) (index : Expr I32) :
    (Place.indexSlice base index).core = .index base.core index.core := rfl

-- The assignment index calls a function that mutates another slice element.
-- Evaluating that index twice would return 38 rather than 37.
example : (match Lanius.Execution.run 256
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 37) _ => true
  | _ => false) = true := by decide
