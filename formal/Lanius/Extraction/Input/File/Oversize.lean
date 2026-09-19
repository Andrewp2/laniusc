import Lanius.Extraction.Input.File.Loop

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

/-- An overflowing read changes scratch and advances the host offset, but
does not unpack any of that chunk or advance the stored output total. -/
theorem readOversized (reader : Host.CheckedExternal program .read 3)
    (invariant : Buffers memory processed before)
    (request : before.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length))))
    (remaining : before.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))))
    (world : before.world = memory.worldAt processed.length reads)
    (sizeFit : 65536 < unsignedModulus program.target .usize)
    (oversize : memory.capacity < processed.length + (memory.chunk processed).length) :
    ∃ after, Executes program before (readChunk reader.function.id) (.returned (some (.signed .i32 (-2)))) after ∧
      Buffers memory processed after ∧
      after.world = memory.worldAt (processed.length + (memory.chunk processed).length) (reads + 1) ∧
      Host.Effect memory.writes before after := by
  apply executesRead reader invariant request remaining world sizeFit (.returned (some (.signed .i32 (-2))))
    (fun after => Buffers memory processed after ∧
      after.world = memory.worldAt (processed.length + (memory.chunk processed).length) (reads + 1) ∧
      Host.Effect memory.writes before after)
  intro middle result
  let ready := middle.bindLocal 9 (.signed .i32 (memory.chunk processed).length)
  have buffers := result.toBuffers.bindTemporary 9 (.signed .i32 (memory.chunk processed).length) (by decide)
  have count := Assertion.localPointsTo_local _ _ _ _ (bindLocal_owns_fresh middle 9
    (.signed .i32 (memory.chunk processed).length) result.registry.wellFormed)
  have requestAt : ready.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length))) :=
    (bindLocal_preserves_other_local result.registry.wellFormed (show (9 : VarId) ≠ 6 by decide)).trans result.request
  have remainingAt : ready.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))) :=
    (bindLocal_preserves_other_local result.registry.wellFormed (show (9 : VarId) ≠ 7 by decide)).trans result.remaining
  have rejected := guards_overflow program (memory.chunk processed).length
    (requestSize (memory.capacity - processed.length)) (memory.capacity - processed.length)
    count requestAt remainingAt (List.length_take_le _ _) (by have := invariant.capacity; omega)
  have closed := result.close invariant.registry.wellFormed
    (Host.Effect.ofPure (ModifiesOnly.reflAny memory.writes ready) buffers.registry.wellFormed)
  have restored := buffers.registry.restoreLocals before closed.wellFormed
  exact ⟨ready, rejected, invariant.finish closed restored buffers.representable buffers.total.2
    buffers.outputContents buffers.capacity, result.world, closed⟩

theorem iterationOversized (reader : Host.CheckedExternal program .read 3)
    (wordsFound : program.constant? words.id = some words) (wordsValue : words.value = .signed .i32 16384)
    (invariant : Invariant memory processed reads before)
    (sizeFit : 65536 < unsignedModulus program.target .usize)
    (oversize : memory.capacity < processed.length + (memory.chunk processed).length) :
    ∃ after, Executes program before (iteration reader.function.id words.id) (.returned (some (.signed .i32 (-2)))) after ∧
      Buffers memory processed after ∧
      after.world = memory.worldAt (processed.length + (memory.chunk processed).length) (reads + 1) ∧
      Host.Effect memory.writes before after := by
  apply executesIteration program reader.function.id wordsFound wordsValue invariant.toBuffers
    (.returned (some (.signed .i32 (-2)))) (fun after => Buffers memory processed after ∧
      after.world = memory.worldAt (processed.length + (memory.chunk processed).length) (reads + 1) ∧
      Host.Effect memory.writes before after)
  intro middle prepared
  obtain ⟨after, run, done, world, effect⟩ := readOversized reader prepared.toBuffers prepared.request prepared.remaining
    (prepared.effect.world.trans invariant.world) sizeFit oversize
  have closed := effect.closePrefix prepared.effect invariant.registry.wellFormed
  have buffers := invariant.toBuffers.finish closed (done.registry.restoreLocals before closed.wellFormed)
    done.representable done.total.2 done.outputContents done.capacity
  exact ⟨after, run, buffers, world, closed⟩

/-- Every oversized file terminates with -2 after consuming exactly capacity
plus one bytes. Earlier complete chunks remain a bounded source prefix; the
overflowing chunk is never copied. This includes arbitrarily many chunks. -/
theorem rejectsLoop (reader : Host.CheckedExternal program .read 3)
    (wordsFound : program.constant? words.id = some words) (wordsValue : words.value = .signed .i32 16384)
    (invariant : Invariant memory processed reads before)
    (source : memory.bytes = processed ++ remaining)
    (oversize : memory.capacity < memory.bytes.length)
    (sizeFit : 65536 < unsignedModulus program.target .usize) :
    ∃ after copied finalReads, Executes program before (loop reader.function.id words.id)
        (.returned (some (.signed .i32 (-2)))) after ∧
      Buffers memory copied after ∧ copied.IsPrefix memory.bytes ∧
      after.world = memory.worldAt (memory.capacity + 1) finalReads ∧
      reads < finalReads ∧ Host.Effect memory.writes before after := by
  generalize size : remaining.length = count
  induction count using Nat.strongRecOn generalizing processed remaining before reads with
  | ind count ih =>
    by_cases fits : processed.length + (memory.chunk processed).length ≤ memory.capacity
    · have chunk := memory.chunk_of_suffix source
      have totalLength : memory.bytes.length = processed.length + remaining.length := by simp only [source, List.length_append]
      have positive := requestSize_bounds (memory.capacity - processed.length)
      have nonempty : memory.chunk processed ≠ [] := by
        apply List.length_pos_iff.mp
        rw [chunk, List.length_take]
        exact Nat.lt_min.mpr ⟨positive.1, by have := invariant.capacity; omega⟩
      obtain ⟨middle, iteration, afterIteration, effect⟩ := iterationStep reader wordsFound wordsValue invariant sizeFit fits
      have nextSource : memory.bytes = (processed ++ memory.chunk processed) ++
          remaining.drop (requestSize (memory.capacity - processed.length)) := by
        rw [chunk, List.append_assoc, List.take_append_drop]
        exact source
      have decreased : (remaining.drop (requestSize (memory.capacity - processed.length))).length < count := by
        simp only [List.length_drop]
        have := invariant.capacity
        omega
      obtain ⟨after, copied, finalReads, rest, done, sourcePrefix, world, moreReads, finalEffect⟩ :=
        ih _ decreased afterIteration nextSource rfl
      refine ⟨after, copied, finalReads, ?_, done, sourcePrefix, world,
        Nat.lt_trans (Nat.lt_succ_self _) moreReads, effect.trans finalEffect⟩
      exact executesWhileTrueThen Lanius.Semantics.evaluatesValue (by simpa [Memory.completion, nonempty] using iteration) rest
    · have consumed : processed.length + (memory.chunk processed).length = memory.capacity + 1 := by
        have chunkBound : (memory.chunk processed).length ≤ requestSize (memory.capacity - processed.length) := List.length_take_le _ _
        have := (requestSize_bounds (memory.capacity - processed.length)).2.2
        have := invariant.capacity
        omega
      obtain ⟨after, run, done, world, effect⟩ := iterationOversized reader wordsFound wordsValue invariant sizeFit (by omega)
      exact ⟨after, processed, reads + 1, executesWhileReturned Lanius.Semantics.evaluatesValue run, done, ⟨remaining, source.symm⟩,
        by simpa only [consumed] using world, Nat.lt_succ_self _, effect⟩

/-- The common loop boundary for fitting and oversized inputs. Both cases
retain exact host consumption and a safe source prefix in the output buffer. -/
theorem runsLoop (reader : Host.CheckedExternal program .read 3)
    (wordsFound : program.constant? words.id = some words) (wordsValue : words.value = .signed .i32 16384)
    (invariant : Invariant memory [] 0 before)
    (sizeFit : 65536 < unsignedModulus program.target .usize) :
    ∃ after copied reads, Executes program before (loop reader.function.id words.id)
        (.returned (some (.signed .i32 memory.toResources.result))) after ∧
      Buffers memory copied after ∧ copied.IsPrefix memory.bytes ∧
      (memory.bytes.length ≤ memory.capacity → copied = memory.bytes) ∧
      0 < reads ∧ after.world = memory.toResources.finalWorld reads ∧ Host.Effect memory.writes before after := by
  by_cases fits : memory.bytes.length ≤ memory.capacity
  · obtain ⟨after, reads, run, done, positive, effect⟩ := completesLoop reader wordsFound wordsValue invariant rfl fits sizeFit
    refine ⟨after, memory.bytes, reads, ?_, done.toBuffers, ⟨[], List.append_nil _⟩, fun _ => rfl, positive, ?_, effect⟩
    · change Executes program before (loop reader.function.id words.id)
        (.returned (some (.signed .i32 (if memory.bytes.length ≤ memory.capacity then memory.bytes.length else -2)))) after
      rw [if_pos fits]
      exact run
    · have consumed : memory.toResources.consumed = memory.bytes.length := by
        change min memory.bytes.length (memory.capacity + 1) = memory.bytes.length
        exact Nat.min_eq_left (by omega)
      simpa only [Resources.finalWorld, consumed, Memory.worldAt] using done.world
  · obtain ⟨after, copied, reads, run, done, sourcePrefix, world, positive, effect⟩ :=
      rejectsLoop reader wordsFound wordsValue invariant rfl (by omega) sizeFit
    refine ⟨after, copied, reads, ?_, done, sourcePrefix, fun impossible => False.elim (fits impossible), positive, ?_, effect⟩
    · change Executes program before (loop reader.function.id words.id)
        (.returned (some (.signed .i32 (if memory.bytes.length ≤ memory.capacity then memory.bytes.length else -2)))) after
      rw [if_neg fits]
      exact run
    · have consumed : memory.toResources.consumed = memory.capacity + 1 := by
        change min memory.bytes.length (memory.capacity + 1) = memory.capacity + 1
        exact Nat.min_eq_right (by omega)
      simpa only [Resources.finalWorld, consumed, Memory.worldAt] using world

end Lanius.Extraction.Input.File
