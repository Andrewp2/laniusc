import Lanius.X86.Machine.Sequence

namespace Lanius.X86.Machine

/-- A terminating code window with an arbitrary postcondition. The following
code remains loaded at the returned instruction pointer. Store rules must
establish that property; it is not an implicit non-aliasing assumption. -/
def Block (count : Nat) (code tail : List UInt8) (before : State) (post : State → Prop) : Prop :=
  CodeAt before.memory before.rip (code ++ tail) →
  ∃ after, Steps count before after ∧ post after ∧
    after.rip = before.rip + BitVec.ofNat 64 code.length ∧ CodeAt after.memory after.rip tail

theorem Block.append (first : Block n left (right ++ tail) before middle)
    (next : ∀ state, middle state → Block m right tail state post) :
    Block (n + m) (left ++ right) tail before post := by
  intro loaded
  obtain ⟨state, steps, held, cursor, remaining⟩ := first (by simpa only [List.append_assoc] using loaded)
  obtain ⟨after, last, result, endCursor, following⟩ := next state held remaining
  refine ⟨after, steps.trans last, result, ?_, following⟩
  rw [endCursor, cursor, List.length_append, BitVec.ofNat_add, BitVec.add_assoc]

theorem Block.mono (run : Block count code tail before post) (weaken : ∀ state, post state → next state) :
    Block count code tail before next := by
  intro loaded
  obtain ⟨after, steps, held, cursor, following⟩ := run loaded
  exact ⟨after, steps, weaken after held, cursor, following⟩

theorem ReadOnly.block (instructions : List ReadOnly) (before : State) :
    Block instructions.length (ReadOnly.code instructions) tail before (· = ReadOnly.run instructions before) := by
  intro loaded
  have fields := ReadOnly.fields instructions before
  exact ⟨ReadOnly.run instructions before, ReadOnly.steps instructions before loaded.prefix, rfl, fields.2,
    by rw [fields.1, fields.2]; exact loaded.suffix⟩

end Lanius.X86.Machine
