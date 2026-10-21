import verified_compiler.tests.direct_ir_body_production_inputs_context
import Lanius.Semantics.RawSlice

namespace IRBodyOwnedInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

/-- Signed descriptors also represent entry rejection; native rows are separate. -/
structure AllocationTable where
  memory : Nat
  count : Int32

def AllocationTable.value (table : AllocationTable) : Value :=
  source_value Extracted.«lowering::allocation».Types.«Table».mk
    [.pointer table.memory, .signed .i32 table.count.toInt]

structure Header where
  fields : Fin 9 → Int32

def Header.rows (header : Header) : Int32 := header.fields 1
def Header.value (header : Header) : Value :=
  source_value Extracted.«lowering::allocation».Types.«AllocationHeader».mk
    [.signed .i32 (header.fields 0).toInt, .signed .i32 (header.fields 1).toInt,
      .signed .i32 (header.fields 2).toInt, .signed .i32 (header.fields 3).toInt,
      .signed .i32 (header.fields 4).toInt, .signed .i32 (header.fields 5).toInt,
      .signed .i32 (header.fields 6).toInt, .signed .i32 (header.fields 7).toInt,
      .signed .i32 (header.fields 8).toInt]

abbrev DeclarationKind := Extracted.«lowering::declarations».Types.«DeclarationKind»
def kindValue : DeclarationKind → Value
  | .Invalid => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Invalid» []
  | .Structure => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Structure» []
  | .Enumeration => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Enumeration» []
  | .Alias => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Alias» []
  | .Constant => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Constant» []
  | .Function => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Function» []
  | .External => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«External» []
  | .Module => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Module» []
  | .Import => source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Import» []

structure DeclarationRow where
  unit : Int32
  kind : DeclarationKind
  isPublic : Bool
  item : Int32
  declaration : Int32
  name : Int32
  target : Int32
  ordinal : Int32

def DeclarationRow.value (row : DeclarationRow) : Value :=
  source_value Extracted.«lowering::declarations».Types.«DeclarationRow».mk
    [.signed .i32 row.unit.toInt, kindValue row.kind, .boolean row.isPublic,
      .signed .i32 row.item.toInt, .signed .i32 row.declaration.toInt,
      .signed .i32 row.name.toInt, .signed .i32 row.target.toInt,
      .signed .i32 row.ordinal.toInt]

structure AllocationRow where
  source : DeclarationRow
  declarationId : Int32
  coreId : Int32

def AllocationRow.value (row : AllocationRow) : Value :=
  source_value Extracted.«lowering::allocation».Types.«AllocationRow».mk
    [row.source.value, .signed .i32 row.declarationId.toInt, .signed .i32 row.coreId.toInt]

def headerType : Ty := match source_value Extracted.«lowering::allocation».Types.«AllocationHeader».mk [] with
  | .structure id _ => .structure id | _ => .unit
def rowType : Ty := match source_value Extracted.«lowering::allocation».Types.«AllocationRow».mk [] with
  | .structure id _ => .structure id | _ => .unit
def AllocationTable.rowBase (table : AllocationTable) (index : Nat) : Nat :=
  table.memory + 72 + index * 80

/-- Rejection after the header needs only this original live 72-byte region. -/
structure HeaderGeometry (table : AllocationTable) (heap : Heap) where
  block : Block
  found : heap.containingBlock? table.memory = some block
  aligned : table.memory % 8 = 0
  alignment : 8 ≤ block.alignment
  bounds : table.memory + 72 ≤ block.base + block.size
  pointerFits : table.memory + 72 < 2 ^ 64
  unique : HeapBlockBasesUnique heap

structure NativeHeader (table : AllocationTable) (heap : Heap) where
  header : Header
  snapshot : NativeSnapshot 64 extractedProgram heap headerType table.memory header.value 72

structure NativeRow (table : AllocationTable) (heap : Heap) (index : Nat) where
  row : AllocationRow
  snapshot : NativeSnapshot 64 extractedProgram heap rowType (table.rowBase index) row.value 80

/-- One independent original block and bound, not one arithmetic premise per row. -/
structure NormalTable (table : AllocationTable) (heap : Heap) where
  count : Nat
  countEq : table.count.toInt = count
  offsetFits : count * 80 < 2 ^ 31
  geometry : HeaderGeometry table heap
  rowsBounds : table.memory + 72 + count * 80 ≤ geometry.block.base + geometry.block.size
  pointerFits : table.memory + 72 + count * 80 < 2 ^ 64
  header : NativeHeader table heap
  rows : ∀ index, index < count → NativeRow table heap index

/-- This is derived by the reached header effect, never demanded initially. -/
structure BorrowedTable (table : AllocationTable) (heap : Heap) extends NormalTable table heap where
  borrowed : heap.borrowBlock geometry.block.base = heap

theorem NormalTable.rowBounds (normal : NormalTable table heap) (inside : index < normal.count) :
    table.rowBase index + 80 ≤ normal.geometry.block.base + normal.geometry.block.size ∧
      table.rowBase index + 80 < 2 ^ 64 ∧ index * 80 < 2 ^ 31 := by
  have extent := normal.rowsBounds
  have pointer := normal.pointerFits
  have offset := normal.offsetFits
  dsimp only [AllocationTable.rowBase]
  omega

/-- Changing only selected metadata does not change the actual input descriptor. -/
theorem signatureValueEq (first second : Signature)
    (address : first.address = second.address) (length : first.length = second.length)
    (count : first.count = second.count) (tail : first.tail = second.tail) :
    first.value = second.value := by
  simp only [Signature.value, address, length, count, tail]

theorem inputsValueEq (input : Inputs) (selected : Signature)
    (address : input.signature.address = selected.address)
    (length : input.signature.length = selected.length)
    (count : input.signature.count = selected.count) (tail : input.signature.tail = selected.tail) :
    ({ input with signature := selected } : Inputs).value = input.value := by
  simp only [Inputs.value, Inputs.tokensValue, Inputs.allocatedValue]
  rw [signatureValueEq selected input.signature address.symm length.symm count.symm tail.symm]

#print axioms NormalTable.rowBounds
#print axioms signatureValueEq
#print axioms inputsValueEq

end IRBodyOwnedInputs
