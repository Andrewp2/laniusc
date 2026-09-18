import Lanius.X86.Source.Register
import Lanius.X86.Buffer.Reservation
import Lanius.Separation.LocalStore

namespace Lanius.X86.Register

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

theorem validation_expression (program : Program) (kind : Validation) (input : Int)
    (found : before.local? 0 = some (.signed .i32 input)) :
    Evaluates program before (validationExpression kind) (.boolean (kind.accepts input)) before := by
  have readInput := local_evaluates program found
  cases kind with
  | register =>
      have low : Evaluates program before (.binary .greaterEqual (read 0) (number 0))
          (.boolean (decide (0 ≤ input))) before := by
        apply evaluatesEagerBinary (by decide) (by decide) readInput ⟨1, rfl⟩
        simp [evalBinaryValue, evalSignedBinary]
      have high : Evaluates program before (.binary .less (read 0) (number 16))
          (.boolean (decide (input < 16))) before := by
        apply evaluatesEagerBinary (by decide) (by decide) readInput ⟨1, rfl⟩
        simp [evalBinaryValue, evalSignedBinary]
      simpa only [validationExpression, Validation.accepts, Bool.decide_and] using evaluatesPureLogicalAnd low high
  | width =>
      have equal (n : Nat) : Evaluates program before (.binary .equal (read 0) (number n))
          (.boolean (decide (input = (n : Int)))) before := by
        apply evaluatesEagerBinary (by decide) (by decide) readInput ⟨1, rfl⟩
        simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, ↓reduceIte,
          Except.ok.injEq, Value.boolean.injEq]
        apply Bool.eq_iff_iff.mpr
        simp
      simpa only [validationExpression, Validation.accepts, Bool.decide_or,
        show ((32 : Nat) : Int) = 32 from rfl, show ((64 : Nat) : Int) = 64 from rfl]
        using evaluatesPureLogicalOr (equal 32) (equal 64)

/-- Both validators execute for every integer argument and preserve caller
state. Their acceptance domains are characterized by register_domain/width_domain. -/
theorem validation_call (checked : CheckedValidation program kind) (input : Int)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 input] before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.boolean (kind.accepts input)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun _ : Fin 1 => Value.signed .i32 input)
  let callee := enterCall before params
  have found : callee.local? 0 = some (.signed .i32 input) :=
    enterCall_parameterBindings_matches wellFormed ⟨0, by decide⟩
  have body := executesSequenceReturned (second := .skip)
    (executesReturnValue (validation_expression program.core kind input found))
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl body
    (CellEffect.refl (writes := CellSet.empty) (enterCall_preserves_wellFormed wellFormed))
  exact ⟨restoreLocals before callee, called.1, called.2,
    HeapFrame.closeCall before params (HeapFrame.refl callee)⟩

def inputValues (width : Width) (reg base : Fin 16) (forceByte : Bool) : List Value :=
  [.signed .i32 width.bits, .signed .i32 reg.val, .signed .i32 base.val, .boolean forceByte]

def Inputs (width : Width) (reg base : Fin 16) (forceByte : Bool) (state : State) : Prop :=
  ∀ index : Fin 4, state.local? index.val = some ((inputValues width reg base forceByte).get index)

theorem Inputs.bind {value : Value} (inputs : Inputs width reg base forceByte before) (wellFormed : StateWellFormed before) :
    Inputs width reg base forceByte (before.bindLocal 4 value) := by
  intro index
  exact (bindLocal_preserves_other_local (boundId := 4) (queriedId := index.val)
    (value := value) wellFormed (Nat.ne_of_gt index.isLt)).trans (inputs index)

theorem initial_evaluates (program : Program) (reg base : Fin 16)
    (regRead : before.local? 1 = some (.signed .i32 reg.val))
    (baseRead : before.local? 2 = some (.signed .i32 base.val)) :
    Evaluates program before rexInitial (.signed .i32 (initial reg base)) before := by
  have regBound := reg.isLt
  have baseBound := base.isLt
  have dividedReg := evaluatesNatI32Divide (leftValue := reg.val) (rightValue := 8)
    (local_evaluates program regRead) (show Evaluates program before (number 8) (.signed .i32 8) before from ⟨1, rfl⟩)
    (by decide) (by omega)
  have dividedBase := evaluatesNatI32Divide (leftValue := base.val) (rightValue := 8)
    (local_evaluates program baseRead) (show Evaluates program before (number 8) (.signed .i32 8) before from ⟨1, rfl⟩)
    (by decide) (by omega)
  have scaled := evaluatesNatI32Multiply (leftValue := reg.val / 8) (rightValue := 4)
    dividedReg (show Evaluates program before (number 4) (.signed .i32 4) before from ⟨1, rfl⟩) (by omega)
  have first := evaluatesNatI32Add (leftValue := 64) (rightValue := reg.val / 8 * 4)
    (show Evaluates program before (number 64) (.signed .i32 64) before from ⟨1, rfl⟩) scaled (by omega)
  exact evaluatesNatI32Add (leftValue := 64 + reg.val / 8 * 4) (rightValue := base.val / 8) first dividedBase (by omega)

/-- Execute the width flag update inside the fresh local's scope. Only that
fresh cell changes; the four input bindings remain available. -/
theorem selectWidth (program : Program) (width : Width) (reg base : Fin 16) (forceByte : Bool)
    (wellFormed : StateWellFormed before) (inputs : Inputs width reg base forceByte before) :
    ∃ after, Executes program (before.bindLocal 4 (.signed .i32 (initial reg base))) rexWidth .next after ∧
      Inputs width reg base forceByte after ∧
      after.local? 4 = some (.signed .i32 (fields width reg base).encode) ∧
      CellEffect (CellSet.singleton before.nextCell) (before.bindLocal 4 (.signed .i32 (initial reg base))) after ∧
      HeapFrame (before.bindLocal 4 (.signed .i32 (initial reg base))) after := by
  let start : Value := .signed .i32 (initial reg base)
  let scope := before.bindLocal 4 start
  have scopeWF := bindLocal_preserves_well_formed before 4 start wellFormed
  have scopeInputs : Inputs width reg base forceByte scope := inputs.bind wellFormed
  have guard : Evaluates program scope (.binary .equal (read 0) (number 64))
      (.boolean (decide (width = .w64))) scope := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (show Evaluates program scope (read 0) (.signed .i32 width.bits) scope from
        local_evaluates program (scopeInputs ⟨0, by decide⟩))
      (show Evaluates program scope (number 64) (.signed .i32 64) scope from ⟨1, rfl⟩)
    cases width <;> rfl
  cases width with
  | w32 =>
      have encoded : (fields .w32 reg base).encode = initial reg base := by
        simpa using fields_arithmetic .w32 reg base
      exact ⟨scope, executesIfFalse guard (executesSkip _ _), scopeInputs,
        encoded ▸ bindLocal_finds_local before 4 start wellFormed,
        CellEffect.refl scopeWF, HeapFrame.refl scope⟩
  | w64 =>
      have encoded : (fields .w64 reg base).encode = initial reg base + 8 := by
        simpa using fields_arithmetic .w64 reg base
      have operation : evalAssignValue program.target .add (some start) (.signed .i32 8) =
          .ok (.signed .i32 (fields .w64 reg base).encode) := by
        have bound := initial_bounds reg base
        simp only [start, evalAssignValue, assignOpBinary?, evalBinaryValue,
          beq_self_eq_true, if_true, evalSignedBinary]
        rw [wrapSigned_i32_of_nonnegative program.target ((initial reg base : Int) + 8) (by omega) (by omega), encoded]
        congr 2
      obtain ⟨after, assigned, owned, effect, heapFrame⟩ := evaluatesOwnedLocalUpdate
        scopeWF (bindLocal_owns_fresh before 4 start wellFormed)
        (show Evaluates program scope (number 8) (.signed .i32 8) scope from ⟨1, rfl⟩) operation
      refine ⟨after, executesIfTrue guard (executesSequence (executesExpression assigned) (executesSkip _ _)),
        ?_, Assertion.localPointsTo_local 4 before.nextCell _ after owned, effect, heapFrame⟩
      intro index
      apply effect.preserves_local scopeWF (scopeInputs index)
      intro cell binding same
      change cell = before.nextCell at same
      rw [same] at binding
      exact bindLocal_other_cellId_ne_fresh before 4 index.val start wellFormed (Nat.ne_of_gt index.isLt) binding

theorem return_value (program : Program) (width : Width) (reg base : Fin 16) (forceByte : Bool)
    (valueRead : before.local? 4 = some (.signed .i32 (fields width reg base).encode))
    (byteRead : before.local? 3 = some (.boolean forceByte)) :
    Executes program before rexReturn
      (.returned (some (.signed .i32 (value width reg base forceByte)))) before := by
  have same : Evaluates program before (.binary .equal (read 4) (number 64))
      (.boolean (decide ((fields width reg base).encode = 64))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program valueRead)
      (show Evaluates program before (number 64) (.signed .i32 64) before from ⟨1, rfl⟩)
    simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, ↓reduceIte,
      Except.ok.injEq, Value.boolean.injEq]
    apply Bool.eq_iff_iff.mpr
    simp
    omega
  have negated := evaluatesUnary (local_evaluates program byteRead)
    (show evalUnaryValue program.target .logicalNot (.boolean forceByte) = .ok (.boolean (!forceByte)) from rfl)
  have guard := evaluatesPureLogicalAnd same negated
  by_cases omitted : (fields width reg base).encode = 64 ∧ forceByte = false
  · have flag : (decide ((fields width reg base).encode = 64) && !forceByte) = true := by simp [omitted.1, omitted.2]
    rw [flag] at guard
    simp only [value, if_pos omitted]
    exact executesSequenceReturned (executesIfTrue guard
      (executesSequenceReturned (executesReturnValue ⟨1, rfl⟩)))
  · have flag : (decide ((fields width reg base).encode = 64) && !forceByte) = false := by
      cases forceByte <;> simp_all
    rw [flag] at guard
    simp only [value, if_neg omitted]
    exact executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequenceReturned (executesReturnValue (local_evaluates program valueRead)))

/-- Actual Lanius REX construction for validated operands. This does not assert
that rex itself rejects invalid widths or register numbers: its callers do so. -/
theorem rex_call (checked : CheckedRex program) (width : Width) (reg base : Fin 16) (forceByte : Bool)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (inputValues width reg base forceByte) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (value width reg base forceByte)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 4 => (inputValues width reg base forceByte).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs : Inputs width reg base forceByte callee :=
    fun index => enterCall_parameterBindings_matches wellFormed index
  have initialized := initial_evaluates program.core reg base (inputs ⟨1, by decide⟩) (inputs ⟨2, by decide⟩)
  obtain ⟨sized, selected, retained, valueRead, effect, heapFrame⟩ :=
    selectWidth program.core width reg base forceByte calleeWF inputs
  have returned := return_value program.core width reg base forceByte valueRead (retained ⟨3, by decide⟩)
  have body := executesLetLocal (id := 4) (type := i32) initialized (executesSequence selected returned)
  have closed := CellEffect.closeLocal callee 4 (.signed .i32 (initial reg base)) calleeWF effect
  have narrow : CellEffect CellSet.empty callee (restoreLocals callee sized) := by
    apply closed.narrow
    intro cell old member
    exact False.elim ((Nat.ne_of_lt old) member)
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl body narrow
  exact ⟨restoreLocals before (restoreLocals callee sized), called.1, called.2,
    HeapFrame.closeCall before params (HeapFrame.closeLocal callee 4 (.signed .i32 (initial reg base)) heapFrame)⟩

end Lanius.X86.Register
