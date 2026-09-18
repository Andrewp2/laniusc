import Lanius.X86.Lower.Expression.Raw.Prepare
import Lanius.X86.Lower.Expression.Literal
import Lanius.X86.Lower.Expression.Local.Preservation

namespace Lanius.X86.Lower.Expression.Raw

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

private theorem plain_depth
    (plain : ∀ value ∈ Literal.inputValues input work output inputLength workLength outputLength
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements) :
    ∀ value ∈ Literal.inputValues input work output inputLength workLength outputLength
      length capacity nextDepth active context contextLength, ∀ elements, value ≠ .array elements := by
  intro value member elements
  simp only [Literal.inputValues, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · intro same; cases same
  · intro same; cases same
  · intro same; cases same
  · intro same; cases same
  · intro same; cases same
  · exact plain value (by simp [Literal.inputValues]) elements
  · intro same; cases same
  · exact plain value (by simp [Literal.inputValues]) elements
  · exact plain value (by simp [Literal.inputValues]) elements

/-- Evaluate the real raw-slice recursive arguments. In particular, the child
depth is computed by the source addition, not supplied as an assumed call. -/
theorem recurse_arguments {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal)
    (length capacity depth : Nat) (active context contextLength : Value)
    (ready : Literal.Ready before
      (Literal.inputValues input work output transport.length workspace.length values.length
        length capacity depth active context contextLength ++ extras)
      frontier input output work transport values workspace)
    (depthBound : depth + 1 < 512) :
    ArgumentsEvaluateTo emitters.pack.program.core before Source.Expression.Raw.recurseArguments
      (Literal.inputValues input work output transport.length workspace.length values.length
        length capacity (depth + 1) active context contextLength) before := by
  have localRead (index : Fin 9) : before.local? index.val = some
      ((Literal.inputValues input work output transport.length workspace.length values.length
        length capacity depth active context contextLength).get index) := by
    apply ready.read index.val
    rw [List.getElem?_append_left (by simpa [Literal.inputValues] using index.isLt)]
    exact List.getElem?_eq_getElem index.isLt
  have deeper := evaluatesNatI32Add
    (local_evaluates emitters.pack.program.core (localRead ⟨6, by decide⟩))
    (show Evaluates emitters.pack.program.core before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
    (by omega : depth + 1 ≤ 2147483647)
  exact .cons (local_evaluates _ (localRead ⟨0, by decide⟩))
    (.cons (local_evaluates _ (localRead ⟨1, by decide⟩))
      (.cons (local_evaluates _ (localRead ⟨2, by decide⟩))
        (.cons (local_evaluates _ (localRead ⟨3, by decide⟩))
          (.cons (local_evaluates _ (localRead ⟨4, by decide⟩))
            (.cons (local_evaluates _ (localRead ⟨5, by decide⟩))
              (.cons deeper (.cons (local_evaluates _ (localRead ⟨7, by decide⟩))
                (.cons (local_evaluates _ (localRead ⟨8, by decide⟩)) (.nil _ _)))))))))

/-- Discharge a raw-slice length child's recursive call with the actual i32
literal compiler. The child consumes its three words and restores entry TOP. -/
theorem literal {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal)
    (length position depth capacity start : Nat) (low top : Int) (active context contextLength : Value)
    (ready : Literal.Ready before
      (Literal.inputValues input work output transport.length workspace.length values.length
        length capacity depth active context contextLength ++ extras)
      frontier input output work transport values workspace)
    (current : workspace[0]? = some (position : Int)) (cursor : workspace[1]? = some (start : Int))
    (healthy : workspace[4]? = some 0) (topFound : workspace[6]? = some top)
    (depthBound : depth + 1 < 512) (readable : position + 3 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (room : start + 5 ≤ capacity) (outputStorage : capacity ≤ values.length) (outputBound : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some 1)
    (lowWord : transport[position + 2]? = some low) :
    ∃ after, OperandCall checked 1 before after output work start workspace.length
        values (Encode.Immediate.written values start low) (Literal.afterLiteral workspace position start)
        (Encode.Immediate.bytes low) ∧
      (Literal.afterLiteral workspace position start)[6]? = some top := by
  let c : Context := {
    input := input, output := output, work := work, transport := transport, values := values, workspace := workspace,
    length := length, position := position, depth := depth + 1, active := active, capacity := capacity,
    start := start, top := top, context := context, contextLength := contextLength }
  obtain ⟨after, run, ⟨_, outputBacking, workBacking, rfl, window⟩, effect, heap⟩ :=
    (Literal.compiles literal c
      ⟨current, cursor, healthy, topFound, depthBound, storage, bounded, outputStorage, outputBound⟩
      ⟨.inl rfl, readable, tagWord, kindWord, lowWord⟩ room).call ready.wellFormed
      (recurse_arguments checked length capacity depth active context contextLength ready depthBound)
      ⟨plain_depth (fun value member elements => ready.plain value
        (by simp only [List.mem_append]; exact Or.inl member) elements), ready.inputBacking, ready.outputBacking, ready.workBacking,
        ready.inputOutput, ready.inputWork, ready.outputWork⟩
  have within : 6 < workspace.length := by
    by_cases inside : 6 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at topFound
      cases topFound
  refine ⟨after, ⟨run, outputBacking, workBacking, ?_, ?_, window, effect, heap⟩, ?_⟩
  · simp only [Literal.afterLiteral, List.length_set]
  · simp only [Literal.afterLiteral, Encode.Immediate.bytes_length]
    exact List.getElem?_set_self (by simpa only [List.length_set] using (show 1 < workspace.length by omega))
  · simpa only [Literal.afterLiteral, List.getElem?_set_ne (by decide : 1 ≠ 6),
      List.getElem?_set_ne (by decide : 0 ≠ 6)] using topFound

/-- Discharge the pointer child's recursive call by checked lexical lookup
and the actual MOV64 getter. Its exact frame slot and address correspondence
remain visible to the later live-slot preservation argument. -/
theorem pointer_local {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal) (localChecked : Source.Expression.Local.Checked literal)
    (length position depth active stride binding slot capacity start : Nat)
    (locations : Storage.Locations) (coreLocal : VarId) (pointer : Nat) (top : Int) (context contextLength : Value)
    (ready : Literal.Ready before
      (Literal.inputValues input work output transport.length workspace.length values.length
        length capacity depth (.signed .i32 active) context contextLength ++ extras)
      frontier input output work transport values workspace)
    (current : workspace[0]? = some (position : Int)) (cursor : workspace[1]? = some (start : Int))
    (healthy : workspace[4]? = some 0) (topFound : workspace[6]? = some top) (depthBound : depth + 1 < 512)
    (readable : position + 2 ≤ length) (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (tagWord : transport[position]? = some 1) (keyWord : transport[position + 1]? = some (coreLocal : Int))
    (correct : Frame.Lookup.Correct workspace active coreLocal (some binding))
    (tableRoom : 16 + active ≤ workspace.length) (tableBound : 16 + active ≤ 2147483647)
    (strideValue : workspace[12]? = some (stride : Int))
    (kindInside : 16 + stride + binding < workspace.length)
    (slotInside : 16 + stride * 2 + binding < workspace.length)
    (addressBound : 16 + stride * 2 + binding ≤ 2147483647)
    (kindValue : workspace[16 + stride + binding]? = some 4)
    (slotValue : workspace[16 + stride * 2 + binding]? = some (slot : Int))
    (slotBound : slot ≤ 1048576) (room : start + (Value.Get.bytes .w64 slot).length ≤ capacity)
    (outputStorage : capacity ≤ values.length) (outputBound : capacity ≤ 2147483647) :
    ∃ after emitted, OperandCall checked 4 before after output work start workspace.length
        values emitted (Local.afterLocal .w64 workspace position start slot) (Value.Get.bytes .w64 slot) ∧
      Local.PointerNativeRefines locations slot coreLocal pointer (byteSlice emitted start 7) ∧
      (Local.afterLocal .w64 workspace position start slot)[6]? = some top := by
  let c : Context := {
    input := input, output := output, work := work,
    transport := transport, values := values, workspace := workspace,
    length := length, position := position, depth := depth + 1, active := .signed .i32 active,
    capacity := capacity, start := start, top := top, context := context, contextLength := contextLength }
  obtain ⟨after, run, ⟨emitted, outputBacking, workBacking, window, native⟩, effect, heap⟩ :=
    (Local.Preservation.pointer_compiles (locations := locations) (pointer := pointer) localChecked c
      ⟨current, cursor, healthy, topFound, depthBound, storage, bounded, outputStorage, outputBound⟩
      ⟨active, rfl, stride, binding, correct, tableRoom, tableBound, strideValue, kindInside, slotInside,
        addressBound, kindValue, slotValue, slotBound, room⟩ ⟨readable, tagWord, keyWord⟩).call
      ready.wellFormed
      (recurse_arguments checked length capacity depth (.signed .i32 active) context contextLength ready depthBound)
      ⟨plain_depth (fun value member elements => ready.plain value
          (by simp only [List.mem_append]; exact Or.inl member) elements),
        ready.inputBacking, ready.outputBacking, ready.workBacking, ready.inputOutput, ready.inputWork, ready.outputWork⟩
  have within : 6 < workspace.length := by
    by_cases inside : 6 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at topFound
      cases topFound
  refine ⟨after, emitted, ⟨run, outputBacking, workBacking, ?_, ?_, window, effect, heap⟩, native, ?_⟩
  · simp only [Local.afterLocal, List.length_set]
  · simp only [Local.afterLocal]
    exact List.getElem?_set_self (by simpa only [List.length_set] using (show 1 < workspace.length by omega))
  · simpa only [Local.afterLocal, List.getElem?_set_ne (by decide : 1 ≠ 6),
      List.getElem?_set_ne (by decide : 0 ≠ 6)] using topFound

end Lanius.X86.Lower.Expression.Raw
