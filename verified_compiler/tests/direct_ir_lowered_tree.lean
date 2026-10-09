import verified_compiler.tests.direct_ir_negative_lowering
import verified_compiler.tests.direct_ir_builder_navigation

namespace IRLoweredTreeProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IREventStoreProof IREventWriteProof IRNegativeLoweringProof
open IRShapeProof IRChildrenProof IRBuilderProof IRBuilderCallProof IRBuilderNavigationProof

private theorem slotRead {before after : State} (slot : IREventStoreProof.Context before)
    (snapshot : NativeSnapshot 64 extractedProgram after.heap IREventStoreProof.eventType slot.eventBase value 40) :
    readRawSliceIndex extractedProgram after IREventStoreProof.eventType slot.events slot.capacity slot.position = .ok value := by
  simp only [readRawSliceIndex, show ¬slot.position ≥ slot.capacity from Nat.not_le.mpr slot.bound,
    ↓reduceIte, slot.eventLocation, Bind.bind, Except.bind]
  exact snapshot.read

/-- A native write preserves the allocator's frontier, layout and budget.
    These facts justify the subsequent builder allocation. -/
private theorem appendBelow (effect : appendHeapEffect enabled eventBase typeBase event before after)
    (below : HeapBlocksBelowNext before) : HeapBlocksBelowNext after := by
  obtain ⟨_, middle, first, last⟩ := effect
  cases enabled
  · simp only [Bool.false_eq_true, ↓reduceIte] at last
    subst after
    exact first.below below
  · simp only [↓reduceIte] at last
    exact last.2.below (first.below below)

private theorem afterLowering (written : effect storage number before after)
    (below : HeapBlocksBelowNext before) :
    HeapBlocksBelowNext after ∧ HeapBlockBasesUnique after ∧ after.remaining = before.remaining := by
  obtain ⟨first, second, one, two, recorded, _⟩ := written
  have below := appendBelow two (appendBelow one below)
  have budget := two.footprint.budget.trans one.footprint.budget
  cases enabled : storage.tail.enabled
  · simp only [IRResultTypeProof.Recorded, IRResultTypeProof.annotationSlot, enabled,
      Bool.false_eq_true, ↓reduceIte] at recorded
    subst after
    exact ⟨below, two.footprint.unique, budget⟩
  · simp only [IRResultTypeProof.Recorded, IRResultTypeProof.annotationSlot, enabled, ↓reduceIte] at recorded
    exact ⟨recorded.2.below below, recorded.2.unique, recorded.2.budget.trans budget⟩

/-- The builder's input is derived from the two actual writes, not supplied
    as an independently valid tree or successful classifier execution. -/
def region (storage : Storage before) (number : Nat) (start : storage.head.position = 0)
    (written : effect storage number before.heap after.heap)
    (below : HeapBlocksBelowNext before.heap) : Region after := {
  count := 2, eventsAddress := storage.head.events, eventsLength := storage.head.capacity
  events := fun index => if index = 0 then negateEvent else integer (Int32.ofNat number).toBitVec
  kinds := fun _ => .ExpressionNode
  arities := fun index => if index = 0 then 1 else 0
  rules := fun index => if index = 0 then .Expressions else .NoChildren
  fits := by decide
  below := (afterLowering written below).1
  reads := by
    intro index inside
    obtain ⟨_, _, _, _, _, header, child⟩ := written
    have first := slotRead storage.head header
    have second := slotRead storage.tail child
    rw [start] at first
    have next : storage.tail.position = 1 := by rw [storage.next, start]
    rw [next] at second
    have descriptors := congrArg (fun value : Value => match value with
      | .structure _ (events :: _) => events | _ => .unit) storage.same
    change Value.rawSlice IREventStoreProof.eventType storage.tail.events storage.tail.capacity =
      Value.rawSlice IREventStoreProof.eventType storage.head.events storage.head.capacity at descriptors
    injection descriptors with _ events capacity
    rw [events, capacity] at second
    have cases : index = 0 ∨ index = 1 := by omega
    rcases cases with rfl | rfl
    · exact first
    · exact second
  classified := by
    intro index inside
    by_cases first : index = 0
    · simp only [first, ↓reduceIte]
      exact .fixed (by simp [fixedShapes, negateEvent])
    · simp only [first, ↓reduceIte]
      exact .payload (payload := .signed .i32 (Int32.ofNat number).toBitVec.toInt) List.mem_cons_self
  capacity := storage.head.capacity
  resultAddress := storage.head.types, resultLength := storage.head.typesLength, hasResultTypes := storage.head.enabled }

private theorem regionShape {before after : State}
    (storage : Storage before) (number : Nat) (start : storage.head.position = 0)
    (written : effect storage number before.heap after.heap) (below : HeapBlocksBelowNext before.heap) :
    (region storage number start written below).toSource.Suffix (fun _ => 2) 0 := by
  intro index _ inside
  have cases : index = 0 ∨ index = 1 := by change index < 2 at inside; omega
  rcases cases with rfl | rfl
  · dsimp only [Source.Node, region]
    exact ⟨by decide, by decide, by decide, 2, rfl, .cons (by decide) rfl (by decide) (by decide) .nil⟩
  · dsimp only [Source.Node, region]
    exact ⟨by decide, by decide, by decide, 2, rfl, .nil⟩

/-- The real source decoder, negative-literal lowering and tree builder run
    in order. The builder allocates its own endpoint table and returns the
    exact two-node tree; no successful intermediate call is a premise. -/
theorem actualNegativeTree (input : IRIntegerLoweringProof.Input before) (unused : List Value) (number : Nat)
    (decoded : IRDecimalLoopProof.scan input.bytes input.length 0 .empty = .number number)
    (storage : Storage before) (start : storage.head.position = 0)
    (formed : before.CellsWellFormed) (below : HeapBlocksBelowNext before.heap)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = [])
    (budget : consumeBudget before.heap.remaining 8 ≠ none) :
    ∃ lowered, ∃ written : effect storage number before.heap lowered.heap, ∃ built,
      ∃ tree : Ready (region storage number start written below) built,
        RunsExpr extractedProgram before (call input unused storage.head.value 0) (.signed .i32 2) lowered ∧
        RunsExpr extractedProgram lowered (region storage number start written below).call tree.value built ∧
        FreshCellFrame before built ∧ tree.ends 0 = 2 ∧ tree.ends 1 = 2 := by
  obtain ⟨lowered, lower, cells, world, views, written⟩ :=
    actualNumber input unused number decoded storage formed unique noViews
  rw [start] at lower
  obtain ⟨_, loweredUnique, remaining⟩ := afterLowering written below
  have tailOne : storage.tail.position = 1 := by rw [storage.next, start]
  have capacity : 2 ≤ storage.head.capacity := by
    have same := congrArg (fun value : Value => match value with
      | .structure _ [_, _, _, capacity] => capacity | _ => .unit) storage.same
    change Value.signed .i32 storage.tail.capacity = Value.signed .i32 storage.head.capacity at same
    injection same with _ counts
    have bound := storage.tail.bound
    omega
  obtain ⟨built, tree, build, builtCells, _, endpoints, _⟩ := actualCompleteCall
    (region storage number start written below) (regionShape storage number start written below)
    rfl (by change 0 < (2 : Nat); decide)
    (by change (2 : Int) ≤ storage.head.capacity; omega)
    (by change (2 : Nat) ≤ 536870911; decide)
    (by simpa only [region, remaining] using budget)
    (cells.after_cellsWellFormed formed) loweredUnique (views.trans noViews)
  exact ⟨lowered, written, built, tree, lower, build, cells.trans builtCells,
    endpoints 0 (by change (0 : Nat) < 2; decide), endpoints 1 (by change (1 : Nat) < 2; decide)⟩

#print axioms actualNegativeTree

end IRLoweredTreeProof
