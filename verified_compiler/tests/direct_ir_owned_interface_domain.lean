import verified_compiler.tests.direct_ir_owned_interface_producer
import verified_compiler.tests.direct_ir_value_catalog_valid

namespace IRBodyOwnedProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs
open IRValueCatalogValid IRBodyProductionProof IRBodyProductionInputs
open IRCatalogConstructionProof IRCatalogAppendProof

variable {origin : State}

def allocationIndexValue (raw : RawInputs) : Value :=
  source_value Extracted.«lowering::allocation».Types.«Index».mk
    [raw.allocationTable.value, raw.allocationTail 0, raw.allocationTail 1,
      raw.allocationTail 2, raw.allocationTail 3, raw.allocationTail 4]

/-- These are the approved original-input definitions, not a domain of
    successful executions. They are retained here to avoid importing the
    previous caller proof and its framing infrastructure. -/
structure OriginalValidation (raw : RawInputs) (origin : State) where
  values : Values
  index : Index
  valuesValue : values.value = raw.valuesValue
  valuesCount : values.count = raw.valueCount
  indexValue : index.value = allocationIndexValue raw
  table : index.table = raw.allocationTable
  native : OriginalSlice values index 0 values.count.toInt raw.tokenCount.toInt origin.heap

structure OriginalSignatures (raw : RawInputs) (normal : NormalTable raw.allocationTable origin.heap) where
  index : SignatureIndex
  descriptor : index.value = raw.signatureValue
  count : index.count = raw.signatureCount
  capacity : index.count.toInt.toNat ≤ index.length
  slots : ∀ position (inside : position < normal.count),
    selectedRowBool raw.owner (normal.rowValue position) = true →
    ∀ bounds : 0 ≤ (normal.rowValue position).coreId.toInt ∧
      (normal.rowValue position).coreId.toInt < index.count.toInt,
    NativeSignatureSlot index origin.heap (normal.rowValue position).coreId.toInt.toNat

def OriginalSignatures.present
    (signatures : OriginalSignatures raw normal) (position : Nat) (inside : position < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue position) = true)
    (bounds : 0 ≤ (normal.rowValue position).coreId.toInt ∧
      (normal.rowValue position).coreId.toInt < signatures.index.count.toInt) : Bool :=
  let native := signatures.slots position inside chosen bounds
  decide (native.entry.id.toInt = (normal.rowValue position).coreId.toInt) &&
    shapeSame native.entry.shape .InternalFunctionShape

/-- Existing bodies are arbitrary represented native trees, including
    string payloads, rather than members of the newly lowered natural family. -/
structure OccupiedStorage (row : PreviousRow) (heap : Heap) where
  events : Nat
  types : Nat
  ends : Nat
  eventLength : Nat
  typeLength : Nat
  endLength : Nat
  enabled : Bool
  count : Int32
  descriptor : row.tree = IRValidatorProof.treeValue
    (.rawSlice IREventStoreProof.eventType events eventLength)
    (.rawSlice IREventStoreProof.referenceType types typeLength) enabled
    (.rawSlice (.scalar (.signed .i32)) ends endLength) count.toInt
  eventBound : count.toInt.toNat ≤ eventLength
  typeBound : enabled = true → count.toInt.toNat ≤ typeLength
  endBound : count.toInt.toNat ≤ endLength
  eventBases : Nat → Nat
  typeBases : Nat → Nat
  eventLocation : ∀ index, index < count.toInt.toNat → rawSliceElementAddress? extractedProgram
    IREventStoreProof.eventType events index = .ok (eventBases index)
  typeLocation : enabled = true → ∀ index, index < count.toInt.toNat → rawSliceElementAddress? extractedProgram
    IREventStoreProof.referenceType types index = .ok (typeBases index)
  eventValues : Nat → Value
  typeValues : Nat → Value
  endValues : Nat → Int
  eventSnapshot : ∀ index, index < count.toInt.toNat → NativeSnapshot 64 extractedProgram heap
    IREventStoreProof.eventType (eventBases index) (eventValues index) 40
  typeSnapshot : enabled = true → ∀ index, index < count.toInt.toNat → NativeSnapshot 64 extractedProgram heap
    IREventStoreProof.referenceType (typeBases index) (typeValues index) 16
  endSnapshot : ∀ index, index < count.toInt.toNat → NativeSnapshot 64 extractedProgram heap
    (.scalar (.signed .i32)) (ends + index * 4) (.signed .i32 (endValues index)) 4
  stringSnapshot : ∀ index, index < count.toInt.toNat → ∀ pointer capacity (length : Int32),
    eventValues index = source_value Extracted.«ir::body_events».Types.«Event».«ExpressionString»
      [source_value Extracted.«ir::body_events».Types.«StringValue».mk
        [.rawSlice (.scalar (.signed .i32)) pointer capacity, .signed .i32 length.toInt]] →
    ∀ word, word < length.toInt.toNat → word < capacity →
      ∃ value : Int, NativeSnapshot 64 extractedProgram heap (.scalar (.signed .i32))
        (pointer + word * 4) (.signed .i32 value) 4

def OccupiedStorage.bytes (stored : OccupiedStorage row heap) (address : Nat) : Prop :=
  (∃ index, index < stored.count.toInt.toNat ∧
    ((stored.eventBases index ≤ address ∧ address < stored.eventBases index + 40) ∨
      (stored.enabled = true ∧ stored.typeBases index ≤ address ∧ address < stored.typeBases index + 16) ∨
      (stored.ends + index * 4 ≤ address ∧ address < stored.ends + index * 4 + 4))) ∨
  (∃ index, index < stored.count.toInt.toNat ∧ ∃ pointer capacity : Nat, ∃ length : Int32,
    stored.eventValues index = source_value Extracted.«ir::body_events».Types.«Event».«ExpressionString»
      [source_value Extracted.«ir::body_events».Types.«StringValue».mk
        [.rawSlice (.scalar (.signed .i32)) pointer capacity, .signed .i32 length.toInt]] ∧
    ∃ word, word < length.toInt.toNat ∧ word < capacity ∧
      pointer + word * 4 ≤ address ∧ address < pointer + word * 4 + 4)

structure OriginalScan (raw : RawInputs) (rawWorkspace : RawWorkspace)
    (normal : NormalTable raw.allocationTable origin.heap) (validation : OriginalValidation raw origin) where
  catalog : Catalog
  initialCount : Int32
  previous : Nat → PreviousRow
  invariant : Invariant catalog initialCount previous origin
  region : Nat → Prop
  occupied : ∀ index, index < initialCount.toInt.toNat → OccupiedStorage (previous index) origin.heap
  occupiedCovered : ∀ index inside address, (occupied index inside).bytes address → region address
  tableCovered : ∀ address, raw.allocationTable.memory ≤ address →
    address < raw.allocationTable.memory + 72 + normal.count * 80 → region address
  validationCovered : ∀ address, validation.native.bytes address → region address
  mutable : Nat → Prop
  protectedApart : ∀ address, region address → ¬mutable address
  catalogApart : ∀ address, region address →
    ¬(catalog.memory ≤ address ∧ address < catalog.memory + catalog.bytes)
  workspaceCatalogApart : ∀ address, catalog.memory ≤ address → address < catalog.memory + catalog.bytes →
    ¬mutable address
  mutableBelow : ∀ address, mutable address → address < origin.heap.nextAddress
  signatures : OriginalSignatures raw normal
  signatureCovered : ∀ position inside chosen bounds address,
    (signatures.slots position inside chosen bounds).base ≤ address →
    address < (signatures.slots position inside chosen bounds).base + 72 → region address
  producers : ∀ position (inside : position < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue position) = true)
    (bounds : 0 ≤ (normal.rowValue position).coreId.toInt ∧
      (normal.rowValue position).coreId.toInt < signatures.index.count.toInt),
    signatures.present position inside chosen bounds = true →
    OriginalProducer raw rawWorkspace (normal.rowValue position) origin region mutable catalog
  addressRoom : max origin.heap.nextAddress 1 +
    (normal.count + 1) * (localBytes raw.tokenCount.toInt.toNat + 200) + 16 < 2 ^ 64

inductive OriginalDomain (raw : RawInputs) (rawWorkspace : RawWorkspace) (origin : State) : Type where
  | early (rejected : raw.beforeHeaderReject)
  | header (geometry : HeaderGeometry raw.allocationTable origin.heap)
      (native : NativeHeader raw.allocationTable origin.heap)
      (earlyGood : ¬raw.beforeHeaderReject)
      (nonnegative : 0 ≤ raw.allocationTable.count.toInt)
      (rejected : native.header.rows.toInt ≠ raw.allocationTable.count.toInt ∨
        raw.afterHeaderReject rawWorkspace ∨ native.header.rows.toInt ≤ 0)
  | normal (table : NormalTable raw.allocationTable origin.heap)
      (locations : RowLocations table)
      (earlyGood : ¬raw.beforeHeaderReject) (descriptorGood : ¬raw.afterHeaderReject rawWorkspace)
      (exactRows : table.header.header.rows.toInt = raw.allocationTable.count.toInt)
      (positive : 0 < table.count)
      (validation : OriginalValidation raw origin)
      (scan : SemanticValidSlice validation.values validation.index table.rowValue
        0 validation.values.count.toInt raw.tokenCount.toInt → OriginalScan raw rawWorkspace table validation)

def FundedBudget : Option Nat → List Nat → Prop
  | _, [] => True
  | budget, bytes :: rest => ∃ remaining,
      consumeBudget budget bytes = some remaining ∧ FundedBudget remaining rest

def OriginalScan.selectedRows
    (scan : OriginalScan raw rawWorkspace normal validation) : List Nat :=
  (List.range normal.count).filter (fun position => selectedRowBool raw.owner (normal.rowValue position))

noncomputable def OriginalScan.emittedCount
    (scan : OriginalScan raw rawWorkspace normal validation) (position : Nat) : Nat := by
  classical
  exact if inside : position < normal.count then
    if chosen : selectedRowBool raw.owner (normal.rowValue position) = true then
      if bounds : 0 ≤ (normal.rowValue position).coreId.toInt ∧
          (normal.rowValue position).coreId.toInt < scan.signatures.index.count.toInt then
        if present : scan.signatures.present position inside chosen bounds = true then
          (scan.producers position inside chosen bounds present).body.count
        else 0
      else 0
    else 0
  else 0

noncomputable def OriginalScan.fundingPlan
    (scan : OriginalScan raw rawWorkspace normal validation) : List Nat :=
  scan.selectedRows.flatMap fun position =>
    [localBytes raw.tokenCount.toInt.toNat, scan.emittedCount position * 56,
      scan.emittedCount position * 4]

structure FullFunding (scan : OriginalScan (origin := origin) raw rawWorkspace normal validation) : Prop where
  signatures : ∀ position (inside : position < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue position) = true),
    ∃ bounds : 0 ≤ (normal.rowValue position).coreId.toInt ∧
        (normal.rowValue position).coreId.toInt < scan.signatures.index.count.toInt,
      scan.signatures.present position inside chosen bounds = true
  room : scan.initialCount.toInt.toNat + scan.selectedRows.length ≤ scan.catalog.length
  distinct : (scan.selectedRows.map fun position => (normal.rowValue position).coreId).Nodup
  absent : ∀ position ∈ scan.selectedRows, ∀ index, index < scan.initialCount.toInt.toNat →
    (scan.previous index).id ≠ (normal.rowValue position).coreId
  budget : FundedBudget origin.heap.remaining scan.fundingPlan

/-- Coordinates are witnesses to native storage, not public numeric results. -/
structure InsertedBody where
  sourceRow : Nat
  id : Int32
  body : ReturnBody
  surface : List Surface.Stmt
  events : Nat
  types : Nat
  ends : Nat
  annotations : Bool

def InsertedBody.previous (entry : InsertedBody) : PreviousRow :=
  { id := entry.id, parameters := Int32.ofNat 0, result := entry.body.result
    tree := IRValidatorProof.treeValue
      (.rawSlice IREventStoreProof.eventType entry.events entry.body.count)
      (.rawSlice IREventStoreProof.referenceType entry.types entry.body.count) true
      (.rawSlice (.scalar (.signed .i32)) entry.ends entry.body.count) entry.body.count }

def InsertedBody.Meaning (entry : InsertedBody) : Prop :=
  ∀ (context : SurfaceElaboration.Context)
    (target : extractedProgram.target = context.target) (nextVariable : VarId),
    entry.body.Meaning entry.body.result context nextVariable entry.surface

def InsertedBody.Stored (entry : InsertedBody) (catalog : Catalog)
    (position : Nat) (heap : Heap) : Prop :=
  StoredTerminalRepresentation heap (catalog.rowBase position) entry.id
    entry.events entry.types entry.ends entry.body.count entry.annotations entry.body.coreStatement

def prefixRows (original : Nat → PreviousRow) (start : Nat)
    (inserted : List InsertedBody) (index : Nat) : PreviousRow :=
  if index < start then original index else
    match inserted[index - start]? with
    | some entry => entry.previous
    | none => original index

def OriginalScan.Source (scan : OriginalScan raw rawWorkspace normal validation)
    (entry : InsertedBody) : Prop :=
  ∃ inside : entry.sourceRow < normal.count,
    ∃ chosen : selectedRowBool raw.owner (normal.rowValue entry.sourceRow) = true,
      ∃ bounds : 0 ≤ (normal.rowValue entry.sourceRow).coreId.toInt ∧
          (normal.rowValue entry.sourceRow).coreId.toInt < scan.signatures.index.count.toInt,
        ∃ present : scan.signatures.present entry.sourceRow inside chosen bounds = true,
          let original := scan.producers entry.sourceRow inside chosen bounds present
          entry.id = (normal.rowValue entry.sourceRow).coreId ∧
          entry.body = original.body ∧ entry.surface = original.natural.surface ∧
          entry.annotations = original.output.enabled

noncomputable def OriginalScan.remainingPlan
    (scan : OriginalScan raw rawWorkspace normal validation) (lowered : Nat) : List Nat :=
  (scan.selectedRows.drop lowered).flatMap fun position =>
    [localBytes raw.tokenCount.toInt.toNat, scan.emittedCount position * 56,
      scan.emittedCount position * 4]

def OriginalScan.signatureBool (scan : OriginalScan raw rawWorkspace normal validation)
    (position : Nat) (inside : position < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue position) = true) : Bool :=
  if bounds : 0 ≤ (normal.rowValue position).coreId.toInt ∧
      (normal.rowValue position).coreId.toInt < scan.signatures.index.count.toInt then
    scan.signatures.present position inside chosen bounds
  else false

end IRBodyOwnedProof
