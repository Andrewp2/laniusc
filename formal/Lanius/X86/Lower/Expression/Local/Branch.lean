import Lanius.X86.Lower.Expression.Local.Tail

namespace Lanius.X86.Lower.Expression.Local

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The selected LOCAL branch reads its serialized identifier, searches the
actual active-binding table, loads the initialized i32 slot, and emits its
machine load. No execution of a source helper is assumed. -/
theorem branch {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Local.Checked literal) (width : Register.Width)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (length position active stride binding slot capacity start : Nat) (key : Int)
    (inputPrefix : 6 ≤ bindings.length) (fresh : bindings.length ≤ 14)
    (inputLocal : before.local? 0 = some (.slice i32 input [] 0 transport.length))
    (lengthLocal : before.local? 1 = some (.signed .i32 length))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (activeLocal : before.local? 5 = some (.signed .i32 active))
    (current : workspace[0]? = some (position : Int)) (cursor : workspace[1]? = some (start : Int))
    (readable : position < length) (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (keyWord : transport[position]? = some key)
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
        (Source.Expression.Local.branch literal.take.internal.source.function.id checked.lookup.internal.source.function.id
          literal.layout.aggregate.source.function.id checked.get.internal.source.function.id
          checked.lookup.header.id checked.stride.id checked.negativeBranch checked.aggregateBranch)
        (.returned (some (.signed .i32 (Value.Get.kind width)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        ((workspace.set 0 (position + 1 : Nat)).set 1 (start + (Value.Get.bytes width slot).length : Nat)))) } ∧
      Emission values start (Value.Get.bytes width slot) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have workEntry := ready.entry 2 (by omega) workLocal
  have outputEntry := ready.entry 3 (by omega) outputLocal
  have capacityEntry := ready.entry 4 (by omega) capacityLocal
  have activeEntry := ready.entry 5 (by omega) activeLocal
  obtain ⟨idState, idRun, afterId, idEffect, idHeap⟩ := ready.take literal.take length position
    inputLocal lengthLocal workLocal current readable storage bounded keyWord
  let named := idState.bindLocal 14 (.signed .i32 key)
  have namedReady := afterId.bind 14 fresh (.signed .i32 key)
  have idLocal := bindLocal_finds_local idState 14 (.signed .i32 key) afterId.wellFormed
  have lookupArguments : ArgumentsEvaluateTo emitters.pack.program.core named [read 2, read 5, read 14]
      (Frame.Lookup.arguments (.slice i32 work [] 0 (workspace.set 0 (position + 1 : Nat)).length) active key) named := by
    exact .cons (local_evaluates _ (by simpa only [List.length_set] using namedReady.read 2 workEntry))
      (.cons (local_evaluates _ (namedReady.read 5 activeEntry)) (.cons (local_evaluates _ idLocal) (.nil _ _)))
  obtain ⟨lookupState, lookupRun, _, lookupEffect, lookupHeap⟩ := Frame.Lookup.call checked.lookup active key
    namedReady.wellFormed namedReady.workBacking (by simpa only [List.length_set] using tableRoom)
    tableBound (lookup_after_input correct (position + 1 : Nat)) lookupArguments
  have afterLookup := namedReady.empty lookupEffect
  let found := lookupState.bindLocal 15 (.signed .i32 binding)
  have foundReady := afterLookup.bind 15 (by omega) (.signed .i32 binding)
  have bindingLocal := bindLocal_finds_local lookupState 15 (.signed .i32 binding) afterLookup.wellFormed
  have rejection : Evaluates emitters.pack.program.core found Source.Expression.Local.rejected (.boolean false) found := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ bindingLocal)
      (show Evaluates emitters.pack.program.core found (number 0) (.signed .i32 0) found from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  have kindRun := kind_read checked foundReady stride binding
    (by simpa only [List.length_set] using foundReady.read 2 workEntry) bindingLocal
    (by simpa only [List.getElem?_set_ne (by decide : 0 ≠ 12)] using strideValue)
    (by simpa only [List.length_set] using kindInside) (by omega)
    (by simpa only [List.getElem?_set_ne (by omega : 0 ≠ 16 + stride + binding)] using kindValue)
  let kinded := found.bindLocal 16 (.signed .i32 (Value.Get.kind width))
  have kindedReady := foundReady.bind 16 (by omega) (.signed .i32 (Value.Get.kind width))
  have kindLocal := bindLocal_finds_local found 16 (.signed .i32 (Value.Get.kind width)) foundReady.wellFormed
  have slotRun := slot_read checked kindedReady stride binding slot
    (by simpa only [List.length_set] using kindedReady.read 2 workEntry)
    ((bindLocal_preserves_other_local foundReady.wellFormed (by decide : 16 ≠ 15)).trans bindingLocal)
    (by simpa only [List.getElem?_set_ne (by decide : 0 ≠ 12)] using strideValue)
    (by simpa only [List.length_set] using slotInside) addressBound
    (by simpa only [List.getElem?_set_ne (by omega : 0 ≠ 16 + stride * 2 + binding)] using slotValue)
  let slotted := kinded.bindLocal 17 (.signed .i32 slot)
  have slottedReady := kindedReady.bind 17 (by omega) (.signed .i32 slot)
  have slotLocal := bindLocal_finds_local kinded 17 (.signed .i32 slot) kindedReady.wellFormed
  obtain ⟨completed, emitted, tailRun, finalOut, finalWork, emission, tailEffect, tailHeap⟩ := tail checked width slot capacity start slottedReady
    (by simpa only [List.length_set] using slottedReady.read 2 workEntry) (slottedReady.read 3 outputEntry)
    (slottedReady.read 4 capacityEntry)
    ((bindLocal_preserves_other_local kindedReady.wellFormed (by decide : 17 ≠ 16)).trans kindLocal)
    slotLocal (by simpa only [List.getElem?_set_ne (by decide : 0 ≠ 1)] using cursor)
    slotBound room outputStorage outputBound
  have slotScope := executesLetLocal (id := 17) (type := i32) slotRun tailRun
  have kindScope := executesLetLocal (id := 16) (type := i32) kindRun slotScope
  have slotEffect := CellEffect.closeLocal kinded 17 (.signed .i32 slot) kindedReady.wellFormed tailEffect
  have slotHeap := HeapFrame.closeLocal kinded 17 (.signed .i32 slot) tailHeap
  have kindEffect := CellEffect.closeLocal found 16 (.signed .i32 (Value.Get.kind width)) foundReady.wellFormed slotEffect
  have kindHeap := HeapFrame.closeLocal found 16 (.signed .i32 (Value.Get.kind width)) slotHeap
  have foundScope := executesLetLocal (id := 15) (type := i32) (by simpa only [Frame.Lookup.result] using lookupRun)
    (executesSequence (executesIfFalse (thenBranch := returned negativeOne) rejection (executesSkip _ _)) kindScope)
  have foundEffect := (lookupEffect.weaken (larger := Literal.writes output work) CellSet.empty_subset).trans
    (CellEffect.closeLocal lookupState 15 (.signed .i32 binding) afterLookup.wellFormed kindEffect)
  have foundHeap := lookupHeap.trans (HeapFrame.closeLocal lookupState 15 (.signed .i32 binding) kindHeap)
  exact ⟨_, emitted, executesLetLocal (id := 14) (type := i32) idRun foundScope,
    finalOut, finalWork, emission,
    idEffect.trans (CellEffect.closeLocal idState 14 (.signed .i32 key) afterId.wellFormed foundEffect),
    idHeap.trans (HeapFrame.closeLocal idState 14 (.signed .i32 key) foundHeap)⟩

end Lanius.X86.Lower.Expression.Local
