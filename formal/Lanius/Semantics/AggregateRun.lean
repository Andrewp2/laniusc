import Lanius.Semantics.CallRun

namespace Lanius.Semantics

open Lanius.Core

/-- Fields run left to right and may have effects. No typing tree or
    purity assumption is needed to construct a record. -/
theorem RunsExpr.structValue
    (fields : RunsExprs program before expressions values after) :
    RunsExpr program before (.structValue typeId expressions) (.structure typeId values) after := by
  obtain ⟨threshold, fields, locals⟩ := fields
  refine ⟨threshold + 1, ?_, locals⟩
  intro fuel enough
  have run := fields (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [run]

/-- Enum payloads use the same left-to-right, effect-preserving argument
    composition as records and calls. -/
theorem RunsExpr.enumValue
    (payload : RunsExprs program before expressions values after) :
    RunsExpr program before (.enumValue typeId ordinal expressions) (.enumeration typeId ordinal values) after := by
  obtain ⟨threshold, payload, locals⟩ := payload
  refine ⟨threshold + 1, ?_, locals⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [payload (fuel - 1) (by omega)]

/-- Project a field after the base expression's proved effects. -/
theorem RunsExpr.field
    (base : RunsExpr program before expression (.structure typeId fields) after)
    (found : fields[fieldId]? = some value) :
    RunsExpr program before (.field expression fieldId) value after := by
  obtain ⟨threshold, base, locals⟩ := base
  refine ⟨threshold + 1, ?_, locals⟩
  intro fuel enough
  have run := base (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [run, found]

end Lanius.Semantics
