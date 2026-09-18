import Lanius.X86.Lower.Expression.Indexed.Body
import Lanius.X86.Lower.Expression.Indexed.Machine

namespace Lanius.X86.Lower.Expression.Indexed.Preservation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The actual Lanius indexed-expression compiler call emits a complete
window with a native indexed-address refinement. The source recursion
premise proves emission of the child bytes; `NativeRefines` separately
requires their recursive machine simulation. Neither obligation is silently
upgraded to correctness of the whole compiler, and consumers need no hidden
`Prepared` source-state witness to use the returned native contract. -/
theorem compiles (checked : Source.Expression.Indexed.Checked emitters) (signed : Bool)
    (top peak capacity start : Nat) (recursiveBytes : List UInt8)
    (input length active depth context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ index : Fin 9, ∀ elements,
      (inputValues input length active depth context contextLength work output workspace.length values.length capacity).get index ≠ .array elements)
    (distinct : output ≠ work)
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (cursor : workspace[1]? = some (start : Int))
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit) (slotRoom : top < Frame.Allocate.limit)
    (room : start + (saveBytes top).length + recursiveBytes.length + (Machine.Index.bytes signed top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input length active depth context contextLength work output workspace.length values.length capacity) before)
    (recursive : ∀ prepared frontier preparedValues,
      Prepared prepared (inputValues input length active depth context contextLength work output workspace.length values.length capacity)
        frontier output work top peak start values workspace preparedValues →
      StoreEffect (writes output work) before prepared →
      ∃ recursed recursiveValues recursiveWorkspace,
        RecursiveCall checked signed prepared recursed output work (start + (saveBytes top).length)
          workspace.length preparedValues recursiveValues recursiveWorkspace recursiveBytes) :
    ∃ after emitted finalWorkspace,
      Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments) (.boolean true) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
      Emission values start (saveBytes top ++ recursiveBytes ++ Machine.Index.bytes signed top) emitted ∧
      NativeRefines signed top recursiveBytes (byteSlice emitted start
        (saveBytes top ++ recursiveBytes ++ Machine.Index.bytes signed top).length) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨after, emitted, finalWorkspace, run, output, work, window, suffix, effect, heap⟩ :=
    Indexed.compiles checked signed top peak capacity start recursiveBytes input length active depth context contextLength
      wellFormed plain distinct outputBacking workBacking within current watermark cursor ordered peakBound slotRoom
      room storage bounded argumentsResult recursive
  exact ⟨after, emitted, finalWorkspace, run, output, work, window, window_refines window suffix, effect, heap⟩

end Lanius.X86.Lower.Expression.Indexed.Preservation
