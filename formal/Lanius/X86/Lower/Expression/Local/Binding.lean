import Lanius.X86.Source.Expression.Local
import Lanius.X86.Lower.Expression.Literal.State
import Lanius.X86.Frame.Lookup

namespace Lanius.X86.Lower.Expression.Local

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

theorem keeps_scalar {id : VarId} (ready : Literal.Ready before bindings frontier input output work transport emitted workspace)
    (effect : CellEffect (Literal.writes output work) before after)
    (found : before.local? id = some (.signed .i32 value)) : after.local? id = some (.signed .i32 value) := by
  apply effect.preserves_local ready.wellFormed found
  intro cell binding changed
  rcases changed with out | work
  · exact local_cell_ne_of_distinct_value found ready.outputBacking (by intro same; cases same) binding out
  · exact local_cell_ne_of_distinct_value found ready.workBacking (by intro same; cases same) binding work

/-- Advancing the transport cursor cannot alter lexical name lookup: every
active key resides in the table beginning at workspace word 16. -/
theorem lookup_after_input (correct : Frame.Lookup.Correct workspace active key answer) (position : Int) :
    Frame.Lookup.Correct (workspace.set 0 position) active key answer := by
  cases answer with
  | none =>
      intro index inside equal
      exact correct index inside (by simpa only [List.getElem?_set_ne (by omega : 0 ≠ 16 + index)] using equal)
  | some index =>
      refine ⟨correct.1, ?_, ?_⟩
      · simpa only [List.getElem?_set_ne (by omega : 0 ≠ 16 + index)] using correct.2.1
      · intro later higher inside equal
        exact correct.2.2 later higher inside (by simpa only [List.getElem?_set_ne (by omega : 0 ≠ 16 + later)] using equal)

theorem kind_read {literal : Source.Expression.Literal.Checked emitters} (checked : Source.Expression.Local.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport emitted workspace)
    (stride binding : Nat)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (bindingLocal : before.local? 15 = some (.signed .i32 binding))
    (strideValue : workspace[12]? = some (stride : Int))
    (inside : 16 + stride + binding < workspace.length) (bounded : 16 + stride + binding ≤ 2147483647)
    (kind : workspace[16 + stride + binding]? = some value) :
    Evaluates emitters.pack.program.core before
      (.index (read 2) (Source.Expression.Local.kindAddress checked.lookup.header.id checked.stride.id))
      (.signed .i32 value) before := by
  have header := checked.lookup.header.evaluates (before := before)
  rw [checked.lookup.value] at header
  have step := ready.field checked.stride 12 checked.values.2 workLocal strideValue
  have offset := evaluatesNatI32Add header step (by omega : 16 + stride ≤ 2147483647)
  have address := evaluatesNatI32Add offset (local_evaluates _ bindingLocal) bounded
  have run := evaluatesSignedI32SliceIndex emitters.pack.program.core before before before workspace (read 2)
    (Source.Expression.Local.kindAddress checked.lookup.header.id checked.stride.id) work (16 + stride + binding) inside
    (local_evaluates _ workLocal) address ready.workBacking
  have entry : workspace.get ⟨16 + stride + binding, inside⟩ = value := by
    simpa only [List.getElem?_eq_getElem inside, Option.some.injEq, List.get_eq_getElem] using kind
  simpa only [entry] using run

theorem slot_read {literal : Source.Expression.Literal.Checked emitters} (checked : Source.Expression.Local.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport emitted workspace)
    (stride binding slot : Nat)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (bindingLocal : before.local? 15 = some (.signed .i32 binding))
    (strideValue : workspace[12]? = some (stride : Int))
    (inside : 16 + stride * 2 + binding < workspace.length) (bounded : 16 + stride * 2 + binding ≤ 2147483647)
    (slotValue : workspace[16 + stride * 2 + binding]? = some (slot : Int)) :
    Evaluates emitters.pack.program.core before
      (.index (read 2) (Source.Expression.Local.slotAddress checked.lookup.header.id checked.stride.id))
      (.signed .i32 slot) before := by
  have header := checked.lookup.header.evaluates (before := before)
  rw [checked.lookup.value] at header
  have step := ready.field checked.stride 12 checked.values.2 workLocal strideValue
  have doubled := evaluatesNatI32Multiply step
    (show Evaluates emitters.pack.program.core before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
    (by omega : stride * 2 ≤ 2147483647)
  have offset := evaluatesNatI32Add header doubled (by omega : 16 + stride * 2 ≤ 2147483647)
  have address := evaluatesNatI32Add offset (local_evaluates _ bindingLocal) bounded
  have run := evaluatesSignedI32SliceIndex emitters.pack.program.core before before before workspace (read 2)
    (Source.Expression.Local.slotAddress checked.lookup.header.id checked.stride.id) work (16 + stride * 2 + binding) inside
    (local_evaluates _ workLocal) address ready.workBacking
  have entry : workspace.get ⟨16 + stride * 2 + binding, inside⟩ = (slot : Int) := by
    simpa only [List.getElem?_eq_getElem inside, Option.some.injEq, List.get_eq_getElem] using slotValue
  simpa only [entry] using run

end Lanius.X86.Lower.Expression.Local
