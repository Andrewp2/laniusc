import Lanius.X86.Lower.Expression.Local.Binding
import Lanius.X86.Lower.Expression.Literal.Entry
import Lanius.X86.Lower.Expression.Literal.Emit
import Lanius.X86.Lower.Expression.Wrapper

namespace Lanius.X86.Lower.Expression.Local.Reject

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer
open Literal

private theorem negative (program : Program) :
    Evaluates program before negativeOne (.signed .i32 (-1)) before := by
  apply evaluatesUnary (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
  simp [evalUnaryValue, wrapSigned_i32_neg_one]

/-- The actual LOCAL branch reads its identifier and returns immediately on
a missing binding. Kind/slot tables and the value getter are never read. -/
theorem branch {literal : Source.Expression.Literal.Checked emitters} (checked : Source.Expression.Local.Checked literal)
    (ready : Ready before bindings frontier input output work transport values workspace)
    (length position active : Nat) (key : Int) (fresh : bindings.length ≤ 14)
    (inputLocal : before.local? 0 = some (.slice i32 input [] 0 transport.length))
    (lengthLocal : before.local? 1 = some (.signed .i32 length))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (activeLocal : before.local? 5 = some (.signed .i32 active))
    (current : workspace[0]? = some (position : Int))
    (readable : position < length) (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (keyWord : transport[position]? = some key)
    (lookupRoom : 16 + active ≤ workspace.length) (lookupBound : 16 + active ≤ 2147483647)
    (missing : Frame.Lookup.Correct workspace active key none) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Local.branch literal.take.internal.source.function.id checked.lookup.internal.source.function.id
          literal.layout.aggregate.source.function.id checked.get.internal.source.function.id checked.lookup.header.id checked.stride.id
          checked.negativeBranch checked.aggregateBranch)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 0 (position + 1 : Nat)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨readState, readRun, readReady, readEffect, readHeap⟩ := ready.take literal.take length position
    inputLocal lengthLocal workLocal current readable storage bounded keyWord
  have readWork := readEffect.preserves_local ready.wellFormed workLocal (by
    intro cell binding changed
    rcases changed with out | work
    · exact local_cell_ne_of_distinct_value workLocal ready.outputBacking (by intro same; cases same) binding out
    · exact local_cell_ne_of_distinct_value workLocal ready.workBacking (by intro same; cases same) binding work)
  have readActive := keeps_scalar ready readEffect activeLocal
  let keyed := readState.bindLocal 14 (.signed .i32 key)
  have keyedReady := readReady.bind 14 fresh (.signed .i32 key)
  have keyedWork := (bindLocal_preserves_other_local (boundId := 14) (queriedId := 2) (value := .signed .i32 key)
    readReady.wellFormed (by decide)).trans readWork
  have keyedActive := (bindLocal_preserves_other_local (boundId := 14) (queriedId := 5) (value := .signed .i32 key)
    readReady.wellFormed (by decide)).trans readActive
  have keyedId := bindLocal_finds_local readState 14 (.signed .i32 key) readReady.wellFormed
  have args : ArgumentsEvaluateTo emitters.pack.program.core keyed [read 2, read 5, read 14]
      (Frame.Lookup.arguments (.slice i32 work [] 0 (workspace.set 0 (position + 1 : Nat)).length) active key) keyed := by
    simp only [List.length_set]
    exact .cons (local_evaluates _ keyedWork) (.cons (local_evaluates _ keyedActive) (.cons (local_evaluates _ keyedId) (.nil _ _)))
  obtain ⟨looked, lookupRun, _, lookupEffect, lookupHeap⟩ := Frame.Lookup.call checked.lookup active key keyedReady.wellFormed
    keyedReady.workBacking (by simpa only [List.length_set] using lookupRoom) lookupBound
    (lookup_after_input missing (position + 1 : Nat)) args
  have lookedReady := keyedReady.empty lookupEffect
  let selected := looked.bindLocal 15 (.signed .i32 (-1))
  have selectedReady := lookedReady.bind 15 (by omega) (.signed .i32 (-1))
  have selectedId := bindLocal_finds_local looked 15 (.signed .i32 (-1)) lookedReady.wellFormed
  have guard : Evaluates emitters.pack.program.core selected Source.Expression.Local.rejected (.boolean true) selected :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ selectedId) ⟨1, rfl⟩ rfl
  have closedLookup := lookupEffect.trans (CellEffect.closeLocal looked 15 (.signed .i32 (-1)) lookedReady.wellFormed
    (CellEffect.refl (writes := CellSet.empty) selectedReady.wellFormed))
  have closedHeap := lookupHeap.trans (HeapFrame.closeLocal looked 15 (.signed .i32 (-1)) (HeapFrame.refl selected))
  exact ⟨_, executesLetLocal readRun (executesLetLocal lookupRun
    (executesSequenceReturned (executesIfTrue guard (executesSequenceReturned
      (executesReturnValue (negative emitters.pack.program.core)))))), selectedReady.outputBacking, selectedReady.workBacking,
    readEffect.trans (CellEffect.closeLocal readState 14 (.signed .i32 key) readReady.wellFormed
      (closedLookup.weaken CellSet.empty_subset)),
    readHeap.trans (HeapFrame.closeLocal readState 14 (.signed .i32 key) closedHeap)⟩

/-- Dispatch the real emitter's LOCAL case and derive lookup failure from
the key-table invariant. The only workspace change is consuming two input
words, and no output or kind/slot-table access is required. -/
theorem emit_body {literal : Source.Expression.Literal.Checked emitters} (checked : Source.Expression.Local.Checked literal)
    (ready : Ready before bindings frontier input output work transport values workspace)
    (length position depth start active : Nat) (key : Int) (inputCount : bindings.length = 9)
    (inputLocal : before.local? 0 = some (.slice i32 input [] 0 transport.length))
    (lengthLocal : before.local? 1 = some (.signed .i32 length))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (activeLocal : before.local? 5 = some (.signed .i32 active))
    (depthLocal : before.local? 6 = some (.signed .i32 depth))
    (current : workspace[0]? = some (position : Int)) (cursor : workspace[1]? = some (start : Int))
    (healthy : workspace[4]? = some 0) (depthBound : depth < 512) (readable : position + 2 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (tagWord : transport[position]? = some 1) (keyWord : transport[position + 1]? = some key)
    (lookupRoom : 16 + active ≤ workspace.length) (lookupBound : 16 + active ≤ 2147483647)
    (missing : Frame.Lookup.Correct workspace active key none) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.emitBody literal.layout literal.constants literal.take.internal.source.function.id
          literal.immediate.source.function.id literal.stringBranch literal.otherBranches)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 0 (position + 2 : Nat)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have entryGuard := entry_guard literal.constants ready depth start depthBound depthLocal workLocal cursor healthy
  have inputEntry := ready.entry 0 (by omega) inputLocal
  have lengthEntry := ready.entry 1 (by omega) lengthLocal
  have workEntry := ready.entry 2 (by omega) workLocal
  have activeEntry := ready.entry 5 (by omega) activeLocal
  have within : 0 < workspace.length := by omega
  obtain ⟨tagState, tagRun, tagReady, tagEffect, tagHeap⟩ := ready.take literal.take length position
    inputLocal lengthLocal workLocal current (by omega) storage bounded tagWord
  let tagged := tagState.bindLocal 9 (.signed .i32 1)
  have taggedReady := tagReady.bind 9 (by omega) (.signed .i32 1)
  have tagRead := bindLocal_finds_local tagState 9 (.signed .i32 1) tagReady.wellFormed
  have valueConstant := literal.constants.value.evaluates (before := tagged)
  rw [literal.constants.values.2.2.2.1] at valueConstant
  have literalGuard : Evaluates emitters.pack.program.core tagged
      (.binary .equal (read 9) (.constant literal.constants.value.id)) (.boolean false) tagged :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ tagRead) valueConstant rfl
  have localConstant := checked.tag.evaluates (before := tagged)
  rw [checked.values.1] at localConstant
  have localGuard : Evaluates emitters.pack.program.core tagged (Source.Expression.Local.selected checked.tag.id)
      (.boolean true) tagged :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ tagRead) localConstant rfl
  obtain ⟨completed, localRun, finalOutput, finalWork, localEffect, localHeap⟩ := branch checked taggedReady length (position + 1)
    active key (by omega) (taggedReady.read 0 inputEntry) (taggedReady.read 1 lengthEntry)
    (by simpa only [List.length_set] using taggedReady.read 2 workEntry) (taggedReady.read 5 activeEntry)
    (List.getElem?_set_self within) (by omega) storage bounded keyWord
    (by simpa only [List.length_set] using lookupRoom) lookupBound (lookup_after_input missing (position + 1 : Nat))
  have selectedRun : Executes emitters.pack.program.core tagged literal.otherBranches
      (.returned (some (.signed .i32 (-1)))) completed := by
    rw [checked.bodyExact]
    exact executesSequenceReturned (executesIfTrue localGuard localRun)
  refine ⟨restoreLocals tagState completed, executesSequence (executesIfFalse entryGuard (executesSkip _ _))
    (executesLetLocal tagRun (executesSequence (executesIfFalse literalGuard (executesSkip _ _)) selectedRun)),
    finalOutput, ?_, tagEffect.trans (CellEffect.closeLocal tagState 9 (.signed .i32 1) tagReady.wellFormed localEffect),
    tagHeap.trans (HeapFrame.closeLocal tagState 9 (.signed .i32 1) localHeap)⟩
  change completed.cellEntry? work = _
  simpa [List.set_set, Nat.add_assoc] using finalWork

/-- Whole actual internal emitter call for a missing lexical local. The
lookup proof, dispatch and input reads are supplied by source theorems. -/
theorem emitter_rejects {literal : Source.Expression.Literal.Checked emitters} (checked : Source.Expression.Local.Checked literal)
    (length position depth capacity start active : Nat) (key : Int) (context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ inputValues input work output transport.length workspace.length values.length
      length capacity depth (.signed .i32 active) context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (current : workspace[0]? = some (position : Int)) (cursor : workspace[1]? = some (start : Int))
    (healthy : workspace[4]? = some 0) (depthBound : depth < 512) (readable : position + 2 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (tagWord : transport[position]? = some 1) (keyWord : transport[position + 1]? = some key)
    (lookupRoom : 16 + active ≤ workspace.length) (lookupBound : 16 + active ≤ 2147483647)
    (missing : Frame.Lookup.Correct workspace active key none)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input work output transport.length workspace.length values.length length capacity depth
        (.signed .i32 active) context contextLength) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call literal.emitter.source.function.id arguments)
        (.signed .i32 (-1)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 0 (position + 2 : Nat)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let bindings := inputValues input work output transport.length workspace.length values.length length capacity depth
    (.signed .i32 active) context contextLength
  let params := parameterBindings (fun index : Fin 9 => bindings.get index)
  have ready := Literal.Ready.enterCall (bindings := bindings) wellFormed plain
    inputBacking outputBacking workBacking inputOutput inputWork outputWork
  obtain ⟨completed, run, finalOutput, finalWork, effect, heap⟩ := emit_body checked ready length position depth start active key rfl
    (ready.locals.found ⟨0, by simp [bindings, inputValues]⟩) (ready.locals.found ⟨1, by simp [bindings, inputValues]⟩)
    (ready.locals.found ⟨2, by simp [bindings, inputValues]⟩) (ready.locals.found ⟨5, by simp [bindings, inputValues]⟩)
    (ready.locals.found ⟨6, by simp [bindings, inputValues]⟩) current cursor healthy depthBound readable storage bounded
    tagWord keyWord lookupRoom lookupBound missing
  have called := literal.emitter.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, finalOutput, finalWork, called.2, HeapFrame.closeCall before params heap⟩



private theorem wrapper_body {literal : Source.Expression.Literal.Checked emitters} (checked : Source.Expression.Local.Checked literal)
    (length position depth capacity start active : Nat) (key top : Int) (context contextLength : Value)
    (ready : Ready before
      (inputValues input work output transport.length workspace.length values.length length capacity depth (.signed .i32 active) context contextLength)
      frontier input output work transport values workspace)
    (current : workspace[0]? = some (position : Int)) (cursor : workspace[1]? = some (start : Int))
    (healthy : workspace[4]? = some 0) (topFound : workspace[6]? = some top)
    (depthBound : depth < 512) (readable : position + 2 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (tagWord : transport[position]? = some 1) (keyWord : transport[position + 1]? = some key)
    (lookupRoom : 16 + active ≤ workspace.length) (lookupBound : 16 + active ≤ 2147483647)
    (missing : Frame.Lookup.Correct workspace active key none) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.body literal.layout literal.constants literal.emitter.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 0 (position + 2 : Nat)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let c : Context := {
    input := input, output := output, work := work, transport := transport, values := values, workspace := workspace,
    length := length, position := position, depth := depth, active := .signed .i32 active, capacity := capacity,
    start := start, top := top, context := context, contextLength := contextLength }
  obtain ⟨after, run, ⟨emitted, finalOutput, finalWork, rfl⟩, effect, heap⟩ :=
    Wrapper.body literal c (-1)
      (fun emitted => emitted = values) (workspace.set 0 (position + 2 : Nat))
      ready topFound (by simp [c]) (by
        constructor
        intro caller arguments before wellFormed evaluated memory
        obtain ⟨completed, emittedRun, outputContents, workContents, effect, heap⟩ :=
          emitter_rejects checked length position depth capacity start active key context contextLength wellFormed
            memory.plain memory.inputBacking memory.outputBacking memory.workBacking
            memory.inputOutput memory.inputWork memory.outputWork current cursor healthy depthBound readable storage bounded
            tagWord keyWord lookupRoom lookupBound missing evaluated
        exact ⟨completed, emittedRun, ⟨_, outputContents, workContents, rfl⟩, effect, heap⟩)
  have retained : (workspace.set 0 (position + 2 : Nat))[6]? = some top := by
    simpa only [List.getElem?_set_ne (by decide : 0 ≠ 6)] using topFound
  rw [Wrapper.finish_eq retained] at finalWork
  exact ⟨after, run, finalOutput, finalWork, effect, heap⟩

/-- The complete expression call propagates the missing-local sentinel,
classifies -1 as nonaggregate and restores TOP. Only INPUT advances by two;
output, CODE, FAILED, and the binding tables remain unchanged. -/
theorem wrapper_rejects {literal : Source.Expression.Literal.Checked emitters} (checked : Source.Expression.Local.Checked literal)
    (length position depth capacity start active : Nat) (key top : Int) (context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ inputValues input work output transport.length workspace.length values.length
      length capacity depth (.signed .i32 active) context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (current : workspace[0]? = some (position : Int)) (cursor : workspace[1]? = some (start : Int))
    (healthy : workspace[4]? = some 0) (topFound : workspace[6]? = some top) (depthBound : depth < 512) (readable : position + 2 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (tagWord : transport[position]? = some 1) (keyWord : transport[position + 1]? = some key)
    (lookupRoom : 16 + active ≤ workspace.length) (lookupBound : 16 + active ≤ 2147483647)
    (missing : Frame.Lookup.Correct workspace active key none)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input work output transport.length workspace.length values.length length capacity depth
        (.signed .i32 active) context contextLength) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call literal.wrapper.source.function.id arguments)
        (.signed .i32 (-1)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 0 (position + 2 : Nat)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let bindings := inputValues input work output transport.length workspace.length values.length length capacity depth
    (.signed .i32 active) context contextLength
  let params := parameterBindings (fun index : Fin 9 => bindings.get index)
  have ready := Literal.Ready.enterCall (bindings := bindings) wellFormed plain
    inputBacking outputBacking workBacking inputOutput inputWork outputWork
  obtain ⟨completed, run, finalOutput, finalWork, effect, heap⟩ := wrapper_body checked
    length position depth capacity start active key top context contextLength ready current cursor healthy topFound
    depthBound readable storage bounded tagWord keyWord lookupRoom lookupBound missing
  have called := literal.wrapper.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, finalOutput, finalWork, called.2, HeapFrame.closeCall before params heap⟩


end Lanius.X86.Lower.Expression.Local.Reject
