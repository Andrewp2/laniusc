import Lanius.X86.Lower.Expression.Literal

namespace Lanius.X86.Lower.Expression.Literal.Capacity

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Output-capacity rejection still consumes the literal and returns its
kind. CODE becomes -1; no output byte is written and TOP is restored. -/
def afterFailure (workspace : List Int) (position : Nat) : List Int :=
  (workspace.set 0 (position + 3 : Nat)).set 1 (-1)

/-- Execute the real nested width/immediate calls and store their failure
result in CODE. The immediate helper returns before touching output. -/
theorem emit (checked : Source.Expression.Literal.Checked emitters) {kind : Int}
    (capacity start : Nat) (low : Int) (narrow : kind = 1 ∨ kind = 2)
    (ready : Ready before bindings frontier input output work transport values workspace)
    (workValue : bindings[2]? = some (.slice i32 work [] 0 workspace.length))
    (outputValue : bindings[3]? = some (.slice i32 output [] 0 values.length))
    (capacityValue : bindings[4]? = some (.signed .i32 capacity))
    (kindValue : bindings[10]? = some (.signed .i32 kind))
    (lowValue : bindings[11]? = some (.signed .i32 low))
    (highRead : before.local? 13 = some (.signed .i32 0))
    (cursor : workspace[1]? = some (start : Int))
    (bad : capacity < start + 5) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes emitters.pack.program.core before
        (.sequence (Source.Expression.Literal.assign checked.constants.code.id
          (.call checked.immediate.source.function.id [read 3, read 4, Source.Expression.Literal.field checked.constants.code.id,
            .call checked.layout.width.source.function.id [read 10], .constant checked.constants.rax.id, read 11, read 13]))
          (returned (read 10))) (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array
        (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array
        (signedI32Values (workspace.set 1 (-1)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have codeRead := ready.field checked.constants.code 1 checked.constants.values.2.2.1
    (ready.read 2 workValue) cursor
  obtain ⟨widthState, widthRun, widthEffect, widthHeap⟩ := Layout.width32 checked.layout narrow ready.wellFormed
    (.cons (local_evaluates _ (ready.read 10 kindValue)) (.nil _ _))
  have widthReady := ready.empty widthEffect
  have rax := checked.constants.rax.evaluates (before := widthState)
  rw [checked.constants.values.2.2.2.2.2.1] at rax
  have highAfter := widthEffect.preserves_local ready.wellFormed highRead (by simp [CellSet.empty])
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core before
      [read 3, read 4, Source.Expression.Literal.field checked.constants.code.id,
        .call checked.layout.width.source.function.id [read 10], .constant checked.constants.rax.id, read 11, read 13]
      (Encode.Immediate.inputs (.slice i32 output [] 0 values.length) capacity start low 0) widthState :=
    .cons (local_evaluates _ (ready.read 3 outputValue)) (.cons (local_evaluates _ (ready.read 4 capacityValue))
      (.cons codeRead (.cons widthRun (.cons rax (.cons (local_evaluates _ (widthReady.read 11 lowValue))
        (.cons (local_evaluates _ highAfter) (.nil _ _)))))))
  obtain ⟨written, rhs, outputEffect, outputHeap⟩ := Encode.Immediate.rejects_capacity32
    checked.immediate (.slice i32 output [] 0 values.length) capacity start low 0 widthEffect.wellFormed
      (by omega) (by simp only [reserved, decide_eq_false_iff_not]; omega) arguments
  have outputContents := outputEffect.empty_preserves_entry widthEffect.wellFormed widthReady.outputBacking
  have rhsEffect := (widthEffect.trans outputEffect).weaken (larger := CellSet.singleton output) CellSet.empty_subset
  have within : 1 < workspace.length := by
    by_cases inside : 1 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at cursor
      cases cursor
  have code := checked.constants.code.evaluates (before := before)
  rw [checked.constants.values.2.2.1] at code
  obtain ⟨after, update, workContents, effect, storeHeap, storeEffect⟩ := evaluatesFramedSliceStore
    emitters.pack.program.core before written workspace 2 (.constant checked.constants.code.id)
      (.call checked.immediate.source.function.id [read 3, read 4, Source.Expression.Literal.field checked.constants.code.id,
        .call checked.layout.width.source.function.id [read 10], .constant checked.constants.rax.id, read 11, read 13])
      work 1 (-1) ready.wellFormed within (ready.read 2 workValue) code rhs rhsEffect
      (Ne.symm ready.outputWork) ready.workBacking
  have finalOutput := storeEffect.preserves_entry rhsEffect.wellFormed outputContents ready.outputWork
  have finalReady := ready.frame effect finalOutput workContents
  exact ⟨after, executesSequence (executesExpression update)
    (executesSequenceReturned (executesReturnValue (local_evaluates _ (finalReady.read 10 kindValue)))),
    finalOutput, workContents, effect, widthHeap.trans (outputHeap.trans storeHeap)⟩


theorem tail (checked : Source.Expression.Literal.Checked emitters) {kind : Int}
    (capacity start : Nat) (low : Int) (narrow : kind = 1 ∨ kind = 2)
    (ready : Ready before bindings frontier input output work transport values workspace)
    (fresh : bindings.length ≤ 13)
    (workValue : bindings[2]? = some (.slice i32 work [] 0 workspace.length))
    (outputValue : bindings[3]? = some (.slice i32 output [] 0 values.length))
    (capacityValue : bindings[4]? = some (.signed .i32 capacity))
    (kindValue : bindings[10]? = some (.signed .i32 kind))
    (lowValue : bindings[11]? = some (.signed .i32 low))
    (cursor : workspace[1]? = some (start : Int))
    (bad : capacity < start + 5) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.literalTail checked.layout checked.constants
          checked.take.internal.source.function.id checked.immediate.source.function.id)
        (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array
        (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array
        (signedI32Values (workspace.set 1 (-1)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have enteredReady := ready.bind 13 fresh (.signed .i32 0)
  have high := bindLocal_finds_local before 13 (.signed .i32 0) ready.wellFormed
  obtain ⟨guarded, widthRun, widthEffect, widthHeap⟩ := Layout.width32 checked.layout narrow enteredReady.wellFormed
    (.cons (local_evaluates _ (enteredReady.read 10 kindValue)) (.nil _ _))
  have guard : Evaluates emitters.pack.program.core (before.bindLocal 13 (.signed .i32 0))
      (.binary .equal (.call checked.layout.width.source.function.id [read 10]) (number 64)) (.boolean false) guarded := by
    apply evaluatesEagerBinary (by decide) (by decide) widthRun
      (show Evaluates emitters.pack.program.core guarded (number 64) (.signed .i32 64) guarded from ⟨1, rfl⟩)
    rfl
  obtain ⟨completed, run, outputContents, workContents, effect, heap⟩ := emit checked capacity start low narrow
    (enteredReady.empty widthEffect) workValue outputValue capacityValue kindValue lowValue
    (widthEffect.preserves_local enteredReady.wellFormed high (by simp [CellSet.empty])) cursor bad bounded
  exact ⟨restoreLocals before completed,
    executesLetLocal (show Evaluates emitters.pack.program.core before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
      (executesSequence (executesIfFalse guard (executesSkip _ _)) run), outputContents, workContents,
    CellEffect.closeLocal before 13 (.signed .i32 0) ready.wellFormed
      ((widthEffect.weaken CellSet.empty_subset).trans effect),
    HeapFrame.closeLocal before 13 (.signed .i32 0) (widthHeap.trans heap)⟩


theorem emit_body (checked : Source.Expression.Literal.Checked emitters) {kind : Int}
    (ready : Ready before bindings frontier input output work transport values workspace)
    (length position depth capacity start : Nat) (low : Int) (scalar : Scalar32 kind low) (inputCount : bindings.length = 9)
    (inputLocal : before.local? 0 = some (.slice i32 input [] 0 transport.length))
    (lengthLocal : before.local? 1 = some (.signed .i32 length))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (depthLocal : before.local? 6 = some (.signed .i32 depth))
    (current : workspace[0]? = some (position : Int))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (bad : capacity < start + 5) (outputBound : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some kind)
    (lowWord : transport[position + 2]? = some low) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.emitBody checked.layout checked.constants checked.take.internal.source.function.id
          checked.immediate.source.function.id checked.stringBranch checked.otherBranches)
        (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array
        (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterFailure workspace position))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have workValue := ready.entry 2 (by omega) workLocal
  have outputValue := ready.entry 3 (by omega) outputLocal
  have capacityValue := ready.entry 4 (by omega) capacityLocal
  apply emits_with_tail checked ready length position depth start low scalar inputCount inputLocal lengthLocal
    workLocal depthLocal current cursor healthy depthBound readable storage bounded tagWord kindWord lowWord
  intro valueBound frontier' valueReady
  apply tail checked capacity start low scalar.width valueReady
  · simp [inputCount]
  · simpa [List.getElem?_append, inputCount] using workValue
  · simpa [List.getElem?_append, inputCount] using outputValue
  · simpa [List.getElem?_append, inputCount] using capacityValue
  · simp [inputCount]
  · simp [inputCount]
  · simpa [List.getElem?_set] using cursor
  · exact bad
  · exact outputBound


theorem emit_call (checked : Source.Expression.Literal.Checked emitters) {kind : Int}
    (length position depth capacity start : Nat) (low : Int) (scalar : Scalar32 kind low) (active context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (current : workspace[0]? = some (position : Int))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (bad : capacity < start + 5) (outputBound : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some kind)
    (lowWord : transport[position + 2]? = some low)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input work output transport.length workspace.length values.length length capacity depth active context contextLength) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.emitter.source.function.id arguments)
        (.signed .i32 kind) after ∧
      after.cellEntry? output = some { id := output, value := some (.array
        (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterFailure workspace position))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let bindings := inputValues input work output transport.length workspace.length values.length length capacity depth active context contextLength
  let params := parameterBindings (fun index : Fin 9 => bindings.get index)
  have ready := Literal.Ready.enterCall (bindings := bindings) wellFormed plain
    inputBacking outputBacking workBacking inputOutput inputWork outputWork
  obtain ⟨completed, run, finalOutput, finalWork, effect, heap⟩ := emit_body checked ready
    length position depth capacity start low scalar rfl (ready.locals.found ⟨0, by simp [bindings, inputValues]⟩)
    (ready.locals.found ⟨1, by simp [bindings, inputValues]⟩) (ready.locals.found ⟨2, by simp [bindings, inputValues]⟩)
    (ready.locals.found ⟨3, by simp [bindings, inputValues]⟩) (ready.locals.found ⟨4, by simp [bindings, inputValues]⟩)
    (ready.locals.found ⟨6, by simp [bindings, inputValues]⟩) current cursor healthy depthBound readable storage bounded
    bad outputBound tagWord kindWord lowWord
  have called := checked.emitter.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, finalOutput, finalWork, called.2, HeapFrame.closeCall before params heap⟩


theorem wrapper_body (checked : Source.Expression.Literal.Checked emitters)
    (length position depth capacity start : Nat) (low top : Int) (active context contextLength : Value)
    (ready : Ready before
      (inputValues input work output transport.length workspace.length values.length length capacity depth active context contextLength)
      frontier input output work transport values workspace)
    (current : workspace[0]? = some (position : Int))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0)
    (topFound : workspace[6]? = some top)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (bad : capacity < start + 5) (outputBound : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some 1)
    (lowWord : transport[position + 2]? = some low) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.body checked.layout checked.constants checked.emitter.source.function.id)
        (.returned (some (.signed .i32 1))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterFailure workspace position))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let c : Context := {
    input := input, output := output, work := work, transport := transport, values := values, workspace := workspace,
    length := length, position := position, depth := depth, active := active, capacity := capacity,
    start := start, top := top, context := context, contextLength := contextLength }
  obtain ⟨after, run, ⟨emitted, finalOutput, finalWork, rfl⟩, effect, heap⟩ :=
    Wrapper.body checked c 1
      (fun emitted => emitted = values) (afterFailure workspace position)
      ready topFound (by simp [afterFailure, c]) (by
        constructor
        intro caller arguments before wellFormed evaluated memory
        obtain ⟨completed, emittedRun, outputContents, workContents, effect, heap⟩ :=
          emit_call checked length position depth capacity start low (.inl rfl) active context contextLength wellFormed
            memory.plain memory.inputBacking memory.outputBacking memory.workBacking
            memory.inputOutput memory.inputWork memory.outputWork current cursor healthy depthBound readable storage bounded
            bad outputBound tagWord kindWord lowWord evaluated
        exact ⟨completed, emittedRun, ⟨_, outputContents, workContents, rfl⟩, effect, heap⟩)
  have retained : (afterFailure workspace position)[6]? = some top := by
    simpa only [afterFailure, List.getElem?_set_ne (by decide : 1 ≠ 6),
      List.getElem?_set_ne (by decide : 0 ≠ 6)] using topFound
  rw [Wrapper.finish_eq retained] at finalWork
  exact ⟨after, run, finalOutput, finalWork, effect, heap⟩


/-- Whole source-linked expression call on a readable signed literal with
insufficient output capacity. The return is kind 1, not a failure sentinel:
CODE records -1, INPUT advances by three, output is unchanged, and captured
TOP is restored. No compiler execution premise is assumed. -/
theorem records_failure (checked : Source.Expression.Literal.Checked emitters)
    (length position depth capacity start : Nat) (low top : Int) (active context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (current : workspace[0]? = some (position : Int))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0) (topFound : workspace[6]? = some top)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (bad : capacity < start + 5) (outputBound : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some 1)
    (lowWord : transport[position + 2]? = some low)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input work output transport.length workspace.length values.length length capacity depth active context contextLength) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.wrapper.source.function.id arguments)
        (.signed .i32 1) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterFailure workspace position))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let bindings := inputValues input work output transport.length workspace.length values.length length capacity depth active context contextLength
  let params := parameterBindings (fun index : Fin 9 => bindings.get index)
  have ready := Literal.Ready.enterCall (bindings := bindings) wellFormed plain
    inputBacking outputBacking workBacking inputOutput inputWork outputWork
  obtain ⟨completed, run, finalOutput, finalWork, effect, heap⟩ := wrapper_body checked length position depth capacity start low top
    active context contextLength ready current cursor healthy topFound depthBound readable storage bounded bad outputBound
    tagWord kindWord lowWord
  have called := checked.wrapper.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, finalOutput, finalWork, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Lower.Expression.Literal.Capacity
