import Lanius.Semantics.Typing.Target
import Lanius.Semantics.StmtList

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing

/-- Unlike shape typing, this connects a reference to initialized declared
    storage. It does not require exclusive ownership of its target. -/
inductive CellReferenceValid (program : Program) (types : CellTypes) (state : State) :
    Value → Ty → Prop where
  | reference (target : CellTargetValid program types state cell projections referent) :
      CellReferenceValid program types state (.reference referent cell projections) referent

variable {reference : Value}

/-- Borrowing an initialized local creates a valid reference directly through
    the actual place evaluator; no successful borrow is an input premise. -/
theorem CellTargetValid.borrowLocal (target : CellTargetValid program types state cell [] referent)
    (binding : state.cellId? localId = some cell) :
    RunsExpr program state (.borrow referent (.local localId)) (.reference referent cell []) state ∧
      CellReferenceValid program types state (.reference referent cell []) referent := by
  cases contents : state.cell? cell with
  | none => exact (target.choose_spec.2.2 contents).elim
  | some value =>
    have found : state.local? localId = some value := by simp [State.local?, binding, contents]
    refine ⟨RunsExpr.ofEval (fuel := 2) ?_, .reference target⟩
    rw [evalExpr.eq_def]
    simp only [evalPlace_local_of_local? 0 program state .read localId cell value binding found]

theorem CellReferenceValid.typed (valid : CellReferenceValid program types state reference referent) :
    ValueHasType program reference (.reference referent) := by
  cases valid
  exact .reference _ _ _

theorem CellReferenceValid.retained (valid : CellReferenceValid program types before reference referent)
    (frame : FreshCellFrame before after) : CellReferenceValid program types after reference referent := by
  cases valid with
  | reference target => exact .reference (target.retained frame)

theorem CellReferenceValid.cellEffect (valid : CellReferenceValid program types before reference referent)
    (effect : CellEffect before after cell replacement) : CellReferenceValid program types after reference referent := by
  cases valid with
  | reference target => exact .reference (target.cellEffect effect)

theorem CellReferenceValid.read (valid : CellReferenceValid program types state reference referent)
    (store : state.CellsHaveTypes program types) :
    ∃ value, dereferenceValue state reference = .ok value ∧ ValueHasType program value referent := by
  cases valid with
  | reference target => exact target.read store

/-- Reference-expression effects happen before reading its live target. The
    caller proves target/store validity in that resulting state, not a snapshot. -/
theorem RunsExpr.dereferenceTyped (run : RunsExpr program before expression reference ready)
    (store : ready.CellsHaveTypes program types)
    (valid : CellReferenceValid program types ready reference referent) :
    ∃ value, RunsExpr program before (.dereference expression) value ready ∧ ValueHasType program value referent := by
  obtain ⟨value, read, typed⟩ := valid.read store
  obtain ⟨threshold, evaluated, locals⟩ := run
  refine ⟨value, ⟨threshold + 1, ?_, locals⟩, typed⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [evaluated (fuel - 1) (by omega), read]

#print axioms RunsExpr.dereferenceTyped

end Lanius.Semantics
