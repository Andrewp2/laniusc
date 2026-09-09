import Lanius.Extraction.CompactOutput.Unit.Function

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- Public execution from evaluated arguments and their bound input layout.
The input contract describes the parameter state, not a presumed body run. -/
theorem Checked.write
    (word : Word.Checked program byte digit)
    (bytes : Bytes.Checked program byte digit hex)
    (tokens : Tokens.Checked program byte digit word)
    (semantic : Assignments.Checked program byte digit word)
    (nodes : Nodes.Checked program byte digit word tokenTag stateTag)
    (checked : Checked program ⟨word.source.function.id, bytes.source.function.id,
      tokens.source.function.id, semantic.source.function.id, nodes.source.function.id⟩)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments values before)
    (bound : bindParameters parameters values = some bindings)
    (inputs : Inputs (enterCall before bindings) outputCell original.length)
    (position : Int)
    (positionRead : (enterCall before bindings).local? 18 = some (.signed .i32 position))
    (nonempty : 0 < inputs.nodes.records.length)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (appendAll inputs.capacity inputs.encoding position original).position) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll inputs.capacity inputs.encoding position original).contents)) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  have calleeBacking := ((enterCall_effect before bindings).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, run, output, effect⟩ := inputs.execute word bytes tokens semantic nodes
    tokenConstant stateConstant (enterCall_preserves_wellFormed wellFormed)
    position positionRead nonempty calleeBacking
  have called := checked.call wellFormed argumentsResult bound run effect
  exact ⟨restoreLocals before completed, called.1, output, called.2⟩

end Lanius.Extraction.CompactOutput.Unit
