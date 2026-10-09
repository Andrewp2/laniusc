import verified_compiler.tests.direct_ir_catalog_build
import verified_compiler.tests.direct_ir_count_store
import Lanius.Semantics.NativeSnapshotFrame

namespace IRCatalogStoreProof
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCatalogCopyProof IRCatalogBuildProof IREventStoreProof IRTypeRefProof
open IRBuilderProof IRBuilderCallProof IRBuilderNavigationProof

variable {original before after state copied : State} {input : Input original} {budget : Option Nat}

def signature (id parameters : Int32) (result : Reference) : Value :=
  source_value Extracted.«ir::body_catalog».Types.«FunctionSignature».mk
    [.signed .i32 id.toInt, referenceValue result, .signed .i32 parameters.toInt]
def body (signature tree : Value) : Value :=
  source_value Extracted.«ir::body_catalog».Types.«FunctionBody».mk [signature, tree]
def bodyType : Ty := match body .unit .unit with | .structure id _ => .structure id | _ => .unit
def countId : TypeId := match source.bindingStatement 0 with
  | .letLocal _ (.slice (.structure id)) _ _ => id | _ => 0

/-- Original catalog storage and represented caller data. No field describes
    a future tree, a successful store, or acceptance by a guard. -/
structure Entry (input : Input original) (budget : Option Nat) where
  build : IRCatalogBuildProof.Entry input budget
  id : Int32
  parameters : Int32
  result : Reference
  next : Nat
  rowsAddress : Nat
  rowsLength : Nat
  countAddress : Nat
  countLength : Nat
  incrementFits : next + 1 < 2 ^ 31
  rowBound : next < rowsLength
  rowFloor : (next + 1) * 96 ≤ rowsAddress + 8
  countBound : 0 < countLength
  rowRoom : original.heap.Readable (rowsAddress + 8 - (next + 1) * 96) 96
  countRoom : original.heap.Readable countAddress 4
  separate : rowsAddress + 8 - (next + 1) * 96 + 96 ≤ countAddress ∨
    countAddress + 4 ≤ rowsAddress + 8 - (next + 1) * 96
  signatureFound : original.local? (source.argumentId 1) = some (signature id parameters result)
  rowsFound : original.local? (source.bindingId 1) = some (.rawSlice bodyType rowsAddress rowsLength)
  countFound : original.local? (source.bindingId 0) = some (.rawSlice (.structure countId) countAddress countLength)
  nextFound : original.local? (source.bindingId 3) = some (.signed .i32 next)

def Entry.rowBase (entry : Entry input budget) : Nat := entry.rowsAddress + 8 - (entry.next + 1) * 96
def Entry.footprint (entry : Entry input budget) (address : Nat) : Prop :=
  (entry.rowBase ≤ address ∧ address < entry.rowBase + 96) ∨
  (entry.countAddress ≤ address ∧ address < entry.countAddress + 4)

theorem actualWrites : catalogWrites = .sequence
    (.expression (source.effectExpression 5))
    (.sequence (.expression (source.effectExpression 6))
      (.returnValue (some (.local (source.bindingId 3))))) := by rfl
theorem actualRow : source.effectExpression 5 = .assign .set
    (.index (.local (source.bindingId 1)) (.local (source.bindingId 3)))
    (.structValue (match bodyType with | .structure id => id | _ => 0)
      [.local (source.argumentId 1), .local (source.bindingId 12)]) := by rfl

@[native_store_rule] theorem signatureCodec (id parameters : Int32) (result : Reference) :
    NativeStoreSpec (fuel + 3) extractedProgram
      (((source.parameters[1]?).getD (0, .unit)).2)
      (signature id parameters result) 32 := by native_store

theorem Entry.rowLocation (entry : Entry input budget) :
    rawSliceElementAddress? extractedProgram bodyType entry.rowsAddress entry.next = .ok entry.rowBase := by
  apply rawSliceElementAddress_of_layout (words := 12) rfl (by decide +kernel) (by decide)
  · have floor := entry.rowFloor; omega
  · dsimp only [Entry.rowBase]; omega

theorem nonempty (entry : IRCatalogBuildProof.Entry input budget) (live : Live input budget state) : live.value ≠ emptyTree := by
  intro empty
  have counts := congrArg (fun value => match value with
    | .structure _ fields => fields[4]? | _ => none) (live.represented.symm.trans empty)
  have zero : input.count = 0 := by
    simpa [Ready.value, Region.tree, Memory.region, emptyTree] using counts
  have positive := entry.positive
  omega

/-- The retained actual allocation identifies the endpoint descriptor and its
    readable storage. These are conclusions about the derived Live tree. -/
theorem endStorage (entry : Entry input budget) (live : Live input budget state) :
    ∃ copied, ∃ _cut : CutState input budget copied,
      live.tree.address = copied.heap.borrowedAddress ∧
      state.heap.Readable live.tree.address (input.count * 4) := by
  obtain ⟨copied, cut, post⟩ := live.memory.allocation
  rcases post.2.2.2.2.2 with failed | ⟨⟨ends, structural, room, _⟩, _metadata⟩
  · exact False.elim (nonempty entry.build live failed.1)
  · rcases structural with rejected | ⟨represented, _, _⟩
    · exact False.elim (nonempty entry.build live rejected.1)
    · have pointers := congrArg (fun value => match value with
        | .structure _ fields => fields[3]? | _ => none) (live.represented.symm.trans represented)
      have address : live.tree.address = copied.heap.borrowedAddress := by
        simpa [Ready.value, Region.tree, Memory.region, CutState.region] using pointers
      exact ⟨copied, cut, address, by simpa only [address, CutState.region] using room⟩

theorem endpoint (entry : Entry input budget) (cut : CutState input budget copied) :
    copied.heap.borrowedAddress = input.memory + input.count * 56 := by
  have positive := entry.build.positive
  have extent : max (input.count * 56) 1 = input.count * 56 := by omega
  have frontier : copied.heap.nextAddress = input.memory + input.count * 56 := by
    simpa only [Input.freshHeap, Input.memory, Heap.borrowBlock, Heap.allocatedBytes, extent] using cut.writes.frontier
  have aligned := original.heap.allocationAddress_aligned (alignment := 8)
  have addressPositive := original.heap.allocationAddress_pos (by decide : 0 < 8)
  change input.memory % 8 = 0 at aligned
  change 0 < input.memory at addressPositive
  have multiple : (input.memory + input.count * 56) % 4 = 0 := by omega
  have division := Nat.mod_add_div (input.memory + input.count * 56) 4
  simp only [Heap.borrowedAddress, frontier, alignUp]
  rw [Nat.max_eq_left (by omega : 1 ≤ input.memory + input.count * 56)]
  rw [show input.memory + input.count * 56 + 4 - 1 = input.memory + input.count * 56 + 3 by omega]
  rw [Nat.add_div (a := input.memory + input.count * 56) (b := 3) (by decide : 0 < 4)]
  simp only [multiple, Nat.zero_add, show 3 / 4 = 0 from rfl, show 3 % 4 = 3 from rfl,
    if_neg (by decide : ¬4 ≤ 3), Nat.add_zero]
  rw [Nat.mul_comm]
  simpa only [multiple, Nat.zero_add] using division

theorem descriptorBounds (entry : Entry input budget) (live : Live input budget state) :
    input.eventPointer < 2 ^ 64 ∧ input.typePointer < 2 ^ 64 ∧
    live.tree.address < 2 ^ 64 ∧ input.count < 2 ^ 64 := by
  obtain ⟨copied, cut, address, _⟩ := endStorage entry live
  have pointerFits := entry.build.pointerFits
  have countFits := entry.build.fits
  rw [address, endpoint entry cut]
  dsimp only [Input.eventPointer, Input.typePointer]
  omega

private theorem naturalWord (number : Nat) (fits : number < 2 ^ 31) :
    (BitVec.ofInt 32 number).toInt = number := by
  apply BitVec.toInt_ofInt_eq_self (by decide) <;> omega

theorem bodyCodec (entry : Entry input budget) (live : Live input budget state) :
    NativeStoreSpec 64 extractedProgram bodyType
      (body (signature entry.id entry.parameters entry.result) live.value) 96 := by
  obtain ⟨events, types, endpoints, length⟩ := descriptorBounds entry live
  have countFits : input.count < 2 ^ 31 := by have fits := entry.build.fits; omega
  have countCodec : NativeStoreSpec 62 extractedProgram (.scalar (.signed .i32))
      (.signed .i32 input.count) 8 := by
    simpa only [naturalWord input.count countFits] using
      (NativeStoreSpec.i32 (program := extractedProgram) (fuel := 61) (BitVec.ofInt 32 input.count)).enlarge (by decide : 4 ≤ 8)
  have represented : live.value = IRValidatorProof.treeValue
      (.rawSlice eventType input.eventPointer input.count)
      (.rawSlice referenceType input.typePointer input.count) true
      (.rawSlice (.scalar (.signed .i32)) live.tree.address input.count) input.count := live.represented
  have codec : NativeStoreSpec 64 extractedProgram bodyType
      (body (signature entry.id entry.parameters entry.result)
        (IRValidatorProof.treeValue (.rawSlice eventType input.eventPointer input.count)
          (.rawSlice referenceType input.typePointer input.count) true
          (.rawSlice (.scalar (.signed .i32)) live.tree.address input.count) input.count)) 96 := by
    native_store
  simpa only [represented] using codec

/-- Catalog writes only: the built heap supplies the reference state. The
    overwritten catalog bytes are deliberately not claimed to be unchanged. -/
structure Stored (entry : Entry input budget) (live : Live input budget before) (after : State) : Prop where
  writes : HeapWritesOn before.heap after.heap entry.footprint
  cells : FreshCellFrame original after
  locals : after.locals = original.locals
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews
  row : NativeSnapshot 64 extractedProgram after.heap bodyType entry.rowBase
    (body (signature entry.id entry.parameters entry.result) live.value) 96
  count : NativeSnapshot 64 extractedProgram after.heap (.scalar (.signed .i32)) entry.countAddress
    (.signed .i32 (entry.next + 1)) 4
  tree : ∃ ready : Ready live.memory.region after,
    ready.address = live.tree.address ∧ ready.ends = live.tree.ends
  types : ∀ index, index < input.count → readRawSliceIndex extractedProgram after referenceType
    input.typePointer input.count index = .ok (input.annotation index)

def Post (entry : Entry input budget) (completion : Completion) (after : State) : Prop :=
  (completion = .returned (some (.signed .i32 (-1))) ∧ Memory input budget emptyTree after ∧
    after.locals = original.locals) ∨
  (completion = .returned (some (.signed .i32 entry.next)) ∧
    ∃ before, ∃ live : Live input budget before, Stored entry live after)

/-- Both real assignments and the return, with no guard or store execution
    assumed. The reference heap is the actual derived live build state. -/
private theorem actualWritesRun (entry : Entry input budget) (live : Live input budget before) :
    ∃ middle heap, RunsStmt extractedProgram before catalogWrites
      (.returned (some (.signed .i32 entry.next))) { before with heap } ∧
      HeapRegionWrite before.heap middle entry.rowBase 96 ∧
      HeapRegionWrite middle heap entry.countAddress 4 ∧
      NativeSnapshot 64 extractedProgram heap bodyType entry.rowBase
        (body (signature entry.id entry.parameters entry.result) live.value) 96 ∧
      NativeSnapshot 64 extractedProgram heap (.scalar (.signed .i32)) entry.countAddress
        (.signed .i32 (entry.next + 1)) 4 := by
  have signatureFound := live.memory.callerFound (by decide +kernel) entry.signatureFound
  have rowsFound := live.memory.callerFound (by decide +kernel) entry.rowsFound
  have countFound := live.memory.callerFound (by decide +kernel) entry.countFound
  have nextFound := live.memory.callerFound (by decide +kernel) entry.nextFound
  have treeFound := live.found
  have countRoom := live.memory.reads.readable entry.countRoom
  obtain ⟨middle, rowRun, rowSnapshot, rowWrite⟩ := RunsExpr.assignRawNative
    (program := extractedProgram) (before := before) (indexed := before) (ready := before)
    (indexExpression := .local (source.bindingId 3))
    (expression := .structValue (match bodyType with | .structure id => id | _ => 0)
      [.local (source.argumentId 1), .local (source.bindingId 12)])
    rowsFound (by core_run) entry.rowBound
    entry.rowLocation (bodyCodec entry live) (live.memory.reads.readable entry.rowRoom)
    live.memory.unique live.memory.noViews (by core_run)
  let writing := { before with heap := middle }
  have nextFound : writing.local? (source.bindingId 3) = some (.signed .i32 entry.next) := nextFound
  have countFound : writing.local? (source.bindingId 0) =
      some (.rawSlice (.structure countId) entry.countAddress entry.countLength) := countFound
  obtain ⟨heap, countRun, countSnapshot, countWrite⟩ := IRCountStoreProof.actualCountStore
    (state := writing) countFound nextFound entry.countBound entry.incrementFits
    (rowWrite.readable _ _ countRoom) rowWrite.unique live.memory.noViews
  have rowRun : RunsExpr extractedProgram before (source.effectExpression 5) .unit writing := by
    simpa only [actualRow, body, bodyType] using rowRun
  have countRun : RunsExpr extractedProgram writing (source.effectExpression 6) .unit { before with heap } := by
    simpa only [IRCountStoreProof.source, IRCatalogCopyProof.source, writing] using countRun
  refine ⟨middle, heap, ?_, rowWrite, ?_,
    rowSnapshot.afterWrite countWrite (by have apart := entry.separate; dsimp only [Entry.rowBase] at *; omega), ?_⟩
  · rw [actualWrites]
    have returnedFound : ({ before with heap } : State).local? (source.bindingId 3) =
        some (.signed .i32 entry.next) := nextFound
    core_stmt
  · exact countWrite
  · exact countSnapshot

private theorem copiedSnapshots (memory : Memory input budget value state) (inside : index < input.count) :
    NativeSnapshot 64 extractedProgram state.heap eventType (input.eventBase index) (input.events index) 40 ∧
    NativeSnapshot 64 extractedProgram state.heap referenceType (input.typeBase index) (input.annotation index) 16 := by
  obtain ⟨_, cut, post⟩ := memory.allocation
  exact ⟨(cut.eventSnapshots index inside).afterHeapReads post.1,
    (cut.typeSnapshots index inside).afterHeapReads post.1⟩

/-- Close the final stores while preserving the already-built physical tree.
    Initial readable catalog slots lie below the actual fresh copy/ends. -/
theorem actualStores (entry : Entry input budget) (live : Live input budget before) :
    ∃ after, RunsStmt extractedProgram before catalogWrites
      (.returned (some (.signed .i32 entry.next))) after ∧ Stored entry live (restoreLocals original after) := by
  obtain ⟨middle, heap, run, rowWrite, countWrite, row, count⟩ := actualWritesRun entry live
  let after := { before with heap }
  have rowBound : entry.rowBase + 96 ≤ input.memory :=
    Nat.le_trans (entry.rowRoom.belowNext (by decide) input.below) (original.heap.allocationAddress_ge (by decide : 0 < 8))
  have countBound : entry.countAddress + 4 ≤ input.memory :=
    Nat.le_trans (entry.countRoom.belowNext (by decide) input.below) (original.heap.allocationAddress_ge (by decide : 0 < 8))
  have events : ∀ index, index < input.count → readRawSliceIndex extractedProgram after eventType
      input.eventPointer input.count index = .ok (input.events index) := by
    intro index inside
    have snapshot := (copiedSnapshots live.memory inside).1
    have preserved := (snapshot.afterWrite rowWrite (Or.inr (by dsimp only [Input.eventBase]; omega))).afterWrite
      countWrite (Or.inr (by dsimp only [Input.eventBase]; omega))
    unfold readRawSliceIndex
    rw [if_neg (Nat.not_le_of_lt inside)]
    change (rawSliceElementAddress? extractedProgram eventType input.eventPointer index).bind
      (fun base => readNativeValue 64 extractedProgram heap eventType base) = _
    rw [input.eventLocation inside]
    exact preserved.read
  have types : ∀ index, index < input.count → readRawSliceIndex extractedProgram after referenceType
      input.typePointer input.count index = .ok (input.annotation index) := by
    intro index inside
    have snapshot := (copiedSnapshots live.memory inside).2
    have preserved := (snapshot.afterWrite rowWrite (Or.inr (by dsimp only [Input.typeBase]; omega))).afterWrite
      countWrite (Or.inr (by dsimp only [Input.typeBase]; omega))
    unfold readRawSliceIndex
    rw [if_neg (Nat.not_le_of_lt inside)]
    change (rawSliceElementAddress? extractedProgram referenceType input.typePointer index).bind
      (fun base => readNativeValue 64 extractedProgram heap referenceType base) = _
    rw [input.typeLocation inside]
    exact preserved.read
  obtain ⟨copied, cut, address, endRoom⟩ := endStorage entry live
  have endsLower : input.memory ≤ live.tree.address := by rw [address, endpoint entry cut]; omega
  have firstEnds := i32Table_afterRegionWrite (program := extractedProgram)
    (pointer := live.tree.address) (count := input.count) (capacity := input.count) (values := live.tree.ends)
    (before := before) (after := { before with heap := middle }) rowWrite (Nat.le_refl _)
    endRoom (Or.inr (by omega)) live.tree.contents
  have finalEnds := i32Table_afterRegionWrite (program := extractedProgram)
    (pointer := live.tree.address) (count := input.count) (capacity := input.count) (values := live.tree.ends)
    (before := { before with heap := middle }) (after := after) countWrite (Nat.le_refl _)
    (rowWrite.readable _ _ endRoom) (Or.inr (by omega)) firstEnds
  let ready : Ready live.memory.region (restoreLocals original after) := {
    address := live.tree.address, ends := live.tree.ends, suffix := live.tree.suffix, root := live.tree.root
    eventReads := events, contents := finalEnds }
  refine ⟨after, run, ?_, live.memory.cells, rfl, rfl, rfl, row, count, ⟨ready, rfl, rfl⟩, types⟩
  exact (rowWrite.footprint.weaken (fun _ inside => Or.inl inside)).trans
    (countWrite.footprint.weaken (fun _ inside => Or.inr inside))

theorem rejectImpossible (entry : IRCatalogBuildProof.Entry input budget) {canonical : Nat → Int}
    (shape : input.toRegion.toSource.Suffix canonical 0) (root : canonical 0 = (input.count : Int))
    (second : consumeBudget budget (input.count * 4) ≠ none)
    (memory : Memory input budget emptyTree state) : False := by
  obtain ⟨copied, cut, post⟩ := memory.allocation
  have shape : cut.region.toSource.Suffix canonical 0 := shape
  have root : canonical 0 = (cut.region.count : Int) := root
  have positive : 0 < cut.region.count := entry.positive
  rcases post.2.2.2.2.2 with ⟨_, failed, _heap⟩ | ⟨⟨ends, structural, _, _⟩, _metadata⟩
  · have available : consumeBudget copied.heap.remaining (cut.region.count * 4) ≠ none := by
      simpa only [cut.writes.budget, CutState.region, Input.freshHeap, Heap.borrowBlock, Heap.allocatedBytes] using second
    cases consumed : consumeBudget copied.heap.remaining (cut.region.count * 4) with
    | none => exact available consumed
    | some rest =>
      simp only [IRAllocationProof.allocation, consumed] at failed
      exact (Nat.ne_of_gt copied.heap.borrowedAddress_pos) failed
  · rcases structural with ⟨_, bad⟩ | ⟨represented, _, _⟩
    · rcases bad with ⟨index, inside, later, bad⟩ | ⟨suffix, notSingle⟩
      · exact cut.region.toSource.noBadNode shape later inside bad
      · exact notSingle ((cut.region.toSource.equalEndpoints suffix shape 0
          (Nat.zero_le _) positive).trans root)
    · have counts := congrArg (fun value => match value with
        | .structure _ fields => fields[4]? | _ => none) represented
      have zero : input.count = 0 := by
        have equal : (0 : Int) = input.count := by simpa [Region.tree, CutState.region, emptyTree] using counts
        omega
      have positive := entry.positive
      omega

/-- The real binding-5 continuation terminates: rejection returns -1 with
    catalog bytes intact; success executes both stores and returns next. -/
theorem actualStore (entry : Entry input budget) :
    ∃ completion after, RunsStmt extractedProgram original (source.bindingStatement 5) completion after ∧
      Post entry completion after := by
  apply actualSourceContinuation entry.build (Post entry)
  · intro state memory
    exact Or.inl ⟨rfl, memory.restoreLocals, rfl⟩
  · intro state live
    obtain ⟨after, run, stored⟩ := actualStores entry live
    exact ⟨_, after, run, Or.inr ⟨rfl, state, live, stored⟩⟩

/-- Independent canonical one-root shape and second-allocation budget force
    the actual success return. Neither execution nor validity is a premise. -/
theorem actualSuccess (entry : Entry input budget) {canonical : Nat → Int}
    (shape : input.toRegion.toSource.Suffix canonical 0) (root : canonical 0 = (input.count : Int))
    (second : consumeBudget budget (input.count * 4) ≠ none) :
    ∃ after, RunsStmt extractedProgram original (source.bindingStatement 5)
      (.returned (some (.signed .i32 entry.next))) after ∧
      ∃ before, ∃ live : Live input budget before, Stored entry live after := by
  obtain ⟨completion, after, run, rejected | ⟨returned, stored⟩⟩ := actualStore entry
  · exact False.elim (rejectImpossible entry.build shape root second rejected.2.1)
  · subst completion
    exact ⟨after, run, stored⟩

/-- A disjoint original represented row survives allocation/build and both
    stores. This is scoped initial storage evidence, not a future-state input. -/
theorem Stored.otherRow {entry : Entry input budget} {live : Live input budget before}
    (stored : Stored entry live after)
    (snapshot : NativeSnapshot 64 extractedProgram original.heap bodyType pointer value 96)
    (rowApart : pointer + 96 ≤ entry.rowBase ∨ entry.rowBase + 96 ≤ pointer)
    (countApart : pointer + 96 ≤ entry.countAddress ∨ entry.countAddress + 4 ≤ pointer) :
    NativeSnapshot 64 extractedProgram after.heap bodyType pointer value 96 := by
  intro later preserved
  apply (snapshot.afterHeapReads live.memory.reads) later
  intro location width bytes lower upper loaded
  apply preserved _ _ _ lower upper
  apply stored.writes.loadBytes loaded
  intro offset inside
  dsimp only [Entry.footprint]
  rcases rowApart with left | right <;> rcases countApart with bottom | top <;> omega

#print axioms actualWrites
#print axioms bodyCodec
#print axioms actualStores
#print axioms actualStore
#print axioms actualSuccess
#print axioms Stored.otherRow

end IRCatalogStoreProof
