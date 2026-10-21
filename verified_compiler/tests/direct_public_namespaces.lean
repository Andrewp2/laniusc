import Lanius.Execution
import GeneratedDirectCore

-- Identical type/constructor spellings in different source modules stay distinct.
def localChoice : Extracted.«app::main».Types.Type := .instance
def importedChoice : Extracted.«app::namespace».Types.Type := .example
def sameNamedType : Extracted.«app::namespace».Types.«theorem» := .mk 7
def reservedConstructor : Extracted.«app::namespace».Types.GeneratedNames := .«constructor:rec»

example : localChoice = Extracted.«app::main».Types.Type.instance := rfl
example : importedChoice = Extracted.«app::namespace».Types.Type.example := rfl
example : extractedProgram.function? Extracted.«app::namespace».Functions.«theorem».core.id =
    some Extracted.«app::namespace».Functions.«theorem».core := rfl

-- Calls target the declarations themselves, including a function called `ref`.
example : Extracted.«app::main».Functions.ref.core.body = some
    (.returnValue (some (.call Extracted.«app::main».Functions.even.core.id
      (Extracted.«app::main».Functions.ref.core.parameters.map (fun p => .local p.1))))) := rfl
example : Extracted.«app::main».Functions.even.core.id ≠
    Extracted.«app::main».Functions.odd.core.id := by decide

example : (match Lanius.Execution.run 512
    { program := extractedProgram, entrypoint := Extracted.«app::main».Functions.main.core.id } {} with
  | .returned (.signed .i32 16) _ => true
  | _ => false) = true := by decide
