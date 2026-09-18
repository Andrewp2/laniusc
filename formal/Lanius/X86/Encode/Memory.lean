import Lanius.X86.Source.Memory
import Lanius.X86.Encode.Register
import Lanius.X86.Machine.Encoding

namespace Lanius.X86.Encode.Memory

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer Lanius.X86.Encoding

/-- The shared disp32 memory form. Opcode membership describes its encoding
map; machine semantics are supplied by the public instruction's theorem. -/
structure Config where
  width : Register.Width
  opcode : Opcode
  reg : Fin 16
  base : Fin 16
  displacement : Int
  forceByte : Bool

def Config.rex (config : Config) : Nat := Register.value config.width config.reg config.base config.forceByte
def Config.sib (config : Config) : Bool := decide (config.base.val % 8 = 4)
def Config.modRM (config : Config) : Nat := 128 + config.reg.val % 8 * 8 + config.base.val % 8
def Config.size (config : Config) : Nat :=
  6 + (decide (config.rex ≠ 0)).toNat + config.opcode.extended.toNat + config.sib.toNat
def Config.tailHeader (config : Config) : List Nat := [config.opcode.byte.val, config.modRM] ++ if config.sib then [36] else []
def Config.header (config : Config) : List Nat := Encoding.header config.rex config.opcode ++ config.tailHeader
def Config.bytes (config : Config) : List UInt8 := config.header.map UInt8.ofNat ++ i32Bytes config.displacement
def Config.written (config : Config) (values : List Int) (start : Nat) : List Int :=
  writtenWord (writtenBytes values start config.header) (start + config.size - 4) config.displacement
def Config.arguments (config : Config) (output : Value) (capacity start : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 config.width.bits,
    .signed .i32 config.opcode.packed, .signed .i32 config.reg.val, .signed .i32 config.base.val,
    .signed .i32 config.displacement, .boolean config.forceByte]
def Config.saved (config : Config) (output : Value) (capacity start : Int) : List Value :=
  config.arguments output capacity start ++ [.signed .i32 config.rex]

@[simp] theorem Config.arguments_length (config : Config) : (config.arguments output capacity start).length = 9 := rfl
@[simp] theorem Config.saved_length (config : Config) : (config.saved output capacity start).length = 10 := rfl
@[simp] theorem Config.written_length (config : Config) (values : List Int) :
    (config.written values start).length = values.length := by simp [Config.written]
theorem Config.size_bound (config : Config) : 6 ≤ config.size ∧ config.size ≤ 9 := by
  simp only [Config.size]
  have := Bool.toNat_le (decide (config.rex ≠ 0))
  have := Bool.toNat_le config.opcode.extended
  have := Bool.toNat_le config.sib
  omega
theorem Config.header_size (config : Config) : config.header.length + 4 = config.size := by
  by_cases absent : config.rex = 0 <;> cases escape : config.opcode.extended <;> cases sib : config.sib <;>
    simp [Config.header, Config.tailHeader, Encoding.header, Config.size, absent, escape, sib, Bool.toNat]
theorem Config.saved_not_array (config : Config) (cell : CellId) (length : Nat) (capacity start : Int) :
    ∀ index : Fin (config.saved (.slice i32 cell [] 0 length) capacity start).length,
      ∀ elements, (config.saved (.slice i32 cell [] 0 length) capacity start).get index ≠ .array elements := by
  intro ⟨index, bound⟩ elements
  change index < 10 at bound
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 ∨ index = 6 ∨ index = 7 ∨ index = 8 ∨ index = 9 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> intro same <;> cases same

theorem has_rex (program : Program) (config : Config)
    (found : before.local? 9 = some (.signed .i32 config.rex)) :
    Evaluates program before Source.Memory.hasRex (.boolean (decide (config.rex ≠ 0))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found)
    (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, ↓reduceIte, Except.ok.injEq, Value.boolean.injEq]
  apply Bool.eq_iff_iff.mpr
  simp

theorem has_sib (program : Program) (config : Config)
    (found : before.local? 6 = some (.signed .i32 config.base.val)) :
    Evaluates program before Source.Memory.hasSib (.boolean config.sib) before := by
  have low := evaluatesNatI32Remainder (leftValue := config.base.val) (rightValue := 8)
    (local_evaluates program found)
    (show Evaluates program before (number 8) (.signed .i32 8) before from ⟨1, rfl⟩) (by decide) (by omega)
  apply evaluatesEagerBinary (by decide) (by decide) low
    (show Evaluates program before (number 4) (.signed .i32 4) before from ⟨1, rfl⟩)
  simp [evalBinaryValue, scalarEqual, Config.sib]
  apply Bool.eq_iff_iff.mpr
  simp only [beq_iff_eq, decide_eq_true_eq]
  omega

theorem modrm_byte (program : Program) (config : Config)
    (reg : before.local? 5 = some (.signed .i32 config.reg.val))
    (base : before.local? 6 = some (.signed .i32 config.base.val)) :
    Evaluates program before Source.Memory.modRM (.signed .i32 config.modRM) before := by
  have eight : Evaluates program before (number 8) (.signed .i32 8) before := ⟨1, rfl⟩
  have regLow := evaluatesNatI32Remainder (leftValue := config.reg.val) (rightValue := 8)
    (local_evaluates program reg) eight (by decide) (by omega)
  have baseLow := evaluatesNatI32Remainder (leftValue := config.base.val) (rightValue := 8)
    (local_evaluates program base) eight (by decide) (by omega)
  have scaled := evaluatesNatI32Multiply (leftValue := config.reg.val % 8) (rightValue := 8) regLow eight (by omega)
  have first := evaluatesNatI32Add (leftValue := 128) (rightValue := config.reg.val % 8 * 8)
    (show Evaluates program before (number 128) (.signed .i32 128) before from ⟨1, rfl⟩) scaled (by omega)
  exact evaluatesNatI32Add (leftValue := 128 + config.reg.val % 8 * 8) (rightValue := config.base.val % 8) first baseLow (by omega)

theorem tail (word : CheckedWord program) (config : Config)
    (cursor : Cursor before cell temporary 11 position values)
    (inputs : Locals (config.saved output capacity start) frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ index : Fin (config.saved output capacity start).length,
      ∀ elements, (config.saved output capacity start).get index ≠ .array elements)
    (room : position + 6 + config.sib.toNat ≤ values.length)
    (bounded : position + 6 + config.sib.toNat ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Memory.tail word.source.function.id)
        (.returned (some (.signed .i32 (position + 6 + config.sib.toNat : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (writtenWord (writtenBytes values position config.tailHeader)
          (position + 2 + config.sib.toNat) config.displacement))) } ∧
      CellEffect (CellSet.union (CellSet.singleton cell) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  obtain ⟨first, opcodeRun, firstCursor, firstInputs, firstEffect, firstHeap⟩ :=
    cursor.store program.core inputs notArray 0 config.opcode.byte.val (by omega) (by omega)
      (opcode_byte program.core config.opcode (inputs.found ⟨4, by simp⟩))
  obtain ⟨second, modrmRun, secondCursor, secondInputs, secondEffect, secondHeap⟩ :=
    firstCursor.store program.core firstInputs notArray 1 config.modRM
      (by simp only [List.length_set]; omega) (by omega)
      (modrm_byte program.core config (firstInputs.found ⟨5, by simp⟩) (firstInputs.found ⟨6, by simp⟩))
  obtain ⟨third, advanceRun, thirdCursor, thirdInputs, thirdEffect, thirdHeap⟩ :=
    secondCursor.advance program.core secondInputs fresh 2 (by omega)
  obtain ⟨fourth, sibRun, fourthCursor, fourthInputs, fourthEffect, fourthHeap⟩ :=
    thirdCursor.append program.core thirdInputs fresh notArray config.sib 36
      (by simp only [List.length_set]; omega) (by omega)
      (has_sib program.core config (thirdInputs.found ⟨6, by simp⟩))
      (show Evaluates program.core third (number 36) (.signed .i32 36) third from ⟨1, rfl⟩)
  have args : ArgumentsEvaluateTo program.core fourth [read 0, read 11, read 7]
      (wordValues (.slice i32 cell [] 0
        (writtenBytes ((values.set position config.opcode.byte.val).set (position + 1) config.modRM)
          (position + 2) (if config.sib then [36] else [])).length)
        (position + 2 + config.sib.toNat) config.displacement) fourth :=
    .cons (local_evaluates program.core fourthCursor.sliceRead)
      (.cons (local_evaluates program.core fourthCursor.read)
        (.cons (local_evaluates program.core (fourthInputs.found ⟨7, by simp⟩)) (.nil _ _)))
  obtain ⟨after, wordRun, contents, wordEffect, wordHeap⟩ := word_call word (position + 2 + config.sib.toNat)
    config.displacement fourthCursor.wellFormed (by simp only [writtenBytes_length, List.length_set]; omega)
      (by omega) fourthCursor.backing args
  have next : position + 2 + config.sib.toNat + 4 = position + 6 + config.sib.toNat := by omega
  rw [next] at wordRun
  refine ⟨after, executesSequence (executesExpression opcodeRun)
    (executesSequence (executesExpression modrmRun) (executesSequence (executesExpression advanceRun)
      (executesSequence sibRun (executesSequenceReturned (executesReturnValue wordRun))))), ?_,
    ((((firstEffect.trans secondEffect).weaken CellSet.subset_union_left).trans
      (thirdEffect.weaken CellSet.subset_union_right)).trans fourthEffect).trans
      (wordEffect.weaken CellSet.subset_union_left),
    (((firstHeap.trans secondHeap).trans thirdHeap).trans fourthHeap).trans wordHeap⟩
  simpa [Config.tailHeader, writtenBytes, Nat.add_assoc] using contents

theorem write (word : CheckedWord program) (config : Config)
    (cursor : Cursor before cell temporary 11 position values)
    (inputs : Locals (config.saved output capacity start) frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ index : Fin (config.saved output capacity start).length,
      ∀ elements, (config.saved output capacity start).get index ≠ .array elements)
    (room : position + config.size ≤ values.length) (bounded : position + config.size ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Memory.write word.source.function.id)
        (.returned (some (.signed .i32 (position + config.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (config.written values position))) } ∧
      CellEffect (CellSet.union (CellSet.singleton cell) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  have size : config.size = 6 + (decide (config.rex ≠ 0)).toNat + config.opcode.extended.toNat + config.sib.toNat := rfl
  obtain ⟨first, rexRun, firstCursor, firstInputs, firstEffect, firstHeap⟩ :=
    cursor.append program.core inputs fresh notArray (decide (config.rex ≠ 0)) config.rex
      (by omega) (by omega) (has_rex program.core config (inputs.found ⟨9, by simp⟩))
      (local_evaluates program.core (inputs.found ⟨9, by simp⟩))
  obtain ⟨second, escapeRun, secondCursor, secondInputs, secondEffect, secondHeap⟩ :=
    firstCursor.append program.core firstInputs fresh notArray config.opcode.extended 15
      (by simp only [writtenBytes_length]; omega) (by omega)
      (has_escape program.core config.opcode (firstInputs.found ⟨4, by simp⟩))
      (show Evaluates program.core first (number 15) (.signed .i32 15) first from ⟨1, rfl⟩)
  obtain ⟨after, tailRun, contents, tailEffect, tailHeap⟩ := tail word config secondCursor secondInputs fresh notArray
    (by simp only [writtenBytes_length]; omega) (by omega)
  have next : position + (decide (config.rex ≠ 0)).toNat + config.opcode.extended.toNat + 6 + config.sib.toNat = position + config.size := by omega
  rw [next] at tailRun
  refine ⟨after, executesSequence rexRun (executesSequence escapeRun tailRun), ?_,
    (firstEffect.trans secondEffect).trans tailEffect, (firstHeap.trans secondHeap).trans tailHeap⟩
  by_cases absent : config.rex = 0 <;> cases escape : config.opcode.extended <;> cases sib : config.sib <;>
    simpa [Config.written, Config.header, Config.tailHeader, Encoding.header, Config.size,
      absent, escape, sib, Bool.toNat, writtenBytes, Nat.add_assoc] using contents

theorem after_size (fits : CheckedFits program) (word : CheckedWord program) (config : Config) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (sizeRead : before.local? 10 = some (.signed .i32 config.size))
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + config.size ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Memory.afterSize fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (start + config.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (config.written values start))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 1, read 2, read 10]
      (fitsValues capacity start config.size) before :=
    .cons (local_evaluates program.core (inputs.found ⟨1, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨2, by simp⟩))
        (.cons (local_evaluates program.core sizeRead) (.nil _ _)))
  obtain ⟨guarded, fit, guardEffect, guardHeap⟩ := fits_call fits capacity start config.size wellFormed (Int.ofNat_le.mpr bounded) args
  have good : reserved capacity start config.size = true := by simp only [reserved, decide_eq_true_eq]; omega
  rw [good] at fit
  have guard := evaluatesUnary fit (show evalUnaryValue program.core.target .logicalNot (.boolean true) = .ok (.boolean false) from rfl)
  have guardedInputs := inputs.empty wellFormed guardEffect
  have guardedBacking := guardEffect.empty_preserves_entry wellFormed backing
  let scope := guarded.bindLocal 11 (.signed .i32 start)
  have scopeWF := bindLocal_preserves_well_formed guarded 11 (.signed .i32 start) guardEffect.wellFormed
  have scopeInputs := guardedInputs.bind guardEffect.wellFormed (id := 11) (by simp) (.signed .i32 start)
  have cursor : Cursor scope cell guarded.nextCell 11 start values := ⟨scopeWF, scopeInputs.found ⟨0, by simp⟩,
    bindLocal_owns_fresh guarded 11 (.signed .i32 start) guardEffect.wellFormed,
    ((bindLocal_effect guarded 11 (.signed .i32 start)).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry guardEffect.wellFormed guardedBacking) (by simp [CellSet.empty])).trans guardedBacking⟩
  obtain ⟨written, writeRun, contents, writeEffect, writeHeap⟩ := write word config cursor scopeInputs
    guardedInputs.frontierBound (config.saved_not_array cell values.length capacity start) (by omega) (by omega)
  have closed := CellEffect.closeLocal guarded 11 (.signed .i32 start) guardEffect.wellFormed writeEffect
  have narrow : CellEffect (CellSet.singleton cell) guarded (restoreLocals guarded written) := by
    apply closed.narrow
    intro changed old member
    rcases member with output | temporary
    · exact output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
  exact ⟨restoreLocals guarded written,
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesLetLocal (local_evaluates program.core (guardedInputs.found ⟨2, by simp⟩)) writeRun),
    contents, (guardEffect.weaken CellSet.empty_subset).trans narrow,
    guardHeap.trans (HeapFrame.closeLocal guarded 11 (.signed .i32 start) writeHeap)⟩

theorem select_size (program : Program) (config : Config) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved output capacity start) frontier before) :
    ∃ after, Executes program (before.bindLocal 10 (.signed .i32 6))
        (.sequence (countPrefix 10 Source.Memory.hasRex)
          (.sequence (countPrefix 10 hasEscape) (countPrefix 10 Source.Memory.hasSib))) .next after ∧
      after.local? 10 = some (.signed .i32 config.size) ∧
      Locals (config.saved output capacity start) frontier after ∧
      CellEffect (CellSet.singleton before.nextCell) (before.bindLocal 10 (.signed .i32 6)) after ∧
      HeapFrame (before.bindLocal 10 (.signed .i32 6)) after := by
  have scopeWF := bindLocal_preserves_well_formed before 10 (.signed .i32 6) wellFormed
  have scopeInputs := inputs.bind wellFormed (id := 10) (by simp) (.signed .i32 6)
  have size : config.size = 6 + (decide (config.rex ≠ 0)).toNat + config.opcode.extended.toNat + config.sib.toNat := rfl
  have small := config.size_bound
  obtain ⟨first, rexRun, rexOwned, firstInputs, firstEffect, firstHeap⟩ := count_prefix (position := 6) program scopeWF
    (bindLocal_owns_fresh before 10 (.signed .i32 6) wellFormed) scopeInputs inputs.frontierBound
    (decide (config.rex ≠ 0)) (by omega) (has_rex program config (scopeInputs.found ⟨9, by simp⟩))
  obtain ⟨second, escapeRun, escapeOwned, secondInputs, secondEffect, secondHeap⟩ := count_prefix
    (position := 6 + (decide (config.rex ≠ 0)).toNat) program firstEffect.wellFormed rexOwned firstInputs inputs.frontierBound
    config.opcode.extended (by omega) (has_escape program config.opcode (firstInputs.found ⟨4, by simp⟩))
  obtain ⟨third, sibRun, sibOwned, thirdInputs, thirdEffect, thirdHeap⟩ := count_prefix
    (position := 6 + (decide (config.rex ≠ 0)).toNat + config.opcode.extended.toNat) program secondEffect.wellFormed
    escapeOwned secondInputs inputs.frontierBound config.sib (by omega) (has_sib program config (secondInputs.found ⟨6, by simp⟩))
  exact ⟨third, executesSequence rexRun (executesSequence escapeRun sibRun),
    Assertion.localPointsTo_local 10 before.nextCell _ third sibOwned, thirdInputs,
    (firstEffect.trans secondEffect).trans thirdEffect, (firstHeap.trans secondHeap).trans thirdHeap⟩

theorem sized (fits : CheckedFits program) (word : CheckedWord program) (config : Config) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + config.size ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Memory.size fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (start + config.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (config.written values start))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have scopeWF := bindLocal_preserves_well_formed before 10 (.signed .i32 6) wellFormed
  obtain ⟨selected, sizeRun, sizeRead, selectedInputs, sizeEffect, sizeHeap⟩ := select_size program.core config wellFormed inputs
  have scopeBacking := ((bindLocal_effect before 10 (.signed .i32 6)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have selectedBacking := sizeEffect.preserves_entry scopeWF scopeBacking
    (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry wellFormed backing))
  obtain ⟨written, writeRun, contents, writeEffect, writeHeap⟩ := after_size fits word config capacity start
    sizeEffect.wellFormed selectedInputs sizeRead selectedBacking room storage bounded
  obtain ⟨first, firstRun, restRun⟩ := executesSequenceNext_inv sizeRun
  have body := executesLetLocal (id := 10) (type := i32)
    (show Evaluates program.core before (number 6) (.signed .i32 6) before from ⟨1, rfl⟩)
    (executesSequence firstRun (executesSequence_continue restRun writeRun))
  have closed := CellEffect.closeLocal before 10 (.signed .i32 6) wellFormed
    ((sizeEffect.weaken CellSet.subset_union_left).trans (writeEffect.weaken CellSet.subset_union_right))
  have narrow : CellEffect (CellSet.singleton cell) before (restoreLocals before written) := by
    apply closed.narrow
    intro changed old member
    rcases member with temporary | output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
    · exact output
  exact ⟨restoreLocals before written, body, contents, narrow,
    HeapFrame.closeLocal before 10 (.signed .i32 6) (sizeHeap.trans writeHeap)⟩

theorem after_guard (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program)
    (config : Config) (capacity start : Nat) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + config.size ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before
        (.letLocal 9 i32 (.call rex.source.function.id [read 3, read 5, read 6, read 8])
          (Source.Memory.size fits.source.function.id word.source.function.id))
        (.returned (some (.signed .i32 (start + config.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (config.written values start))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 3, read 5, read 6, read 8]
      (Register.inputValues config.width config.reg config.base config.forceByte) before :=
    .cons (local_evaluates program.core (inputs.found ⟨3, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨5, by simp⟩))
        (.cons (local_evaluates program.core (inputs.found ⟨6, by simp⟩))
          (.cons (local_evaluates program.core (inputs.found ⟨8, by simp⟩)) (.nil _ _))))
  obtain ⟨middle, rexRun, rexEffect, rexHeap⟩ := Register.rex_call rex config.width config.reg config.base config.forceByte wellFormed args
  have middleInputs := inputs.empty wellFormed rexEffect
  have middleBacking := rexEffect.empty_preserves_entry wellFormed backing
  let scope := middle.bindLocal 9 (.signed .i32 config.rex)
  have scopeWF := bindLocal_preserves_well_formed middle 9 (.signed .i32 config.rex) rexEffect.wellFormed
  have scopeInputs : Locals (config.saved (.slice i32 cell [] 0 values.length) capacity start) scope.nextCell scope :=
    middleInputs.push rexEffect.wellFormed (.signed .i32 config.rex)
  have scopeBacking := ((bindLocal_effect middle 9 (.signed .i32 config.rex)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry rexEffect.wellFormed middleBacking) (by simp [CellSet.empty])).trans middleBacking
  obtain ⟨written, sizeRun, contents, sizeEffect, sizeHeap⟩ := sized fits word config capacity start scopeWF scopeInputs scopeBacking room storage bounded
  exact ⟨restoreLocals middle written, executesLetLocal rexRun sizeRun, contents,
    (rexEffect.weaken CellSet.empty_subset).trans (CellEffect.closeLocal middle 9 (.signed .i32 config.rex) rexEffect.wellFormed sizeEffect),
    rexHeap.trans (HeapFrame.closeLocal middle 9 (.signed .i32 config.rex) sizeHeap)⟩

/-- Complete source-linked success: register/width guards, REX, size,
reservation, prefix/SIB stores, signed disp32, and all three local scopes. -/
theorem succeeds (checked : Source.Memory.Checked program valid width rex fits word) (config : Config)
    (capacity start : Nat) (wellFormed : StateWellFormed before)
    (room : start + config.size ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (config.arguments (.slice i32 cell [] 0 values.length) capacity start) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (start + config.size : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (config.written values start))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 9 =>
    (config.arguments (.slice i32 cell [] 0 values.length) capacity start).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := config.arguments (.slice i32 cell [] 0 values.length) capacity start)
    calleeWF (fun index => enterCall_parameterBindings_matches wellFormed index)
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨guarded, guardRun, guardEffect, guardHeap⟩ := register_guard valid width config.width config.reg config.base calleeWF
    (inputs.found ⟨5, by simp⟩) (inputs.found ⟨6, by simp⟩) (inputs.found ⟨3, by simp⟩)
  obtain ⟨completed, bodyRun, contents, bodyEffect, bodyHeap⟩ := after_guard rex fits word config capacity start
    guardEffect.wellFormed (inputs.empty calleeWF guardEffect)
    (guardEffect.empty_preserves_entry calleeWF calleeBacking) room storage bounded
  have effect := (guardEffect.weaken CellSet.empty_subset).trans bodyEffect
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequence (executesIfFalse guardRun (executesSkip _ _)) bodyRun) effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2,
    HeapFrame.closeCall before params (guardHeap.trans bodyHeap)⟩

theorem sized_rejects (fits : CheckedFits program) (word : CheckedWord program) (config : Config)
    (output : Value) (capacity start : Int) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved output capacity start) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start config.size = false) :
    ∃ after, Executes program.core before (Source.Memory.size fits.source.function.id word.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨selected, sizeRun, sizeRead, selectedInputs, sizeEffect, sizeHeap⟩ := select_size program.core config wellFormed inputs
  have args : ArgumentsEvaluateTo program.core selected [read 1, read 2, read 10]
      (fitsValues capacity start config.size) selected :=
    .cons (local_evaluates program.core (selectedInputs.found ⟨1, by simp⟩))
      (.cons (local_evaluates program.core (selectedInputs.found ⟨2, by simp⟩))
        (.cons (local_evaluates program.core sizeRead) (.nil _ _)))
  obtain ⟨rejected, fit, guardEffect, guardHeap⟩ := fits_call fits capacity start config.size sizeEffect.wellFormed bounded args
  rw [bad] at fit
  have guard := evaluatesUnary fit (show evalUnaryValue program.core.target .logicalNot (.boolean false) = .ok (.boolean true) from rfl)
  have negative : Evaluates program.core rejected negativeOne (.signed .i32 (-1)) rejected := by
    apply evaluatesUnary (show Evaluates program.core rejected (number 1) (.signed .i32 1) rejected from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  have rejectedRun : Executes program.core selected (Source.Memory.afterSize fits.source.function.id word.source.function.id)
      (.returned (some (.signed .i32 (-1)))) rejected :=
    executesSequenceReturned (executesIfTrue guard (executesSequenceReturned (executesReturnValue negative)))
  obtain ⟨first, firstRun, restRun⟩ := executesSequenceNext_inv sizeRun
  have body := executesLetLocal (id := 10) (type := i32)
    (show Evaluates program.core before (number 6) (.signed .i32 6) before from ⟨1, rfl⟩)
    (executesSequence firstRun (executesSequence_continue restRun rejectedRun))
  have closed := CellEffect.closeLocal before 10 (.signed .i32 6) wellFormed
    (sizeEffect.trans (guardEffect.weaken CellSet.empty_subset))
  have narrow : CellEffect CellSet.empty before (restoreLocals before rejected) := by
    apply closed.narrow
    intro changed old member
    exact False.elim ((Nat.ne_of_lt old) member)
  exact ⟨restoreLocals before rejected, body, narrow,
    HeapFrame.closeLocal before 10 (.signed .i32 6) (sizeHeap.trans guardHeap)⟩

theorem after_guard_rejects (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program)
    (config : Config) (output : Value) (capacity start : Int) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments output capacity start) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start config.size = false) :
    ∃ after, Executes program.core before
        (.letLocal 9 i32 (.call rex.source.function.id [read 3, read 5, read 6, read 8])
          (Source.Memory.size fits.source.function.id word.source.function.id))
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 3, read 5, read 6, read 8]
      (Register.inputValues config.width config.reg config.base config.forceByte) before :=
    .cons (local_evaluates program.core (inputs.found ⟨3, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨5, by simp⟩))
        (.cons (local_evaluates program.core (inputs.found ⟨6, by simp⟩))
          (.cons (local_evaluates program.core (inputs.found ⟨8, by simp⟩)) (.nil _ _))))
  obtain ⟨middle, rexRun, rexEffect, rexHeap⟩ := Register.rex_call rex config.width config.reg config.base config.forceByte wellFormed args
  have middleInputs := inputs.empty wellFormed rexEffect
  let scope := middle.bindLocal 9 (.signed .i32 config.rex)
  have scopeWF := bindLocal_preserves_well_formed middle 9 (.signed .i32 config.rex) rexEffect.wellFormed
  have scopeInputs : Locals (config.saved output capacity start) scope.nextCell scope :=
    middleInputs.push rexEffect.wellFormed (.signed .i32 config.rex)
  obtain ⟨rejected, run, effect, heap⟩ := sized_rejects fits word config output capacity start scopeWF scopeInputs bounded bad
  exact ⟨restoreLocals middle rejected, executesLetLocal rexRun run,
    rexEffect.trans (CellEffect.closeLocal middle 9 (.signed .i32 config.rex) rexEffect.wellFormed effect),
    rexHeap.trans (HeapFrame.closeLocal middle 9 (.signed .i32 config.rex) heap)⟩

/-- The complete memory-form emitter rejects insufficient capacity before
any output access, preserving all existing caller cells and host state. -/
theorem rejects_capacity (checked : Source.Memory.Checked program valid width rex fits word) (config : Config)
    (output : Value) (capacity start : Int) (wellFormed : StateWellFormed before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start config.size = false)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (config.arguments output capacity start) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 9 => (config.arguments output capacity start).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := config.arguments output capacity start)
    calleeWF (fun index => enterCall_parameterBindings_matches wellFormed index)
  obtain ⟨guarded, guardRun, guardEffect, guardHeap⟩ := register_guard valid width config.width config.reg config.base calleeWF
    (inputs.found ⟨5, by simp⟩) (inputs.found ⟨6, by simp⟩) (inputs.found ⟨3, by simp⟩)
  obtain ⟨rejected, run, effect, heap⟩ := after_guard_rejects rex fits word config output capacity start
    guardEffect.wellFormed (inputs.empty calleeWF guardEffect) bounded bad
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequence (executesIfFalse guardRun (executesSkip _ _)) run) (guardEffect.trans effect)
  exact ⟨restoreLocals before rejected, called.1, called.2, HeapFrame.closeCall before params (guardHeap.trans heap)⟩

theorem Config.emission (config : Config) (room : start + config.size ≤ values.length) :
    byteSlice (config.written values start) start config.size = config.bytes := by
  have headerSize := config.header_size
  have field : start + config.size - 4 = start + config.header.length := by omega
  rw [Config.written, field, ← headerSize]
  exact writtenHeaderWord_byteSlice config.header config.displacement (by omega)

theorem Config.frame (config : Config) {index start : Nat} {values : List Int}
    (outside : index < start ∨ start + config.size ≤ index) :
    (config.written values start)[index]? = values[index]? := by
  have size := config.size_bound
  have headerSize := config.header_size
  rw [Config.written, writtenWord_frame (by omega), writtenBytes_frame (by omega)]

def moveConfig (width : Register.Width) (load : Bool) (reg base : Fin 16) (displacement : Int) : Config :=
  ⟨width, .primary ⟨if load then 139 else 137, by cases load <;> decide⟩, reg, base, displacement, false⟩
def moveValues (output : Value) (capacity start : Int) (width : Register.Width) (reg base : Fin 16) (displacement : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 width.bits,
    .signed .i32 reg.val, .signed .i32 base.val, .signed .i32 displacement]

theorem move_encoding (width : Register.Width) (load : Bool) (reg base : Fin 16) (displacement : Int) :
    (moveConfig width load reg base displacement).bytes = Machine.memoryBytes width load reg base displacement ∧
    (moveConfig width load reg base displacement).size = (Machine.memoryBytes width load reg base displacement).length := by
  have exactBytes : (moveConfig width load reg base displacement).bytes = Machine.memoryBytes width load reg base displacement := by
    cases load <;> by_cases absent : Register.value width reg base false = 0 <;>
      by_cases sib : base.val % 8 = 4 <;>
      simp [Config.bytes, Config.header, Config.tailHeader, Config.rex, Config.modRM, Config.sib,
        Encoding.header, Opcode.extended, Opcode.byte, moveConfig, Machine.memoryBytes, Machine.memoryHeader,
        absent, sib]
    all_goals rfl
  refine ⟨exactBytes, ?_⟩
  have headerSize := (moveConfig width load reg base displacement).header_size
  rw [← exactBytes]
  simpa only [Config.bytes, List.length_append, List.length_map, i32Bytes_length] using headerSize.symm

theorem move_arguments (program : Program) (load : Bool)
    (locals : ∀ index : Fin 7, before.local? index.val =
      some ((moveValues output capacity start width reg base displacement).get index)) :
    ArgumentsEvaluateTo program before (Source.Memory.moveArguments load)
      ((moveConfig width load reg base displacement).arguments output capacity start) before := by
  cases load <;>
    simp only [Source.Memory.moveArguments, moveConfig, Config.arguments, Opcode.packed, Opcode.extended, Opcode.byte, Bool.false_eq_true, ↓reduceIte] <;>
    (repeat' apply ArgumentsEvaluateTo.cons (afterHead := before)) <;>
    first
    | exact .nil _ _
    | exact local_evaluates program (locals ⟨0, by decide⟩)
    | exact local_evaluates program (locals ⟨1, by decide⟩)
    | exact local_evaluates program (locals ⟨2, by decide⟩)
    | exact local_evaluates program (locals ⟨3, by decide⟩)
    | exact local_evaluates program (locals ⟨4, by decide⟩)
    | exact local_evaluates program (locals ⟨5, by decide⟩)
    | exact local_evaluates program (locals ⟨6, by decide⟩)
    | exact ⟨1, rfl⟩

/-- Public Lanius load/store emission gives the existing decoded MOV step.
The memory mapping is explicit; no assumed emitter result or output validator
is needed. This covers all register/base choices, widths, and signed disp32. -/
theorem move_emits (checked : Source.Memory.CheckedMove program form load) (width : Register.Width)
    (reg base : Fin 16) (displacement : Int) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (room : start + (Machine.memoryBytes width load reg base displacement).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (moveValues (.slice i32 cell [] 0 values.length) capacity start width reg base displacement) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (start + (Machine.memoryBytes width load reg base displacement).length : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values emitted)) } ∧
      byteSlice emitted start (Machine.memoryBytes width load reg base displacement).length = Machine.memoryBytes width load reg base displacement ∧
      (∀ machine, Machine.CodeAt machine.memory machine.rip
        (byteSlice emitted start (Machine.memoryBytes width load reg base displacement).length) →
        Machine.Step machine (Machine.execute (Machine.memoryInstruction width load reg base (BitVec.ofInt 32 displacement))
          (Machine.memoryBytes width load reg base displacement).length machine)) ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (Machine.memoryBytes width load reg base displacement).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let config := moveConfig width load reg base displacement
  let params := parameterBindings (fun index : Fin 7 =>
    (moveValues (.slice i32 cell [] 0 values.length) capacity start width reg base displacement).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have locals (index : Fin 7) : callee.local? index.val = some
      ((moveValues (.slice i32 cell [] 0 values.length) capacity start width reg base displacement).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have args := move_arguments program.core load locals
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have encoding := move_encoding width load reg base displacement
  obtain ⟨completed, run, contents, effect, heap⟩ := succeeds form config capacity start calleeWF
    (by simpa only [config, encoding.2] using room) storage bounded calleeBacking args
  have bytes : byteSlice (config.written values start) start
      (Machine.memoryBytes width load reg base displacement).length = Machine.memoryBytes width load reg base displacement := by
    rw [← encoding.2, config.emission (by simpa only [config, encoding.2] using Nat.le_trans room storage)]
    exact encoding.1
  rw [show config.size = (Machine.memoryBytes width load reg base displacement).length from encoding.2] at run
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequenceReturned (executesReturnValue run)) effect
  refine ⟨restoreLocals before completed, config.written values start, called.1, contents, bytes, ?_,
    config.written_length values, ?_, called.2, HeapFrame.closeCall before params heap⟩
  · intro machine loaded
    rw [bytes] at loaded
    exact .decoded _ loaded _ _ (by simpa only [List.append_nil] using Machine.memory_decodes width load reg base displacement []) rfl
  · intro index outside
    exact config.frame (by simpa only [config, encoding.2] using outside)

theorem move_rejects_capacity (checked : Source.Memory.CheckedMove program form load) (width : Register.Width)
    (reg base : Fin 16) (displacement : Int) (output : Value) (capacity start : Int)
    (wellFormed : StateWellFormed before) (bounded : capacity ≤ 2147483647)
    (bad : reserved capacity start (Machine.memoryBytes width load reg base displacement).length = false)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (moveValues output capacity start width reg base displacement) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let config := moveConfig width load reg base displacement
  let params := parameterBindings (fun index : Fin 7 =>
    (moveValues output capacity start width reg base displacement).get index)
  let callee := enterCall before params
  have locals (index : Fin 7) : callee.local? index.val = some
      ((moveValues output capacity start width reg base displacement).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have args := move_arguments program.core load locals
  obtain ⟨rejected, run, effect, heap⟩ := rejects_capacity form config output capacity start
    (enterCall_preserves_wellFormed wellFormed) bounded
    (by simpa only [config, (move_encoding width load reg base displacement).2] using bad) args
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequenceReturned (executesReturnValue run)) effect
  exact ⟨restoreLocals before rejected, called.1, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Encode.Memory
