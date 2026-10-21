import verified_compiler.tests.direct_ir_owned_interface
import verified_compiler.tests.direct_ir_body_production_void_tests
import Lanius.Semantics.Representation

namespace ProofInterfaceOwnedDomain

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRBodyOwnedInputs IRBodyOwnedProof IRBodyProductionInputs IRBodyProductionProof
open IRBodyProductionScalar IRValueCatalogValid IRCatalogConstructionProof IRCatalogAppendProof

/- The source, native return topology, signature, occupied catalog row and output
   storage are the existing producer fixture. Only the caller's original
   allocation-table storage is added here. In particular it starts owned. -/

def table : AllocationTable := { memory := 5120, count := 1 }
def header : Header := { fields := fun field => if field.val = 1 then 1 else 0 }
def row : AllocationRow := {
  source := {
    unit := 0, kind := .Function, isPublic := false, item := 0
    declaration := 0, name := 0, target := 0, ordinal := 0 }
  declarationId := 0, coreId := 0 }
private def tableBytes : List UInt8 := List.replicate 8 0 ++ i32Bytes 1 ++
  List.replicate 68 0 ++ encodeNatLE 4 5 ++ List.replicate 68 0
def tableBlock : Block := { base := table.memory, size := 152, alignment := 8, bytes := tableBytes }
def origin : State := { IRBodyProductionVoidTests.funded with
  heap := { IRBodyProductionVoidTests.funded.heap with
    blocks := IRBodyProductionVoidTests.funded.heap.blocks ++ [tableBlock]
    nextAddress := 5272 } }

private theorem oldReads : HeapReads IRBodyProductionVoidTests.funded.heap origin.heap := by
  intro pointer offset byte read
  obtain ⟨block, found, contents⟩ := Heap.loadByte_ok_iff.mp read
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨block, ?_, contents⟩
  simp only [Heap.containingBlock?, origin, List.find?_append] at found ⊢
  rw [found, Option.some_or]

private theorem oldBase (block : Block) (member : block ∈ IRBodyProductionVoidTests.funded.heap.blocks) :
    block.base < 5120 := by
  have below := IRBodyProductionVoidTests.catalogInvariant.below block member
  have positive := Nat.le_max_right block.size 1
  change block.base + max block.size 1 ≤ 5120 at below
  dsimp only [Address] at *
  omega

private theorem unique : HeapBlockBasesUnique origin.heap := by
  intro left hl right hr same
  simp only [origin, List.mem_append, List.mem_singleton] at hl hr
  rcases hl with hl | rfl <;> rcases hr with hr | rfl
  · exact IRBodyProductionVoidTests.catalogInvariant.unique left hl right hr same
  · exact False.elim ((Nat.ne_of_lt (oldBase left hl)) same)
  · exact False.elim ((Nat.ne_of_lt (oldBase right hr)) same.symm)
  · rfl

private theorem below : HeapBlocksBelowNext origin.heap := by
  intro block member
  rcases List.mem_append.mp member with old | fresh
  · have bound := IRBodyProductionVoidTests.catalogInvariant.below block old
    change block.base + max block.size 1 ≤ 5120 at bound
    change block.base + max block.size 1 ≤ 5272
    dsimp only [Address] at bound ⊢
    omega
  · simp only [List.mem_singleton] at fresh
    subst block
    decide

macro "table_primitive" : tactic => `(tactic| first
  | exact (NativeSnapshot.scalarOfRead (Or.inr rfl) rfl).enlarge (by decide)
  | exact (NativeSnapshot.scalarOfRead (Or.inl rfl) rfl).enlarge (by decide)
  | exact (NativeSnapshot.enumEmpty
      (by core_lookup) (by decide +kernel) (by decide) rfl).enlarge (by decide))

private def nativeHeader : NativeHeader table origin.heap := {
  header := header
  snapshot := by
    original_record [0, 8, 16, 24, 32, 40, 48, 56, 64], [8, 8, 8, 8, 8, 8, 8, 8, 8], 9 =>
      table_primitive }

private def nativeRow : NativeRow table origin.heap 0 := {
  row := row
  snapshot := by
    have declaration : NativeSnapshot 63 extractedProgram origin.heap
        (match row.source.value with | .structure id _ => .structure id | _ => .unit)
        (table.rowBase 0) row.source.value 64 := by
      original_record [0, 8, 16, 24, 32, 40, 48, 56], [8, 8, 8, 8, 8, 8, 8, 8], 8 =>
        table_primitive
    original_record [0, 64, 72], [64, 8, 8], 3 => first | exact declaration | table_primitive }

def normal : NormalTable table origin.heap := {
  count := 1, countEq := rfl, offsetFits := by decide
  geometry := {
    block := tableBlock, found := rfl, aligned := by decide
    alignment := by decide, bounds := by decide, pointerFits := by decide, unique := unique }
  rowsBounds := by decide, pointerFits := by decide, header := nativeHeader
  rows := fun index inside => by
    have zero : index = 0 := by omega
    subst index
    exact nativeRow }

private theorem locations : RowLocations normal := by
  intro index inside
  have zero : index = 0 := by change index < 1 at inside; omega
  subst index
  rfl

def values : Values := {
  address := 0, length := 0, count := 0
  binding := fun _ => { token := 0, scope := .InvalidScope, target := .InvalidTarget } }
def index : Index := {
  table := table, address := 0, length := 0
  enumerationAddress := 0, enumerationLength := 0, enumerationCount := 0
  count := 0, valid := true, entry := fun _ => { declarationRow := 0, coreRow := 0 } }
private def allocationTail : Fin 5 → Value := fun field => match field.val with
  | 0 => .rawSlice indexEntryType 0 0
  | 1 => .rawSlice (.scalar (.signed .i32)) 0 0
  | 2 | 3 => .signed .i32 0
  | _ => .boolean true

def input : Inputs := { IRBodyProductionVoidTests.inputs with
  allocationTable := table.value, allocationTail := allocationTail, values := values.value }
abbrev raw : RawInputs := {
  owner := input.owner, source := input.source, sourceWords := 6
  tokens := input.tokens, tokenCount := 1, tokenStorage := input.tokenStorage
  nodes := .rawSlice nodeType input.tree.nodes input.tree.nodesLength
  children := .rawSlice childType input.tree.children input.tree.childrenLength
  nodeCount := 6, childCount := 15
  allocationTable := table, allocationTail := allocationTail
  signatureData := .rawSlice signatureType input.signature.address input.signature.length
  signatureCount := 1, signatureTail := input.signature.tail
  resolutions := input.resolutions, aliases := input.aliases
  valueData := .rawSlice bindingType 0 0, valueCount := 0
  valueNames := input.valueNames, contexts := input.contexts
  sourceCatalog := input.sourceCatalog, tokenCatalog := input.tokenCatalog
  globalDeclarations := input.globalDeclarations, trees := input.trees }

private def sourceNatural : NaturalBody input IRBodyProductionVoidTests.funded 0 := {
  topology := { IRBodyProductionVoidTests.natural.topology with
    returnToken := { IRBodyProductionVoidTests.natural.topology.returnToken with } }
  keyword := { IRBodyProductionVoidTests.natural.keyword with
    toNativeToken := { IRBodyProductionVoidTests.natural.keyword.toNativeToken with } }
  returns := .void rfl rfl }
private def natural : NaturalBody input origin 0 := sourceNatural.afterReads oldReads
private def signature : NativeSignature input.signature origin.heap :=
  IRBodyProductionVoidTests.nativeSignature.afterReads oldReads
private def output : IREventStoreProof.Context origin := {
  IRBodyProductionVoidTests.output false with
  eventRoom := oldReads.readable (IRBodyProductionVoidTests.output false).eventRoom
  typeRoom := fun enabled => oldReads.readable ((IRBodyProductionVoidTests.output false).typeRoom enabled) }
private def permissions : OutputPermissions output ReturnBody.void.count :=
  (IRBodyProductionVoidTests.permissions false).afterReads oldReads

def rawWorkspace : RawWorkspace := {
  expressionData := .unit, expressionCount := .unit, expressionCapacity := 1
  codes := .unit, depths := .unit, typeData := .unit, typeCount := .unit, typeCapacity := 1
  aliasScratch := .unit, aliasCapacity := 0, typeOutput := .unit, typeOutputCount := 1
  events := output.value, catalog := IRBodyProductionVoidTests.catalog.value }
private def workspace : Workspace := {
  expressionData := .unit, expressionCount := .unit, expressionCapacity := 1
  codes := .unit, depths := .unit
  types := source_value Extracted.«verified::surface_type».Types.«TypeArena».mk
    [.unit, .unit, .signed .i32 1]
  aliasScratch := .unit, aliasCapacity := 0
  typeOutput := source_value Extracted.«lowering::types».Types.«Results».mk [.unit, .signed .i32 1]
  events := output.value, catalog := IRBodyProductionVoidTests.catalog.value }

def validation : OriginalValidation raw origin := {
  values := values, index := index, valuesValue := rfl, valuesCount := rfl
  indexValue := rfl, table := rfl
  native := {
    bindings := by intro _ position _ upper; change position < 0 at upper; omega
    entries := by intro _ position _ upper; change position < 0 at upper; omega
    safeRows := by intro _ position _ upper; change position < 0 at upper; omega } }

theorem valid : SemanticValidSlice validation.values validation.index normal.rowValue
    0 validation.values.count.toInt raw.tokenCount.toInt := by
  refine ⟨rfl, ?_⟩
  intro position member
  change position ∈ ([] : List Nat) at member
  cases member

private def signatures : OriginalSignatures raw normal := {
  index := {
    address := input.signature.address, length := input.signature.length
    count := 1, tail := input.signature.tail }
  descriptor := rfl, count := rfl, capacity := by decide
  slots := fun position inside _ _ => by
    have zero : position = 0 := by change position < 1 at inside; omega
    subst position
    exact {
      entry := {
        id := 0, kind := .Function, shape := .InternalFunctionShape
        arity := 0, result := .Void, starts := fun _ => 0 }
      base := signature.base, inside := by decide, location := signature.location
      snapshot := signature.snapshot } }

private theorem catalogInvariant : Invariant IRBodyProductionVoidTests.catalog 1
    (fun _ => IRBodyProductionVoidTests.previous) origin := {
  supported := IRBodyProductionVoidTests.catalogInvariant.supported
  bounds := IRBodyProductionVoidTests.catalogInvariant.bounds
  count := oldReads.nativeValue IRBodyProductionVoidTests.catalogInvariant.count
  backing := oldReads.readable IRBodyProductionVoidTests.catalogInvariant.backing
  occupied := fun slot inside =>
    (IRBodyProductionVoidTests.catalogInvariant.occupied slot inside).afterHeapReads oldReads
  formed := IRBodyProductionVoidTests.catalogInvariant.formed
  unique := unique, below := below, noViews := rfl }

private def occupied : OccupiedStorage IRBodyProductionVoidTests.previous origin.heap := {
  events := 0, types := 0, ends := 0, eventLength := 0, typeLength := 0, endLength := 0
  enabled := false, count := 0, descriptor := rfl
  eventBound := by decide, typeBound := fun _ => by decide, endBound := by decide
  eventBases := fun _ => 0, typeBases := fun _ => 0
  eventLocation := by intro position inside; change position < 0 at inside; omega
  typeLocation := by intro _ position inside; change position < 0 at inside; omega
  eventValues := fun _ => .unit, typeValues := fun _ => .unit, endValues := fun _ => 0
  eventSnapshot := by intro position inside; change position < 0 at inside; omega
  typeSnapshot := by intro _ position inside; change position < 0 at inside; omega
  endSnapshot := by intro position inside; change position < 0 at inside; omega
  stringSnapshot := by intro position inside; change position < 0 at inside; omega }

def region (address : Nat) : Prop :=
  (256 ≤ address ∧ address < 4240) ∨ (5120 ≤ address ∧ address < 5272)
private def mutable (address : Nat) : Prop := address < 128

private def producer : OriginalProducer raw rawWorkspace row origin region mutable
    IRBodyProductionVoidTests.catalog := {
  input := input, workspace := workspace, inputValue := rfl, workspaceValue := rfl
  declaration := 0, declarationEq := rfl, signatureId := rfl, nodeCount := rfl, tokenCount := rfl
  natural := natural, native := signature, body := .void, selected := rfl
  storage := PUnit.unit, output := output, zero := rfl, permissions := permissions
  events := rfl, catalogValue := rfl, tokenBound := by decide
  sourceCovered := fun address source => Or.inl (IRBodyProductionVoidTests.originalRange source)
  mutableCovered := by
    intro address changed
    rcases changed with impossible | written
    · exact False.elim impossible
    · exact IRBodyProductionVoidTests.outputBelow written
  outputApart := by intro _ _ impossible; exact impossible }

def scan : OriginalScan raw rawWorkspace normal validation := {
  catalog := IRBodyProductionVoidTests.catalog, initialCount := 1
  previous := fun _ => IRBodyProductionVoidTests.previous, invariant := catalogInvariant
  region := region, occupied := fun _ _ => occupied
  occupiedCovered := by
    intro _ _ address used
    rcases used with ⟨position, inside, _⟩ | ⟨position, inside, _⟩ <;>
      change position < 0 at inside <;> omega
  tableCovered := fun address lower upper => Or.inr ⟨lower, upper⟩
  validationCovered := by
    intro address used
    rcases used with ⟨_, position, _, upper, _⟩ | ⟨_, position, _, upper, _⟩ <;>
      change position < 0 at upper <;> omega
  mutable := mutable
  protectedApart := by
    intro address used changed
    change address < 128 at changed
    rcases used with used | used <;> omega
  catalogApart := by
    intro address used catalog
    change 4608 ≤ address ∧ address < 4808 at catalog
    rcases used with used | used <;> omega
  workspaceCatalogApart := by
    intro address lower upper changed
    change 4608 ≤ address at lower
    change address < 128 at changed
    omega
  mutableBelow := by intro address changed; change address < 128 at changed; change address < 5272; omega
  signatures := signatures
  signatureCovered := by
    intro position inside chosen bounds address lower upper
    have zero : position = 0 := by change position < 1 at inside; omega
    subst position
    change 4168 ≤ address at lower
    change address < 4240 at upper
    exact Or.inl ⟨by omega, upper⟩
  producers := fun position inside _ _ _ => by
    have zero : position = 0 := by change position < 1 at inside; omega
    subst position
    exact producer
  addressRoom := by decide }

/-- This witness reaches the normal branch with a selected natural function. -/
def domain : OriginalDomain raw rawWorkspace origin :=
  .normal normal locations (by unfold RawInputs.beforeHeaderReject; decide)
    (by unfold RawInputs.afterHeaderReject; decide) rfl (by decide) validation (fun _ => scan)

theorem selected : scan.selectedRows = [0] := rfl
theorem initiallyOwned : normal.geometry.block.owned = true := rfl
theorem selectedVoid : (scan.producers 0 (by decide) rfl (by decide) rfl).body = .void := rfl

private theorem emitted : scan.emittedCount 0 = 1 := by
  simp only [OriginalScan.emittedCount]
  rw [dif_pos (show 0 < normal.count by decide), dif_pos (show selectedRowBool raw.owner (normal.rowValue 0) = true from rfl),
    dif_pos (show 0 ≤ (normal.rowValue 0).coreId.toInt ∧
      (normal.rowValue 0).coreId.toInt < scan.signatures.index.count.toInt by decide),
    dif_pos (show scan.signatures.present 0 (by decide) rfl (by decide) = true from rfl)]
  rfl

theorem fullyFunded : FullFunding scan := {
  signatures := by
    intro position inside chosen
    have zero : position = 0 := by change position < 1 at inside; omega
    subst position
    exact ⟨by decide, rfl⟩
  room := by rw [selected]; decide
  distinct := by rw [selected]; simp
  absent := by
    intro position member previous inside
    rw [selected] at member
    simp only [List.mem_singleton] at member
    subst position
    change (40 : Int32) ≠ 0
    decide
  budget := by
    have plan : scan.fundingPlan = [32, 56, 4] := by
      change [32, scan.emittedCount 0 * 56, scan.emittedCount 0 * 4] = [32, 56, 4]
      rw [emitted]
    rw [plan]
    exact ⟨some 60, rfl, some 4, rfl, some 0, rfl, True.intro⟩ }

/-- The complete caller theorem reaches one successful append on these
    independently supplied original bytes and the exact funding budget. -/
theorem lowersOne : ∃ after,
    RunsExpr extractedProgram origin (ownedCall raw.value rawWorkspace.value)
      (.signed .i32 1) after ∧ SuccessfulScan scan after := by
  obtain ⟨result, after, run, _, _, _, observed⟩ :=
    actualOwnedLowering raw rawWorkspace origin domain catalogInvariant.formed
  have outcome : ScanResult scan result after := by
    simpa only [domain, OwnedOutcome, dif_pos valid] using observed
  have one : result = 1 := by
    simpa [selected] using outcome.2.2 fullyFunded
  refine ⟨after, one ▸ run, ?_⟩
  rcases outcome.2.1 with failure | success
  · omega
  · exact success.2

#print axioms domain
#print axioms selected
#print axioms initiallyOwned
#print axioms selectedVoid
#print axioms fullyFunded
#print axioms lowersOne

end ProofInterfaceOwnedDomain
