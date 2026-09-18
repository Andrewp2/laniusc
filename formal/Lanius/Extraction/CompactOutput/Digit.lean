import Lanius.Extraction.CompactOutput.Byte

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

/-- Lowercase ASCII, as required by the compact decoder. -/
def hexDigit (value : Nat) : Nat := if value < 10 then 48 + value else 87 + value

theorem hexDigit_bound (bounded : value < 16) : hexDigit value < 256 := by
  unfold hexDigit
  split <;> omega

theorem digit_body (program : Program) (value : Nat) (bounded : value < 16)
    (found : before.local? 0 = some (.signed .i32 value)) :
    Executes program before digitBody (.returned (some (.signed .i32 (hexDigit value)))) before := by
  by_cases small : value < 10 <;> simp only [hexDigit, small, if_true, if_false]
  all_goals core_exec []

/-- A call to the checked source has no caller-visible writes. Fresh parameter
allocation is retained in the runtime but hidden from its caller's frame. -/
theorem CheckedDigit.call_digit (checked : CheckedDigit program) (value : Nat) (bounded : value < 16) :
    checked.Spec [.signed .i32 value] (.signed .i32 (hexDigit value)) := by
  apply checked.specPure rfl
  intro callee locals
  exact digit_body program.core value bounded (locals 0 (by simp))

end Lanius.Extraction.CompactOutput
