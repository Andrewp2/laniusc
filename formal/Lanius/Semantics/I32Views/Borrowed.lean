import Lanius.Semantics.I32Views

namespace Lanius.Semantics

open Lanius.Core

/-- Persistent resources from borrowing a fresh word-padded string. Unlike
an owned allocation, borrowing does not consume the allocation budget. -/
structure I32BorrowedResources (before : State) (count : Nat) (after : State) : Prop where
  storage : ∃ address elements,
    after.i32ArrayViews = before.i32ArrayViews ++
      [{ address, root := before.nextCell, projections := [], length := count }] ∧
    I32ArrayViewBlockWellFormed after.heap
      { address, root := before.nextCell, projections := [], length := count } ∧
    after.cells = before.cells ++ [{ id := before.nextCell, value := some (.array elements) }] ∧
    elements.length = count ∧ (∀ element ∈ elements, ∃ value, element = .signed .i32 value) ∧
    before.heap.nextAddress ≤ address
  viewsPreserved : Lanius.Properties.I32ArrayViewBlocksPreserved before.i32ArrayViews before.heap after.heap
  remaining : after.heap.remaining = before.heap.remaining
  representable : ∀ words : List Int,
    after.cellEntry? before.nextCell = some {
      id := before.nextCell, value := some (.array (words.map (Value.signed .i32))) } →
    ∀ word ∈ words, -2147483648 ≤ word ∧ word ≤ 2147483647

end Lanius.Semantics
