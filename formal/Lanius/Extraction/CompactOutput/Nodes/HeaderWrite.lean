import Lanius.Extraction.CompactOutput.Nodes.Header

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

structure HeaderMemory where
  record : RecordVisit
  words : List Int
  inputCell : CellId
  outputCell : CellId
  cursorCell : CellId
  capacity : Nat
  stored : record.Stored 0 words
  sizeFit : words.length ≤ 2147483647
  capacityFit : capacity ≤ 2147483647
  productionFit : record.production ≤ 2147483647
  startFit : record.start ≤ 2147483647
  finishFit : record.finish ≤ 2147483647
  distinctBuffers : outputCell ≠ inputCell

def HeaderMemory.writes (memory : HeaderMemory) : CellSet :=
  CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell)

structure HeaderOwned (memory : HeaderMemory) (position : Int) (contents : List Int) (state : State) : Prop where
  wellFormed : StateWellFormed state
  room : memory.capacity ≤ contents.length
  input : I32PrefixLocal state 0 memory.inputCell memory.words
  record : state.local? 10 = some (.signed .i32 memory.record.offset)
  production : state.local? 11 = some (.signed .i32 memory.record.production)
  children : state.local? 12 = some (.signed .i32 memory.record.children.length)
  output : state.local? 5 = some (.slice i32 memory.outputCell [] 0 contents.length)
  capacity : state.local? 6 = some (.signed .i32 memory.capacity)
  backing : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values contents)) }
  cursor : (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 position))).holds state
  stable : ∀ id ∈ [0, 5, 6, 10, 11, 12], ∀ cell, state.cellId? id = some cell → cell ≠ memory.cursorCell

theorem HeaderOwned.transition {nextCursor : Int}
    (owned : HeaderOwned memory position contents before)
    (effect : CellEffect memory.writes before after) (size : updated.length = contents.length)
    (backing : after.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values updated)) })
    (cursor : (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 nextCursor))).holds after) :
    HeaderOwned memory nextCursor updated after := by
  have keep {id : VarId} {value : Value} (member : id ∈ [0, 5, 6, 10, 11, 12])
      (found : before.local? id = some value) (different : value ≠ .array (signedI32Values contents)) :
      after.local? id = some value := by
    apply effect.preserves_local owned.wellFormed found
    intro cell binding changed
    rcases changed with output | cursor
    · exact local_cell_ne_of_distinct_value found owned.backing different binding output
    · exact owned.stable id member cell binding cursor
  have input : I32PrefixLocal after 0 memory.inputCell memory.words := by
    apply owned.input.transport
    · intro capacity found
      exact keep (by simp) found (by intro same; cases same)
    · intro stored found
      apply effect.preserves_entry owned.wellFormed found
      intro changed
      rcases changed with output | cursor
      · exact memory.distinctBuffers output.symm
      · obtain ⟨unused, _, old⟩ := owned.input.exists_unused
        rw [cursor, owned.cursor.2] at old
        cases old
  refine ⟨effect.wellFormed, by rw [size]; exact owned.room, input,
    keep (by simp) owned.record (by intro same; cases same),
    keep (by simp) owned.production (by intro same; cases same),
    keep (by simp) owned.children (by intro same; cases same), ?_,
    keep (by simp) owned.capacity (by intro same; cases same), backing, cursor, ?_⟩
  · simpa only [size] using keep (by simp) owned.output (by intro same; cases same)
  · intro id member cell binding
    exact owned.stable id member cell (by simpa only [State.cellId?, effect.locals] using binding)

theorem HeaderOwned.write (owned : HeaderOwned memory position contents before)
    (word : Word.Checked program byte digit) (value : Nat) (fit : value ≤ 2147483647)
    (readValue : Evaluates program.core before expression (.signed .i32 value) before) :
    ∃ after, Evaluates program.core before (headerWrite word.source.function.id expression) .unit after ∧
      HeaderOwned memory (appendAll memory.capacity (hexDigits value 8) position contents).position
        (appendAll memory.capacity (hexDigits value 8) position contents).contents after ∧
      CellEffect memory.writes before after := by
  obtain ⟨after, run, cursor, backing, effect⟩ := Word.assign_word word position memory.capacity value
    owned.wellFormed owned.room memory.capacityFit fit owned.cursor owned.backing
    (local_evaluates program.core owned.output) (local_evaluates program.core owned.capacity) readValue
  exact ⟨after, run, owned.transition effect (appendAll_length _ _ _ _) backing cursor, effect⟩

def encodeHeader (record : RecordVisit) : List Nat :=
  ((hexDigits record.production 8 ++ hexDigits record.start 8) ++ hexDigits record.finish 8) ++
    hexDigits record.children.length 8

theorem write_header (owned : HeaderOwned memory position contents before)
    (word : Word.Checked program byte digit) :
    ∃ first second third after,
      Evaluates program.core before (headerWrite word.source.function.id (read 11)) .unit first ∧
      Evaluates program.core first (headerWrite word.source.function.id (recordRead 1)) .unit second ∧
      Evaluates program.core second (headerWrite word.source.function.id (recordRead 2)) .unit third ∧
      Evaluates program.core third (headerWrite word.source.function.id (read 12)) .unit after ∧
      HeaderOwned memory (appendAll memory.capacity (encodeHeader memory.record) position contents).position
        (appendAll memory.capacity (encodeHeader memory.record) position contents).contents after ∧
      CellEffect memory.writes before after := by
  obtain ⟨first, firstRun, firstOwned, firstEffect⟩ := owned.write word _ memory.productionFit
    (local_evaluates program.core owned.production)
  have startRead := (read_header program.core memory.record firstOwned.input memory.stored firstOwned.record memory.sizeFit).2.1
  obtain ⟨second, secondRun, secondOwned, secondEffect⟩ := firstOwned.write word _ memory.startFit startRead
  have finishRead := (read_header program.core memory.record secondOwned.input memory.stored secondOwned.record memory.sizeFit).2.2.1
  obtain ⟨third, thirdRun, thirdOwned, thirdEffect⟩ := secondOwned.write word _ memory.finishFit finishRead
  have childrenFit : memory.record.children.length ≤ 2147483647 := by
    have := memory.stored.bounds
    have := memory.sizeFit
    omega
  obtain ⟨after, lastRun, lastOwned, lastEffect⟩ := thirdOwned.write word _ childrenFit
    (local_evaluates program.core thirdOwned.children)
  refine ⟨first, second, third, after, firstRun, secondRun, thirdRun, lastRun, ?_,
    ((firstEffect.trans secondEffect).trans thirdEffect).trans lastEffect⟩
  simpa only [encodeHeader, Word.appendAll_following_word] using lastOwned

end Lanius.Extraction.CompactOutput.Nodes
