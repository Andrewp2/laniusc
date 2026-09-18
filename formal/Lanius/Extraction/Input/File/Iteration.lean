import Lanius.Extraction.Input.File.Unpack

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

def Memory.completion (memory : Memory) (processed : List UInt8) : Completion :=
  if memory.chunk processed = [] then .returned (some (.signed .i32 processed.length)) else .next

theorem ReadResult.close (result : ReadResult memory processed reads before middle)
    (valid : StateWellFormed before)
    (tailEffect : Host.Effect memory.writes
      (middle.bindLocal 9 (.signed .i32 (memory.chunk processed).length)) after) :
    Host.Effect memory.writes before (restoreLocals before after) := by
  have callEffect := result.effect.weaken (larger := memory.writes) (fun _ changed => Or.inl (Or.inr changed))
  have bodyEffect := tailEffect.closeLocal middle 9 _ result.registry.wellFormed
  have closed := (callEffect.trans bodyEffect).closeLocal before 8
    (.unsigned .usize (requestSize (memory.capacity - processed.length))) valid
  exact closed

/-- One complete read/count/unpack operation, including the final EOF
probe. The completion distinguishes EOF from a chunk that advances the loop. -/
theorem readStep (reader : Host.CheckedExternal program .read 3)
    (invariant : Buffers memory processed before)
    (request : before.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length))))
    (remaining : before.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))))
    (world : before.world = memory.worldAt processed.length reads)
    (sizeFit : 65536 < unsignedModulus program.target .usize)
    (fits : processed.length + (memory.chunk processed).length ≤ memory.capacity) :
    ∃ after, Executes program before (readChunk reader.function.id) (memory.completion processed) after ∧
      Invariant memory (processed ++ memory.chunk processed) (reads + 1) after ∧ Host.Effect memory.writes before after := by
  apply executesRead reader invariant request remaining world sizeFit (memory.completion processed)
    (fun after => Invariant memory (processed ++ memory.chunk processed) (reads + 1) after ∧ Host.Effect memory.writes before after)
  intro middle result
  let ready := middle.bindLocal 9 (.signed .i32 (memory.chunk processed).length)
  have buffers := result.toBuffers.bindTemporary 9 (.signed .i32 (memory.chunk processed).length) (by decide)
  have count := Assertion.localPointsTo_local _ _ _ _ (bindLocal_owns_fresh middle 9
    (.signed .i32 (memory.chunk processed).length) result.registry.wellFormed)
  have requestAt : ready.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length))) :=
    (bindLocal_preserves_other_local result.registry.wellFormed (show (9 : VarId) ≠ 6 by decide)).trans result.request
  have remainingAt : ready.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))) :=
    (bindLocal_preserves_other_local result.registry.wellFormed (show (9 : VarId) ≠ 7 by decide)).trans result.remaining
  have finish (after : State) (tailBuffers : Buffers memory (processed ++ memory.chunk processed) after)
      (tailEffect : ModifiesOnly memory.writes ready after) :
      Invariant memory (processed ++ memory.chunk processed) (reads + 1) (restoreLocals before after) ∧
        Host.Effect memory.writes before (restoreLocals before after) := by
    have closed := result.close invariant.registry.wellFormed (Host.Effect.ofPure tailEffect tailBuffers.registry.wellFormed)
    have registered := tailBuffers.registry.restoreLocals before closed.wellFormed
    have finished := invariant.finish closed registered tailBuffers.representable tailBuffers.total.2
      tailBuffers.outputContents tailBuffers.capacity
    exact ⟨⟨finished, by simpa only [List.length_append, restoreLocals] using tailEffect.world.trans result.world⟩, closed⟩
  by_cases empty : memory.chunk processed = []
  · have endRead := guards_eof program (requestSize (memory.capacity - processed.length)) processed.length
      (by simpa [ready, empty] using count) requestAt
      (Assertion.localPointsTo_local _ _ _ _ buffers.total)
    have completed := finish ready (by simpa [ready, empty] using buffers) (ModifiesOnly.reflAny _ _)
    exact ⟨ready, by simpa [Memory.completion, empty, ready] using endRead, completed⟩
  · have copied : Host.Copied memory.packed (memory.chunk processed) ready := by
      obtain ⟨words, raw, contents, rest⟩ := result.copied.storage
      exact ⟨words, raw, ((bindLocal_effect middle 9 (.signed .i32 (memory.chunk processed).length)).oldCells
        memory.packed.root (result.registry.root_lt_next result.packedMember) (by simp [CellSet.empty])).trans contents, rest⟩
    obtain ⟨after, unpacked, afterBuffers, effect⟩ := unpackChunk program buffers copied count fits
    have accepted := guards_continue program (memory.chunk processed).length
      (requestSize (memory.capacity - processed.length)) (memory.capacity - processed.length)
      count requestAt remainingAt (List.length_pos_iff.mpr empty) (List.length_take_le _ _) (by omega) unpacked
    exact ⟨after, by simpa [Memory.completion, empty] using accepted, finish after afterBuffers effect⟩

/-- The full source iteration: request declarations, bounded probe, host
read, count guards, unpacking, total update, and lexical-scope restoration. -/
theorem iterationStep (reader : Host.CheckedExternal program .read 3)
    (wordsFound : program.constant? words.id = some words) (wordsValue : words.value = .signed .i32 16384)
    (invariant : Invariant memory processed reads before)
    (sizeFit : 65536 < unsignedModulus program.target .usize)
    (fits : processed.length + (memory.chunk processed).length ≤ memory.capacity) :
    ∃ after, Executes program before (iteration reader.function.id words.id) (memory.completion processed) after ∧
      Invariant memory (processed ++ memory.chunk processed) (reads + 1) after ∧ Host.Effect memory.writes before after := by
  apply executesIteration program reader.function.id wordsFound wordsValue invariant.toBuffers (memory.completion processed)
    (fun after => Invariant memory (processed ++ memory.chunk processed) (reads + 1) after ∧ Host.Effect memory.writes before after)
  intro middle prepared
  obtain ⟨after, run, done, effect⟩ := readStep reader prepared.toBuffers prepared.request prepared.remaining
    (prepared.effect.world.trans invariant.world) sizeFit fits
  have closed := effect.closePrefix prepared.effect invariant.registry.wellFormed
  have buffers := invariant.toBuffers.finish closed (done.registry.restoreLocals before closed.wellFormed)
    done.representable done.total.2 done.outputContents done.capacity
  exact ⟨after, run, ⟨buffers, done.world⟩, closed⟩

end Lanius.Extraction.Input.File
