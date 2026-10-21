import Lanius.Execution
import GeneratedDirectCore

open Extracted.«app::main».Types Extracted.«app::main».Functions
open Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface

-- Importers can name the actual source type, constructors, and function.
def selected : Choice := .Some 7
example : selected = Choice.Some 7 := rfl
example : extractedProgram.function? main.core.id = some main.core := rfl

-- Native proof support is retained even though extraction does not generate
-- unused SizeOf machinery for every source type.
example (a b : I32) : Choice.Some a = Choice.Some b ↔ a = b := by simp
example (value : I32) : Choice.Some value ≠ Choice.None := by simp

-- The generation option must not leak to subsequent user declarations.
inductive UserType where | item (value : Nat)
example : sizeOf (UserType.item 0) > 0 := by decide

-- A proof that needs a structural size can request it for just that type.
deriving instance SizeOf for Choice
example : sizeOf (Choice.Some 7) > 0 := by decide

-- The imported constructor metadata also supports ordinary source-shaped
-- proof definitions, without access to any private generated helper names.
def reconstructed : Function [] Choice :=
  function (id := 2, name := "reconstructed", arguments := [], bindings := []) do
    return (.Some 7 : Extracted.«app::main».Types.Choice)
example : reconstructed.core.body = some
    (.returnValue (some (.enumValue 0 1 [.value (.signed .i32 7)]))) := rfl

example : (match Lanius.Execution.run 64
    { program := extractedProgram, entrypoint := main.core.id } {} with
  | .returned (.signed .i32 7) _ => true
  | _ => false) = true := by decide
