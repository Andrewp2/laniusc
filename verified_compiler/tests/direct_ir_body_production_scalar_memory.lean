import verified_compiler.tests.direct_ir_body_production_scalar_domain
import verified_compiler.tests.direct_ir_body_production_scalar_arena
import Lanius.Semantics.NativeSnapshotFrame

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

variable {before after : State}

/-- Address separation of original syntax and source, independent of contents
    or future queries. Spare descriptors need not be decoded or backed. -/
structure InputApart (input : Inputs) (allowed : Nat → Prop) : Prop where
  nodes : ∀ index base, index < input.tree.nodeCount →
    rawSliceElementAddress? extractedProgram nodeType input.tree.nodes index = .ok base →
    ∀ address, base ≤ address → address < base + 40 → ¬allowed address
  children : ∀ index base, index < input.tree.childCount →
    rawSliceElementAddress? extractedProgram childType input.tree.children index = .ok base →
    ∀ address, base ≤ address → address < base + 24 → ¬allowed address
  tokens : ∀ pointer length index base,
    input.tokens = .rawSlice tokenType pointer length → index < input.tokenCount →
    rawSliceElementAddress? extractedProgram tokenType pointer index = .ok base →
    ∀ address, base ≤ address → address < base + 24 → ¬allowed address
  source : ∀ pointer length, input.source = .rawSlice (.scalar (.signed .i32)) pointer length →
    ∀ index, index < input.sourceLength →
    ∀ address, pointer + index * 4 ≤ address → address < pointer + index * 4 + 4 → ¬allowed address

/-- Narrow the legitimate write set without reconstructing original syntax
    or requiring any read from spare storage. -/
theorem InputApart.mono (apart : InputApart input allowed)
    (subset : ∀ address, smaller address → allowed address) : InputApart input smaller := {
  nodes := fun index base inside location address lower upper selected =>
    apart.nodes index base inside location address lower upper (subset address selected)
  children := fun index base inside location address lower upper selected =>
    apart.children index base inside location address lower upper (subset address selected)
  tokens := fun pointer length index base descriptor inside location address lower upper selected =>
    apart.tokens pointer length index base descriptor inside location address lower upper (subset address selected)
  source := fun pointer length descriptor index inside address lower upper selected =>
    apart.source pointer length descriptor index inside address lower upper (subset address selected) }

private theorem keepWord (write : HeapWritesOn before.heap after.heap allowed)
    (bound : index < length)
    (apart : ∀ address, pointer + index * 4 ≤ address → address < pointer + index * 4 + 4 → ¬allowed address)
    (read : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) pointer length index = .ok value) :
    readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) pointer length index = .ok value := by
  simp only [readRawSliceIndex, Nat.not_le_of_lt bound, ↓reduceIte] at read ⊢
  change readNativeValue 64 extractedProgram before.heap (.scalar (.signed .i32)) (pointer + index * 4) = .ok value at read
  change readNativeValue 64 extractedProgram after.heap (.scalar (.signed .i32)) (pointer + index * 4) = .ok value
  cases loaded : before.heap.loadBytes (pointer + index * 4) 4 with
  | error reason =>
      simp only [readNativeValue, loadNatLE, loaded] at read
      change (Except.error reason : Except Trap Value) = .ok value at read
      cases read
  | ok bytes =>
      have retained := write.loadBytes loaded (fun offset inside =>
        apart (pointer + index * 4 + offset) (Nat.le_add_right _ _)
          (Nat.add_lt_add_left inside _))
      simpa only [readNativeValue, loadNatLE, loaded, retained] using read

def OriginalToken.afterFootprint (token : OriginalToken input before index text expected)
    (write : HeapWritesOn before.heap after.heap allowed) (apart : InputApart input allowed) :
    OriginalToken input after index text expected := {
  token with
  toNativeToken := {
    token.toNativeToken with
    snapshot := token.snapshot.afterFootprint write (apart.tokens _ _ _ _ token.descriptor token.inside token.location) }
  words := fun offset bound => keepWord write
    (by have := token.span; have := token.sourceBound; omega)
    (apart.source _ _ token.source _ (by have := token.span; omega)) (token.words offset bound) }

theorem OriginalScalar.afterFootprint (original : OriginalScalar input before root expression route)
    (write : HeapWritesOn before.heap after.heap allowed) (apart : InputApart input allowed) :
    OriginalScalar input after root expression route := by
  let node {index : Nat} (value : NativeNode input.tree before.heap index) : NativeNode input.tree after.heap index :=
    { value with snapshot := value.snapshot.afterFootprint write (apart.nodes _ _ value.inside value.location) }
  let child {index : Nat} (value : NativeChild input.tree before.heap index) : NativeChild input.tree after.heap index :=
    { value with snapshot := value.snapshot.afterFootprint write (apart.children _ _ value.inside value.location) }
  induction original with
  | boolean value production count token kind payload spelling =>
      exact .boolean (node value) production count (child token) kind payload (spelling.afterFootprint write apart)
  | integer value production count token kind payload spelling =>
      exact .integer (node value) production count (child token) kind payload (spelling.afterFootprint write apart)
  | negative value production count operand kind payload minus minusKind minusPayload minusSpelling original ih =>
      exact .negative (node value) production count (child operand) kind payload (child minus) minusKind minusPayload
        (minusSpelling.afterFootprint write apart) ih
  | wrapper value production slot selected inside operand kind payload original ih =>
      exact .wrapper (node value) production slot selected inside (child operand) kind payload ih
  | binaryEnd value count left leftKind leftPayload tail tailKind tailPayload ending production original ih =>
      exact .binaryEnd (node value) count (child left) leftKind leftPayload (child tail) tailKind tailPayload
        (node ending) production ih

def NaturalScalar.afterFootprint (scalar : NaturalScalar input before root)
    (write : HeapWritesOn before.heap after.heap allowed) (apart : InputApart input allowed) :
    NaturalScalar input after root := { scalar with «syntax» := scalar.syntax.afterFootprint write apart }

/-- Initial writable expression/cache geometry. Old count, node and code
    values are unused: the real extractor resets count and clears live codes. -/
structure ScalarStorage (workspace : Workspace) (before : State) (slots : Nat) where
  arena : Arena
  arenaValue : workspace.arena = arena.value
  positive : 0 < slots
  bound : slots ≤ arena.capacity
  bases : Nat → Nat
  locations : ∀ index, index < slots →
    rawSliceElementAddress? extractedProgram expressionNodeType arena.nodes index = .ok (bases index)
  nodeRoom : ∀ index, index < slots → before.heap.Readable (bases index) 48
  countRoom : before.heap.Readable arena.count 4
  codes : Nat
  depths : Nat
  codesValue : workspace.codes = .rawSlice (.scalar (.signed .i32)) codes arena.capacity
  depthsValue : workspace.depths = .rawSlice (.scalar (.signed .i32)) depths arena.capacity
  codesRoom : before.heap.Readable codes (slots * 4)
  depthsRoom : before.heap.Readable depths (slots * 4)
  countCodes : arena.count + 4 ≤ codes ∨ codes + slots * 4 ≤ arena.count
  countDepths : arena.count + 4 ≤ depths ∨ depths + slots * 4 ≤ arena.count
  codeDepths : codes + slots * 4 ≤ depths ∨ depths + slots * 4 ≤ codes
  nodeCount : ∀ index, index < slots → bases index + 48 ≤ arena.count ∨ arena.count + 4 ≤ bases index
  nodeCodes : ∀ index, index < slots → bases index + 48 ≤ codes ∨ codes + slots * 4 ≤ bases index
  nodeDepths : ∀ index, index < slots → bases index + 48 ≤ depths ∨ depths + slots * 4 ≤ bases index

def ScalarStorage.afterReads (storage : ScalarStorage workspace before slots) (reads : HeapReads before.heap after.heap) :
    ScalarStorage workspace after slots := {
  storage with
  nodeRoom := fun index bound => reads.readable (storage.nodeRoom index bound)
  countRoom := reads.readable storage.countRoom
  codesRoom := reads.readable storage.codesRoom
  depthsRoom := reads.readable storage.depthsRoom }

def ScalarStorage.afterFootprint (storage : ScalarStorage workspace before slots)
    (write : HeapWritesOn before.heap after.heap allowed) :
    ScalarStorage workspace after slots := {
  storage with
  nodeRoom := fun index bound => write.readable _ _ (storage.nodeRoom index bound)
  countRoom := write.readable _ _ storage.countRoom
  codesRoom := write.readable _ _ storage.codesRoom
  depthsRoom := write.readable _ _ storage.depthsRoom }

def ScalarStorage.writes (storage : ScalarStorage workspace before slots) (address : Nat) : Prop :=
  (storage.arena.count ≤ address ∧ address < storage.arena.count + 4) ∨
  (∃ index, index < slots ∧ storage.bases index ≤ address ∧ address < storage.bases index + 48) ∨
  (storage.codes ≤ address ∧ address < storage.codes + slots * 4) ∨
  (storage.depths ≤ address ∧ address < storage.depths + slots * 4)

private theorem nominalSlotOrder (element : Ty)
    (nominal : match element with | .structure _ | .enumeration _ => True | _ => False)
    (layout : NativeLayout.valueWords? extractedProgram element = some words) (positive : 0 < words)
    (first : rawSliceElementAddress? extractedProgram element pointer left = .ok firstBase)
    (second : rawSliceElementAddress? extractedProgram element pointer right = .ok secondBase)
    (less : left < right) : secondBase + words * 8 ≤ firstBase := by
  have rule (index : Nat) : rawSliceElementAddress? extractedProgram element pointer index =
      match NativeLayout.elementBase? pointer index words with
      | none => .error .rawMemoryBounds | some base => .ok base := by
    cases element <;> try exact False.elim nominal
    all_goals
      rw [rawSliceElementAddress?, layout]
      cases base : NativeLayout.elementBase? pointer index words <;>
        simp only [base, Pure.pure, Except.pure]
  have located (index base : Nat)
      (selected : rawSliceElementAddress? extractedProgram element pointer index = .ok base) :
      pointer = base + (index * words + words - 1) * 8 := by
    rw [rule] at selected
    have found : NativeLayout.elementBase? pointer index words = some base := by
      cases address : NativeLayout.elementBase? pointer index words with
      | none => simp only [address, reduceCtorEq] at selected
      | some actual =>
          have equal : actual = base := by simpa only [address, Except.ok.injEq] using selected
          exact congrArg some equal
    have lower : (index * words + words - 1) * 8 ≤ pointer := by
      by_cases lower : (index * words + words - 1) * 8 ≤ pointer
      · exact lower
      · have tooLow : pointer < (index * words + words - 1) * 8 := by omega
        simp [NativeLayout.elementBase?, NativeLayout.wordBytes, tooLow] at found
    have address : NativeLayout.elementBase? pointer index words =
        some (pointer - (index * words + words - 1) * 8) := by
      simp [NativeLayout.elementBase?, NativeLayout.wordBytes, Nat.ne_of_gt positive, Nat.not_lt.mpr lower]
    rw [address] at found
    have equal := Option.some.inj found
    omega
  have leftAddress := located left firstBase first
  have rightAddress := located right secondBase second
  have displacement (index : Nat) : (index * words + words - 1) * 8 + 8 =
      index * words * 8 + words * 8 := by
    have lower : 1 ≤ index * words + words := by omega
    calc
      (index * words + words - 1) * 8 + 8 = (index * words + words - 1 + 1) * 8 :=
        (Nat.add_mul _ 1 8).symm
      _ = (index * words + words) * 8 := congrArg (fun value : Nat => value * 8) (Nat.sub_add_cancel lower)
      _ = index * words * 8 + words * 8 := Nat.add_mul _ _ _
  have leftDisplacement := displacement left
  have rightDisplacement := displacement right
  have step : left * words + words ≤ right * words := by
    simpa only [Nat.succ_mul] using Nat.mul_le_mul_right words (Nat.succ_le_of_lt less)
  have scaled : left * words * 8 + words * 8 ≤ right * words * 8 := by
    calc
      left * words * 8 + words * 8 = (left * words + words) * 8 := (Nat.add_mul _ _ _).symm
      _ ≤ right * words * 8 := Nat.mul_le_mul_right 8 step
  have ordered : (left * words + words - 1) * 8 + words * 8 ≤ (right * words + words - 1) * 8 := by
    apply (Nat.add_le_add_iff_right (n := 8)).mp
    calc
      ((left * words + words - 1) * 8 + words * 8) + 8 =
          ((left * words + words - 1) * 8 + 8) + words * 8 := Nat.add_right_comm _ _ _
      _ = (left * words * 8 + words * 8) + words * 8 := congrArg (fun value : Nat => value + words * 8) leftDisplacement
      _ ≤ right * words * 8 + words * 8 := Nat.add_le_add_right scaled _
      _ = (right * words + words - 1) * 8 + 8 := rightDisplacement.symm
  apply (Nat.add_le_add_iff_right (n := (left * words + words - 1) * 8)).mp
  calc
    (secondBase + words * 8) + (left * words + words - 1) * 8 =
        (secondBase + (left * words + words - 1) * 8) + words * 8 := Nat.add_right_comm _ _ _
    _ = secondBase + ((left * words + words - 1) * 8 + words * 8) := Nat.add_assoc _ _ _
    _ ≤ secondBase + (right * words + words - 1) * 8 := Nat.add_le_add_left ordered _
    _ = pointer := rightAddress.symm
    _ = firstBase + (left * words + words - 1) * 8 := leftAddress

private theorem nominalSlotSeparation (element : Ty)
    (nominal : match element with | .structure _ | .enumeration _ => True | _ => False)
    (layout : NativeLayout.valueWords? extractedProgram element = some words) (positive : 0 < words)
    (first : rawSliceElementAddress? extractedProgram element pointer left = .ok firstBase)
    (second : rawSliceElementAddress? extractedProgram element pointer right = .ok secondBase)
    (different : left ≠ right) : firstBase + words * 8 ≤ secondBase ∨ secondBase + words * 8 ≤ firstBase := by
  rcases Nat.lt_or_gt_of_ne different with less | greater
  · exact Or.inr (nominalSlotOrder element nominal layout positive first second less)
  · exact Or.inl (nominalSlotOrder element nominal layout positive second first greater)

/-- Real backward layout makes distinct selected arena nodes disjoint. -/
theorem ScalarStorage.nodeSeparation (storage : ScalarStorage workspace state slots)
    (left right : Nat) (leftInside : left < slots) (rightInside : right < slots) (different : left ≠ right) :
    storage.bases left + 48 ≤ storage.bases right ∨ storage.bases right + 48 ≤ storage.bases left :=
  nominalSlotSeparation expressionNodeType (by change True; trivial) (words := 6) (by decide +kernel)
    (by decide) (storage.locations left leftInside) (storage.locations right rightInside) different

/-- One original output descriptor and permissions for exactly the used
    indices. Disabled annotations grant no type reads or writes. -/
structure OutputPermissions (output : IREventStoreProof.Context before) (used : Nat) where
  bound : used ≤ output.capacity
  typeBound : output.enabled = true → used ≤ output.typesLength
  eventBases : Nat → Nat
  typeBases : Nat → Nat
  eventLocation : ∀ index, index < used → rawSliceElementAddress? extractedProgram
    IREventStoreProof.eventType output.events index = .ok (eventBases index)
  typeLocation : output.enabled = true → ∀ index, index < used → rawSliceElementAddress? extractedProgram
    IREventStoreProof.referenceType output.types index = .ok (typeBases index)
  eventRoom : ∀ index, index < used → before.heap.Readable (eventBases index) 40
  typeRoom : output.enabled = true → ∀ index, index < used → before.heap.Readable (typeBases index) 16
  planes : output.enabled = true → ∀ event type, event < used → type < used →
    eventBases event + 40 ≤ typeBases type ∨ typeBases type + 16 ≤ eventBases event

theorem OutputPermissions.eventOrder {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used)
    (left right : Nat) (leftInside : left < used) (rightInside : right < used) (less : left < right) :
    permissions.eventBases right + 40 ≤ permissions.eventBases left :=
  nominalSlotOrder IREventStoreProof.eventType (by change True; trivial) (words := 5) (by decide +kernel)
    (by decide) (permissions.eventLocation left leftInside) (permissions.eventLocation right rightInside) less

theorem OutputPermissions.typeOrder {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used) (enabled : output.enabled = true)
    (left right : Nat) (leftInside : left < used) (rightInside : right < used) (less : left < right) :
    permissions.typeBases right + 16 ≤ permissions.typeBases left :=
  nominalSlotOrder IREventStoreProof.referenceType (by change True; trivial) (words := 2) (by decide +kernel)
    (by decide) (permissions.typeLocation enabled left leftInside)
    (permissions.typeLocation enabled right rightInside) less

theorem OutputPermissions.eventSeparation {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used)
    (left right : Nat) (leftInside : left < used) (rightInside : right < used) (different : left ≠ right) :
    permissions.eventBases left + 40 ≤ permissions.eventBases right ∨
      permissions.eventBases right + 40 ≤ permissions.eventBases left :=
  nominalSlotSeparation IREventStoreProof.eventType (by change True; trivial) (words := 5) (by decide +kernel)
    (by decide) (permissions.eventLocation left leftInside) (permissions.eventLocation right rightInside) different

theorem OutputPermissions.typeSeparation {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used) (enabled : output.enabled = true)
    (left right : Nat) (leftInside : left < used) (rightInside : right < used) (different : left ≠ right) :
    permissions.typeBases left + 16 ≤ permissions.typeBases right ∨
      permissions.typeBases right + 16 ≤ permissions.typeBases left :=
  nominalSlotSeparation IREventStoreProof.referenceType (by change True; trivial) (words := 2) (by decide +kernel)
    (by decide) (permissions.typeLocation enabled left leftInside)
    (permissions.typeLocation enabled right rightInside) different

/-- Fresh locals allocation retains the same output descriptor and permissions. -/
def OutputPermissions.afterReads {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used)
    (reads : HeapReads before.heap after.heap) :
    OutputPermissions ({ output with
      eventRoom := reads.readable output.eventRoom
      typeRoom := fun enabled => reads.readable (output.typeRoom enabled) } : IREventStoreProof.Context after) used := {
  permissions with
  eventRoom := fun index bound => reads.readable (permissions.eventRoom index bound)
  typeRoom := fun enabled index bound => reads.readable (permissions.typeRoom enabled index bound) }

/-- A real header/workspace write retains permissions, without claiming
    that arbitrary old mutable bytes survive the write. -/
def OutputPermissions.afterFootprint {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used)
    (write : HeapWritesOn before.heap after.heap allowed) :
    OutputPermissions ({ output with
      eventRoom := write.readable _ _ output.eventRoom
      typeRoom := fun enabled => write.readable _ _ (output.typeRoom enabled) } : IREventStoreProof.Context after) used := {
  permissions with
  eventRoom := fun index bound => write.readable _ _ (permissions.eventRoom index bound)
  typeRoom := fun enabled index bound => write.readable _ _ (permissions.typeRoom enabled index bound) }

/-- Reached contexts are derived from original permissions and the actual
    phase's preservation of readable storage, not supplied as producer inputs. -/
def OutputPermissions.slot {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used)
    (index : Nat) (inside : index < used)
    (retained : ∀ pointer count, before.heap.Readable pointer count → after.heap.Readable pointer count) :
    IREventStoreProof.Context after := {
  position := index, capacity := output.capacity, events := output.events, types := output.types
  typesLength := output.typesLength, enabled := output.enabled
  eventBase := permissions.eventBases index, typeBase := permissions.typeBases index
  bound := Nat.lt_of_lt_of_le inside permissions.bound, fits := output.fits
  eventLocation := permissions.eventLocation index inside
  typeBound := fun enabled => Nat.lt_of_lt_of_le inside (permissions.typeBound enabled)
  typeLocation := fun enabled => permissions.typeLocation enabled index inside
  eventRoom := retained _ _ (permissions.eventRoom index inside)
  typeRoom := fun enabled => retained _ _ (permissions.typeRoom enabled index inside)
  separate := fun enabled => permissions.planes enabled index index inside inside }

theorem OutputPermissions.slotValue {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used)
    (index : Nat) (inside : index < used)
    (retained : ∀ pointer count, before.heap.Readable pointer count → after.heap.Readable pointer count) :
    (permissions.slot index inside retained).value = output.value := rfl

def OutputPermissions.writesFrom {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used) (first address : Nat) : Prop :=
  ∃ index, first ≤ index ∧ index < used ∧
    ((permissions.eventBases index ≤ address ∧ address < permissions.eventBases index + 40) ∨
      (output.enabled = true ∧ permissions.typeBases index ≤ address ∧ address < permissions.typeBases index + 16))

#print axioms OriginalToken.afterFootprint
#print axioms InputApart.mono
#print axioms OriginalScalar.afterFootprint
#print axioms NaturalScalar.afterFootprint
#print axioms OutputPermissions.afterReads
#print axioms OutputPermissions.afterFootprint
#print axioms OutputPermissions.slotValue
#print axioms ScalarStorage.nodeSeparation
#print axioms OutputPermissions.eventSeparation
#print axioms OutputPermissions.typeSeparation
#print axioms OutputPermissions.eventOrder
#print axioms OutputPermissions.typeOrder

end IRBodyProductionScalar
