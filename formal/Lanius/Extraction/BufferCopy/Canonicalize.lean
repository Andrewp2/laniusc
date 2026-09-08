import Lanius.Extraction.BufferCopy.Entry
import Lanius.Extraction.BufferCopy.Tokens
import Lanius.Extraction.CanonicalTokens.Compaction.Call
import Lanius.Extraction.RawLexer.LexInto.Spans
import Lanius.FunctionalViewCoreReadOnly

namespace Lanius.Extraction.BufferCopy

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction

/-- Execute the source's copy loop and canonicalizer call in their original
cursor scope. The continuation receives the canonical count as a bound local.
Destination capacity need only fit the emitted prefix, not the raw capacity. -/
theorem copy_then_canonicalize
    (checked : CheckedSource program functionId triviaId kindId keywordId matcher)
    (locals : Locals) (memory : Memory locals) (before : State) (entry : Entry memory before)
    (request : RawLexer.LexInto.Model.Request)
    (copiedValues : memory.values = encodeTokens (RawLexer.LexInto.Model.emittedTokens request.outcome))
    (rawCount : memory.count = (RawLexer.LexInto.Model.emittedTokens request.outcome).length)
    (sourceId : VarId) (sourceCell : CellId)
    (sourceLocal : before.local? sourceId = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 request.source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values (sourceIntegers request.source))) })
    (sourceDestination : sourceCell ≠ memory.destinationCell)
    (sourceNotCursor : locals.cursor ≠ sourceId) :
    let raw := RawLexer.LexInto.Model.emittedTokens request.outcome
    let tokens := canonicalizeTokens request.source raw
    let call := Expr.call functionId [.local sourceId, .local locals.destination, .local locals.count]
    ∃ after,
      (∀ resultId rest completion final,
        Executes program (after.bindLocal resultId (.signed .i32 tokens.length)) rest completion final →
        Executes program before
          (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
            (.sequence locals.loop (.letLocal resultId (.scalar (.signed .i32)) call rest)))
          completion (restoreLocals before (restoreLocals after final))) ∧
      after.cellEntry? memory.destinationCell = some {
        id := memory.destinationCell, value := some (.array (signedI32Values
          (compactedBuffer raw (memory.untouched.drop (3 * raw.length)) tokens))) } ∧
      after.cellEntry? sourceCell = some {
        id := sourceCell, value := some (.array (signedI32Values (sourceIntegers request.source))) } ∧
      CellEffect memory.writes (before.bindLocal locals.cursor (.signed .i32 0)) after := by
  dsimp only
  let raw := RawLexer.LexInto.Model.emittedTokens request.outcome
  have initial := entry.initialize
  obtain ⟨copied, loop, complete, copyEffect⟩ := executes_loop program locals memory [] memory.values
    (before.bindLocal locals.cursor (.signed .i32 0)) rfl initial
  have sourceOld := StateWellFormed.cell_lt_next_of_entry entry.wellFormed sourceContents
  have sourceCursor : sourceCell ≠ memory.cursorCell := by
    rw [entry.cursorFresh]
    exact Nat.ne_of_lt sourceOld
  have bindingEffect := bindLocal_effect before locals.cursor (.signed .i32 0)
  have sourceReady := (bindingEffect.oldCells sourceCell sourceOld (by simp [CellSet.empty])).trans sourceContents
  have sourceCopied := copyEffect.preserves_entry initial.wellFormed sourceReady
    (by simp [Memory.writes, CellSet.union, CellSet.singleton, sourceDestination, sourceCursor])
  have sourceLocalReady := (bindLocal_preserves_other_local entry.wellFormed sourceNotCursor
    (value := Value.signed .i32 0)).trans sourceLocal
  have sourceLocalCopied := copyEffect.preserves_local initial.wellFormed sourceLocalReady
    (entry.stable_local sourceLocal sourceNotCursor (by intro same; cases same))
  have recordsCopied : copied.cellEntry? memory.destinationCell = some {
      id := memory.destinationCell, value := some (.array (signedI32Values
        (encodeTokens raw ++ memory.untouched.drop (3 * raw.length)))) } := by
    simpa only [copiedValues, raw_buffer] using complete.destinationContents
  have capacity : 3 * raw.length ≤ memory.untouched.length := by
    simpa only [copiedValues, encoded_length] using memory.capacity
  have recordsLength : 3 * raw.length + (memory.untouched.drop (3 * raw.length)).length =
      memory.untouched.length := by simp only [List.length_drop]; omega
  have argumentsResult : ArgumentsEvaluateTo program copied
      [.local sourceId, .local locals.destination, .local locals.count]
      [.slice (.scalar (.signed .i32)) sourceCell [] 0 request.source.length,
       .slice (.scalar (.signed .i32)) memory.destinationCell [] 0 memory.untouched.length,
       .signed .i32 raw.length] copied := by
    exact .cons ⟨1, evalLocal_of_local 0 program copied sourceId _ sourceLocalCopied⟩
      (.cons ⟨1, evalLocal_of_local 0 program copied locals.destination _ complete.destinationLocal⟩
        (.singleton ⟨1, evalLocal_of_local 0 program copied locals.count _ (by simpa only [rawCount] using complete.count)⟩))
  obtain ⟨after, canonicalized, contents, canonicalEffect⟩ := checked.evaluates_call copied
    sourceCell memory.destinationCell request.source raw (memory.untouched.drop (3 * raw.length))
    _ complete.wellFormed sourceCopied recordsCopied sourceDestination
    (by have := request.sourceFitsI32; omega)
    (by rw [recordsLength]; exact memory.destinationFits)
    (RawLexer.LexInto.Model.emittedTokens_validSpans request.source request.capacity)
    (by simpa only [recordsLength] using argumentsResult)
  refine ⟨after, ?_, contents,
    canonicalEffect.preserves_entry complete.wellFormed sourceCopied sourceDestination,
    copyEffect.trans (canonicalEffect.weaken CellSet.subset_union_left)⟩
  intro resultId rest completion final tailRun
  have tailWithCount := executesLetLocal (type := .scalar (.signed .i32)) canonicalized tailRun
  exact executesLetLocal (show Evaluates program before (.value (.signed .i32 0))
      (.signed .i32 0) before from ⟨1, rfl⟩) (executesSequence loop tailWithCount)

/-- Construct the raw-copy entry directly from the lexer's emitted prefix and
ordinary caller storage. Spare raw words are not copied or interpreted as tokens.
The result retains the original raw buffer and the actual cursor scope. -/
theorem copy_emitted_then_canonicalize
    (checked : CheckedSource program functionId triviaId kindId keywordId matcher)
    (before : State) (request : RawLexer.LexInto.Model.Request)
    (records untouched : List Int)
    (sourceId rawId canonicalId cursorId countId : VarId)
    (sourceCell rawCell canonicalCell : CellId)
    (wellFormed : StateWellFormed before)
    (sourceRaw : sourceCell ≠ rawCell) (sourceCanonical : sourceCell ≠ canonicalCell)
    (rawCanonical : rawCell ≠ canonicalCell)
    (cursorDistinct : ∀ id ∈ [sourceId, rawId, canonicalId, countId], cursorId ≠ id)
    (recordsCapacity : 3 * request.capacity ≤ records.length)
    (recordsFits : records.length ≤ 2147483647) (canonicalFits : untouched.length ≤ 2147483647)
    (capacity : 3 * (RawLexer.LexInto.Model.emittedTokens request.outcome).length ≤ untouched.length)
    (sourceLocal : before.local? sourceId = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 request.source.length))
    (rawLocal : before.local? rawId = some
      (.slice (.scalar (.signed .i32)) rawCell [] 0 records.length))
    (canonicalLocal : before.local? canonicalId = some
      (.slice (.scalar (.signed .i32)) canonicalCell [] 0 untouched.length))
    (countLocal : before.local? countId = some
      (.signed .i32 (RawLexer.LexInto.Model.emittedTokens request.outcome).length))
    (owned : (FunctionalView.Core.ReadOnly.World.owns
      (FunctionalView.Core.ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
        (encodeTokens (RawLexer.LexInto.Model.emittedTokens request.outcome) ++
          records.drop (3 * (RawLexer.LexInto.Model.emittedTokens request.outcome).length)))).holds before)
    (canonicalContents : before.cellEntry? canonicalCell = some {
      id := canonicalCell, value := some (.array (signedI32Values untouched)) }) :
    let raw := RawLexer.LexInto.Model.emittedTokens request.outcome
    let tokens := canonicalizeTokens request.source raw
    let locals : Locals := ⟨rawId, canonicalId, cursorId, countId, .plain, .triple⟩
    ∃ after,
      (∀ resultId rest completion final,
        Executes program (after.bindLocal resultId (.signed .i32 tokens.length)) rest completion final →
        Executes program before
          (.letLocal cursorId (.scalar (.signed .i32)) (.value (.signed .i32 0))
            (.sequence locals.loop (.letLocal resultId (.scalar (.signed .i32))
              (.call functionId [.local sourceId, .local canonicalId, .local countId]) rest)))
          completion (restoreLocals before (restoreLocals after final))) ∧
      (FunctionalView.Core.ReadOnly.World.owns
        (FunctionalView.Core.ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
          (encodeTokens raw ++ records.drop (3 * raw.length)))).holds after ∧
      after.cellEntry? canonicalCell = some {
        id := canonicalCell, value := some (.array (signedI32Values
          (compactedBuffer raw (untouched.drop (3 * raw.length)) tokens))) } ∧
      CellEffect (CellSet.union (CellSet.singleton canonicalCell) (CellSet.singleton before.nextCell))
        (before.bindLocal cursorId (.signed .i32 0)) after := by
  dsimp only
  let raw := RawLexer.LexInto.Model.emittedTokens request.outcome
  let locals : Locals := ⟨rawId, canonicalId, cursorId, countId, .plain, .triple⟩
  have sourceContents := owned _ _ FunctionalView.Core.ReadOnly.World.pair_finds_first
  have rawContents := owned _ _ (FunctionalView.Core.ReadOnly.World.pair_finds_second (Ne.symm sourceRaw))
  have rawBound := RawLexer.LexInto.Model.emittedTokens_length_le_capacity request.source request.capacity
  have rawLength : (encodeTokens raw ++ records.drop (3 * raw.length)).length = records.length := by
    simp only [List.length_append, encoded_length, List.length_drop]
    change raw.length ≤ request.capacity at rawBound
    omega
  let memory : Memory locals := {
    sourceCell := rawCell, destinationCell := canonicalCell, cursorCell := before.nextCell,
    source := encodeTokens raw ++ records.drop (3 * raw.length),
    untouched, values := encodeTokens raw, count := raw.length,
    countLength := by simp only [locals, Scale.factor, encoded_length]; omega,
    selected := raw_selected raw _,
    capacity := by simpa only [encoded_length] using capacity,
    destinationFits := canonicalFits,
    sourceFits := by simpa only [rawLength] using recordsFits,
    source_destination := rawCanonical,
    source_cursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry wellFormed rawContents),
    destination_cursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry wellFormed canonicalContents)
  }
  have entry : Entry memory before := {
    wellFormed,
    sourceLocal := by simpa only [memory, locals, rawLength] using rawLocal,
    destinationLocal := canonicalLocal, sourceContents := rawContents,
    destinationContents := canonicalContents, count := countLocal,
    cursorDistinct := fun id member => cursorDistinct id (by simp_all [locals]),
    cursorFresh := rfl
  }
  obtain ⟨after, continuation, canonicalAfter, sourceAfter, effect⟩ :=
    copy_then_canonicalize checked locals memory before entry request rfl rfl sourceId sourceCell
      sourceLocal sourceContents sourceCanonical (cursorDistinct _ (by simp))
  have boundRaw := (bindLocal_effect before cursorId (.signed .i32 0)).oldCells rawCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed rawContents) (by simp [CellSet.empty])
  have rawAfter := effect.preserves_entry entry.initialize.wellFormed (boundRaw.trans rawContents)
    (by simp only [Memory.writes, memory, CellSet.union, CellSet.singleton, not_or];
        exact ⟨rawCanonical, memory.source_cursor⟩)
  refine ⟨after, continuation, ?_, canonicalAfter, effect⟩
  intro cell values found
  simp only [FunctionalView.Core.ReadOnly.World.pair] at found
  split at found
  · cases Option.some.inj found
    simp_all only
  · split at found
    · cases Option.some.inj found
      simp_all only
    · contradiction

end Lanius.Extraction.BufferCopy
