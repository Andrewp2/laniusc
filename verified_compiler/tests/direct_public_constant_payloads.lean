import Lanius.Execution
import GeneratedDirectCore

open Lanius.TypedIR.Surface

-- The source checker now authenticates these declared types and exact values,
-- in addition to the ordinary Core typing and public-name checks below.
example : Constant String := Extracted.«app::main».Constants.message
example : Constant Usize := Extracted.«app::main».Constants.count
example : Constant RawPtr := Extracted.«app::main».Constants.nowhere

example : (extractedProgram.constant? Extracted.«app::main».Constants.message.id).map
    (·.value) = some (.string "Aé") := rfl
example : (extractedProgram.constant? Extracted.«app::main».Constants.count.id).map
    (·.value) = some (.unsigned .usize 19) := rfl
example : (extractedProgram.constant? Extracted.«app::main».Constants.nowhere.id).map
    (·.value) = some (.pointer 0) := rfl
example : (match Lanius.Execution.run 128
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 0) _ => true
  | _ => false) = true := by decide
