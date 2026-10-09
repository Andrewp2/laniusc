import verified_compiler.tests.direct_ir_body_production_inputs

namespace IRBodyProductionInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof

/-- Only the selected original signature row is represented. Its spare table
    slots and later query execution are not input obligations. -/
structure NativeSignature (signature : Signature) (heap : Heap) where
  base : Nat
  location : rawSliceElementAddress? extractedProgram signatureType
    signature.address signature.id = .ok base
  snapshot : NativeSnapshot 64 extractedProgram heap signatureType base signature.entry 72

theorem NativeSignature.read (native : NativeSignature signature state.heap) :
    signature.Read state := by
  have inside : signature.id < signature.length :=
    Nat.lt_of_lt_of_le signature.inside signature.bound
  unfold Signature.Read
  simp only [readRawSliceIndex, Nat.not_le_of_lt inside, ↓reduceIte, native.location]
  exact native.snapshot.read

def NativeSignature.afterReads (native : NativeSignature signature before)
    (reads : HeapReads before after) : NativeSignature signature after :=
  { native with snapshot := native.snapshot.afterHeapReads reads }

/-- The final byte-local frame suffices for the selected original entry;
    neither a spare signature row nor a future query is required. -/
def NativeSignature.afterBytes (native : NativeSignature signature before)
    (retained : ∀ pointer offset byte, native.base ≤ pointer + offset →
      pointer + offset < native.base + 72 → before.loadByte pointer offset = .ok byte →
      after.loadByte pointer offset = .ok byte) : NativeSignature signature after := {
  native with
  snapshot := by
    intro other within
    apply native.snapshot other
    intro pointer width bytes lower upper loaded
    apply within pointer width bytes lower upper
    have length := (loadBytesFrom_spec loaded).1
    rw [← length]
    apply loadBytesFrom_of_reads
    intro index byte found
    rw [Nat.zero_add]
    have inside := (List.getElem?_eq_some_iff.mp found).1
    exact retained pointer index byte (by omega) (by omega) (Heap.loadBytes_get loaded found) }

#print axioms NativeSignature.read
#print axioms NativeSignature.afterReads
#print axioms NativeSignature.afterBytes

end IRBodyProductionInputs
