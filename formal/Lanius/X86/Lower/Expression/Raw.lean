import Lanius.X86.Lower.Expression.Raw.Entry
import Lanius.X86.Lower.Expression.Raw.Body
import Lanius.X86.Lower.Expression.Raw.Operands
import Lanius.X86.Lower.Expression.Wrapper

namespace Lanius.X86.Lower.Expression.Raw

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Actual code for a raw slice whose pointer is an initialized pointer local
and whose length is an i32 literal. The signed guard is emitted even when the
literal is negative; source compilation does not assume runtime success. -/
def bytes (slot top : Nat) (low : Int) : List UInt8 :=
  Value.Get.bytes .w64 slot ++ saveBytes top ++ tailBytes (top + 1) (Encode.Immediate.bytes low)

def capturedWorkspace (workspace : List Int) (position start slot top peak : Nat) : List Int :=
  workspaceAfter (Local.afterLocal .w64 (workspace.set 0 (position + 1 : Nat)) (position + 1) start slot)
    top peak (start + (Value.Get.bytes .w64 slot).length + (saveBytes top).length)

def afterRaw (workspace : List Int) (position start slot top peak : Nat) (low : Int) : List Int :=
  (Literal.afterLiteral (capturedWorkspace workspace position start slot top peak) (position + 3)
    (start + (Value.Get.bytes .w64 slot).length + (saveBytes top).length)).set 1
      (start + (bytes slot top low).length : Nat)

theorem afterRaw_length : (afterRaw workspace position start slot top peak low).length = workspace.length := by
  simp only [afterRaw, Literal.afterLiteral, capturedWorkspace, workspaceAfter, Local.afterLocal,
    List.length_set, Frame.Allocate.updated_length]

theorem afterRaw_top (within : 6 < workspace.length) :
    (afterRaw workspace position start slot top peak low)[6]? = some ((top + 2 : Nat) : Int) := by
  simp only [afterRaw, Literal.afterLiteral, List.getElem?_set_ne (by decide : 1 ≠ 6),
    List.getElem?_set_ne (by decide : 0 ≠ 6)]
  exact workspaceAfter_top (by simpa only [Local.afterLocal, List.length_set] using within)

/-- Input and frame-table invariants, not compiler-execution premises. The
stream is RAW, LOCAL, key, VALUE, I32, low. Lookup remains the existing
rightmost lexical binding relation; no host-assigned slot is trusted. -/
structure Input (transport workspace values : List Int)
    (length position depth active stride binding slot capacity start top peak : Nat)
    (key : VarId) (low : Int) : Prop where
  current : workspace[0]? = some (position : Int)
  cursor : workspace[1]? = some (start : Int)
  healthy : workspace[4]? = some 0
  topFound : workspace[6]? = some (top : Int)
  watermark : workspace[2]? = some (peak : Int)
  ordered : top ≤ peak
  peakBound : peak ≤ Frame.Allocate.limit
  slotRoom : top + 2 ≤ Frame.Allocate.limit
  depthBound : depth + 1 < 512
  readable : position + 6 ≤ length
  storage : length ≤ transport.length
  bounded : length ≤ 2147483647
  tagWord : transport[position]? = some 15
  pointerTag : transport[position + 1]? = some 1
  keyWord : transport[position + 2]? = some (key : Int)
  literalTag : transport[position + 3]? = some 0
  literalKind : transport[position + 4]? = some 1
  lowWord : transport[position + 5]? = some low
  correct : Frame.Lookup.Correct workspace active key (some binding)
  tableRoom : 16 + active ≤ workspace.length
  tableBound : 16 + active ≤ 2147483647
  strideValue : workspace[12]? = some (stride : Int)
  kindInside : 16 + stride + binding < workspace.length
  slotInside : 16 + stride * 2 + binding < workspace.length
  addressBound : 16 + stride * 2 + binding ≤ 2147483647
  kindValue : workspace[16 + stride + binding]? = some 4
  slotValue : workspace[16 + stride * 2 + binding]? = some (slot : Int)
  slotBound : slot ≤ 1048576
  room : start + (bytes slot top low).length ≤ capacity
  outputStorage : capacity ≤ values.length
  outputBound : capacity ≤ 2147483647

variable {emitters : CheckedBuffer encoded sources}
  {literal : Source.Expression.Literal.Checked emitters}

/-- Execute the actual raw emitter branch with both recursive calls derived
from their concrete source rules. No OperandCall or Executes hypothesis is
required by this endpoint. -/
theorem emit_body (checked : Source.Expression.Raw.Checked literal)
    (localChecked : Source.Expression.Local.Checked literal)
    (length position depth active stride binding slot capacity start top peak : Nat)
    (key : VarId) (low : Int) (context contextLength : Value)
    (config : Input transport workspace values length position depth active stride binding slot capacity start top peak key low)
    (ready : Literal.Ready before
      (Literal.inputValues input work output transport.length workspace.length values.length
        length capacity depth (.signed .i32 active) context contextLength)
      frontier input output work transport values workspace) :
    ∃ after emitted,
      Executes emitters.pack.program.core before
        (Source.Expression.Literal.emitBody literal.layout literal.constants literal.take.internal.source.function.id
          literal.immediate.source.function.id literal.stringBranch literal.otherBranches)
        (.returned (some (.signed .i32 6))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (afterRaw workspace position start slot top peak low))) } ∧
      Emission values start (bytes slot top low) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have tableRoom := config.tableRoom
  have readable := config.readable
  have depthBound := config.depthBound
  have within : 6 < workspace.length := by omega
  apply emits_with_branch checked ready length position depth start 6 (bytes slot top low) rfl
    (ready.read 0 (by simp [Literal.inputValues])) (ready.read 1 (by simp [Literal.inputValues]))
    (ready.read 2 (by simp [Literal.inputValues])) (ready.read 6 (by simp [Literal.inputValues]))
    config.current config.cursor config.healthy (by omega) (by omega) config.storage config.bounded config.tagWord
  intro tagged tagFrontier entered tagFrame
  have tagReady : Literal.Ready tagged
      (Literal.inputValues input work output transport.length (workspace.set 0 (position + 1 : Nat)).length values.length
        length capacity depth (.signed .i32 active) context contextLength ++ [.signed .i32 15])
      tagFrontier input output work transport values (workspace.set 0 (position + 1 : Nat)) := by
    simpa only [List.length_set] using entered.ready
  have childPlain : ∀ value ∈ Literal.inputValues input work output transport.length
      (workspace.set 0 (position + 1 : Nat)).length values.length length capacity (depth + 1)
      (.signed .i32 active) context contextLength, ∀ elements, value ≠ .array elements := by
    intro value member elements
    simp only [Literal.inputValues, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    all_goals first | (solve | intro same; cases same) | (exact ready.plain _ (by simp [Literal.inputValues]) elements)
  let child : Context := {
    input := input, output := output, work := work,
    transport := transport, values := values, length := length, active := .signed .i32 active, capacity := capacity, start := start,
    workspace := workspace.set 0 (position + 1 : Nat), position := position + 1, depth := depth + 1,
    top := top, context := context, contextLength := contextLength }
  obtain ⟨pointerState, pointerRun, ⟨pointerValues, pointerOutput, pointerWork, pointerWindow, _⟩, pointerEffect, pointerHeap⟩ :=
    (Local.compiles (width := .w64) (key := key) (slot := slot) localChecked child
      ⟨entered.inputPosition, entered.codePosition, entered.healthy,
        by simpa only [child, List.getElem?_set_ne (by decide : 0 ≠ 6)] using config.topFound,
        config.depthBound, config.storage, config.bounded, config.outputStorage, config.outputBound⟩
      ⟨active, rfl, stride, binding, Local.lookup_after_input config.correct (position + 1 : Nat),
        by simpa only [child, List.length_set] using config.tableRoom, config.tableBound,
        by simpa only [child, List.getElem?_set_ne (by decide : 0 ≠ 12)] using config.strideValue,
        by simpa only [child, List.length_set] using config.kindInside,
        by simpa only [child, List.length_set] using config.slotInside, config.addressBound,
        by simpa only [child, Value.Get.kind, List.getElem?_set_ne (by omega : 0 ≠ 16 + stride + binding)] using config.kindValue,
        by simpa only [child, List.getElem?_set_ne (by omega : 0 ≠ 16 + stride * 2 + binding)] using config.slotValue,
        config.slotBound, by dsimp [child]; have room := config.room; simp only [bytes, List.length_append] at room; omega⟩
      ⟨by dsimp [child]; omega, config.pointerTag, by simpa only [child, Nat.add_assoc] using config.keyWord⟩).call
      tagReady.wellFormed
      (recurse_arguments checked length capacity depth (.signed .i32 active) context contextLength tagReady config.depthBound)
      ⟨childPlain, tagReady.inputBacking, tagReady.outputBacking, tagReady.workBacking,
        tagReady.inputOutput, tagReady.inputWork, tagReady.outputWork⟩
  let pointerWorkspace := Local.afterLocal .w64 (workspace.set 0 (position + 1 : Nat)) (position + 1) start slot
  have pointer : OperandCall checked 4 tagged pointerState output work start
      (workspace.set 0 (position + 1 : Nat)).length values pointerValues pointerWorkspace (Value.Get.bytes .w64 slot) :=
    ⟨pointerRun, pointerOutput, pointerWork, by simp only [pointerWorkspace, Local.afterLocal, List.length_set],
      by exact List.getElem?_set_self (by simpa only [List.length_set] using (show 1 < workspace.length by omega)),
      pointerWindow, pointerEffect, pointerHeap⟩
  apply body checked entered.ready top peak capacity start (Encode.Immediate.bytes low)
    (by simpa only [List.length_set] using pointer)
    (by simp [Literal.inputValues]) (by simpa [Literal.inputValues] using checked.fresh.1)
    (by simpa only [List.length_set] using tagReady.read 2 (by simp [Literal.inputValues]))
    (tagReady.read 3 (by simp [Literal.inputValues])) (tagReady.read 4 (by simp [Literal.inputValues]))
    (by simpa only [pointerWorkspace, Local.afterLocal, List.length_set] using within)
    (by simpa only [pointerWorkspace, Local.afterLocal, List.getElem?_set_ne (by decide : 1 ≠ 6),
      List.getElem?_set_ne (by decide : 0 ≠ 6)] using config.topFound)
    (by simpa only [pointerWorkspace, Local.afterLocal, List.getElem?_set_ne (by decide : 1 ≠ 2),
      List.getElem?_set_ne (by decide : 0 ≠ 2)] using config.watermark)
    config.ordered config.peakBound config.slotRoom config.room config.outputStorage config.outputBound
  intro prepared preparedValues preparedReady preparedFrame
  have preparedLength : preparedValues.length = values.length :=
    preparedReady.window.length.trans pointerWindow.length
  have preparedInput : Literal.Ready prepared
      (Literal.inputValues input work output transport.length
        (capturedWorkspace workspace position start slot top peak).length preparedValues.length
        length capacity depth (.signed .i32 active) context contextLength ++ [.signed .i32 15])
      tagFrontier input output work transport preparedValues (capturedWorkspace workspace position start slot top peak) := by
    simpa only [capturedWorkspace, workspaceAfter, pointerWorkspace, Local.afterLocal, List.length_set,
      Frame.Allocate.updated_length, preparedLength] using preparedReady.ready
  have preparedCurrent : (capturedWorkspace workspace position start slot top peak)[0]? = some ((position + 3 : Nat) : Int) := by
    simp only [capturedWorkspace, workspaceAfter, List.getElem?_set_ne (by decide : 1 ≠ 0),
      Frame.Allocate.updated_frame (by decide : 0 ≠ 6 ∧ 0 ≠ 2), Local.afterLocal]
    simpa only [Nat.add_assoc] using (List.getElem?_set_self
      (l := workspace.set 0 (position + 1 : Nat)) (a := ((position + 1 + 2 : Nat) : Int))
      (by simpa only [List.length_set] using (show 0 < workspace.length by omega)))
  have preparedHealthy : (capturedWorkspace workspace position start slot top peak)[4]? = some 0 := by
    simpa only [capturedWorkspace, workspaceAfter, List.getElem?_set_ne (by decide : 1 ≠ 4),
      Frame.Allocate.updated_frame (by decide : 4 ≠ 6 ∧ 4 ≠ 2), Local.afterLocal,
      List.getElem?_set_ne (by decide : 0 ≠ 4)] using config.healthy
  obtain ⟨recursed, child, childTop⟩ := Raw.literal checked length (position + 3) depth capacity
    (start + (Value.Get.bytes .w64 slot).length + (saveBytes top).length) low (top + 2 : Nat)
    (.signed .i32 active) context contextLength preparedInput preparedCurrent
    (workspaceAfter_cursor (by simpa only [Local.afterLocal, List.length_set] using within)) preparedHealthy
    (workspaceAfter_top (by simpa only [Local.afterLocal, List.length_set] using within))
    config.depthBound (by omega) config.storage config.bounded
    (by have room := config.room
        simp only [bytes, tailBytes, List.length_append, Encode.Immediate.bytes_length] at room
        omega)
    (by simpa only [preparedLength] using config.outputStorage) config.outputBound config.literalTag
    (by simpa only [Nat.add_assoc] using config.literalKind)
    (by simpa only [Nat.add_assoc] using config.lowWord)
  exact ⟨recursed, _, by simpa only [capturedWorkspace, workspaceAfter, pointerWorkspace, Local.afterLocal,
    List.length_set, Frame.Allocate.updated_length] using child⟩

/-- Call the actual internal emitter, deriving parameter entry, the concrete
raw branch, and caller restoration from authenticated source definitions. -/
theorem emit_call (checked : Source.Expression.Raw.Checked literal)
    (localChecked : Source.Expression.Local.Checked literal)
    (length position depth active stride binding slot capacity start top peak : Nat)
    (key : VarId) (low : Int) (context contextLength : Value)
    (config : Input transport workspace values length position depth active stride binding slot capacity start top peak key low)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ Literal.inputValues input work output transport.length workspace.length values.length
      length capacity depth (.signed .i32 active) context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (Literal.inputValues input work output transport.length workspace.length values.length length capacity depth
        (.signed .i32 active) context contextLength) before) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call literal.emitter.source.function.id arguments)
        (.signed .i32 6) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (afterRaw workspace position start slot top peak low))) } ∧
      Emission values start (bytes slot top low) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  let bindings := Literal.inputValues input work output transport.length workspace.length values.length
    length capacity depth (.signed .i32 active) context contextLength
  let params := parameterBindings (fun index : Fin 9 => bindings.get index)
  have ready := Literal.Ready.enterCall (bindings := bindings) wellFormed plain
    inputBacking outputBacking workBacking inputOutput inputWork outputWork
  obtain ⟨completed, emitted, run, finalOutput, finalWork, window, effect, heap⟩ :=
    emit_body checked localChecked length position depth active stride binding slot capacity start top peak
      key low context contextLength config ready
  have called := literal.emitter.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, emitted, called.1, finalOutput, finalWork, window,
    called.2, HeapFrame.closeCall before params heap⟩

/-- Complete source compiler endpoint for raw-slice(pointer-local, i32-literal).
Both recursive calls and all emitters are proved, rather than supplied as
execution hypotheses. Returning aggregate kind6 keeps TOP at entry TOP+2;
negative lengths compile to the same checked runtime rejection sequence. -/
theorem compiles (checked : Source.Expression.Raw.Checked literal)
    (localChecked : Source.Expression.Local.Checked literal)
    (length position depth active stride binding slot capacity start top peak : Nat)
    (key : VarId) (low : Int) (context contextLength : Value)
    (config : Input transport workspace values length position depth active stride binding slot capacity start top peak key low)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ Literal.inputValues input work output transport.length workspace.length values.length
      length capacity depth (.signed .i32 active) context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (Literal.inputValues input work output transport.length workspace.length values.length length capacity depth
        (.signed .i32 active) context contextLength) before) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call literal.wrapper.source.function.id arguments)
        (.signed .i32 6) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (afterRaw workspace position start slot top peak low))) } ∧
      Emission values start (bytes slot top low) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  let c : Context := {
    input := input, output := output, work := work, transport := transport, values := values, workspace := workspace,
    length := length, position := position, depth := depth, active := .signed .i32 active, capacity := capacity,
    start := start, top := top, context := context, contextLength := contextLength }
  have compiled := Wrapper.call literal c 6 (Emission values start (bytes slot top low))
    (afterRaw workspace position start slot top peak low) config.topFound afterRaw_length (by
      constructor
      intro caller arguments before wellFormed evaluated memory
      obtain ⟨after, emitted, run, finalOutput, finalWork, window, effect, heap⟩ :=
        emit_call checked localChecked length position depth active stride binding slot capacity start top peak
          key low context contextLength config wellFormed memory.plain memory.inputBacking memory.outputBacking memory.workBacking
          memory.inputOutput memory.inputWork memory.outputWork evaluated
      exact ⟨after, run, ⟨emitted, finalOutput, finalWork, window⟩, effect, heap⟩)
  obtain ⟨after, run, ⟨emitted, finalOutput, finalWork, window⟩, effect, heap⟩ :=
    compiled.call wellFormed argumentsResult ⟨plain, inputBacking, outputBacking, workBacking, inputOutput, inputWork, outputWork⟩
  exact ⟨after, emitted, run, finalOutput, finalWork, window, effect, heap⟩

end Lanius.X86.Lower.Expression.Raw
