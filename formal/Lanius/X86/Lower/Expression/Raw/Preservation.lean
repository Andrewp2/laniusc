import Lanius.X86.Lower.Expression.Raw
import Lanius.X86.Lower.Expression.Raw.Native
import Lanius.X86.Machine.Slice.Raw.Expression

namespace Lanius.X86.Lower.Expression.Raw.Preservation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def expression (key : VarId) (low : Int) : Expr :=
  .i32SliceFromRawParts (.local key) (.value (.signed .i32 low))

/-- Full-expression refinement for the actual local-pointer/literal source
case. The positive domain is an exact represented live allocation; negative
lengths need no allocation metadata. The two descriptor words are fresh
private frame storage, separate from code and mapped heap bytes. -/
def NativeRefines (sourceSlot top : Nat) (key : VarId) (low : Int) (code : List UInt8) : Prop :=
  ∀ (program : Program) (auxiliary : Bool) (runtime : State) (address : Nat),
    runtime.local? key = some (.pointer address) → StateWellFormed runtime →
    ∀ (locations : Storage.Locations) (native entry started : Machine.State),
    Storage.Heap.Correspondence runtime.heap native.memory locations → Frame.BodyFrame entry started native →
    ∀ (layout : Frame.Layout) (inside : sourceSlot < layout.slots) (room : top + 1 < layout.slots),
    sourceSlot < top → layout.slots ≤ 1048576 → native.registers 5 = BitVec.ofNat 64 layout.base →
    layout.base + 16 ≤ 2^64 → ∀ data, locations.pointer address = some data →
    Machine.read64 native.memory (layout.address ⟨sourceSlot, inside⟩) = data →
    (0 ≤ low → ∃ block, runtime.heap.block? address = some block ∧
      block.size = low.toNat * 4 ∧ block.alignment = 4) →
    ∀ tail, Machine.CodeAt native.memory native.rip (code ++ tail) →
    (∀ index, index < (code ++ tail).length → Storage.Slice.Descriptor.Outside
      (layout.address ⟨top + 1, room⟩) (native.rip + BitVec.ofNat 64 index)) →
    (∀ block ∈ runtime.heap.blocks, ∀ base, locations.pointer block.base = some base →
      ∀ offset, offset < block.size → Storage.Slice.Descriptor.Outside
        (layout.address ⟨top + 1, room⟩) (base + BitVec.ofNat 64 offset)) →
    ∃ after,
      after = (if 0 ≤ low then Machine.Slice.Raw.continuation
        (Machine.Slice.Raw.guarded (Machine.Slice.Raw.Expression.prepared native sourceSlot top low) auxiliary) (top + 1)
        else Machine.Slice.Raw.guarded (Machine.Slice.Raw.Expression.prepared native sourceSlot top low) auxiliary) ∧
      Storage.Heap.Correspondence runtime.heap after.memory locations ∧ Frame.BodyFrame entry started after ∧
      (∀ live : Fin layout.slots, live.val < top → ∀ lane : Fin 8,
        after.memory (layout.address live + BitVec.ofNat 64 lane.val) =
          native.memory (layout.address live + BitVec.ofNat 64 lane.val)) ∧
      (∀ register, register ≠ 0 → after.registers register = native.registers register) ∧
      after.flags.getLsbD 10 = native.flags.getLsbD 10 ∧
      if 0 ≤ low then
        ∃ coreAfter values, Machine.Steps 8 native after ∧
          Evaluates program runtime (expression key low)
            (.slice (.scalar (.signed .i32)) runtime.nextCell [] 0 low.toNat) coreAfter ∧
          Storage.Slice.Raw.Constructed runtime coreAfter address low.toNat after.memory data
            (Storage.Slice.Descriptor.install locations runtime.nextCell [] 0 data) values ∧
          Storage.Represents (Storage.Slice.Descriptor.install locations runtime.nextCell [] 0 data)
            after.memory (layout.address ⟨top + 1, room⟩)
            (.slice (.scalar (.signed .i32)) runtime.nextCell [] 0 low.toNat) ∧
          after.registers 0 = layout.address ⟨top + 1, room⟩ ∧ Machine.CodeAt after.memory after.rip tail
      else
        evalExpr 2 program runtime (expression key low) = .trapped .rawMemoryBounds runtime ∧
          Machine.Steps 5 native after ∧ Machine.Fault after

private theorem expression_rejects (program : Program)
    (found : runtime.local? key = some (.pointer address)) (negative : low < 0) :
    evalExpr 2 program runtime (expression key low) = .trapped .rawMemoryBounds runtime := by
  rw [expression, evalExpr.eq_def]
  simp only
  rw [evalLocal_of_local 0 program runtime key (.pointer address) found]
  exact Storage.Slice.Raw.rejects_negative negative

/-- The native prefix supplies every pointer-capture and literal-register
premise of Native.constructs. The Core local read is real, and construction
is derived from the live heap domain rather than assumed as an execution. -/
theorem bytes_refines (sourceSlot top : Nat) (key : VarId)
    (canonical : -2147483648 ≤ low ∧ low ≤ 2147483647) :
    NativeRefines sourceSlot top key low (Machine.Slice.Raw.Expression.bytes sourceSlot top low) := by
  intro program auxiliary runtime address localRead wellFormed locations native entry started related caller
    layout inside room liveSource bounded base headerBound data mapped pointer domain tail loaded codeSeparate heapSeparate
  let source : Fin layout.slots := ⟨sourceSlot, inside⟩
  let slot : Fin layout.slots := ⟨top + 1, room⟩
  let prepared := Machine.Slice.Raw.Expression.prepared native sourceSlot top low
  have fields := Machine.Slice.Raw.Expression.prepared_fields (length := low) native layout source slot rfl bounded base pointer
  have prefixCode : Machine.CodeAt native.memory native.rip
      (Machine.Slice.Raw.Expression.prefixBytes sourceSlot top low ++
        (Machine.Slice.Raw.bytes (top + 1) ++ tail)) := by
    simpa only [Machine.Slice.Raw.Expression.bytes, List.append_assoc] using loaded
  have prefixRun := Machine.Slice.Raw.Expression.prepares native layout source slot top rfl bounded base pointer
    (Machine.Slice.Raw.bytes (top + 1) ++ tail) prefixCode (by
      intro index within lane
      exact codeSeparate index (by simpa only [Machine.Slice.Raw.Expression.bytes, List.append_assoc] using within)
        ⟨lane.val, by have := lane.isLt; omega⟩)
  have prefixHeap := Machine.Slice.Raw.Expression.prepares_heap (length := low) native layout source slot rfl
    bounded base pointer related (by
      intro block member nativeBase mapping offset within lane
      exact heapSeparate block member nativeBase mapping offset within ⟨lane.val, by have := lane.isLt; omega⟩)
  have prefixCaller := Machine.Slice.Raw.Expression.prepares_caller (length := low) native layout source slot rfl
    bounded base pointer caller headerBound
  have prefixBase : prepared.registers 5 = BitVec.ofNat 64 layout.base := (fields.2.2.1 5 (by decide)).trans base
  have preparedRip : prepared.rip = native.rip + 19 := fields.2.2.2.2
  have prefixLive (other : Fin layout.slots) (live : other.val < top) (lane : Fin 8) :
      prepared.memory (layout.address other + BitVec.ofNat 64 lane.val) =
        native.memory (layout.address other + BitVec.ofNat 64 lane.val) :=
    Machine.Slice.Raw.Expression.prepares_slot native layout source slot other rfl bounded base pointer live lane
  by_cases sign : 0 ≤ low
  · obtain ⟨block, found, size, alignment⟩ := domain sign
    obtain ⟨coreAfter, values, _, constructed, steps, descriptor, result, heap, frame, live,
        memory, registers, direction, rip, code⟩ := Native.constructs program (native := prepared) auxiliary
      wellFormed prefixHeap found mapped size alignment canonical sign fields.2.1 layout slot top rfl bounded
      prefixBase prefixRun.2.1 prefixCaller headerBound tail prefixRun.2.2 (by
        intro index within lane
        have total : 19 + index < (Machine.Slice.Raw.Expression.bytes sourceSlot top low ++ tail).length := by
          simpa only [Machine.Slice.Raw.Expression.bytes, List.length_append, slot,
            Machine.Slice.Raw.Expression.prefixBytes_length, Nat.add_assoc] using (Nat.add_lt_add_left within 19)
        have separate := codeSeparate (19 + index) total ⟨8 + lane.val, by have := lane.isLt; omega⟩
        rw [preparedRip]
        simpa only [slot, BitVec.ofNat_add, BitVec.add_assoc,
          show BitVec.ofNat 64 19 = (19 : Machine.Address) from rfl,
          show BitVec.ofNat 64 8 = (8 : Machine.Address) from rfl] using separate)
      (by
        intro candidate member nativeBase mapping offset within lane
        simpa only [slot, BitVec.ofNat_add, BitVec.add_assoc,
          show BitVec.ofNat 64 8 = (8 : Machine.Address) from rfl] using
          heapSeparate candidate member nativeBase mapping offset within ⟨8 + lane.val, by have := lane.isLt; omega⟩)
    refine ⟨_, by simp only [if_pos sign]; rfl, heap, frame, ?_, ?_, ?_, ?_⟩
    · intro other old lane
      exact (live other old lane).trans (prefixLive other old lane)
    · intro register different
      exact (registers register different).trans (fields.2.2.1 register different)
    · exact direction.trans (congrArg (fun flags => flags.getLsbD 10) fields.2.2.2.1)
    · rw [if_pos sign]
      refine ⟨coreAfter, values, prefixRun.1.trans steps, ?_, constructed, descriptor, result, code⟩
      apply evaluatesI32SliceFromRawParts
        (show Evaluates program runtime (.local key) (.pointer address) runtime from ⟨1, evalLocal_of_local 0 _ _ _ _ localRead⟩)
        (show Evaluates program runtime (.value (.signed .i32 low)) (.signed .i32 low) runtime from ⟨1, rfl⟩)
      simpa only [Int.toNat_of_nonneg sign] using constructed.run
  · have rejected := Native.rejects_negative (before := runtime) (address := address)
      (native := prepared) program auxiliary (top + 1) tail canonical (by omega) fields.2.1 prefixRun.2.2
    let after := Machine.Slice.Raw.guarded prepared auxiliary
    have memory : after.memory = prepared.memory := rejected.2.2.2.1
    have registers : after.registers = prepared.registers := rejected.2.2.2.2.1
    have direction : after.flags.getLsbD 10 = prepared.flags.getLsbD 10 := rejected.2.2.2.2.2.1
    have frame : Frame.BodyFrame entry started after := by
      refine ⟨?_, ?_, ?_, ?_, direction.trans prefixCaller.direction⟩
      · rw [registers]; exact prefixCaller.framePointer
      · rw [memory]; exact prefixCaller.savedPointer
      · rw [memory]; exact prefixCaller.returnAddress
      · intro register saved; rw [registers]; exact prefixCaller.registers register saved
    refine ⟨after, by simp only [if_neg sign]; rfl, ?_, frame, ?_, ?_, ?_, ?_⟩
    · rw [memory]; exact prefixHeap
    · intro other old lane; rw [memory]; exact prefixLive other old lane
    · intro register different; rw [registers]; exact fields.2.2.1 register different
    · exact direction.trans (congrArg (fun flags => flags.getLsbD 10) fields.2.2.2.1)
    · rw [if_neg sign]
      exact ⟨expression_rejects program localRead (by omega), prefixRun.1.trans rejected.2.1, rejected.2.2.1⟩

/-- Source-selected bytes are exactly the decoded full native expression,
not a generic descriptor initializer substituted for the actual compiler. -/
theorem bytes_eq : Raw.bytes sourceSlot top low = Machine.Slice.Raw.Expression.bytes sourceSlot top low := by
  simp only [Raw.bytes, tailBytes, Guard.bytes, Guard.testBytes, Finish.bytes, saveBytes,
    Machine.Slice.Raw.Expression.bytes, Machine.Slice.Raw.Expression.prefixBytes,
    Machine.Slice.Raw.bytes, Machine.Slice.Raw.guardBytes, Machine.Slice.Raw.testBytes,
    Machine.Slice.Raw.continuationBytes, Machine.Slice.Raw.moveBytes, List.append_assoc]
  rfl

theorem window_refines (sourceSlot top : Nat) (key : VarId)
    (canonical : -2147483648 ≤ low ∧ low ≤ 2147483647)
    (window : Emission original start (Raw.bytes sourceSlot top low) emitted) :
    NativeRefines sourceSlot top key low (byteSlice emitted start (Raw.bytes sourceSlot top low).length) := by
  rw [window.bytes, bytes_eq]
  exact bytes_refines sourceSlot top key canonical

/-- The actual source compiler returns the aggregate kind and emits a full
expression window refining the same Core local and signed literal. No source
call, native instruction execution, or successful constructor is a premise. -/
theorem compiles {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal) (localChecked : Source.Expression.Local.Checked literal)
    (length position depth active stride binding slot capacity start top peak : Nat)
    (key : VarId) (low : Int) (context contextLength : Value)
    (canonical : -2147483648 ≤ low ∧ low ≤ 2147483647)
    (config : Raw.Input transport workspace values length position depth active stride binding slot capacity start top peak key low)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ Literal.inputValues input work output transport.length workspace.length values.length
      length capacity depth (.signed .i32 active) context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (Literal.inputValues input work output transport.length workspace.length values.length length capacity depth
        (.signed .i32 active) context contextLength) before) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call literal.wrapper.source.function.id arguments)
        (.signed .i32 6) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (afterRaw workspace position start slot top peak low))) } ∧
      Emission values start (Raw.bytes slot top low) emitted ∧
      NativeRefines slot top key low (byteSlice emitted start (Raw.bytes slot top low).length) ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨after, emitted, run, outputContents, workContents, window, effect, heap⟩ :=
    Raw.compiles checked localChecked length position depth active stride binding slot capacity start top peak key low
      context contextLength config wellFormed plain inputBacking outputBacking workBacking inputOutput inputWork outputWork
      argumentsResult
  exact ⟨after, emitted, run, outputContents, workContents, window,
    window_refines slot top key canonical window, effect, heap⟩

end Lanius.X86.Lower.Expression.Raw.Preservation
