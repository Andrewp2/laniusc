import Lanius.X86.Lower.Value.Get
import Lanius.X86.Frame.Function
import Lanius.X86.Storage.Value

namespace Lanius.X86.Lower.Expression.Local

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.X86.Buffer

/-- A scalar local's emitted window reads its represented frame slot and
returns the same Core signed-i32 value. The assumptions describe the local
and native storage, not an execution of the compiler or emitted code. -/
def NativeRefines (slot : Nat) (coreLocal : VarId) (value : Int) (bytes : List UInt8) : Prop :=
  ∀ (program : Lanius.Core.Program) (runtime : Lanius.Semantics.State),
    runtime.local? coreLocal = some (.signed .i32 value) →
    ∀ (native entry started : Machine.State), Frame.BodyFrame entry started native →
    ∀ (layout : Frame.Layout) (inside : slot < layout.slots), layout.slots ≤ 1048576 →
    native.registers 5 = BitVec.ofNat 64 layout.base →
    Machine.read32 native.memory (layout.address ⟨slot, inside⟩) = BitVec.ofInt 32 value →
    ∀ tail : List UInt8, Machine.CodeAt native.memory native.rip (bytes ++ tail) →
    ∃ after, Machine.Steps 1 native after ∧
      Evaluates program runtime (.local coreLocal)
        (.signed .i32 ((after.registers 0).setWidth 32).toInt) runtime ∧
      (after.registers 0).setWidth 32 = BitVec.ofInt 32 value ∧
      ((after.registers 0).setWidth 32).toInt = value ∧
      (∀ register, register ≠ 0 → after.registers register = native.registers register) ∧
      after.memory = native.memory ∧ after.flags = native.flags ∧
      Frame.BodyFrame entry started after ∧
      after.rip = native.rip + BitVec.ofNat 64 bytes.length ∧
      Machine.CodeAt after.memory after.rip tail

/-- Execute the actual MOV32 encoding, using the real nonwrapping frame
layout to identify its signed displacement with the represented local slot.
No separation premise is needed for a load: all memory, including code and
the saved caller frame, remains unchanged. -/
theorem bytes_refines (slot : Nat) (coreLocal : VarId)
    (canonical : -2147483648 ≤ value ∧ value ≤ 2147483647) :
    NativeRefines slot coreLocal value (Value.Get.bytes .w32 slot) := by
  intro program runtime localRead native entry started frame layout inside bounded base stored tail loaded
  let after := native.load32 0 5 (BitVec.ofInt 32 (Frame.displacement slot)) (Value.Get.bytes .w32 slot).length
  have execution := Frame.load_correct layout ⟨slot, inside⟩ 0 native
    (values := fun candidate => Machine.read32 native.memory (layout.address candidate))
    bounded base (fun _ => rfl) loaded.prefix
  have step : Machine.Step native after := execution.1
  have eax : after.registers 0 =
      (Machine.read32 native.memory (layout.address ⟨slot, inside⟩)).setWidth 64 := execution.2.1
  have bits : (after.registers 0).setWidth 32 = BitVec.ofInt 32 value := by
    rw [eax, stored]
    simp
  have observed : ((after.registers 0).setWidth 32).toInt = value := by
    rw [bits]
    exact BitVec.toInt_ofInt_eq_self (by decide) canonical.1 (by omega)
  have other (register : Machine.Register) (different : register ≠ 0) :
      after.registers register = native.registers register := execution.2.2.1 register different
  have keptFrame : Frame.BodyFrame entry started after := by
    refine ⟨(other 5 (by decide)).trans frame.framePointer, frame.savedPointer, frame.returnAddress,
      ?_, frame.direction⟩
    intro register saved
    rw [other]
    · exact frame.registers register saved
    · rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide
  refine ⟨after, .cons step (.refl after), ?_, bits, observed, other, rfl, rfl, keptFrame, ?_, ?_⟩
  · rw [observed]
    exact local_evaluates program localRead
  · rfl
  · exact loaded.suffix

/-- A pointer local loads all 64 machine bits from its identified frame slot.
The Core pointer is related by Locations.pointer, never by numerical identity.
The contract preserves memory but does not assert that later temporary stores
cannot overwrite this slot; such stores must respect their live-slot frontier. -/
def PointerNativeRefines (locations : Storage.Locations) (slot : Nat) (coreLocal : VarId)
    (pointer : Nat) (bytes : List UInt8) : Prop :=
  ∀ (program : Lanius.Core.Program) (runtime : Lanius.Semantics.State),
    runtime.local? coreLocal = some (.pointer pointer) →
    ∀ (native entry started : Machine.State), Frame.BodyFrame entry started native →
    ∀ (layout : Frame.Layout) (inside : slot < layout.slots), layout.slots ≤ 1048576 →
    native.registers 5 = BitVec.ofNat 64 layout.base →
    Storage.Represents locations native.memory (layout.address ⟨slot, inside⟩) (.pointer pointer) →
    ∀ tail : List UInt8, Machine.CodeAt native.memory native.rip (bytes ++ tail) →
    ∃ after, Machine.Steps 1 native after ∧
      Evaluates program runtime (.local coreLocal) (.pointer pointer) runtime ∧
      locations.pointer pointer = some (after.registers 0) ∧
      (∀ register, register ≠ 0 → after.registers register = native.registers register) ∧
      after.memory = native.memory ∧ after.flags = native.flags ∧
      Frame.BodyFrame entry started after ∧
      after.rip = native.rip + BitVec.ofNat 64 bytes.length ∧
      Machine.CodeAt after.memory after.rip tail

/-- Execute the exact source-selected MOV64 bytes using the existing frame
displacement and machine decoder; the source local remains a Core pointer. -/
theorem pointer_bytes_refines (locations : Storage.Locations) (slot : Nat) (coreLocal : VarId)
    (pointer : Nat) : PointerNativeRefines locations slot coreLocal pointer (Value.Get.bytes .w64 slot) := by
  intro program runtime localRead native entry started frame layout inside bounded base represented tail loaded
  obtain ⟨address, mapping, stored⟩ := Storage.Represents.pointer_iff.mp represented
  let after := native.load64 0 5 (BitVec.ofInt 32 (Frame.displacement slot)) (Value.Get.bytes .w64 slot).length
  have step : Machine.Step native after :=
    .decoded _ loaded.prefix _ _ (by
      simpa only [Value.Get.bytes_memory, List.append_nil] using
        Machine.memory_decodes .w64 true 0 5 (Frame.displacement slot) []) rfl
  have result : after.registers 0 = address := by
    simp only [after, Machine.State.load64, ↓reduceIte, layout.operand ⟨slot, inside⟩ bounded base, stored]
  have other (register : Machine.Register) (different : register ≠ 0) :
      after.registers register = native.registers register := by
    simp only [after, Machine.State.load64, if_neg different]
  have keptFrame : Frame.BodyFrame entry started after := by
    refine ⟨(other 5 (by decide)).trans frame.framePointer, frame.savedPointer, frame.returnAddress,
      ?_, frame.direction⟩
    intro register saved
    rw [other]
    · exact frame.registers register saved
    · rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide
  refine ⟨after, .cons step (.refl after), local_evaluates program localRead, ?_, other,
    rfl, rfl, keptFrame, rfl, loaded.suffix⟩
  rw [result]
  exact mapping

end Lanius.X86.Lower.Expression.Local
