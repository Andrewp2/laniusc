import verified_compiler.tests.direct_ir_owned_interface_frame
import verified_compiler.tests.direct_ir_owned_interface_effects

namespace IRBodyOwnedProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs
open IRValueCatalogValid IRBodyProductionProof IRBodyProductionInputs
open IRCatalogConstructionProof IRCatalogAppendProof

variable {origin : State} {raw : RawInputs} {workspace : RawWorkspace}
  {normal : NormalTable raw.allocationTable origin.heap} {validation : OriginalValidation raw origin}

def OriginalScan.protected (scan : OriginalScan raw workspace normal validation) : Footprint :=
  { bytes := fun address => ¬(scan.mutable address ∨
      (scan.catalog.memory ≤ address ∧ address < scan.catalog.memory + scan.catalog.bytes))
    blocks := fun _ => True
    ownership := fun _ => False }

theorem OriginalScan.regionProtected (scan : OriginalScan raw workspace normal validation)
    (inside : scan.region address) : scan.protected.bytes address :=
  fun changed => changed.elim (scan.protectedApart address inside) (scan.catalogApart address inside)

/-- Representation carried by the scan, without lexical-state facts. -/
structure ScanStorage (scan : OriginalScan raw workspace normal validation)
    (inserted : List InsertedBody) (heap : Heap) : Prop where
  «protected» : HeapFrame scan.protected origin.heap heap
  table : (tableRep normal).holds heap
  catalogState : CatalogHeap scan.catalog (scan.initialCount.toInt.toNat + inserted.length)
    (prefixRows scan.previous scan.initialCount.toInt.toNat inserted) heap
  stored : (prefixRep inserted).holds heap

def SafeHeap (scan : OriginalScan raw workspace normal validation) (heap : Heap) : Prop :=
  ∃ inserted, ScanStorage scan inserted heap

/-- On failure a safely represented partial catalog is existentially hidden.
    The original row descriptors and arbitrary payload bytes are still fixed;
    only workspace/catalog writes and fresh allocations are permitted. -/
def SafeScan (scan : OriginalScan raw workspace normal validation) (after : State) : Prop :=
  HeapFrame scan.protected origin.heap after.heap ∧
    (tableRep normal).holds after.heap ∧
    ∃ inserted : List InsertedBody,
      Invariant scan.catalog (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length))
        (prefixRows scan.previous scan.initialCount.toInt.toNat inserted) after ∧
      ∀ (index : Nat) (entry : InsertedBody), inserted[index]? = some entry →
        entry.Stored scan.catalog (scan.initialCount.toInt.toNat + index) after.heap

theorem SafeScan.initialPayload (scan : OriginalScan raw workspace normal validation)
    (safe : SafeScan scan after) (index : Nat) (inside : index < scan.initialCount.toInt.toNat)
    (covered : (scan.occupied index inside).bytes (pointer + offset))
    (loaded : origin.heap.loadByte pointer offset = .ok byte) :
    after.heap.loadByte pointer offset = .ok byte :=
  safe.1.bytes pointer offset byte
    (scan.regionProtected (scan.occupiedCovered index inside (pointer + offset) covered)) loaded

/-- Successful output names exactly the source-selected ordered rows. Its
    native coordinates are existential witnesses, not numeric API results. -/
def SuccessfulScan (scan : OriginalScan raw workspace normal validation) (after : State) : Prop :=
  ∃ inserted : List InsertedBody,
    inserted.map InsertedBody.sourceRow = scan.selectedRows ∧
    (∀ entry ∈ inserted, scan.Source entry ∧ entry.Meaning) ∧
    Invariant scan.catalog (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length))
      (prefixRows scan.previous scan.initialCount.toInt.toNat inserted) after ∧
    ∀ (index : Nat) (entry : InsertedBody), inserted[index]? = some entry →
      entry.Stored scan.catalog (scan.initialCount.toInt.toNat + index) after.heap

def ScanResult (scan : OriginalScan raw workspace normal validation) (result : Int) (after : State) : Prop :=
  SafeScan scan after ∧
    (result = -1 ∨ (result = (scan.selectedRows.length : Int) ∧ SuccessfulScan scan after)) ∧
    (FullFunding scan → result = (scan.selectedRows.length : Int))

/-- The internal result retains one catalog witness. Lexical formation and
views are supplied only at the real public endpoint. -/
def ScanOutput (scan : OriginalScan raw workspace normal validation) (result : Int) (heap : Heap) : Prop :=
  ∃ inserted, ScanStorage scan inserted heap ∧
    (result = -1 ∨ (result = (scan.selectedRows.length : Int) ∧
      inserted.map InsertedBody.sourceRow = scan.selectedRows ∧
      ∀ entry ∈ inserted, scan.Source entry ∧ entry.Meaning)) ∧
    (FullFunding scan → result = (scan.selectedRows.length : Int))

theorem ScanOutput.failure {scan : OriginalScan raw workspace normal validation}
    (safe : SafeHeap scan heap) (impossible : ¬FullFunding scan) :
    ScanOutput scan (-1) heap := by
  obtain ⟨inserted, storage⟩ := safe
  exact ⟨inserted, storage, Or.inl rfl, fun funded => False.elim (impossible funded)⟩

theorem ScanOutput.project {scan : OriginalScan raw workspace normal validation} {after : State}
    (result : ScanOutput scan answer after.heap)
    (formed : after.CellsWellFormed) (noViews : after.i32ArrayViews = []) :
    ScanResult scan answer after := by
  obtain ⟨inserted, storage, outcome, funded⟩ := result
  have catalog := storage.catalogState.invariant formed noViews
  have stored := fun (index : Nat) (entry : InsertedBody) (found : inserted[index]? = some entry) =>
    storage.catalogState.stored storage.stored found
  refine ⟨⟨storage.protected, storage.table, inserted, catalog, stored⟩, ?_, funded⟩
  rcases outcome with negative | ⟨count, ordered, source⟩
  · exact Or.inl negative
  · exact Or.inr ⟨count, inserted, ordered, source, catalog, stored⟩

/-- The public failure projection forgets failed-prefix contents, addresses
    and attempt traces. It does not change the actual run or promise rollback. -/
noncomputable def OwnedOutcome (domain : OriginalDomain raw workspace origin) (result : Int) (after : State) : Prop := by
  classical
  exact match domain with
  | .early _ => result = -1 ∧ after.heap = origin.heap ∧ after.world = origin.world
  | .header geometry _ _ _ _ =>
      result = -1 ∧ after.heap = origin.heap.borrowBlock geometry.block.base ∧ after.world = origin.world
  | .normal table _ _ _ _ _ validation scan =>
      if valid : SemanticValidSlice validation.values validation.index table.rowValue
          0 validation.values.count.toInt raw.tokenCount.toInt then
        ScanResult (scan valid) result after
      else result = -1 ∧ after.heap = origin.heap.borrowBlock table.geometry.block.base ∧
        after.world = origin.world

def OrderedPrefix (selected : Nat → Bool) (cursor : Nat) (inserted : List InsertedBody) : Prop :=
  inserted.map InsertedBody.sourceRow = (List.range cursor).filter selected

theorem OrderedPrefix.countBound (ordered : OrderedPrefix selected cursor inserted) :
    inserted.length ≤ cursor := by
  have count := congrArg List.length ordered
  have bounded := List.length_filter_le selected (List.range cursor)
  simpa only [List.length_map, List.length_range, ← count] using bounded

theorem OrderedPrefix.skip (ordered : OrderedPrefix selected cursor inserted)
    (skipped : selected cursor = false) : OrderedPrefix selected (cursor + 1) inserted := by
  simpa only [OrderedPrefix, List.range_succ, List.filter_append, List.filter_cons,
    skipped, Bool.false_eq_true, ↓reduceIte, List.filter_nil, List.append_nil] using ordered

theorem OrderedPrefix.insert (ordered : OrderedPrefix selected cursor inserted)
    (chosen : selected cursor = true) {entry : InsertedBody} (row : entry.sourceRow = cursor) :
    OrderedPrefix selected (cursor + 1) (inserted ++ [entry]) := by
  change inserted.map InsertedBody.sourceRow = (List.range cursor).filter selected at ordered
  simp only [OrderedPrefix, List.map_append, List.map_cons, List.map_nil,
    List.range_succ, List.filter_append, List.filter_cons, chosen, ↓reduceIte,
    List.filter_nil, row, ordered]

theorem prefixRows_nil : prefixRows original start [] = original := by
  funext index
  simp only [prefixRows, List.getElem?_nil]
  split <;> rfl

theorem prefixRows_original (inside : index < start) :
    prefixRows original start inserted index = original index := by
  simp only [prefixRows, if_pos inside]

theorem prefixRows_append (previous : Nat → PreviousRow) (start : Nat)
    (entries : List InsertedBody) (entry : InsertedBody) :
    prefixRows previous start (entries ++ [entry]) = fun index =>
      if index = start + entries.length then entry.previous else prefixRows previous start entries index := by
  funext index
  by_cases before : index < start
  · simp only [prefixRows, if_pos before, if_neg (by omega : index ≠ start + entries.length)]
  · simp only [prefixRows, if_neg before]
    by_cases inside : index - start < entries.length
    · rw [List.getElem?_append_left inside, if_neg (by omega : index ≠ start + entries.length)]
    · rw [List.getElem?_append_right (by omega : entries.length ≤ index - start)]
      by_cases same : index = start + entries.length
      · subst index
        simp only [Nat.add_sub_cancel_left, Nat.sub_self, List.getElem?_cons_zero, if_true]
      · have outside : entries.length ≤ index - start := by omega
        have past : 1 ≤ index - start - entries.length := by omega
        rw [List.getElem?_eq_none (by simpa only [List.length_singleton] using past),
          List.getElem?_eq_none outside, if_neg same]

theorem OriginalScan.remainingPlan_zero (scan : OriginalScan raw workspace normal validation) :
    scan.remainingPlan 0 = scan.fundingPlan := by
  simp only [OriginalScan.remainingPlan, List.drop_zero, OriginalScan.fundingPlan]

theorem OriginalScan.emittedCount_present (scan : OriginalScan raw workspace normal validation)
    (inside : position < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue position) = true)
    (bounds : 0 ≤ (normal.rowValue position).coreId.toInt ∧
      (normal.rowValue position).coreId.toInt < scan.signatures.index.count.toInt)
    (present : scan.signatures.present position inside chosen bounds = true) :
    scan.emittedCount position = (scan.producers position inside chosen bounds present).body.count := by
  simp only [OriginalScan.emittedCount, dif_pos inside, dif_pos chosen, dif_pos bounds, dif_pos present]

def InsertedBody.CopyBounds (entry : InsertedBody) (floor frontier : Nat) : Prop :=
  ∃ memory, floor ≤ memory ∧ memory + entry.body.count * 60 ≤ frontier ∧
    entry.events = memory + entry.body.count * 40 - 8 ∧
    entry.types = memory + entry.body.count * 56 - 8 ∧
    entry.ends = memory + entry.body.count * 56

/-- One algorithmic scan invariant. Lexical values live in LocalEnv; these
    are fixed data/representation facts and a single linear frontier bound. -/
structure LoopFacts (scan : OriginalScan raw workspace normal validation)
    (cursor : Nat) (inserted : List InsertedBody) (heap : Heap) : Prop
    extends ScanStorage scan inserted heap where
  cursorBound : cursor ≤ normal.count
  ordered : OrderedPrefix (fun position => selectedRowBool raw.owner (normal.rowValue position)) cursor inserted
  source : ∀ entry ∈ inserted, scan.Source entry ∧ entry.Meaning
  copied : ∀ entry ∈ inserted, entry.CopyBounds origin.heap.nextAddress heap.nextAddress
  frontier : origin.heap.nextAddress ≤ heap.nextAddress ∧
    heap.nextAddress ≤ max origin.heap.nextAddress 1 +
      cursor * (localBytes raw.tokenCount.toInt.toNat + 200)
  funding : FullFunding scan → FundedBudget heap.remaining (scan.remainingPlan inserted.length)

variable {current after : State} {scan : OriginalScan raw workspace normal validation}
  {cursor : Nat} {inserted : List InsertedBody} {heap : Heap}

theorem LoopFacts.safe (facts : LoopFacts scan cursor inserted heap) : SafeHeap scan heap :=
  ⟨inserted, facts.toScanStorage⟩

theorem LoopFacts.complete (facts : LoopFacts scan normal.count inserted heap) :
    ScanOutput scan inserted.length heap := by
  have ordered : inserted.map InsertedBody.sourceRow = scan.selectedRows := facts.ordered
  have length := congrArg List.length ordered
  simp only [List.length_map] at length
  exact ⟨inserted, facts.toScanStorage, Or.inr ⟨by omega, ordered, facts.source⟩, fun _ => by omega⟩

def LoopFacts.skip (facts : LoopFacts scan cursor inserted heap)
    (inside : cursor < normal.count)
    (skipped : selectedRowBool raw.owner (normal.rowValue cursor) = false) :
    LoopFacts scan (cursor + 1) inserted heap := {
  facts with
  cursorBound := by omega
  ordered := facts.ordered.skip skipped
  frontier := ⟨facts.frontier.1, Nat.le_trans facts.frontier.2
    (Nat.add_le_add_left (Nat.mul_le_mul_right _ (Nat.le_succ cursor)) _)⟩ }

theorem LoopFacts.start (scan : OriginalScan raw workspace normal validation)
    (locations : RowLocations normal) :
    LoopFacts scan 0 [] (origin.heap.borrowBlock normal.geometry.block.base) := by
  have reads : HeapReads origin.heap (origin.heap.borrowBlock normal.geometry.block.base) := by
    intro pointer offset byte loaded
    rw [Heap.loadByte_borrowBlock]
    exact loaded
  have original := CatalogHeap.ofInvariant scan.invariant
  refine {
    cursorBound := Nat.zero_le _, ordered := rfl, source := by simp
    «protected» := HeapFrame.borrowBlock (fun _ _ impossible _ => False.elim impossible)
    table := tableRep_borrow normal locations
    catalogState := ?_
    stored := fun index => False.elim (Nat.not_lt_zero _ index.isLt)
    copied := by simp
    frontier := by simp only [Heap.borrowBlock, Nat.zero_mul, Nat.add_zero]; exact ⟨Nat.le_refl _, Nat.le_max_left _ _⟩
    funding := by intro funded; rw [show ([] : List InsertedBody).length = 0 from rfl,
      scan.remainingPlan_zero]; exact funded.budget }
  simp only [List.length_nil, Nat.add_zero, prefixRows_nil]
  exact {
    original with
    count := reads.nativeValue original.count
    backing := reads.readable original.backing
    occupied := fun index inside => (original.occupied index inside).afterHeapReads reads
    unique := original.unique.borrowBlock
    below := original.below.borrowBlock }

theorem LoopFacts.producerFits (facts : LoopFacts scan cursor inserted current.heap)
    (inside : cursor < normal.count)
    (producer : OriginalProducer raw workspace row current scan.region scan.mutable scan.catalog) :
    current.heap.allocationAddress 8 + localBytes producer.input.tokenCount < 2 ^ 64 ∧
      ∀ budget, consumeBudget current.heap.remaining (localBytes producer.input.tokenCount) = some budget →
        (producer.localHeap budget).allocationAddress 8 + producer.body.count * 56 < 2 ^ 64 := by
  have tokenEq : producer.input.tokenCount = raw.tokenCount.toInt.toNat := by
    have same := producer.tokenCount; omega
  have localPositive : 1 ≤ localBytes producer.input.tokenCount := by unfold localBytes; omega
  have count : producer.body.count ≤ 3 := by cases producer.body <;> simp [ReturnBody.count]
  have capacity := scan.addressRoom
  simp only [Nat.add_mul, Nat.one_mul] at capacity
  have originPositive := Nat.le_max_right origin.heap.nextAddress 1
  have cursorCost := Nat.mul_le_mul_right (localBytes raw.tokenCount.toInt.toNat + 200) (Nat.le_of_lt inside)
  have alignment (address : Nat) : address ≤ alignUp address 8 ∧ alignUp address 8 < address + 8 := by
    have remainder := Nat.mod_lt (address + 8 - 1) (by decide : 0 < 8)
    have division := Nat.mod_add_div (address + 8 - 1) 8
    unfold alignUp
    rw [Nat.mul_comm 8] at division
    omega
  have first := alignment (max current.heap.nextAddress 1)
  have currentBound := facts.frontier.2
  dsimp only [Address] at *
  have maxFrontier : max current.heap.nextAddress 1 ≤ max origin.heap.nextAddress 1 +
      cursor * (localBytes raw.tokenCount.toInt.toNat + 200) := by
    exact Nat.max_le.mpr ⟨currentBound, Nat.le_trans originPositive (Nat.le_add_right _ _)⟩
  have address : current.heap.allocationAddress 8 < max current.heap.nextAddress 1 + 8 := first.2
  constructor
  · change alignUp (max current.heap.nextAddress 1) 8 + localBytes producer.input.tokenCount < 2 ^ 64
    rw [tokenEq]
    omega
  · intro budget available
    have second := alignment (max (current.heap.allocationAddress 8 + localBytes producer.input.tokenCount) 1)
    simp only [OriginalProducer.localHeap, Heap.allocatedBytes, Heap.borrowBlock,
      Heap.allocationAddress, Nat.max_eq_left localPositive]
    change alignUp (max (current.heap.allocationAddress 8 + localBytes producer.input.tokenCount) 1) 8 +
      producer.body.count * 56 < 2 ^ 64
    rw [tokenEq] at second ⊢
    simp only [Heap.allocationAddress] at second ⊢
    omega

theorem OriginalScan.actualSignature (scan : OriginalScan raw workspace normal validation)
    (position : Nat) (inside : position < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue position) = true)
    (frame : HeapFrame scan.protected origin.heap current.heap) (formed : current.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram current
      (.call Extracted.«lowering::body_lookup».Functions.«has_function_signature».core.id
        [.value raw.signatureValue, .value (.signed .i32 (normal.rowValue position).coreId.toInt)])
      (.boolean (scan.signatureBool position inside chosen)) after ∧ PureFrame current after := by
  by_cases bounds : 0 ≤ (normal.rowValue position).coreId.toInt ∧
      (normal.rowValue position).coreId.toInt < scan.signatures.index.count.toInt
  · let old := scan.signatures.slots position inside chosen bounds
    let native : NativeSignatureSlot scan.signatures.index current.heap (normal.rowValue position).coreId.toInt.toNat :=
      { old with
        snapshot := by
          exact frame.snapshot old.snapshot (fun address lower upper =>
            scan.regionProtected (scan.signatureCovered position inside chosen bounds address lower upper)) }
    have actual := actualHasFunctionSignatureAt scan.signatures.index (normal.rowValue position).coreId bounds native formed
    change ∃ after, RunsExpr extractedProgram current
      (.call Extracted.«lowering::body_lookup».Functions.«has_function_signature».core.id
        [.value scan.signatures.index.value, .value (.signed .i32 (normal.rowValue position).coreId.toInt)])
      (.boolean (decide (native.entry.id.toInt = (normal.rowValue position).coreId.toInt) &&
        shapeSame native.entry.shape .InternalFunctionShape)) after ∧ PureFrame current after at actual
    simpa only [OriginalScan.signatureBool, dif_pos bounds, OriginalSignatures.present,
      native, old, scan.signatures.descriptor] using actual
  · have outside : (normal.rowValue position).coreId.toInt ≤ -1 ∨
        scan.signatures.index.count.toInt ≤ (normal.rowValue position).coreId.toInt := by omega
    have actual := actualHasFunctionSignatureOutside scan.signatures.index (normal.rowValue position).coreId outside formed
    change ∃ after, RunsExpr extractedProgram current
      (.call Extracted.«lowering::body_lookup».Functions.«has_function_signature».core.id
        [.value scan.signatures.index.value, .value (.signed .i32 (normal.rowValue position).coreId.toInt)])
      (.boolean false) after ∧ PureFrame current after at actual
    simpa only [OriginalScan.signatureBool, dif_neg bounds, scan.signatures.descriptor] using actual

/-- The internal producer boundary hides a failed attempt immediately.
    A successful attempt extends the same ordered source prefix once. -/
def ProducerStep (scan : OriginalScan raw workspace normal validation)
    (cursor : Nat) (inserted : List InsertedBody) (result : Int) (after : State) : Prop :=
  (result = -1 ∧ SafeHeap scan after.heap ∧ ¬FullFunding scan) ∨
  (result = 0 ∧ ∃ entry : InsertedBody, entry.sourceRow = cursor ∧
    LoopFacts scan (cursor + 1) (inserted ++ [entry]) after.heap)

/-- Original-source filter arithmetic for the next chosen row. -/
theorem OriginalScan.nextSelected (original : OriginalScan raw workspace normal validation)
    (ordered : OrderedPrefix (fun position => selectedRowBool raw.owner (normal.rowValue position)) cursor inserted)
    (inside : cursor < normal.count) (chosen : selectedRowBool raw.owner (normal.rowValue cursor) = true) :
    ∃ rest, original.selectedRows = inserted.map InsertedBody.sourceRow ++ cursor :: rest := by
  let selected := fun position => selectedRowBool raw.owner (normal.rowValue position)
  have split : List.range normal.count =
      List.range cursor ++ List.range' cursor (normal.count - cursor) := by
    have total : cursor + (normal.count - cursor) = normal.count := by omega
    simpa only [List.range_eq_range', Nat.zero_add, total] using
      (List.range'_append_1 (s := 0) (m := cursor) (n := normal.count - cursor)).symm
  have remaining : normal.count - cursor = (normal.count - cursor - 1) + 1 := by omega
  have first : List.range' cursor (normal.count - cursor) =
      cursor :: List.range' (cursor + 1) (normal.count - cursor - 1) := by
    rw [remaining, List.range']
    simp only [Nat.add_sub_cancel]
  refine ⟨(List.range' (cursor + 1) (normal.count - cursor - 1)).filter selected, ?_⟩
  change inserted.map InsertedBody.sourceRow = (List.range cursor).filter selected at ordered
  change (List.range normal.count).filter selected = _
  rw [split, first, List.filter_append, List.filter_cons]
  simp only [selected, chosen, ↓reduceIte] at ordered ⊢
  rw [← ordered]

/-- One selected row removes exactly its three planned allocations. The
    sizes stay tied to the original source-selected body witness. -/
theorem OriginalScan.remainingPlan_next (original : OriginalScan raw workspace normal validation)
    (ordered : OrderedPrefix (fun position => selectedRowBool raw.owner (normal.rowValue position)) cursor inserted)
    (inside : cursor < normal.count) (chosen : selectedRowBool raw.owner (normal.rowValue cursor) = true) :
    original.remainingPlan inserted.length = localBytes raw.tokenCount.toInt.toNat ::
      original.emittedCount cursor * 56 :: original.emittedCount cursor * 4 ::
        original.remainingPlan (inserted.length + 1) := by
  obtain ⟨rest, selected⟩ := original.nextSelected ordered inside chosen
  have head : original.selectedRows.drop inserted.length = cursor :: rest := by
    rw [selected, ← List.length_map (f := InsertedBody.sourceRow), List.drop_append_length]
  have tail : original.selectedRows.drop (inserted.length + 1) = rest := by
    rw [← List.drop_drop]
    simp only [head, List.drop_succ_cons, List.drop_zero]
  simp only [OriginalScan.remainingPlan, head, tail, List.flatMap_cons,
    List.cons_append, List.nil_append]

/-- Independent original room/nonduplication and the retained ordered
    source prefix fund this SAME next producer. This is pure plan arithmetic,
    not a successful producer run or a supplied append result. -/
theorem OriginalScan.selectedFunding (original : OriginalScan raw workspace normal validation)
    (ordered : OrderedPrefix (fun position => selectedRowBool raw.owner (normal.rowValue position)) cursor inserted)
    (source : ∀ entry ∈ inserted, original.Source entry)
    (inside : cursor < normal.count) (chosen : selectedRowBool raw.owner (normal.rowValue cursor) = true)
    (bounds : 0 ≤ (normal.rowValue cursor).coreId.toInt ∧
      (normal.rowValue cursor).coreId.toInt < original.signatures.index.count.toInt)
    (present : original.signatures.present cursor inside chosen bounds = true)
    (funded : FullFunding original)
    (budget : FundedBudget currentBudget (original.remainingPlan inserted.length)) :
    original.initialCount.toInt.toNat + inserted.length < original.catalog.length ∧
      (∀ index, index < original.initialCount.toInt.toNat + inserted.length →
        (prefixRows original.previous original.initialCount.toInt.toNat inserted index).id ≠
          (normal.rowValue cursor).coreId) ∧
      ∃ localBudget first second,
        consumeBudget currentBudget (localBytes raw.tokenCount.toInt.toNat) = some localBudget ∧
        consumeBudget localBudget ((original.producers cursor inside chosen bounds present).body.count * 56) = some first ∧
        consumeBudget first ((original.producers cursor inside chosen bounds present).body.count * 4) = some second ∧
        FundedBudget second (original.remainingPlan (inserted.length + 1)) := by
  obtain ⟨rest, selected⟩ := original.nextSelected ordered inside chosen
  have length := congrArg List.length selected
  simp only [List.length_append, List.length_map, List.length_cons] at length
  have room := funded.room
  have currentSelected : cursor ∈ original.selectedRows := by
    rw [selected]
    exact List.mem_append_right _ List.mem_cons_self
  have distinct := funded.distinct
  rw [selected, List.map_append, List.map_cons] at distinct
  have apart := (List.nodup_append.mp distinct).2.2
  refine ⟨by omega, ?_, ?_⟩
  · intro index occupied
    by_cases old : index < original.initialCount.toInt.toNat
    · rw [prefixRows_original old]
      exact funded.absent cursor currentSelected index old
    · have inInserted : index - original.initialCount.toInt.toNat < inserted.length := by omega
      let entry := inserted[index - original.initialCount.toInt.toNat]
      have found : inserted[index - original.initialCount.toInt.toNat]? = some entry :=
        List.getElem?_eq_getElem inInserted
      have member : entry ∈ inserted := List.mem_of_getElem? found
      obtain ⟨rowInside, rowChosen, rowBounds, rowPresent, identity⟩ := source entry member
      have selectedMember : entry.sourceRow ∈ inserted.map InsertedBody.sourceRow :=
        List.mem_map.mpr ⟨entry, member, rfl⟩
      have idMember : (normal.rowValue entry.sourceRow).coreId ∈
          (inserted.map InsertedBody.sourceRow).map (fun position => (normal.rowValue position).coreId) :=
        List.mem_map.mpr ⟨entry.sourceRow, selectedMember, rfl⟩
      have different := apart _ idMember _ List.mem_cons_self
      simp only [prefixRows, if_neg old, found]
      change entry.id ≠ (normal.rowValue cursor).coreId
      rw [identity.1]
      exact different
  · rw [original.remainingPlan_next ordered inside chosen,
      original.emittedCount_present inside chosen bounds present] at budget
    obtain ⟨localBudget, localAvailable, budget⟩ := budget
    obtain ⟨first, copyAvailable, budget⟩ := budget
    obtain ⟨second, endsAvailable, tail⟩ := budget
    exact ⟨localBudget, first, second, localAvailable, copyAvailable, endsAvailable, tail⟩

#print axioms OriginalScan.nextSelected
#print axioms OriginalScan.remainingPlan_next
#print axioms OriginalScan.selectedFunding

end IRBodyOwnedProof
