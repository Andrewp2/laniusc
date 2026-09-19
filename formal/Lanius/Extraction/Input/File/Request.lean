import Lanius.Extraction.Input.File.State

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

def requestEntry (before : State) : State := before.bindLocal 6 (.signed .i32 65536)
def remainingEntry (memory : Memory) (processed : List UInt8) (before : State) : State :=
  (requestEntry before).bindLocal 7 (.signed .i32 (Int.ofNat (memory.capacity - processed.length)))

structure Requested (memory : Memory) (processed : List UInt8) (before after : State) : Prop
    extends Buffers memory processed after where
  request : after.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length)))
  remaining : after.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length)))
  effect : StoreEffect CellSet.empty before after

/-- The two real temporary declarations and the capacity-probe branch
preserve all persistent input storage. Their writes are fresh allocations,
not writes to the caller's cells. -/
theorem prepareRequest (program : Program) (invariant : Buffers memory processed before) :
    ∃ after, Executes program (remainingEntry memory processed before)
        (RequestLocals.adjust ⟨7, 6⟩) .next after ∧ Requested memory processed before after := by
  let first := requestEntry before
  let second := remainingEntry memory processed before
  have firstBuffers := invariant.bindTemporary 6 (.signed .i32 65536) (by decide)
  have secondBuffers := firstBuffers.bindTemporary 7 (.signed .i32 (Int.ofNat (memory.capacity - processed.length))) (by decide)
  have ownedFirst := bindLocal_owns_fresh before 6 (.signed .i32 65536) invariant.registry.wellFormed
  have owned := bindLocal_preserves_localPointsTo_of_ne first 7 6
    (.signed .i32 (Int.ofNat (memory.capacity - processed.length))) before.nextCell _ firstBuffers.registry.wellFormed (by decide) ownedFirst
  have remaining : second.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))) :=
    Assertion.localPointsTo_local _ _ _ _ (bindLocal_owns_fresh first 7 _ firstBuffers.registry.wellFormed)
  obtain ⟨after, run, valid, request, effect⟩ := executes_request_adjustment program second ⟨7, 6⟩ before.nextCell
    (memory.capacity - processed.length) secondBuffers.registry.wellFormed remaining owned
  have localsKept : ∀ id ∈ [0, 1, 2, 3, 4], second.cellId? id ≠ some before.nextCell := by
    intro id member
    have small : id ≤ 4 := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl | rfl | rfl <;> decide
    have six : 6 ≠ id := Ne.symm (Nat.ne_of_lt (Nat.lt_of_le_of_lt small (by decide)))
    have seven : 7 ≠ id := Ne.symm (Nat.ne_of_lt (Nat.lt_of_le_of_lt small (by decide)))
    rw [show second.cellId? id = first.cellId? id from bindLocal_preserves_other_cellId first 7 id _ seven]
    exact bindLocal_other_cellId_ne_fresh before 6 id _ invariant.registry.wellFormed six
  have kept := secondBuffers.pureScalar effect valid owned.2
    (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry invariant.registry.wellFormed invariant.total.2)) localsKept
  have remainingKept : after.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))) := by
    apply effect.preserves_local secondBuffers.registry.wellFormed remaining
    intro cell found same
    change cell = before.nextCell at same
    have seven : second.cellId? 7 = some first.nextCell := by simp [second, first, remainingEntry, State.cellId?, State.bindLocal, State.bindCell]
    have identity := Option.some.inj (seven.symm.trans found)
    have fresh : first.nextCell = before.nextCell + 1 := rfl
    exact Nat.ne_of_gt (show before.nextCell < first.nextCell from fresh ▸ Nat.lt_succ_self _) (identity.trans same)
  have allocated := (bindLocal_effect before 6 (.signed .i32 65536)).trans
    (bindLocal_effect first 7 (.signed .i32 (Int.ofNat (memory.capacity - processed.length))))
  have combined := (allocated.trans effect.toStoreEffect).hideFreshWrites (by
    intro cell written
    simp only [CellSet.union, CellSet.empty, CellSet.singleton, false_or] at written
    exact written ▸ Nat.le_refl _)
  exact ⟨after, run, ⟨kept, Assertion.localPointsTo_local _ _ _ _ request, remainingKept, combined⟩⟩

/-- Compose preparation with the actual following read statement. The
continuation states its postcondition after closing the temporary scopes. -/
theorem executesIteration (program : Program) (reader : FunctionId)
    (wordsFound : program.constant? words.id = some words) (wordsValue : words.value = .signed .i32 16384)
    (invariant : Buffers memory processed before) (completion : Completion) (post : State → Prop)
    (continuation : ∀ middle, Requested memory processed before middle →
      ∃ after, Executes program middle (readChunk reader) completion after ∧ post (restoreLocals before after)) :
    ∃ after, Executes program before (iteration reader words.id) completion after ∧ post after := by
  obtain ⟨middle, adjustment, prepared⟩ := prepareRequest program invariant
  obtain ⟨after, run, done⟩ := continuation middle prepared
  have multiplied : Evaluates program before (binary .multiply (.constant words.id) (number 4)) (.signed .i32 65536) before :=
    evaluatesNatI32Multiply (leftValue := 16384) (rightValue := 4)
      (wordsValue ▸ evaluatesConstant wordsFound) Lanius.Semantics.evaluatesValue (by decide)
  have first := invariant.bindTemporary 6 (.signed .i32 65536) (by decide)
  have subtracted : Evaluates program (requestEntry before) (binary .subtract (read 2) (read 5))
      (.signed .i32 (Int.ofNat (memory.capacity - processed.length))) (requestEntry before) :=
    evaluatesNatI32Subtract (Lanius.Semantics.evaluatesLocal first.capacityLocal)
      (Lanius.Semantics.evaluatesLocal (Assertion.localPointsTo_local _ _ _ _ first.total))
      invariant.capacity (Nat.le_trans (Nat.sub_le _ _) (Nat.le_trans memory.capacityBound memory.outputBound))
  exact ⟨restoreLocals before (restoreLocals (requestEntry before) after),
    executesLetLocal multiplied (executesLetLocal subtracted (executesSequence adjustment run)), done⟩

end Lanius.Extraction.Input.File
