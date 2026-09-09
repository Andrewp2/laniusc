import Lanius.Extraction.CompactOutput.Unit.Entry
import Lanius.Extraction.CompactOutput.Unit.Guard
import Lanius.Extraction.CompactOutput.Unit.Sequence
import Lanius.Extraction.CompactOutput.Unit.Transport

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Complete current unit-emitter body on valid inputs and a nonempty node
list, including the guard, initializer, every serializer, return, and scope
closure. Output capacity need not suffice: partial writes remain exact. -/
theorem Inputs.execute (inputs : Inputs before outputCell original.length)
    (word : Word.Checked program byte digit)
    (bytes : Bytes.Checked program byte digit hex)
    (tokens : Tokens.Checked program byte digit word)
    (semantic : Assignments.Checked program byte digit word)
    (nodes : Nodes.Checked program byte digit word tokenTag stateTag)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (wellFormed : StateWellFormed before) (position : Int)
    (positionRead : before.local? 18 = some (.signed .i32 position))
    (nonempty : 0 < inputs.nodes.records.length)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Executes program.core before
        (body ⟨word.source.function.id, bytes.source.function.id, tokens.source.function.id,
          semantic.source.function.id, nodes.source.function.id⟩)
        (.returned (some (.signed .i32 (appendAll inputs.capacity inputs.encoding position original).position))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll inputs.capacity inputs.encoding position original).contents)) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  have passed := guard_pass program.core inputs.path.values.length inputs.source.values.length
    inputs.nodes.records.length inputs.path.lengthRead inputs.source.lengthRead inputs.nodes.nodesRead nonempty
  obtain ⟨written, memory, firstRun, baseEqual, outputEqual, cursorEqual, positionEqual,
    contentsEqual, firstEffect, keep, preserve⟩ := initialize_cursor word inputs.path.values.length inputs.capacity position
      wellFormed inputs.path.lengthFit inputs.room inputs.capacityFit inputs.path.lengthRead
      inputs.outputRead inputs.capacityRead positionRead backing
  have lengthEqual : memory.initialContents.length = original.length := by
    rw [contentsEqual, appendAll_length]
  let enteredInputs := inputs.transport outputEqual lengthEqual original keep preserve
  obtain ⟨completed, tailRun, output, tailEffect⟩ := enteredInputs.execute_tail memory.owned
    word bytes tokens semantic nodes tokenConstant stateConstant
  have sequenceRun : Executes program.core memory.base
      (tail ⟨word.source.function.id, bytes.source.function.id, tokens.source.function.id,
        semantic.source.function.id, nodes.source.function.id⟩)
      (.returned (some (.signed .i32
        (appendAll inputs.capacity inputs.tailEncoding memory.initialPosition memory.initialContents).position))) completed := tailRun
  have outputResult : completed.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values
        (appendAll inputs.capacity inputs.tailEncoding memory.initialPosition memory.initialContents).contents)) } := output
  rw [baseEqual, positionEqual, contentsEqual] at sequenceRun
  rw [outputEqual, positionEqual, contentsEqual] at outputResult
  have combined := following_chunk inputs.capacity (hexDigits inputs.path.values.length 8) inputs.tailEncoding position original
  rw [← combined.1] at sequenceRun
  rw [← combined.2] at outputResult
  have run := executesSequence (executesIfFalse (thenBranch := returned negativeOne) passed (executesSkip _ _))
    (executesLetLocal (id := 19) (type := i32) firstRun sequenceRun)
  rw [baseEqual] at tailEffect
  have closed := CellEffect.closeLocal written 19 (.signed .i32 memory.initialPosition) firstEffect.wellFormed tailEffect
  have narrowed : CellEffect (CellSet.singleton outputCell) written (restoreLocals written completed) := closed.narrow (by
    intro cell old changed
    rcases changed with output | cursor
    · exact output.trans outputEqual
    · exact (Nat.ne_of_lt old (cursor.trans cursorEqual)).elim)
  exact ⟨restoreLocals written completed, run, outputResult, firstEffect.trans narrowed⟩

end Lanius.Extraction.CompactOutput.Unit
