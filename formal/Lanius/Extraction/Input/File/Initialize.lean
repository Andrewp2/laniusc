import Lanius.Extraction.Input.File.Oversize

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

structure Finished (resources : Resources) (before after : State) : Prop where
  registry : Allocation.Registry after
  representable : Host.RepresentableViews after
  output : ∃ copied, copied.IsPrefix resources.bytes ∧ copied.length ≤ resources.capacity ∧
    (resources.bytes.length ≤ resources.capacity → copied = resources.bytes) ∧
    after.cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values (copiedBuffer [] resources.original copied))) }
  world : ∃ reads, 0 < reads ∧ after.world = resources.finalWorld reads
  effect : Host.Effect resources.writes before after

theorem Finished.outputOfFits (finished : Finished resources before after)
    (fits : resources.bytes.length ≤ resources.capacity) :
    after.cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values (copiedBuffer [] resources.original resources.bytes))) } := by
  obtain ⟨copied, _, _, complete, stored⟩ := finished.output
  simpa only [complete fits] using stored

/-- Establish the loop invariant from the actual function parameters and
registered buffers. Pointer synchronization and both temporary declarations
are executed here; no internal loop invariant is assumed by the caller. -/
theorem body_returns (reader : Host.CheckedExternal program .read 3)
    (wordsFound : program.constant? words.id = some words) (wordsValue : words.value = .signed .i32 16384)
    (resources : Resources) (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (outputMember : resources.output ∈ before.i32ArrayViews) (packedMember : resources.packed ∈ before.i32ArrayViews)
    (outputContents : before.cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values resources.original)) })
    (handleRead : before.local? 0 = some (.signed .i32 resources.handle.id))
    (outputRead : before.local? 1 = some (.slice i32 resources.output.root [] 0 resources.output.length))
    (capacityRead : before.local? 2 = some (.signed .i32 resources.capacity))
    (packedRead : before.local? 3 = some (.slice i32 resources.packed.root [] 0 resources.packed.length))
    (world : before.world = resources.world)
    (sizeFit : 65536 < unsignedModulus program.target .usize) :
    ∃ after, Executes program before (body reader.function.id words.id)
        (.returned (some (.signed .i32 resources.result))) after ∧ Finished resources before after := by
  have capacityGuard : Evaluates program before (binary .lessEqual (read 2) negativeOne) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program capacityRead) (negativeOne_evaluates program before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  obtain ⟨called, pointer, nonnull, registry, cells, locals, views, next, remaining, sameWorld⟩ :=
    initial.evaluatesPointer program packedMember 3 (by simpa only [initial.roots resources.packed packedMember] using packedRead)
  have syncEffect : Host.Effect CellSet.empty before called :=
    ⟨registry.wellFormed, locals, fun _ _ _ => by simp only [State.cellEntry?, cells], Nat.le_of_eq next.symm,
      ⟨fun entry member => ⟨entry, by simpa only [cells] using member, rfl⟩⟩, views, remaining⟩
  have calledRepresentable : Host.RepresentableViews called := by
    intro view member values contents
    exact representable view (by simpa only [views] using member) values (by simpa only [State.cellEntry?, cells] using contents)
  let pointerReady := called.bindLocal 4 (.pointer resources.packed.address)
  have pointerRegistry := registry.bindLocal 4 (.pointer resources.packed.address)
  have pointerRepresentable := calledRepresentable.bindLocal registry 4 (.pointer resources.packed.address)
  have pointerOutput : resources.output ∈ pointerReady.i32ArrayViews := by
    change resources.output ∈ called.i32ArrayViews
    simpa only [views] using outputMember
  have pointerPacked : resources.packed ∈ pointerReady.i32ArrayViews := by
    change resources.packed ∈ called.i32ArrayViews
    simpa only [views] using packedMember
  let memory : Memory := {
    toResources := resources
    totalCell := pointerReady.nextCell
    outputTotal := Nat.ne_of_lt (pointerRegistry.root_lt_next pointerOutput),
    packedTotal := Nat.ne_of_lt (pointerRegistry.root_lt_next pointerPacked) }
  let ready := pointerReady.bindLocal 5 (.signed .i32 0)
  have readyRegistry := pointerRegistry.bindLocal 5 (.signed .i32 0)
  have readyRepresentable := pointerRepresentable.bindLocal pointerRegistry 5 (.signed .i32 0)
  have keep {id : Lanius.VarId} {value : Value} (four : (4 : Lanius.VarId) ≠ id) (five : (5 : Lanius.VarId) ≠ id)
      (found : before.local? id = some value) : ready.local? id = some value :=
    (bindLocal_preserves_other_local pointerRegistry.wellFormed five).trans
      ((bindLocal_preserves_other_local registry.wellFormed four).trans
        (syncEffect.preservesLocal initial.wellFormed found (fun _ _ impossible => impossible)))
  have readyHandle := keep (by decide) (by decide) handleRead
  have readyOutput := keep (by decide) (by decide) outputRead
  have readyCapacity := keep (by decide) (by decide) capacityRead
  have readyPacked := keep (by decide) (by decide) packedRead
  have pointerLocal : pointerReady.local? 4 = some (.pointer resources.packed.address) :=
    Assertion.localPointsTo_local _ _ _ _ (bindLocal_owns_fresh called 4 _ registry.wellFormed)
  have readyPointer : ready.local? 4 = some (.pointer resources.packed.address) :=
    (bindLocal_preserves_other_local pointerRegistry.wellFormed (show (5 : Lanius.VarId) ≠ 4 by decide)).trans pointerLocal
  have pointerGuard : Evaluates program pointerReady (binary .equal (read 4) (.value (.pointer 0))) (.boolean false) pointerReady := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program pointerLocal)
      (show Evaluates program pointerReady (.value (.pointer 0)) (.pointer 0) pointerReady from ⟨1, rfl⟩)
    simpa only [evalBinaryValue, scalarEqual, Except.ok.injEq, Value.boolean.injEq, beq_eq_false_iff_ne, Lanius.Memory.null] using nonnull
  have allocated := (bindLocal_effect called 4 (.pointer resources.packed.address)).trans (bindLocal_effect pointerReady 5 (.signed .i32 0))
  have readyContents : ready.cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values resources.original)) } := by
    rw [allocated.oldCells resources.output.root (registry.root_lt_next (by simpa only [views] using outputMember)) (by simp [CellSet.union, CellSet.empty])]
    simpa only [State.cellEntry?, cells] using outputContents
  have total := bindLocal_owns_fresh pointerReady 5 (.signed .i32 0) pointerRegistry.wellFormed
  have invariant : Invariant memory [] 0 ready := by
    refine ⟨⟨readyRegistry, readyRepresentable, ?_, pointerOutput, pointerPacked, readyOutput, readyPacked,
      readyHandle, readyCapacity, readyPointer, total, readyContents, Nat.zero_le _, ?_⟩, ?_⟩
    · change called.i32ArrayViews.Pairwise I32ViewRangesDisjoint
      simpa only [views] using disjoint
    · intro id member cell binding changed
      have readValue : ∃ value, (∀ elements, value ≠ .array elements) ∧ ready.local? id = some value := by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl | rfl | rfl | rfl
        · refine ⟨_, ?_, readyHandle⟩
          intro elements same; cases same
        · refine ⟨_, ?_, readyOutput⟩
          intro elements same; cases same
        · refine ⟨_, ?_, readyCapacity⟩
          intro elements same; cases same
        · refine ⟨_, ?_, readyPacked⟩
          intro elements same; cases same
        · refine ⟨_, ?_, readyPointer⟩
          intro elements same; cases same
      obtain ⟨value, notArray, readValue⟩ := readValue
      have notView (view : I32ArrayView) (present : view ∈ ready.i32ArrayViews) : cell ≠ view.root := by
        obtain ⟨values, _, stored⟩ := readyRegistry.storage present
        exact local_cell_ne_of_distinct_value readValue stored (notArray _) binding
      rcases changed with (output | packed) | scalar
      · exact notView resources.output pointerOutput output
      · exact notView resources.packed pointerPacked packed
      · have different : (5 : Lanius.VarId) ≠ id := by
          simp only [List.mem_cons, List.not_mem_nil, or_false] at member
          rcases member with rfl | rfl | rfl | rfl | rfl <;> decide
        exact bindLocal_other_cellId_ne_fresh pointerReady 5 id _ pointerRegistry.wellFormed different (scalar ▸ binding)
    · exact (sameWorld.trans world).trans memory.worldAt_zero.symm
  obtain ⟨completed, copied, reads, runLoop, done, sourcePrefix, complete, positive, finalWorld, loopEffect⟩ :=
    runsLoop reader wordsFound wordsValue invariant sizeFit
  have totalClosed := loopEffect.closeLocal pointerReady 5 (.signed .i32 0) pointerRegistry.wellFormed
  have visible := totalClosed.narrow (retained := resources.writes) (by
    intro cell old written
    rcases written with retained | temporary
    · exact retained
    · exact False.elim ((Nat.ne_of_lt old) temporary))
  have pointerClosed := visible.closeLocal called 4 (.pointer resources.packed.address) registry.wellFormed
  have fullEffect := (syncEffect.weaken (larger := resources.writes) (fun _ impossible => False.elim impossible)).trans pointerClosed
  refine ⟨restoreLocals called (restoreLocals pointerReady completed),
    executesSequence (executesIfFalse capacityGuard (executesSkip _ _))
      (executesLetLocal pointer (executesSequence (executesIfFalse pointerGuard (executesSkip _ _))
        (executesLetLocal (show Evaluates program pointerReady (number 0) (.signed .i32 0) pointerReady from ⟨1, rfl⟩)
          (executesSequenceReturned runLoop)))), ?_⟩
  exact ⟨done.registry.restoreLocals called fullEffect.wellFormed, done.representable,
    ⟨copied, sourcePrefix, done.capacity, complete, done.outputContents⟩, ⟨reads, positive, finalWorld⟩, fullEffect⟩

end Lanius.Extraction.Input.File
