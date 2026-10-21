import verified_compiler.tests.direct_ir_region_allocation
import verified_compiler.tests.direct_ir_event_codecs
import verified_compiler.tests.direct_ir_builder_call
import Lanius.Semantics.RawSlice

namespace IRCatalogCopyProof
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IREventStoreProof IREventCodecProof IRTypeRefProof IRRegionAllocationProof
open IRBuilderProof IRBuilderCallProof

def source := Extracted.«ir::body_catalog».Functions.«append».core
def tail : Stmt := source.bindingStatement 12
private def plug (continuation : Stmt) : Stmt → Stmt
  | .letLocal id type initial body =>
      if id = source.bindingId 12 then continuation else .letLocal id type initial (plug continuation body)
  | .sequence first second => .sequence (plug continuation first) (plug continuation second)
  | other => other
def «prefix» (continuation : Stmt) : Stmt := plug continuation (source.bindingStatement 5)
theorem actualDecomposition : «prefix» tail = source.bindingStatement 5 := by rfl

/-- Existing signature, count, rows and next cells consumed by catalog writes. -/
def callerIds : List VarId :=
  [source.argumentId 1, source.bindingId 0, source.bindingId 1, source.bindingId 3]

structure Input (original : State) extends Region original where
  annotations : Nat → Reference
  represented : ∀ index, index < count → ∃ first second third flag kind sliceKind pointer length,
    pointer < 2 ^ 64 ∧ length < 2 ^ 64 ∧ events index ∈
      representedEvents first second third flag kind sliceKind pointer length
  annotationReads : hasResultTypes = true → ∀ index, index < count →
    readRawSliceIndex extractedProgram original referenceType resultAddress resultLength index =
      .ok (referenceValue (annotations index))

def Input.annotation (input : Input original) (index : Nat) : Value :=
  if input.hasResultTypes then referenceValue (input.annotations index) else invalid
def Input.memory (_input : Input original) : Nat := original.heap.allocationAddress 8
def Input.freshHeap (input : Input original) (budget : Option Nat) : Heap :=
  (original.heap.allocatedBytes (input.count * 56) 8 budget).borrowBlock input.memory
def Input.eventPointer (input : Input original) : Nat := input.memory + input.count * 40 - 8
def Input.typePointer (input : Input original) : Nat := input.memory + input.count * 56 - 8
def Input.eventBase (input : Input original) (index : Nat) : Nat :=
  input.memory + (input.count - index - 1) * 40
def Input.typeBase (input : Input original) (index : Nat) : Nat :=
  input.memory + input.count * 40 + (input.count - index - 1) * 16

theorem Input.eventLocation (input : Input original) (inside : index < input.count) :
    rawSliceElementAddress? extractedProgram eventType input.eventPointer index = .ok (input.eventBase index) := by
  apply rawSliceElementAddress_of_layout (words := 5) rfl (by decide +kernel) (by decide)
  all_goals dsimp only [Input.eventPointer, Input.eventBase]; omega

theorem Input.typeLocation (input : Input original) (inside : index < input.count) :
    rawSliceElementAddress? extractedProgram referenceType input.typePointer index = .ok (input.typeBase index) := by
  apply rawSliceElementAddress_of_layout (words := 2) rfl (by decide +kernel) (by decide)
  all_goals dsimp only [Input.typePointer, Input.typeBase]; omega

theorem Input.codec (input : Input original) (inside : index < input.count) :
    NativeStoreSpec 64 extractedProgram eventType (input.events index) 40 := by
  obtain ⟨first, second, third, flag, kind, sliceKind, pointer, length, pointerFits, lengthFits, member⟩ :=
    input.represented index inside
  exact representedCodecs first second third flag kind sliceKind pointer length pointerFits lengthFits _ member

/-- Open state just before the actual index binding. Allocation, guards and
    descriptor scopes establish this; the copy loop does not assume its output. -/
structure Seed (input : Input original) (budget : Option Nat) (base : State) where
  formed : base.CellsWellFormed
  cells : FreshCellFrame original base
  callerCells : ∀ id, id ∈ callerIds → base.cellId? id = original.cellId? id
  reads : HeapReads original.heap base.heap
  heap : base.heap = input.freshHeap budget
  unique : HeapBlockBasesUnique base.heap
  below : HeapBlocksBelowNext base.heap
  world : base.world = World.record original.world .alloc
  views : base.i32ArrayViews = original.i32ArrayViews
  noViews : base.i32ArrayViews = []
  sourceFound : base.local? (source.argumentId 2) = some input.value
  sourceEvents : base.local? (source.bindingId 2) =
    some (.rawSlice eventType input.eventsAddress input.eventsLength)
  countFound : base.local? (source.argumentId 3) = some (.signed .i32 input.count)
  owned : base.local? (source.bindingId 7) = some (regionValue input.memory input.count)
  events : base.local? (source.bindingId 8) = some (.rawSlice eventType input.eventPointer input.count)
  types : base.local? (source.bindingId 9) = some (.rawSlice referenceType input.typePointer input.count)
  sourceTypes : base.local? (source.bindingId 10) =
    some (.rawSlice referenceType input.resultAddress input.resultLength)

structure CutState (input : Input original) (budget : Option Nat) (state : State) : Prop where
  cells : FreshCellFrame original state
  callerCells : ∀ id, id ∈ callerIds → state.cellId? id = original.cellId? id
  reads : HeapReads original.heap state.heap
  writes : HeapRegionWrite (input.freshHeap budget) state.heap input.memory (input.count * 56)
  world : state.world = World.record original.world .alloc
  views : state.i32ArrayViews = original.i32ArrayViews
  below : HeapBlocksBelowNext state.heap
  eventSnapshots : ∀ index, index < input.count → NativeSnapshot 64 extractedProgram state.heap eventType
    (input.eventBase index) (input.events index) 40
  typeSnapshots : ∀ index, index < input.count → NativeSnapshot 64 extractedProgram state.heap referenceType
    (input.typeBase index) (input.annotation index) 16
  owned : state.local? (source.bindingId 7) = some (regionValue input.memory input.count)
  countFound : state.local? (source.argumentId 3) = some (.signed .i32 input.count)

theorem CutState.eventReads (cut : CutState input budget state) (index : Nat) (inside : index < input.count) :
    readRawSliceIndex extractedProgram state eventType input.eventPointer input.count index = .ok (input.events index) := by
  rw [readRawSliceIndex, if_neg (Nat.not_le_of_lt inside), input.eventLocation inside]
  exact (cut.eventSnapshots index inside).read

theorem CutState.typeReads (cut : CutState input budget state) (index : Nat) (inside : index < input.count) :
    readRawSliceIndex extractedProgram state referenceType input.typePointer input.count index = .ok (input.annotation index) := by
  rw [readRawSliceIndex, if_neg (Nat.not_le_of_lt inside), input.typeLocation inside]
  exact (cut.typeSnapshots index inside).read

/-- Fixed copied descriptors and inherited classification, with actual reads. -/
def CutState.region (cut : CutState input budget state) : Region state := {
  count := input.count, capacity := input.count
  eventsAddress := input.eventPointer, eventsLength := input.count, events := input.events
  resultAddress := input.typePointer, resultLength := input.count, hasResultTypes := true
  kinds := input.kinds, arities := input.arities, rules := input.rules
  fits := input.fits, below := cut.below, reads := cut.eventReads, classified := input.classified }

end IRCatalogCopyProof
