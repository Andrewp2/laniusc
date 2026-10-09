import GeneratedDirectCore
import Lanius.Execution

open Lanius

#print axioms extractedProgram


-- Select the parameterless string entry by signature, not declaration order
-- or the extractor's incidental numeric function IDs.
private def literalResult : Option String := do
  let entry ← extractedProgram.functions.find? fun declaration =>
    declaration.parameters.isEmpty && declaration.returnType == .scalar .string
  match Execution.run 64 { program := extractedProgram, entrypoint := entry.id } {} with
  | .returned (.string value) _ => some value
  | _ => none

-- Includes newline, quote, backslash, embedded NUL, and multibyte UTF-8.
example : literalResult = some "A\n\"\\\x00éλ" := by decide

example : (match Execution.run 128
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 37) _ => true
  | _ => false) = true := by decide
