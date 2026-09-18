import Lanius.X86.Source.Operation
import Lanius.X86.Encode.Boolean
import Lanius.X86.Encode.Guarded
import Lanius.X86.Buffer.Locals

namespace Lanius.X86.Lower.Operation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer Lanius.Extraction.Source

def bytes (code : Fin 16) (capacity start : Nat) : List Nat :=
  [57, 200] ++ (if start + 5 ≤ capacity then
    (if start + 8 ≤ capacity then Encode.Boolean.bytes code else [15, 144 + code.val, 192]) else [])

/-- The successful source output is exactly the decoded comparison window. -/
theorem emitted_code (operation : BinaryOp) (valid : 0 ≤ Condition.code operation)
    (room : start + 8 ≤ capacity) (storage : capacity ≤ values.length) :
    byteSlice (writtenBytes values start (bytes (Condition.nativeCode operation valid) capacity start)) start 8 =
      Machine.ReadOnly.code (Machine.Boolean.comparison32 (Condition.nativeCode operation valid)) := by
  have enough : start + 5 ≤ capacity := by omega
  simp only [bytes, if_pos room, if_pos enough]
  exact writtenBytes_byteSlice (bytes := [57, 200] ++ Encode.Boolean.bytes (Condition.nativeCode operation valid)) (by
    change start + 8 ≤ values.length; omega)

/-- The actual comparison call emits eight bytes or retains exactly its
completed two- or five-byte instruction prefix and returns sticky -1.
Successful output carries its Core/native refinement for subsequent callers. -/
theorem write (checked : Source.Operation.Checked emitters) (operation : BinaryOp)
    (valid : 0 ≤ Condition.code operation) (capacity start : Nat)
    (room : start + 2 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    checked.internal.Spec (Encode.Boolean.inputs (.slice i32 cell [] 0 values.length) capacity start (Transport.binaryTag operation))
      (.signed .i32 (if start + 8 ≤ capacity then (start + 8 : Nat) else -1))
      (requires := fun before => before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
      (ensures := fun _ after => after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (writtenBytes values start (bytes (Condition.nativeCode operation valid) capacity start)))) } ∧
        (start + 8 ≤ capacity → ∀ target, Condition.NativeRefines target operation
          (byteSlice (writtenBytes values start (bytes (Condition.nativeCode operation valid) capacity start)) start 8)))
      (writes := CellSet.singleton cell) := by
  refine CellSpec.withFact ?_ (by
    intro enough target
    rw [emitted_code operation valid enough storage]
    exact Condition.native_steps operation valid)
  apply checked.internal.specCell rfl
  intro before wellFormed reads backing
  let cc := Condition.nativeCode operation valid
  have ccValue : (cc.val : Int) = Condition.code operation := Int.toNat_of_nonneg valid
  have inputs := Locals.ofReads wellFormed (fun index => reads index.val index.isLt)
  obtain ⟨selected, selection, _, selectionEffect, selectionHeap⟩ := (Condition.selects checked.selector operation).call
    (caller := before) (arguments := [read 3]) wellFormed (by core_args [Encode.Boolean.inputs])
  rw [← ccValue] at selection
  have locals := (inputs.empty wellFormed selectionEffect).push selectionEffect.wellFormed (.signed .i32 cc.val)
  have reads := locals.found
  let scope := selected.bindLocal 4 (.signed .i32 cc.val)
  have scopeWF := bindLocal_preserves_well_formed selected 4 (.signed .i32 cc.val) selectionEffect.wellFormed
  have selectedBacking := selectionEffect.empty_preserves_entry wellFormed backing
  have scopeBacking := ((bindLocal_effect selected 4 (.signed .i32 cc.val)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry selectionEffect.wellFormed selectedBacking) (by simp [CellSet.empty])).trans selectedBacking
  have cmp := checked.cmp.evaluates (before := scope)
  have rax := checked.rax.evaluates (before := scope)
  have rcx := checked.rcx.evaluates (before := scope)
  simp only [checked.values.1, checked.values.2.1, checked.values.2.2] at cmp rax rcx
  obtain ⟨middle, first, contents, effect, heap⟩ :=
    (Encode.Guarded.succeeds checked.binary Encode.Guarded.comparison .w32 0 1 capacity start room storage bounded).call
      (caller := scope) (arguments := Source.Operation.arguments checked.cmp.id checked.rax.id checked.rcx.id)
      scopeWF (by core_args [Source.Operation.arguments, Encode.Guarded.inputs, Encode.Guarded.comparison,
        Encode.Boolean.inputs, Register.Width.bits, scope]) scopeBacking
  change Evaluates _ _ _ (.signed .i32 (start + 2 : Nat)) _ at first
  change middle.cellEntry? cell = some {
    id := cell, value := some (.array (signedI32Values (writtenBytes values start [57, 200]))) } at contents
  have codeRead := effect.preserves_local_of_distinct_value scopeWF
    (locals.found ⟨4, by simp [Encode.Boolean.inputs]⟩) scopeBacking (by intro same; cases same)
  by_cases enough : start + 5 ≤ capacity
  · obtain ⟨after, last, written, finalEffect, finalHeap⟩ := (Encode.Boolean.write checked.boolean cc capacity (start + 2)
      (by omega) (by simpa only [writtenBytes_length] using storage) bounded).call
        (caller := scope) (arguments := Source.Operation.booleanArguments checked.binary.internal.source.function.id
          checked.cmp.id checked.rax.id checked.rcx.id)
        effect.wellFormed (by core_args [Source.Operation.booleanArguments, Encode.Boolean.inputs, scope]) contents
    have sums : start + 2 + 6 = start + 8 := by omega
    simp only [sums] at last written
    refine ⟨_, executesLetLocal selection (by core_exec [Source.Operation.body, Encode.Boolean.inputs]), ?_, ?_, ?_⟩
    · simpa only [bytes, if_pos enough, writtenBytes_append, List.length_cons, List.length_nil, Nat.zero_add,
        cc, State.cellEntry?, restoreLocals] using written
    · exact (selectionEffect.weaken CellSet.empty_subset).trans
        (CellEffect.closeLocal selected 4 (.signed .i32 cc.val) selectionEffect.wellFormed (effect.trans finalEffect))
    · exact selectionHeap.trans (HeapFrame.closeLocal selected 4 (.signed .i32 cc.val) (heap.trans finalHeap))
  · obtain ⟨after, last, _, finalEffect, finalHeap⟩ := (Encode.Boolean.rejects checked.boolean
      (.slice i32 cell [] 0 values.length) capacity (start + 2 : Nat) cc.val (by omega)
      (Or.inr (Or.inr (by simp [reserved]; omega)))).call
        (caller := scope) (arguments := Source.Operation.booleanArguments checked.binary.internal.source.function.id
          checked.cmp.id checked.rax.id checked.rcx.id)
        effect.wellFormed (by core_args [Source.Operation.booleanArguments, Encode.Boolean.inputs, scope])
    have short : ¬ start + 8 ≤ capacity := by omega
    simp only [if_neg short]
    exact ⟨_, executesLetLocal selection (by core_exec [Source.Operation.body, Encode.Boolean.inputs]),
      by simpa [bytes, enough, State.cellEntry?, restoreLocals] using finalEffect.empty_preserves_entry effect.wellFormed contents,
      (selectionEffect.weaken CellSet.empty_subset).trans (CellEffect.closeLocal selected 4 (.signed .i32 cc.val)
        selectionEffect.wellFormed (effect.trans (finalEffect.weaken CellSet.empty_subset))),
      selectionHeap.trans (HeapFrame.closeLocal selected 4 (.signed .i32 cc.val) (heap.trans finalHeap))⟩

/-- Failure before CMP requires no buffer access, even for negative cursors
and nonslice output values. The subsequent Boolean call sees sticky -1. -/
theorem rejects (checked : Source.Operation.Checked emitters) (operation : BinaryOp)
    (valid : 0 ≤ Condition.code operation) (output : Value) (capacity start : Int)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 2 = false) :
    checked.internal.Spec (Encode.Boolean.inputs output capacity start (Transport.binaryTag operation)) (.signed .i32 (-1)) := by
  apply checked.internal.specFrame rfl
  intro before wellFormed reads
  let cc := Condition.nativeCode operation valid
  have ccValue : (cc.val : Int) = Condition.code operation := Int.toNat_of_nonneg valid
  have inputs := Locals.ofReads wellFormed (fun index => reads index.val index.isLt)
  obtain ⟨selected, selection, _, effect, heap⟩ := (Condition.selects checked.selector operation).call
    (caller := before) (arguments := [read 3]) wellFormed (by core_args [Encode.Boolean.inputs])
  rw [← ccValue] at selection
  have entered := (inputs.empty wellFormed effect).push effect.wellFormed (.signed .i32 cc.val)
  have reads := entered.found
  let scope := selected.bindLocal 4 (.signed .i32 cc.val)
  have scopeWF := bindLocal_preserves_well_formed selected 4 (.signed .i32 cc.val) effect.wellFormed
  have cmp := checked.cmp.evaluates (before := scope)
  have rax := checked.rax.evaluates (before := scope)
  have rcx := checked.rcx.evaluates (before := scope)
  simp only [checked.values.1, checked.values.2.1, checked.values.2.2] at cmp rax rcx
  obtain ⟨middle, first, _, cmpEffect, cmpHeap⟩ := (Encode.Guarded.rejects_capacity checked.binary
    Encode.Guarded.comparison .w32 0 1 output capacity start bounded bad).call
      (caller := scope) (arguments := Source.Operation.arguments checked.cmp.id checked.rax.id checked.rcx.id)
      scopeWF (by core_args [Source.Operation.arguments, Encode.Guarded.inputs, Encode.Guarded.comparison,
        Encode.Boolean.inputs, Register.Width.bits, scope])
  have reads := (entered.empty scopeWF cmpEffect).found
  obtain ⟨after, last, _, finalEffect, finalHeap⟩ := (Encode.Boolean.rejects checked.boolean output capacity (-1) cc.val
    bounded (Or.inr (Or.inr (by simp [reserved])))).call
      (caller := scope) (arguments := Source.Operation.booleanArguments checked.binary.internal.source.function.id
        checked.cmp.id checked.rax.id checked.rcx.id) cmpEffect.wellFormed
      (by core_args [Source.Operation.booleanArguments, Encode.Boolean.inputs, scope])
  exact ⟨_, executesLetLocal selection (by core_exec [Source.Operation.body, Source.Operation.branch, Encode.Boolean.inputs]),
    effect.trans (CellEffect.closeLocal selected 4 (.signed .i32 cc.val) effect.wellFormed (cmpEffect.trans finalEffect)),
    heap.trans (HeapFrame.closeLocal selected 4 (.signed .i32 cc.val) (cmpHeap.trans finalHeap))⟩

end Lanius.X86.Lower.Operation
