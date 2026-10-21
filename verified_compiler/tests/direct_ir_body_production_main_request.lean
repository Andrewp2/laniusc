import verified_compiler.tests.direct_ir_body_production_main_stream
import verified_compiler.tests.direct_ir_body_production_scalar_memory
import verified_compiler.tests.direct_ir_catalog_construction_call

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IREventStoreProof IREventWriteProof IRTypeRefProof IRShapeProof
open IRCatalogAppendProof IRCatalogConstructionProof IREventCodecProof
open IRBodyProductionScalar

/-- Classification is fixed by the finite source-selected stream, not an
    assumed successful shape query. -/
theorem ReturnBody.classified (body : ReturnBody) (inside : index < body.count) :
    Classifies (body.event index)
      (shapeValue (kindValue (body.kind index)) (body.arity index) (ruleValue (body.rule index))) := by
  by_cases first : index = 0
  · subst index
    cases body <;> apply Classifies.fixed <;>
      simp [ReturnBody.event, ReturnBody.kind, ReturnBody.arity, ReturnBody.rule,
        fixedShapes, returnEvent]
  · cases body with
    | void => simp only [ReturnBody.count] at inside; omega
    | boolean flag =>
      have last : index = 1 := by simp only [ReturnBody.count] at inside; omega
      subst index
      apply Classifies.payload (payload := .boolean flag)
      simp [ReturnBody.event, ReturnBody.leaf, ReturnBody.kind, ReturnBody.arity,
        ReturnBody.rule, payloadShapes, IREventStoreProof.boolean]
    | integer value =>
      have last : index = 1 := by simp only [ReturnBody.count] at inside; omega
      subst index
      apply Classifies.payload (payload := .signed .i32 value.toInt)
      simp [ReturnBody.event, ReturnBody.leaf, ReturnBody.kind, ReturnBody.arity,
        ReturnBody.rule, payloadShapes, IREventStoreProof.integer]
    | negative value =>
      have last : index = 1 ∨ index = 2 := by simp only [ReturnBody.count] at inside; omega
      rcases last with rfl | rfl
      · apply Classifies.fixed
        simp [ReturnBody.event, ReturnBody.kind, ReturnBody.arity, ReturnBody.rule,
          fixedShapes, negateEvent]
      · apply Classifies.payload (payload := .signed .i32 value.toInt)
        simp [ReturnBody.event, ReturnBody.leaf, ReturnBody.kind, ReturnBody.arity,
          ReturnBody.rule, payloadShapes, IREventStoreProof.integer]

private theorem nullaryRepresentation (event : Value) (member : event ∈ nullaryEvents) :
    ∃ first second third flag kind sliceKind pointer length,
      pointer < 2 ^ 64 ∧ length < 2 ^ 64 ∧
        event ∈ representedEvents first second third flag kind sliceKind pointer length := by
  exact ⟨0, 0, 0, false, .Invalid, .I32Slice, 0, 0, by decide, by decide,
    List.mem_append_left _ (List.mem_append_left _ member)⟩

/-- Native codec coverage follows from the actual payload constructors; no
    successful encoder or decoded destination is part of the domain. -/
theorem ReturnBody.represented (body : ReturnBody) (inside : index < body.count) :
    ∃ first second third flag kind sliceKind pointer length,
      pointer < 2 ^ 64 ∧ length < 2 ^ 64 ∧
        body.event index ∈ representedEvents first second third flag kind sliceKind pointer length := by
  by_cases first : index = 0
  · subst index
    apply nullaryRepresentation
    cases body <;> dsimp only [ReturnBody.event]
    all_goals
      apply List.mem_filterMap.mpr
      first
        | exact ⟨(match returnEvent false with | .enumeration _ ordinal _ => ordinal | _ => 0),
            List.mem_range.mpr (by decide +kernel), rfl⟩
        | exact ⟨(match returnEvent true with | .enumeration _ ordinal _ => ordinal | _ => 0),
            List.mem_range.mpr (by decide +kernel), rfl⟩
  · cases body with
    | void => simp only [ReturnBody.count] at inside; omega
    | boolean flag =>
      have last : index = 1 := by simp only [ReturnBody.count] at inside; omega
      subst index
      refine ⟨0, 0, 0, flag, .Invalid, .I32Slice, 0, 0, by decide, by decide, ?_⟩
      apply List.mem_append_left
      apply List.mem_append_right
      simp [ReturnBody.event, ReturnBody.leaf, scalarEvents]
    | integer value =>
      have last : index = 1 := by simp only [ReturnBody.count] at inside; omega
      subst index
      refine ⟨value, 0, 0, false, .Invalid, .I32Slice, 0, 0, by decide, by decide, ?_⟩
      apply List.mem_append_left
      apply List.mem_append_right
      simp [ReturnBody.event, ReturnBody.leaf, scalarEvents]
    | negative value =>
      have last : index = 1 ∨ index = 2 := by simp only [ReturnBody.count] at inside; omega
      rcases last with rfl | rfl
      · apply nullaryRepresentation
        change negateEvent ∈ nullaryEvents
        apply List.mem_filterMap.mpr
        refine ⟨(match negateEvent with | .enumeration _ ordinal _ => ordinal | _ => 0),
          List.mem_range.mpr (by decide +kernel), rfl⟩
      · refine ⟨value, 0, 0, false, .Invalid, .I32Slice, 0, 0, by decide, by decide, ?_⟩
        apply List.mem_append_left
        apply List.mem_append_right
        simp [ReturnBody.event, ReturnBody.leaf, scalarEvents]

/-- The real producer's reads are the only phase evidence consumed here.
    Shape, codec coverage and canonicality are derived from the same body. -/
theorem streamRequestEvidence {original storage : State} {phase : Heap}
    {catalog : Catalog} {next : Int32} {previous : Nat → PreviousRow}
    (body : ReturnBody) (output : Context original)
    (id : Int32) (result : Reference) (annotations : Nat → Reference)
    (events : ∀ index, index < body.count → readRawSliceIndex extractedProgram storage
      IREventStoreProof.eventType output.events output.capacity index = .ok (body.event index))
    (types : output.enabled = true → ∀ index, index < body.count →
      readRawSliceIndex extractedProgram storage IREventStoreProof.referenceType
        output.types output.typesLength index = .ok (referenceValue (annotations index)))
    (fits : phase.allocationAddress 8 + body.count * 56 < 2 ^ 64) :
    RequestEvidence (catalog.model next previous (streamRequest output id result body annotations)) storage phase := by
  have count : (catalog.model next previous (streamRequest output id result body annotations)).request = body.count := by
    change (Int32.ofNat body.count).toInt.toNat = body.count
    cases body <;> rfl
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · intro _ index inside
    exact events index (by simpa only [count] using inside)
  · intro _ index inside
    exact body.classified (by simpa only [count] using inside)
  · intro _ index inside
    exact body.represented (by simpa only [count] using inside)
  · intro _ enabled index inside
    exact types enabled index (by simpa only [count] using inside)
  · intro _
    simpa only [count] using fits

/-- The producer's actual native snapshots and original used-slot geometry
    discharge the single catalog evidence interface in either annotation mode. -/
theorem streamSnapshotEvidence {original storage : State} {phase : Heap}
    {catalog : Catalog} {next : Int32} {previous : Nat → PreviousRow}
    (body : ReturnBody) (output : Context original)
    (permissions : OutputPermissions output body.count)
    (id : Int32) (result : Reference) (annotations : Nat → Reference)
    (events : ∀ index, index < body.count → NativeSnapshot 64 extractedProgram storage.heap
      IREventStoreProof.eventType (permissions.eventBases index) (body.event index) 40)
    (types : output.enabled = true → ∀ index, index < body.count →
      NativeSnapshot 64 extractedProgram storage.heap IREventStoreProof.referenceType
        (permissions.typeBases index) (referenceValue (annotations index)) 16)
    (fits : phase.allocationAddress 8 + body.count * 56 < 2 ^ 64) :
    RequestEvidence (catalog.model next previous (streamRequest output id result body annotations)) storage phase := by
  apply streamRequestEvidence body output id result annotations
  · intro index inside
    rw [readRawSliceIndex, if_neg (by have := permissions.bound; omega),
      permissions.eventLocation index inside]
    exact (events index inside).read
  · intro enabled index inside
    rw [readRawSliceIndex, if_neg (by have := permissions.typeBound enabled; omega),
      permissions.typeLocation enabled index inside]
    exact (types enabled index inside).read
  · exact fits

#print axioms ReturnBody.classified
#print axioms ReturnBody.represented
#print axioms streamRequestEvidence
#print axioms streamSnapshotEvidence

end IRBodyProductionProof
