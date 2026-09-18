import Lanius.X86.Source.Indexed
import Lanius.X86.Encode.Register
import Lanius.X86.Buffer.Fixed
import Lanius.X86.Machine.Index

namespace Lanius.X86.Encode.Indexed

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

structure Config where
  destination : Fin 16
  base : Fin 16
  index : Fin 16
  scale : Fin 4
  displacement : Int
  notRsp : index.val ≠ 4

def Config.initial (config : Config) : Nat := Register.value .w64 config.destination config.base false
def Config.rex (config : Config) : Nat := config.initial + if 8 ≤ config.index.val then 2 else 0
def Config.modRM (config : Config) : Nat := 132 + config.destination.val % 8 * 8
def Config.sib (config : Config) : Nat := config.scale.val * 64 + config.index.val % 8 * 8 + config.base.val % 8
def Config.header (config : Config) : List Nat := [config.rex, 141, config.modRM, config.sib]
def Config.bytes (config : Config) : List UInt8 := config.header.map UInt8.ofNat ++ i32Bytes config.displacement
def Config.written (config : Config) (values : List Int) (start : Nat) : List Int :=
  writtenWord (writtenBytes values start config.header) (start + 4) config.displacement

def Config.arguments (config : Config) (output : Value) (capacity start : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 config.destination.val,
    .signed .i32 config.base.val, .signed .i32 config.index.val,
    .signed .i32 config.scale.val, .signed .i32 config.displacement]

def Config.saved (config : Config) (output : Value) (capacity start : Int) : List Value :=
  config.arguments output capacity start ++ [.signed .i32 config.rex]

@[simp] theorem Config.arguments_length (config : Config) : (config.arguments output capacity start).length = 8 := rfl
@[simp] theorem Config.saved_length (config : Config) : (config.saved output capacity start).length = 9 := rfl
@[simp] theorem Config.header_length (config : Config) : config.header.length = 4 := rfl
@[simp] theorem Config.bytes_length (config : Config) : config.bytes.length = 8 := by simp [Config.bytes, i32Bytes_length]
@[simp] theorem Config.written_length (config : Config) (values : List Int) :
    (config.written values start).length = values.length := by simp [Config.written]

theorem Config.initial_bound (config : Config) : config.initial ≤ 79 := by
  have := Register.value_bounds .w64 config.destination config.base false
  change config.initial = 0 ∨ (64 ≤ config.initial ∧ config.initial < 80) at this
  omega

theorem Config.saved_not_array (config : Config) (cell : CellId) (length : Nat) (capacity start : Int) :
    ∀ index : Fin (config.saved (.slice i32 cell [] 0 length) capacity start).length,
      ∀ elements, (config.saved (.slice i32 cell [] 0 length) capacity start).get index ≠ .array elements := by
  intro ⟨index, bound⟩ elements
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 ∨ index = 6 ∨ index = 7 ∨ index = 8 := by
    change index < 9 at bound
    omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> intro same <;> cases same

theorem valid_guard (checked : Source.Indexed.Checked program valid rex fits word) (config : Config)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments output capacity start) frontier before) :
    ∃ after, Evaluates program.core before (Source.Indexed.guard valid.source.function.id checked.rsp)
        (.boolean false) after ∧ Locals (config.arguments output capacity start) frontier after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨first, a, ae, ah⟩ := validate valid config.destination.val wellFormed
    (local_evaluates program.core (inputs.found ⟨3, by simp⟩))
  have ai := inputs.empty wellFormed ae
  obtain ⟨second, b, be, bh⟩ := validate valid config.base.val ae.wellFormed
    (local_evaluates program.core (ai.found ⟨4, by simp⟩))
  have bi := ai.empty ae.wellFormed be
  obtain ⟨after, c, ce, ch⟩ := validate valid config.index.val be.wellFormed
    (local_evaluates program.core (bi.found ⟨5, by simp⟩))
  have ci := bi.empty be.wellFormed ce
  have good (register : Fin 16) : Register.Validation.register.accepts register.val = true :=
    (Register.register_domain _).mpr ⟨register, rfl⟩
  rw [good] at a b c
  have rspValue : Evaluates program.core after (.constant checked.rsp) (.signed .i32 4) after := by
    refine ⟨1, ?_⟩
    simp only [evalExpr, checked.found, checked.value]
  have noRsp : Evaluates program.core after (.binary .equal (read 5) (.constant checked.rsp)) (.boolean false) after := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core (ci.found ⟨5, by simp⟩)) rspValue
    change evalBinaryValue program.core.target .equal (.signed .i32 config.index.val) (.signed .i32 4) = .ok (.boolean false)
    simp [evalBinaryValue, scalarEqual]
    exact_mod_cast config.notRsp
  have low : Evaluates program.core after (.binary .less (read 6) (number 0)) (.boolean false) after := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core (ci.found ⟨6, by simp⟩))
      (show Evaluates program.core after (number 0) (.signed .i32 0) after from ⟨1, rfl⟩)
    change evalBinaryValue program.core.target .less (.signed .i32 config.scale.val) (.signed .i32 0) = .ok (.boolean false)
    simp [evalBinaryValue, evalSignedBinary]
  have high : Evaluates program.core after (.binary .greater (read 6) (number 3)) (.boolean false) after := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core (ci.found ⟨6, by simp⟩))
      (show Evaluates program.core after (number 3) (.signed .i32 3) after from ⟨1, rfl⟩)
    change evalBinaryValue program.core.target .greater (.signed .i32 config.scale.val) (.signed .i32 3) = .ok (.boolean false)
    have := config.scale.isLt
    simp [evalBinaryValue, evalSignedBinary]
    omega
  exact ⟨after, evaluatesLogicalOrFalse (evaluatesLogicalOrFalse (evaluatesLogicalOrFalse
    (evaluatesLogicalOrFalse (evaluatesLogicalOrFalse a b) c) noRsp) low) high,
    ci, (ae.trans be).trans ce, (ah.trans bh).trans ch⟩

theorem modrm_byte (program : Program) (config : Config)
    (found : before.local? 3 = some (.signed .i32 config.destination.val)) :
    Evaluates program before Source.Indexed.modRM (.signed .i32 config.modRM) before := by
  have eight : Evaluates program before (number 8) (.signed .i32 8) before := ⟨1, rfl⟩
  have low := evaluatesNatI32Remainder (leftValue := config.destination.val) (rightValue := 8)
    (local_evaluates program found) eight (by decide) (by omega)
  have scaled := evaluatesNatI32Multiply (leftValue := config.destination.val % 8) (rightValue := 8) low eight (by omega)
  exact evaluatesNatI32Add (leftValue := 132) (rightValue := config.destination.val % 8 * 8) ⟨1, rfl⟩ scaled (by omega)

theorem sib_byte (program : Program) (config : Config)
    (base : before.local? 4 = some (.signed .i32 config.base.val))
    (index : before.local? 5 = some (.signed .i32 config.index.val))
    (scale : before.local? 6 = some (.signed .i32 config.scale.val)) :
    Evaluates program before Source.Indexed.sib (.signed .i32 config.sib) before := by
  have eight : Evaluates program before (number 8) (.signed .i32 8) before := ⟨1, rfl⟩
  have indexLow := evaluatesNatI32Remainder (leftValue := config.index.val) (rightValue := 8)
    (local_evaluates program index) eight (by decide) (by omega)
  have baseLow := evaluatesNatI32Remainder (leftValue := config.base.val) (rightValue := 8)
    (local_evaluates program base) eight (by decide) (by omega)
  have indexPart := evaluatesNatI32Multiply (leftValue := config.index.val % 8) (rightValue := 8) indexLow eight (by omega)
  have scalePart := evaluatesNatI32Multiply (leftValue := config.scale.val) (rightValue := 64)
    (local_evaluates program scale) (show Evaluates _ _ (number 64) _ _ from ⟨1, rfl⟩) (by have := config.scale.isLt; omega)
  have combined := evaluatesNatI32Add (leftValue := config.scale.val * 64) (rightValue := config.index.val % 8 * 8)
    scalePart indexPart (by have := config.scale.isLt; omega)
  exact evaluatesNatI32Add (leftValue := config.scale.val * 64 + config.index.val % 8 * 8)
    (rightValue := config.base.val % 8) combined baseLow (by have := config.scale.isLt; omega)

theorem stores (word : CheckedWord program) (config : Config)
    (entries : List (Expr × Nat)) (offset : Nat) (position : Nat)
    (resources : FixedResources before cell position values)
    (inputs : Locals (config.saved output capacity start) frontier before)
    (notArray : ∀ index : Fin (config.saved output capacity start).length,
      ∀ elements, (config.saved output capacity start).get index ≠ .array elements)
    (within : offset + entries.length = 4)
    (room : position + 8 ≤ values.length) (bounded : position + 8 ≤ 2147483647)
    (expressions : ∀ entry ∈ entries, ∀ state,
      Locals (config.saved output capacity start) frontier state →
      Evaluates program.core state entry.1 (.signed .i32 entry.2) state) :
    ∃ after, Executes program.core before
        (Source.Indexed.stores offset (entries.map Prod.fst)
          (returned (.call word.source.function.id [read 0, fixedIndex 4, read 7])))
        (.returned (some (.signed .i32 (position + 8 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
        (writtenWord (writtenBytes values (position + offset) (entries.map Prod.snd))
          (position + 4) config.displacement))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  induction entries generalizing before values offset with
  | nil =>
    have args : ArgumentsEvaluateTo program.core before [read 0, fixedIndex 4, read 7]
        (wordValues (.slice i32 cell [] 0 values.length) (position + 4) config.displacement) before :=
      .cons (local_evaluates program.core resources.sliceRead)
        (.cons (fixed_index program.core position 4 (by omega) resources.positionRead)
          (.cons (local_evaluates program.core (inputs.found ⟨7, by simp⟩)) (.nil _ _)))
    obtain ⟨after, run, contents, effect, heap⟩ := word_call word (position + 4) config.displacement
      resources.wellFormed (by omega) (by omega) resources.backing args
    refine ⟨after, ?_, contents, effect, heap⟩
    simpa [Source.Indexed.stores, returned, Nat.add_assoc] using executesSequenceReturned (executesReturnValue run)
  | cons entry entries ih =>
    obtain ⟨middle, store, contents, effect, heap, _⟩ := evaluatesSliceStore program.core before before
      values 0 (fixedIndex offset) entry.1 cell (position + offset) entry.2
      resources.wellFormed (by simp only [List.length_cons] at within; omega) resources.sliceRead
      (fixed_index program.core position offset (by simp only [List.length_cons] at within; omega) resources.positionRead)
      (expressions entry (by simp) before inputs) (CellEffect.refl resources.wellFormed) resources.backing
    have middleResources : FixedResources middle cell position (values.set (position + offset) entry.2) :=
      ⟨effect.wellFormed, (by simpa only [List.length_set] using (effect.preserves_local_of_distinct_value
        resources.wellFormed resources.sliceRead resources.backing (by intro same; cases same))),
        effect.preserves_local_of_distinct_value resources.wellFormed resources.positionRead resources.backing
          (by intro same; cases same), contents⟩
    obtain ⟨after, rest, result, restEffect, restHeap⟩ := ih (offset + 1) middleResources
      (inputs.store resources.wellFormed effect resources.backing (fun index => notArray index _))
      (by simp only [List.length_cons] at within; omega) (by simpa only [List.length_set] using room)
      (fun pair member state locals => expressions pair (List.mem_cons_of_mem _ member) state locals)
    exact ⟨after, executesSequence (executesExpression store) rest,
      by simpa only [List.map_cons, writtenBytes, Nat.add_assoc] using result,
      effect.trans restEffect, heap.trans restHeap⟩

theorem write (word : CheckedWord program) (config : Config)
    (resources : FixedResources before cell position values)
    (inputs : Locals (config.saved output capacity start) frontier before)
    (notArray : ∀ index : Fin (config.saved output capacity start).length,
      ∀ elements, (config.saved output capacity start).get index ≠ .array elements)
    (room : position + 8 ≤ values.length) (bounded : position + 8 ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Indexed.write word.source.function.id)
        (.returned (some (.signed .i32 (position + 8 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (config.written values position))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let entries : List (Expr × Nat) := [(read 8, config.rex), (number 141, 141),
    (Source.Indexed.modRM, config.modRM), (Source.Indexed.sib, config.sib)]
  apply stores word config entries 0 position resources inputs notArray rfl room bounded
  intro entry member state locals
  simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl
  · exact local_evaluates program.core (locals.found ⟨8, by simp⟩)
  · exact ⟨1, rfl⟩
  · exact modrm_byte program.core config (locals.found ⟨3, by simp⟩)
  · exact sib_byte program.core config (locals.found ⟨4, by simp⟩)
      (locals.found ⟨5, by simp⟩) (locals.found ⟨6, by simp⟩)

theorem extend_rex (config : Config) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments output capacity start) frontier before) :
    ∃ after, Executes program (before.bindLocal 8 (.signed .i32 config.initial))
        Source.Indexed.extendRex .next after ∧
      Locals (config.saved output capacity start) after.nextCell after ∧
      CellEffect (CellSet.singleton before.nextCell) (before.bindLocal 8 (.signed .i32 config.initial)) after ∧
      HeapFrame (before.bindLocal 8 (.signed .i32 config.initial)) after := by
  let scope := before.bindLocal 8 (.signed .i32 config.initial)
  have scopeWF := bindLocal_preserves_well_formed before 8 (.signed .i32 config.initial) wellFormed
  have scopeInputs := inputs.bind wellFormed (id := 8) (by simp) (.signed .i32 config.initial)
  have owns := bindLocal_owns_fresh before 8 (.signed .i32 config.initial) wellFormed
  have condition : Evaluates program scope Source.Indexed.extended (.boolean (decide (8 ≤ config.index.val))) scope := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program (scopeInputs.found ⟨5, by simp⟩))
      (show Evaluates program scope (number 8) (.signed .i32 8) scope from ⟨1, rfl⟩)
    change evalBinaryValue program.target .greaterEqual (.signed .i32 config.index.val) (.signed .i32 8) = _
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have saved (state : State) (wf : StateWellFormed state)
      (old : Locals (config.arguments output capacity start) frontier state)
      (new : state.local? 8 = some (.signed .i32 config.rex)) :
      Locals (config.saved output capacity start) state.nextCell state := by
    apply Locals.ofReads wf
    intro ⟨index, bound⟩
    change index < 9 at bound
    have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 ∨ index = 6 ∨ index = 7 ∨ index = 8 := by omega
    rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact old.found ⟨0, by simp⟩
    · exact old.found ⟨1, by simp⟩
    · exact old.found ⟨2, by simp⟩
    · exact old.found ⟨3, by simp⟩
    · exact old.found ⟨4, by simp⟩
    · exact old.found ⟨5, by simp⟩
    · exact old.found ⟨6, by simp⟩
    · exact old.found ⟨7, by simp⟩
    · exact new
  by_cases extended : 8 ≤ config.index.val
  · simp only [extended, decide_true] at condition
    have operation : evalAssignValue program.target .add (some (.signed .i32 config.initial)) (.signed .i32 2) =
        .ok (.signed .i32 config.rex) := by
      simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
      rw [wrapSigned_i32_of_nonnegative program.target ((config.initial : Int) + 2) (by omega)
        (by have := config.initial_bound; omega)]
      simp [Config.rex, extended]
    obtain ⟨after, update, owned, effect, heap⟩ := evaluatesOwnedLocalUpdate scopeWF owns
      (show Evaluates program scope (number 2) (.signed .i32 2) scope from ⟨1, rfl⟩) operation
    exact ⟨after, executesIfTrue condition (executesSequence (executesExpression update) (executesSkip _ _)),
      saved after effect.wellFormed (scopeInputs.fresh scopeWF effect inputs.frontierBound)
        (Assertion.localPointsTo_local 8 before.nextCell _ after owned), effect, heap⟩
  · have rexIs : config.rex = config.initial := by simp [Config.rex, extended]
    simp only [extended, decide_false] at condition
    exact ⟨scope, executesIfFalse condition (executesSkip _ _),
      saved scope scopeWF scopeInputs (by simpa only [rexIs] using bindLocal_finds_local before 8 (.signed .i32 config.initial) wellFormed),
      CellEffect.refl scopeWF, HeapFrame.refl scope⟩

theorem after_rex (rex : CheckedRex program) (word : CheckedWord program) (config : Config)
    (capacity start : Nat) (wellFormed : StateWellFormed before)
    (inputs : Locals (config.arguments (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 8 ≤ values.length) (bounded : start + 8 ≤ 2147483647) :
    ∃ after, Executes program.core before
        (.letLocal 8 i32 (.call rex.source.function.id Source.Indexed.rexArguments)
          (.sequence Source.Indexed.extendRex (Source.Indexed.write word.source.function.id)))
        (.returned (some (.signed .i32 (start + 8 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (config.written values start))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo program.core before Source.Indexed.rexArguments
      (Register.inputValues .w64 config.destination config.base false) before :=
    .cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (inputs.found ⟨3, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨4, by simp⟩)) (.cons ⟨1, rfl⟩ (.nil _ _))))
  obtain ⟨middle, rexRun, rexEffect, rexHeap⟩ :=
    Register.rex_call rex .w64 config.destination config.base false wellFormed args
  have middleInputs := inputs.empty wellFormed rexEffect
  have middleBacking := rexEffect.empty_preserves_entry wellFormed backing
  let scope := middle.bindLocal 8 (.signed .i32 config.initial)
  have scopeWF := bindLocal_preserves_well_formed middle 8 (.signed .i32 config.initial) rexEffect.wellFormed
  have scopeBacking := ((bindLocal_effect middle 8 (.signed .i32 config.initial)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry rexEffect.wellFormed middleBacking) (by simp [CellSet.empty])).trans middleBacking
  obtain ⟨extended, extendRun, saved, extendEffect, extendHeap⟩ := extend_rex (program := program.core) config rexEffect.wellFormed middleInputs
  have extendedBacking := extendEffect.preserves_entry scopeWF scopeBacking
    (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry rexEffect.wellFormed middleBacking))
  have resources : FixedResources extended cell start values :=
    ⟨extendEffect.wellFormed, saved.found ⟨0, by simp⟩, saved.found ⟨2, by simp⟩, extendedBacking⟩
  obtain ⟨written, writeRun, contents, writeEffect, writeHeap⟩ := write word config resources saved
    (config.saved_not_array cell values.length capacity start) room bounded
  have close := CellEffect.closeLocal middle 8 (.signed .i32 config.initial) rexEffect.wellFormed
    ((extendEffect.weaken CellSet.subset_union_left).trans (writeEffect.weaken CellSet.subset_union_right))
  have narrow : CellEffect (CellSet.singleton cell) middle (restoreLocals middle written) := by
    apply close.narrow
    intro changed old member
    rcases member with temporary | output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
    · exact output
  exact ⟨restoreLocals middle written, executesLetLocal rexRun (executesSequence extendRun writeRun),
    contents, (rexEffect.weaken CellSet.empty_subset).trans narrow,
    rexHeap.trans (HeapFrame.closeLocal middle 8 (.signed .i32 config.initial) (extendHeap.trans writeHeap))⟩

/-- Execute the actual Lanius validation, reservation, REX construction,
four header stores and signed disp32 store. No byte-output premise or
output validator appears in this source-linked contract. -/
theorem succeeds (checked : Source.Indexed.Checked program valid rex fits word) (config : Config)
    (capacity start : Nat) (wellFormed : StateWellFormed before)
    (room : start + 8 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (config.arguments (.slice i32 cell [] 0 values.length) capacity start) before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + 8 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (config.written values start))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 8 =>
    (config.arguments (.slice i32 cell [] 0 values.length) capacity start).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := config.arguments (.slice i32 cell [] 0 values.length) capacity start)
    calleeWF (fun index => enterCall_parameterBindings_matches wellFormed index)
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨guarded, guardRun, guardedInputs, guardEffect, guardHeap⟩ := valid_guard checked config calleeWF inputs
  obtain ⟨reservedState, reserveRun, reserveEffect, reserveHeap⟩ := fixed_guard fits capacity start 8 guardEffect.wellFormed
    (Int.ofNat_le.mpr bounded) (guardedInputs.found ⟨1, by simp⟩) (guardedInputs.found ⟨2, by simp⟩)
  have good : reserved capacity start 8 = true := by simp only [reserved, decide_eq_true_eq]; omega
  change Evaluates program.core guarded (fixedGuard fits.source.function.id 8)
    (.boolean (!reserved capacity start 8)) reservedState at reserveRun
  rw [good] at reserveRun
  have reserveInputs := guardedInputs.empty guardEffect.wellFormed reserveEffect
  have reserveBacking := reserveEffect.empty_preserves_entry guardEffect.wellFormed
    (guardEffect.empty_preserves_entry calleeWF calleeBacking)
  obtain ⟨completed, emitRun, contents, emitEffect, emitHeap⟩ := after_rex rex word config capacity start
    reserveEffect.wellFormed reserveInputs reserveBacking (by omega) (by omega)
  have bodyRun : Executes program.core callee (Source.Indexed.body valid.source.function.id rex.source.function.id
      fits.source.function.id word.source.function.id checked.rsp)
      (.returned (some (.signed .i32 (start + 8 : Nat)))) completed :=
    executesSequence (executesIfFalse guardRun (executesSkip _ _))
    (executesSequence (executesIfFalse reserveRun (executesSkip _ _)) emitRun)
  have effect := ((guardEffect.trans reserveEffect).weaken CellSet.empty_subset).trans emitEffect
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl bodyRun effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2,
    HeapFrame.closeCall before params ((guardHeap.trans reserveHeap).trans emitHeap)⟩

/-- Insufficient capacity rejects before touching output, including an
invalid output value. Validation helpers only allocate private locals. -/
theorem rejects_capacity (checked : Source.Indexed.Checked program valid rex fits word) (config : Config)
    (output : Value) (capacity start : Int) (wellFormed : StateWellFormed before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 8 = false)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (config.arguments output capacity start) before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (-1)) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 8 => (config.arguments output capacity start).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := config.arguments output capacity start)
    calleeWF (fun index => enterCall_parameterBindings_matches wellFormed index)
  obtain ⟨guarded, guardRun, guardedInputs, guardEffect, guardHeap⟩ := valid_guard checked config calleeWF inputs
  obtain ⟨after, reserveRun, reserveEffect, reserveHeap⟩ := fixed_guard fits capacity start 8 guardEffect.wellFormed
    bounded (guardedInputs.found ⟨1, by simp⟩) (guardedInputs.found ⟨2, by simp⟩)
  change Evaluates program.core guarded (fixedGuard fits.source.function.id 8)
    (.boolean (!reserved capacity start 8)) after at reserveRun
  rw [bad] at reserveRun
  have negative : Evaluates program.core after negativeOne (.signed .i32 (-1)) after := by
    apply evaluatesUnary (show Evaluates program.core after (number 1) (.signed .i32 1) after from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  have run : Executes program.core callee (Source.Indexed.body valid.source.function.id rex.source.function.id
      fits.source.function.id word.source.function.id checked.rsp) (.returned (some (.signed .i32 (-1)))) after :=
    executesSequence (executesIfFalse guardRun (executesSkip _ _))
      (executesSequenceReturned (executesIfTrue reserveRun (executesSequenceReturned (executesReturnValue negative))))
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run (guardEffect.trans reserveEffect)
  exact ⟨restoreLocals before after, called.1, called.2, HeapFrame.closeCall before params (guardHeap.trans reserveHeap)⟩

theorem Config.emission (config : Config) (room : start + 8 ≤ values.length) :
    byteSlice (config.written values start) start 8 = config.bytes := by
  exact writtenHeaderWord_byteSlice config.header config.displacement (by simpa using room)

theorem Config.frame (config : Config) {index start : Nat} {values : List Int}
    (outside : index < start ∨ start + 8 ≤ index) :
    (config.written values start)[index]? = values[index]? := by
  rw [Config.written, writtenWord_frame (by omega), writtenBytes_frame (by simp only [Config.header_length]; omega)]

def sliceAddress : Config := ⟨0, 11, 0, 2, 0, by decide⟩

/-- Source-to-byte-to-machine connection for the LEA used by checked slice
indexing. The complete guard/descriptor sequence is proved in Machine.Index;
its other source emitters and recursive composition remain separate work. -/
theorem slice_address_emits (checked : Source.Indexed.Checked program valid rex fits word)
    (capacity start : Nat) (wellFormed : StateWellFormed before)
    (room : start + 8 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (sliceAddress.arguments (.slice i32 cell [] 0 values.length) capacity start) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + 8 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values emitted)) } ∧
      byteSlice emitted start 8 = Machine.Index.address.bytes ∧
      (∀ machine, Machine.CodeAt machine.memory machine.rip (byteSlice emitted start 8) →
        Machine.Step machine (machine.address64 0 11 (some 0) 2 0 8)) ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + 8 ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨after, run, contents, effect, heap⟩ := succeeds checked sliceAddress capacity start
    wellFormed room storage bounded backing argumentsResult
  have bytes : byteSlice (sliceAddress.written values start) start 8 = Machine.Index.address.bytes := by
    rw [sliceAddress.emission (by omega)]
    rfl
  refine ⟨after, sliceAddress.written values start, run, contents, bytes, ?_,
    sliceAddress.written_length values, fun index outside => sliceAddress.frame outside, effect, heap⟩
  intro machine loaded
  rw [bytes] at loaded
  exact .decoded Machine.Index.address.bytes loaded Machine.Index.address.instruction 8
    Machine.Index.address.decoded rfl

end Lanius.X86.Encode.Indexed
