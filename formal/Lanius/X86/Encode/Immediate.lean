import Lanius.X86.Source.Immediate
import Lanius.X86.Encode.Register
import Lanius.Separation.LocalCall
import Lanius.X86.Machine.Scalar
import Lanius.X86.Control.Emission

namespace Lanius.X86.Encode.Immediate

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The literal compiler uses MOV EAX, imm32. The authenticated source also
contains the 64-bit form; this theorem only accepts its actual 32-bit inputs. -/
def inputs (output : Value) (capacity start low high : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 32,
    .signed .i32 0, .signed .i32 low, .signed .i32 high]
def saved (output : Value) (capacity start low high : Int) : List Value :=
  inputs output capacity start low high ++ [.signed .i32 0]
def written (values : List Int) (start : Nat) (low : Int) : List Int :=
  writtenWord (values.set start 184) (start + 1) low
def bytes (low : Int) : List UInt8 := [184] ++ i32Bytes low

@[simp] theorem inputs_length : (inputs output capacity start low high).length = 7 := rfl
@[simp] theorem saved_length : (saved output capacity start low high).length = 8 := rfl
@[simp] theorem written_length : (written values start low).length = values.length := by simp [written]
@[simp] theorem bytes_length : (bytes low).length = 5 := by simp [bytes, i32Bytes_length]

theorem emission (room : start + 5 ≤ values.length) :
    byteSlice (written values start low) start 5 = bytes low := by
  simpa [written, bytes, writtenBytes] using writtenHeaderWord_byteSlice [184] low room

theorem frame (outside : index < start ∨ start + 5 ≤ index) :
    (written values start low)[index]? = values[index]? := by
  rw [written, writtenWord_frame (by omega)]
  exact List.getElem?_set_ne (by omega)

theorem not_array (output : Value) (notArray : ∀ elements, output ≠ .array elements) :
    ∀ index : Fin (saved output capacity start low high).length, ∀ elements,
      (saved output capacity start low high).get index ≠ .array elements := by
  intro ⟨index, bound⟩ elements
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 ∨ index = 6 ∨ index = 7 := by
    change index < 8 at bound
    omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact notArray elements
  all_goals intro same; cases same

theorem wide_false (program : Program) (found : before.local? 3 = some (.signed .i32 32)) :
    Evaluates program before Source.Immediate.wide (.boolean false) before :=
  evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found) ⟨1, rfl⟩ rfl

theorem rex_false (program : Program) (found : before.local? 7 = some (.signed .i32 0)) :
    Evaluates program before Source.Immediate.hasRex (.boolean false) before :=
  evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found) ⟨1, rfl⟩ rfl

theorem opcode_value (program : Program) (found : before.local? 4 = some (.signed .i32 0)) :
    Evaluates program before Source.Immediate.opcode (.signed .i32 184) before := by
  have remainder : Evaluates program before (.binary .remainder (read 4) (number 8)) (.signed .i32 0) before :=
    evaluatesNatI32Remainder (leftValue := 0) (rightValue := 8)
      (local_evaluates program found) ⟨1, rfl⟩ (by decide) (by decide)
  exact evaluatesNatI32Add (leftValue := 184) (rightValue := 0) ⟨1, rfl⟩ remainder (by decide)

theorem tail (word : CheckedWord program)
    (cursor : Cursor before cell temporary 9 position values)
    (locals : Locals (saved output capacity start low high) frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ elements, output ≠ .array elements)
    (room : position + 5 ≤ values.length) (bounded : position + 5 ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Immediate.tail word.source.function.id)
        (.returned (some (.signed .i32 (position + 5 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values position low))) } ∧
      CellEffect (CellSet.union (CellSet.singleton cell) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  obtain ⟨first, opcodeRun, firstCursor, firstLocals, firstEffect, firstHeap⟩ :=
    cursor.store program.core locals (not_array output notArray) 0 184 (by omega) (by omega)
      (opcode_value program.core (locals.found ⟨4, by simp⟩))
  have args : ArgumentsEvaluateTo program.core first [read 0, .binary .add (read 9) (number 1), read 5]
      (wordValues (.slice i32 cell [] 0 (values.set position 184).length) (position + 1) low) first :=
    .cons (local_evaluates program.core firstCursor.sliceRead)
      (.cons (firstCursor.index program.core 1 (by omega))
        (.cons (local_evaluates program.core (firstLocals.found ⟨5, by simp⟩)) (.nil _ _)))
  obtain ⟨second, wordRun, secondBacking, wordEffect, wordHeap⟩ := word_call word (position + 1) low
    firstCursor.wellFormed (by simpa only [List.length_set, Nat.add_assoc] using room)
    (by omega) firstCursor.backing args
  have owned := wordEffect.preserves_localPointsTo firstCursor.wellFormed firstCursor.position firstCursor.distinct
  obtain ⟨third, assigned, thirdOwned, assignedEffect, localEffect, localHeap, _⟩ :=
    evaluatesOwnedLocalSet firstCursor.position wordRun wordEffect owned
  have secondLocals := firstLocals.store firstCursor.wellFormed wordEffect firstCursor.backing
    (fun index => not_array output notArray index _)
  have thirdLocals := secondLocals.fresh wordEffect.wellFormed localEffect fresh
  have contents := localEffect.preserves_entry wordEffect.wellFormed secondBacking (Ne.symm firstCursor.distinct)
  have returned := executesSequenceReturned (second := .skip) (executesReturnValue
    (local_evaluates program.core (Assertion.localPointsTo_local 9 temporary _ third thirdOwned)))
  have highRun : Executes program.core third (Source.Immediate.highWord word.source.function.id) .next third :=
    executesIfFalse (wide_false program.core (thirdLocals.found ⟨3, by simp⟩)) (executesSkip _ _)
  have run := executesSequence (executesExpression opcodeRun)
    (executesSequence (executesExpression assigned)
      (executesSequence highRun returned))
  refine ⟨third, ?_, contents, (firstEffect.weaken CellSet.subset_union_left).trans assignedEffect,
    firstHeap.trans (wordHeap.trans localHeap)⟩
  simpa only [Source.Immediate.tail, Source.returned, Source.read, cursorIndex, ↓reduceIte, Nat.add_assoc] using run

theorem write (word : CheckedWord program)
    (cursor : Cursor before cell temporary 9 position values)
    (locals : Locals (saved output capacity start low high) frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ elements, output ≠ .array elements)
    (room : position + 5 ≤ values.length) (bounded : position + 5 ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Immediate.write word.source.function.id)
        (.returned (some (.signed .i32 (position + 5 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values position low))) } ∧
      CellEffect (CellSet.union (CellSet.singleton cell) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  obtain ⟨after, run, backing, effect, heap⟩ := tail word cursor locals fresh notArray room bounded
  exact ⟨after, executesSequence
    (executesIfFalse (rex_false program.core (locals.found ⟨7, by simp⟩)) (executesSkip _ _)) run,
    backing, effect, heap⟩

theorem after_size (fits : CheckedFits program) (word : CheckedWord program) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (locals : Locals (saved (.slice i32 cell [] 0 values.length) capacity start low high) frontier before)
    (sizeRead : before.local? 8 = some (.signed .i32 5))
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 5 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Immediate.afterSize fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (start + 5 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 1, read 2, read 8] (fitsValues capacity start 5) before :=
    .cons (local_evaluates program.core (locals.found ⟨1, by simp⟩))
      (.cons (local_evaluates program.core (locals.found ⟨2, by simp⟩))
        (.cons (local_evaluates program.core sizeRead) (.nil _ _)))
  obtain ⟨guarded, fit, guardEffect, guardHeap⟩ := fits_call fits capacity start 5 wellFormed (Int.ofNat_le.mpr bounded) args
  have good : reserved capacity start 5 = true := by simp only [reserved, decide_eq_true_eq]; omega
  rw [good] at fit
  have guard := evaluatesUnary fit (show evalUnaryValue program.core.target .logicalNot (.boolean true) = .ok (.boolean false) from rfl)
  have guardedLocals := locals.empty wellFormed guardEffect
  have guardedBacking := guardEffect.empty_preserves_entry wellFormed backing
  let scope := guarded.bindLocal 9 (.signed .i32 start)
  have scopeWF := bindLocal_preserves_well_formed guarded 9 (.signed .i32 start) guardEffect.wellFormed
  have scopeLocals := guardedLocals.bind guardEffect.wellFormed (id := 9) (by simp) (.signed .i32 start)
  have cursor : Cursor scope cell guarded.nextCell 9 start values := ⟨scopeWF, scopeLocals.found ⟨0, by simp⟩,
    bindLocal_owns_fresh guarded 9 (.signed .i32 start) guardEffect.wellFormed,
    ((bindLocal_effect guarded 9 (.signed .i32 start)).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry guardEffect.wellFormed guardedBacking) (by simp [CellSet.empty])).trans guardedBacking⟩
  obtain ⟨completed, run, contents, effect, heap⟩ := write word cursor scopeLocals
    guardedLocals.frontierBound (by intro elements same; cases same) (by omega) (by omega)
  have closed := CellEffect.closeLocal guarded 9 (.signed .i32 start) guardEffect.wellFormed effect
  have narrow : CellEffect (CellSet.singleton cell) guarded (restoreLocals guarded completed) := by
    apply closed.narrow
    intro changed old member
    rcases member with output | temporary
    · exact output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
  exact ⟨restoreLocals guarded completed,
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesLetLocal (local_evaluates program.core (guardedLocals.found ⟨2, by simp⟩)) run),
    contents, (guardEffect.weaken CellSet.empty_subset).trans narrow,
    guardHeap.trans (HeapFrame.closeLocal guarded 9 (.signed .i32 start) heap)⟩

theorem sized (fits : CheckedFits program) (word : CheckedWord program) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (locals : Locals (saved (.slice i32 cell [] 0 values.length) capacity start low high) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 5 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Immediate.size fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (start + 5 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let scope := before.bindLocal 8 (.signed .i32 5)
  have scopeWF := bindLocal_preserves_well_formed before 8 (.signed .i32 5) wellFormed
  have scopeLocals := locals.bind wellFormed (id := 8) (by simp) (.signed .i32 5)
  have scopeBacking := ((bindLocal_effect before 8 (.signed .i32 5)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, run, contents, effect, heap⟩ := after_size fits word capacity start scopeWF scopeLocals
    (bindLocal_finds_local before 8 (.signed .i32 5) wellFormed) scopeBacking room storage bounded
  have wideRun : Executes program.core scope Source.Immediate.wideSize .next scope :=
    executesIfFalse (wide_false program.core (scopeLocals.found ⟨3, by simp⟩)) (executesSkip _ _)
  have rexRun : Executes program.core scope (countPrefix 8 Source.Immediate.hasRex) .next scope :=
    executesIfFalse (rex_false program.core (scopeLocals.found ⟨7, by simp⟩)) (executesSkip _ _)
  exact ⟨restoreLocals before completed,
    executesLetLocal (show Evaluates program.core before (number 5) (.signed .i32 5) before from ⟨1, rfl⟩)
      (executesSequence wideRun (executesSequence rexRun run)), contents,
    CellEffect.closeLocal before 8 (.signed .i32 5) wellFormed effect,
    HeapFrame.closeLocal before 8 (.signed .i32 5) heap⟩

theorem after_guard (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program)
    (capacity start : Nat) (wellFormed : StateWellFormed before)
    (locals : Locals (inputs (.slice i32 cell [] 0 values.length) capacity start low high) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 5 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before
        (.letLocal 7 i32 (.call rex.source.function.id [read 3, number 0, read 4, .value (.boolean false)])
          (Source.Immediate.size fits.source.function.id word.source.function.id))
        (.returned (some (.signed .i32 (start + 5 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 3, number 0, read 4, .value (.boolean false)]
      (Register.inputValues .w32 0 0 false) before :=
    .cons (local_evaluates program.core (locals.found ⟨3, by simp⟩))
      (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (locals.found ⟨4, by simp⟩))
        (.cons ⟨1, rfl⟩ (.nil _ _))))
  obtain ⟨middle, rexRun, rexEffect, rexHeap⟩ := Register.rex_call rex .w32 0 0 false wellFormed args
  change Evaluates program.core before (.call rex.source.function.id _) (.signed .i32 0) middle at rexRun
  have middleLocals := locals.empty wellFormed rexEffect
  have middleBacking := rexEffect.empty_preserves_entry wellFormed backing
  let scope := middle.bindLocal 7 (.signed .i32 0)
  have scopeWF := bindLocal_preserves_well_formed middle 7 (.signed .i32 0) rexEffect.wellFormed
  have scopeLocals : Locals (saved (.slice i32 cell [] 0 values.length) capacity start low high) scope.nextCell scope :=
    middleLocals.push rexEffect.wellFormed (.signed .i32 0)
  have scopeBacking := ((bindLocal_effect middle 7 (.signed .i32 0)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry rexEffect.wellFormed middleBacking) (by simp [CellSet.empty])).trans middleBacking
  obtain ⟨completed, run, contents, effect, heap⟩ := sized fits word capacity start scopeWF scopeLocals scopeBacking room storage bounded
  exact ⟨restoreLocals middle completed, executesLetLocal rexRun run, contents,
    (rexEffect.weaken CellSet.empty_subset).trans (CellEffect.closeLocal middle 7 (.signed .i32 0) rexEffect.wellFormed effect),
    rexHeap.trans (HeapFrame.closeLocal middle 7 (.signed .i32 0) heap)⟩

theorem guard (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (wellFormed : StateWellFormed before)
    (destination : before.local? 4 = some (.signed .i32 0)) (bits : before.local? 3 = some (.signed .i32 32)) :
    ∃ after, Evaluates program.core before (Source.Immediate.guard valid.source.function.id width.source.function.id)
        (.boolean false) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨first, validRun, validEffect, validHeap⟩ := Register.validation_call valid 0 wellFormed
    (ArgumentsEvaluateTo.cons (local_evaluates program.core destination) (.nil _ _))
  have firstBits := validEffect.empty_preserves_local wellFormed bits
  obtain ⟨second, widthRun, widthEffect, widthHeap⟩ := Register.validation_call width 32 validEffect.wellFormed
    (ArgumentsEvaluateTo.cons (local_evaluates program.core firstBits) (.nil _ _))
  have firstNot := evaluatesUnary validRun
    (show evalUnaryValue program.core.target .logicalNot (.boolean (Register.Validation.register.accepts 0)) = .ok (.boolean false) from rfl)
  have secondNot := evaluatesUnary widthRun
    (show evalUnaryValue program.core.target .logicalNot (.boolean (Register.Validation.width.accepts 32)) = .ok (.boolean false) from rfl)
  exact ⟨second, evaluatesLogicalOrFalse firstNot secondNot, validEffect.trans widthEffect, validHeap.trans widthHeap⟩

/-- The actual complete Lanius immediate emitter, specialized to its literal
compiler inputs: validation, REX, capacity guard, opcode and signed word,
cursor assignment, and lexical scopes. No helper execution is assumed. -/
theorem succeeds32 (checked : Source.Immediate.Checked program valid width rex fits word)
    (capacity start : Nat) (low high : Int) (wellFormed : StateWellFormed before)
    (room : start + 5 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputs (.slice i32 cell [] 0 values.length) capacity start low high) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (start + 5 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 7 =>
    (inputs (.slice i32 cell [] 0 values.length) capacity start low high).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have locals := Locals.ofReads (values := inputs (.slice i32 cell [] 0 values.length) capacity start low high)
    calleeWF (fun index => enterCall_parameterBindings_matches wellFormed index)
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨guarded, guardRun, guardEffect, guardHeap⟩ := guard valid width calleeWF
    (locals.found ⟨4, by simp⟩) (locals.found ⟨3, by simp⟩)
  obtain ⟨completed, run, contents, effect, heap⟩ := after_guard rex fits word capacity start guardEffect.wellFormed
    (locals.empty calleeWF guardEffect) (guardEffect.empty_preserves_entry calleeWF calleeBacking) room storage bounded
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequence (executesIfFalse guardRun (executesSkip _ _)) run)
    ((guardEffect.weaken CellSet.empty_subset).trans effect)
  exact ⟨restoreLocals before completed, called.1, contents, called.2, HeapFrame.closeCall before params (guardHeap.trans heap)⟩

theorem sized_rejects (fits : CheckedFits program) (word : CheckedWord program)
    (output : Value) (capacity start low high : Int) (wellFormed : StateWellFormed before)
    (locals : Locals (saved output capacity start low high) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 5 = false) :
    ∃ after, Executes program.core before (Source.Immediate.size fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let scope := before.bindLocal 8 (.signed .i32 5)
  have scopeWF := bindLocal_preserves_well_formed before 8 (.signed .i32 5) wellFormed
  have scopeLocals := locals.bind wellFormed (id := 8) (by simp) (.signed .i32 5)
  have sizeRead := bindLocal_finds_local before 8 (.signed .i32 5) wellFormed
  have args : ArgumentsEvaluateTo program.core scope [read 1, read 2, read 8] (fitsValues capacity start 5) scope :=
    .cons (local_evaluates program.core (scopeLocals.found ⟨1, by simp⟩))
      (.cons (local_evaluates program.core (scopeLocals.found ⟨2, by simp⟩))
        (.cons (local_evaluates program.core sizeRead) (.nil _ _)))
  obtain ⟨rejected, fit, effect, heap⟩ := fits_call fits capacity start 5 scopeWF bounded args
  rw [bad] at fit
  have reject := evaluatesUnary fit
    (show evalUnaryValue program.core.target .logicalNot (.boolean false) = .ok (.boolean true) from rfl)
  have negative : Evaluates program.core rejected negativeOne (.signed .i32 (-1)) rejected := by
    apply evaluatesUnary (show Evaluates program.core rejected (number 1) (.signed .i32 1) rejected from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  have rejectedRun : Executes program.core scope (Source.Immediate.afterSize fits.source.function.id word.source.function.id)
      (.returned (some (.signed .i32 (-1)))) rejected :=
    executesSequenceReturned (executesIfTrue reject (executesSequenceReturned (executesReturnValue negative)))
  have wideRun : Executes program.core scope Source.Immediate.wideSize .next scope :=
    executesIfFalse (wide_false program.core (scopeLocals.found ⟨3, by simp⟩)) (executesSkip _ _)
  have rexRun : Executes program.core scope (countPrefix 8 Source.Immediate.hasRex) .next scope :=
    executesIfFalse (rex_false program.core (scopeLocals.found ⟨7, by simp⟩)) (executesSkip _ _)
  exact ⟨restoreLocals before rejected,
    executesLetLocal (show Evaluates program.core before (number 5) (.signed .i32 5) before from ⟨1, rfl⟩)
      (executesSequence wideRun (executesSequence rexRun rejectedRun)),
    CellEffect.closeLocal before 8 (.signed .i32 5) wellFormed effect,
    HeapFrame.closeLocal before 8 (.signed .i32 5) heap⟩

theorem after_guard_rejects (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program)
    (output : Value) (capacity start low high : Int) (wellFormed : StateWellFormed before)
    (locals : Locals (inputs output capacity start low high) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 5 = false) :
    ∃ after, Executes program.core before
        (.letLocal 7 i32 (.call rex.source.function.id [read 3, number 0, read 4, .value (.boolean false)])
          (Source.Immediate.size fits.source.function.id word.source.function.id))
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 3, number 0, read 4, .value (.boolean false)]
      (Register.inputValues .w32 0 0 false) before :=
    .cons (local_evaluates program.core (locals.found ⟨3, by simp⟩))
      (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (locals.found ⟨4, by simp⟩))
        (.cons ⟨1, rfl⟩ (.nil _ _))))
  obtain ⟨middle, rexRun, rexEffect, rexHeap⟩ := Register.rex_call rex .w32 0 0 false wellFormed args
  change Evaluates program.core before (.call rex.source.function.id _) (.signed .i32 0) middle at rexRun
  have middleLocals := locals.empty wellFormed rexEffect
  let scope := middle.bindLocal 7 (.signed .i32 0)
  have scopeWF := bindLocal_preserves_well_formed middle 7 (.signed .i32 0) rexEffect.wellFormed
  have scopeLocals : Locals (saved output capacity start low high) scope.nextCell scope :=
    middleLocals.push rexEffect.wellFormed (.signed .i32 0)
  obtain ⟨rejected, run, effect, heap⟩ := sized_rejects fits word output capacity start low high scopeWF scopeLocals bounded bad
  exact ⟨restoreLocals middle rejected, executesLetLocal rexRun run,
    rexEffect.trans (CellEffect.closeLocal middle 7 (.signed .i32 0) rexEffect.wellFormed effect),
    rexHeap.trans (HeapFrame.closeLocal middle 7 (.signed .i32 0) heap)⟩

/-- Insufficient capacity (including negative capacity/cursor) returns -1
without reading or writing output. No output-slice validity premise is needed. -/
theorem rejects_capacity32 (checked : Source.Immediate.Checked program valid width rex fits word)
    (output : Value) (capacity start low high : Int) (wellFormed : StateWellFormed before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 5 = false)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputs output capacity start low high) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 7 => (inputs output capacity start low high).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have locals := Locals.ofReads (values := inputs output capacity start low high)
    calleeWF (fun index => enterCall_parameterBindings_matches wellFormed index)
  obtain ⟨guarded, guardRun, guardEffect, guardHeap⟩ := guard valid width calleeWF
    (locals.found ⟨4, by simp⟩) (locals.found ⟨3, by simp⟩)
  obtain ⟨rejected, run, effect, heap⟩ := after_guard_rejects rex fits word output capacity start low high guardEffect.wellFormed
    (locals.empty calleeWF guardEffect) bounded bad
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequence (executesIfFalse guardRun (executesSkip _ _)) run) (guardEffect.trans effect)
  exact ⟨restoreLocals before rejected, called.1, called.2, HeapFrame.closeCall before params (guardHeap.trans heap)⟩

theorem decodes (low : Int) : Machine.decode (bytes low) = some (.immediate32 0 (BitVec.ofInt 32 low), 5) := by
  have word : Control.displacement? (i32Bytes low) = some (BitVec.ofInt 32 low) := by
    simpa using Control.displacement?_i32Bytes low []
  simp [bytes, Machine.decode, Machine.decodeOpcode, Register.Rex.decode?, word, Machine.extendRegister]

theorem executes (before : Machine.State) (loaded : Machine.CodeAt before.memory before.rip (bytes low)) :
    Machine.Step before (before.immediate32 0 (BitVec.ofInt 32 low) 5) :=
  .decoded _ loaded _ _ (decodes low) rfl

end Lanius.X86.Encode.Immediate
