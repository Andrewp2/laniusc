import verified_compiler.tests.direct_ir_event_store
import Lanius.Semantics.CountedLocal
import Lanius.Semantics.LoopRun
import Lanius.Semantics.RawSlice

namespace IRRegionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof

private def source := Extracted.«ir::body_events».Functions.«from_raw_parts».core
private def counterId := source.bindingId 4
private def typesId := source.bindingId 3
private def loop := source.whileLoop 0
private theorem typeWidth : NativeLayout.valueWords? extractedProgram referenceType = some 2 := by decide +kernel

private theorem location (inside : position < count) :
    rawSliceElementAddress? extractedProgram referenceType (address + count * 16 - 8) position =
      .ok (address + (count - position - 1) * 16) := by
  have width := typeWidth
  change NativeLayout.valueWords? extractedProgram (.enumeration _) = some 2 at width
  change rawSliceElementAddress? extractedProgram (.enumeration _) _ _ = _
  simp only [rawSliceElementAddress?, width, NativeLayout.elementBase?, NativeLayout.wordBytes]
  have enough : ¬address + count * 16 - 8 < (position * 2 + 2 - 1) * 8 := by omega
  simp only [show (2 == 0) = false from rfl, Bool.false_or, enough, decide_false, Bool.false_eq_true, ↓reduceIte]
  rw [show address + count * 16 - 8 - (position * 2 + 2 - 1) * 8 = address + (count - position - 1) * 16 by omega]
  rfl

/-- Fresh allocation already has zero tags. The actual initialization loop
    still executes every store and increment, reaches capacity, and retains
    that allocation's bytes and the caller's cells. -/
theorem actualInitialize (count address : Nat) (fits : count < 2 ^ 31)
    (formed : base.CellsWellFormed) (unique : HeapBlockBasesUnique base.heap) (noViews : base.i32ArrayViews = [])
    (types : base.local? typesId = some (.rawSlice referenceType (address + count * 16 - 8) count))
    (capacity : base.local? (source.argumentId 1) = some (.signed .i32 count))
    (zero : ∀ position, position < count → base.heap.loadBytes (address + (count - position - 1) * 16) 4 =
      .ok (encodeNatLE 4 0)) :
    ∃ after, RunsStmt extractedProgram (base.bindLocal counterId (.signed .i32 0)) (.whileLoop loop.1 loop.2) .next after ∧
      CountedLocal base after counterId count ∧ after.heap = base.heap ∧
      after.world = base.world ∧ after.i32ArrayViews = base.i32ArrayViews := by
  let invariant := fun remaining current => ∃ position : Nat, position + remaining = count ∧
    CountedLocal base current counterId position ∧ current.heap = base.heap ∧
    current.world = base.world ∧ current.i32ArrayViews = base.i32ArrayViews
  apply RunsStmt.whileCount (remaining := count) invariant
  · intro current initial
    obtain ⟨position, endCount, frame, heap, world, views⟩ := initial
    have equal : position = count := by omega
    subst position
    have indexFound := frame.counter
    have capacityFound := frame.read (source.argumentId 1) _ (by decide) capacity
    exact ⟨current, by core_run, frame, heap, world, views⟩
  · intro remaining current initial
    obtain ⟨position, progress, frame, heap, world, views⟩ := initial
    have inside : position < count := by omega
    have currentFormed := frame.cells.after_cellsWellFormed formed
    have indexFound := frame.counter
    have typesFound := frame.read typesId _ (by decide) types
    have capacityFound := frame.read (source.argumentId 1) _ (by decide) capacity
    have tag : current.heap.loadBytes (address + (count - position - 1) * 16) 4 = .ok (encodeNatLE 4 0) := by
      rw [heap]; exact zero position inside
    have currentUnique : HeapBlockBasesUnique current.heap := by rw [heap]; exact unique
    have stored : writeNativeValue 64 extractedProgram current current.heap referenceType
        (address + (count - position - 1) * 16) invalid = .ok current.heap :=
      writeNativeValue_enumEmpty_same (by core_lookup) rfl currentUnique tag
    have store : RunsExpr extractedProgram current (source.effectExpression 0) .unit current :=
      RunsExpr.ofStable (StableExpr.assignRaw (before := current) (indexed := current) (ready := current)
        typesFound (.local indexFound) inside (location inside)
        (by rw [views]; exact noViews) (by core_expr_step) stored) rfl
    obtain ⟨next, increment, counter, sameHeap, sameWorld, sameViews⟩ := frame.increment (index := position)
      (program := extractedProgram) formed (by omega)
    refine ⟨current, next, .next, by core_run, by core_stmt_forward, Or.inl rfl,
      position + 1, by omega, counter, sameHeap.trans heap, sameWorld.trans world, sameViews.trans views⟩
  · exact ⟨0, by omega, CountedLocal.start formed _ _, rfl, rfl, rfl⟩

/-- The allocator case used by body_catalog: one aligned, zero-filled region.
    These are backing-memory facts, not a successful constructor or valid IR. -/
structure FreshRegion (state : State) where
  memory : Nat
  count : Nat
  block : Block
  positive : 0 < count
  bytesFit : count * 56 < 2 ^ 31
  pointerFit : memory + count * 56 < 2 ^ 64
  aligned : memory % 8 = 0
  eventBlock : state.heap.containingBlock? memory = some block
  typeBlock : state.heap.containingBlock? (memory + count * 40) = some block
  alignment : 8 ≤ block.alignment
  bounds : memory + count * 56 ≤ block.base + block.size
  readable : state.heap.Readable memory (count * 56)
  zero : ∀ position, position < count → state.heap.loadBytes
    (memory + count * 40 + (count - position - 1) * 16) 4 = .ok (encodeNatLE 4 0)

def FreshRegion.eventPointer (input : FreshRegion state) := input.memory + input.count * 40 - 8
def FreshRegion.typeBase (input : FreshRegion state) := input.memory + input.count * 40
def FreshRegion.typePointer (input : FreshRegion state) := input.typeBase + input.count * 16 - 8
def FreshRegion.value (input : FreshRegion state) : Value :=
  source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice eventType input.eventPointer input.count, .rawSlice referenceType input.typePointer input.count,
      .boolean true, .signed .i32 input.count]
def FreshRegion.call (input : FreshRegion state) : Expr :=
  .call source.id [.value (.pointer input.memory), .value (.signed .i32 input.count)]

/-- Complete actual constructor on the compiler's fresh-allocation domain:
    native pointers/descriptors, every initialized slot, ownership transfer,
    termination, and preservation of the allocation's bytes and caller cells. -/
theorem actualRegion (input : FreshRegion before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before input.call input.value after ∧
      FreshCellFrame before after ∧ after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews ∧
      after.heap = before.heap.borrowBlock input.block.base ∧
      ∀ position, position < input.count → NativeSnapshot 64 extractedProgram after.heap referenceType
        (input.typeBase + (input.count - position - 1) * 16) invalid 16 := by
  let bindings := [(source.argumentId 0, Value.pointer input.memory),
    (source.argumentId 1, Value.signed .i32 input.count)]
  let callee := ({ before with locals := [] }).bindLocals bindings
  let first := callee.bindLocal (source.bindingId 0) (.pointer input.eventPointer)
  let based := first.bindLocal (source.bindingId 1) (.pointer input.typeBase)
  let pointed := based.bindLocal (source.bindingId 2) (.pointer input.typePointer)
  let borrowed := { pointed with heap := before.heap.borrowBlock input.block.base }
  let descriptor := Value.rawSlice referenceType input.typePointer input.count
  let base := borrowed.bindLocal typesId descriptor
  have calleeFormed : callee.CellsWellFormed := by core_formed
  have firstFormed : first.CellsWellFormed := by core_formed
  have basedFormed : based.CellsWellFormed := by core_formed
  have pointedFormed : pointed.CellsWellFormed := by core_formed
  have baseFormed : base.CellsWellFormed := by core_formed
  have capacityFits := input.bytesFit
  have pointerFits := input.pointerFit
  have positive := input.positive
  have eventAdd := eval_pointer_addNat extractedProgram.target input.memory (input.count * 40) (by
    change input.memory + input.count * 40 < 2 ^ 64; omega)
  have eventSubtract := eval_pointer_subNat extractedProgram.target (input.memory + input.count * 40) 8 (by omega) (by
    change input.memory + input.count * 40 < 2 ^ 64; omega)
  have typeAdd := eval_pointer_addNat extractedProgram.target input.typeBase (input.count * 16) (by
    change input.memory + input.count * 40 + input.count * 16 < 2 ^ 64; omega)
  have typeSubtract := eval_pointer_subNat extractedProgram.target (input.typeBase + input.count * 16) 8 (by
    change 8 ≤ input.memory + input.count * 40 + input.count * 16; omega) (by
    change input.memory + input.count * 40 + input.count * 16 < 2 ^ 64; omega)
  have firstRun : RunsExpr extractedProgram callee (source.bindingInitializer 0) (.pointer input.eventPointer) callee := by core_run
  have baseRun : RunsExpr extractedProgram first (source.bindingInitializer 1) (.pointer input.typeBase) first := by core_run
  have pointerRun : RunsExpr extractedProgram based (source.bindingInitializer 2) (.pointer input.typePointer) based := by core_run
  have typeConstruct : mapRawNominalSlice extractedProgram pointed referenceType input.typePointer input.count =
      .done descriptor borrowed := by
    have start : input.typePointer + 8 - input.count * 2 * 8 = input.typeBase := by
      dsimp only [FreshRegion.typePointer, FreshRegion.typeBase]; omega
    apply mapRawNominalSlice_of_block (block := input.block) input.count positive rfl typeWidth (by decide)
    · change input.count * 2 * 8 ≤ input.memory + input.count * 40 + input.count * 16 - 8 + 8; omega
    · change before.heap.containingBlock? (input.typePointer + 8 - input.count * 2 * 8) = some input.block
      rw [start]; exact input.typeBlock
    · change (input.typePointer + 8 - input.count * 2 * 8) % 8 = 0
      rw [start]
      dsimp only [FreshRegion.typeBase]
      have aligned := input.aligned
      omega
    · exact input.alignment
    · dsimp only [FreshRegion.typePointer, FreshRegion.typeBase, NativeLayout.wordBytes]
      have room := input.bounds
      omega
    · exact unique
  have typeRun : RunsExpr extractedProgram pointed (source.bindingInitializer 3) descriptor borrowed :=
    RunsExpr.nominalSliceFromParts (by core_run) (by core_run) typeConstruct rfl
  obtain ⟨loopAfter, loopRun, counter, heap, world, views⟩ := actualInitialize input.count input.typeBase
    (by omega) baseFormed unique.borrowBlock noViews (by core_local) (by core_local) (by
      intro position inside
      change (before.heap.borrowBlock input.block.base).loadBytes _ 4 = _
      rw [Heap.loadBytes_borrowBlock]
      exact input.zero position inside)
  have eventPointerFound := counter.read (source.bindingId 0) _ (by decide) (by core_local)
  have capacityFound := counter.read (source.argumentId 1) _ (by decide) (by core_local)
  have typesFound := counter.read typesId _ (by decide) (by core_local)
  have eventWidth : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
  have eventConstruct : mapRawNominalSlice extractedProgram loopAfter eventType input.eventPointer input.count =
      .done (.rawSlice eventType input.eventPointer input.count) loopAfter := by
    have borrowedBlock := Heap.containingBlock?_borrowSelected input.eventBlock
    have start : input.eventPointer + 8 - input.count * 5 * 8 = input.memory := by
      dsimp only [FreshRegion.eventPointer]; omega
    have currentUnique : HeapBlockBasesUnique loopAfter.heap := by rw [heap]; exact unique.borrowBlock
    have constructed : mapRawNominalSlice extractedProgram loopAfter eventType input.eventPointer input.count =
        .done (.rawSlice eventType input.eventPointer input.count)
          { loopAfter with heap := loopAfter.heap.borrowBlock input.block.base } := by
      apply mapRawNominalSlice_of_block (block := { input.block with owned := false })
        input.count positive rfl eventWidth (by decide)
      · change input.count * 5 * 8 ≤ input.memory + input.count * 40 - 8 + 8; omega
      · change loopAfter.heap.containingBlock? (input.eventPointer + 8 - input.count * 5 * 8) = _
        rw [heap, start]; exact borrowedBlock
      · change (input.eventPointer + 8 - input.count * 5 * 8) % 8 = 0
        rw [start]; exact input.aligned
      · exact input.alignment
      · change input.eventPointer + 8 ≤ input.block.base + input.block.size
        dsimp only [FreshRegion.eventPointer, NativeLayout.wordBytes]
        have room := input.bounds
        omega
      · exact currentUnique
    have unchanged : loopAfter.heap.borrowBlock input.block.base = loopAfter.heap := by
      rw [heap]; exact Heap.borrowBlock_idempotent _ _
    simpa only [unchanged] using constructed
  have eventRun : RunsExpr extractedProgram loopAfter
      (.typedSliceFromRawParts eventType (.local (source.bindingId 0)) (.local (source.argumentId 1)))
      (.rawSlice eventType input.eventPointer input.count) loopAfter :=
    RunsExpr.nominalSliceFromParts (by core_run) (by core_run) eventConstruct rfl
  let completed := restoreLocals callee loopAfter
  have body : RunsStmt extractedProgram callee (source.body.getD .skip) (.returned (some input.value)) completed := by
    core_stmt_forward
  have cells := (FreshCellFrame.bindLocals ({ before with locals := [] }) bindings).trans
    ((FreshCellFrame.bindLocal callee (source.bindingId 0) (.pointer input.eventPointer)).trans
      ((FreshCellFrame.bindLocal first (source.bindingId 1) (.pointer input.typeBase)).trans
        ((FreshCellFrame.bindLocal based (source.bindingId 2) (.pointer input.typePointer)).trans
          ((FreshCellFrame.bindLocal borrowed typesId descriptor).trans counter.cells))))
  refine ⟨restoreLocals before completed, RunsExpr.call (function := source)
    (values := [.pointer input.memory, .signed .i32 input.count]) (bindings := bindings)
    (by core_lookup) rfl (RunsExprs.values [.pointer input.memory, .signed .i32 input.count]) rfl body,
    cells, world, views, heap, ?_⟩
  intro position inside
  have tag : loopAfter.heap.loadBytes (input.typeBase + (input.count - position - 1) * 16) 4 =
      .ok (encodeNatLE 4 0) := by
    rw [heap]
    change (before.heap.borrowBlock input.block.base).loadBytes _ 4 = _
    rw [Heap.loadBytes_borrowBlock]; exact input.zero position inside
  exact (NativeSnapshot.enumEmpty (fuel := 63) (by core_lookup) rfl (by decide) tag).enlarge (by decide)

#print axioms actualInitialize
#print axioms actualRegion

end IRRegionProof
