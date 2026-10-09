import verified_compiler.tests.direct_ir_catalog_loop

namespace IRCatalogCopyDomain
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCatalogCopyProof IREventStoreProof IREventCodecProof IRTypeRefProof IRShapeProof

private def region : Value := source_value Extracted.«ir::body_events».Types.«Region».mk
  [.rawSlice eventType 48 1, .rawSlice referenceType 9999 1, .boolean false, .signed .i32 1]
def original : State :=
  ({ heap := {
    blocks := [{ base := 16, size := 40, alignment := 8, bytes := List.replicate 40 0 }]
    nextAddress := 56, remaining := some 56 } } : State)
    |>.bindLocal (source.argumentId 2) region
    |>.bindLocal (source.argumentId 3) (.signed .i32 1)
    |>.bindLocal (source.bindingId 2) (.rawSlice eventType 48 1)

/-- Independent readable source and classifications, not successful execution. -/
def input : Input original := {
  count := 1, eventsAddress := 48, eventsLength := 1, events := fun _ => integer 0
  kinds := fun _ => .ExpressionNode, arities := fun _ => 0, rules := fun _ => .NoChildren
  fits := by decide
  below := by simp [HeapBlocksBelowNext, original, State.bindLocal, State.bindCell]
  reads := by
    intro index inside
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    have snapshot : NativeSnapshot 64 extractedProgram original.heap eventType 16 (integer 0) 12 :=
      NativeSnapshot.enumSingle (by core_lookup) rfl (by decide) (by rfl)
        (NativeSnapshot.i32 0 (by rfl))
    have width : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
    have location : rawSliceElementAddress? extractedProgram eventType 48 0 = .ok 16 := by
      dsimp only [eventType] at width ⊢
      simp only [rawSliceElementAddress?, width]
      rfl
    change readRawSliceIndex extractedProgram original eventType 48 1 0 = .ok (integer 0)
    rw [readRawSliceIndex, if_neg (by decide), location]
    exact snapshot.read
  classified := by
    intro index inside
    exact Classifies.payload (payload := .signed .i32 0) (by simp [payloadShapes, integer])
  capacity := 1, resultAddress := 9999, resultLength := 1, hasResultTypes := false
  annotations := fun _ => .Invalid
  represented := by
    intro index inside
    refine ⟨0, 0, 0, false, .I32, .I32Slice, 0, 0, by decide, by decide, ?_⟩
    simp [representedEvents, scalarEvents]
  annotationReads := by intro enabled; cases enabled }

theorem disabledTypesUnreadable :
    readRawSliceIndex extractedProgram original referenceType input.resultAddress input.resultLength 0 =
      .error .invalidPointer := by rfl

/-- The assembled theorem has an inhabited domain even when source TypeRefs
    are unreadable. Its live CutState survives as a witness after scopes close. -/
theorem totalStage : ∃ after reached,
    RunsStmt extractedProgram original («prefix» .skip) .next after ∧
    CutState input (some 0) reached ∧ after = restoreLocals original reached := by
  have formed : original.CellsWellFormed := by
    apply State.CellsWellFormed.bindLocal
    apply State.CellsWellFormed.bindLocal
    apply State.CellsWellFormed.bindLocal
    simp [State.CellsWellFormed]
  have unique : HeapBlockBasesUnique original.heap := by
    intro left leftFound right rightFound _
    simp only [original, State.bindLocal, State.bindCell, List.mem_singleton] at leftFound rightFound
    exact leftFound.trans rightFound.symm
  let Q : Completion → State → Prop := fun completion after => completion = .next ∧ ∃ reached,
    CutState input (some 0) reached ∧ after = restoreLocals original reached
  obtain ⟨completion, after, run, done, reached, cut, restored⟩ :=
    actualAllocationCopy input (some 0) .skip (by decide) (by decide) (by decide)
      (by rfl) (by rfl) (by rfl) (by rfl) formed unique rfl Q
      (fun reached cut => ⟨.next, reached, RunsStmt.skip _ _, rfl, reached, cut, rfl⟩)
  subst completion
  exact ⟨after, reached, run, cut, restored⟩

/-- A separately proved actual tail contract reconnects the original source,
    without assuming allocation or copying or asserting full append success. -/
example (input : Input before) (budget : Option Nat)
    (positive : 0 < input.count) (fits : input.count * 56 < 2 ^ 31)
    (pointerFits : input.memory + input.count * 56 < 2 ^ 64)
    (sourceFound : before.local? (source.argumentId 2) = some input.value)
    (sourceEvents : before.local? (source.bindingId 2) =
      some (.rawSlice eventType input.eventsAddress input.eventsLength))
    (countFound : before.local? (source.argumentId 3) = some (.signed .i32 input.count))
    (available : consumeBudget before.heap.remaining (input.count * 56) = some budget)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) (Q : Completion → State → Prop)
    (tailContract : ∀ state, CutState input budget state → ∃ completion after,
      RunsStmt extractedProgram state tail completion after ∧ Q completion (restoreLocals before after)) :
    ∃ completion after, RunsStmt extractedProgram before (source.bindingStatement 5) completion after ∧
      Q completion after := by
  simpa only [actualDecomposition] using actualAllocationCopy input budget tail positive fits pointerFits
    sourceFound sourceEvents countFound available formed unique noViews Q tailContract

#print axioms input
#print axioms disabledTypesUnreadable
#print axioms totalStage
end IRCatalogCopyDomain
