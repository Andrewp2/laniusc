import Lanius.Execution
import GeneratedDirectCore

open Lanius.TypedIR.Surface

-- The public declaration owns its value as well as its source name and label.
example : Constant I32 := Extracted.«app::main».Constants.«theorem»
example : Constant Bool := Extracted.«app::main».Constants.enabled
example : Extracted.«app::main».Constants.«theorem».core.value = .signed .i32 3 := rfl
example : Extracted.«app::main».Constants.enabled.core.value = .boolean true := rfl
example : (extractedProgram.constant? Extracted.«app::main».Constants.unreferenced.id).map
    (·.value) = some (.signed .i32 99) := rfl

example : Extracted.«app::main».Constants.«theorem».id ≠
    Extracted.«app::constants».Constants.«theorem».id := by decide

example : (extractedProgram.constant? Extracted.«app::main».Constants.«theorem».id).map
    (·.value) = some (.signed .i32 3) := rfl
example : (extractedProgram.constant? Extracted.«app::constants».Constants.«theorem».id).map
    (·.value) = some (.signed .i32 17) := rfl

example : (match Lanius.Execution.run 128
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 37) _ => true
  | _ => false) = true := by decide
