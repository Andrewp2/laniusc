import Lanius.Semantics.CellRenaming.Execution.Step
import Lanius.Semantics.CellRenaming.Execution.Bounds
import Std.Tactic

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

private theorem heap (rename : CellId → CellId) (before : State) :
    (state rename before).heap = before.heap := rfl

private theorem withHeap (rename : CellId → CellId) (before : State) (heap : Memory.Heap) :
    { state rename before with heap } = state rename { before with heap } := rfl

theorem reallocExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (pointer oldSize newSize alignment : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.realloc pointer oldSize newSize alignment) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.realloc (CellRenaming.expression rename.forward pointer) (CellRenaming.expression rename.forward oldSize) (CellRenaming.expression rename.forward newSize) (CellRenaming.expression rename.forward alignment)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before [pointer, oldSize, newSize, alignment] with
  | done entries next =>
      obtain ⟨transport, nextReady⟩ := step.expressions ready run
      simp only [CellRenaming.expressions] at transport
      rw [transport]
      simp only [run] at evaluated
      repeat' first
        | contradiction
        | simp_all only [values, value, syncToHeap, syncFromHeap, Except.map,
            heap, withHeap, Outcome.done.injEq, List.cons.injEq,
            Value.pointer.injEq, Value.unsigned.injEq]
        | split at evaluated
      all_goals grind only [→ syncToHeap_nextCell, → syncFromHeap_nextCell, state, value]
  | _ => simp [run] at evaluated

theorem deallocExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (pointer size alignment : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.dealloc pointer size alignment) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.dealloc (CellRenaming.expression rename.forward pointer) (CellRenaming.expression rename.forward size) (CellRenaming.expression rename.forward alignment)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before [pointer, size, alignment] with
  | done entries next =>
      obtain ⟨transport, nextReady⟩ := step.expressions ready run
      simp only [CellRenaming.expressions] at transport
      rw [transport]
      simp only [run] at evaluated
      repeat' first
        | contradiction
        | simp_all only [values, value, syncToHeap, syncFromHeap, Except.map,
            heap, withHeap, Outcome.done.injEq, List.cons.injEq,
            Value.pointer.injEq, Value.unsigned.injEq]
        | split at evaluated
      all_goals grind only [→ syncToHeap_nextCell, → syncFromHeap_nextCell, state, value]
  | _ => simp [run] at evaluated

theorem loadByteExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (pointer offset : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.loadByte pointer offset) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.loadByte (CellRenaming.expression rename.forward pointer) (CellRenaming.expression rename.forward offset)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before [pointer, offset] with
  | done entries next =>
      obtain ⟨transport, nextReady⟩ := step.expressions ready run
      simp only [CellRenaming.expressions] at transport
      rw [transport]
      simp only [run] at evaluated
      repeat' first
        | contradiction
        | simp_all only [values, value, syncToHeap, syncFromHeap, Except.map,
            heap, withHeap, Outcome.done.injEq, List.cons.injEq,
            Value.pointer.injEq, Value.unsigned.injEq]
        | split at evaluated
      all_goals grind only [→ syncToHeap_nextCell, → syncFromHeap_nextCell, state, value]
  | _ => simp [run] at evaluated

theorem storeByteExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (pointer offset input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.storeByte pointer offset input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.storeByte (CellRenaming.expression rename.forward pointer) (CellRenaming.expression rename.forward offset) (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before [pointer, offset, input] with
  | done entries next =>
      obtain ⟨transport, nextReady⟩ := step.expressions ready run
      simp only [CellRenaming.expressions] at transport
      rw [transport]
      simp only [run] at evaluated
      repeat' first
        | contradiction
        | simp_all only [values, value, syncToHeap, syncFromHeap, Except.map,
            heap, withHeap, Outcome.done.injEq, List.cons.injEq,
            Value.pointer.injEq, Value.unsigned.injEq]
        | split at evaluated
      all_goals grind only [→ syncToHeap_nextCell, → syncFromHeap_nextCell, state, value]
  | _ => simp [run] at evaluated

theorem allocExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (size alignment : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.alloc size alignment) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.alloc (CellRenaming.expression rename.forward size) (CellRenaming.expression rename.forward alignment)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases sizeRun : evalExpr fuel program before size with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready sizeRun
      rw [transport]
      cases entry <;> simp only [sizeRun] at evaluated
      all_goals try contradiction
      case unsigned type sizeValue =>
        cases type <;> try simp only [] at evaluated
        all_goals try contradiction
        simp only [value]
        cases alignmentRun : evalExpr fuel program next alignment with
        | done entry afterAlignment =>
            obtain ⟨alignmentTransport, alignmentReady⟩ := step.expression nextReady alignmentRun
            rw [alignmentTransport]
            cases entry <;> simp only [alignmentRun] at evaluated
            all_goals try contradiction
            case unsigned type alignmentValue =>
              cases type <;> try simp only [] at evaluated
              all_goals try contradiction
              simp only [value, heap]
              cases allocated : afterAlignment.heap.allocate sizeValue alignmentValue <;>
                simp only [allocated, Outcome.done.injEq] at evaluated
              all_goals try contradiction
              all_goals
                obtain ⟨rfl, rfl⟩ := evaluated
                exact ⟨by simp [allocated, value, withHeap], alignmentReady⟩
        | _ => simp [alignmentRun] at evaluated
  | _ => simp [sizeRun] at evaluated

theorem intrinsicExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (op : Intrinsic) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.intrinsic op input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.intrinsic op (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready run
      rw [transport]
      simp only [run] at evaluated
      repeat' first
        | contradiction
        | simp_all only [value, Outcome.done.injEq]
        | split at evaluated
      all_goals grind only [state, value]
  | _ => simp [run] at evaluated

end Lanius.Semantics.CellRenaming.Execution
