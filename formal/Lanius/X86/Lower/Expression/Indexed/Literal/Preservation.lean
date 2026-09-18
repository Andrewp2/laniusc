import Lanius.X86.Lower.Expression.Indexed.Literal
import Lanius.X86.Lower.Expression.Indexed.Literal.Native
import Lanius.X86.Transport.Literal

namespace Lanius.X86.Lower.Expression.Indexed.Literal.Preservation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The actual indexed-helper source call emits native code that captures
the descriptor, evaluates a canonical Core literal, and checks its address.
No recursive source or native execution is assumed; the remaining native
premises are the explicit represented-storage, code, and frame conditions. -/
theorem compiles (checked : Source.Expression.Indexed.Checked emitters) (literal : Source.Expression.Literal.Checked emitters)
    (sameExpression : checked.expression.function.id = literal.wrapper.source.function.id)
    (top peak length position depth capacity start : Nat) (low : Int) (active context contextLength : Value)
    (canonical : -2147483648 ≤ low ∧ low ≤ 2147483647)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ Expression.Literal.inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (cursor : workspace[1]? = some (start : Int))
    (inputCursor : workspace[0]? = some (position : Int)) (healthy : workspace[4]? = some 0)
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit) (slotRoom : top < Frame.Allocate.limit)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (inputStorage : length ≤ transport.length) (inputBound : length ≤ 2147483647)
    (room : start + (saveBytes top).length + 5 + (Machine.Index.bytes true top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some 1) (lowWord : transport[position + 2]? = some low)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (Indexed.inputValues (.slice i32 input [] 0 transport.length) (.signed .i32 length) active (.signed .i32 depth)
        context contextLength work output workspace.length values.length capacity) before) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.boolean true) after ∧
      after.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) } ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (resultWorkspace workspace top peak position start))) } ∧
      (resultWorkspace workspace top peak position start)[0]? = some ((position + 3 : Nat) : Int) ∧
      Emission values start (saveBytes top ++ Encode.Immediate.bytes low ++ Machine.Index.bytes true top) emitted ∧
      NativeRefines top low (byteSlice emitted start
        (saveBytes top ++ Encode.Immediate.bytes low ++ Machine.Index.bytes true top).length) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨after, emitted, run, finalInput, finalOutput, finalWork, inputPosition, window, suffixRefines, effect, heap⟩ :=
    Indexed.Literal.compiles checked literal sameExpression top peak length position depth capacity start low active context contextLength
      wellFormed plain inputBacking outputBacking workBacking inputOutput inputWork outputWork within current watermark cursor inputCursor
      healthy ordered peakBound slotRoom depthBound readable inputStorage inputBound room storage bounded tagWord kindWord lowWord argumentsResult
  exact ⟨after, emitted, run, finalInput, finalOutput, finalWork, inputPosition, window,
    window_refines canonical window suffixRefines, effect, heap⟩

/-- A serialized Core signed literal discharges the range, tag and read-bound
premises of the complete source/native indexed case. The current input
length bounds the stream; suffix words are untouched by the three-word read. -/
theorem from_transport (checked : Source.Expression.Indexed.Checked emitters) (literal : Source.Expression.Literal.Checked emitters)
    (sameExpression : checked.expression.function.id = literal.wrapper.source.function.id)
    (top peak length position depth capacity start : Nat) (low : Int) (active context contextLength : Value)
    (serialized : Transport.expression? sourceProgram (.value (.signed .i32 low)) = some words)
    (stream : ((transport : List Int).take length).drop position = words ++ suffix)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ Expression.Literal.inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (cursor : workspace[1]? = some (start : Int))
    (inputCursor : workspace[0]? = some (position : Int)) (healthy : workspace[4]? = some 0)
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit) (slotRoom : top < Frame.Allocate.limit)
    (depthBound : depth < 512)
    (inputStorage : length ≤ transport.length) (inputBound : length ≤ 2147483647)
    (room : start + (saveBytes top).length + 5 + (Machine.Index.bytes true top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (Indexed.inputValues (.slice i32 input [] 0 transport.length) (.signed .i32 length) active (.signed .i32 depth)
        context contextLength work output workspace.length values.length capacity) before) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.boolean true) after ∧
      after.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) } ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (resultWorkspace workspace top peak position start))) } ∧
      (resultWorkspace workspace top peak position start)[0]? = some ((position + 3 : Nat) : Int) ∧
      Emission values start (saveBytes top ++ Encode.Immediate.bytes low ++ Machine.Index.bytes true top) emitted ∧
      NativeRefines top low (byteSlice emitted start
        (saveBytes top ++ Encode.Immediate.bytes low ++ Machine.Index.bytes true top).length) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨canonical, available, tag, kind, value⟩ := Transport.i32_window serialized stream
  have readable : position + 3 ≤ length := by
    simp only [List.length_take] at available
    omega
  rw [List.getElem?_take_of_lt (by omega)] at tag
  rw [List.getElem?_take_of_lt (by omega)] at kind
  rw [List.getElem?_take_of_lt (by omega)] at value
  exact compiles checked literal sameExpression top peak length position depth capacity start low active context contextLength canonical
    wellFormed plain inputBacking outputBacking workBacking inputOutput inputWork outputWork within current watermark cursor inputCursor
    healthy ordered peakBound slotRoom depthBound readable inputStorage inputBound room storage bounded tag kind value argumentsResult

end Lanius.X86.Lower.Expression.Indexed.Literal.Preservation
