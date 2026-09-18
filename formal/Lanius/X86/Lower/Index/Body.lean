import Lanius.X86.Lower.Index.Tail

namespace Lanius.X86.Lower.Index.Emission

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def kindValue (signed : Bool) : Int := if signed then 1 else 3
def normalBytes (signed : Bool) : List UInt8 := if signed then Chunk.normalize.bytes else []
def codeBytes (signed : Bool) (slot : Nat) : List UInt8 := normalBytes signed ++ (slotBytes slot ++ tailBytes)

theorem code_bytes (signed : Bool) (slot : Nat) : codeBytes signed slot = Machine.Index.bytes signed slot := by
  cases signed <;> simp [codeBytes, normalBytes, slotBytes, tailBytes, Chunk.bytes, Machine.Index.bytes,
    Machine.Index.prepare, Machine.ReadOnly.code, List.append_assoc]

theorem code_length : (codeBytes signed slot).length = (normalBytes signed).length + 40 := by
  simp only [codeBytes, List.length_append, slotBytes_length, tailBytes_length]

theorem kind_test (constants : Source.Index.Constants program) (signed : Bool)
    (found : before.local? 4 = some (.signed .i32 (kindValue signed))) :
    Evaluates program before (Source.Index.signedKind constants) (.boolean signed) before := by
  have literal := constants.signed.evaluates (before := before)
  rw [constants.values.2.1] at literal
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found) literal
  cases signed <;> rfl

theorem kind_valid (constants : Source.Index.Constants program) (signed : Bool)
    (found : before.local? 4 = some (.signed .i32 (kindValue signed))) :
    Evaluates program before (Source.Index.invalidKind constants) (.boolean false) before := by
  have signedLiteral := constants.signed.evaluates (before := before)
  have unsignedLiteral := constants.unsigned.evaluates (before := before)
  rw [constants.values.2.1] at signedLiteral
  rw [constants.values.2.2.1] at unsignedLiteral
  have left : Evaluates program before (.binary .notEqual (read 4) (.constant constants.signed.id)) (.boolean (!signed)) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found) signedLiteral
    cases signed <;> rfl
  have right : Evaluates program before (.binary .notEqual (read 4) (.constant constants.unsigned.id)) (.boolean signed) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found) unsignedLiteral
    cases signed <;> rfl
  have run := evaluatesPureLogicalAnd left right
  cases signed <;> exact run

theorem normalize (checked : Source.Index.Checked emitters) (signed : Bool)
    (ready : Ready before output work temporary frontier capacity slot (kindValue signed) cursor values workspace)
    (room : cursor + (normalBytes signed).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before (Source.Index.normalize checked.constants checked.helpers.calls) .next after ∧
      Ready after output work temporary frontier capacity slot (kindValue signed) (cursor + (normalBytes signed).length) emitted workspace ∧
      Buffer.Emission values cursor (normalBytes signed) emitted ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  have guard := kind_test checked.constants signed (ready.inputs.found ⟨4, by simp⟩)
  cases signed with
  | false =>
      exact ⟨before, values, executesIfFalse guard (executesSkip _ _), ready,
        ⟨rfl, by simp [normalBytes, byteSlice], fun _ _ => rfl⟩, CellEffect.refl ready.wellFormed, HeapFrame.refl before⟩
  | true =>
      obtain ⟨after, emitted, run, afterReady, emission, effect, heap⟩ := step .normalize checked ready cursor
        (local_evaluates _ ready.read) room storage bounded
      exact ⟨after, emitted, executesIfTrue guard (executesSequence run (executesSkip _ _)), afterReady, emission, effect, heap⟩

/-- Compose the whole lexical scope in source order. Only normalization is
conditional; the saved descriptor load updates workspace before the length
load reads it, and the final workspace assignment replaces those earlier
cursor writes. No helper-execution premise or output validator is assumed. -/
theorem scope (checked : Source.Index.Checked emitters) (signed : Bool)
    (ready : Ready before output work temporary frontier capacity slot (kindValue signed) cursor values workspace)
    (within : 1 < workspace.length) (slotBound : slot ≤ 1048576)
    (room : cursor + (codeBytes signed slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before (Source.Index.scope checked.constants checked.helpers.calls)
        (.returned (some (.signed .i32 (cursor + (codeBytes signed slot).length : Nat)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (cursor + (codeBytes signed slot).length : Nat)))) } ∧
      Buffer.Emission values cursor (codeBytes signed slot) emitted ∧
      CellEffect (writes output work temporary) before after ∧ HeapFrame before after := by
  have space : cursor + (normalBytes signed).length + 40 ≤ capacity := by rw [code_length] at room; omega
  obtain ⟨normalState, normalValues, normalRun, normalReady, normalWindow, normalEffect, normalHeap⟩ :=
    normalize checked signed ready (by omega) storage bounded
  obtain ⟨savedState, savedRun, savedReady, savedEffect, savedHeap⟩ := normalReady.code checked.constants within
    (local_evaluates _ normalReady.read) (CellEffect.refl normalReady.wellFormed) (HeapFrame.refl normalState)
    normalReady.outputBacking rfl
  obtain ⟨slotState, slotValues, slotRun, slotReady, slotWindow, slotEffect, slotHeap⟩ :=
    load_slot checked savedReady (cursor + (normalBytes signed).length) (List.getElem?_set_self within) slotBound
      (by rw [slotBytes_length]; omega) (by rw [normalWindow.length]; exact storage) bounded
  obtain ⟨after, emitted, tailRun, outputContents, workContents, tailWindow, tailEffect, tailHeap⟩ :=
    tail checked slotReady (cursor + (normalBytes signed).length + (slotBytes slot).length)
      (List.getElem?_set_self (by simpa only [List.length_set] using within))
      (by rw [tailBytes_length, slotBytes_length]; omega)
      (by rw [slotWindow.length, normalWindow.length]; exact storage) bounded
  have total : cursor + (normalBytes signed).length + (slotBytes slot).length + tailBytes.length =
      cursor + (codeBytes signed slot).length := by simp only [codeBytes, List.length_append]; omega
  rw [total] at tailRun workContents
  simp only [List.set_set] at workContents
  exact ⟨after, emitted, executesSequence normalRun (executesSequence savedRun (executesSequence slotRun tailRun)),
    outputContents, workContents, normalWindow.append (slotWindow.append tailWindow),
    (normalEffect.weaken writes_cursor).trans ((savedEffect.weaken writes_workspace).trans
      ((slotEffect.weaken writes_workspace).trans tailEffect)),
    normalHeap.trans (savedHeap.trans (slotHeap.trans tailHeap))⟩

end Lanius.X86.Lower.Index.Emission
