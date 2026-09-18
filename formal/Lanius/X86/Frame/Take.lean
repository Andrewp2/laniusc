import Lanius.X86.Source.Constant
import Lanius.X86.Buffer.Reservation
import Lanius.X86.Buffer.Locals

namespace Lanius.X86.Source.Take

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) := [(0, .slice i32), (1, i32), (2, .slice i32)]
def field (id : ConstantId) : Expr := .index (read 2) (.constant id)
def assign (id : ConstantId) (right : Expr) : Stmt :=
  .expression (.assign .set (.index (.local 2) (.constant id)) right)
def guard : Expr := .binary .logicalOr (.binary .less (read 3) (number 0))
  (.binary .greaterEqual (read 3) (read 1))
def body (input failed : ConstantId) : Stmt :=
  .letLocal 3 i32 (field input)
    (.sequence (.ifThenElse guard (.sequence (assign failed (number 1)) (returned (number 0))) .skip)
      (.sequence (assign input (.binary .add (read 3) (number 1)))
        (returned (.index (read 0) (read 3)))))

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  input : IntegerConstant program.core
  failed : IntegerConstant program.core
  values : input.value = 0 ∧ failed.value = 4
  internal : Extraction.Source.CheckedInternal program ["backend", "frame"] "take" parameters i32
    (body input.id failed.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (Checked program) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "frame"] "take"
  let some (.letLocal _ _ (.index _ (.constant inputId))
    (.sequence (.ifThenElse _ (.sequence (.expression (.assign _ (.index _ (.constant failedId)) _)) _) _) _)) :=
    source.function.body | none
  let input ← integerConstant? program.core inputId
  let failed ← integerConstant? program.core failedId
  if values : input.value = 0 ∧ failed.value = 4 then
    let internal ← Extraction.Source.checkInternal? program ["backend", "frame"] "take" parameters i32
      (body input.id failed.id)
    pure ⟨input, failed, values, internal⟩
  else none

end Lanius.X86.Source.Take

namespace Lanius.X86.Frame.Take

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def inputValues (input work : CellId) (inputLength length workLength : Nat) : List Value :=
  [.slice i32 input [] 0 inputLength, .signed .i32 length, .slice i32 work [] 0 workLength]

/-- One successful transport read from the actual Lanius reader. INPUT
advances once; the input array and every other workspace field are retained. -/
theorem body_success (checked : Source.Take.Checked program) (length position : Nat)
    (wellFormed : StateWellFormed before)
    (locals : Locals (inputValues input work values.length length workspace.length) frontier before)
    (distinct : input ≠ work)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[0]? = some (position : Int))
    (readable : position < length) (storage : length ≤ values.length) (bounded : length ≤ 2147483647)
    (word : values[position]? = some value) :
    ∃ after, Executes program.core before (Source.Take.body checked.input.id checked.failed.id)
        (.returned (some (.signed .i32 value))) after ∧
      after.cellEntry? input = some { id := input, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 0 (position + 1 : Nat)))) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  have workWithin : 0 < workspace.length := by
    by_cases inside : 0 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  have initialConstant := checked.input.evaluates (before := before)
  rw [checked.values.1] at initialConstant
  have initial : Evaluates program.core before (Source.Take.field checked.input.id) (.signed .i32 position) before := by
    have read := evaluatesSignedI32SliceIndex program.core before before before workspace (Source.read 2)
      (.constant checked.input.id) work 0 workWithin (local_evaluates _ (locals.found ⟨2, by simp [inputValues]⟩)) initialConstant workBacking
    have entry : workspace.get ⟨0, workWithin⟩ = (position : Int) := by
      simpa only [List.getElem?_eq_getElem workWithin, Option.some.injEq, List.get_eq_getElem] using current
    simpa only [entry, Source.Take.field] using read
  let entered := before.bindLocal 3 (.signed .i32 position)
  have enteredWF := bindLocal_preserves_well_formed before 3 (.signed .i32 position) wellFormed
  have enteredLocals := locals.bind (id := 3) wellFormed (by simp [inputValues]) (.signed .i32 position)
  have positionLocal := bindLocal_finds_local before 3 (.signed .i32 position) wellFormed
  have enteredInput := ((bindLocal_effect before 3 (.signed .i32 position)).oldCells input
    (StateWellFormed.cell_lt_next_of_entry wellFormed inputBacking) (by simp [CellSet.empty])).trans inputBacking
  have enteredWork := ((bindLocal_effect before 3 (.signed .i32 position)).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking
  have negative : Evaluates program.core entered (.binary .less (Source.read 3) (Source.number 0)) (.boolean false) entered := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ positionLocal)
      (show Evaluates program.core entered (Source.number 0) (.signed .i32 0) entered from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  have outside : Evaluates program.core entered (.binary .greaterEqual (Source.read 3) (Source.read 1)) (.boolean false) entered := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ positionLocal)
      (local_evaluates _ (enteredLocals.found ⟨1, by simp [inputValues]⟩))
    simp [inputValues, evalBinaryValue, evalSignedBinary]
    omega
  have guard : Evaluates program.core entered Source.Take.guard (.boolean false) entered :=
    evaluatesPureLogicalOr negative outside
  have increment := evaluatesNatI32Add (program := program.core) (local_evaluates _ positionLocal)
    (show Evaluates program.core entered (Source.number 1) (.signed .i32 1) entered from ⟨1, rfl⟩) (by omega : position + 1 ≤ 2147483647)
  have inputConstant := checked.input.evaluates (before := entered)
  rw [checked.values.1] at inputConstant
  obtain ⟨completed, store, completedWork, _, heap, effect⟩ := evaluatesFramedSliceStore program.core entered entered workspace 2
    (.constant checked.input.id) (.binary .add (Source.read 3) (Source.number 1)) work 0 (position + 1 : Nat)
    enteredWF workWithin (enteredLocals.found ⟨2, by simp [inputValues]⟩) inputConstant increment
    (CellEffect.refl (writes := CellSet.empty) enteredWF) (by simp [CellSet.empty]) enteredWork
  have completedInput := effect.preserves_entry enteredWF enteredInput distinct
  have completedInputLocal := effect.preserves_local_of_distinct_value enteredWF (enteredLocals.found ⟨0, by simp [inputValues]⟩)
    enteredWork (by intro same; cases same)
  have completedPosition := effect.preserves_local_of_distinct_value enteredWF positionLocal enteredWork (by intro same; cases same)
  have returnedWord : Evaluates program.core completed (.index (Source.read 0) (Source.read 3)) (.signed .i32 value) completed := by
    have read := evaluatesSignedI32SliceIndex program.core completed completed completed values (Source.read 0) (Source.read 3)
      input position (by omega) (local_evaluates _ completedInputLocal) (local_evaluates _ completedPosition) completedInput
    have entry : values.get ⟨position, by omega⟩ = value := by
      simpa only [List.getElem?_eq_getElem (show position < values.length by omega), Option.some.injEq, List.get_eq_getElem] using word
    simpa only [entry] using read
  exact ⟨restoreLocals before completed,
    executesLetLocal initial (executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequence (executesExpression store) (executesSequenceReturned (executesReturnValue returnedWord)))),
    completedInput, completedWork, CellEffect.closeLocal before 3 (.signed .i32 position) wellFormed effect,
    HeapFrame.closeLocal before 3 (.signed .i32 position) heap⟩

theorem succeeds (checked : Source.Take.Checked program) (length position : Nat)
    (wellFormed : StateWellFormed before) (distinct : input ≠ work)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[0]? = some (position : Int))
    (readable : position < length) (storage : length ≤ values.length) (bounded : length ≤ 2147483647)
    (word : values[position]? = some value)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputValues input work values.length length workspace.length) before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id arguments) (.signed .i32 value) after ∧
      after.cellEntry? input = some { id := input, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 0 (position + 1 : Nat)))) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 3 => (inputValues input work values.length length workspace.length).get index)
  have initialWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have initialLocals := Locals.ofReads (values := inputValues input work values.length length workspace.length) initialWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have initialInput := ((enterCall_effect before params).oldCells input
    (StateWellFormed.cell_lt_next_of_entry wellFormed inputBacking) (by simp [CellSet.empty])).trans inputBacking
  have initialWork := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking
  obtain ⟨completed, run, finalInput, finalWork, effect, heap⟩ := body_success checked length position initialWF initialLocals
    distinct initialInput initialWork current readable storage bounded word
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, finalInput, finalWork, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Frame.Take
