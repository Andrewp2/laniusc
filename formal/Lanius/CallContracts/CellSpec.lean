import Lanius.CallContracts
import Lanius.Separation.HeapFrame

namespace Lanius.CallContracts

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- A total function contract for Core cell operations. Calls terminate with
`result`, may change only `writes` among existing cells, and preserve caller
locals, the external world, raw heap, and registered views. Fresh local cells
are permitted. `requires` and `ensures` describe additional storage facts.

Argument expressions may have effects: the contract starts at their final
state `before`, not at `caller`. This is not a contract for host I/O or raw-heap
mutation; those operations need a different effect specification. -/
structure CellSpec (program : Program) (function : FunctionId)
    (values : List Value) (result : Value)
    (requires : State → Prop := fun _ => True)
    (ensures : State → State → Prop := fun _ _ => True)
    (writes : CellSet := CellSet.empty) : Prop where
  call : ∀ {caller arguments before}, StateWellFormed before →
    ArgumentsEvaluateTo program caller arguments values before →
    (pre : requires before := by trivial) →
    ∃ after, Evaluates program caller (.call function arguments) result after ∧
      ensures before after ∧ CellEffect writes before after ∧ HeapFrame before after

/-- Retain a proved property of the result alongside the state postcondition.
This reuses the call evidence; it does not execute or check the callee again. -/
theorem CellSpec.withFact (spec : CellSpec program function values result requires ensures writes)
    (fact : extra) : CellSpec program function values result requires
      (fun before after => ensures before after ∧ extra) writes := by
  constructor
  intro caller arguments before wellFormed argumentsResult pre
  obtain ⟨after, execution, post, effect, heap⟩ := spec.call wellFormed argumentsResult pre
  exact ⟨after, execution, ⟨post, fact⟩, effect, heap⟩

theorem CellSpec.map (spec : CellSpec program function values result requires ensures writes)
    (weaken : ∀ before after, ensures before after → post before after) :
    CellSpec program function values result requires post writes := by
  constructor
  intro caller arguments before wellFormed evaluated pre
  obtain ⟨after, run, result, effect, heap⟩ := spec.call wellFormed evaluated pre
  exact ⟨after, run, weaken before after result, effect, heap⟩

end Lanius.CallContracts
