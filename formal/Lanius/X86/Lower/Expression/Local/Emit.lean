import Lanius.X86.Lower.Expression.Local.Branch
import Lanius.X86.Lower.Expression.Local.Input
import Lanius.X86.Lower.Expression.Literal.Emit

namespace Lanius.X86.Lower.Expression.Local

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def afterLocal (width : Register.Width) (workspace : List Int) (position start slot : Nat) : List Int :=
  (workspace.set 0 (position + 2 : Nat)).set 1 (start + (Value.Get.bytes width slot).length : Nat)

/-- The actual emitter dispatch for an initialized scalar local. Both transport
reads, the lexical lookup and the selected load emitter are executed. -/
theorem emit_body {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Local.Checked literal) (width : Register.Width)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (length position depth active stride binding slot capacity start : Nat) (key : Int)
    (inputCount : bindings.length = 9)
    (inputLocal : before.local? 0 = some (.slice i32 input [] 0 transport.length))
    (lengthLocal : before.local? 1 = some (.signed .i32 length))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (activeLocal : before.local? 5 = some (.signed .i32 active))
    (depthLocal : before.local? 6 = some (.signed .i32 depth))
    (current : workspace[0]? = some (position : Int)) (cursor : workspace[1]? = some (start : Int))
    (healthy : workspace[4]? = some 0) (depthBound : depth < 512)
    (readable : position + 2 ≤ length) (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (tagWord : transport[position]? = some 1) (keyWord : transport[position + 1]? = some key)
    (correct : Frame.Lookup.Correct workspace active key (some binding))
    (tableRoom : 16 + active ≤ workspace.length) (tableBound : 16 + active ≤ 2147483647)
    (strideValue : workspace[12]? = some (stride : Int))
    (kindInside : 16 + stride + binding < workspace.length)
    (slotInside : 16 + stride * 2 + binding < workspace.length)
    (addressBound : 16 + stride * 2 + binding ≤ 2147483647)
    (kindValue : workspace[16 + stride + binding]? = some (Value.Get.kind width))
    (slotValue : workspace[16 + stride * 2 + binding]? = some (slot : Int))
    (slotBound : slot ≤ 1048576)
    (room : start + (Value.Get.bytes width slot).length ≤ capacity)
    (outputStorage : capacity ≤ values.length) (outputBound : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before
        (Source.Expression.Literal.emitBody literal.layout literal.constants literal.take.internal.source.function.id
          literal.immediate.source.function.id literal.stringBranch literal.otherBranches)
        (.returned (some (.signed .i32 (Value.Get.kind width)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterLocal width workspace position start slot))) } ∧
      Emission values start (Value.Get.bytes width slot) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have guard := Literal.entry_guard literal.constants ready depth start depthBound depthLocal workLocal cursor healthy
  have inputEntry := ready.entry 0 (by omega) inputLocal
  have lengthEntry := ready.entry 1 (by omega) lengthLocal
  have workEntry := ready.entry 2 (by omega) workLocal
  have outputEntry := ready.entry 3 (by omega) outputLocal
  have capacityEntry := ready.entry 4 (by omega) capacityLocal
  have activeEntry := ready.entry 5 (by omega) activeLocal
  have within : 0 < workspace.length := by
    by_cases inside : 0 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  obtain ⟨tagState, tagRun, afterTag, tagEffect, tagHeap⟩ := ready.take literal.take length position
    inputLocal lengthLocal workLocal current (by omega) storage bounded tagWord
  let tagged := tagState.bindLocal 9 (.signed .i32 1)
  have taggedReady : Literal.Ready tagged (bindings ++ [.signed .i32 1]) tagged.nextCell input output work
      transport values (workspace.set 0 (position + 1 : Nat)) := by
    simpa only [inputCount] using afterTag.push (.signed .i32 1) (by intro elements same; cases same)
  have tagLocal := taggedReady.read (value := .signed .i32 1) 9 (by simp [List.getElem?_append, inputCount])
  have valueConstant := literal.constants.value.evaluates (before := tagged)
  rw [literal.constants.values.2.2.2.1] at valueConstant
  have valueTest : Evaluates emitters.pack.program.core tagged
      (.binary .equal (read 9) (.constant literal.constants.value.id)) (.boolean false) tagged :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ tagLocal) valueConstant rfl
  have localConstant := checked.tag.evaluates (before := tagged)
  rw [checked.values.1] at localConstant
  have localTest : Evaluates emitters.pack.program.core tagged
      (Source.Expression.Local.selected checked.tag.id) (.boolean true) tagged :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ tagLocal) localConstant rfl
  obtain ⟨completed, emitted, branchRun, finalOutput, finalWork, emission, branchEffect, branchHeap⟩ :=
    branch checked width taggedReady length (position + 1) active stride binding slot capacity start key
      (by simp [inputCount]) (by simp [inputCount])
      (taggedReady.read 0 ((List.getElem?_append_left (by omega)).trans inputEntry))
      (taggedReady.read 1 ((List.getElem?_append_left (by omega)).trans lengthEntry))
      (by simpa only [List.length_set] using taggedReady.read 2 ((List.getElem?_append_left (by omega)).trans workEntry))
      (taggedReady.read 3 ((List.getElem?_append_left (by omega)).trans outputEntry))
      (taggedReady.read 4 ((List.getElem?_append_left (by omega)).trans capacityEntry))
      (taggedReady.read 5 ((List.getElem?_append_left (by omega)).trans activeEntry))
      (List.getElem?_set_self within)
      (by simpa only [List.getElem?_set_ne (by decide : 0 ≠ 1)] using cursor)
      (by omega) storage bounded keyWord (lookup_after_input correct (position + 1 : Nat))
      (by simpa only [List.length_set] using tableRoom) tableBound
      (by simpa only [List.getElem?_set_ne (by decide : 0 ≠ 12)] using strideValue)
      (by simpa only [List.length_set] using kindInside) (by simpa only [List.length_set] using slotInside) addressBound
      (by simpa only [List.getElem?_set_ne (by omega : 0 ≠ 16 + stride + binding)] using kindValue)
      (by simpa only [List.getElem?_set_ne (by omega : 0 ≠ 16 + stride * 2 + binding)] using slotValue)
      slotBound room outputStorage outputBound
  have restRun : Executes emitters.pack.program.core tagged literal.otherBranches (.returned (some (.signed .i32 (Value.Get.kind width)))) completed := by
    rw [checked.bodyExact]
    exact executesSequenceReturned (executesIfTrue (elseBranch := .skip) localTest branchRun)
  have dispatch := executesSequence (executesIfFalse
    (thenBranch := Source.Expression.Literal.literalBody literal.layout literal.constants
      literal.take.internal.source.function.id literal.immediate.source.function.id literal.stringBranch)
    valueTest (executesSkip _ _)) restRun
  refine ⟨_, emitted, executesSequence (executesIfFalse guard (executesSkip _ _))
    (executesLetLocal (id := 9) (type := i32) tagRun dispatch), finalOutput, ?_, emission,
    tagEffect.trans (CellEffect.closeLocal tagState 9 (.signed .i32 1) afterTag.wellFormed branchEffect),
    tagHeap.trans (HeapFrame.closeLocal tagState 9 (.signed .i32 1) branchHeap)⟩
  change completed.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterLocal width workspace position start slot))) }
  simpa only [afterLocal, List.set_set, Nat.add_assoc, Nat.reduceAdd] using finalWork

/-- A proved call to the actual emit_expression function, with no source
execution premise for the initialized scalar-local case. -/
theorem emit_call {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Local.Checked literal) (c : Context) (valid : c.Valid)
    (binding : Binding c width key slot) (source : Syntax c key) :
    c.Emits emitters.pack.program.core literal.emitter.source.function.id (Value.Get.kind width)
      (Value.Get.bytes width slot) (afterLocal width c.workspace c.position c.start slot) := by
  constructor
  intro caller arguments before wellFormed evaluated memory
  let params := parameterBindings (fun index : Fin 9 => c.arguments.get index)
  have ready := Literal.Ready.enterCall (bindings := c.arguments) wellFormed memory.plain
    memory.inputBacking memory.outputBacking memory.workBacking memory.inputOutput memory.inputWork memory.outputWork
  have reads := ready.locals.found
  obtain ⟨completed, emitted, run, finalOutput, finalWork, emission, effect, heap⟩ := emit_body checked width ready
    c.length c.position c.depth binding.active binding.stride binding.index slot c.capacity c.start key rfl
    (reads ⟨0, by simp [Context.arguments, Literal.inputValues]⟩)
    (reads ⟨1, by simp [Context.arguments, Literal.inputValues]⟩)
    (reads ⟨2, by simp [Context.arguments, Literal.inputValues]⟩)
    (reads ⟨3, by simp [Context.arguments, Literal.inputValues]⟩)
    (reads ⟨4, by simp [Context.arguments, Literal.inputValues]⟩)
    (by rw [← binding.activeValue]; exact reads ⟨5, by simp [Context.arguments, Literal.inputValues]⟩)
    (reads ⟨6, by simp [Context.arguments, Literal.inputValues]⟩)
    valid.current valid.cursor valid.healthy valid.depthBound source.readable valid.storage valid.bounded
    source.tagWord source.keyWord binding.correct binding.tableRoom binding.tableBound binding.strideValue
    binding.kindInside binding.slotInside binding.addressBound binding.kindValue binding.slotValue binding.slotBound
    binding.room valid.outputStorage valid.outputBound
  have called := literal.emitter.call wellFormed evaluated (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, ⟨emitted, finalOutput, finalWork, emission, trivial⟩,
    called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Lower.Expression.Local
