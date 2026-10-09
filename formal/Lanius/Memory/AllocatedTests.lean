import Lanius.Memory.Allocated
import Lanius.Memory.BorrowRange

namespace Lanius.Memory.AllocatedTests

open Lanius.Memory

-- Alignment rounds an unaligned frontier; the exact budget is consumed.
example : (match ({ nextAddress := 9, remaining := some 16 } : Heap).allocate 16 8 with
  | .allocated 16 after => after.remaining = some 0 ∧ after.nextAddress = 32
  | _ => False) := ⟨rfl, rfl⟩

-- Zero-sized allocations still reserve a distinct base for the next block.
example : (match ({ nextAddress := 9, remaining := some 0 } : Heap).allocate 0 8 with
  | .allocated 16 after => after.nextAddress = 17 ∧
      (match after.allocate 0 8 with | .allocated 24 _ => True | _ => False)
  | _ => False) := ⟨rfl, trivial⟩

example : ({ nextAddress := 9, remaining := some 15 } : Heap).allocate 16 8 =
    .exhausted { nextAddress := 9, remaining := some 15 } := rfl

example : ({ nextAddress := 9 } : Heap).allocate 16 3 =
    .trapped .allocatorContract { nextAddress := 9 } := rfl

example (below : HeapBlocksBelowNext heap) (positive : 0 < alignment) (bound : offset + count ≤ size) :
    (heap.allocatedBytes size alignment budget).loadBytes (heap.allocationAddress alignment + offset) count =
      .ok (List.replicate count 0) := Heap.allocatedBytes_zeroRange below positive bound

example (below : HeapBlocksBelowNext heap) (positive : 0 < alignment) :
    HeapBlocksBelowNext ((heap.allocatedBytes size alignment budget).borrowBlock (heap.allocationAddress alignment)) :=
  (heap.allocatedBytes_below below positive).borrowBlock

#print axioms Heap.allocate_of_budget
#print axioms Heap.allocatedBytes_zeroRange
#print axioms Heap.allocatedBytes_unique
#print axioms Heap.allocatedBytes_below
#print axioms HeapBlocksBelowNext.borrowBlock

end Lanius.Memory.AllocatedTests
