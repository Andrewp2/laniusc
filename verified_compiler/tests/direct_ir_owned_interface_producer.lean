import verified_compiler.tests.direct_ir_body_production
import verified_compiler.tests.direct_ir_owned_inputs_entry
import verified_compiler.tests.direct_ir_owned_queries_signature

namespace IRBodyOwnedProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs
open IRBodyProductionInputs IRBodyProductionProof IRBodyProductionScalar IREventStoreProof
open IRCatalogAppendProof IRCatalogConstructionProof

variable {origin : State} {input : Inputs} {declaration : Nat}

private theorem scalarSelectionUnique {expression : Surface.Expr} {reference : IRTypeRefProof.Reference}
    {left right : ReturnBody} (spelling : ScalarSpelling expression reference)
    (first : spelling.Selects left) (second : spelling.Selects right) : left = right := by
  cases first with
  | boolean flag => cases second; rfl
  | decimal spelled bound =>
      cases second with
      | decimal other otherBound =>
          have same := Option.some.inj (spelled.parsedDecimal.symm.trans other.parsedDecimal)
          rw [same]
  | negative spelled bound ordinary =>
      cases second with
      | negative other otherBound otherOrdinary =>
          have same := Option.some.inj (spelled.parsedDecimal.symm.trans other.parsedDecimal)
          rw [same]
      | minimum other otherBound minimum =>
          have same := Option.some.inj (spelled.parsedDecimal.symm.trans other.parsedDecimal)
          omega
  | minimum spelled bound minimum =>
      cases second with
      | negative other otherBound ordinary =>
          have same := Option.some.inj (spelled.parsedDecimal.symm.trans other.parsedDecimal)
          omega
      | minimum other otherBound otherMinimum => rfl

theorem naturalSelectionUnique (natural : NaturalBody input origin declaration)
    (first : natural.Selects left) (second : natural.Selects right) : left = right := by
  cases returns : natural.returns with
  | void optional result =>
      simp only [NaturalBody.Selects, returns] at first second
      exact first.trans second.symm
  | scalar root optional bound child kind payload scalar result distinct =>
      simp only [NaturalBody.Selects, returns] at first second
      rcases scalar with ⟨expression, reference, spelling, route, nativeSyntax, routeDistinct⟩
      exact scalarSelectionUnique spelling first second

private theorem naturalSelectionResult (natural : NaturalBody input origin declaration)
    (body : ReturnBody) (selected : natural.Selects body) : input.signature.result = body.result := by
  cases returns : natural.returns with
  | void optional result =>
      simp only [NaturalBody.Selects, returns] at selected
      rw [selected]
      exact result
  | scalar root optional bound child kind payload scalar result distinct =>
      simp only [NaturalBody.Selects, returns] at selected
      rcases scalar with ⟨expression, reference, spelling, route, nativeSyntax, routeDistinct⟩
      cases selected <;> simpa only [ReturnBody.result] using result

/-- The approved original-data producer view, retained without any execution,
    funding or successful-output premise. Only selected, present signatures
    require this witness; missing and skipped rows do not. -/
structure OriginalProducer (raw : RawInputs) (rawWorkspace : RawWorkspace)
    (row : AllocationRow) (origin : State) (region mutable : Nat → Prop)
    (catalog : Catalog) where
  input : Inputs
  workspace : Workspace
  inputValue : input.value = raw.value
  workspaceValue : workspace.value = rawWorkspace.value
  declaration : Nat
  declarationEq : (declaration : Int) = row.source.declaration.toInt
  signatureId : (input.signature.id : Int) = row.coreId.toInt
  nodeCount : (input.tree.nodeCount : Int) = raw.nodeCount.toInt
  tokenCount : (input.tokenCount : Int) = raw.tokenCount.toInt
  natural : NaturalBody input origin declaration
  native : NativeSignature input.signature origin.heap
  body : ReturnBody
  selected : natural.Selects body
  storage : natural.returns.WorkspaceStorage workspace
  output : Context origin
  zero : output.position = 0
  permissions : OutputPermissions output body.count
  events : workspace.events = output.value
  catalogValue : workspace.catalog = catalog.value
  tokenBound : input.tokenCount ≤ 89478484
  sourceCovered : ∀ address, sourceBytes input native address → region address
  mutableCovered : ∀ address,
    natural.returns.workspaceWrites workspace storage address ∨ permissions.writesFrom 0 address → mutable address
  outputApart : ∀ address, permissions.writesFrom 0 address →
    ¬natural.returns.workspaceWrites workspace storage address

def OriginalProducer.allowed
    (original : OriginalProducer raw rawWorkspace row origin region mutable catalog) : Nat → Prop :=
  fun address => original.natural.returns.workspaceWrites original.workspace original.storage address ∨
    original.permissions.writesFrom 0 address

theorem OriginalProducer.call_eq
    (original : OriginalProducer raw rawWorkspace row origin region mutable catalog) :
    producerCall original.input original.workspace original.declaration original.input.tree.nodeCount =
      .call producerSource.id [.value raw.value, .value rawWorkspace.value,
        .value (.signed .i32 row.source.declaration.toInt),
        .value (.signed .i32 row.coreId.toInt), .value (.signed .i32 raw.nodeCount.toInt)] := by
  simp only [producerCall, original.inputValue, original.workspaceValue, original.declarationEq,
    original.signatureId, original.nodeCount]

theorem OriginalProducer.result
    (original : OriginalProducer raw rawWorkspace row origin region mutable catalog) :
    original.input.signature.result = original.body.result :=
  naturalSelectionResult original.natural original.body original.selected

def OriginalProducer.permissionsFor
    (original : OriginalProducer raw rawWorkspace row origin region mutable catalog)
    (body : ReturnBody) (selected : original.natural.Selects body) :
    OutputPermissions original.output body.count := by
  have same := naturalSelectionUnique original.natural selected original.selected
  subst body
  exact original.permissions

theorem OriginalProducer.inputApart
    (original : OriginalProducer raw rawWorkspace row origin region mutable catalog)
    (apart : ∀ address, region address → ¬mutable address) :
    InputApart original.input original.allowed := {
  nodes := fun index base inside location address lower upper changed =>
    apart address (original.sourceCovered address
      (Or.inl (Or.inl ⟨index, base, inside, location, lower, upper⟩)))
      (original.mutableCovered address changed)
  children := fun index base inside location address lower upper changed =>
    apart address (original.sourceCovered address
      (Or.inl (Or.inr (Or.inl ⟨index, base, inside, location, lower, upper⟩))))
      (original.mutableCovered address changed)
  tokens := fun pointer length index base descriptor inside location address lower upper changed =>
    apart address (original.sourceCovered address
      (Or.inl (Or.inr (Or.inr (Or.inl
        ⟨pointer, length, index, base, descriptor, inside, location, lower, upper⟩)))))
      (original.mutableCovered address changed)
  source := fun pointer length descriptor index inside address lower upper changed =>
    apart address (original.sourceCovered address
      (Or.inl (Or.inr (Or.inr (Or.inr
        ⟨pointer, length, index, descriptor, inside, lower, upper⟩)))))
      (original.mutableCovered address changed) }

def OriginalProducer.request
    (original : OriginalProducer raw rawWorkspace row before region mutable catalog) : Model :=
  streamRequest original.output (Int32.ofNat original.input.signature.id) original.input.signature.result
    original.body (fun index => if index = 0 then .Invalid else original.input.signature.result)

/-- Retain the actual accepted callee's effect once, without re-exporting its
    internal allocation attempts. The caller projects this on failure. -/
def ProducerObservation
    (original : OriginalProducer raw rawWorkspace row before region mutable catalog)
    (next : Int32) (previous : Nat → PreviousRow) (result : Int) (after : State) : Prop :=
  FreshCellFrame before after ∧ after.locals = before.locals ∧ after.i32ArrayViews = before.i32ArrayViews ∧
  (consumeBudget before.heap.remaining (localBytes original.input.tokenCount) = none →
    result = -1 ∧ after.heap = before.heap ∧ after.world = World.record before.world .alloc ∧
      Invariant catalog next previous after) ∧
  (∀ budget, consumeBudget before.heap.remaining (localBytes original.input.tokenCount) = some budget →
    let localHeap := (before.heap.allocatedBytes (localBytes original.input.tokenCount) 8 budget).borrowBlock
      (before.heap.allocationAddress 8)
    result = (by classical exact if (catalog.model next previous original.request).Success localHeap then 0 else -1) ∧
    FunctionInsertion before original.body original.output original.permissions original.input.signature.result
      original.allowed (before.heap.allocationAddress 8) localHeap catalog next previous original.request before after ∧
    ((catalog.model next previous original.request).Success localHeap →
      StoredTerminalRepresentation after.heap (catalog.rowBase next.toInt.toNat)
        (Int32.ofNat original.input.signature.id)
        (localHeap.allocationAddress 8 + original.body.count * 40 - 8)
        (localHeap.allocationAddress 8 + original.body.count * 56 - 8)
        (localHeap.allocationAddress 8 + original.body.count * 56)
        original.body.count original.output.enabled original.body.coreStatement)) ∧
  (∀ budget first second,
    consumeBudget before.heap.remaining (localBytes original.input.tokenCount) = some budget →
    consumeBudget budget (original.body.count * 56) = some first →
    consumeBudget first (original.body.count * 4) = some second →
    next.toInt < catalog.capacity.toInt →
    (∀ index, index < next.toInt.toNat →
      (previous index).id.toInt ≠ (Int32.ofNat original.input.signature.id).toInt) → result = 0)

private theorem catalogFootprintCovered (invariant : Invariant catalog next previous before)
    (room : next.toInt < catalog.capacity.toInt)
    (changed : (catalog.model next previous request).footprint address) :
    catalog.memory ≤ address ∧ address < catalog.memory + catalog.bytes := by
  have strict : next.toInt.toNat < catalog.length := by
    have nonnegative := invariant.bounds.1
    dsimp only [Catalog.length]
    omega
  rcases changed with rowChanged | countChanged
  · change catalog.memory + catalog.length * 96 + 8 - (next.toInt.toNat + 1) * 96 ≤ address ∧
      address < catalog.memory + catalog.length * 96 + 8 - (next.toInt.toNat + 1) * 96 + 96 at rowChanged
    rw [catalog.rowAddress strict] at rowChanged
    dsimp only [Catalog.rowBase, Catalog.bytes] at *
    omega
  · change catalog.memory ≤ address ∧ address < catalog.memory + 4 at countChanged
    dsimp only [Catalog.bytes]
    omega

theorem actualOriginalProducer
    (original : OriginalProducer raw rawWorkspace row before region mutable catalog)
    (invariant : Invariant catalog next previous before)
    (protectedApart : ∀ address, region address → ¬mutable address)
    (workspaceApart : ∀ address, catalog.memory ≤ address → address < catalog.memory + catalog.bytes → ¬mutable address)
    (catalogApart : ∀ address, region address → ¬(catalog.memory ≤ address ∧ address < catalog.memory + catalog.bytes))
    (localFits : before.heap.allocationAddress 8 + localBytes original.input.tokenCount < 2 ^ 64)
    (copyFits : ∀ budget, consumeBudget before.heap.remaining (localBytes original.input.tokenCount) = some budget →
      ((before.heap.allocatedBytes (localBytes original.input.tokenCount) 8 budget).borrowBlock
        (before.heap.allocationAddress 8)).allocationAddress 8 + original.body.count * 56 < 2 ^ 64) :
    ∃ result after, RunsExpr extractedProgram before
      (.call producerSource.id [.value raw.value, .value rawWorkspace.value,
        .value (.signed .i32 row.source.declaration.toInt), .value (.signed .i32 row.coreId.toInt),
        .value (.signed .i32 raw.nodeCount.toInt)]) (.signed .i32 result) after ∧
      ProducerObservation original next previous result after := by
  obtain ⟨body, selected, result, after, run, frame, locals, views, meaning, readonly,
    signature, exhausted, funded, enough⟩ := actualNaturalFunction
      original.input original.workspace original.declaration original.natural original.native original.storage
      original.output original.zero original.permissionsFor original.events original.catalogValue invariant
      original.tokenBound localFits
      (fun body selected budget available => by
        have same := naturalSelectionUnique original.natural selected original.selected
        subst body
        exact copyFits budget available)
      (fun body selected => by
        have same := naturalSelectionUnique original.natural selected original.selected
        subst body
        exact original.inputApart protectedApart)
      (fun body selected address lower upper changed => by
        have same := naturalSelectionUnique original.natural selected original.selected
        subst body
        exact protectedApart address (original.sourceCovered address (Or.inr ⟨lower, upper⟩))
          (original.mutableCovered address changed))
      (fun body selected => by
        have same := naturalSelectionUnique original.natural selected original.selected
        subst body
        exact original.outputApart)
      (fun body selected address lower upper changed => by
        have same := naturalSelectionUnique original.natural selected original.selected
        subst body
        exact workspaceApart address lower upper (original.mutableCovered address changed))
      (fun body selected address source room changed => catalogApart address
        (original.sourceCovered address source) (catalogFootprintCovered invariant room changed))
  have same := naturalSelectionUnique original.natural selected original.selected
  subst body
  refine ⟨result, after, ?_, frame, locals, views, exhausted, ?_, enough⟩
  · simpa only [original.call_eq] using run
  · intro budget available
    obtain ⟨answer, insertion, world, stored⟩ := funded budget available
    exact ⟨answer, insertion, stored⟩

#print axioms actualOriginalProducer

end IRBodyOwnedProof
