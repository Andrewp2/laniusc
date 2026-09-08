import Lanius.Semantics.CellRenaming.Value
import Lanius.Typing

namespace Lanius.Semantics.CellRenaming
open Lanius.Core

/- Source literals cannot contain runtime cell identities, even inside
aggregates. Renaming a caller's allocations therefore leaves them unchanged. -/
mutual
  theorem literal_fixed (rename : CellId → CellId) (entry : Value)
      (literal : Typing.Value.isLiteral entry = true) :
      value rename entry = entry := by
    cases entry <;>
      simp only [Typing.Value.isLiteral] at literal <;>
      simp_all only [Bool.false_eq_true, value, literals_fixed]
  theorem literals_fixed (rename : CellId → CellId) (entries : List Value)
      (literal : Typing.Values.areLiteral entries = true) :
      values rename entries = entries := by
    cases entries with
    | nil => rfl
    | cons first rest =>
        obtain ⟨head, tail⟩ := Bool.and_eq_true_iff.mp literal
        simp only [values, literal_fixed rename first head,
          literals_fixed rename rest tail]
end

end Lanius.Semantics.CellRenaming
