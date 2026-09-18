import Lanius.X86.Storage.StringCopy
import Lean.Elab.Term
import Lean.Util.CollectAxioms

namespace Lanius.X86.Storage.String

-- An empty payload still consumes an allocation identity. A relation using
-- only zero-width byte intervals would incorrectly allow these to alias.
example (address : Machine.Address) : ¬ Separated address 0 address 0 := by
  intro separate
  exact separate.different rfl

example : Separated 4096 0 4100 0 := by unfold Separated; decide

-- Embedded NUL and multibyte UTF-8 are payload, not terminators or padding.
example : Lanius.World.utf8Bytes "a\x00é" = [97, 0, 195, 169] := by decide

example (before : Lanius.Semantics.State) (wellFormed : Lanius.Memory.HeapWellFormed before.heap) :
    ∃ left middle right after,
      Core.Mapped before middle "" left ∧ Core.Mapped middle after "" right ∧ left ≠ right := by
  obtain ⟨left, middle, right, after, first, second, distinct⟩ := Core.two_calls wellFormed ""
  exact ⟨left, middle, right, after, first, second, Nat.ne_of_lt distinct⟩

run_elab do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  for name in [``Bytes.frame, ``Bytes.lane, ``Bytes.store, ``bytes_length,
      ``of_canonical, ``Represents.frame, ``copy_descriptor,
      ``Separated.symm, ``Separated.different, ``Separated.lanes,
      ``CopyResult.contents, ``CopyResult.preserve, ``Represents.copy_data,
      ``Bytes.store_separate, ``Core.map_correct, ``Core.Mapped.distinct,
      ``Core.Mapped.old_block, ``Core.two_calls, ``Core.Mapped.realize, ``Core.BorrowedAt.frame] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "string storage theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Content-based string descriptors, decoded descriptor copies, conditional fresh-copy framing, mutation isolation, and exact Core borrowed-block creation use only standard axioms"

end Lanius.X86.Storage.String
