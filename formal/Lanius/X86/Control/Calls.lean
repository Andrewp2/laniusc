import Lanius.X86.Buffer.Relative
import Lanius.X86.Control.Layout

namespace Lanius.X86.Control

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def directValues (output : Value) (capacity cursor target : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 cursor, .signed .i32 target]

def directBindings (output : Value) (capacity cursor target : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 4 => (directValues output capacity cursor target).get index)

theorem Transfer.direct_condition (transfer : Transfer) (direct : transfer.conditional = false) :
    transfer.condition = 0 := by
  cases transfer <;> simp_all [Transfer.conditional, Transfer.condition]

theorem direct_success (transfer : Transfer) (direct : transfer.conditional = false)
    (checked : CheckedDirect program relative name transfer.opcode)
    (capacity cursor target : Nat) (wellFormed : StateWellFormed before)
    (room : cursor + transfer.size ≤ capacity) (storage : capacity ≤ values.length)
    (capacityBound : capacity ≤ 2147483647) (targetBound : target ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (directValues (.slice i32 cell [] 0 values.length) capacity cursor target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (cursor + transfer.size : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (Relative.emittedValues transfer values cursor target))) } ∧
      transfer.Emission values cursor target (Relative.emittedValues transfer values cursor target) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let output : Value := .slice i32 cell [] 0 values.length
  let params := directBindings output capacity cursor target
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have locals (index : Fin 4) : callee.local? index.val = some ((directValues output capacity cursor target).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have zero : transfer.condition = 0 := transfer.direct_condition direct
  have arguments : ArgumentsEvaluateTo program.core callee
      [read 0, read 1, read 2, number transfer.opcode, number 0, read 3]
      (Relative.inputValues transfer output capacity cursor target) callee := by
    unfold Relative.inputValues
    rw [zero]
    exact .cons (local_evaluates program.core (locals ⟨0, by decide⟩))
      (.cons (local_evaluates program.core (locals ⟨1, by decide⟩))
        (.cons (local_evaluates program.core (locals ⟨2, by decide⟩))
          (.cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (locals ⟨3, by decide⟩)) (.nil _ _))))))
  obtain ⟨completed, run, contents, effect, heapFrame⟩ := Relative.succeeds relative transfer
    capacity cursor target calleeWF room storage capacityBound targetBound calleeBacking arguments
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequenceReturned (executesReturnValue run)) effect
  exact ⟨restoreLocals before completed, called.1, contents,
    transfer.emission (by omega) (by omega) targetBound, called.2, HeapFrame.closeCall before params heapFrame⟩

theorem direct_reject (transfer : Transfer) (direct : transfer.conditional = false)
    (checked : CheckedDirect program relative name transfer.opcode) (output : Value)
    (capacity cursor target : Int) (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ 2147483647) (bad : Relative.bad transfer capacity cursor target = true)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (directValues output capacity cursor target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := directBindings output capacity cursor target
  let callee := enterCall before params
  have locals (index : Fin 4) : callee.local? index.val = some ((directValues output capacity cursor target).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have zero : transfer.condition = 0 := transfer.direct_condition direct
  have arguments : ArgumentsEvaluateTo program.core callee
      [read 0, read 1, read 2, number transfer.opcode, number 0, read 3]
      (Relative.inputValues transfer output capacity cursor target) callee := by
    unfold Relative.inputValues
    rw [zero]
    exact .cons (local_evaluates program.core (locals ⟨0, by decide⟩))
      (.cons (local_evaluates program.core (locals ⟨1, by decide⟩))
        (.cons (local_evaluates program.core (locals ⟨2, by decide⟩))
          (.cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (locals ⟨3, by decide⟩)) (.nil _ _))))))
  obtain ⟨completed, run, effect, heapFrame⟩ := Relative.rejects relative transfer output capacity cursor target
    (enterCall_preserves_wellFormed wellFormed) capacityBound bad arguments
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequenceReturned (executesReturnValue run)) effect
  exact ⟨restoreLocals before completed, called.1, called.2, HeapFrame.closeCall before params heapFrame⟩

def branchValues (output : Value) (capacity cursor condition target : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 cursor, .signed .i32 condition, .signed .i32 target]

def branchBindings (output : Value) (capacity cursor condition target : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 5 => (branchValues output capacity cursor condition target).get index)

def conditionBad (condition : Int) : Bool := decide (condition < 0) || decide (15 < condition)

theorem branch_guard (program : Program) (condition : Int)
    (conditionRead : before.local? 3 = some (.signed .i32 condition)) :
    Evaluates program before branchGuard (.boolean (conditionBad condition)) before := by
  have lower : Evaluates program before (.binary .less (read 3) (number 0))
      (.boolean (decide (condition < 0))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program conditionRead)
      (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  have upper : Evaluates program before (.binary .greater (read 3) (number 15))
      (.boolean (decide (15 < condition))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program conditionRead)
      (show Evaluates program before (number 15) (.signed .i32 15) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  exact evaluatesPureLogicalOr lower upper

theorem condition_good (condition : Fin 16) : conditionBad condition.val = false := by
  have bound := condition.isLt
  simp only [conditionBad, Bool.or_eq_false_iff, decide_eq_false_iff_not]
  omega

theorem branch_invalid (checked : CheckedBranch program relative) (output : Value)
    (capacity cursor condition target : Int) (wellFormed : StateWellFormed before)
    (bad : conditionBad condition = true)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (branchValues output capacity cursor condition target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := branchBindings output capacity cursor condition target
  let callee := enterCall before params
  have locals (index : Fin 5) : callee.local? index.val =
      some ((branchValues output capacity cursor condition target).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have guard := branch_guard program.core condition (locals ⟨3, by decide⟩)
  rw [bad] at guard
  have run : Executes program.core callee (branchBody relative.source.function.id)
      (.returned (some (.signed .i32 (-1)))) callee :=
    executesSequenceReturned (executesIfTrue guard
      (executesSequenceReturned (executesReturnValue (Relative.negativeValue program.core callee))))
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl run
    (CellEffect.refl (writes := CellSet.empty) (enterCall_preserves_wellFormed wellFormed))
  exact ⟨restoreLocals before callee, called.1, called.2, HeapFrame.closeCall before params (HeapFrame.refl callee)⟩

theorem branch_success (checked : CheckedBranch program relative) (condition : Fin 16)
    (capacity cursor target : Nat) (wellFormed : StateWellFormed before)
    (room : cursor + 6 ≤ capacity) (storage : capacity ≤ values.length)
    (capacityBound : capacity ≤ 2147483647) (targetBound : target ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (branchValues (.slice i32 cell [] 0 values.length) capacity cursor condition.val target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (cursor + 6 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (Relative.emittedValues (.branch condition) values cursor target))) } ∧
      (Transfer.branch condition).Emission values cursor target
        (Relative.emittedValues (.branch condition) values cursor target) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let output : Value := .slice i32 cell [] 0 values.length
  let params := branchBindings output capacity cursor condition.val target
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have locals (index : Fin 5) : callee.local? index.val =
      some ((branchValues output capacity cursor condition.val target).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have guard := branch_guard program.core condition.val (locals ⟨3, by decide⟩)
  rw [condition_good] at guard
  have arguments : ArgumentsEvaluateTo program.core callee
      [read 0, read 1, read 2, number 15, read 3, read 4]
      (Relative.inputValues (.branch condition) output capacity cursor target) callee :=
    .cons (local_evaluates program.core (locals ⟨0, by decide⟩))
      (.cons (local_evaluates program.core (locals ⟨1, by decide⟩))
        (.cons (local_evaluates program.core (locals ⟨2, by decide⟩))
          (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (locals ⟨3, by decide⟩))
            (.cons (local_evaluates program.core (locals ⟨4, by decide⟩)) (.nil _ _))))))
  obtain ⟨completed, run, contents, effect, heapFrame⟩ := Relative.succeeds relative (.branch condition)
    capacity cursor target calleeWF room storage capacityBound targetBound calleeBacking arguments
  have body : Executes program.core callee (branchBody relative.source.function.id)
      (.returned (some (.signed .i32 (cursor + 6 : Nat)))) completed :=
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequenceReturned (executesReturnValue run))
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl body effect
  exact ⟨restoreLocals before completed, called.1, contents,
    (Transfer.branch condition).emission (Nat.le_trans room storage)
      (Nat.le_trans room capacityBound) targetBound,
    called.2, HeapFrame.closeCall before params heapFrame⟩

theorem branch_reject (checked : CheckedBranch program relative) (condition : Fin 16) (output : Value)
    (capacity cursor target : Int) (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ 2147483647) (bad : Relative.bad (.branch condition) capacity cursor target = true)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (branchValues output capacity cursor condition.val target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := branchBindings output capacity cursor condition.val target
  let callee := enterCall before params
  have locals (index : Fin 5) : callee.local? index.val =
      some ((branchValues output capacity cursor condition.val target).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have guard := branch_guard program.core condition.val (locals ⟨3, by decide⟩)
  rw [condition_good] at guard
  have arguments : ArgumentsEvaluateTo program.core callee
      [read 0, read 1, read 2, number 15, read 3, read 4]
      (Relative.inputValues (.branch condition) output capacity cursor target) callee :=
    .cons (local_evaluates program.core (locals ⟨0, by decide⟩))
      (.cons (local_evaluates program.core (locals ⟨1, by decide⟩))
        (.cons (local_evaluates program.core (locals ⟨2, by decide⟩))
          (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (locals ⟨3, by decide⟩))
            (.cons (local_evaluates program.core (locals ⟨4, by decide⟩)) (.nil _ _))))))
  obtain ⟨completed, run, effect, heapFrame⟩ := Relative.rejects relative (.branch condition) output
    capacity cursor target (enterCall_preserves_wellFormed wellFormed) capacityBound bad arguments
  have body : Executes program.core callee (branchBody relative.source.function.id)
      (.returned (some (.signed .i32 (-1)))) completed :=
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequenceReturned (executesReturnValue run))
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl body effect
  exact ⟨restoreLocals before completed, called.1, called.2, HeapFrame.closeCall before params heapFrame⟩

end Lanius.X86.Control
