import Lanius.X86.Lower.Expression.Literal.Entry
import Lanius.X86.Lower.Expression.Literal.Tail

namespace Lanius.X86.Lower.Expression.Literal

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def afterLiteral (workspace : List Int) (position start : Nat) : List Int :=
  (workspace.set 0 (position + 3 : Nat)).set 1 (start + 5 : Nat)

/-- The real emit_expression literal case, with no assumed dispatch, reads,
layout calls, or emission. Untaken source branches are retained by the checker
but never executed on this transport prefix. -/
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
    (room : start + 5 ≤ capacity) (outputStorage : capacity ≤ values.length) (outputBound : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some kind)
    (lowWord : transport[position + 2]? = some low) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.emitBody checked.layout checked.constants checked.take.internal.source.function.id
          checked.immediate.source.function.id checked.stringBranch checked.otherBranches)
        (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array
        (signedI32Values (Encode.Immediate.written values start low))) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterLiteral workspace position start))) } ∧
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
  · simp [List.getElem?_append, inputCount]
  · simp [List.getElem?_append, inputCount]
  · simpa [List.getElem?_set] using cursor
  · exact room
  · exact outputStorage
  · exact outputBound

/-- The actual internal emitter call for a three-word scalar literal. The
universal recursive-expression emission IH is discharged on this base case:
only the actual source/input/resource preconditions remain. -/
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
    (room : start + 5 ≤ capacity) (outputStorage : capacity ≤ values.length) (outputBound : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some kind)
    (lowWord : transport[position + 2]? = some low)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input work output transport.length workspace.length values.length length capacity depth active context contextLength) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.emitter.source.function.id arguments)
        (.signed .i32 kind) after ∧
      after.cellEntry? output = some { id := output, value := some (.array
        (signedI32Values (Encode.Immediate.written values start low))) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterLiteral workspace position start))) } ∧
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
    room outputStorage outputBound tagWord kindWord lowWord
  have called := checked.emitter.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, finalOutput, finalWork, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Lower.Expression.Literal
