import Lanius.Semantics.Capacity.State

namespace Lanius.Semantics.Capacity
open Lanius.Core Lanius.Properties

theorem Ready.withHeap (ready : Ready config before) (heap : Lanius.Memory.Heap) :
    Ready config { before with heap } := ⟨ready.frontier, ready.root, ready.locals, ready.cells⟩

theorem Ready.withViews (ready : Ready config before) (views : List I32ArrayView) :
    Ready config { before with i32ArrayViews := views } := ⟨ready.frontier, ready.root, ready.locals, ready.cells⟩

theorem allocateTemporary (valid : config.Valid) (ready : Ready config before) (entry : Value) :
    state config (before.allocateTemporary entry).2 =
      ((state config before).allocateTemporary (value config entry)).2 := by
  have transported := bindCell valid before ready.frontier 0 (some entry)
  exact congrArg (restoreLocals (state config before)) transported

theorem Ready.allocateTemporary (valid : config.Valid) (ready : Ready config before)
    (entryClosed : closed config entry = true) : Ready config (before.allocateTemporary entry).2 :=
  (ready.bindLocal valid 0 entry entryClosed).restoreLocals ready

private theorem decode_plain (decoded : decodeI32Array count bytes = .ok entries) : plains entries = true := by
  induction count generalizing bytes entries with
  | zero =>
    simp only [decodeI32Array] at decoded
    split at decoded <;> cases decoded
    rfl
  | succ count ih =>
    simp only [decodeI32Array] at decoded
    split at decoded
    · contradiction
    · cases tailDecoded : decodeI32Array count (bytes.drop 4) with
      | error reason => simp [tailDecoded] at decoded
      | ok tail =>
        rw [tailDecoded] at decoded
        cases decoded
        simpa only [plains, plain, Bool.true_and] using ih tailDecoded

theorem stringDataPtr (config : Config) (ready : Ready config before)
    (mapped : mapStringDataPtr before text = .done result after) :
    mapStringDataPtr (state config before) text = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  unfold mapStringDataPtr at mapped ⊢
  simp only [show (state config before).heap = before.heap from rfl]
  cases allocated : before.heap.mapBorrowed (Lanius.World.utf8Bytes text) 4 <;> simp only [allocated] at mapped ⊢
  all_goals try contradiction
  case allocated address heap =>
    cases mapped
    exact ⟨rfl, ready.withHeap heap, rfl⟩

/-- Raw view construction reads the unchanged heap and allocates a fresh
semantic cell. It does not synchronize or mutate existing backing arrays. -/
theorem rawI32Slice (valid : config.Valid) (ready : Ready config before)
    (mapped : mapRawI32Slice before address count = .done result after) :
    mapRawI32Slice (state config before) address count = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [mapRawI32Slice] at mapped ⊢
  split at mapped
  · contradiction
  · rename_i nonnegative
    simp only [nonnegative, ↓reduceIte]
    simp only [show (state config before).heap = before.heap from rfl]
    cases protection : before.heap.protectAsBorrowed address (count.toNat * 4) 4 <;> simp only [protection] at mapped ⊢
    all_goals try contradiction
    case ok heap =>
      cases loaded : heap.loadBytes address (count.toNat * 4) <;> simp only [loaded] at mapped ⊢
      all_goals try contradiction
      case ok bytes =>
        cases decoded : decodeI32Array count.toNat bytes <;> simp only [decoded] at mapped ⊢
        all_goals try contradiction
        case ok entries =>
          cases mapped
          have entryPlain : plain (.array entries) = true := decode_plain decoded
          have fresh : before.nextCell ≠ config.root := Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le valid.old ready.frontier))
          refine ⟨?_, ((ready.withHeap heap).allocateTemporary valid (plain_closed config _ entryPlain)).withViews _, ?_⟩
          · have transport := allocateTemporary valid (ready.withHeap heap) (.array entries)
            rw [plain_fixed config _ entryPlain] at transport
            simp only [allocateTemporary_returns_fresh_cell, value, fresh, false_and, ↓reduceIte]
            exact congrArg (fun next : State => Outcome.done (Value.slice (.scalar (.signed .i32)) before.nextCell [] 0 count.toNat)
              { next with i32ArrayViews := before.i32ArrayViews ++ [{ address, root := before.nextCell, projections := [], length := count.toNat }] }) transport.symm
          · change config.reachable before.nextCell = true
            simp only [Config.reachable, ready.frontier, decide_true, Bool.or_true]

end Lanius.Semantics.Capacity
