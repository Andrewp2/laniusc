import Lanius.X86.Source.Lower

namespace Lanius.X86.Lower.Parameter

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Source Lanius.X86.Source.Lower

theorem case_register (position : Fin 6) :
    Table.lookup argumentEntries position.val = (argumentRegister position).val := by
  decide +revert

theorem argument_call (checked : CheckedArgumentRegister program) (position : Fin 6)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 position.val] before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (argumentRegister position).val) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨after, run, _, effect, heap⟩ := (checked.spec position.val).call wellFormed argumentsResult
  rw [case_register position] at run
  exact ⟨after, run, effect, heap⟩

end Lanius.X86.Lower.Parameter
