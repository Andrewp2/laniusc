import verified_compiler.tests.direct_ir_body_production
import verified_compiler.tests.direct_ir_body_production_inputs_signature
import verified_compiler.tests.direct_ir_body_production_event_store_tests
import Lanius.Semantics.NativeRecordStore
import Lanius.Semantics.NativeSliceStore

namespace IRBodyProductionVoidTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRBodyProductionInputs IRBodyProductionProof IRTypeRefProof
open IREventStoreProof IRBodyProductionEventStoreTests
open IRBodyProductionScalar

private def word (value : Int) : List UInt8 := i32Bytes value ++ List.replicate 4 165
private def tag (value : Value) : List UInt8 := match value with
  | .enumeration _ ordinal _ => encodeNatLE 4 ordinal ++ List.replicate 4 165
  | _ => []
private def node (production first count : Int) : List UInt8 :=
  word production ++ word 0 ++ word 6 ++ word first ++ word count
private def child (kind : ChildKind) (payload : Int) : List UInt8 :=
  tag (childKindValue kind) ++ word payload ++ word 0

-- Records are supplied as original bytes. Reverse native indexing leaves
-- unused physical capacity below the six reached nodes and fifteen children.
private def nodes := List.replicate 80 165 ++
  node 74 15 0 ++ node 91 15 0 ++ node 76 13 2 ++ node 73 11 2 ++ node 12 9 2 ++ node 11 0 9
private def children := (List.range 18).reverse.flatMap fun index => match index with
  | 8 => child .StateChild 1
  | 10 => child .StateChild 2
  | 11 => child .StateChild 3
  | 12 => child .StateChild 5
  | 13 => child .TokenChild 0
  | 14 => child .StateChild 4
  | _ => child .NoChild 0
private def token := tag (source_value Extracted.«verified::token».Types.«TokenKind».«ReturnKeyword» []) ++
  word 0 ++ word 6
private def signatureBytes := word 0 ++ tag functionKind ++ tag internalShape ++ word 0 ++
  tag (referenceValue .Void) ++ List.replicate 8 165 ++ word 0 ++ word 0 ++ word 0
private def sourceWords := "return".toList.map fun character => i32Bytes character.toNat
private def sourceBlocks : List Lanius.Memory.Block := [
  { base := 256, size := 40, alignment := 4, bytes := sourceWords.flatten ++ List.replicate 16 165 },
  { base := 1024, size := 320, alignment := 8, bytes := nodes },
  { base := 2048, size := 432, alignment := 8, bytes := children },
  { base := 3072, size := 72, alignment := 8, bytes := List.replicate 48 165 ++ token },
  { base := 4096, size := 144, alignment := 8, bytes := List.replicate 72 165 ++ signatureBytes }]

def inputs : Inputs := {
  owner := 0
  source := .rawSlice (.scalar (.signed .i32)) 256 10
  sourceLength := 6
  tokens := .rawSlice tokenType 3136 3
  tokenCount := 1
  tokenStorage := 640
  tree := {
    nodes := 1336
    children := 2472
    nodesLength := 8
    childrenLength := 18
    nodeCount := 6
    childCount := 15
    nodesBound := by decide
    childrenBound := by decide
    nodesFit := by decide
    childrenFit := by decide }
  allocationTable := .unit
  allocationTail := fun _ => .unit
  signature := {
    address := 4232
    length := 2
    count := 1
    id := 0
    result := .Void
    tail := fun _ => .unit
    starts := fun _ => .signed .i32 0
    inside := by decide
    bound := by decide
    fits := by decide }
  resolutions := .unit
  aliases := .unit
  values := .unit
  valueNames := .unit
  contexts := .unit
  sourceCatalog := .unit
  tokenCatalog := .unit
  globalDeclarations := .unit
  trees := .unit }
private def workspace : Workspace := {
  expressionData := .unit, expressionCount := .unit, expressionCapacity := 0
  codes := .unit, depths := .unit, types := .unit, aliasScratch := .unit, aliasCapacity := 0
  typeOutput := .unit, events := .unit, catalog := .unit }

def catalog : IRCatalogConstructionProof.Catalog := { memory := 4608, capacity := 2 }
def previous : IRCatalogAppendProof.PreviousRow := {
  id := 40, parameters := 0, result := .Void, tree := IRBuilderProof.emptyTree }
private def previousBytes : List UInt8 :=
  word 40 ++ tag (referenceValue .Void) ++ List.replicate 8 165 ++ word 0 ++ List.replicate 64 0
private def catalogBytes := word 1 ++ List.replicate 96 165 ++ previousBytes
def funded : State := { original with
  heap := {
    blocks := original.heap.blocks ++ sourceBlocks ++ [
      { base := catalog.memory, size := catalog.bytes, alignment := 8, bytes := catalogBytes }]
    nextAddress := 5120, remaining := some 92 }
  world := { standardOutput := [88], standardError := [89] } }
def fundedWorkspace (enabled : Bool) : Workspace := {
  workspace with events := (input enabled).value, catalog := catalog.value }

private theorem fundedUnique : HeapBlockBasesUnique funded.heap := by
  intro left leftMember right rightMember same
  simp only [funded, original, sourceBlocks, List.mem_append,
    List.mem_cons, List.not_mem_nil, or_false, or_assoc] at leftMember rightMember
  rcases leftMember with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    rcases rightMember with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    first | rfl | cases same

macro "original_location" words:num : tactic => `(tactic|
  apply rawSliceElementAddress_of_layout (words := $words) rfl (by decide +kernel) (by decide) <;> decide)

-- Primitive snapshots read only the supplied original bytes; no identity
-- store or future query is used to construct a native record witness.
private theorem originalWord (number : Int) (lower : -(2 ^ 31) ≤ number)
    (upper : number < 2 ^ 31) (large : 4 ≤ size)
    (loaded : funded.heap.loadBytes address 4 = .ok (i32Bytes number)) :
    NativeSnapshot (fuel + 1) extractedProgram funded.heap (.scalar (.signed .i32))
      address (.signed .i32 number) size := by
  have represented : (BitVec.ofInt 32 number).toInt = number :=
    BitVec.toInt_ofInt_eq_self (by decide) lower upper
  simpa only [represented] using
    (NativeSnapshot.i32 (program := extractedProgram) (fuel := fuel)
      (BitVec.ofInt 32 number) (by simpa only [represented] using loaded)).enlarge large

private theorem originalFalse
    (loaded : funded.heap.loadBytes address 4 = .ok (encodeNatLE 4 0)) :
    NativeSnapshot (fuel + 1) extractedProgram funded.heap (.scalar .bool)
      address (.boolean false) 8 := by
  intro other reads
  have loaded := reads _ _ _ (Nat.le_refl _) (by omega) loaded
  simp only [readNativeValue, loadNatLE_of_encoded loaded (by decide)]
  rfl

private theorem originalEmptySlice
    (supported : nativeSliceSupported extractedProgram element = true)
    (pointer : funded.heap.loadBytes address 8 = .ok (encodeNatLE 8 0))
    (length : funded.heap.loadBytes (address + 8) 8 = .ok (encodeNatLE 8 0)) :
    NativeSnapshot (fuel + 1) extractedProgram funded.heap (.slice element)
      address (.rawSlice element 0 0) 16 := by
  intro other reads
  have pointer := reads _ _ _ (Nat.le_refl _) (by omega) pointer
  have length := reads (address + 8) 8 _ (by omega) (by omega) length
  simp only [readNativeValue]
  change (if !nativeSliceSupported extractedProgram element then .error .typeMismatch else do
      let pointer ← loadNatLE other address 8
      let length ← loadNatLE other (address + 8) 8
      pure (Value.rawSlice element pointer length)) = .ok (.rawSlice element 0 0)
  simp only [supported, Bool.not_true, Bool.false_eq_true, ↓reduceIte,
    loadNatLE_of_encoded pointer (by decide), loadNatLE_of_encoded length (by decide)]
  rfl

open Lean Meta Elab Tactic in
elab "original_primitive" : tactic => withMainContext do
  let target ← instantiateMVars (← (← getMainGoal).getType)
  unless target.isAppOfArity ``NativeSnapshot 7 do throwError "native snapshot required"
  let value ← whnf target.getAppArgs[5]!
  if value.isAppOfArity ``Lanius.Core.Value.signed 2 then
    evalTactic (← `(tactic| apply originalWord <;> first | rfl | decide))
  else if value.isAppOfArity ``Lanius.Core.Value.enumeration 3 then
    evalTactic (← `(tactic| exact (NativeSnapshot.enumEmpty
      (by core_lookup) (by decide +kernel) (by decide) rfl).enlarge (by decide)))
  else if value.isAppOfArity ``Lanius.Core.Value.boolean 1 then
    evalTactic (← `(tactic| exact originalFalse rfl))
  else if value.isAppOfArity ``Lanius.Core.Value.rawSlice 3 then
    evalTactic (← `(tactic| exact originalEmptySlice (by decide +kernel) rfl rfl))
  else throwError "original primitive bytes required"

open Lean Meta Elab Tactic in
private def originalFinite (index : TSyntax `ident) : Nat → TSyntax `tactic → TacticM (TSyntax `tactic)
  | 0, _ => `(tactic| ((try simp only [List.length_cons, List.length_nil] at *); omega))
  | count + 1, leaf => do
      let tail ← originalFinite index count leaf
      `(tactic| cases $index:ident with | zero => $leaf:tactic | succ $index:ident => $tail:tactic)

open Lean Meta Elab Tactic in
elab "original_fields " count:num " => " leaf:tactic : tactic => do
  let index := mkIdent (← mkFreshUserName `field)
  let bound := mkIdent (← mkFreshUserName `inside)
  let cases ← originalFinite index count.getNat leaf
  evalTactic (← `(tactic| intro $index:ident $bound:ident; $cases:tactic))

open Lean Elab Tactic in
elab "original_record " offsets:term ", " widths:term ", " count:num " => " leaf:tactic : tactic => do
  evalTactic (← `(tactic| apply NativeSnapshot.record
    (offset := fun index => (($offsets)[index]?).getD 0)
    (width := fun index => (($widths)[index]?).getD 0)))
  evalTactic (← `(tactic| next => core_lookup))
  evalTactic (← `(tactic| next => rfl))
  evalTactic (← `(tactic| next => original_fields $count => decide +kernel))
  evalTactic (← `(tactic| next => original_fields $count => first | decide | omega))
  evalTactic (← `(tactic| original_fields $count => $leaf:tactic))

def nativeSignature : NativeSignature inputs.signature funded.heap := {
  base := 4168
  location := by original_location 9
  snapshot := by original_record [0, 8, 16, 24, 32, 48, 56, 64], [8, 8, 8, 8, 16, 8, 8, 8], 8 => original_primitive }

private def topology : TerminalTopology inputs funded.heap 0 := {
  block := 1, list := 2, statement := 3, rest := 5, optional := 4, tokenIndex := 0
  declarationNode := {
    production := 11, origin := 0, finish := 6, first := 0, count := 9, base := 1304
    inside := by decide, childrenInside := by decide, location := by original_location 5
    snapshot := by original_record [0, 8, 16, 24, 32], [8, 8, 8, 8, 8], 5 => original_primitive }
  declarationProduction := rfl, declarationBound := by decide
  bodyChild := {
    kind := .StateChild, payload := 1, semantic := 0, base := 2264
    inside := by decide, location := by original_location 3
    snapshot := by original_record [0, 8, 16], [8, 8, 8], 3 => original_primitive }
  bodyKind := rfl, bodyIndex := rfl
  blockNode := {
    production := 12, origin := 0, finish := 6, first := 9, count := 2, base := 1264
    inside := by decide, childrenInside := by decide, location := by original_location 5
    snapshot := by original_record [0, 8, 16, 24, 32], [8, 8, 8, 8, 8], 5 => original_primitive }
  blockProduction := rfl, blockBound := by decide
  listChild := {
    kind := .StateChild, payload := 2, semantic := 0, base := 2216
    inside := by decide, location := by original_location 3
    snapshot := by original_record [0, 8, 16], [8, 8, 8], 3 => original_primitive }
  listKind := rfl, listIndex := rfl
  listNode := {
    production := 73, origin := 0, finish := 6, first := 11, count := 2, base := 1224
    inside := by decide, childrenInside := by decide, location := by original_location 5
    snapshot := by original_record [0, 8, 16, 24, 32], [8, 8, 8, 8, 8], 5 => original_primitive }
  listProduction := rfl, listBound := by decide
  firstChild := {
    kind := .StateChild, payload := 3, semantic := 0, base := 2192
    inside := by decide, location := by original_location 3
    snapshot := by original_record [0, 8, 16], [8, 8, 8], 3 => original_primitive }
  firstKind := rfl, firstIndex := rfl
  restChild := {
    kind := .StateChild, payload := 5, semantic := 0, base := 2168
    inside := by decide, location := by original_location 3
    snapshot := by original_record [0, 8, 16], [8, 8, 8], 3 => original_primitive }
  restKind := rfl, restIndex := rfl
  restNode := {
    production := 74, origin := 0, finish := 6, first := 15, count := 0, base := 1104
    inside := by decide, childrenInside := by decide, location := by original_location 5
    snapshot := by original_record [0, 8, 16, 24, 32], [8, 8, 8, 8, 8], 5 => original_primitive }
  restProduction := rfl
  statementNode := {
    production := 76, origin := 0, finish := 6, first := 13, count := 2, base := 1184
    inside := by decide, childrenInside := by decide, location := by original_location 5
    snapshot := by original_record [0, 8, 16, 24, 32], [8, 8, 8, 8, 8], 5 => original_primitive }
  statementProduction := rfl, statementBound := by decide
  optionalChild := {
    kind := .StateChild, payload := 4, semantic := 0, base := 2120
    inside := by decide, location := by original_location 3
    snapshot := by original_record [0, 8, 16], [8, 8, 8], 3 => original_primitive }
  optionalKind := rfl, optionalIndex := rfl
  optionalNode := {
    production := 91, origin := 0, finish := 6, first := 15, count := 0, base := 1144
    inside := by decide, childrenInside := by decide, location := by original_location 5
    snapshot := by original_record [0, 8, 16, 24, 32], [8, 8, 8, 8, 8], 5 => original_primitive }
  returnChild := {
    kind := .TokenChild, payload := 0, semantic := 0, base := 2144
    inside := by decide, location := by original_location 3
    snapshot := by original_record [0, 8, 16], [8, 8, 8], 3 => original_primitive }
  returnKind := rfl, returnIndex := rfl
  returnToken := {
    address := 3136, length := 3, base := 3120
    kind := source_value Extracted.«verified::token».Types.«TokenKind».«ReturnKeyword» []
    start := 0, finish := 6, descriptor := rfl, inside := by decide, bound := by decide
    location := by original_location 3
    snapshot := by original_record [0, 8, 16], [8, 8, 8], 3 => original_primitive }
  returnKeyword := rfl, distinct := by decide }

def output (enabled : Bool) : Context funded := {
  input enabled with
  eventRoom := Heap.Readable.of_loadBytes (show funded.heap.loadBytes 56 40 = .ok eventBytes from rfl)
  typeRoom := by
    intro yes
    change enabled = true at yes
    simp only [input, yes, ↓reduceIte]
    exact Heap.Readable.of_loadBytes (show funded.heap.loadBytes 112 16 = .ok typeBytes from rfl) }

theorem catalogInvariant : IRCatalogConstructionProof.Invariant catalog 1 (fun _ => previous) funded := {
  supported := ⟨by decide, by decide⟩, bounds := ⟨by decide, by decide⟩
  count := (originalWord (fuel := 63) (size := 4) 1 (by decide) (by decide) (by decide) rfl).read
  backing := by
    intro index inside
    have length : catalogBytes.length = catalog.bytes := by decide +kernel
    have bound : index < catalogBytes.length := by omega
    refine ⟨catalogBytes[index], Heap.loadByte_ok_iff.mpr ⟨
      { base := catalog.memory, size := catalog.bytes, alignment := 8, bytes := catalogBytes }, ?_, ?_⟩⟩
    · change index < 200 at inside
      dsimp only [Heap.containingBlock?, funded, original, sourceBlocks,
        catalog, IRCatalogConstructionProof.Catalog.bytes, IRCatalogConstructionProof.Catalog.length]
      simp (disch := omega)
      omega
    · simpa only [Nat.add_sub_cancel_left] using
        (show catalogBytes[index]? = some catalogBytes[index] from List.getElem?_eq_getElem bound)
  occupied := by
    intro index inside
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    have signatureSnapshot : NativeSnapshot 63 extractedProgram funded.heap (.structure 4)
        (catalog.rowBase 0) (IRCatalogStoreProof.signature previous.id previous.parameters previous.result) 32 := by
      original_record [0, 8, 24], [8, 16, 8], 3 => original_primitive
    have treeSnapshot : NativeSnapshot 63 extractedProgram funded.heap (.structure 8)
        (catalog.rowBase 0 + 32) previous.tree 64 := by
      original_record [0, 16, 32, 40, 56], [16, 16, 8, 16, 8], 5 => original_primitive
    original_record [0, 32], [32, 64], 2 =>
      first | exact signatureSnapshot | exact treeSnapshot
  formed := by simp [State.CellsWellFormed, funded, original]
  unique := fundedUnique
  below := by
    intro block member
    simp only [funded, original, sourceBlocks, List.mem_append,
      List.mem_cons, List.not_mem_nil, or_false, or_assoc] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
  noViews := rfl }

private theorem originalSourceWord (number : Int) (lower : -(2 ^ 31) ≤ number)
    (upper : number < 2 ^ 31) (inside : offset < 10)
    (loaded : funded.heap.loadBytes (256 + offset * 4) 4 = .ok (i32Bytes number)) :
    readRawSliceIndex extractedProgram funded (.scalar (.signed .i32)) 256 10 offset =
      .ok (.signed .i32 number) := by
  have represented : (BitVec.ofInt 32 number).toInt = number :=
    BitVec.toInt_ofInt_eq_self (by decide) lower upper
  simpa only [represented] using readRawSliceIndex_i32Bytes extractedProgram funded
    (word := BitVec.ofInt 32 number) inside (by simpa only [represented] using loaded)

def natural : NaturalBody inputs funded 0 := {
  topology := topology
  keyword := {
    toNativeToken := topology.returnToken
    sourceAddress := 256, sourceCapacity := 10, origin := 0
    kindMatches := rfl, startMatches := rfl, finishMatches := rfl
    source := rfl, span := by decide, sourceBound := by decide
    sourceFits := by decide, tokensFit := by decide
    words := by
      intro offset inside
      change offset < 6 at inside
      revert inside offset
      original_fields 6 => apply originalSourceWord <;> first | rfl | decide }
  returns := .void rfl rfl }

/-- The same original bytes inhabit the total theorem's natural domain. -/
theorem originalNaturalBody : ∃ body : NaturalBody inputs funded 0, body.Selects .void :=
  ⟨natural, rfl⟩

private def localsHeap := (funded.heap.allocatedBytes 32 8 (some 60)).borrowBlock 5120
private def request (enabled : Bool) := streamRequest (output enabled) 0 .Void .void
  (fun index => if index = 0 then .Invalid else inputs.signature.result)
private def model (enabled : Bool) := catalog.model 1 (fun _ => previous) (request enabled)

private theorem succeeds (enabled : Bool) : (model enabled).Success localsHeap := by
  have guard : (model enabled).Guarded := by
    change (0 : Int) ≤ 0 ∧ true = true ∧ (0 : Int) ≤ 0 ∧ (0 : Int) ≤ 1 ∧
      (1 : Int) < 2 ∧ (0 : Int) < 1 ∧ (1 : Int) ≤ 2
    decide
  have sized : (model enabled).Sized := by
    change 0 < (1 : Nat) ∧ (1 : Nat) ≤ 38347922
    decide
  refine ⟨guard, ?_, sized, ⟨some 4, some 0, rfl, rfl⟩, ?_⟩
  · rintro ⟨index, _, same⟩
    change (40 : Int) = 0 at same
    omega
  · refine ⟨fun _ => 1, ?_, rfl⟩
    intro index inside
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    exact ⟨by change (0 : Int) ≤ 0; decide,
      by change (0 : Int) ≤ (0 : Nat); decide,
      by change (Extracted.«ir::body_tree».Types.«NodeKind».«StatementNode» : IRShapeProof.Kind) ≠ .InvalidNode; decide,
      1, rfl, IRChildrenProof.ChildChain.nil⟩

def permissions (enabled : Bool) : OutputPermissions (output enabled) ReturnBody.void.count := {
  bound := by change (1 : Nat) ≤ 2; decide
  typeBound := fun yes => by change enabled = true at yes; subst enabled; decide
  eventBases := fun _ => (output enabled).eventBase
  typeBases := fun _ => (output enabled).typeBase
  eventLocation := fun index inside => by
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    exact (output enabled).eventLocation
  typeLocation := fun yes index inside => by
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    exact (output enabled).typeLocation yes
  eventRoom := fun _ _ => (output enabled).eventRoom
  typeRoom := fun yes _ _ => (output enabled).typeRoom yes
  planes := fun yes _ _ _ _ => (output enabled).separate yes }

theorem outputBelow (written : (permissions enabled).writesFrom 0 address) : address < 128 := by
  rcases written with ⟨index, _, _, event | ⟨yes, annotation⟩⟩
  · change 56 ≤ address ∧ address < 96 at event
    omega
  · change enabled = true at yes
    subst enabled
    change 112 ≤ address ∧ address < 128 at annotation
    omega

private theorem originalSlot (element : Ty) (pointer index words base : Nat)
    (nominal : (match element with | .structure _ | .enumeration _ => true | _ => false) = true)
    (layout : NativeLayout.valueWords? extractedProgram element = some words) (positive : 0 < words)
    (room : (index * words + words - 1) * 8 ≤ pointer)
    (location : rawSliceElementAddress? extractedProgram element pointer index = .ok base) :
    base + (index * words + words - 1) * 8 = pointer := by
  have known := rawSliceElementAddress_of_layout nominal layout positive room rfl
  have same := Except.ok.inj (location.symm.trans known)
  change base = pointer - (index * words + words - 1) * 8 at same
  omega

-- One address-only bound for the same logical original spans. This neither
-- reads spare slots nor reconstructs a second topology after production.
private theorem originalApart : InputApart inputs (fun address => ¬(256 ≤ address ∧ address < 4240)) := {
  nodes := fun index base inside location address lower upper outside => by
    change index < 6 at inside
    have point := originalSlot nodeType 1336 index 5 base rfl (by decide +kernel) (by decide) (by omega) location
    change base ≤ address at lower
    change address < base + 40 at upper
    dsimp only [Lanius.Address] at point lower upper
    exact outside ⟨by omega, by omega⟩
  children := fun index base inside location address lower upper outside => by
    change index < 15 at inside
    have point := originalSlot childType 2472 index 3 base rfl (by decide +kernel) (by decide) (by omega) location
    change base ≤ address at lower
    change address < base + 24 at upper
    dsimp only [Lanius.Address] at point lower upper
    exact outside ⟨by omega, by omega⟩
  tokens := fun pointer length index base descriptor inside location address lower upper outside => by
    change Value.rawSlice tokenType 3136 3 = .rawSlice tokenType pointer length at descriptor
    have same : pointer = 3136 ∧ length = 3 := by cases descriptor; exact ⟨rfl, rfl⟩
    rcases same with ⟨rfl, rfl⟩
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    have point := originalSlot tokenType 3136 0 3 base rfl (by decide +kernel) (by decide) (by decide) location
    change base ≤ address at lower
    change address < base + 24 at upper
    dsimp only [Lanius.Address] at point lower upper
    exact outside ⟨by omega, by omega⟩
  source := fun pointer length descriptor index inside address lower upper outside => by
    change Value.rawSlice (.scalar (.signed .i32)) 256 10 = .rawSlice (.scalar (.signed .i32)) pointer length at descriptor
    have same : pointer = 256 ∧ length = 10 := by cases descriptor; exact ⟨rfl, rfl⟩
    rcases same with ⟨rfl, rfl⟩
    change index < 6 at inside
    change 256 + index * 4 ≤ address at lower
    change address < 256 + index * 4 + 4 at upper
    dsimp only [Lanius.Address] at lower upper
    exact outside ⟨by omega, by omega⟩ }

theorem originalRange (inside : sourceBytes inputs nativeSignature address) :
    256 ≤ address ∧ address < 4240 := by
  apply Classical.byContradiction
  intro outside
  exact sourceBytes.apart originalApart
    (fun address lower upper => by change 4168 ≤ address at lower; change address < 4240 at upper; omega)
    inside outside

private theorem catalogFootprint (request : IRCatalogAppendProof.Model) :
    (catalog.model 1 (fun _ => previous) request).footprint address =
      ((4616 ≤ address ∧ address < 4712) ∨ (4608 ≤ address ∧ address < 4612)) := by
  dsimp only [IRCatalogAppendProof.Arguments.footprint, IRCatalogAppendProof.Arguments.rowBase,
    IRCatalogAppendProof.Arguments.occupied, IRCatalogConstructionProof.Catalog.model]
  rw [show catalog.length = 2 by decide +kernel,
    show (1 : Int32).toInt.toNat = 1 by decide +kernel]
  change ((4616 ≤ address ∧ address < 4712) ∨ (4608 ≤ address ∧ address < 4612)) = _
  rfl

/-- The total theorem is inhabited by the same occupied native input in both
    annotation modes, and retains source/Core meaning and readonly bytes. -/
theorem fundedSuccess (enabled : Bool) : ∃ after,
    RunsExpr extractedProgram funded (producerCall inputs (fundedWorkspace enabled) 0 inputs.tree.nodeCount)
      (.signed .i32 0) after ∧
    FunctionInsertion funded .void (output enabled) (permissions enabled) inputs.signature.result
      (fun address => False ∨ (permissions enabled).writesFrom 0 address)
      5120 localsHeap catalog 1 (fun _ => previous)
      (request enabled) funded after ∧ after.locals = funded.locals ∧
    inputs.signature.Read after ∧
    (∀ pointer offset byte, sourceBytes inputs nativeSignature (pointer + offset) →
      funded.heap.loadByte pointer offset = .ok byte → after.heap.loadByte pointer offset = .ok byte) ∧
    (∀ (context : SurfaceElaboration.Context) (_target : extractedProgram.target = context.target) (next : VarId),
      ReturnBody.void.Meaning inputs.signature.result context next natural.surface) ∧
    StoredTerminalRepresentation after.heap (catalog.rowBase 1) 0 5184 5200 5208 1 enabled (.returnValue none) ∧
    after.world = World.record (World.record (World.record funded.world .alloc) .alloc) .alloc := by
  classical
  obtain ⟨body, selected, result, after, run, _, locals, _, meaning, readonly, signature, _, inserted, _⟩ :=
    actualNaturalFunction inputs (fundedWorkspace enabled) 0 natural nativeSignature PUnit.unit
      (output enabled) rfl
      (fun body selected => by change body = .void at selected; subst body; exact permissions enabled)
      rfl rfl catalogInvariant (by decide) (by decide)
      (by
        intro body selected budget available
        change body = .void at selected
        subst body
        have same : budget = some 60 := Option.some.inj available.symm
        subst budget
        decide)
      (by
        intro body selected
        change body = .void at selected
        subst body
        exact originalApart.mono (fun address changed => by
          change False ∨ (permissions enabled).writesFrom 0 address at changed
          have bound := outputBelow (changed.elim False.elim id)
          omega))
      (by
        intro body selected address lower upper changed
        change body = .void at selected
        subst body
        change False ∨ (permissions enabled).writesFrom 0 address at changed
        have bound := outputBelow (changed.elim False.elim id)
        change 4168 ≤ address at lower
        omega)
      (by
        intro body selected address _ changed
        change body = .void at selected
        subst body
        change False at changed
        exact changed)
    (by
      intro body selected address lower _ changed
      change body = .void at selected
      subst body
      change False ∨ (permissions enabled).writesFrom 0 address at changed
      have bound := outputBelow (changed.elim False.elim id)
      change 4608 ≤ address at lower
      omega)
    (by
      intro body selected address inside _room changed
      change body = .void at selected
      subst body
      have range := originalRange inside
      rw [catalogFootprint] at changed
      omega)
  change body = .void at selected
  subst body
  obtain ⟨answer, post, world, stored⟩ := inserted (some 60) rfl
  have zero : result = 0 := by
    change result = (if (model enabled).Success localsHeap then 0 else -1) at answer
    simpa only [if_pos (succeeds enabled)] using answer
  rw [zero] at run
  refine ⟨after, run, post, locals, signature, readonly, meaning, ?_, ?_⟩
  · exact stored (succeeds enabled)
  · change after.world = (model enabled).expectedWorld localsHeap (World.record funded.world .alloc) at world
    have successful := succeeds enabled
    have active : (model enabled).Guarded ∧ ¬(model enabled).Duplicate ∧ (model enabled).Sized :=
      ⟨successful.1, successful.2.1, successful.2.2.1⟩
    have owned : consumeBudget localsHeap.remaining ((model enabled).request * 56) = some (some 4) := rfl
    simpa only [IRCatalogAppendProof.Model.expectedWorld, if_pos active, owned] using world

#print axioms fundedSuccess
#print axioms originalNaturalBody
#print axioms Lanius.Semantics.NativeSnapshot.record

-- One real1179 call starts with an occupied row and independently supplied
-- syntax/signature bytes. Its public result is0 even though append stores row1.
#eval (do
  for enabled in [false, true] do
    let before := funded
    let active := fundedWorkspace enabled
    unless (readRawSliceIndex extractedProgram before signatureType
        inputs.signature.address inputs.signature.length inputs.signature.id).toOption == some inputs.signature.entry &&
        (readRawSliceIndex extractedProgram before IRCatalogStoreProof.bodyType
          (catalog.memory + catalog.length * 96) catalog.length 0).toOption == some previous.value do
      throw (IO.userError "full Void fixture lacks its original signature or occupied row")
    unless consumeBudget before.heap.remaining 32 == some (some 60) &&
        consumeBudget (some 60) 56 == some (some 4) &&
        consumeBudget (some 4) 4 == some (some 0) do
      throw (IO.userError "full Void fixture lacks independent sequential allocation budget")
    if !enabled then
      unless (readRawSliceIndex extractedProgram before referenceType (input enabled).types
          (input enabled).typesLength 0).toOption.isNone do
        throw (IO.userError "disabled full Void annotation descriptor unexpectedly readable")
    let .done (.signed .i32 0) after :=
        evalExpr 900 extractedProgram before (producerCall inputs active 0 inputs.tree.nodeCount)
      | throw (IO.userError "actual append_function failed or returned the catalog row index")
    unless (after.heap.loadBytes catalog.memory 4).toOption == some (i32Bytes 2) &&
        (after.heap.loadBytes (catalog.rowBase 0) 96).toOption == some previousBytes do
      throw (IO.userError "actual append_function lost count2 or the original occupied row")
    let tree := IRValidatorProof.treeValue (.rawSlice eventType 5184 1)
      (.rawSlice referenceType 5200 1) true (.rawSlice (.scalar (.signed .i32)) 5208 1) 1
    let stored := IRCatalogStoreProof.body (IRCatalogStoreProof.signature 0 0 .Void) tree
    unless (readRawSliceIndex extractedProgram after IRCatalogStoreProof.bodyType
        (catalog.memory + catalog.length * 96) catalog.length 1).toOption == some stored &&
        (readNativeValue 64 extractedProgram after.heap eventType 5152).toOption == some (returnEvent false) &&
        (after.heap.loadBytes 5208 4).toOption == some (i32Bytes 1) do
      throw (IO.userError "actual append_function did not store its produced Void body and endpoint")
    for block in sourceBlocks do
      unless (after.heap.loadBytes block.base block.size).toOption == some block.bytes do
        throw (IO.userError "actual append_function changed original source/tree/token/signature bytes")
    for cell in before.cells do
      unless after.cell? cell.id == cell.value do
        throw (IO.userError "actual append_function changed an original caller cell")
    unless after.locals == before.locals && after.i32ArrayViews.isEmpty &&
        after.world.standardOutput == before.world.standardOutput &&
        after.world.standardError == before.world.standardError &&
        after.world.calls == [.alloc, .alloc, .alloc] &&
        after.heap.remaining == some 0 && after.heap.nextAddress == 5212 do
      throw (IO.userError "actual append_function lost caller metadata or sequential allocation effects")
    let added := (after.heap.blocks.filter (fun block => block.base ≥ 5120)).map fun block =>
      (block.base, block.size, block.alignment, block.live, block.owned)
    unless added == [(5120, 32, 8, true, false), (5152, 56, 8, true, false), (5208, 4, 4, true, false)] do
      throw (IO.userError "actual append_function allocation layout differs from locals/copy/endpoints")
  IO.println "actual full Void append_function: nonempty catalog returns0, count2 and three allocations retained" : IO Unit)

#eval (do
  for enabled in [false, true] do
    let before : State := { original with heap := {
      blocks := original.heap.blocks ++ sourceBlocks ++ [
        { base := 512, size := 4, alignment := 8, bytes := i32Bytes 0 },
        { base := 600, size := 4, alignment := 8, bytes := i32Bytes 0 },
        { base := 640, size := 16, alignment := 8, bytes := List.replicate 16 91 },
        { base := 720, size := 96, alignment := 8, bytes := List.replicate 96 165 }]
      nextAddress := 4240, remaining := some 60 } }
    unless (readRawSliceIndex extractedProgram before signatureType
        inputs.signature.address inputs.signature.length inputs.signature.id).toOption == some inputs.signature.entry do
      throw (IO.userError "original Void signature bytes do not represent its declaration")
    let block := terminalBlockCall (bodyContext inputs workspace (localsValue 512 1)) 1
      (input enabled).value 0 6
    let .done (.signed .i32 1) produced := evalExpr 900 extractedProgram before block
      | throw (IO.userError "original native Void body failed to produce one return event")
    unless (readNativeValue 64 extractedProgram produced.heap eventType 56).toOption == some (returnEvent false) &&
        (produced.heap.loadBytes 512 4).toOption == some (i32Bytes 0) do
      throw (IO.userError "Void production lost its return event or four-byte locals restore")
    let request : IRCatalogAppendProof.Model := {
      rowsAddress := 808, rowsLength := 1, countAddress := 600, countLength := 1
      capacity := 1, id := 0, parameters := 0, result := .Void, next := 0
      eventsAddress := 88, eventsLength := 2, resultAddress := if enabled then 120 else 0
      resultLength := if enabled then 2 else 0, hasResultTypes := enabled
      sourceCapacity := 2, eventCount := 1
      previous := fun _ => { id := 40, parameters := 0, result := .I32, tree := IRBuilderProof.emptyTree }
      events := fun _ => returnEvent false, annotations := fun _ => .Invalid
      kinds := fun _ => .StatementNode, arities := fun _ => 0, rules := fun _ => .NoChildren }
    let .done (.signed .i32 0) after := evalExpr 900 extractedProgram produced request.call
      | throw (IO.userError "actual public append rejected the original-byte-produced Void stream")
    unless (after.heap.loadBytes 600 4).toOption == some (i32Bytes 1) do
      throw (IO.userError "public append did not increment its original four-byte count")
    for block in sourceBlocks do
      unless (after.heap.loadBytes block.base block.size).toOption == some block.bytes do
        throw (IO.userError "producer-to-append changed original source/tree/token/signature bytes")
    unless after.locals == before.locals && after.world.calls == [.alloc, .alloc] && after.i32ArrayViews.isEmpty do
      throw (IO.userError "producer-to-append failed to restore caller bindings or world/views")
    unless after.local? 9 == some (.signed .i32 91) do
      throw (IO.userError "producer-to-append changed the original caller cell")
  IO.println "actual original Void fixtures: native producer feeds public append in both annotation modes" : IO Unit)

end IRBodyProductionVoidTests
