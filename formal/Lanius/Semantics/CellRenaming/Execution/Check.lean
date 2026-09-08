import Lanius.Semantics.CellRenaming.Source
import Lanius.Semantics.CellRenaming.Execution.Program

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

def sourceBody : Option Stmt → Bool
  | none => false
  | some body => Source.statement body

/-- A single source check establishes invariance for every cell renaming.
External declarations are rejected, not assumed to satisfy this contract. -/
def sourceProgram (program : Program) : Bool :=
  program.constants.all (fun declaration => Typing.Value.isLiteral declaration.value) &&
    program.functions.all (fun declaration => sourceBody declaration.body)

theorem sourceProgram_invariant (program : Program) (checked : sourceProgram program = true)
    (rename : CellId → CellId) : ProgramInvariant rename program := by
  obtain ⟨constants, functions⟩ := Bool.and_eq_true_iff.mp checked
  constructor
  · intro id declaration found
    exact literal_fixed rename declaration.value
      (List.all_eq_true.mp constants declaration (List.mem_of_find?_eq_some found))
  · intro id declaration found
    have checkedBody := List.all_eq_true.mp functions declaration (List.mem_of_find?_eq_some found)
    cases present : declaration.body with
    | none => simp [present, sourceBody] at checkedBody
    | some body =>
        exact ⟨body, rfl, Source.statement_fixed rename body (by
          simpa only [present, sourceBody] using checkedBody)⟩

def checkSourceProgram? (program : Program) :
    Option (PLift (∀ rename, ProgramInvariant rename program)) :=
  if checked : sourceProgram program = true then
    some ⟨sourceProgram_invariant program checked⟩
  else none

end Lanius.Semantics.CellRenaming.Execution
