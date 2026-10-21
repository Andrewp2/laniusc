import GeneratedDirectCore
import Lanius.Execution

open Lanius Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface


-- In particular, signed remainder follows the dividend, and signed right
-- shift preserves the sign. These differ from plausible host arithmetic.
example : (match Execution.run 256
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 37) _ => true
  | _ => false) = true := by decide

private def divideByZero : Function [] I32 :=
  function (id := 0, name := "divideByZero", arguments := [], bindings := []) do
    return 7 / 0

-- The notation must retain the language operation and its trap, not compute
-- Lean's total division while elaborating the embedding.
example : (match Execution.run 32
    { program := { functions := [divideByZero.pack] }, entrypoint := 0 } {} with
  | .trapped .divisionByZero _ => true
  | _ => false) = true := by decide
