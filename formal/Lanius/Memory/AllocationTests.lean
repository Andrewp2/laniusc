import Lanius.Memory.Allocation

namespace Lanius.Memory

variable {heap : Heap} {words pointer count : Nat} {budget : Option Nat} {values : List UInt8}

-- Exact budget, insufficient budget, zero-size allocation, and alignment.
example : (match ({ remaining := some 8 } : Heap).allocate 8 4 with
  | .allocated 4 heap => heap.remaining = some 0 ∧ heap.nextAddress = 12
  | _ => False) := ⟨rfl, rfl⟩
example : (match ({ remaining := some 7 } : Heap).allocate 8 4 with
  | .exhausted heap => heap.remaining = some 7 ∧ heap.blocks.isEmpty = true
  | _ => False) := ⟨rfl, rfl⟩
example : (match ({ nextAddress := 9 } : Heap).allocate 0 4 with
  | .allocated 12 heap => heap.nextAddress = 13
  | _ => False) := rfl

example (below : HeapBlocksBelowNext heap) :
    (heap.allocatedI32 words budget).Readable heap.borrowedAddress (words * 4) :=
  Heap.allocatedI32_readable below
example (loaded : heap.loadBytes pointer count = .ok values) :
    (heap.allocatedI32 words budget).loadBytes pointer count = .ok values :=
  Heap.appendI32_oldLoad loaded

#print axioms Heap.allocate_i32
#print axioms Heap.allocatedI32_readable
#print axioms Heap.appendI32_oldLoad

end Lanius.Memory
