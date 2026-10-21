import verified_compiler.tests.direct_ir_catalog_count_read
import verified_compiler.tests.direct_ir_catalog_append_contract
import Lanius.Semantics.RawFieldStore
import Lanius.Semantics.NaturalArithmetic
import Lanius.Memory.Allocated
import Lanius.Semantics.ScopedEffect
import Lanius.Semantics.CallProof

namespace IRCatalogConstructionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRCatalogAppendProof

def sizeSource := Extracted.«ir::body_catalog».Functions.«allocation_bytes».core
def constructor := Extracted.«ir::body_catalog».Functions.«from_raw_parts».core
def lowerSource := Extracted.«lowering::program».Functions.«lower_units».core

abbrev Supported (capacity : Int32) : Prop := 0 < capacity.toInt ∧ capacity.toInt ≤ 22369621
def allocationBytes (capacity : Int32) : Int :=
  if Supported capacity then 8 + capacity.toInt * 96 else -1

theorem actualSizeSupported (capacity : Nat) (positive : 0 < capacity) (bounded : capacity ≤ 22369621)
    (formed : before.CellsWellFormed) : ∃ after,
    RunsExpr extractedProgram before (.call sizeSource.id [.value (.signed .i32 capacity)])
      (.signed .i32 (8 + capacity * 96 : Nat)) after ∧ PureFrame before after := by
  have productFits : capacity * 96 < 2 ^ 31 := by omega
  have totalFits : 8 + capacity * 96 < 2 ^ 31 := by omega
  core_call_pure sizeSource as callee
  core_pure

theorem actualSizeRejected (capacity : Int32) (bad : ¬Supported capacity)
    (formed : before.CellsWellFormed) : ∃ after,
    RunsExpr extractedProgram before (.call sizeSource.id [.value (.signed .i32 capacity.toInt)])
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  dsimp only [Supported] at bad
  core_call_pure sizeSource as callee
  core_pure

/-- Every represented signed capacity is covered, including invalid values. -/
theorem actualSize (capacity : Int32) (formed : before.CellsWellFormed) : ∃ after,
    RunsExpr extractedProgram before (.call sizeSource.id [.value (.signed .i32 capacity.toInt)])
      (.signed .i32 (allocationBytes capacity)) after ∧ PureFrame before after := by
  by_cases supported : Supported capacity
  · have positive := supported.1
    have bounded := supported.2
    have represented : (capacity.toInt.toNat : Int) = capacity.toInt := Int.toNat_of_nonneg (by omega)
    simpa only [allocationBytes, if_pos supported, Int.natCast_add, Int.natCast_mul,
      Int.cast_ofNat_Int, represented] using
      actualSizeSupported capacity.toInt.toNat (by omega) (by omega) formed
  · simpa only [allocationBytes, if_neg supported] using actualSizeRejected capacity supported formed

/-- Constructor coordinates are fixed; request data is kept in the existing append model. -/
structure Catalog where
  memory : Nat
  capacity : Int32

def Catalog.length (catalog : Catalog) : Nat := catalog.capacity.toInt.toNat
def Catalog.bytes (catalog : Catalog) : Nat := 8 + catalog.length * 96
def Catalog.rowBase (catalog : Catalog) (index : Nat) : Nat :=
  catalog.memory + 8 + (catalog.length - index - 1) * 96
def Catalog.model (catalog : Catalog) (next : Int32) (previous : Nat → PreviousRow) (request : Model) : Model :=
  { request with
    rowsAddress := catalog.memory + catalog.length * 96
    rowsLength := catalog.length
    countAddress := catalog.memory
    countLength := 1
    capacity := catalog.capacity
    next := next
    previous := previous }
def Catalog.value (catalog : Catalog) : Value :=
  source_value Extracted.«ir::body_catalog».Types.«Catalog».mk
    [.rawSlice bodyType (catalog.memory + catalog.length * 96) catalog.length,
      .rawSlice (.structure countId) catalog.memory 1, .signed .i32 catalog.capacity.toInt]
def Catalog.call (catalog : Catalog) : Expr :=
  .call constructor.id [.value (.pointer catalog.memory), .value (.signed .i32 catalog.capacity.toInt)]

/-- Only occupied rows have values. Readable backing supplies permission for future SETs. -/
structure Invariant (catalog : Catalog) (next : Int32) (previous : Nat → PreviousRow) (state : State) : Prop where
  supported : Supported catalog.capacity
  bounds : 0 ≤ next.toInt ∧ next.toInt ≤ catalog.capacity.toInt
  count : readNativeValue 64 extractedProgram state.heap (.scalar (.signed .i32)) catalog.memory =
    .ok (.signed .i32 next.toInt)
  backing : state.heap.Readable catalog.memory catalog.bytes
  occupied : ∀ index, index < next.toInt.toNat → NativeSnapshot 64 extractedProgram state.heap
    bodyType (catalog.rowBase index) (previous index).value 96
  formed : state.CellsWellFormed
  unique : HeapBlockBasesUnique state.heap
  below : HeapBlocksBelowNext state.heap
  noViews : state.i32ArrayViews = []

theorem Invariant.countRead (invariant : Invariant catalog next previous state) (request : Model) :
    (catalog.model next previous request).toArguments.CountRead state := by
  change readRawSliceIndex extractedProgram state (.structure countId) catalog.memory 1 0 =
    .ok (.structure countId [.signed .i32 next.toInt])
  exact IRCatalogCountReadProof.fromScalarRead (by decide) invariant.count

/-- The actual caller reads `required.entries`, then invokes the size helper. -/
theorem actualSizeInitializer (capacity : Int32)
    (required : before.local? (lowerSource.bindingId 7) = some
      (source_value Extracted.«lowering::signature_index».Types.«Requirements».mk
        [.signed .i32 capacity.toInt, members, variants, fields, constants, bytes, .boolean valid]))
    (formed : before.CellsWellFormed) : ∃ after,
    RunsExpr extractedProgram before (lowerSource.bindingInitializer 15)
      (.signed .i32 (allocationBytes capacity)) after ∧ PureFrame before after := by
  apply RunsExpr.callPureArguments
  · exact .cons (RunsExpr.field (.ofStable (.local required) rfl) rfl) .nil
  · exact actualSize capacity formed

/-- Fresh catalog storage is borrowed, never decoded. The SET writes the
    allocator's existing zero bytes, so both descriptors share that same block. -/
theorem actualConstructor (catalog : Catalog) (supported : Supported catalog.capacity)
    (base : catalog.memory = origin.allocationAddress 8)
    (allocated : before.heap = origin.allocatedBytes catalog.bytes 8 budget)
    (below : HeapBlocksBelowNext origin) (unique : HeapBlockBasesUnique origin)
    (fits : catalog.memory + catalog.bytes < 2 ^ 64)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before catalog.call catalog.value after ∧
      MemoryEffect (fun _ heap => heap = before.heap.borrowBlock catalog.memory) before after := by
  have capacityIs : (catalog.length : Int) = catalog.capacity.toInt :=
    Int.toNat_of_nonneg (by have := supported.1; omega)
  have positive : 0 < catalog.length := by have := supported.1; omega
  have productFits : catalog.length * 96 < 2 ^ 31 := by have := supported.2; omega
  have countDecl : extractedProgram.structure? countId =
      some { id := countId, fields := [.scalar (.signed .i32)] } := by decide +kernel
  have countLayout : NativeLayout.valueWords? extractedProgram (.structure countId) = some 1 := by decide +kernel
  have rowLayout : NativeLayout.valueWords? extractedProgram bodyType = some 12 := by decide +kernel
  have fieldOffset : NativeLayout.structureFieldOffset? extractedProgram countId 0 = some 0 := by decide +kernel
  have location : rawSliceElementAddress? extractedProgram (.structure countId) catalog.memory 0 = .ok catalog.memory := by
    simp [rawSliceElementAddress?, countLayout, NativeLayout.elementBase?, NativeLayout.wordBytes,
      Pure.pure, Except.pure]
  have allocatedUnique : HeapBlockBasesUnique before.heap := by
    rw [allocated]; exact origin.allocatedBytes_unique below unique (by decide)
  have countBorrow (state : State) (same : state.heap = before.heap) :
      mapRawNominalSlice extractedProgram state (.structure countId) catalog.memory 1 =
        .done (.rawSlice (.structure countId) catalog.memory 1)
          { state with heap := before.heap.borrowBlock catalog.memory } := by
    have found := origin.allocatedBytes_containing (size := catalog.bytes) (budget := budget)
      (offset := 0) below (by decide : 0 < 8) (by dsimp [Catalog.bytes]; omega)
    have mapped := mapRawNominalSlice_of_block 1 (by decide) rfl countLayout (by decide) (by omega)
      (state := state) (by
        simpa only [NativeLayout.wordBytes, Nat.mul_one, Nat.one_mul, Nat.add_sub_cancel,
          same, allocated, base, Nat.add_zero] using found)
      (by simpa only [NativeLayout.wordBytes, Nat.mul_one, Nat.one_mul, Nat.add_sub_cancel, base]
        using origin.allocationAddress_aligned (alignment := 8))
      (by change 8 ≤ 8; decide) (by dsimp [Heap.allocationBlock, Catalog.bytes, NativeLayout.wordBytes]; rw [← base]; omega)
      (by rw [same]; exact allocatedUnique)
    simpa only [same, Heap.allocationBlock, ← base, Int.natCast_one] using mapped
  unfold Catalog.call Catalog.value
  rw [← capacityIs]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) constructor as callee
  apply RunsStmt.letEffect (id := constructor.bindingId 0)
    (value := .pointer (catalog.memory + catalog.length * 96))
    (MemoryEffect.scopeStable _)
  · have pointerFits : catalog.memory + catalog.length * 96 < 2 ^ 64 := by
      dsimp only [Catalog.bytes] at fits; omega
    have pointerAdd := eval_pointer_addNat extractedProgram.target catalog.memory (catalog.length * 96) pointerFits
    core_run
  · core_formed
  core_state first
  apply RunsStmt.letMemoryEffect (id := constructor.bindingId 1)
  · exact ⟨{ first with heap := before.heap.borrowBlock catalog.memory },
      RunsExpr.nominalSliceFromParts (pointer := .local (constructor.argumentId 0))
        (length := .value (.signed .i32 1)) (by core_run) (.ofStable .value rfl)
        (countBorrow first rfl) rfl,
      ⟨(CallerFrame.refl (state := first) (by core_formed)).cells, rfl, rfl, rfl⟩⟩
  intro ready countRun effect
  have cells := effect.1
  have readyFormed := countRun.cellsWellFormed (by core_formed)
  core_state counted
  have same : counted.heap = before.heap.borrowBlock catalog.memory := effect.2.2.2
  have countedUnique : HeapBlockBasesUnique counted.heap := by rw [same]; exact allocatedUnique.borrowBlock
  have zero : counted.heap.loadBytes catalog.memory 4 = .ok (i32Bytes 0) := by
    rw [same, Heap.loadBytes_borrowBlock, allocated, base]
    simpa only [Nat.add_zero, show i32Bytes 0 = List.replicate 4 0 by rfl] using
      origin.allocatedBytes_zeroRange (size := catalog.bytes) (budget := budget) (offset := 0)
        below (by decide : 0 < 8) (by dsimp [Catalog.bytes]; omega)
  have zeroCodec : NativeStoreSpec 64 extractedProgram (.scalar (.signed .i32)) (.signed .i32 0) 4 := by
    simpa using NativeStoreSpec.i32 (program := extractedProgram) (fuel := 63) (0 : BitVec 32)
  obtain ⟨heap, setRun, _, _, written⟩ := RunsExpr.assignRawFieldNative
    (program := extractedProgram) (before := counted) (sourceId := constructor.bindingId 1)
    (field := 0) (indexExpression := .value (.signed .i32 0)) (expression := .value (.signed .i32 0))
    (by core_local) (.ofStable .value rfl) (by decide) location countDecl rfl fieldOffset
    zeroCodec
    (by simpa only [Nat.add_zero] using Heap.Readable.of_loadBytes zero) countedUnique
    (by change ready.i32ArrayViews = []; exact effect.2.2.1.trans noViews) (.ofStable .value rfl)
  have unchanged : writeNativeValue 64 extractedProgram counted counted.heap (.scalar (.signed .i32))
      (catalog.memory + 0) (.signed .i32 0) = .ok counted.heap := by
    simpa only [writeNativeValue, Nat.add_zero] using Heap.storeBytes_same countedUnique zero
  change writeNativeValue 64 extractedProgram counted counted.heap (.scalar (.signed .i32))
    (catalog.memory + 0) (.signed .i32 0) = .ok heap at written
  rw [unchanged] at written
  cases written
  have rowBorrow : mapRawNominalSlice extractedProgram counted bodyType
      (catalog.memory + catalog.length * 96) catalog.length =
      .done (.rawSlice bodyType (catalog.memory + catalog.length * 96) catalog.length) counted := by
    have found := origin.allocatedBytes_containing (size := catalog.bytes) (budget := budget)
      (offset := 8) below (by decide : 0 < 8) (by dsimp [Catalog.bytes]; omega)
    have borrowed := Heap.containingBlock?_borrowSelected found
    have start : catalog.memory + catalog.length * 96 + 8 - catalog.length * 12 * 8 =
        catalog.memory + 8 := by omega
    have run := mapRawNominalSlice_of_block (address := catalog.memory + catalog.length * 96)
      (block := { origin.allocationBlock catalog.bytes 8 with owned := false })
      (state := counted) catalog.length positive (by rfl) rowLayout (by decide)
      (by change catalog.length * 12 * 8 ≤ catalog.memory + catalog.length * 96 + 8; omega) (by
        change counted.heap.containingBlock? (catalog.memory + catalog.length * 96 + 8 - catalog.length * 12 * 8) = _
        rw [start]
        simpa only [same, allocated, Heap.allocationBlock, base] using borrowed)
      (by change (catalog.memory + catalog.length * 96 + 8 - catalog.length * 12 * 8) % 8 = 0
          rw [start]
          simpa only [base, Nat.add_mod, Nat.mod_self, Nat.add_zero, Nat.mod_mod] using
            origin.allocationAddress_aligned (alignment := 8))
      (by change 8 ≤ 8; decide) (by dsimp [Heap.allocationBlock, Catalog.bytes, NativeLayout.wordBytes]; rw [← base]; omega) countedUnique
    have borrowedHeap : counted.heap.borrowBlock catalog.memory = counted.heap := by
      rw [same, Heap.borrowBlock_idempotent]
    simpa only [Heap.allocationBlock, ← base, borrowedHeap] using run
  have dataRun : RunsExpr extractedProgram counted
      (.typedSliceFromRawParts bodyType (.local (constructor.bindingId 0)) (.local (constructor.argumentId 1)))
      (.rawSlice bodyType (catalog.memory + catalog.length * 96) catalog.length) counted :=
    RunsExpr.nominalSliceFromParts (by core_run) (by core_run) rowBorrow rfl
  apply RunsStmt.sequencePureNext (RunsStmt.expression setRun)
  core_pure

#print axioms actualSize
#print axioms Invariant.countRead
#print axioms actualSizeInitializer
#print axioms actualConstructor

end IRCatalogConstructionProof
