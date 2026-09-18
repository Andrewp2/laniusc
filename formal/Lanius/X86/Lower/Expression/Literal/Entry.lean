import Lanius.X86.Lower.Expression.Literal.State
import Lanius.Automation.Execute

namespace Lanius.X86.Lower.Expression.Literal

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

theorem entry_guard (constants : Source.Expression.Literal.Constants program)
    (ready : Ready before bindings frontier input output work transport emitted workspace)
    (depth start : Nat) (depthBound : depth < 512)
    (depthLocal : before.local? 6 = some (.signed .i32 depth))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0) :
    Evaluates program before (Source.Expression.Literal.entryGuard constants) (.boolean false) before := by
  have maximum := constants.maxDepth.evaluates (before := before)
  rw [constants.values.1] at maximum
  have depthTest : Evaluates program before (.binary .greaterEqual (Source.read 6) (.constant constants.maxDepth.id))
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ depthLocal) maximum
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have failed := ready.field constants.failed 4 constants.values.2.1 workLocal healthy
  have failureTest : Evaluates program before (.binary .notEqual (Source.Expression.Literal.field constants.failed.id) (number 0))
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) failed
      (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    rfl
  have code := ready.field constants.code 1 constants.values.2.2.1 workLocal cursor
  have codeTest : Evaluates program before (.binary .less (Source.Expression.Literal.field constants.code.id) (number 0))
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) code
      (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  exact evaluatesPureLogicalOr (evaluatesPureLogicalOr depthTest failureTest) codeTest

/-- Precisely the valid three-word scalar literals; Boolean payloads are 0/1. -/
def Scalar32 (kind low : Int) : Prop := kind = 1 ∨ kind = 2 ∧ (low = 0 ∨ low = 1)

theorem Scalar32.width (valid : Scalar32 kind low) : kind = 1 ∨ kind = 2 :=
  valid.imp id And.left

theorem literal_guards (checked : Source.Expression.Literal.Checked emitters) {kind low : Int}
    (valid : Scalar32 kind low) (kindLocal : before.local? 10 = some (.signed .i32 kind))
    (lowLocal : before.local? 11 = some (.signed .i32 low)) :
    Evaluates emitters.pack.program.core before
      (.binary .equal (read 10) (.constant checked.layout.string.id)) (.boolean false) before ∧
    Evaluates emitters.pack.program.core before
      (Source.Expression.Literal.invalidKind checked.layout checked.constants) (.boolean false) before := by
  have string := checked.layout.string.evaluates (before := before)
  have signed := checked.layout.signed.evaluates (before := before)
  have pointer := checked.constants.pointer.evaluates (before := before)
  have boolean := checked.layout.boolean.evaluates (before := before)
  rw [checked.layout.values.2.2.2.1] at string
  rw [checked.layout.values.1] at signed
  rw [checked.constants.values.2.2.2.2.1] at pointer
  rw [checked.layout.values.2.1] at boolean
  rcases valid with rfl | ⟨rfl, rfl | rfl⟩ <;> constructor <;>
    core_eval [Source.Expression.Literal.invalidKind]

/-- Dispatch the real compiler through its entry checks and all three
transport reads to the scalar-literal tail. The supplied tail theorem is a
composition boundary, not an assumption about the recursive expression
compiler: the final literal theorem instantiates it with proved emission. -/
theorem emits_with_tail (checked : Source.Expression.Literal.Checked emitters) {kind : Int}
    (ready : Ready before bindings frontier input output work transport emitted workspace)
    (length position depth start : Nat) (low : Int) (scalar : Scalar32 kind low) (inputCount : bindings.length = 9)
    (inputLocal : before.local? 0 = some (.slice i32 input [] 0 transport.length))
    (lengthLocal : before.local? 1 = some (.signed .i32 length))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (depthLocal : before.local? 6 = some (.signed .i32 depth))
    (current : workspace[0]? = some (position : Int))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some kind)
    (lowWord : transport[position + 2]? = some low)
    (tail : ∀ valueBound frontier',
      Ready valueBound (bindings ++ [.signed .i32 0] ++ [.signed .i32 kind] ++ [.signed .i32 low])
        frontier' input output work transport emitted (workspace.set 0 (position + 3 : Nat)) →
      ∃ completed, Executes emitters.pack.program.core valueBound
          (Source.Expression.Literal.literalTail checked.layout checked.constants checked.take.internal.source.function.id
            checked.immediate.source.function.id) (.returned (some (.signed .i32 kind))) completed ∧
        completed.cellEntry? output = some { id := output, value := some (.array (signedI32Values finalOutput)) } ∧
        completed.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
        CellEffect (writes output work) valueBound completed ∧ HeapFrame valueBound completed) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.emitBody checked.layout checked.constants checked.take.internal.source.function.id
          checked.immediate.source.function.id checked.stringBranch checked.otherBranches)
        (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values finalOutput)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have guard := entry_guard checked.constants ready depth start depthBound depthLocal workLocal cursor healthy
  have inputEntry := ready.entry 0 (by omega) inputLocal
  have lengthEntry := ready.entry 1 (by omega) lengthLocal
  have workEntry := ready.entry 2 (by omega) workLocal
  have within : 0 < workspace.length := by
    by_cases inside : 0 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  obtain ⟨tagState, tagRun, afterTag, tagEffect, tagHeap⟩ := ready.take checked.take length position
    inputLocal lengthLocal workLocal current (by omega) storage bounded tagWord
  let tagged := tagState.bindLocal 9 (.signed .i32 0)
  have taggedReady : Ready tagged (bindings ++ [.signed .i32 0]) tagged.nextCell input output work
      transport emitted (workspace.set 0 (position + 1 : Nat)) := by
    simpa only [inputCount] using afterTag.push (.signed .i32 0) (by intro elements same; cases same)
  have taggedInput := taggedReady.read 0 ((List.getElem?_append_left (by omega)).trans inputEntry)
  have taggedLength := taggedReady.read 1 ((List.getElem?_append_left (by omega)).trans lengthEntry)
  have taggedWork := taggedReady.read 2 ((List.getElem?_append_left (by omega)).trans workEntry)
  have tagLocal := taggedReady.read (value := .signed .i32 0) 9 (by simp [List.getElem?_append, inputCount])
  have tagConstant := checked.constants.value.evaluates (before := tagged)
  rw [checked.constants.values.2.2.2.1] at tagConstant
  have tagTest : Evaluates emitters.pack.program.core tagged
      (.binary .equal (read 9) (.constant checked.constants.value.id)) (.boolean true) tagged :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ tagLocal) tagConstant rfl
  obtain ⟨kindState, kindRun, afterKind, kindEffect, kindHeap⟩ := taggedReady.take checked.take length (position + 1)
    taggedInput taggedLength (by simpa only [List.length_set] using taggedWork)
    (List.getElem?_set_self within) (by omega) storage bounded kindWord
  let kinded := kindState.bindLocal 10 (.signed .i32 kind)
  have kindedReady : Ready kinded (bindings ++ [.signed .i32 0] ++ [.signed .i32 kind]) kinded.nextCell input output work
      transport emitted (workspace.set 0 (position + 2 : Nat)) := by
    simpa only [List.length_append, List.length_singleton, inputCount, List.set_set, Nat.add_assoc] using
      afterKind.push (.signed .i32 kind) (by intro elements same; cases same)
  have kindedInput := kindedReady.read 0 ((List.getElem?_append_left (by simp only [List.length_append, List.length_singleton]; omega)).trans
    ((List.getElem?_append_left (by omega)).trans inputEntry))
  have kindedLength := kindedReady.read 1 ((List.getElem?_append_left (by simp only [List.length_append, List.length_singleton]; omega)).trans
    ((List.getElem?_append_left (by omega)).trans lengthEntry))
  have kindedWork := kindedReady.read 2 ((List.getElem?_append_left (by simp only [List.length_append, List.length_singleton]; omega)).trans
    ((List.getElem?_append_left (by omega)).trans workEntry))
  obtain ⟨valueState, valueRun, afterValue, valueEffect, valueHeap⟩ := kindedReady.take checked.take length (position + 2)
    kindedInput kindedLength (by simpa only [List.length_set] using kindedWork)
    (List.getElem?_set_self within) (by omega) storage bounded lowWord
  let valued := valueState.bindLocal 11 (.signed .i32 low)
  have valuedReady : Ready valued (bindings ++ [.signed .i32 0] ++ [.signed .i32 kind] ++ [.signed .i32 low])
      valued.nextCell input output work transport emitted (workspace.set 0 (position + 3 : Nat)) := by
    simpa only [List.length_append, List.length_singleton, inputCount, List.set_set, Nat.add_assoc] using
      afterValue.push (.signed .i32 low) (by intro elements same; cases same)
  have kindLocal := valuedReady.read (value := .signed .i32 kind) 10 (by simp [List.getElem?_append, inputCount])
  obtain ⟨stringTest, invalidTest⟩ := literal_guards checked scalar kindLocal
    (valuedReady.read 11 (by simp [List.getElem?_append, inputCount]))
  obtain ⟨completed, tailRun, finalOut, finalWork, tailEffect, tailHeap⟩ := tail valued valued.nextCell valuedReady
  have finish := executesSequence (executesIfFalse (thenBranch := checked.stringBranch) stringTest (executesSkip _ _))
    (executesSequence (executesIfFalse (thenBranch := returned negativeOne) invalidTest (executesSkip _ _)) tailRun)
  have lowScope := executesLetLocal (id := 11) (type := i32) valueRun finish
  have kindScope := executesLetLocal (id := 10) (type := i32) kindRun lowScope
  have lowEffect := valueEffect.trans (CellEffect.closeLocal valueState 11 (.signed .i32 low)
    afterValue.wellFormed tailEffect)
  have lowHeap := valueHeap.trans (HeapFrame.closeLocal valueState 11 (.signed .i32 low) tailHeap)
  have kindFrame := kindEffect.trans (CellEffect.closeLocal kindState 10 (.signed .i32 kind) afterKind.wellFormed lowEffect)
  have kindFrameHeap := kindHeap.trans (HeapFrame.closeLocal kindState 10 (.signed .i32 kind) lowHeap)
  have complete := executesLetLocal (id := 9) (type := i32) tagRun
    (executesSequenceReturned (second := checked.otherBranches) (executesIfTrue (elseBranch := .skip) tagTest kindScope))
  exact ⟨_, executesSequence (executesIfFalse guard (executesSkip _ _)) complete,
    finalOut, finalWork, tagEffect.trans (CellEffect.closeLocal tagState 9 (.signed .i32 0) afterTag.wellFormed kindFrame),
    tagHeap.trans (HeapFrame.closeLocal tagState 9 (.signed .i32 0) kindFrameHeap)⟩

end Lanius.X86.Lower.Expression.Literal
