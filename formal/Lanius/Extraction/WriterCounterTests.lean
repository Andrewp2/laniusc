import Lanius.Extraction.WriterCounter
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof

namespace Lanius.Extraction.WriterCounterTests

open Lanius.Core Lanius.Semantics

private def echo : Function := {
  id := 99, parameters := [(9, .scalar (.signed .i32))], returnType := .scalar (.signed .i32),
  body := some (.returnValue (some (.local 9))) }
private def program : Program := { functions := [echo] }

-- The writer call allocates a parameter cell, restores the loop's locals,
-- and must not lose or mutate the fresh counter before it is incremented.
theorem nestedWriter (formed : base.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique base.heap) :
    ∃ after, WriterCounter base after 10 20 address 4 [] 1 := by
  let before := (base.bindLocal 10 (.signed .i32 4)).bindLocal 20 (.signed .i32 0)
  have current : WriterCounter base before 10 20 address 4 [] 0 := .start formed unique (by decide)
  have beforeFormed : before.CellsWellFormed := current.frame.afterFormed formed
  have call : ∃ ready, RunsExpr program before (.call 99 [.value (.signed .i32 4)]) (.signed .i32 4) ready ∧
      PureFrame before ready := by
    clear current
    core_call echo
    core_stmt
  obtain ⟨ready, run, pure⟩ := call
  have heap : before.heap = base.heap := rfl
  have frame : WriterFrame before ready address [] :=
    ⟨by simpa only [pure.heap, heap] using Memory.OutputEffect.write (Memory.BytesWrite.refl unique),
      pure.cells, pure.world, pure.views⟩
  obtain ⟨middle, store, next⟩ := current.advance formed run frame
  obtain ⟨after, increment, final⟩ := next.increment (program := program) formed (by decide)
  exact ⟨after, final⟩

#print axioms nestedWriter
#print axioms WriterCounter.advance
#print axioms WriterCounter.increment

end Lanius.Extraction.WriterCounterTests
