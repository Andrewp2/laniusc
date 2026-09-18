import Lanius.X86.Buffer.Cursor
import Lanius.X86.Register.Execution
import Lanius.X86.Encoding
import Lanius.Extraction.Input.Unpacking
import Lanius.Semantics.Sequence

namespace Lanius.X86.Encode

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core
open Lanius.X86.Source Lanius.X86.Buffer Lanius.X86.Encoding

structure Config where
  width : Register.Width
  opcode : Opcode
  reg : Fin 16
  rm : Fin 16
  forceByte : Bool

def Config.rex (config : Config) : Nat := Register.value config.width config.reg config.rm config.forceByte
def Config.size (config : Config) : Nat := Encoding.size config.rex config.opcode
def Config.bytes (config : Config) : List Nat := Encoding.bytes config.rex config.opcode config.reg config.rm

def rawArguments (output : Value) (capacity cursor width opcode reg rm : Int) (forceByte : Bool) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 cursor, .signed .i32 width,
    .signed .i32 opcode, .signed .i32 reg, .signed .i32 rm, .boolean forceByte]

@[simp] theorem rawArguments_length : (rawArguments output capacity cursor width opcode reg rm forceByte).length = 8 := rfl

def Config.arguments (config : Config) (output : Value) (capacity cursor : Int) : List Value :=
  rawArguments output capacity cursor config.width.bits config.opcode.packed config.reg.val config.rm.val config.forceByte

def Config.saved (config : Config) (output : Value) (capacity cursor : Int) : List Value :=
  config.arguments output capacity cursor ++ [.signed .i32 config.rex]

@[simp] theorem Config.arguments_length (config : Config) (output : Value) (capacity cursor : Int) :
    (config.arguments output capacity cursor).length = 8 := rfl

@[simp] theorem Config.saved_length (config : Config) (output : Value) (capacity cursor : Int) :
    (config.saved output capacity cursor).length = 9 := rfl

theorem Config.prefix_size (config : Config) :
    (decide (config.rex ≠ 0)).toNat + config.opcode.extended.toNat + 2 = config.size := by
  by_cases absent : config.rex = 0 <;> simp [Config.size, Encoding.size, absent, Bool.toNat] <;> omega

theorem Config.bytes_are_bytes (config : Config) : ∀ byte ∈ config.bytes, byte < 256 := by
  apply Encoding.bytes_are_bytes
  have bound := Register.value_bounds config.width config.reg config.rm config.forceByte
  change config.rex = 0 ∨ (64 ≤ config.rex ∧ config.rex < 80) at bound
  omega

structure Config.Emission (config : Config) (original : List Int) (start : Nat) (emitted : List Int) : Prop where
  length : emitted.length = original.length
  bytes : byteSlice emitted start config.size = config.bytes.map UInt8.ofNat
  frame : ∀ index, index < start ∨ start + config.size ≤ index → emitted[index]? = original[index]?

theorem Config.emission (config : Config) (room : start + config.size ≤ values.length) :
    config.Emission values start (writtenBytes values start config.bytes) := by
  have size : config.bytes.length = config.size := Encoding.bytes_size _ _ _ _
  refine ⟨writtenBytes_length, ?_, fun index outside => writtenBytes_frame (by omega)⟩
  rw [← size]
  exact writtenBytes_byteSlice (by omega)

theorem Config.saved_not_array (config : Config) (cell : CellId) (length : Nat) (capacity cursor : Int) :
    ∀ index : Fin (config.saved (.slice i32 cell [] 0 length) capacity cursor).length,
      ∀ elements, (config.saved (.slice i32 cell [] 0 length) capacity cursor).get index ≠ .array elements := by
  intro ⟨index, bound⟩ elements
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 ∨ index = 6 ∨ index = 7 ∨ index = 8 := by
    change index < 9 at bound
    omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> intro same <;> cases same

theorem has_rex (program : Program) (rex : Nat) (found : before.local? 8 = some (.signed .i32 rex)) :
    Evaluates program before hasRex (.boolean (decide (rex ≠ 0))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found)
    (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, ↓reduceIte, Except.ok.injEq, Value.boolean.injEq]
  apply Bool.eq_iff_iff.mpr
  simp

theorem has_escape (program : Program) (opcode : Opcode)
    (found : before.local? 4 = some (.signed .i32 opcode.packed)) :
    Evaluates program before hasEscape (.boolean opcode.extended) before := by
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found)
    (show Evaluates program before (number 255) (.signed .i32 255) before from ⟨1, rfl⟩)
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, ↓reduceIte]
  have equivalent : decide ((255 : Int) < opcode.packed) = decide (255 < opcode.packed) := by
    apply Bool.eq_iff_iff.mpr
    simp only [decide_eq_true_eq]
    omega
  rw [equivalent, opcode.packed_extended]

theorem opcode_byte (program : Program) (opcode : Opcode)
    (found : before.local? 4 = some (.signed .i32 opcode.packed)) :
    Evaluates program before (.binary .bitAnd (read 4) (number 255)) (.signed .i32 opcode.byte.val) before := by
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found)
    (show Evaluates program before (number 255) (.signed .i32 255) before from ⟨1, rfl⟩)
  have bound := opcode.packed_bounds
  have mask := Extraction.Input.mask_low_byte program.target opcode.packed
  rw [wrapSigned_i32_of_nonnegative program.target opcode.packed (by omega) (by omega)] at mask
  have modulo : (opcode.packed : Int) % 256 = (opcode.byte.val : Int) := by
    have := opcode.packed_byte
    omega
  simpa only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, modulo] using mask

theorem modrm_byte (program : Program) (reg rm : Fin 16)
    (regRead : before.local? 5 = some (.signed .i32 reg.val))
    (rmRead : before.local? 6 = some (.signed .i32 rm.val)) :
    Evaluates program before registerModRM (.signed .i32 (modRM reg rm)) before := by
  have eight : Evaluates program before (number 8) (.signed .i32 8) before := ⟨1, rfl⟩
  have regLow := evaluatesNatI32Remainder (leftValue := reg.val) (rightValue := 8)
    (local_evaluates program regRead) eight (by decide) (by omega)
  have rmLow := evaluatesNatI32Remainder (leftValue := rm.val) (rightValue := 8)
    (local_evaluates program rmRead) eight (by decide) (by omega)
  have scaled := evaluatesNatI32Multiply (leftValue := reg.val % 8) (rightValue := 8) regLow eight (by omega)
  have first := evaluatesNatI32Add (leftValue := 192) (rightValue := reg.val % 8 * 8)
    (show Evaluates program before (number 192) (.signed .i32 192) before from ⟨1, rfl⟩) scaled (by omega)
  exact evaluatesNatI32Add (leftValue := 192 + reg.val % 8 * 8) (rightValue := rm.val % 8) first rmLow (by omega)

theorem validate (checked : CheckedValidation program kind) (input : Int)
    (wellFormed : StateWellFormed before)
    (readInput : Evaluates program.core before expression (.signed .i32 input) before) :
    ∃ after, Evaluates program.core before (.unary .logicalNot (.call checked.source.function.id [expression]))
        (.boolean (!kind.accepts input)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨after, run, effect, heapFrame⟩ := Register.validation_call checked input wellFormed (.cons readInput (.nil _ _))
  exact ⟨after, evaluatesUnary run rfl, effect, heapFrame⟩

theorem register_guard (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (widthValue : Register.Width) (reg rm : Fin 16) (wellFormed : StateWellFormed before)
    (regRead : before.local? 5 = some (.signed .i32 reg.val))
    (rmRead : before.local? 6 = some (.signed .i32 rm.val))
    (widthRead : before.local? 3 = some (.signed .i32 widthValue.bits)) :
    ∃ after, Evaluates program.core before (registerGuard valid.source.function.id width.source.function.id)
        (.boolean false) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have regGood : Register.Validation.register.accepts reg.val = true :=
    (Register.register_domain _).mpr ⟨reg, rfl⟩
  have rmGood : Register.Validation.register.accepts rm.val = true :=
    (Register.register_domain _).mpr ⟨rm, rfl⟩
  have widthGood : Register.Validation.width.accepts widthValue.bits = true :=
    (Register.width_domain _).mpr ⟨widthValue, rfl⟩
  obtain ⟨first, regRun, regEffect, regHeap⟩ := validate valid reg.val wellFormed
    (local_evaluates program.core regRead)
  rw [regGood] at regRun
  obtain ⟨second, rmRun, rmEffect, rmHeap⟩ := validate valid rm.val regEffect.wellFormed
    (local_evaluates program.core (regEffect.empty_preserves_local wellFormed rmRead))
  rw [rmGood] at rmRun
  obtain ⟨after, widthRun, widthEffect, widthHeap⟩ := validate width widthValue.bits rmEffect.wellFormed
    (local_evaluates program.core ((regEffect.trans rmEffect).empty_preserves_local wellFormed widthRead))
  rw [widthGood] at widthRun
  exact ⟨after, evaluatesLogicalOrFalse (evaluatesLogicalOrFalse regRun rmRun) widthRun,
    (regEffect.trans rmEffect).trans widthEffect,
    (regHeap.trans rmHeap).trans widthHeap⟩

theorem valid_guard (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (config : Config) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments output capacity cursor) frontier before) :
    ∃ after, Evaluates program.core before (registerGuard valid.source.function.id width.source.function.id)
        (.boolean false) after ∧ Locals (config.arguments output capacity cursor) frontier after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨after, run, effect, heap⟩ := register_guard valid width config.width config.reg config.rm wellFormed
    (inputs.found ⟨5, by simp⟩) (inputs.found ⟨6, by simp⟩) (inputs.found ⟨3, by simp⟩)
  exact ⟨after, run, inputs.empty wellFormed effect, effect, heap⟩

theorem tail (program : Program) (config : Config)
    (cursor : Cursor before cell temporary 10 position values)
    (inputs : Locals (config.saved output capacity start) frontier before)
    (notArray : ∀ index : Fin (config.saved output capacity start).length,
      ∀ elements, (config.saved output capacity start).get index ≠ .array elements)
    (room : position + 2 ≤ values.length) (bounded : position + 2 ≤ 2147483647) :
    ∃ after, Executes program before registerTail (.returned (some (.signed .i32 (position + 2 : Nat)))) after ∧
      Cursor after cell temporary 10 position (writtenBytes values position [config.opcode.byte.val, modRM config.reg config.rm]) ∧
      Locals (config.saved output capacity start) frontier after ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have opcode := opcode_byte program config.opcode (inputs.found ⟨4, by simp⟩)
  obtain ⟨first, opcodeRun, firstCursor, firstInputs, firstEffect, firstHeap⟩ :=
    cursor.store program inputs notArray 0 config.opcode.byte.val (by omega) (by omega) opcode
  have modrm := modrm_byte program config.reg config.rm
    (firstInputs.found ⟨5, by simp⟩) (firstInputs.found ⟨6, by simp⟩)
  obtain ⟨after, modrmRun, finalCursor, finalInputs, finalEffect, finalHeap⟩ :=
    firstCursor.store program firstInputs notArray 1 (modRM config.reg config.rm)
      (by simp only [List.length_set]; omega) (by omega) modrm
  have returned := evaluatesNatI32Add (leftValue := position) (rightValue := 2)
    (local_evaluates program finalCursor.read)
    (show Evaluates program after (number 2) (.signed .i32 2) after from ⟨1, rfl⟩) bounded
  exact ⟨after, executesSequence (executesExpression opcodeRun)
    (executesSequence (executesExpression modrmRun) (executesSequenceReturned (executesReturnValue returned))),
    finalCursor, finalInputs, firstEffect.trans finalEffect, firstHeap.trans finalHeap⟩

theorem write (program : Program) (config : Config)
    (cursor : Cursor before cell temporary 10 position values)
    (inputs : Locals (config.saved output capacity start) frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ index : Fin (config.saved output capacity start).length,
      ∀ elements, (config.saved output capacity start).get index ≠ .array elements)
    (room : position + config.size ≤ values.length) (bounded : position + config.size ≤ 2147483647) :
    ∃ after, Executes program before registerWrite (.returned (some (.signed .i32 (position + config.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (writtenBytes values position config.bytes))) } ∧
      CellEffect (CellSet.union (CellSet.singleton cell) (CellSet.singleton temporary)) before after ∧
      HeapFrame before after := by
  have size := config.prefix_size
  have rexGuard := has_rex program config.rex (inputs.found ⟨8, by simp⟩)
  have rexValue := local_evaluates program (inputs.found ⟨8, by simp⟩)
  obtain ⟨first, rexRun, firstCursor, firstInputs, firstEffect, firstHeap⟩ :=
    cursor.append program inputs fresh notArray (decide (config.rex ≠ 0)) config.rex
      (by omega) (by omega) rexGuard rexValue
  have escapeGuard := has_escape program config.opcode (firstInputs.found ⟨4, by simp⟩)
  obtain ⟨second, escapeRun, secondCursor, secondInputs, secondEffect, secondHeap⟩ :=
    firstCursor.append program firstInputs fresh notArray config.opcode.extended 15
      (by simp only [writtenBytes_length]; omega) (by omega) escapeGuard
      (show Evaluates program first (number 15) (.signed .i32 15) first from ⟨1, rfl⟩)
  obtain ⟨after, tailRun, tailCursor, _, tailEffect, tailHeap⟩ := tail program config secondCursor secondInputs notArray
    (by simp only [writtenBytes_length]; omega) (by omega)
  have next : position + (decide (config.rex ≠ 0)).toNat + config.opcode.extended.toNat + 2 = position + config.size := by omega
  rw [next] at tailRun
  refine ⟨after, executesSequence rexRun (executesSequence escapeRun tailRun), ?_,
    (firstEffect.trans secondEffect).trans (tailEffect.weaken CellSet.subset_union_left),
    (firstHeap.trans secondHeap).trans tailHeap⟩
  have content := tailCursor.backing
  by_cases absent : config.rex = 0 <;> cases escape : config.opcode.extended <;>
    simpa [Config.bytes, Encoding.bytes, Encoding.header, absent, escape, Bool.toNat,
      writtenBytes, Nat.add_assoc] using content

theorem after_size (fits : CheckedFits program) (config : Config) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (sizeRead : before.local? 9 = some (.signed .i32 config.size))
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + config.size ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (registerAfterSize fits.source.function.id)
        (.returned (some (.signed .i32 (start + config.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (writtenBytes values start config.bytes))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 1, read 2, read 9]
      (fitsValues capacity start config.size) before :=
    .cons (local_evaluates program.core (inputs.found ⟨1, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨2, by simp⟩))
        (.cons (local_evaluates program.core sizeRead) (.nil _ _)))
  obtain ⟨guarded, fit, guardEffect, guardHeap⟩ := fits_call fits capacity start config.size wellFormed
    (Int.ofNat_le.mpr bounded) args
  have good : reserved capacity start config.size = true := by
    simp only [reserved, decide_eq_true_eq]
    omega
  rw [good] at fit
  have guard := evaluatesUnary fit (show evalUnaryValue program.core.target .logicalNot (.boolean true) = .ok (.boolean false) from rfl)
  have guardedInputs := inputs.empty wellFormed guardEffect
  have guardedBacking := guardEffect.empty_preserves_entry wellFormed backing
  let scope := guarded.bindLocal 10 (.signed .i32 start)
  have scopeWF := bindLocal_preserves_well_formed guarded 10 (.signed .i32 start) guardEffect.wellFormed
  have scopeInputs := guardedInputs.bind guardEffect.wellFormed (id := 10) (by simp) (.signed .i32 start)
  have cursor : Cursor scope cell guarded.nextCell 10 start values := ⟨scopeWF, scopeInputs.found ⟨0, by simp⟩,
    bindLocal_owns_fresh guarded 10 (.signed .i32 start) guardEffect.wellFormed,
    ((bindLocal_effect guarded 10 (.signed .i32 start)).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry guardEffect.wellFormed guardedBacking) (by simp [CellSet.empty])).trans guardedBacking⟩
  obtain ⟨written, writeRun, content, writeEffect, writeHeap⟩ := write program.core config cursor scopeInputs
    guardedInputs.frontierBound (config.saved_not_array cell values.length capacity start) (by omega) (by omega)
  have closed := CellEffect.closeLocal guarded 10 (.signed .i32 start) guardEffect.wellFormed writeEffect
  have narrow : CellEffect (CellSet.singleton cell) guarded (restoreLocals guarded written) := by
    apply closed.narrow
    intro changed old member
    rcases member with output | temporary
    · exact output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
  exact ⟨restoreLocals guarded written,
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesLetLocal (local_evaluates program.core (guardedInputs.found ⟨2, by simp⟩)) writeRun),
    content, (guardEffect.weaken CellSet.empty_subset).trans narrow,
    guardHeap.trans (HeapFrame.closeLocal guarded 10 (.signed .i32 start) writeHeap)⟩

theorem select_size (program : Program) (config : Config) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved output capacity start) frontier before) :
    ∃ after, Executes program (before.bindLocal 9 (.signed .i32 2))
        (.sequence (countPrefix 9 hasRex) (countPrefix 9 hasEscape)) .next after ∧
      after.local? 9 = some (.signed .i32 config.size) ∧
      Locals (config.saved output capacity start) frontier after ∧
      CellEffect (CellSet.singleton before.nextCell) (before.bindLocal 9 (.signed .i32 2)) after ∧
      HeapFrame (before.bindLocal 9 (.signed .i32 2)) after := by
  let scope := before.bindLocal 9 (.signed .i32 2)
  have scopeWF := bindLocal_preserves_well_formed before 9 (.signed .i32 2) wellFormed
  have scopeInputs := inputs.bind wellFormed (id := 9) (by simp) (.signed .i32 2)
  have count := config.prefix_size
  have small := Encoding.size_bounds config.rex config.opcode
  change 2 ≤ config.size ∧ config.size ≤ 4 at small
  obtain ⟨first, rexRun, rexOwned, firstInputs, firstEffect, firstHeap⟩ := count_prefix (position := 2) program scopeWF
    (bindLocal_owns_fresh before 9 (.signed .i32 2) wellFormed) scopeInputs inputs.frontierBound
    (decide (config.rex ≠ 0)) (by omega) (has_rex program config.rex (scopeInputs.found ⟨8, by simp⟩))
  obtain ⟨second, escapeRun, escapeOwned, secondInputs, secondEffect, secondHeap⟩ := count_prefix
    (position := 2 + (decide (config.rex ≠ 0)).toNat) program
    firstEffect.wellFormed rexOwned firstInputs inputs.frontierBound config.opcode.extended (by omega)
    (has_escape program config.opcode (firstInputs.found ⟨4, by simp⟩))
  have amount : 2 + (decide (config.rex ≠ 0)).toNat + config.opcode.extended.toNat = config.size := by omega
  rw [amount] at escapeOwned
  exact ⟨second, executesSequence rexRun escapeRun,
    Assertion.localPointsTo_local 9 before.nextCell _ second escapeOwned, secondInputs,
    firstEffect.trans secondEffect, firstHeap.trans secondHeap⟩

theorem sized (fits : CheckedFits program) (config : Config) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + config.size ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (registerSize fits.source.function.id)
        (.returned (some (.signed .i32 (start + config.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (writtenBytes values start config.bytes))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have scopeWF := bindLocal_preserves_well_formed before 9 (.signed .i32 2) wellFormed
  obtain ⟨second, sizeRun, sizeRead, secondInputs, sizeEffect, sizeHeap⟩ := select_size program.core config wellFormed inputs
  have scopeBacking := ((bindLocal_effect before 9 (.signed .i32 2)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have secondBacking := sizeEffect.preserves_entry scopeWF scopeBacking
    (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry wellFormed backing))
  obtain ⟨written, writeRun, contents, writeEffect, writeHeap⟩ := after_size fits config capacity start
    sizeEffect.wellFormed secondInputs sizeRead secondBacking room storage bounded
  have body := executesLetLocal (id := 9) (type := i32)
    (show Evaluates program.core before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
    (executesSequence_continue sizeRun writeRun)
  have closed := CellEffect.closeLocal before 9 (.signed .i32 2) wellFormed
    ((sizeEffect.weaken CellSet.subset_union_left).trans (writeEffect.weaken CellSet.subset_union_right))
  have narrow : CellEffect (CellSet.singleton cell) before (restoreLocals before written) := by
    apply closed.narrow
    intro changed old member
    rcases member with temporary | output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
    · exact output
  exact ⟨restoreLocals before written, body, contents, narrow,
    HeapFrame.closeLocal before 9 (.signed .i32 2) (sizeHeap.trans writeHeap)⟩

theorem rex_value (rex : CheckedRex program) (config : Config) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments output capacity start) frontier before) :
    ∃ after, Evaluates program.core before (.call rex.source.function.id [read 3, read 5, read 6, read 7])
        (.signed .i32 config.rex) after ∧ Locals (config.arguments output capacity start) frontier after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 3, read 5, read 6, read 7]
      (Register.inputValues config.width config.reg config.rm config.forceByte) before :=
    .cons (local_evaluates program.core (inputs.found ⟨3, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨5, by simp⟩))
        (.cons (local_evaluates program.core (inputs.found ⟨6, by simp⟩))
          (.cons (local_evaluates program.core (inputs.found ⟨7, by simp⟩)) (.nil _ _))))
  obtain ⟨after, run, effect, heapFrame⟩ := Register.rex_call rex config.width config.reg config.rm config.forceByte wellFormed args
  exact ⟨after, run, inputs.empty wellFormed effect, effect, heapFrame⟩

theorem after_guard (rex : CheckedRex program) (fits : CheckedFits program) (config : Config) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + config.size ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before
        (.letLocal 8 i32 (.call rex.source.function.id [read 3, read 5, read 6, read 7]) (registerSize fits.source.function.id))
        (.returned (some (.signed .i32 (start + config.size : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (writtenBytes values start config.bytes))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨middle, rexRun, middleInputs, rexEffect, rexHeap⟩ := rex_value rex config wellFormed inputs
  have middleBacking := rexEffect.empty_preserves_entry wellFormed backing
  let scope := middle.bindLocal 8 (.signed .i32 config.rex)
  have scopeWF := bindLocal_preserves_well_formed middle 8 (.signed .i32 config.rex) rexEffect.wellFormed
  have scopeInputs : Locals (config.saved (.slice i32 cell [] 0 values.length) capacity start) scope.nextCell scope :=
    middleInputs.push rexEffect.wellFormed (.signed .i32 config.rex)
  have scopeBacking := ((bindLocal_effect middle 8 (.signed .i32 config.rex)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry rexEffect.wellFormed middleBacking) (by simp [CellSet.empty])).trans middleBacking
  obtain ⟨written, sizeRun, contents, sizeEffect, sizeHeap⟩ := sized fits config capacity start scopeWF scopeInputs scopeBacking room storage bounded
  exact ⟨restoreLocals middle written, executesLetLocal rexRun sizeRun, contents,
    (rexEffect.weaken CellSet.empty_subset).trans (CellEffect.closeLocal middle 8 (.signed .i32 config.rex) rexEffect.wellFormed sizeEffect),
    rexHeap.trans (HeapFrame.closeLocal middle 8 (.signed .i32 config.rex) sizeHeap)⟩

/-- Full source-linked success contract: execute validation, REX construction,
size selection, reservation, and every byte store, restoring all three scopes. -/
theorem succeeds (checked : CheckedRegisterForm program valid width rex fits) (config : Config) (capacity start : Nat)
    (wellFormed : StateWellFormed before) (room : start + config.size ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (config.arguments (.slice i32 cell [] 0 values.length) capacity start) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (start + config.size : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (writtenBytes values start config.bytes))) } ∧
      config.Emission values start (writtenBytes values start config.bytes) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let output : Value := .slice i32 cell [] 0 values.length
  let params := parameterBindings (fun index : Fin 8 => (config.arguments output capacity start).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have reads (index : Fin 8) : callee.local? index.val = some ((config.arguments output capacity start).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have inputs := Locals.ofReads (values := config.arguments output capacity start) calleeWF reads
  obtain ⟨guarded, guardRun, guardedInputs, guardEffect, guardHeap⟩ := valid_guard valid width config calleeWF inputs
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, bodyRun, contents, bodyEffect, bodyHeap⟩ := after_guard rex fits config capacity start
    guardEffect.wellFormed guardedInputs (guardEffect.empty_preserves_entry calleeWF calleeBacking) room storage bounded
  have effect := (guardEffect.weaken CellSet.empty_subset).trans bodyEffect
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequence (executesIfFalse guardRun (executesSkip _ _)) bodyRun) effect
  exact ⟨restoreLocals before completed, called.1, contents, config.emission (by omega), called.2,
    HeapFrame.closeCall before params (guardHeap.trans bodyHeap)⟩

theorem invalid_guard (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (rawArguments output capacity start widthValue opcode reg rm forceByte) frontier before)
    (invalid : Register.Validation.register.accepts reg = false ∨
      Register.Validation.register.accepts rm = false ∨ Register.Validation.width.accepts widthValue = false) :
    ∃ after, Evaluates program.core before (registerGuard valid.source.function.id width.source.function.id)
        (.boolean true) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨first, regRun, regEffect, regHeap⟩ := validate valid reg wellFormed
    (local_evaluates program.core (inputs.found ⟨5, by simp⟩))
  cases regFlag : Register.Validation.register.accepts reg with
  | false =>
      rw [regFlag] at regRun
      exact ⟨first, evaluatesLogicalOrTrue (evaluatesLogicalOrTrue regRun), regEffect, regHeap⟩
  | true =>
      rw [regFlag] at regRun
      have firstInputs := inputs.empty wellFormed regEffect
      obtain ⟨second, rmRun, rmEffect, rmHeap⟩ := validate valid rm regEffect.wellFormed
        (local_evaluates program.core (firstInputs.found ⟨6, by simp⟩))
      cases rmFlag : Register.Validation.register.accepts rm with
      | false =>
          rw [rmFlag] at rmRun
          exact ⟨second, evaluatesLogicalOrTrue (evaluatesLogicalOrFalse regRun rmRun),
            regEffect.trans rmEffect, regHeap.trans rmHeap⟩
      | true =>
          rw [rmFlag] at rmRun
          have widthBad : Register.Validation.width.accepts widthValue = false := by
            simpa only [regFlag, rmFlag, Bool.true_eq_false, false_or] using invalid
          have secondInputs := firstInputs.empty regEffect.wellFormed rmEffect
          obtain ⟨after, widthRun, widthEffect, widthHeap⟩ := validate width widthValue rmEffect.wellFormed
            (local_evaluates program.core (secondInputs.found ⟨3, by simp⟩))
          rw [widthBad] at widthRun
          exact ⟨after, evaluatesLogicalOrFalse (evaluatesLogicalOrFalse regRun rmRun) widthRun,
            (regEffect.trans rmEffect).trans widthEffect, (regHeap.trans rmHeap).trans widthHeap⟩

/-- Invalid register/width operands reject before REX, capacity checks, or
output access. No premise is needed about the output value or capacity. -/
theorem rejects_invalid (checked : CheckedRegisterForm program valid width rex fits)
    (output : Value) (capacity start widthValue opcode reg rm : Int) (forceByte : Bool)
    (wellFormed : StateWellFormed before)
    (invalid : Register.Validation.register.accepts reg = false ∨
      Register.Validation.register.accepts rm = false ∨ Register.Validation.width.accepts widthValue = false)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (rawArguments output capacity start widthValue opcode reg rm forceByte) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let values := rawArguments output capacity start widthValue opcode reg rm forceByte
  let params := parameterBindings (fun index : Fin 8 => values.get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have reads (index : Fin 8) : callee.local? index.val = some (values.get index) :=
    enterCall_parameterBindings_matches wellFormed index
  obtain ⟨rejected, guardRun, effect, heapFrame⟩ := invalid_guard valid width calleeWF
    (Locals.ofReads (values := values) calleeWF reads) invalid
  have negative : Evaluates program.core rejected negativeOne (.signed .i32 (-1)) rejected := by
    apply evaluatesUnary (show Evaluates program.core rejected (number 1) (.signed .i32 1) rejected from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  have body : Executes program.core callee
      (registerBody valid.source.function.id width.source.function.id rex.source.function.id fits.source.function.id)
      (.returned (some (.signed .i32 (-1)))) rejected :=
    executesSequenceReturned (executesIfTrue guardRun (executesSequenceReturned (executesReturnValue negative)))
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl body effect
  exact ⟨restoreLocals before rejected, called.1, called.2, HeapFrame.closeCall before params heapFrame⟩

theorem after_size_rejected (fits : CheckedFits program) (config : Config) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved output capacity start) frontier before)
    (sizeRead : before.local? 9 = some (.signed .i32 config.size))
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start config.size = false) :
    ∃ after, Executes program.core before (registerAfterSize fits.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before [read 1, read 2, read 9]
      (fitsValues capacity start config.size) before :=
    .cons (local_evaluates program.core (inputs.found ⟨1, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨2, by simp⟩))
        (.cons (local_evaluates program.core sizeRead) (.nil _ _)))
  obtain ⟨after, run, effect, heapFrame⟩ := fits_call fits capacity start config.size wellFormed bounded args
  rw [bad] at run
  have guard := evaluatesUnary run (show evalUnaryValue program.core.target .logicalNot (.boolean false) = .ok (.boolean true) from rfl)
  have negative : Evaluates program.core after negativeOne (.signed .i32 (-1)) after := by
    apply evaluatesUnary (show Evaluates program.core after (number 1) (.signed .i32 1) after from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  exact ⟨after, executesSequenceReturned (executesIfTrue guard
    (executesSequenceReturned (executesReturnValue negative))), effect, heapFrame⟩

theorem sized_rejected (fits : CheckedFits program) (config : Config) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.saved output capacity start) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start config.size = false) :
    ∃ after, Executes program.core before (registerSize fits.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨counted, countRun, countRead, countInputs, countEffect, countHeap⟩ := select_size program.core config wellFormed inputs
  obtain ⟨rejected, rejectRun, rejectEffect, rejectHeap⟩ := after_size_rejected fits config capacity start
    countEffect.wellFormed countInputs countRead bounded bad
  have body := executesLetLocal (id := 9) (type := i32)
    (show Evaluates program.core before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
    (executesSequence_continue countRun rejectRun)
  have effect := CellEffect.closeLocal before 9 (.signed .i32 2) wellFormed
    (countEffect.trans (rejectEffect.weaken CellSet.empty_subset))
  have narrow : CellEffect CellSet.empty before (restoreLocals before rejected) := by
    apply effect.narrow
    intro cell old member
    exact False.elim ((Nat.ne_of_lt old) member)
  exact ⟨restoreLocals before rejected, body, narrow,
    HeapFrame.closeLocal before 9 (.signed .i32 2) (countHeap.trans rejectHeap)⟩

theorem after_guard_rejected (rex : CheckedRex program) (fits : CheckedFits program) (config : Config) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments output capacity start) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start config.size = false) :
    ∃ after, Executes program.core before
        (.letLocal 8 i32 (.call rex.source.function.id [read 3, read 5, read 6, read 7]) (registerSize fits.source.function.id))
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨middle, rexRun, middleInputs, rexEffect, rexHeap⟩ := rex_value rex config wellFormed inputs
  let scope := middle.bindLocal 8 (.signed .i32 config.rex)
  have scopeInputs : Locals (config.saved output capacity start) scope.nextCell scope :=
    middleInputs.push rexEffect.wellFormed (.signed .i32 config.rex)
  obtain ⟨rejected, rejectRun, rejectEffect, rejectHeap⟩ := sized_rejected fits config capacity start
    (bindLocal_preserves_well_formed middle 8 (.signed .i32 config.rex) rexEffect.wellFormed) scopeInputs bounded bad
  exact ⟨restoreLocals middle rejected, executesLetLocal rexRun rejectRun,
    rexEffect.trans (CellEffect.closeLocal middle 8 (.signed .i32 config.rex) rexEffect.wellFormed rejectEffect),
    rexHeap.trans (HeapFrame.closeLocal middle 8 (.signed .i32 config.rex) rejectHeap)⟩

/-- Validated operands with an invalid/insufficient reservation return -1
without touching output, even if output is not a slice. Size selection's
temporary writes disappear from the caller-visible footprint. -/
theorem rejects_capacity (checked : CheckedRegisterForm program valid width rex fits) (config : Config)
    (output : Value) (capacity start : Int) (wellFormed : StateWellFormed before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start config.size = false)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (config.arguments output capacity start) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 8 => (config.arguments output capacity start).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have reads (index : Fin 8) : callee.local? index.val = some ((config.arguments output capacity start).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  obtain ⟨guarded, guardRun, guardInputs, guardEffect, guardHeap⟩ := valid_guard valid width config calleeWF
    (Locals.ofReads (values := config.arguments output capacity start) calleeWF reads)
  obtain ⟨rejected, rejectRun, rejectEffect, rejectHeap⟩ := after_guard_rejected rex fits config capacity start
    guardEffect.wellFormed guardInputs bounded bad
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl
    (executesSequence (executesIfFalse guardRun (executesSkip _ _)) rejectRun) (guardEffect.trans rejectEffect)
  exact ⟨restoreLocals before rejected, called.1, called.2, HeapFrame.closeCall before params (guardHeap.trans rejectHeap)⟩

end Lanius.X86.Encode
