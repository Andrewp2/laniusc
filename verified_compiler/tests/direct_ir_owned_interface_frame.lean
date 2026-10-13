import verified_compiler.tests.direct_ir_owned_interface_domain
import Lanius.Semantics.Representation

namespace IRBodyOwnedProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs
open IRBodyProductionInputs IRBodyProductionProof IRBodyProductionScalar IREventStoreProof
open IRCatalogAppendProof IRCatalogConstructionProof

variable {before after : State} {input : Inputs} {footprint : Footprint}

/-- The only native bridge for the legacy spelling's raw i32 reads. All
    source representations below reuse the same proved frame relation. -/
private theorem framedWord (frame : HeapFrame footprint before.heap after.heap)
    (inside : index < length)
    (covered : ∀ address, pointer + index * 4 ≤ address → address < pointer + index * 4 + 4 → footprint.bytes address)
    (read : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) pointer length index = .ok value) :
    readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) pointer length index = .ok value := by
  simp only [readRawSliceIndex, Nat.not_le_of_lt inside, ↓reduceIte] at read ⊢
  change readNativeValue 64 extractedProgram before.heap (.scalar (.signed .i32)) (pointer + index * 4) = .ok value at read
  change readNativeValue 64 extractedProgram after.heap (.scalar (.signed .i32)) (pointer + index * 4) = .ok value
  exact (frame.snapshot (NativeSnapshot.scalarOfRead (Or.inr rfl) read) covered).read

private def framedNode (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (node : NativeNode input.tree before.heap index) : NativeNode input.tree after.heap index :=
  { node with snapshot := frame.snapshot node.snapshot (fun _ lower upper => covered _
      (Or.inl (Or.inl ⟨index, node.base, node.inside, node.location, lower, upper⟩))) }

private def framedChild (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (child : NativeChild input.tree before.heap index) : NativeChild input.tree after.heap index :=
  { child with snapshot := frame.snapshot child.snapshot (fun _ lower upper => covered _
      (Or.inl (Or.inr (Or.inl ⟨index, child.base, child.inside, child.location, lower, upper⟩)))) }

private def framedToken (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (token : OriginalToken input before index text expected) : OriginalToken input after index text expected := {
  token with
  toNativeToken := { token.toNativeToken with
    snapshot := frame.snapshot token.snapshot
      (fun _ lower upper => covered _ (Or.inl (Or.inr (Or.inr (Or.inl
        ⟨token.address, token.length, index, token.base, token.descriptor, token.inside, token.location, lower, upper⟩))))) }
  words := fun offset bound => framedWord frame
    (by have := token.span; have := token.sourceBound; omega)
    (fun _ lower upper => covered _ (Or.inl (Or.inr (Or.inr (Or.inr
      ⟨token.sourceAddress, token.sourceCapacity, token.origin + offset, token.source,
        by have := token.span; omega, lower, upper⟩))))) (token.words offset bound) }

private def framedTopology (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (topology : TerminalTopology input before.heap declaration) : TerminalTopology input after.heap declaration := {
  topology with
  declarationNode := framedNode frame native covered topology.declarationNode
  bodyChild := framedChild frame native covered topology.bodyChild
  blockNode := framedNode frame native covered topology.blockNode
  listChild := framedChild frame native covered topology.listChild
  listNode := framedNode frame native covered topology.listNode
  firstChild := framedChild frame native covered topology.firstChild
  restChild := framedChild frame native covered topology.restChild
  restNode := framedNode frame native covered topology.restNode
  statementNode := framedNode frame native covered topology.statementNode
  optionalChild := framedChild frame native covered topology.optionalChild
  optionalNode := framedNode frame native covered topology.optionalNode
  returnChild := framedChild frame native covered topology.returnChild
  returnToken := { topology.returnToken with
    snapshot := frame.snapshot topology.returnToken.snapshot
      (fun _ lower upper => covered _ (Or.inl (Or.inr (Or.inr (Or.inl
        ⟨topology.returnToken.address, topology.returnToken.length, topology.tokenIndex,
          topology.returnToken.base, topology.returnToken.descriptor, topology.returnToken.inside,
          topology.returnToken.location, lower, upper⟩))))) } }

private theorem framedScalar (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (original : OriginalScalar input before root expression route) :
    OriginalScalar input after root expression route := by
  induction original with
  | boolean node production count child kind payload spelling =>
      exact .boolean (framedNode frame native covered node) production count (framedChild frame native covered child)
        kind payload (framedToken frame native covered spelling)
  | integer node production count child kind payload spelling =>
      exact .integer (framedNode frame native covered node) production count (framedChild frame native covered child)
        kind payload (framedToken frame native covered spelling)
  | negative node production count child kind payload minus minusKind minusPayload minusSpelling operand ih =>
      exact .negative (framedNode frame native covered node) production count (framedChild frame native covered child)
        kind payload (framedChild frame native covered minus) minusKind minusPayload
        (framedToken frame native covered minusSpelling) ih
  | wrapper node production slot selected inside child kind payload operand ih =>
      exact .wrapper (framedNode frame native covered node) production slot selected inside
        (framedChild frame native covered child) kind payload ih
  | binaryEnd node count left leftKind leftPayload tail tailKind tailPayload ending production operand ih =>
      exact .binaryEnd (framedNode frame native covered node) count (framedChild frame native covered left) leftKind leftPayload
        (framedChild frame native covered tail) tailKind tailPayload (framedNode frame native covered ending) production ih

private def framedNatural (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (body : NaturalBody input before declaration) : NaturalBody input after declaration := {
  topology := framedTopology frame native covered body.topology
  keyword := framedToken frame native covered body.keyword
  returns := match body.returns with
    | .void optional result => .void optional result
    | .scalar root optional bound child kind payload scalar result distinct =>
        .scalar root optional bound (framedChild frame native covered child) kind payload
          { scalar with «syntax» := framedScalar frame native covered scalar.syntax } result distinct }

private theorem framedNatural_selects (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (natural : NaturalBody input before declaration) (body : ReturnBody) :
    (framedNatural frame native covered natural).Selects body ↔ natural.Selects body := by
  cases natural with
  | mk topology keyword returns => cases returns <;> rfl

private def framedStorage (frame : HeapFrame footprint before.heap after.heap)
    (storage : ScalarStorage workspace before slots) : ScalarStorage workspace after slots := {
  storage with
  nodeRoom := fun index inside => frame.readable _ _ (storage.nodeRoom index inside)
  countRoom := frame.readable _ _ storage.countRoom
  codesRoom := frame.readable _ _ storage.codesRoom
  depthsRoom := frame.readable _ _ storage.depthsRoom }

private def framedWorkspace (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (natural : NaturalBody input before declaration)
    (storage : natural.returns.WorkspaceStorage workspace) :
    (framedNatural frame native covered natural).returns.WorkspaceStorage workspace := by
  cases natural with
  | mk topology keyword returns =>
      cases returns with
      | void optional result => exact storage
      | scalar root optional bound child kind payload scalar result distinct => exact framedStorage frame storage

private theorem framedWorkspace_writes (frame : HeapFrame footprint before.heap after.heap)
    (native : NativeSignature input.signature before.heap)
    (covered : ∀ address, sourceBytes input native address → footprint.bytes address)
    (natural : NaturalBody input before declaration)
    (storage : natural.returns.WorkspaceStorage workspace) :
    (framedNatural frame native covered natural).returns.workspaceWrites workspace
      (framedWorkspace frame native covered natural storage) = natural.returns.workspaceWrites workspace storage := by
  cases natural with
  | mk topology keyword returns => cases returns <;> rfl

/-- One locality adapter for the legacy accepted1179 input. Logical source,
    body choice, physical coordinates and workspace footprint stay fixed.
    The loop invokes this adapter once rather than reconstructing its fields. -/
def OriginalProducer.at
    {workspace : RawWorkspace}
    (original : OriginalProducer raw workspace row before region mutable catalog)
    (frame : HeapFrame footprint before.heap after.heap)
    (covered : ∀ address, region address → footprint.bytes address) :
    OriginalProducer raw workspace row after region mutable catalog := {
  original with
  natural := framedNatural frame original.native (fun a h => covered a (original.sourceCovered a h)) original.natural
  native := { original.native with
    snapshot := frame.snapshot original.native.snapshot (fun a l u =>
      covered a (original.sourceCovered a (Or.inr ⟨l, u⟩))) }
  selected := (framedNatural_selects frame original.native
    (fun a h => covered a (original.sourceCovered a h)) original.natural original.body).mpr original.selected
  storage := framedWorkspace frame original.native
    (fun a h => covered a (original.sourceCovered a h)) original.natural original.storage
  output := { original.output with
    eventRoom := frame.readable _ _ original.output.eventRoom
    typeRoom := fun enabled => frame.readable _ _ (original.output.typeRoom enabled) }
  permissions := { original.permissions with
    eventRoom := fun index inside => frame.readable _ _ (original.permissions.eventRoom index inside)
    typeRoom := fun enabled index inside => frame.readable _ _ (original.permissions.typeRoom enabled index inside) }
  mutableCovered := by
    intro address changed
    rw [framedWorkspace_writes] at changed
    exact original.mutableCovered address changed
  outputApart := by
    intro address changed
    rw [framedWorkspace_writes]
    exact original.outputApart address changed }

/-- A fixed logical allocation table: contents, selected live allocation
    shape, and the header's borrowed capability are separate atoms. -/
def tableRep (normal : NormalTable table heap) : Rep :=
  (Rep.native 64 extractedProgram headerType table.memory normal.header.header.value 72).and
    ((Rep.all fun index : Fin normal.count => Rep.native 64 extractedProgram rowType
      (table.rowBase index.val) (normal.rows index.val index.isLt).row.value 80).and
      ((Rep.block table.memory (blockShape normal.geometry.block)).and
        ((Rep.owned table.memory false).and
          (Rep.all fun index : Fin normal.count =>
            Rep.block (table.rowBase index.val) (blockShape normal.geometry.block)))))

theorem tableRep_borrow (normal : NormalTable table heap) (locations : RowLocations normal) :
    (tableRep normal).holds (heap.borrowBlock normal.geometry.block.base) := by
  have reads : HeapReads heap (heap.borrowBlock normal.geometry.block.base) :=
    fun _ _ _ loaded => by rw [Heap.loadByte_borrowBlock]; exact loaded
  refine ⟨normal.header.snapshot.afterHeapReads reads,
    (fun index => (normal.rows index.val index.isLt).snapshot.afterHeapReads reads),
    ?_, Rep.borrowed normal.geometry.found, ?_⟩
  · exact ⟨{ normal.geometry.block with owned := false },
      Heap.containingBlock?_borrowSelected normal.geometry.found, rfl⟩
  · intro index
    exact ⟨{ normal.geometry.block with owned := false },
      Heap.containingBlock?_borrowSelected (locations index.val index.isLt), rfl⟩

/-- Native query compatibility is reified once from the compositional
    representation. Global uniqueness is supplied by the current actual
    catalog invariant, not asserted by arbitrary-predicate framing. -/
noncomputable def tableRep_native (normal : NormalTable table original)
    (represented : (tableRep normal).holds current) (unique : HeapBlockBasesUnique current) :
    BorrowedTable table current := by
  classical
  let block := represented.2.2.1.choose
  have found : current.containingBlock? table.memory = some block := represented.2.2.1.choose_spec.1
  have shape : blockShape block = blockShape normal.geometry.block := represented.2.2.1.choose_spec.2
  have owned : block.owned = false := by
    obtain ⟨ownedBlock, ownedFound, owned⟩ := represented.2.2.2.1
    have sameBlock : ownedBlock = block := Option.some.inj (ownedFound.symm.trans found)
    simpa only [sameBlock] using owned
  have base : block.base = normal.geometry.block.base := by simpa only [blockShape] using congrArg Block.base shape
  have size : block.size = normal.geometry.block.size := by simpa only [blockShape] using congrArg Block.size shape
  have alignment : block.alignment = normal.geometry.block.alignment := by
    simpa only [blockShape] using congrArg Block.alignment shape
  exact {
    normal with
    geometry := { normal.geometry with
      block := block, found := found, unique := unique
      alignment := by rw [alignment]; exact normal.geometry.alignment
      bounds := by rw [base, size]; exact normal.geometry.bounds }
    rowsBounds := by
      change table.memory + 72 + normal.count * 80 ≤ block.base + block.size
      rw [base, size]; exact normal.rowsBounds
    header := { normal.header with snapshot := represented.1 }
    rows := fun index inside => { normal.rows index inside with snapshot := represented.2.1 ⟨index, inside⟩ }
    borrowed := Heap.borrowBlock_eq_of_unowned found unique owned }

theorem tableRep_locations (normal : NormalTable table original)
    (represented : (tableRep normal).holds current) (unique : HeapBlockBasesUnique current) :
    RowLocations (tableRep_native normal represented unique).toNormalTable := by
  let block := represented.2.2.1.choose
  have found : current.containingBlock? table.memory = some block := represented.2.2.1.choose_spec.1
  have shape : blockShape block = blockShape normal.geometry.block := represented.2.2.1.choose_spec.2
  intro index inside
  obtain ⟨rowBlock, rowFound, rowShape⟩ := represented.2.2.2.2 ⟨index, inside⟩
  have sameBase : rowBlock.base = block.base :=
    (congrArg Block.base rowShape).trans (congrArg Block.base shape).symm
  have same := unique rowBlock (List.mem_of_find?_eq_some rowFound) block
    (List.mem_of_find?_eq_some found) sameBase
  subst rowBlock
  exact rowFound

/-- Payload observations are independent of the catalog row that names them.
The canonical catalog invariant already preserves that row snapshot. -/
structure TerminalPayloads (heap : Heap) (events types ends count : Nat)
    (annotations : Bool) (statement : Stmt) : Prop where
  payloads : TerminalRepresentation
    (readRawSliceIndex extractedProgram { heap := heap } IREventStoreProof.eventType events count)
    (readRawSliceIndex extractedProgram { heap := heap } (.scalar (.signed .i32)) ends count)
    count statement
  resultTypes : ∀ index, index < count → readRawSliceIndex extractedProgram { heap := heap }
    IREventStoreProof.referenceType types count index = .ok
      (IRTypeRefProof.referenceValue
        (if annotations then if index = 0 then .Invalid else terminalResult statement else .Invalid))

def InsertedBody.Payloads (entry : InsertedBody) (heap : Heap) : Prop :=
  TerminalPayloads heap entry.events entry.types entry.ends entry.body.count
    entry.annotations entry.body.coreStatement

def PayloadBytes (events types ends count address : Nat) : Prop :=
  (∃ index base, index < count ∧
    rawSliceElementAddress? extractedProgram IREventStoreProof.eventType events index = .ok base ∧
    base ≤ address ∧ address < base + 40) ∨
  (∃ index base, index < count ∧
    rawSliceElementAddress? extractedProgram IREventStoreProof.referenceType types index = .ok base ∧
    base ≤ address ∧ address < base + 16) ∨
  (∃ index, index < count ∧ ends + index * 4 ≤ address ∧ address < ends + index * 4 + 4)

private theorem framedSlot (frame : HeapFrame footprint original current)
    (inside : index < count)
    (covered : ∀ base, rawSliceElementAddress? extractedProgram type pointer index = .ok base →
      ∀ address, base ≤ address → address < base + size → footprint.bytes address)
    (confined : ∀ base, readNativeValue 64 extractedProgram original type base = .ok value →
      NativeSnapshot 64 extractedProgram original type base value size)
    (read : readRawSliceIndex extractedProgram { heap := original } type pointer count index = .ok value) :
    readRawSliceIndex extractedProgram { heap := current } type pointer count index = .ok value := by
  simp only [readRawSliceIndex, Nat.not_le_of_lt inside, ↓reduceIte] at read ⊢
  cases location : rawSliceElementAddress? extractedProgram type pointer index with
  | error reason => simp only [location, Bind.bind, Except.bind] at read; cases read
  | ok base =>
      simp only [location, Bind.bind, Except.bind] at read ⊢
      exact (frame.snapshot (confined base read) (covered base location)).read

private theorem referenceSnapshot (reference : IRTypeRefProof.Reference)
    (terminal : reference = .Invalid ∨ reference = .Void ∨ reference = .Bool ∨ reference = .I32)
    (read : readNativeValue 64 extractedProgram heap IREventStoreProof.referenceType address =
      .ok (IRTypeRefProof.referenceValue reference)) :
    NativeSnapshot 64 extractedProgram heap IREventStoreProof.referenceType address
      (IRTypeRefProof.referenceValue reference) 16 := by
  rcases terminal with rfl | rfl | rfl | rfl
  all_goals exact (NativeSnapshot.enumEmptyOfRead (by core_lookup) rfl read).enlarge (by decide)

/-- The legacy stored result has four terminal constructors. Shared native
    confinement handles decoding; this adapter only matches their logical
    events and endpoints and preserves the same stored statement. -/
private theorem payloadsFrame
    (stored : TerminalPayloads original events types ends count annotations statement)
    (frame : HeapFrame footprint original current)
    (covered : ∀ address, PayloadBytes events types ends count address → footprint.bytes address) :
    TerminalPayloads current events types ends count annotations statement := by
  have event (index : Nat) (inside : index < count) (value : Value)
      (confined : ∀ base, readNativeValue 64 extractedProgram original IREventStoreProof.eventType base = .ok value →
        NativeSnapshot 64 extractedProgram original IREventStoreProof.eventType base value 40)
      (read : readRawSliceIndex extractedProgram { heap := original }
        IREventStoreProof.eventType events count index = .ok value) :=
    framedSlot frame inside (fun base location address lower upper =>
      covered address (Or.inl ⟨index, base, inside, location, lower, upper⟩)) confined read
  have endpoint (index : Nat) (inside : index < count) (value : Value)
      (read : readRawSliceIndex extractedProgram { heap := original }
        (.scalar (.signed .i32)) ends count index = .ok value) :=
    framedWord (after := { heap := current }) frame inside (fun address lower upper => covered address
      (Or.inr (Or.inr ⟨index, inside, lower, upper⟩))) read
  have terminal : terminalResult statement = .Invalid ∨ terminalResult statement = .Void ∨
      terminalResult statement = .Bool ∨ terminalResult statement = .I32 := by
    cases stored.payloads <;> simp [terminalResult]
  refine ⟨?_, ?_⟩
  · cases stored.payloads with
    | void header endRead =>
        exact .void (event 0 (by decide) _ (fun _ read =>
          (NativeSnapshot.enumEmptyOfRead (by core_lookup) rfl read).enlarge (by decide)) header)
          (endpoint 0 (by decide) _ endRead)
    | boolean value header literal endReads =>
        exact .boolean value (event 0 (by decide) _ (fun _ read =>
          (NativeSnapshot.enumEmptyOfRead (by core_lookup) rfl read).enlarge (by decide)) header)
          (event 1 (by decide) _ (fun _ read =>
            (NativeSnapshot.enumSingleOfRead (by core_lookup) rfl (Or.inl rfl) read).enlarge (by decide)) literal)
          (fun index inside => endpoint index inside _ (endReads index inside))
    | integer value header literal endReads =>
        exact .integer value (event 0 (by decide) _ (fun _ read =>
          (NativeSnapshot.enumEmptyOfRead (by core_lookup) rfl read).enlarge (by decide)) header)
          (event 1 (by decide) _ (fun _ read =>
            (NativeSnapshot.enumSingleOfRead (by core_lookup) rfl (Or.inr rfl) read).enlarge (by decide)) literal)
          (fun index inside => endpoint index inside _ (endReads index inside))
    | negative value header operator literal endReads =>
        exact .negative value (event 0 (by decide) _ (fun _ read =>
          (NativeSnapshot.enumEmptyOfRead (by core_lookup) rfl read).enlarge (by decide)) header)
          (event 1 (by decide) _ (fun _ read =>
            (NativeSnapshot.enumEmptyOfRead (by core_lookup) rfl read).enlarge (by decide)) operator)
          (event 2 (by decide) _ (fun _ read =>
            (NativeSnapshot.enumSingleOfRead (by core_lookup) rfl (Or.inr rfl) read).enlarge (by decide)) literal)
          (fun index inside => endpoint index inside _ (endReads index inside))
  · intro index inside
    apply framedSlot frame inside
      (fun base location address lower upper => covered address
        (Or.inr (Or.inl ⟨index, base, inside, location, lower, upper⟩)))
      (fun base read => referenceSnapshot _ (by
        by_cases enabled : annotations = true
        · by_cases root : index = 0
          · exact Or.inl (by simp [enabled, root])
          · simpa only [enabled, root, ↓reduceIte] using terminal
        · exact Or.inl (by simp [enabled])) read)
    exact stored.resultTypes index inside

def payloadRep (entry : InsertedBody) : Rep where
  footprint := ⟨PayloadBytes entry.events entry.types entry.ends entry.body.count,
    fun _ => False, fun _ => False⟩
  holds heap := entry.Payloads heap
  stable frame stored := payloadsFrame stored frame (fun _ h => h)

def prefixRep (inserted : List InsertedBody) : Rep :=
  Rep.all fun index : Fin inserted.length => payloadRep inserted[index.val]

theorem prefixRep_ofPayloads
    {inserted : List InsertedBody}
    (stored : ∀ (index : Nat) (entry : InsertedBody), inserted[index]? = some entry → entry.Payloads heap) :
    (prefixRep inserted).holds heap :=
  fun index => stored index.val inserted[index.val] (List.getElem?_eq_getElem index.isLt)

theorem prefixRep_payloads {index : Nat} {entry : InsertedBody}
    (stored : (prefixRep inserted).holds heap)
    (found : inserted[index]? = some entry) : entry.Payloads heap := by
  obtain ⟨inside, same⟩ := List.getElem?_eq_some_iff.mp found
  simpa only [same, payloadRep] using stored ⟨index, inside⟩

/-- The actual1179 catalog contract separates into these heap facts and the
caller's formation/view facts. Counts are natural here; the source bound
proves the signed roundtrip once when invoking the canonical producer. -/
structure CatalogHeap (catalog : Catalog) (next : Nat) (previous : Nat → PreviousRow)
    (heap : Heap) : Prop where
  supported : Supported catalog.capacity
  bound : next ≤ catalog.length
  count : readNativeValue 64 extractedProgram heap (.scalar (.signed .i32)) catalog.memory =
    .ok (.signed .i32 next)
  backing : heap.Readable catalog.memory catalog.bytes
  occupied : ∀ index, index < next → NativeSnapshot 64 extractedProgram heap
    bodyType (catalog.rowBase index) (previous index).value 96
  unique : HeapBlockBasesUnique heap
  below : HeapBlocksBelowNext heap

theorem CatalogHeap.toInt (facts : CatalogHeap catalog next previous heap) :
    (Int32.ofNat next).toInt = (next : Int) := by
  have supported := facts.supported
  have bound := facts.bound
  dsimp only [Catalog.length] at bound
  exact Int32.toInt_ofNat_of_lt (by omega)

theorem CatalogHeap.ofInvariant (invariant : Invariant catalog next previous state) :
    CatalogHeap catalog next.toInt.toNat previous state.heap := {
  supported := invariant.supported
  bound := by have bounds := invariant.bounds; dsimp only [Catalog.length]; omega
  count := by simpa only [Int.toNat_of_nonneg invariant.bounds.1] using invariant.count
  backing := invariant.backing
  occupied := invariant.occupied
  unique := invariant.unique
  below := invariant.below }

theorem CatalogHeap.invariant (facts : CatalogHeap catalog next previous state.heap)
    (formed : state.CellsWellFormed) (noViews : state.i32ArrayViews = []) :
    Invariant catalog (Int32.ofNat next) previous state := {
  supported := facts.supported
  bounds := by
    rw [facts.toInt]
    have supported := facts.supported
    have bound := facts.bound
    dsimp only [Catalog.length] at bound
    omega
  count := by rw [facts.toInt]; exact facts.count
  backing := facts.backing
  occupied := by simpa only [facts.toInt, Int.toNat_natCast] using facts.occupied
  formed := formed
  unique := facts.unique
  below := facts.below
  noViews := noViews }

theorem CatalogHeap.stored {index : Nat} {entry : InsertedBody}
    (facts : CatalogHeap catalog (start + inserted.length) (prefixRows previous start inserted) heap)
    (payloads : (prefixRep inserted).holds heap) (found : inserted[index]? = some entry) :
    entry.Stored catalog (start + index) heap := by
  have inside := (List.getElem?_eq_some_iff.mp found).1
  have row := facts.occupied (start + index) (by omega)
  simp only [prefixRows, if_neg (by omega : ¬start + index < start),
    Nat.add_sub_cancel_left, found] at row
  have payload := prefixRep_payloads payloads found
  have result : terminalResult entry.body.coreStatement = entry.body.result := by cases entry.body <;> rfl
  have bodySame : bodyType = IRCatalogStoreProof.bodyType := by rfl
  have zero : Int32.ofNat 0 = 0 := by decide
  refine ⟨?_, payload.payloads, payload.resultTypes⟩
  simpa only [InsertedBody.previous, PreviousRow.value, result, bodySame, zero] using row

end IRBodyOwnedProof
