import Lanius.Extraction.CompactDecode.Hex
import Init.Data.Range.Lemmas
import Init.Data.List.Monadic

namespace Lanius.Extraction.CompactDecode

/-- A sequence of successful calls to the actual element reader. -/
inductive Reads (read : DecodeM α) : DecodeState → List α → DecodeState → Prop
  | nil : Reads read state [] state
  | cons (head : read.run before = some (value, middle))
      (tail : Reads read middle values after) :
      Reads read before (value :: values) after

theorem Reads.loop {read : DecodeM α} {before after : DecodeState} {values : List α}
    (reads : Reads read before values after)
    (indices : List Nat) (count : indices.length = values.length)
    (push : β → α → β) (initial : β) :
    ((forIn indices initial fun _ acc => do
      let value ← read
      pure (.yield (push acc value))) : DecodeM β).run before =
      some (values.foldl push initial, after) := by
  induction reads generalizing indices initial with
  | nil =>
      have empty : indices = [] := List.eq_nil_of_length_eq_zero count
      subst indices
      rfl
  | cons head tail ih =>
      cases indices with
      | nil => simp at count
      | cons index indices =>
          simp only [List.length_cons, Nat.add_right_cancel_iff] at count
          rw [List.forIn_cons]
          simp only [StateT.run, bind, StateT.bind]
          dsimp only [StateT.run] at head
          rw [head]
          simpa [StateT.run, bind, StateT.bind, pure, StateT.pure, List.foldl]
            using ih indices count (push initial _)

theorem Reads.readMany {read : DecodeM α} {before after : DecodeState}
    {values : List α} (reads : Reads read before values after) :
    (CompactDecode.readMany values.length read).run before = some (values, after) := by
  unfold CompactDecode.readMany
  dsimp only
  rw [Std.Legacy.Range.forIn_eq_forIn_range']
  have loop := reads.loop (List.range' 0 values.length) (by simp) Array.push #[]
  simp only [StateT.run, bind, StateT.bind]
  dsimp only [StateT.run, bind, StateT.bind, pure, StateT.pure] at loop ⊢
  simp only [Std.Legacy.Range.size, Nat.sub_zero, Nat.add_sub_cancel, Nat.div_one]
  rw [loop]
  simp [pure, StateT.pure, List.foldl_push_eq_append]

/-- Compose field round trips without re-running or replacing the reader. -/
theorem reads_encoding {read : DecodeM α} (encode : α → List Nat)
    (valid : α → Prop)
    (field : ∀ value offset, valid value → EncodedAt bytes offset (encode value) →
      read.run {bytes, offset} = some (value, {bytes, offset := offset + (encode value).length}))
    (values : List α) (bounded : ∀ value ∈ values, valid value)
    (encoded : EncodedAt bytes offset (values.flatMap encode)) :
    Reads read {bytes, offset} values
      {bytes, offset := offset + (values.flatMap encode).length} := by
  induction values generalizing offset with
  | nil => exact Reads.nil
  | cons value values ih =>
      simp only [List.flatMap_cons] at encoded ⊢
      have head := field value offset (bounded value List.mem_cons_self) encoded.left
      have tail := ih (fun v h => bounded v (List.mem_cons_of_mem value h)) encoded.right
      simpa only [List.length_append, Nat.add_assoc] using Reads.cons head tail

end Lanius.Extraction.CompactDecode
