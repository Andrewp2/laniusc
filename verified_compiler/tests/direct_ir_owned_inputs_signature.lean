import verified_compiler.tests.direct_ir_owned_inputs
import verified_compiler.tests.direct_ir_body_production_inputs_signature

namespace IRBodyOwnedInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs IRTypeRefProof

abbrev SignatureShape := Extracted.«lowering::signatures».Types.«SignatureShape»
def shapeCode : SignatureShape → Nat
  | .InvalidShape => 0
  | .StructureShape => 1
  | .EnumerationShape => 2
  | .InternalFunctionShape => 3
  | .ExternalFunctionShape => 4
  | .ConstantShape => 5
def shapeValue (shape : SignatureShape) : Value :=
  match shape with
  | .InvalidShape => source_value Extracted.«lowering::signatures».Types.«SignatureShape».«InvalidShape» []
  | .StructureShape => source_value Extracted.«lowering::signatures».Types.«SignatureShape».«StructureShape» []
  | .EnumerationShape => source_value Extracted.«lowering::signatures».Types.«SignatureShape».«EnumerationShape» []
  | .InternalFunctionShape => source_value Extracted.«lowering::signatures».Types.«SignatureShape».«InternalFunctionShape» []
  | .ExternalFunctionShape => source_value Extracted.«lowering::signatures».Types.«SignatureShape».«ExternalFunctionShape» []
  | .ConstantShape => source_value Extracted.«lowering::signatures».Types.«SignatureShape».«ConstantShape» []
def shapeSame (first second : SignatureShape) : Bool := shapeCode first == shapeCode second

theorem shapeSame_iff (first second : SignatureShape) : shapeSame first second = true ↔ first = second := by
  cases first <;> cases second <;> simp [shapeSame, shapeCode]

/-- The original selected row may have an absent ID or the wrong shape. -/
structure SignatureEntry where
  id : Int32
  kind : DeclarationKind
  shape : SignatureShape
  arity : Int32
  result : Reference
  starts : Fin 3 → Int32

def SignatureEntry.value (entry : SignatureEntry) : Value :=
  source_value Extracted.«lowering::signature_index».Types.«Entry».mk
    [.signed .i32 entry.id.toInt, kindValue entry.kind, shapeValue entry.shape,
      .signed .i32 entry.arity.toInt, referenceValue entry.result,
      .signed .i32 (entry.starts 0).toInt, .signed .i32 (entry.starts 1).toInt,
      .signed .i32 (entry.starts 2).toInt]

structure SignatureIndex where
  address : Nat
  length : Nat
  count : Int32
  tail : Fin 10 → Value

def SignatureIndex.value (index : SignatureIndex) : Value :=
  source_value Extracted.«lowering::signature_index».Types.«Table».mk
    [.rawSlice signatureType index.address index.length, .signed .i32 index.count.toInt,
      index.tail 0, index.tail 1, index.tail 2, index.tail 3, index.tail 4,
      index.tail 5, index.tail 6, index.tail 7, index.tail 8, index.tail 9]

structure NativeSignatureSlot (index : SignatureIndex) (heap : Heap) (slot : Nat) where
  entry : SignatureEntry
  base : Nat
  inside : slot < index.length
  location : rawSliceElementAddress? extractedProgram signatureType index.address slot = .ok base
  snapshot : NativeSnapshot 64 extractedProgram heap signatureType base entry.value 72

theorem NativeSignatureSlot.read (native : NativeSignatureSlot index before.heap slot) :
    readRawSliceIndex extractedProgram before signatureType index.address index.length slot = .ok native.entry.value := by
  simp only [readRawSliceIndex, Nat.not_le_of_lt native.inside, ↓reduceIte, native.location]
  exact native.snapshot.read

/-- Only selected metadata changes; the original signature descriptor stays
    shared by all function rows. Count bounds concern that original descriptor. -/
def SignatureIndex.selected (index : SignatureIndex) (query : Int32) (entry : SignatureEntry)
    (countNonnegative : 0 ≤ index.count.toInt) (capacity : index.count.toInt.toNat ≤ index.length)
    (bounds : 0 ≤ query.toInt ∧ query.toInt < index.count.toInt) : Signature := {
  address := index.address
  length := index.length
  count := index.count.toInt.toNat
  id := query.toInt.toNat
  result := entry.result
  tail := index.tail
  starts := fun field => .signed .i32 (entry.starts field).toInt
  inside := by omega
  bound := capacity
  fits := by have upper := index.count.toInt_lt; omega }

theorem SignatureIndex.selectedValue (index : SignatureIndex) (query : Int32) (entry : SignatureEntry)
    (countNonnegative : 0 ≤ index.count.toInt) (capacity : index.count.toInt.toNat ≤ index.length)
    (bounds : 0 ≤ query.toInt ∧ query.toInt < index.count.toInt) :
    (index.selected query entry countNonnegative capacity bounds).value = index.value := by
  have same : (index.count.toInt.toNat : Int) = index.count.toInt := by omega
  simp only [SignatureIndex.selected, Signature.value, SignatureIndex.value, same]

theorem SignatureIndex.selectedEntry (index : SignatureIndex) (query : Int32) (entry : SignatureEntry)
    (countNonnegative : 0 ≤ index.count.toInt) (capacity : index.count.toInt.toNat ≤ index.length)
    (bounds : 0 ≤ query.toInt ∧ query.toInt < index.count.toInt)
    (id : entry.id.toInt = query.toInt) (kind : entry.kind = .Function)
    (shape : entry.shape = .InternalFunctionShape) (zero : entry.arity.toInt = 0) :
    (index.selected query entry countNonnegative capacity bounds).entry = entry.value := by
  have same : (query.toInt.toNat : Int) = query.toInt := by omega
  simp only [SignatureIndex.selected, Signature.entry, SignatureEntry.value, same, id, kind, shape,
    zero, kindValue, shapeValue, functionKind, internalShape]

def NativeSignatureSlot.selected (native : NativeSignatureSlot index heap query.toInt.toNat)
    (countNonnegative : 0 ≤ index.count.toInt) (capacity : index.count.toInt.toNat ≤ index.length)
    (bounds : 0 ≤ query.toInt ∧ query.toInt < index.count.toInt)
    (id : native.entry.id.toInt = query.toInt) (kind : native.entry.kind = .Function)
    (shape : native.entry.shape = .InternalFunctionShape) (zero : native.entry.arity.toInt = 0) :
    NativeSignature (index.selected query native.entry countNonnegative capacity bounds) heap := {
  base := native.base
  location := native.location
  snapshot := by
    rw [index.selectedEntry query native.entry countNonnegative capacity bounds id kind shape zero]
    exact native.snapshot }

#print axioms SignatureIndex.selectedValue
#print axioms SignatureIndex.selectedEntry
#print axioms NativeSignatureSlot.selected
#print axioms shapeSame_iff
#print axioms NativeSignatureSlot.read

end IRBodyOwnedInputs
