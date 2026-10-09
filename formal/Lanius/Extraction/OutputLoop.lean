import Lanius.Semantics.CountedLocal
import Lanius.Semantics.LoopRun
import Lanius.Memory.Read

namespace Lanius.Extraction

open Lanius.Core Lanius.Semantics

/-- An encoded-prefix writer with one fresh logical index. Byte printers and
    native-word copies share its framing and termination rules. -/
structure OutputState (base current : State) (counterId : VarId) (index address position words : Nat)
    (items : List α) (encode : α → List UInt8) : Prop extends CountedLocal base current counterId index where
  written : Memory.BytesWrite base.heap current.heap (address + position) ((items.take index).flatMap encode)
  readable : current.heap.Readable address (words * 4)
  world : current.world = base.world
  views : current.i32ArrayViews = base.i32ArrayViews

theorem OutputState.start (formed : base.CellsWellFormed)
    (readable : base.heap.Readable address (words * 4)) (unique : Memory.HeapBlockBasesUnique base.heap) :
    OutputState base (base.bindLocal counterId (.signed .i32 0)) counterId 0 address position words items encode :=
  ⟨CountedLocal.start formed counterId 0, Memory.BytesWrite.refl unique, readable, rfl, rfl⟩

theorem OutputState.advance
    (current : OutputState base before counterId index address position words items encode)
    (inside : index < items.length)
    (written : Memory.BytesWrite before.heap after.heap
      (address + position + ((items.take index).flatMap encode).length) (encode items[index]))
    (counter : CountedLocal base after counterId (index + 1))
    (world : after.world = before.world) (views : after.i32ArrayViews = before.i32ArrayViews) :
    OutputState base after counterId (index + 1) address position words items encode := by
  refine ⟨counter, ?_, written.readable current.readable,
    world.trans current.world, views.trans current.views⟩
  simpa only [List.take_succ_eq_append_getElem inside, List.flatMap_append, List.flatMap_singleton]
    using current.written.append written

theorem OutputState.transPure
    (current : OutputState base before counterId index address position words items encode)
    (pure : PureFrame before after) :
    OutputState base after counterId index address position words items encode := by
  refine ⟨⟨current.cells.trans pure.cells, pure.locals.trans current.locals,
    pure.localFound current.counter⟩, ?_, ?_,
    pure.world.trans current.world, pure.views.trans current.views⟩
  · simpa only [pure.heap] using current.written
  · simpa only [pure.heap] using current.readable

/-- Run a proved writer step for each index below the limit. The terminal
    case may be ordinary completion or a proved error with a partial prefix. -/
theorem OutputState.run
    {guard : Expr} {post : State → Prop}
    (initial : OutputState base state counterId 0 address position words items encode)
    (finished : ∀ state, OutputState base state counterId limit address position words items encode →
      ∃ after, RunsStmt program state (.whileLoop guard body) result after ∧ post after)
    (step : ∀ index state, index < limit →
      OutputState base state counterId index address position words items encode →
      ∃ after, RunsExpr program state guard (.boolean true) state ∧
        RunsStmt program state body .next after ∧
        OutputState base after counterId (index + 1) address position words items encode) :
    ∃ after, RunsStmt program state (.whileLoop guard body) result after ∧ post after := by
  apply RunsStmt.whilePrefix (remaining := limit)
    (invariant := fun remaining current => ∃ index, index + remaining = limit ∧
      OutputState base current counterId index address position words items encode)
  · intro current ⟨index, total, frame⟩
    have same : index = limit := by omega
    subst index
    exact finished current frame
  · intro remaining current ⟨index, total, frame⟩
    obtain ⟨after, condition, iteration, next⟩ := step index current (by omega) frame
    exact ⟨current, after, condition, iteration, index + 1, by omega, next⟩
  · exact ⟨0, by omega, initial⟩

#print axioms OutputState.advance
#print axioms OutputState.run

end Lanius.Extraction
