import Lanius.Relational.CoreSuccess

namespace Lanius.Extraction.Source

open Lanius.Core Lanius.Semantics
open Lanius.Relational.CoreSuccess

/-- A conservative normal-completion analysis. This does not claim that the
statement terminates: if it completes, it cannot fall through to its successor.
Loops are deliberately not inferred to stop from their bodies. -/
def stops : Stmt → Bool
  | .returnValue _ | .breakLoop | .continueLoop => true
  | .sequence first second => stops first || stops second
  | .letLocal _ _ _ body | .letUninitialized _ _ body => stops body
  | .ifThenElse _ yes no => stops yes && stops no
  | _ => false

private theorem next_not_stopping (run : StmtExecutes program before statement completion after)
    (next : completion = .next) : stops statement = false := by
  induction run <;> simp_all [stops]

structure CheckedStop (statement : Stmt) : Prop where
  supported : Supported statement = true
  stopping : stops statement = true

def checkStop? (statement : Stmt) : Option (PLift (CheckedStop statement)) :=
  if checked : Supported statement = true ∧ stops statement = true then
    some ⟨⟨checked.1, checked.2⟩⟩ else none

theorem CheckedStop.not_next (checked : CheckedStop statement)
    (run : Executes program before statement completion after) : completion ≠ .next := by
  intro next
  have impossible := next_not_stopping (ofExecutes checked.supported run) next
  rw [checked.stopping] at impossible
  contradiction

end Lanius.Extraction.Source
