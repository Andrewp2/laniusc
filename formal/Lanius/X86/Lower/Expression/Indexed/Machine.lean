import Lanius.X86.Lower.Expression.Indexed.Capture
import Lanius.X86.Lower.Index.Preservation

namespace Lanius.X86.Lower.Expression.Indexed

/-- The normal-return induction hypothesis for the recursive index operand.
This is an explicit obligation of recursive expression compilation, not a
claim that that compiler has already been proved. Heap contents may change:
the packed backing relation describes the post-operand state. Live frame
slots, the captured slice descriptor, caller state, and code are protected. -/
structure Recursive (before after entry started : Machine.State) (layout : Frame.Layout)
    (top count : Nat) (code tail : List UInt8) (value : Index.Value)
    (descriptor data : Machine.Address) (values : List Int) (origin length : Nat) : Prop where
  steps : Machine.Steps count before after
  argument : value.argument (after.registers 0)
  frame : Frame.BodyFrame entry started after
  slots : ∀ live : Fin layout.slots, live.val ≤ top → ∀ lane : Fin 8,
    after.memory (layout.address live + BitVec.ofNat 64 lane.val) =
      before.memory (layout.address live + BitVec.ofNat 64 lane.val)
  pointer : Machine.read64 after.memory descriptor = Machine.read64 before.memory descriptor
  extent : Machine.read64 after.memory (descriptor + 8) = Machine.read64 before.memory (descriptor + 8)
  view : origin + length ≤ values.length
  backing : Storage.Slice.Represents after.memory data values
  rip : after.rip = before.rip + BitVec.ofNat 64 code.length
  codeMemory : ∀ index, index < (code ++ tail).length →
    after.memory (before.rip + BitVec.ofNat 64 index) = before.memory (before.rip + BitVec.ofNat 64 index)

theorem Recursive.loaded (recursive : Recursive before after entry started layout top count code tail
    value descriptor data values origin length)
    (loaded : Machine.CodeAt before.memory before.rip (code ++ tail)) :
    Machine.CodeAt after.memory after.rip tail := by
  have kept : Machine.CodeAt after.memory before.rip (code ++ tail) := by
    intro index bound
    rw [recursive.codeMemory index bound]
    exact loaded index bound
  rw [recursive.rip]
  exact kept.suffix

/-- Continue a normal-return recursive operand with the complete checked
address sequence. The saved descriptor is recovered from the live-slot
frame condition, so it is not independently assumed after recursion. -/
theorem Recursive.address (recursive : Recursive captured evaluated entry started layout top count code
    (addressCode ++ tail) value descriptor data values origin length)
    (refines : Index.Emission.Refines signed top addressCode) (representation : value.narrow = signed)
    (slot : Fin layout.slots) (position : slot.val = top) (bounded : layout.slots ≤ 1048576)
    (base : started.registers 5 = BitVec.ofNat 64 layout.base)
    (saved : Machine.read64 captured.memory (layout.address slot) = descriptor)
    (pointer : Machine.read64 captured.memory descriptor = Storage.Slice.address data origin)
    (extent : Machine.read64 captured.memory (descriptor + 8) = BitVec.ofNat 64 length)
    (loaded : Machine.CodeAt captured.memory captured.rip (code ++ (addressCode ++ tail))) :
    if value.word.toNat < length then
      ∃ after, Machine.Steps (count + ((Machine.Index.prepare signed top).length + 2)) captured after ∧
        Lanius.Semantics.integerIndex value.core = .ok value.word.toNat ∧
        after.registers 0 = Storage.Slice.address (Storage.Slice.address data origin) value.word.toNat ∧
        after.memory = evaluated.memory ∧ Frame.BodyFrame entry started after ∧
        (∀ live : Fin layout.slots, live.val ≤ top → ∀ lane : Fin 8,
          after.memory (layout.address live + BitVec.ofNat 64 lane.val) =
            captured.memory (layout.address live + BitVec.ofNat 64 lane.val)) ∧
        Machine.read64 after.memory (layout.address slot) = descriptor ∧
        after.rip = captured.rip + BitVec.ofNat 64 (code.length + addressCode.length) ∧
        Machine.CodeAt after.memory after.rip tail
    else
      (¬ ∃ index, Lanius.Semantics.integerIndex value.core = .ok index ∧ index < length) ∧
      ∃ after, Machine.Steps (count + ((Machine.Index.prepare signed top).length + 1)) captured after ∧
        Machine.Fault after ∧ after.memory = evaluated.memory ∧
        (∀ live : Fin layout.slots, live.val ≤ top → ∀ lane : Fin 8,
          after.memory (layout.address live + BitVec.ofNat 64 lane.val) =
            captured.memory (layout.address live + BitVec.ofNat 64 lane.val)) := by
  have keptSaved : Machine.read64 evaluated.memory (layout.address slot) = descriptor :=
    (Machine.read64_congr _ _ _ (recursive.slots slot (by omega))).trans saved
  have tailLoaded := recursive.loaded loaded
  have result := refines evaluated value recursive.argument representation layout slot position bounded
    (recursive.frame.framePointer.trans base) descriptor data values origin length recursive.view recursive.backing
    keptSaved (recursive.pointer.trans pointer) (recursive.extent.trans extent) tailLoaded.prefix
  by_cases inside : value.word.toNat < length
  · rw [if_pos inside] at result ⊢
    obtain ⟨after, steps, integer, address, memory, rip, registers, direction⟩ := result
    have frame : Frame.BodyFrame entry started after := by
      refine ⟨(registers 5 (by decide) (by decide) (by decide)).trans recursive.frame.framePointer,
        ?_, ?_, ?_, direction.trans recursive.frame.direction⟩
      · rw [memory]; exact recursive.frame.savedPointer
      · rw [memory]; exact recursive.frame.returnAddress
      · intro register savedRegister
        rw [registers register]
        · exact recursive.frame.registers register savedRegister
        all_goals rcases savedRegister with rfl | rfl | rfl | rfl | rfl <;> decide
    refine ⟨after, recursive.steps.trans steps, integer, address, memory, frame, ?_, ?_, ?_, ?_⟩
    · intro live bound lane
      rw [memory]
      exact recursive.slots live bound lane
    · rw [memory]; exact keptSaved
    · rw [rip, recursive.rip, BitVec.ofNat_add, BitVec.add_assoc]
    · rw [memory, rip]
      exact tailLoaded.suffix
  · rw [if_neg inside] at result ⊢
    obtain ⟨rejected, after, steps, fault, memory⟩ := result
    refine ⟨rejected, after, recursive.steps.trans steps, fault, memory, ?_⟩
    intro live bound lane
    rw [memory]
    exact recursive.slots live bound lane

/-- The recursive native proof is applied to the exact captured state.
Its code and heap obligations are kept separate from source-emitter execution. -/
def RecursiveObligation (native entry started : Machine.State) (layout : Frame.Layout)
    (slot : Fin layout.slots) (top count : Nat) (code tail : List UInt8) (value : Index.Value)
    (descriptor data : Machine.Address) (values : List Int) (origin length : Nat) : Prop :=
  ∀ captured : Machine.State,
    Machine.read64 captured.memory (layout.address slot) = descriptor →
    Frame.BodyFrame entry started captured → captured.registers = native.registers →
    captured.flags = native.flags →
    captured.rip = native.rip + BitVec.ofNat 64 (saveBytes top).length →
    captured.memory = Machine.write64 native.memory (layout.address slot) (native.registers 0) →
    Machine.read64 captured.memory descriptor = Storage.Slice.address data origin →
    Machine.read64 captured.memory (descriptor + 8) = BitVec.ofNat 64 length →
    Machine.CodeAt captured.memory captured.rip (code ++ tail) →
    ∃ evaluated, Recursive captured evaluated entry started layout top count code tail
      value descriptor data values origin length

/-- Concrete indexed-address behavior, including the Core integer-index
relation and the caller-owned storage needed by the following load/store. -/
def Outcome (signed : Bool) (top count size : Nat) (native entry started : Machine.State)
    (layout : Frame.Layout) (slot : Fin layout.slots) (value : Index.Value)
    (descriptor data : Machine.Address) (values : List Int) (origin length : Nat) (tail : List UInt8) : Prop :=
  if value.word.toNat < length then
    ∃ after, Machine.Steps (count + (Machine.Index.prepare signed top).length + 3) native after ∧
      Lanius.Semantics.integerIndex value.core = .ok value.word.toNat ∧
      after.registers 0 = Storage.Slice.address (Storage.Slice.address data origin) value.word.toNat ∧
      Frame.BodyFrame entry started after ∧
      origin + length ≤ values.length ∧ Storage.Slice.Represents after.memory data values ∧
      (∀ live : Fin layout.slots, live.val < top → ∀ lane : Fin 8,
        after.memory (layout.address live + BitVec.ofNat 64 lane.val) =
          native.memory (layout.address live + BitVec.ofNat 64 lane.val)) ∧
      Machine.read64 after.memory (layout.address slot) = descriptor ∧
      after.rip = native.rip + BitVec.ofNat 64 size ∧
      Machine.CodeAt after.memory after.rip tail
  else
    (¬ ∃ index, Lanius.Semantics.integerIndex value.core = .ok index ∧ index < length) ∧
    ∃ after, Machine.Steps (count + (Machine.Index.prepare signed top).length + 2) native after ∧
      Machine.Fault after ∧
      Machine.read64 after.memory (started.registers 5) = entry.registers 5 ∧
      Machine.read64 after.memory (started.registers 5 + 8) = Machine.read64 entry.memory (entry.registers 4) ∧
      (∀ live : Fin layout.slots, live.val < top → ∀ lane : Fin 8,
        after.memory (layout.address live + BitVec.ofNat 64 lane.val) =
          native.memory (layout.address live + BitVec.ofNat 64 lane.val))

/-- Machine execution of the actual indexed-expression save prefix,
recursive operand, and checked address emission. The recursive contract is
the only unproved recursive step exposed here. Descriptor storage is kept
separate from the new private slot; mutable backing data is related by the
recursive postcondition rather than incorrectly frozen at capture time. -/
theorem executes (native : Machine.State) (layout : Frame.Layout) (slot : Fin layout.slots) (position : slot.val = top)
    (bounded : layout.slots ≤ 1048576) (base : native.registers 5 = BitVec.ofNat 64 layout.base)
    (frame : Frame.BodyFrame entry started native) (startedBase : started.registers 5 = BitVec.ofNat 64 layout.base)
    (headerBound : layout.base + 16 ≤ 2 ^ 64)
    (descriptor data : Machine.Address) (descriptorValue : native.registers 0 = descriptor)
    (pointer : Machine.read64 native.memory descriptor = Storage.Slice.address data origin)
    (extent : Machine.read64 native.memory (descriptor + 8) = BitVec.ofNat 64 length)
    (descriptorSeparate : ∀ lane : Fin 16, ∀ savedLane : Fin 8,
      descriptor + BitVec.ofNat 64 lane.val ≠ layout.address slot + BitVec.ofNat 64 savedLane.val)
    (refines : Index.Emission.Refines signed top addressCode) (representation : value.narrow = signed)
    (loaded : Machine.CodeAt native.memory native.rip
      (saveBytes top ++ (code ++ (addressCode ++ tail))))
    (codeSeparate : ∀ index, index < (saveBytes top).length + (code ++ (addressCode ++ tail)).length →
      ∀ lane : Fin 8, native.rip + BitVec.ofNat 64 index ≠ layout.address slot + BitVec.ofNat 64 lane.val)
    (recurse : RecursiveObligation native entry started layout slot top count code (addressCode ++ tail)
      value descriptor data values origin length) :
    Outcome signed top count ((saveBytes top).length + code.length + addressCode.length)
      native entry started layout slot value descriptor data values origin length tail := by
  unfold Outcome
  obtain ⟨captured, capture, saved, older, capturedFrame, registers, flags, rip, memory, tailLoaded⟩ :=
    captures native layout slot position bounded base frame startedBase headerBound loaded codeSeparate
  rw [descriptorValue] at saved
  have capturedPointer : Machine.read64 captured.memory descriptor = Storage.Slice.address data origin := by
    rw [memory, Machine.read64_frame]
    · exact pointer
    · intro lane savedLane
      exact descriptorSeparate ⟨lane.val, by have := lane.isLt; omega⟩ savedLane
  have capturedExtent : Machine.read64 captured.memory (descriptor + 8) = BitVec.ofNat 64 length := by
    rw [memory, Machine.read64_frame]
    · exact extent
    · intro lane savedLane
      have bound := lane.isLt
      simpa [BitVec.ofNat_add, BitVec.add_assoc] using descriptorSeparate ⟨8 + lane.val, by omega⟩ savedLane
  obtain ⟨evaluated, recursive⟩ := recurse captured saved capturedFrame registers flags rip memory
    capturedPointer capturedExtent tailLoaded
  have result := recursive.address refines representation slot position bounded startedBase saved
    capturedPointer capturedExtent tailLoaded
  by_cases inside : value.word.toNat < length
  · rw [if_pos inside] at result ⊢
    obtain ⟨after, steps, integer, address, afterMemory, afterFrame, kept, descriptorSaved, afterRip, afterCode⟩ := result
    refine ⟨after, ?_, integer, address, afterFrame, recursive.view, ?_, ?_, descriptorSaved, ?_, afterCode⟩
    · simpa [Nat.add_assoc] using Machine.Steps.cons capture steps
    · rw [afterMemory]; exact recursive.backing
    · intro live bound lane
      exact (kept live (by omega) lane).trans (older live bound lane)
    · rw [afterRip, rip]
      simp only [BitVec.ofNat_add, BitVec.add_assoc]
  · rw [if_neg inside] at result ⊢
    obtain ⟨rejected, after, steps, fault, afterMemory, kept⟩ := result
    refine ⟨rejected, after, ?_, fault, ?_, ?_, ?_⟩
    · simpa [Nat.add_assoc] using Machine.Steps.cons capture steps
    · rw [afterMemory]; exact recursive.frame.savedPointer
    · rw [afterMemory]; exact recursive.frame.returnAddress
    · intro live bound lane
      exact (kept live (by omega) lane).trans (older live bound lane)

/-- Native refinement of one complete emitted indexed-expression window.
No prepared source state occurs in this interface. The only recursive
machine obligation concerns the child bytes, not the whole indexed case. -/
def NativeRefines (signed : Bool) (top : Nat) (child bytes : List UInt8) : Prop :=
  ∀ (native entry started : Machine.State) (layout : Frame.Layout) (slot : Fin layout.slots),
    slot.val = top → layout.slots ≤ 1048576 →
    native.registers 5 = BitVec.ofNat 64 layout.base → Frame.BodyFrame entry started native →
    started.registers 5 = BitVec.ofNat 64 layout.base → layout.base + 16 ≤ 2 ^ 64 →
    ∀ (count : Nat) (value : Index.Value), value.narrow = signed →
    ∀ (descriptor data : Machine.Address) (values : List Int) (origin length : Nat),
    native.registers 0 = descriptor →
    Machine.read64 native.memory descriptor = Storage.Slice.address data origin →
    Machine.read64 native.memory (descriptor + 8) = BitVec.ofNat 64 length →
    (∀ lane : Fin 16, ∀ savedLane : Fin 8,
      descriptor + BitVec.ofNat 64 lane.val ≠ layout.address slot + BitVec.ofNat 64 savedLane.val) →
    ∀ tail : List UInt8, Machine.CodeAt native.memory native.rip (bytes ++ tail) →
    (∀ index, index < bytes.length + tail.length → ∀ lane : Fin 8,
      native.rip + BitVec.ofNat 64 index ≠ layout.address slot + BitVec.ofNat 64 lane.val) →
    RecursiveObligation native entry started layout slot top count child (Machine.Index.bytes signed top ++ tail)
      value descriptor data values origin length →
    Outcome signed top count bytes.length native entry started layout slot value descriptor data values origin length tail

/-- Convert the public source-emission result into native refinement of
exactly that full byte window. The checked-address suffix is identified by
dropping the proved prefix, without rerunning or trusting the emitter. -/
theorem window_refines
    (window : Buffer.Emission original start (saveBytes top ++ child ++ Machine.Index.bytes signed top) emitted)
    (addressRefines : Index.Emission.Refines signed top (Buffer.byteSlice emitted
      (start + (saveBytes top).length + child.length) (Machine.Index.bytes signed top).length)) :
    NativeRefines signed top child (Buffer.byteSlice emitted start
      (saveBytes top ++ child ++ Machine.Index.bytes signed top).length) := by
  have addressExact : Buffer.byteSlice emitted (start + (saveBytes top).length + child.length)
      (Machine.Index.bytes signed top).length = Machine.Index.bytes signed top := by
    have trimmed := congrArg (List.drop (saveBytes top ++ child).length) window.bytes
    rw [List.drop_append_length] at trimmed
    simpa only [Buffer.byteSlice, ← List.map_drop, List.drop_take, List.drop_drop,
      List.length_append, Nat.add_sub_cancel_left, ← Nat.add_assoc] using trimmed
  rw [addressExact] at addressRefines
  rw [window.bytes]
  intro native entry started layout slot position bounded base frame startedBase headerBound
    count value representation descriptor data values origin length descriptorValue pointer extent descriptorSeparate
    tail loaded codeSeparate recurse
  have run := executes native layout slot position bounded base frame startedBase headerBound descriptor data
    descriptorValue pointer extent descriptorSeparate addressRefines representation
    (by simpa only [List.append_assoc] using loaded)
    (by simpa only [List.length_append, Nat.add_assoc] using codeSeparate) recurse
  simpa only [List.length_append] using run

end Lanius.X86.Lower.Expression.Indexed
