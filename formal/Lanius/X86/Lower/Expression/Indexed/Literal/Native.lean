import Lanius.X86.Lower.Expression.Indexed.Machine
import Lanius.X86.Lower.Expression.Literal.Preservation

namespace Lanius.X86.Lower.Expression.Indexed.Literal

/-- The literal operand supplies the recursive native step outright. MOV
does not touch the captured descriptor, packed backing, or private slots. -/
theorem operand (captured entry started : Machine.State) (layout : Frame.Layout)
    (top : Nat) (low : Int) (tail : List UInt8)
    (frame : Frame.BodyFrame entry started captured)
    (view : origin + length ≤ values.length)
    (backing : Storage.Slice.Represents captured.memory data values)
    (loaded : Machine.CodeAt captured.memory captured.rip (Encode.Immediate.bytes low ++ tail)) :
    ∃ evaluated, Indexed.Recursive captured evaluated entry started layout top 1
      (Encode.Immediate.bytes low) tail (.signed (BitVec.ofInt 32 low))
      descriptor data values origin length := by
  let evaluated := captured.immediate32 0 (BitVec.ofInt 32 low) 5
  have step : Machine.Step captured evaluated := Encode.Immediate.executes captured loaded.prefix
  have other (register : Machine.Register) (different : register ≠ 0) :
      evaluated.registers register = captured.registers register := by
    simp [evaluated, Machine.State.immediate32, different]
  have keptFrame : Frame.BodyFrame entry started evaluated := by
    refine ⟨(other 5 (by decide)).trans frame.framePointer, frame.savedPointer,
      frame.returnAddress, ?_, frame.direction⟩
    intro register saved
    rw [other]
    · exact frame.registers register saved
    · rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide
  refine ⟨evaluated, ⟨.cons step (.refl _), ?_, keptFrame,
    ?_, rfl, rfl, view, backing, ?_, ?_⟩⟩
  · simp [Index.Value.argument, evaluated, Machine.State.immediate32]
  · intro live bound lane
    rfl
  · simp only [evaluated, Machine.State.immediate32, Encode.Immediate.bytes_length]
  · intro index bound
    rfl

/-- Complete native behavior for a literal index, with no recursive native
execution premise. Backing storage must be separate from the capture slot;
this is a storage invariant, not an assumed compiler execution. -/
def NativeRefines (top : Nat) (low : Int) (bytes : List UInt8) : Prop :=
  (Index.Value.signed (BitVec.ofInt 32 low)).core = .signed .i32 low ∧
  ∀ (native entry started : Machine.State) (layout : Frame.Layout) (slot : Fin layout.slots),
    slot.val = top → layout.slots ≤ 1048576 →
    native.registers 5 = BitVec.ofNat 64 layout.base → Frame.BodyFrame entry started native →
    started.registers 5 = BitVec.ofNat 64 layout.base → layout.base + 16 ≤ 2 ^ 64 →
    ∀ (descriptor data : Machine.Address) (values : List Int) (origin length : Nat),
    native.registers 0 = descriptor →
    Machine.read64 native.memory descriptor = Storage.Slice.address data origin →
    Machine.read64 native.memory (descriptor + 8) = BitVec.ofNat 64 length →
    (∀ lane : Fin 16, ∀ savedLane : Fin 8,
      descriptor + BitVec.ofNat 64 lane.val ≠ layout.address slot + BitVec.ofNat 64 savedLane.val) →
    origin + length ≤ values.length → Storage.Slice.Represents native.memory data values →
    (∀ index, index < values.length → ∀ lane : Fin 4, ∀ savedLane : Fin 8,
      Storage.Slice.address data index + BitVec.ofNat 64 lane.val ≠
        layout.address slot + BitVec.ofNat 64 savedLane.val) →
    ∀ tail : List UInt8, Machine.CodeAt native.memory native.rip (bytes ++ tail) →
    (∀ index, index < bytes.length + tail.length → ∀ lane : Fin 8,
      native.rip + BitVec.ofNat 64 index ≠ layout.address slot + BitVec.ofNat 64 lane.val) →
    Indexed.Outcome true top 1 bytes.length native entry started layout slot
      (.signed (BitVec.ofInt 32 low)) descriptor data values origin length tail

/-- Attach the source-emitted window to actual machine bounds/address
execution, discharging the generic indexed theorem's recursive obligation
with the one-step literal proof above. -/
theorem window_refines (canonical : -2147483648 ≤ low ∧ low ≤ 2147483647)
    (window : Buffer.Emission original start
      (saveBytes top ++ Encode.Immediate.bytes low ++ Machine.Index.bytes true top) emitted)
    (suffix : Index.Emission.Refines true top (Buffer.byteSlice emitted
      (start + (saveBytes top).length + 5) (Machine.Index.bytes true top).length)) :
    NativeRefines top low (Buffer.byteSlice emitted start
      (saveBytes top ++ Encode.Immediate.bytes low ++ Machine.Index.bytes true top).length) := by
  have generic := Indexed.window_refines window
    (by simpa only [Encode.Immediate.bytes_length] using suffix)
  refine ⟨?_, ?_⟩
  · simp only [Index.Value.core]
    rw [BitVec.toInt_ofInt_eq_self (by decide) canonical.1 (by omega)]
  intro native entry started layout slot position bounded base frame startedBase headerBound
    descriptor data values origin length descriptorValue pointer extent descriptorSeparate view backing backingSeparate
    tail loaded codeSeparate
  apply generic native entry started layout slot position bounded base frame startedBase headerBound
    1 (.signed (BitVec.ofInt 32 low)) rfl descriptor data values origin length
    descriptorValue pointer extent descriptorSeparate tail loaded codeSeparate
  intro captured saved capturedFrame registers flags rip memory capturedPointer capturedExtent capturedCode
  have capturedBacking : Storage.Slice.Represents captured.memory data values := by
    apply backing.frame
    intro index inside lane
    rw [memory]
    exact Machine.write64_frame _ _ _ _ (backingSeparate index inside lane)
  exact operand captured entry started layout top low _ capturedFrame view capturedBacking capturedCode

end Lanius.X86.Lower.Expression.Indexed.Literal
