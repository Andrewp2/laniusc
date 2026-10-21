import Lanius.Semantics.HostCall
import Lanius.Memory.Allocation

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

private def allocator : Function := {
  id := 7
  parameters := [(1, .scalar (.unsigned .usize)), (2, .scalar (.unsigned .usize))]
  returnType := .scalar .rawPtr
  body := none
  external := some (.host .alloc) }
private def program : Program := { functions := [allocator] }

theorem allocatedWords (noViews : state.i32ArrayViews = [])
    (budget : consumeBudget state.heap.remaining (words * 4) = some remaining) :
    RunsExpr program state (.call 7 [.value (.unsigned .usize (words * 4)), .value (.unsigned .usize 4)])
      (.pointer state.heap.borrowedAddress)
      { state with heap := state.heap.allocatedI32 words remaining, world := World.record state.world .alloc } := by
  apply RunsExpr.hostCall (function := allocator) (bindings := [(1, .unsigned .usize (words * 4)), (2, .unsigned .usize 4)])
    (values := [.unsigned .usize (words * 4), .unsigned .usize 4])
    rfl rfl rfl rfl noViews
  simp only [World.call, World.callSimple, Heap.allocate_i32, budget]

theorem exhaustedWords (noViews : state.i32ArrayViews = [])
    (budget : consumeBudget state.heap.remaining (words * 4) = none) :
    RunsExpr program state (.call 7 [.value (.unsigned .usize (words * 4)), .value (.unsigned .usize 4)])
      (.pointer 0) { state with world := World.record state.world .alloc } := by
  apply RunsExpr.hostCall (function := allocator) (bindings := [(1, .unsigned .usize (words * 4)), (2, .unsigned .usize 4)])
    (values := [.unsigned .usize (words * 4), .unsigned .usize 4])
    rfl rfl rfl rfl noViews
  simp only [World.call, World.callSimple, Heap.allocate_i32, budget, null]

#print axioms RunsExpr.hostCall
#print axioms allocatedWords
#print axioms exhaustedWords

end Lanius.Semantics
