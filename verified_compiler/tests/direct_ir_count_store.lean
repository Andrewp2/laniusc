import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.SourceValue
import Lanius.Semantics.RawFieldStore
import Lanius.Semantics.NaturalArithmetic

namespace IRCountStoreProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

def source := Extracted.«ir::body_catalog».Functions.«append».core
def countId : TypeId := match source.bindingStatement 0 with
  | .letLocal _ (.slice (.structure id)) _ _ => id
  | _ => 0

theorem actualCount : source.effectExpression 6 = .assign .set
    (.field (.index (.local (source.bindingId 0)) (.value (.signed .i32 0))) 0)
    (.binary .add (.local (source.bindingId 3)) (.value (.signed .i32 1))) := by rfl

/-- The real append count assignment needs writable field bytes, not a
    decodable old record. Its exact resulting state retains every nonheap field. -/
theorem actualCountStore {state : State} {address length next : Nat}
    (countFound : state.local? (source.bindingId 0) =
      some (.rawSlice (.structure countId) address length))
    (nextFound : state.local? (source.bindingId 3) = some (.signed .i32 (Int.ofNat next)))
    (bound : 0 < length) (fits : next + 1 < 2 ^ 31)
    (room : state.heap.Readable address 4) (unique : HeapBlockBasesUnique state.heap)
    (noViews : state.i32ArrayViews = []) :
    ∃ heap, RunsExpr extractedProgram state (source.effectExpression 6) .unit { state with heap } ∧
      NativeSnapshot 64 extractedProgram heap (.scalar (.signed .i32)) address
        (.signed .i32 (Int.ofNat (next + 1))) 4 ∧ HeapRegionWrite state.heap heap address 4 := by
  have declaration : extractedProgram.structure? countId =
      some { id := countId, fields := [.scalar (.signed .i32)] } := by decide +kernel
  have offset : NativeLayout.structureFieldOffset? extractedProgram countId 0 = some 0 := by decide +kernel
  have layout : NativeLayout.valueWords? extractedProgram (.structure countId) = some 1 := by decide +kernel
  have location : rawSliceElementAddress? extractedProgram (.structure countId) address 0 = .ok address := by
    simp [rawSliceElementAddress?, layout, NativeLayout.elementBase?, NativeLayout.wordBytes,
      Pure.pure, Except.pure]
  have represented : (BitVec.ofInt 32 (Int.ofNat (next + 1))).toInt = Int.ofNat (next + 1) :=
    BitVec.toInt_ofInt_eq_self (by decide)
      (by simp only [Int.ofNat_eq_natCast]; omega)
      (by change Int.ofNat (next + 1) < 2 ^ 31; simp only [Int.ofNat_eq_natCast]; omega)
  have codec : NativeStoreSpec 64 extractedProgram (.scalar (.signed .i32))
      (.signed .i32 (Int.ofNat (next + 1))) 4 := by
    simpa only [represented] using
      NativeStoreSpec.i32 (program := extractedProgram) (fuel := 63) (BitVec.ofInt 32 (Int.ofNat (next + 1)))
  have increment : RunsExpr extractedProgram state
      (.binary .add (.local (source.bindingId 3)) (.value (.signed .i32 1)))
      (.signed .i32 (Int.ofNat (next + 1))) state := by
    apply RunsExpr.ofStable (StableExpr.binary (.local nextFound) .value (by decide) ?_) rfl
    simpa only [Int.ofNat_eq_natCast, Int.natCast_add, Int.natCast_one] using
      eval_i32_addNonneg extractedProgram.target (Int.ofNat next) 1
        (by simp only [Int.ofNat_eq_natCast]; omega) (by simp only [Int.ofNat_eq_natCast]; omega)
  obtain ⟨heap, run, snapshot, effect, _⟩ := RunsExpr.assignRawFieldNative
    (program := extractedProgram) (before := state) (field := 0)
    (indexExpression := .value (.signed .i32 0))
    (expression := .binary .add (.local (source.bindingId 3)) (.value (.signed .i32 1)))
    countFound (.ofStable .value rfl) bound location declaration rfl offset codec
    (by simpa only [Nat.add_zero] using room) unique noViews increment
  exact ⟨heap, by simpa only [actualCount] using run,
    by simpa only [Nat.add_zero, NativeLayout.maxDepth] using snapshot,
    by simpa only [Nat.add_zero] using effect⟩

#print axioms actualCountStore

end IRCountStoreProof
