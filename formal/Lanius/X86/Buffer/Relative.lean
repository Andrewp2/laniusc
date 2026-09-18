import Lanius.X86.Source.Relative
import Lanius.X86.Control.Transfer
import Lanius.Separation.LocalStore
import Lanius.X86.Relative.Core

namespace Lanius.X86.Buffer.Relative

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Control

def inputValues (transfer : Transfer) (output : Value) (capacity cursor target : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 cursor, .signed .i32 transfer.opcode,
    .signed .i32 transfer.condition, .signed .i32 target]

def Inputs (transfer : Transfer) (output : Value) (capacity cursor target : Int) (state : State) : Prop :=
  ∀ index : Fin 6, state.local? index.val = some ((inputValues transfer output capacity cursor target).get index)

theorem Inputs.bind {id : VarId} (inputs : Inputs transfer output capacity cursor target before)
    (wellFormed : StateWellFormed before) (fresh : 6 ≤ id) :
    Inputs transfer output capacity cursor target (before.bindLocal id value) := by
  intro index
  exact (bindLocal_preserves_other_local (boundId := id) (queriedId := index.val)
    (value := value) wellFormed (Nat.ne_of_gt (Nat.lt_of_lt_of_le index.isLt fresh))).trans (inputs index)

theorem Inputs.empty (inputs : Inputs transfer output capacity cursor target before)
    (wellFormed : StateWellFormed before) (effect : CellEffect CellSet.empty before after) :
    Inputs transfer output capacity cursor target after :=
  fun index => effect.empty_preserves_local wellFormed (inputs index)

theorem Inputs.store (inputs : Inputs transfer (.slice i32 cell [] 0 length) capacity cursor target before)
    (wellFormed : StateWellFormed before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array values) })
    (effect : CellEffect (CellSet.singleton cell) before after) :
    Inputs transfer (.slice i32 cell [] 0 length) capacity cursor target after := by
  intro index
  apply effect.preserves_local_of_distinct_value wellFormed (inputs index) backing
  rcases index with ⟨index, bound⟩
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl <;> intro same <;> cases same

theorem conditional (program : Program) (transfer : Transfer)
    (opcodeRead : before.local? 3 = some (.signed .i32 transfer.opcode)) :
    Evaluates program before relativeConditional (.boolean transfer.conditional) before := by
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program opcodeRead)
    (show Evaluates program before (number 15) (.signed .i32 15) before from ⟨1, rfl⟩)
  cases transfer <;> rfl

/-- Execute the size selection inside its real lexical scope. Writes to the
fresh size cell cannot alias any of the six caller parameters. -/
theorem selectSize (program : Program) (transfer : Transfer)
    (wellFormed : StateWellFormed before) (inputs : Inputs transfer output capacity cursor target before) :
    ∃ after, Executes program (before.bindLocal 6 (.signed .i32 5)) relativeSize .next after ∧
      Inputs transfer output capacity cursor target after ∧
      after.local? 6 = some (.signed .i32 transfer.size) ∧
      CellEffect (CellSet.singleton before.nextCell) (before.bindLocal 6 (.signed .i32 5)) after ∧
      HeapFrame (before.bindLocal 6 (.signed .i32 5)) after := by
  let scope := before.bindLocal 6 (.signed .i32 5)
  have scopeWF := bindLocal_preserves_well_formed before 6 (.signed .i32 5) wellFormed
  have scopeInputs : Inputs transfer output capacity cursor target scope := inputs.bind wellFormed (by decide)
  have guard := conditional program transfer (scopeInputs ⟨3, by decide⟩)
  cases choice : transfer.conditional with
  | false =>
      have size : transfer.size = 5 := by simp [Transfer.size, choice]
      rw [choice] at guard
      exact ⟨scope, executesIfFalse guard (executesSkip _ _), scopeInputs,
        (by simpa only [size, show ((5 : Nat) : Int) = 5 from rfl]
          using bindLocal_finds_local before 6 (.signed .i32 5) wellFormed),
        CellEffect.refl scopeWF, HeapFrame.refl scope⟩
  | true =>
      have size : transfer.size = 6 := by simp [Transfer.size, choice]
      rw [choice] at guard
      obtain ⟨after, assigned, owned, effect, heapFrame⟩ := evaluatesOwnedLocalUpdate
        scopeWF (bindLocal_owns_fresh before 6 (.signed .i32 5) wellFormed)
        (show Evaluates program scope (number 6) (.signed .i32 6) scope from ⟨1, rfl⟩)
        (show evalAssignValue program.target .set (some (.signed .i32 5)) (.signed .i32 6) =
          .ok (.signed .i32 6) from rfl)
      refine ⟨after, executesIfTrue guard (executesSequence (executesExpression assigned) (executesSkip _ _)),
        ?_, (by simpa only [size, show ((6 : Nat) : Int) = 6 from rfl]
          using Assertion.localPointsTo_local 6 before.nextCell (.signed .i32 6) after owned),
        effect, heapFrame⟩
      intro index
      apply effect.preserves_local scopeWF (scopeInputs index)
      intro cell binding same
      change cell = before.nextCell at same
      rw [same] at binding
      exact bindLocal_other_cellId_ne_fresh before 6 index.val (.signed .i32 5)
        wellFormed (Nat.ne_of_gt index.isLt) binding

def bad (transfer : Transfer) (capacity cursor target : Int) : Bool :=
  decide (target < 0) || !reserved capacity cursor transfer.size

/-- Negative targets short-circuit without calling fits. Other cases execute
the checked reservation call, preserving the emitter's live size local. -/
theorem guard (fits : CheckedFits program) (transfer : Transfer)
    (wellFormed : StateWellFormed before) (capacityBound : capacity ≤ 2147483647)
    (inputs : Inputs transfer output capacity cursor target before)
    (sizeRead : before.local? 6 = some (.signed .i32 transfer.size)) :
    ∃ after, Evaluates program.core before (relativeGuard fits.source.function.id)
        (.boolean (bad transfer capacity cursor target)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have negative : Evaluates program.core before (.binary .less (read 5) (number 0))
      (.boolean (decide (target < 0))) before := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (show Evaluates program.core before (read 5) (.signed .i32 target) before from
        local_evaluates program.core (inputs ⟨5, by decide⟩))
      (show Evaluates program.core before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  by_cases below : target < 0
  · simp only [below, decide_true] at negative
    have result : bad transfer capacity cursor target = true := by simp [bad, below]
    rw [result]
    exact ⟨before, evaluatesLogicalOrTrue negative, CellEffect.refl wellFormed, HeapFrame.refl before⟩
  · simp only [below, decide_false] at negative
    have arguments : ArgumentsEvaluateTo program.core before [read 1, read 2, read 6]
        (fitsValues capacity cursor transfer.size) before :=
      .cons (local_evaluates program.core (inputs ⟨1, by decide⟩))
        (.cons (local_evaluates program.core (inputs ⟨2, by decide⟩))
          (.cons (local_evaluates program.core sizeRead) (.nil _ _)))
    obtain ⟨after, fit, effect, heapFrame⟩ := fits_call fits capacity cursor transfer.size wellFormed capacityBound arguments
    have negated := evaluatesUnary fit (show evalUnaryValue program.core.target .logicalNot
      (.boolean (reserved capacity cursor transfer.size)) =
        .ok (.boolean (!reserved capacity cursor transfer.size)) from rfl)
    have result : bad transfer capacity cursor target = !reserved capacity cursor transfer.size := by simp [bad, below]
    rw [result]
    exact ⟨after, evaluatesLogicalOrFalse negative negated, effect, heapFrame⟩

theorem negativeValue (program : Program) (state : State) :
    Evaluates program state negativeOne (.signed .i32 (-1)) state := by
  apply evaluatesUnary (show Evaluates program state (number 1) (.signed .i32 1) state from ⟨1, rfl⟩)
  simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

def bindings (transfer : Transfer) (output : Value) (capacity cursor target : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 6 => (inputValues transfer output capacity cursor target).get index)

theorem rejects (checked : CheckedRelative program fits word) (transfer : Transfer) (output : Value)
    (capacity cursor target : Int) (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ 2147483647) (rejected : bad transfer capacity cursor target = true)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputValues transfer output capacity cursor target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := bindings transfer output capacity cursor target
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs : Inputs transfer output capacity cursor target callee :=
    fun index => enterCall_parameterBindings_matches wellFormed index
  obtain ⟨sized, sizeRun, sizeInputs, sizeRead, sizeEffect, sizeHeap⟩ :=
    selectSize program.core transfer calleeWF inputs
  obtain ⟨middle, guardRun, guardEffect, guardHeap⟩ :=
    guard fits transfer sizeEffect.wellFormed capacityBound sizeInputs sizeRead
  rw [rejected] at guardRun
  have afterSize : Executes program.core sized
      (relativeAfterSize fits.source.function.id word.source.function.id)
      (.returned (some (.signed .i32 (-1)))) middle :=
    executesSequenceReturned (executesIfTrue guardRun
      (executesSequenceReturned (executesReturnValue (negativeValue program.core middle))))
  have run : Executes program.core callee
      (relativeBody fits.source.function.id word.source.function.id)
      (.returned (some (.signed .i32 (-1)))) (restoreLocals callee middle) :=
    executesLetLocal (show Evaluates program.core callee (number 5) (.signed .i32 5) callee from ⟨1, rfl⟩)
      (executesSequence sizeRun afterSize)
  have effect := CellEffect.closeLocal callee 6 (.signed .i32 5) calleeWF
    (sizeEffect.trans (guardEffect.weaken CellSet.empty_subset))
  have narrow : CellEffect CellSet.empty callee (restoreLocals callee middle) := by
    apply effect.narrow
    intro cell old same
    change cell = callee.nextCell at same
    exact (Nat.ne_of_lt old) same
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl run narrow
  exact ⟨restoreLocals before (restoreLocals callee middle), called.1, called.2,
    HeapFrame.closeCall before params
      (HeapFrame.closeLocal callee 6 (.signed .i32 5) (sizeHeap.trans guardHeap))⟩

/-- Live emitter parameters after the next-cursor local has been bound. -/
structure WriteReady (transfer : Transfer) (cell : CellId) (capacity cursor target : Nat)
    (state : State) (values : List Int) : Prop where
  wellFormed : StateWellFormed state
  inputs : Inputs transfer (.slice i32 cell [] 0 values.length) capacity cursor target state
  nextRead : state.local? 7 = some (.signed .i32 (cursor + transfer.size : Nat))
  backing : state.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) }

theorem WriteReady.store (ready : WriteReady transfer cell capacity cursor target before values)
    (sameLength : changed.length = values.length)
    (contents : after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values changed)) })
    (effect : CellEffect (CellSet.singleton cell) before after) :
    WriteReady transfer cell capacity cursor target after changed := by
  refine ⟨effect.wellFormed, ?_, ?_, contents⟩
  · simpa only [sameLength] using ready.inputs.store ready.wellFormed ready.backing effect
  · exact effect.preserves_local_of_distinct_value ready.wellFormed ready.nextRead ready.backing
      (by intro same; cases same)

theorem opcode (program : Program) (ready : WriteReady transfer cell capacity cursor target before values)
    (room : cursor + transfer.size ≤ values.length) :
    ∃ after, Evaluates program before relativeOpcode .unit after ∧
      WriteReady transfer cell capacity cursor target after (values.set cursor transfer.opcode) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have sizeBounds := transfer.size_bounds
  obtain ⟨after, store, contents, effect, heapFrame, _⟩ := evaluatesSliceStore program before before
    values 0 (read 2) (read 3) cell cursor transfer.opcode ready.wellFormed (by omega)
    (ready.inputs ⟨0, by decide⟩) (local_evaluates program (ready.inputs ⟨2, by decide⟩))
    (local_evaluates program (ready.inputs ⟨3, by decide⟩))
    (CellEffect.refl ready.wellFormed) ready.backing
  exact ⟨after, store, ready.store List.length_set contents effect, effect, heapFrame⟩

def conditionValues (transfer : Transfer) (values : List Int) (cursor : Nat) : List Int :=
  if transfer.conditional then values.set (cursor + 1) (128 + transfer.condition : Nat) else values

@[simp] theorem conditionValues_length : (conditionValues transfer values cursor).length = values.length := by
  unfold conditionValues
  split <;> simp

theorem condition (program : Program) (ready : WriteReady transfer cell capacity cursor target before values)
    (room : cursor + transfer.size ≤ values.length) (cursorBound : cursor + transfer.size ≤ 2147483647) :
    ∃ after, Executes program before relativeCondition .next after ∧
      WriteReady transfer cell capacity cursor target after (conditionValues transfer values cursor) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have check := conditional program transfer (ready.inputs ⟨3, by decide⟩)
  cases choice : transfer.conditional with
  | false =>
      rw [choice] at check
      exact ⟨before, executesIfFalse check (executesSkip _ _),
        (by simpa only [conditionValues, choice, Bool.false_eq_true, ↓reduceIte] using ready),
        CellEffect.refl ready.wellFormed, HeapFrame.refl before⟩
  | true =>
      rw [choice] at check
      have sizeBounds := transfer.size_bounds
      have conditionBound := transfer.condition_bound
      have index := evaluatesNatI32Add (leftValue := cursor) (rightValue := 1)
        (local_evaluates program (ready.inputs ⟨2, by decide⟩))
        (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩) (by omega)
      have byte := evaluatesNatI32Add (leftValue := 128) (rightValue := transfer.condition)
        (show Evaluates program before (number 128) (.signed .i32 128) before from ⟨1, rfl⟩)
        (local_evaluates program (ready.inputs ⟨4, by decide⟩)) (by omega)
      obtain ⟨after, store, contents, effect, heapFrame, _⟩ := evaluatesSliceStore program before before
        values 0 (.binary .add (read 2) (number 1)) (.binary .add (number 128) (read 4))
        cell (cursor + 1) (128 + transfer.condition : Nat) ready.wellFormed (by omega)
        (ready.inputs ⟨0, by decide⟩) index byte (CellEffect.refl ready.wellFormed) ready.backing
      refine ⟨after, executesIfTrue check (executesSequence (executesExpression store) (executesSkip _ _)),
        ?_, effect, heapFrame⟩
      simpa only [conditionValues, choice, ↓reduceIte] using ready.store List.length_set contents effect

def headerValues (transfer : Transfer) (values : List Int) (cursor : Nat) : List Int :=
  conditionValues transfer (values.set cursor transfer.opcode) cursor

@[simp] theorem headerValues_length : (headerValues transfer values cursor).length = values.length := by
  simp [headerValues]

theorem headerValues_bytes (transfer : Transfer) (values : List Int) (cursor : Nat) :
    headerValues transfer values cursor = writtenBytes values cursor transfer.header := by
  cases transfer <;> rfl

def emittedValues (transfer : Transfer) (values : List Int) (cursor target : Nat) : List Int :=
  writtenWord (headerValues transfer values cursor) (cursor + transfer.size - 4)
    (relativeDisplacement (cursor + transfer.size) target)

theorem write (word : CheckedWord program)
    (ready : WriteReady transfer cell capacity cursor target before values)
    (room : cursor + transfer.size ≤ values.length) (cursorBound : cursor + transfer.size ≤ 2147483647)
    (targetBound : target ≤ 2147483647) :
    ∃ after, Executes program.core before (relativeWrite word.source.function.id)
        (.returned (some (.signed .i32 (cursor + transfer.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (emittedValues transfer values cursor target))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨first, firstRun, firstReady, firstEffect, firstHeap⟩ := opcode program.core ready room
  obtain ⟨second, secondRun, secondReady, secondEffect, secondHeap⟩ := condition program.core firstReady
    (by simpa only [List.length_set] using room) cursorBound
  have sizeBounds := transfer.size_bounds
  have field := evaluatesNatI32Subtract (leftValue := cursor + transfer.size) (rightValue := 4)
    (local_evaluates program.core secondReady.nextRead)
    (show Evaluates program.core second (number 4) (.signed .i32 4) second from ⟨1, rfl⟩) (by omega) (by omega)
  have delta := relative_evaluates (cursor + transfer.size) target cursorBound targetBound
    (local_evaluates program.core (secondReady.inputs ⟨5, by decide⟩))
    (local_evaluates program.core secondReady.nextRead)
  have arguments : ArgumentsEvaluateTo program.core second
      [read 0, .binary .subtract (read 7) (number 4), .binary .subtract (read 5) (read 7)]
      (wordValues (.slice i32 cell [] 0 (headerValues transfer values cursor).length)
        (cursor + transfer.size - 4) (relativeDisplacement (cursor + transfer.size) target)) second :=
    .cons (local_evaluates program.core (secondReady.inputs ⟨0, by decide⟩))
      (.cons field (.cons delta (.nil _ _)))
  obtain ⟨after, called, contents, effect, heapFrame⟩ := word_call word (cursor + transfer.size - 4)
    (relativeDisplacement (cursor + transfer.size) target) secondReady.wellFormed
    (by simpa only [headerValues, conditionValues_length, List.length_set] using
      (show cursor + transfer.size - 4 + 4 ≤ values.length by omega))
    (by omega) secondReady.backing arguments
  have sameNext : cursor + transfer.size - 4 + 4 = cursor + transfer.size := by omega
  rw [sameNext] at called
  exact ⟨after, executesSequence (executesExpression firstRun)
      (executesSequence secondRun (executesSequenceReturned (executesReturnValue called))),
    contents, (firstEffect.trans secondEffect).trans effect, (firstHeap.trans secondHeap).trans heapFrame⟩

theorem afterSize (fits : CheckedFits program) (word : CheckedWord program) (transfer : Transfer)
    (capacity cursor target : Nat) (wellFormed : StateWellFormed before)
    (inputs : Inputs transfer (.slice i32 cell [] 0 values.length) capacity cursor target before)
    (sizeRead : before.local? 6 = some (.signed .i32 transfer.size))
    (room : cursor + transfer.size ≤ capacity) (storage : capacity ≤ values.length)
    (capacityBound : capacity ≤ 2147483647) (targetBound : target ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) }) :
    ∃ after, Executes program.core before (relativeAfterSize fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (cursor + transfer.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (emittedValues transfer values cursor target))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨guarded, guardRun, guardEffect, guardHeap⟩ :=
    guard fits transfer wellFormed (Int.ofNat_le.mpr capacityBound) inputs sizeRead
  have good : bad transfer capacity cursor target = false := by
    have reserved : reserved capacity cursor transfer.size = true := by
      simp only [Buffer.reserved, decide_eq_true_eq]
      omega
    simp [bad, reserved]
  rw [good] at guardRun
  have guardedInputs := inputs.empty wellFormed guardEffect
  have guardedSize := guardEffect.empty_preserves_local wellFormed sizeRead
  have next := evaluatesNatI32Add (leftValue := cursor) (rightValue := transfer.size)
    (local_evaluates program.core (guardedInputs ⟨2, by decide⟩))
    (local_evaluates program.core guardedSize) (by omega)
  let nextValue : Value := .signed .i32 (cursor + transfer.size : Nat)
  let scope := guarded.bindLocal 7 nextValue
  have guardedBacking := guardEffect.empty_preserves_entry wellFormed backing
  have ready : WriteReady transfer cell capacity cursor target scope values := {
    wellFormed := bindLocal_preserves_well_formed guarded 7 nextValue guardEffect.wellFormed
    inputs := guardedInputs.bind guardEffect.wellFormed (by decide)
    nextRead := bindLocal_finds_local guarded 7 nextValue guardEffect.wellFormed
    backing := ((bindLocal_effect guarded 7 nextValue).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry guardEffect.wellFormed guardedBacking)
      (by simp [CellSet.empty])).trans guardedBacking
  }
  obtain ⟨written, writeRun, contents, writeEffect, writeHeap⟩ :=
    write word ready (by omega) (by omega) targetBound
  have body := executesLetLocal (id := 7) (type := i32) next writeRun
  have effect := CellEffect.closeLocal guarded 7 nextValue guardEffect.wellFormed writeEffect
  exact ⟨restoreLocals guarded written,
    executesSequence (executesIfFalse guardRun (executesSkip _ _)) body, contents,
    (guardEffect.weaken CellSet.empty_subset).trans effect,
    guardHeap.trans (HeapFrame.closeLocal guarded 7 nextValue writeHeap)⟩

/-- Execute the entire checked relative-emission helper. Temporary size and
next-cursor cells are hidden on return; only the output backing cell may change. -/
theorem succeeds (checked : CheckedRelative program fits word) (transfer : Transfer)
    (capacity cursor target : Nat) (wellFormed : StateWellFormed before)
    (room : cursor + transfer.size ≤ capacity) (storage : capacity ≤ values.length)
    (capacityBound : capacity ≤ 2147483647) (targetBound : target ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputValues transfer (.slice i32 cell [] 0 values.length) capacity cursor target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (cursor + transfer.size : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (emittedValues transfer values cursor target))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let output : Value := .slice i32 cell [] 0 values.length
  let params := bindings transfer output capacity cursor target
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs : Inputs transfer output capacity cursor target callee :=
    fun index => enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have scopeBacking := ((bindLocal_effect callee 6 (.signed .i32 5)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry calleeWF calleeBacking) (by simp [CellSet.empty])).trans calleeBacking
  obtain ⟨sized, sizeRun, sizeInputs, sizeRead, sizeEffect, sizeHeap⟩ :=
    selectSize program.core transfer calleeWF inputs
  have sizedBacking := sizeEffect.preserves_entry
    (bindLocal_preserves_well_formed callee 6 (.signed .i32 5) calleeWF) scopeBacking
    (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry calleeWF calleeBacking))
  obtain ⟨written, writeRun, contents, writeEffect, writeHeap⟩ :=
    afterSize fits word transfer capacity cursor target sizeEffect.wellFormed sizeInputs sizeRead
      room storage capacityBound targetBound sizedBacking
  have body : Executes program.core callee
      (relativeBody fits.source.function.id word.source.function.id)
      (.returned (some (.signed .i32 (cursor + transfer.size : Nat)))) (restoreLocals callee written) :=
    executesLetLocal (show Evaluates program.core callee (number 5) (.signed .i32 5) callee from ⟨1, rfl⟩)
      (executesSequence sizeRun writeRun)
  have effect := CellEffect.closeLocal callee 6 (.signed .i32 5) calleeWF
    ((sizeEffect.weaken CellSet.subset_union_left).trans (writeEffect.weaken CellSet.subset_union_right))
  have narrow : CellEffect (CellSet.singleton cell) callee (restoreLocals callee written) := by
    apply effect.narrow
    intro changed old member
    rcases member with temporary | output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
    · exact output
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl body narrow
  exact ⟨restoreLocals before (restoreLocals callee written), called.1, contents, called.2,
    HeapFrame.closeCall before params
      (HeapFrame.closeLocal callee 6 (.signed .i32 5) (sizeHeap.trans writeHeap))⟩

end Lanius.X86.Buffer.Relative
