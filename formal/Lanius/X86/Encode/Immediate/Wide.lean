import Lanius.X86.Encode.Immediate

namespace Lanius.X86.Encode.Immediate.Wide

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def inputs (output : Value) (capacity start low high : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 64,
    .signed .i32 0, .signed .i32 low, .signed .i32 high]
def saved (output : Value) (capacity start low high : Int) : List Value :=
  inputs output capacity start low high ++ [.signed .i32 72]
def tailWritten (values : List Int) (position : Nat) (low high : Int) : List Int :=
  writtenWord (writtenWord (values.set position 184) (position + 1) low) (position + 5) high
def written (values : List Int) (start : Nat) (low high : Int) : List Int :=
  tailWritten (values.set start 72) (start + 1) low high
def bytes (low high : Int) : List UInt8 := [72, 184] ++ i32Bytes low ++ i32Bytes high

@[simp] theorem inputs_length : (inputs output capacity start low high).length = 7 := rfl
@[simp] theorem saved_length : (saved output capacity start low high).length = 8 := rfl
@[simp] theorem written_length : (written values start low high).length = values.length := by
  simp [written, tailWritten]
@[simp] theorem bytes_length : (bytes low high).length = 10 := by simp [bytes, i32Bytes_length]

theorem emission (room : start + 10 ≤ values.length) :
    byteSlice (written values start low high) start 10 = bytes low high := by
  let first := writtenWord ((values.set start 72).set (start + 1) 184) (start + 2) low
  have header : byteSlice first start 6 = [72, 184] ++ i32Bytes low := by
    simpa [first, writtenBytes, Nat.add_assoc] using writtenHeaderWord_byteSlice [72, 184] low (by omega : start + 2 + 4 ≤ values.length)
  have keptPrefix : byteSlice (writtenWord first (start + 6) high) start 6 = byteSlice first start 6 := by
    apply List.ext_getElem?
    intro index
    by_cases bound : index < 6
    · rw [byteSlice_get bound, byteSlice_get bound, writtenWord_frame (Or.inl (by omega))]
    · rw [List.getElem?_eq_none (by simp only [byteSlice, List.length_map, List.length_take]; omega),
        List.getElem?_eq_none (by simp only [byteSlice, List.length_map, List.length_take]; omega)]
  have split (buffer : List Int) : byteSlice buffer start 10 = byteSlice buffer start 6 ++ byteSlice buffer (start + 6) 4 := by
    change byteSlice buffer start (6 + 4) = _
    unfold byteSlice
    rw [List.take_add, List.map_append, List.drop_drop]
  change byteSlice (writtenWord first (start + 6) high) start 10 = _
  rw [split, keptPrefix, header, writtenWord_byteSlice (by simp [first]; omega)]
  rfl

theorem frame (outside : index < start ∨ start + 10 ≤ index) :
    (written values start low high)[index]? = values[index]? := by
  rw [written, tailWritten, writtenWord_frame (by omega), writtenWord_frame (by omega)]
  rw [List.getElem?_set_ne (by omega), List.getElem?_set_ne (by omega)]

private theorem not_array (output : Value) (notArray : ∀ elements, output ≠ .array elements) :
    ∀ index : Fin (saved output capacity start low high).length, ∀ elements,
      (saved output capacity start low high).get index ≠ .array elements := by
  intro ⟨index, bound⟩ elements
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 ∨ index = 6 ∨ index = 7 := by
    change index < 8 at bound
    omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact notArray elements
  all_goals intro same; cases same

private theorem wide_true (program : Program) (found : before.local? 3 = some (.signed .i32 64)) :
    Evaluates program before Source.Immediate.wide (.boolean true) before :=
  evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found) ⟨1, rfl⟩ rfl

private theorem rex_true (program : Program) (found : before.local? 7 = some (.signed .i32 72)) :
    Evaluates program before Source.Immediate.hasRex (.boolean true) before :=
  evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found) ⟨1, rfl⟩ rfl

/-- Execute one real word-helper call and assign its result to the owned
cursor. The helper may write output but cannot overwrite the cursor cell. -/
private theorem word_set (word : CheckedWord program)
    (cursor : Cursor before cell temporary 9 position values)
    (locals : Locals (saved output capacity start low high) frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ elements, output ≠ .array elements) (offset : Nat) (value : Int)
    (readValue : Evaluates program.core before expression (.signed .i32 value) before)
    (room : position + offset + 4 ≤ values.length) (bounded : position + offset + 4 ≤ 2147483647) :
    ∃ after, Evaluates program.core before (.assign .set (.local 9)
        (.call word.source.function.id [read 0, cursorIndex 9 offset, expression])) .unit after ∧
      Cursor after cell temporary 9 (position + offset + 4) (writtenWord values (position + offset) value) ∧
      Locals (saved output capacity start low high) frontier after ∧
      CellEffect (CellSet.union (CellSet.singleton cell) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 0, cursorIndex 9 offset, expression]
      (wordValues (.slice i32 cell [] 0 values.length) (position + offset) value) before :=
    .cons (local_evaluates _ cursor.sliceRead) (.cons (cursor.index _ offset (by omega)) (.cons readValue (.nil _ _)))
  obtain ⟨written, wordRun, contents, wordEffect, wordHeap⟩ := word_call word (position + offset) value
    cursor.wellFormed room (by omega) cursor.backing args
  have owned := wordEffect.preserves_localPointsTo cursor.wellFormed cursor.position cursor.distinct
  obtain ⟨after, run, afterOwned, effect, localEffect, localHeap, _⟩ :=
    evaluatesOwnedLocalSet cursor.position wordRun wordEffect owned
  have writtenLocals := locals.store cursor.wellFormed wordEffect cursor.backing
    (fun index => not_array output notArray index _)
  have afterLocals := writtenLocals.fresh wordEffect.wellFormed localEffect fresh
  have afterContents := localEffect.preserves_entry wordEffect.wellFormed contents (Ne.symm cursor.distinct)
  have writtenSlice := wordEffect.preserves_local_of_distinct_value cursor.wellFormed cursor.sliceRead cursor.backing
    (by intro same; cases same)
  have afterSlice := localEffect.preserves_local_of_distinct_value wordEffect.wellFormed writtenSlice owned.2
    (by intro same; cases same)
  exact ⟨after, run, ⟨localEffect.wellFormed, by simpa only [writtenWord_length] using afterSlice,
    afterOwned, afterContents⟩, afterLocals, effect, wordHeap.trans localHeap⟩

private theorem tail (word : CheckedWord program)
    (cursor : Cursor before cell temporary 9 position values)
    (locals : Locals (saved output capacity start low high) frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ elements, output ≠ .array elements)
    (room : position + 9 ≤ values.length) (bounded : position + 9 ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Immediate.tail word.source.function.id)
        (.returned (some (.signed .i32 (position + 9 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (tailWritten values position low high))) } ∧
      CellEffect (CellSet.union (CellSet.singleton cell) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  obtain ⟨first, opcodeRun, firstCursor, firstLocals, firstEffect, firstHeap⟩ :=
    cursor.store program.core locals (not_array output notArray) 0 184 (by omega) (by omega)
      (Immediate.opcode_value program.core (locals.found ⟨4, by simp⟩))
  obtain ⟨second, lowRun, lowCursor, lowLocals, lowEffect, lowHeap⟩ := word_set word firstCursor firstLocals fresh
    notArray 1 low (local_evaluates _ (firstLocals.found ⟨5, by simp⟩)) (by simp only [List.length_set]; omega) (by omega)
  obtain ⟨after, highRun, highCursor, _, highEffect, highHeap⟩ := word_set word lowCursor lowLocals fresh
    notArray 0 high (local_evaluates _ (lowLocals.found ⟨6, by simp⟩)) (by simp only [writtenWord_length, List.length_set]; omega) (by omega)
  have returned := executesSequenceReturned (second := .skip) (executesReturnValue (local_evaluates program.core highCursor.read))
  have highBody := executesIfTrue (elseBranch := .skip) (wide_true _ (lowLocals.found ⟨3, by simp⟩))
    (executesSequence (executesExpression highRun) (executesSkip _ _))
  refine ⟨after, ?_, ?_, (firstEffect.weaken CellSet.subset_union_left).trans (lowEffect.trans highEffect),
    firstHeap.trans (lowHeap.trans highHeap)⟩
  · simpa only [Source.Immediate.tail, Source.Immediate.highWord, Source.returned, Source.read, cursorIndex,
      Nat.one_ne_zero, ↓reduceIte, Nat.add_zero, Nat.add_assoc] using executesSequence (executesExpression opcodeRun)
        (executesSequence (executesExpression lowRun) (executesSequence highBody returned))
  · simpa [tailWritten, Nat.add_assoc] using highCursor.backing

private theorem write (word : CheckedWord program)
    (cursor : Cursor before cell temporary 9 position values)
    (locals : Locals (saved output capacity start low high) frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ elements, output ≠ .array elements)
    (room : position + 10 ≤ values.length) (bounded : position + 10 ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Immediate.write word.source.function.id)
        (.returned (some (.signed .i32 (position + 10 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values position low high))) } ∧
      CellEffect (CellSet.union (CellSet.singleton cell) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  obtain ⟨prefixed, prefixRun, prefixCursor, prefixLocals, prefixEffect, prefixHeap⟩ := cursor.append program.core
    locals fresh (not_array output notArray) true 72 (by simp; omega) (by simp; omega)
    (rex_true _ (locals.found ⟨7, by simp⟩)) (local_evaluates _ (locals.found ⟨7, by simp⟩))
  obtain ⟨after, run, contents, effect, heap⟩ := tail word prefixCursor prefixLocals fresh notArray
    (by simp only [Bool.toNat_true, writtenBytes_length]; omega) (by simp only [Bool.toNat_true]; omega)
  refine ⟨after, ?_, ?_, prefixEffect.trans effect, prefixHeap.trans heap⟩
  · simpa only [Source.Immediate.write, Bool.toNat_true, Nat.add_assoc] using executesSequence prefixRun run
  · simpa [written, writtenBytes] using contents

private theorem after_size (fits : CheckedFits program) (word : CheckedWord program) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (locals : Locals (saved (.slice i32 cell [] 0 values.length) capacity start low high) frontier before)
    (sizeRead : before.local? 8 = some (.signed .i32 10))
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 10 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Immediate.afterSize fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (start + 10 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low high))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 1, read 2, read 8] (fitsValues capacity start 10) before :=
    .cons (local_evaluates program.core (locals.found ⟨1, by simp⟩))
      (.cons (local_evaluates program.core (locals.found ⟨2, by simp⟩))
        (.cons (local_evaluates program.core sizeRead) (.nil _ _)))
  obtain ⟨guarded, fit, guardEffect, guardHeap⟩ := fits_call fits capacity start 10 wellFormed (Int.ofNat_le.mpr bounded) args
  have good : reserved capacity start 10 = true := by simp only [reserved, decide_eq_true_eq]; omega
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


private theorem select_size (program : Program) (wellFormed : StateWellFormed before)
    (locals : Locals (saved output capacity start low high) frontier before) :
    ∃ after, Executes program (before.bindLocal 8 (.signed .i32 5))
        (.sequence Source.Immediate.wideSize (countPrefix 8 Source.Immediate.hasRex)) .next after ∧
      after.local? 8 = some (.signed .i32 10) ∧ Locals (saved output capacity start low high) frontier after ∧
      CellEffect (CellSet.singleton before.nextCell) (before.bindLocal 8 (.signed .i32 5)) after ∧
      HeapFrame (before.bindLocal 8 (.signed .i32 5)) after := by
  let scope := before.bindLocal 8 (.signed .i32 5)
  have scopeWF := bindLocal_preserves_well_formed before 8 (.signed .i32 5) wellFormed
  have scopeLocals := locals.bind wellFormed (id := 8) (by simp) (.signed .i32 5)
  have owned := bindLocal_owns_fresh before 8 (.signed .i32 5) wellFormed
  have guard := wide_true program (scopeLocals.found ⟨3, by simp⟩)
  have operation : evalAssignValue program.target .add (some (.signed .i32 5)) (.signed .i32 4) = .ok (.signed .i32 9) := by
    simp [evalAssignValue, assignOpBinary?, evalBinaryValue, evalSignedBinary, wrapSigned, signedModulus,
      signedSignBit, SignedIntTy.bits]
  obtain ⟨first, addition, firstOwned, firstEffect, firstHeap⟩ := evaluatesOwnedLocalUpdate scopeWF owned
    (show Evaluates program scope (number 4) (.signed .i32 4) scope from ⟨1, rfl⟩) operation
  have firstLocals := scopeLocals.fresh scopeWF firstEffect locals.frontierBound
  obtain ⟨after, countRun, afterOwned, afterLocals, countEffect, countHeap⟩ := count_prefix (position := 9)
    program firstEffect.wellFormed firstOwned firstLocals locals.frontierBound true (by decide)
    (rex_true program (firstLocals.found ⟨7, by simp⟩))
  exact ⟨after, executesSequence (executesIfTrue guard (executesSequence (executesExpression addition) (executesSkip _ _))) countRun,
    Assertion.localPointsTo_local 8 before.nextCell _ after afterOwned, afterLocals,
    firstEffect.trans countEffect, firstHeap.trans countHeap⟩

private theorem sized (fits : CheckedFits program) (word : CheckedWord program) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (locals : Locals (saved (.slice i32 cell [] 0 values.length) capacity start low high) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 10 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Immediate.size fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (start + 10 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low high))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have scopeWF := bindLocal_preserves_well_formed before 8 (.signed .i32 5) wellFormed
  obtain ⟨counted, countRun, sizeRead, countedLocals, countEffect, countHeap⟩ := select_size program.core wellFormed locals
  have scopeBacking := ((bindLocal_effect before 8 (.signed .i32 5)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have countedBacking := countEffect.preserves_entry scopeWF scopeBacking
    (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry wellFormed backing))
  obtain ⟨completed, run, contents, effect, heap⟩ := after_size fits word capacity start countEffect.wellFormed
    countedLocals sizeRead countedBacking room storage bounded
  have closed := CellEffect.closeLocal before 8 (.signed .i32 5) wellFormed
    ((countEffect.weaken CellSet.subset_union_left).trans (effect.weaken CellSet.subset_union_right))
  have narrow : CellEffect (CellSet.singleton cell) before (restoreLocals before completed) := by
    apply closed.narrow
    intro changed old member
    rcases member with temporary | output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
    · exact output
  exact ⟨restoreLocals before completed, executesLetLocal
    (show Evaluates program.core before (number 5) (.signed .i32 5) before from ⟨1, rfl⟩)
    (executesSequence_continue countRun run), contents, narrow,
    HeapFrame.closeLocal before 8 (.signed .i32 5) (countHeap.trans heap)⟩

private theorem after_guard (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program)
    (capacity start : Nat) (wellFormed : StateWellFormed before)
    (locals : Locals (inputs (.slice i32 cell [] 0 values.length) capacity start low high) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 10 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before
        (.letLocal 7 i32 (.call rex.source.function.id [read 3, number 0, read 4, .value (.boolean false)])
          (Source.Immediate.size fits.source.function.id word.source.function.id))
        (.returned (some (.signed .i32 (start + 10 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low high))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 3, number 0, read 4, .value (.boolean false)]
      (Register.inputValues .w64 0 0 false) before :=
    .cons (local_evaluates program.core (locals.found ⟨3, by simp⟩))
      (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (locals.found ⟨4, by simp⟩))
        (.cons ⟨1, rfl⟩ (.nil _ _))))
  obtain ⟨middle, rexRun, rexEffect, rexHeap⟩ := Register.rex_call rex .w64 0 0 false wellFormed args
  change Evaluates program.core before (.call rex.source.function.id _) (.signed .i32 72) middle at rexRun
  have middleLocals := locals.empty wellFormed rexEffect
  have middleBacking := rexEffect.empty_preserves_entry wellFormed backing
  let scope := middle.bindLocal 7 (.signed .i32 72)
  have scopeWF := bindLocal_preserves_well_formed middle 7 (.signed .i32 72) rexEffect.wellFormed
  have scopeLocals : Locals (saved (.slice i32 cell [] 0 values.length) capacity start low high) scope.nextCell scope :=
    middleLocals.push rexEffect.wellFormed (.signed .i32 72)
  have scopeBacking := ((bindLocal_effect middle 7 (.signed .i32 72)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry rexEffect.wellFormed middleBacking) (by simp [CellSet.empty])).trans middleBacking
  obtain ⟨completed, run, contents, effect, heap⟩ := sized fits word capacity start scopeWF scopeLocals scopeBacking room storage bounded
  exact ⟨restoreLocals middle completed, executesLetLocal rexRun run, contents,
    (rexEffect.weaken CellSet.empty_subset).trans (CellEffect.closeLocal middle 7 (.signed .i32 72) rexEffect.wellFormed effect),
    rexHeap.trans (HeapFrame.closeLocal middle 7 (.signed .i32 72) heap)⟩

private theorem guard (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (wellFormed : StateWellFormed before)
    (destination : before.local? 4 = some (.signed .i32 0)) (bits : before.local? 3 = some (.signed .i32 64)) :
    ∃ after, Evaluates program.core before (Source.Immediate.guard valid.source.function.id width.source.function.id)
        (.boolean false) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨first, validRun, validEffect, validHeap⟩ := Register.validation_call valid 0 wellFormed
    (ArgumentsEvaluateTo.cons (local_evaluates program.core destination) (.nil _ _))
  have firstBits := validEffect.empty_preserves_local wellFormed bits
  obtain ⟨second, widthRun, widthEffect, widthHeap⟩ := Register.validation_call width 64 validEffect.wellFormed
    (ArgumentsEvaluateTo.cons (local_evaluates program.core firstBits) (.nil _ _))
  have firstNot := evaluatesUnary validRun
    (show evalUnaryValue program.core.target .logicalNot (.boolean (Register.Validation.register.accepts 0)) = .ok (.boolean false) from rfl)
  have secondNot := evaluatesUnary widthRun
    (show evalUnaryValue program.core.target .logicalNot (.boolean (Register.Validation.width.accepts 64)) = .ok (.boolean false) from rfl)
  exact ⟨second, evaluatesLogicalOrFalse firstNot secondNot, validEffect.trans widthEffect, validHeap.trans widthHeap⟩

/-- The actual complete Lanius immediate emitter, specialized to its literal
compiler inputs: validation, REX, capacity guard, opcode and signed word,
cursor assignments, and lexical scopes. Both signed transport words are
emitted as their low 32-bit patterns, without range assumptions on low/high. No helper execution is assumed. -/
theorem succeeds64 (checked : Source.Immediate.Checked program valid width rex fits word)
    (capacity start : Nat) (low high : Int) (wellFormed : StateWellFormed before)
    (room : start + 10 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputs (.slice i32 cell [] 0 values.length) capacity start low high) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (start + 10 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low high))) } ∧
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


private theorem sized_rejects (fits : CheckedFits program) (word : CheckedWord program)
    (output : Value) (capacity start low high : Int) (wellFormed : StateWellFormed before)
    (locals : Locals (saved output capacity start low high) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 10 = false) :
    ∃ after, Executes program.core before (Source.Immediate.size fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨counted, countRun, sizeRead, countedLocals, countEffect, countHeap⟩ := select_size program.core wellFormed locals
  have args : ArgumentsEvaluateTo program.core counted [read 1, read 2, read 8] (fitsValues capacity start 10) counted :=
    .cons (local_evaluates _ (countedLocals.found ⟨1, by simp⟩))
      (.cons (local_evaluates _ (countedLocals.found ⟨2, by simp⟩)) (.cons (local_evaluates _ sizeRead) (.nil _ _)))
  obtain ⟨rejected, fit, effect, heap⟩ := fits_call fits capacity start 10 countEffect.wellFormed bounded args
  rw [bad] at fit
  have reject := evaluatesUnary fit
    (show evalUnaryValue program.core.target .logicalNot (.boolean false) = .ok (.boolean true) from rfl)
  have negative : Evaluates program.core rejected negativeOne (.signed .i32 (-1)) rejected := by
    apply evaluatesUnary (show Evaluates program.core rejected (number 1) (.signed .i32 1) rejected from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned_i32_neg_one]
  have rejectedRun : Executes program.core counted (Source.Immediate.afterSize fits.source.function.id word.source.function.id)
      (.returned (some (.signed .i32 (-1)))) rejected :=
    executesSequenceReturned (executesIfTrue reject (executesSequenceReturned (executesReturnValue negative)))
  have closed := CellEffect.closeLocal before 8 (.signed .i32 5) wellFormed
    (countEffect.trans (effect.weaken CellSet.empty_subset))
  have narrow : CellEffect CellSet.empty before (restoreLocals before rejected) :=
    closed.narrow (by intro cell old same; exact False.elim ((Nat.ne_of_lt old) same))
  exact ⟨restoreLocals before rejected,
    executesLetLocal (show Evaluates program.core before (number 5) (.signed .i32 5) before from ⟨1, rfl⟩)
      (executesSequence_continue countRun rejectedRun), narrow,
    HeapFrame.closeLocal before 8 (.signed .i32 5) (countHeap.trans heap)⟩

private theorem after_guard_rejects (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program)
    (output : Value) (capacity start low high : Int) (wellFormed : StateWellFormed before)
    (locals : Locals (inputs output capacity start low high) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 10 = false) :
    ∃ after, Executes program.core before
        (.letLocal 7 i32 (.call rex.source.function.id [read 3, number 0, read 4, .value (.boolean false)])
          (Source.Immediate.size fits.source.function.id word.source.function.id))
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 3, number 0, read 4, .value (.boolean false)]
      (Register.inputValues .w64 0 0 false) before :=
    .cons (local_evaluates program.core (locals.found ⟨3, by simp⟩))
      (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (locals.found ⟨4, by simp⟩))
        (.cons ⟨1, rfl⟩ (.nil _ _))))
  obtain ⟨middle, rexRun, rexEffect, rexHeap⟩ := Register.rex_call rex .w64 0 0 false wellFormed args
  change Evaluates program.core before (.call rex.source.function.id _) (.signed .i32 72) middle at rexRun
  have middleLocals := locals.empty wellFormed rexEffect
  let scope := middle.bindLocal 7 (.signed .i32 72)
  have scopeWF := bindLocal_preserves_well_formed middle 7 (.signed .i32 72) rexEffect.wellFormed
  have scopeLocals : Locals (saved output capacity start low high) scope.nextCell scope :=
    middleLocals.push rexEffect.wellFormed (.signed .i32 72)
  obtain ⟨rejected, run, effect, heap⟩ := sized_rejects fits word output capacity start low high scopeWF scopeLocals bounded bad
  exact ⟨restoreLocals middle rejected, executesLetLocal rexRun run,
    rexEffect.trans (CellEffect.closeLocal middle 7 (.signed .i32 72) rexEffect.wellFormed effect),
    rexHeap.trans (HeapFrame.closeLocal middle 7 (.signed .i32 72) heap)⟩

/-- Insufficient capacity (including negative capacity/cursor) returns -1
without reading or writing output. No output-slice validity premise is needed. -/
theorem rejects_capacity64 (checked : Source.Immediate.Checked program valid width rex fits word)
    (output : Value) (capacity start low high : Int) (wellFormed : StateWellFormed before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 10 = false)
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


end Lanius.X86.Encode.Immediate.Wide
