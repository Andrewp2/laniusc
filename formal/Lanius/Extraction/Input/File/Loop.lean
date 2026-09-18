import Lanius.Extraction.Input.File.Iteration

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

theorem Memory.chunk_of_suffix (memory : Memory) (source : memory.bytes = processed ++ remaining) :
    memory.chunk processed = remaining.take (requestSize (memory.capacity - processed.length)) := by
  have suffix : memory.file.bytes.drop (memory.handle.offset + processed.length) = remaining := by
    calc
      _ = memory.bytes.drop processed.length := by simp only [Memory.bytes, List.drop_drop, Nat.add_comm]
      _ = remaining := by simp only [source, List.drop_left]
  simp only [Memory.chunk, suffix]

/-- The actual unbounded source loop terminates on every fitting file,
not merely on a one-chunk fixture. Each non-EOF iteration strictly consumes
the remaining file suffix; the final read is the EOF probe. -/
theorem completesLoop (reader : Host.CheckedExternal program .read 3)
    (wordsFound : program.constant? words.id = some words) (wordsValue : words.value = .signed .i32 16384)
    (invariant : Invariant memory processed reads before)
    (source : memory.bytes = processed ++ remaining)
    (capacity : memory.bytes.length ≤ memory.capacity)
    (sizeFit : 65536 < unsignedModulus program.target .usize) :
    ∃ after finalReads, Executes program before (loop reader.function.id words.id)
        (.returned (some (.signed .i32 memory.bytes.length))) after ∧
      Invariant memory memory.bytes finalReads after ∧ reads < finalReads ∧ Host.Effect memory.writes before after := by
  generalize size : remaining.length = count
  induction count using Nat.strongRecOn generalizing processed remaining before reads with
  | ind count ih =>
    have chunk := memory.chunk_of_suffix source
    have totalLength : memory.bytes.length = processed.length + remaining.length := by simp only [source, List.length_append]
    have fits : processed.length + (memory.chunk processed).length ≤ memory.capacity := by
      rw [chunk, List.length_take]
      have limited := Nat.min_le_right (requestSize (memory.capacity - processed.length)) remaining.length
      omega
    obtain ⟨middle, iteration, afterIteration, effect⟩ := iterationStep reader wordsFound wordsValue invariant sizeFit fits
    by_cases ended : remaining = []
    · have empty : memory.chunk processed = [] := by simp only [chunk, ended, List.take_nil]
      have complete : memory.bytes = processed := by simpa only [ended, List.append_nil] using source
      refine ⟨middle, reads + 1, ?_, ?_, Nat.lt_succ_self _, effect⟩
      · apply executesWhileReturned (show Evaluates program before (.value (.boolean true)) (.boolean true) before from ⟨1, rfl⟩)
        simpa only [Memory.completion, empty, if_pos, complete] using iteration
      · simpa only [empty, List.append_nil, complete] using afterIteration
    · have positive := requestSize_bounds (memory.capacity - processed.length)
      have remainingPositive := List.length_pos_iff.mpr ended
      have nonempty : memory.chunk processed ≠ [] := by
        apply List.length_pos_iff.mp
        rw [chunk, List.length_take]
        exact Nat.lt_min.mpr ⟨positive.1, remainingPositive⟩
      have nextSource : memory.bytes = (processed ++ memory.chunk processed) ++
          remaining.drop (requestSize (memory.capacity - processed.length)) := by
        rw [chunk, List.append_assoc, List.take_append_drop]
        exact source
      have decreased : (remaining.drop (requestSize (memory.capacity - processed.length))).length < count := by
        simp only [List.length_drop]
        omega
      obtain ⟨after, finalReads, rest, done, moreReads, finalEffect⟩ := ih _ decreased afterIteration nextSource rfl
      refine ⟨after, finalReads, ?_, done, Nat.lt_trans (Nat.lt_succ_self _) moreReads, effect.trans finalEffect⟩
      apply executesWhileTrueThen (show Evaluates program before (.value (.boolean true)) (.boolean true) before from ⟨1, rfl⟩)
        (by simpa [Memory.completion, nonempty] using iteration) rest

end Lanius.Extraction.Input.File
