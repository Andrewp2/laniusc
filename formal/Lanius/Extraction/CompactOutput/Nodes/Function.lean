import Lanius.Extraction.CompactOutput.Nodes.Loop

namespace Lanius.Extraction.CompactOutput.Nodes.Function

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

structure Entry (state : State) where
  records : List RecordVisit
  words : List Int
  inputLength : Nat
  count : Nat
  inputCell : CellId
  offsetCell : CellId
  outputCell : CellId
  capacity : Nat
  position : Int
  contents : List Int
  inputRoom : words.length ≤ inputLength
  inputFit : inputLength ≤ 2147483647
  countFit : count ≤ 2147483647
  nodesFit : records.length ≤ 2147483647
  capacityFit : capacity ≤ 2147483647
  stored : ∀ record ∈ records, record.Stored 0 words
  fields : ∀ record ∈ records, record.production ≤ 2147483647 ∧ record.start ≤ 2147483647 ∧ record.finish ≤ 2147483647
  linked : ∀ (index : Nat) (record : RecordVisit), records[index]? = some record → ∀ child ∈ record.children, child.Linked 0 records index
  tokenBound : ∀ record ∈ records, ∀ child ∈ record.children, ∀ use, child = .token use → use.token < count
  distinctInput : outputCell ≠ inputCell
  distinctOffsets : outputCell ≠ offsetCell
  wellFormed : StateWellFormed state
  room : capacity ≤ contents.length
  input : I32PrefixLocal state 0 inputCell words
  offsets : I32PrefixLocal state 2 offsetCell (records.map (fun record => (record.offset : Int)))
  lengthRead : state.local? 1 = some (.signed .i32 inputLength)
  nodes : state.local? 3 = some (.signed .i32 records.length)
  countRead : state.local? 4 = some (.signed .i32 count)
  output : state.local? 5 = some (.slice i32 outputCell [] 0 contents.length)
  capacityRead : state.local? 6 = some (.signed .i32 capacity)
  positionRead : state.local? 7 = some (.signed .i32 position)
  backing : state.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values contents)) }

def Entry.memory (entry : Entry before) : Memory := {
  records := entry.records, words := entry.words, inputLength := entry.inputLength, count := entry.count
  inputCell := entry.inputCell, offsetCell := entry.offsetCell, outputCell := entry.outputCell
  cursorCell := before.nextCell, nodeCell := before.nextCell + 1, capacity := entry.capacity
  inputRoom := entry.inputRoom, inputFit := entry.inputFit, countFit := entry.countFit
  nodesFit := entry.nodesFit, capacityFit := entry.capacityFit, stored := entry.stored, fields := entry.fields
  linked := entry.linked, tokenBound := entry.tokenBound, distinctInput := entry.distinctInput
  distinctOffsets := entry.distinctOffsets, distinctLocals := Nat.ne_of_lt (Nat.lt_succ_self _) }

def Entry.entered (entry : Entry before) : State :=
  (before.bindLocal 8 (.signed .i32 entry.position)).bindLocal 9 (.signed .i32 0)

theorem Entry.invariant (entry : Entry before) :
    Owned entry.memory 0 entry.position entry.contents entry.entered := by
  let first := before.bindLocal 8 (.signed .i32 entry.position)
  have firstWF : StateWellFormed first := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have keep {id : VarId} {value : Value} (n8 : (8 : VarId) ≠ id) (n9 : (9 : VarId) ≠ id)
      (found : before.local? id = some value) : entry.entered.local? id = some value :=
    (bindLocal_preserves_other_local firstWF n9).trans
      ((bindLocal_preserves_other_local entry.wellFormed n8).trans found)
  have backingFirst := ((bindLocal_effect before 8 (.signed .i32 entry.position)).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing) (by simp [CellSet.empty])).trans entry.backing
  have inputFirst := entry.input.bindLocal entry.wellFormed 8 (.signed .i32 entry.position) (by decide)
  have offsetsFirst := entry.offsets.bindLocal entry.wellFormed 8 (.signed .i32 entry.position) (by decide)
  refine ⟨bindLocal_preserves_well_formed _ _ _ firstWF, Nat.zero_le _, entry.room,
    inputFirst.bindLocal firstWF 9 (.signed .i32 0) (by decide),
    offsetsFirst.bindLocal firstWF 9 (.signed .i32 0) (by decide),
    keep (by decide) (by decide) entry.lengthRead, keep (by decide) (by decide) entry.nodes,
    keep (by decide) (by decide) entry.countRead, keep (by decide) (by decide) entry.output,
    keep (by decide) (by decide) entry.capacityRead, ?_, ?_, ?_, ?_⟩
  · exact ((bindLocal_effect first 9 (.signed .i32 0)).oldCells entry.outputCell
      (StateWellFormed.cell_lt_next_of_entry firstWF backingFirst) (by simp [CellSet.empty])).trans backingFirst
  · exact bindLocal_preserves_localPointsTo_of_ne first 9 8 (.signed .i32 0) before.nextCell _ firstWF
      (by decide) (bindLocal_owns_fresh before 8 (.signed .i32 entry.position) entry.wellFormed)
  · exact bindLocal_owns_fresh first 9 (.signed .i32 0) firstWF
  · intro id member cell binding
    have n8 : (8 : VarId) ≠ id := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
    have n9 : (9 : VarId) ≠ id := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
    have oldBinding : before.cellId? id = some cell := by
      simpa only [entered, bindLocal_preserves_other_cellId _ 9 id _ n9,
        bindLocal_preserves_other_cellId _ 8 id _ n8] using binding
    have old := StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed oldBinding
    exact ⟨Nat.ne_of_lt old, Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _))⟩

theorem Entry.guard (entry : Entry before) (program : Program) :
    Evaluates program before entryGuard (.boolean false) before := by
  have nodes := Collect.lessEqual_evaluates (local_evaluates program entry.nodes) (negativeOne_evaluates program before)
  have count := Collect.lessEqual_evaluates (local_evaluates program entry.countRead) (negativeOne_evaluates program before)
  have all := evaluatesPureLogicalOr nodes count
  have nodesNonnegative : ¬ ((entry.records.length : Int) ≤ -1) := by omega
  have countNonnegative : ¬ ((entry.count : Int) ≤ -1) := by omega
  simpa only [entryGuard, Int.ofNat_eq_natCast, nodesNonnegative, countNonnegative, decide_false, Bool.false_or] using all

theorem Entry.execute (entry : Entry before) (word : Word.Checked program byte digit)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2) :
    ∃ after, Executes program.core before (body word.source.function.id tokenTag stateTag)
        (.returned (some (.signed .i32 (appendAll entry.capacity (encodeAll entry.records) entry.position entry.contents).position))) after ∧
      after.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values
          (appendAll entry.capacity (encodeAll entry.records) entry.position entry.contents).contents)) } ∧
      CellEffect (CellSet.singleton entry.outputCell) before after := by
  obtain ⟨completed, loopRun, backing, completedOwned, effect⟩ := execute_loop word tokenConstant stateConstant
    entry.records entry.invariant rfl
  let first := before.bindLocal 8 (.signed .i32 entry.position)
  have firstWF : StateWellFormed first := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have tailRun : Executes program.core entry.entered
      (.sequence (.whileLoop condition (step word.source.function.id tokenTag stateTag)) (returned (read 8)))
      (.returned (some (.signed .i32 (appendAll entry.capacity (encodeAll entry.records) entry.position entry.contents).position))) completed := by
    cases result : appendAll entry.capacity (encodeAll entry.records) entry.position entry.contents with
    | done position contents =>
      have owned : Owned entry.memory entry.records.length position contents completed := by
        simpa only [memory, result, Completed] using completedOwned
      have cursor := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.cursor)
      exact executesSequence (by simpa only [memory, result, AppendOutcome.completion] using loopRun)
        (executesSequenceReturned (executesReturnValue cursor))
    | full contents =>
      simp only [AppendOutcome.position]
      exact executesSequenceReturned (by simpa only [memory, result, AppendOutcome.completion] using loopRun)
  have run := executesSequence (executesIfFalse (thenBranch := returned negativeOne) (entry.guard program.core) (executesSkip _ _))
    (executesLetLocal (id := 8) (type := i32) (local_evaluates program.core entry.positionRead)
      (executesLetLocal (id := 9) (type := i32)
        (show Evaluates program.core first (number 0) (.signed .i32 0) first from ⟨1, rfl⟩) tailRun))
  have closed := CellEffect.closeLocal before 8 (.signed .i32 entry.position) entry.wellFormed
    (CellEffect.closeLocal first 9 (.signed .i32 0) firstWF effect)
  refine ⟨restoreLocals before completed, run, backing, closed.narrow ?_⟩
  intro cell old changed
  rcases changed with (output | cursor) | node
  · exact output
  · change cell = before.nextCell at cursor
    exact (Nat.ne_of_lt old cursor).elim
  · change cell = before.nextCell + 1 at node
    exact (Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _)) node).elim

end Lanius.Extraction.CompactOutput.Nodes.Function
