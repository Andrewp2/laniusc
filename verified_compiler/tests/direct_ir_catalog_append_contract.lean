import verified_compiler.tests.direct_ir_catalog_append_outer
import verified_compiler.tests.direct_ir_catalog_store

namespace IRCatalogAppendProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRShapeProof IRChildrenProof

structure PreviousRow where
  id : Int32
  parameters : Int32
  result : Reference
  tree : Value

def PreviousRow.value (row : PreviousRow) : Value :=
  IRCatalogStoreProof.body (IRCatalogStoreProof.signature row.id row.parameters row.result) row.tree

/-- Logical original data; only the active branches below connect it to heap reads. -/
structure Model extends Arguments where
  previous : Nat → PreviousRow
  events : Nat → Value
  annotations : Nat → Reference
  kinds : Nat → Kind
  arities : Nat → Int
  rules : Nat → Rule

def Arguments.request (input : Arguments) : Nat := input.eventCount.toInt.toNat
def Arguments.occupied (input : Arguments) : Nat := input.next.toInt.toNat
def Arguments.Guarded (input : Arguments) : Prop :=
  0 ≤ input.id.toInt ∧ isValidResult input.result = true ∧ 0 ≤ input.parameters.toInt ∧
  0 ≤ input.next.toInt ∧ input.next.toInt < input.capacity.toInt ∧
  0 < input.eventCount.toInt ∧ input.eventCount.toInt ≤ input.sourceCapacity.toInt
def Model.Duplicate (input : Model) : Prop :=
  ∃ index, index < input.occupied ∧ (input.previous index).id.toInt = input.id.toInt
def Arguments.Sized (input : Arguments) : Prop := 0 < input.request ∧ input.request ≤ 38347922
def Arguments.FirstAvailable (input : Arguments) (heap : Heap) : Prop :=
  ∃ budget, consumeBudget heap.remaining (input.request * 56) = some budget
def Arguments.BothAvailable (input : Arguments) (heap : Heap) : Prop :=
  ∃ first second, consumeBudget heap.remaining (input.request * 56) = some first ∧
    consumeBudget first (input.request * 4) = some second

/-- The existing builder's Node relation, stated using original shape data only. -/
def Model.Node (input : Model) (ends : Nat → Int) (index : Nat) : Prop :=
  0 ≤ input.arities index ∧ input.arities index ≤ (input.request - index - 1 : Nat) ∧
  input.kinds index ≠ .InvalidNode ∧ ∃ endpoint : Nat, ends index = endpoint ∧
    ChildChain input.request input.kinds (input.rules index) (input.arities index).toNat ends
      (input.arities index).toNat 0 (index + 1) endpoint
def Model.Canonical (input : Model) : Prop :=
  ∃ ends, (∀ index, index < input.request → input.Node ends index) ∧ ends 0 = (input.request : Int)
def Model.CopyNeeded (input : Model) (heap : Heap) : Prop :=
  input.Guarded ∧ ¬input.Duplicate ∧ input.Sized ∧ input.FirstAvailable heap
def Model.Success (input : Model) (heap : Heap) : Prop :=
  input.Guarded ∧ ¬input.Duplicate ∧ input.Sized ∧ input.BothAvailable heap ∧ input.Canonical

def Arguments.rowBase (input : Arguments) (index : Nat) : Nat := input.rowsAddress + 8 - (index + 1) * 96
def Arguments.footprint (input : Arguments) (address : Nat) : Prop :=
  (input.rowBase input.occupied ≤ address ∧ address < input.rowBase input.occupied + 96) ∨
  (input.countAddress ≤ address ∧ address < input.countAddress + 4)

/-- Only the actual success writes need this geometry; no spare-row decoder. -/
structure WriteGeometry (input : Arguments) (heap : Heap) : Prop where
  rowBound : input.occupied < input.rowsLength
  rowFloor : (input.occupied + 1) * 96 ≤ input.rowsAddress + 8
  rowRoom : heap.Readable (input.rowBase input.occupied) 96
  countRoom : heap.Readable input.countAddress 4
  separate : input.rowBase input.occupied + 96 ≤ input.countAddress ∨
    input.countAddress + 4 ≤ input.rowBase input.occupied
  countApart : ∀ index, index < input.occupied →
    input.rowBase index + 96 ≤ input.countAddress ∨ input.countAddress + 4 ≤ input.rowBase index

/-- All premises concern original values/storage, not a future phase or execution. -/
structure Input (caller : State) extends Model where
  formed : caller.CellsWellFormed
  unique : HeapBlockBasesUnique caller.heap
  below : HeapBlocksBelowNext caller.heap
  noViews : caller.i32ArrayViews = []
  countRead : toArguments.CountRead caller
  rowBound : toArguments.Guarded → toArguments.occupied ≤ rowsLength
  rowFloor : toArguments.Guarded → toArguments.occupied * 96 ≤ rowsAddress + 8
  rowSnapshots : toArguments.Guarded → ∀ index, index < toArguments.occupied →
    NativeSnapshot 64 extractedProgram caller.heap IRCatalogStoreProof.bodyType
      (toArguments.rowBase index) (previous index).value 96
  eventReads : toModel.CopyNeeded caller.heap → ∀ index, index < toArguments.request →
    readRawSliceIndex extractedProgram caller IREventStoreProof.eventType eventsAddress eventsLength index =
      .ok (events index)
  classified : toModel.CopyNeeded caller.heap → ∀ index, index < toArguments.request →
    Classifies (events index) (shapeValue (kindValue (kinds index)) (arities index) (ruleValue (rules index)))
  represented : toModel.CopyNeeded caller.heap → ∀ index, index < toArguments.request →
    ∃ first second third flag kind sliceKind pointer length,
      pointer < 2 ^ 64 ∧ length < 2 ^ 64 ∧ events index ∈
        IREventCodecProof.representedEvents first second third flag kind sliceKind pointer length
  annotationReads : toModel.CopyNeeded caller.heap → hasResultTypes = true →
    ∀ index, index < toArguments.request → readRawSliceIndex extractedProgram caller
      IREventStoreProof.referenceType resultAddress resultLength index = .ok (referenceValue (annotations index))
  freshFits : toModel.CopyNeeded caller.heap → caller.heap.allocationAddress 8 + toArguments.request * 56 < 2 ^ 64
  geometry : toModel.Success caller.heap → WriteGeometry toArguments caller.heap

theorem Arguments.requestFits (input : Arguments) : input.request < 2 ^ 31 := by
  have upper := input.eventCount.toInt_lt
  dsimp only [Arguments.request]
  omega

theorem Arguments.occupiedFits (input : Arguments) : input.occupied < 2 ^ 31 := by
  have upper := input.next.toInt_lt
  dsimp only [Arguments.occupied]
  omega

/-- One original-heap rebase supplies the accepted copy/build entry, only when copying is needed. -/
def Input.copyInput (input : Input caller) (active : input.CopyNeeded caller.heap)
    (state : State) (sameHeap : state.heap = caller.heap) : IRCatalogCopyProof.Input state := {
  count := input.request, capacity := input.sourceCapacity.toInt
  eventsAddress := input.eventsAddress, eventsLength := input.eventsLength, events := input.events
  resultAddress := input.resultAddress, resultLength := input.resultLength
  hasResultTypes := input.hasResultTypes, annotations := input.annotations
  kinds := input.kinds, arities := input.arities, rules := input.rules
  fits := input.toArguments.requestFits
  below := by rw [sameHeap]; exact input.below
  reads := by
    intro index inside
    change readRawSliceIndex extractedProgram state IREventStoreProof.eventType
      input.eventsAddress input.eventsLength index = .ok (input.events index)
    simpa only [readRawSliceIndex, sameHeap] using input.eventReads active index inside
  classified := input.classified active
  represented := input.represented active
  annotationReads := by
    intro enabled index inside
    simpa only [readRawSliceIndex, sameHeap] using input.annotationReads active enabled index inside }

theorem Input.copyValue (input : Input caller) (active : input.CopyNeeded caller.heap)
    (sameHeap : state.heap = caller.heap) :
    (input.copyInput active state sameHeap).value = input.region := by rfl

theorem Input.copySuffix (input : Input caller) (active : input.CopyNeeded caller.heap)
    (sameHeap : state.heap = caller.heap) :
    (input.copyInput active state sameHeap).toRegion.toSource.Suffix ends 0 ↔
      ∀ index, index < input.request → input.Node ends index := by
  constructor
  · intro suffix index inside; exact suffix index (Nat.zero_le _) inside
  · intro suffix index _ inside; exact suffix index inside

/-- Every actual outer-guard rejection, including the pure helper call, precedes backing reads. -/
theorem actualGuardReject (input : Arguments) (formed : caller.CellsWellFormed)
    (countRead : input.CountRead caller) (rejected : ¬input.Guarded) :
    ∃ after, RunsExpr extractedProgram caller input.call (.signed .i32 (-1)) after ∧
      PureFrame caller after := by
  unfold Arguments.CountRead at countRead
  unfold Arguments.Guarded at rejected
  core_call_pure source as callee
  repeat' (apply RunsStmt.letPure; core_run; core_formed)
  apply RunsStmt.guardFramedTrue (by simp)
  · apply RunsExpr.booleanPure
    · repeat' (any_goals (first | apply RunsExpr.logicalOrPure | intro middle frame))
      all_goals core_pure_expr
    · core_guard_logic
  · intro middle frame
    core_pure

#print axioms actualGuardReject

end IRCatalogAppendProof
