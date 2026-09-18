import Lanius.Extraction.Frontend.Capacity.Post

namespace Lanius.Extraction.Frontend
open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.Extraction.ParserTreeSource

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {visit : CheckedVisit program} {materializer : CheckedMaterialize visit}

/-- The real caller may provide a larger physical source buffer while passing
the logical file length separately. All internal executions and capacity
transport invariants are derived from ordinary caller-owned buffer data.
The exact logical frontend postcondition and the untouched physical source
tail are retained on every return branch. -/
theorem CheckedSyntax.padded_call_evaluates {tail : List Int} (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (fragment : Semantics.Capacity.Fragment.Checked program.core allowed)
    (included : allowed checked.source.function.id = true)
    (data : SyntaxData) (valid : data.Valid) (sourceGrammar : data.sourceCell ≠ data.grammarCell)
    (wellFormed : StateWellFormed before) (owned : data.PaddedOwns tail before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (data.paddedValues tail.length) before) :
    ∃ stage detail : Int, ∃ count nodes words : Nat, ∃ position : Int, ∃ after,
      Evaluates program.core caller (.call checked.source.function.id arguments)
        (syntaxResult checked.tail.finish.constructor.typeId stage detail data.raw.length count nodes words position) after ∧
      data.Post stage detail count nodes words position before after ∧ data.PaddedRawOutput tail after ∧
      CellEffect data.writes before after ∧
      Host.MemoryTail program.core before after := by
  let input := owned.input
  let callee := enterCall input.logical data.bindings
  have logicalWF := input.logical_wellFormed wellFormed
  have logicalOwned := owned.logical valid sourceGrammar wellFormed
  have locals : data.Locals callee := enterCall_parameterBindings_matches logicalWF
  obtain ⟨stage, detail, count, nodes, words, position, after, run, post, buffers, effect, path⟩ :=
    checked.body_executes linked data valid (enterCall_preserves_wellFormed logicalWF) locals (logicalOwned.entered logicalWF _)
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]; exact checked.source.found
  have bound : bindParameters checked.source.function.parameters data.values = some data.bindings := by
    rw [checked.signature.1]; rfl
  have expandedArguments : ArgumentsEvaluateTo program.core caller arguments (Semantics.Capacity.values input.config data.values) before := by
    simpa only [input, owned.argument_values valid sourceGrammar] using argumentsResult
  have evaluated := input.call wellFormed fragment included found checked.body bound owned.values_closed expandedArguments run
  have expandedPost := (post.closeCall logicalWF).expanded input.config rfl valid
  have expandedEffect := Semantics.Capacity.effect input.config (CellEffect.closeCall input.logical data.bindings logicalWF effect)
  have expandedBuffers := owned.raw_expanded valid effect.wellFormed buffers
  refine ⟨stage, detail, count, nodes, words, position, restoreLocals before (Semantics.Capacity.state input.config after), ?_, ?_, ?_, ?_, ?_⟩
  · simpa only [syntaxResult, Semantics.Capacity.value, Semantics.Capacity.values] using evaluated
  · simpa only [Semantics.Capacity.restore, input.restored wellFormed] using expandedPost
  · exact expandedBuffers
  · simpa only [Semantics.Capacity.restore, input.restored wellFormed] using expandedEffect
  · refine ⟨?_⟩
    intro final context store frame typed
    exact (path.closeCall input.logical data.bindings).ofMetadata rfl rfl rfl frame.heap frame.views typed

/-- Native memory is retained for the actual padded caller, not merely for its
shortened logical model. Final runtime typing follows from checked input
typing and the proved call; it is not an assumed postcondition. -/
theorem CheckedSyntax.padded_call_native {tail : List Int} {store : StoreTyping}
    (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (fragment : Semantics.Capacity.Fragment.Checked program.core allowed)
    (included : allowed checked.source.function.id = true)
    (data : SyntaxData) (valid : data.Valid) (sourceGrammar : data.sourceCell ≠ data.grammarCell)
    (typed : RuntimeStateHasType program.core context before store)
    (callTyped : Typing.ExprHasType program.core context (.call checked.source.function.id arguments) type)
    (owned : data.PaddedOwns tail before)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments (data.paddedValues tail.length) before) :
    ∃ stage detail : Int, ∃ count nodes words : Nat, ∃ position : Int, ∃ after,
      Evaluates program.core before (.call checked.source.function.id arguments)
        (syntaxResult checked.tail.finish.constructor.typeId stage detail data.raw.length count nodes words position) after ∧
      data.Post stage detail count nodes words position before after ∧ data.PaddedRawOutput tail after ∧
      CellEffect data.writes before after ∧ Host.MemoryFrame before after ∧
      ∃ afterStore, RuntimeStateHasType program.core context after afterStore := by
  obtain ⟨stage, detail, count, nodes, words, position, after, run, post, buffers, effect, memory⟩ :=
    checked.padded_call_evaluates linked fragment included data valid sourceGrammar typed.typed.wellFormed owned argumentsResult
  obtain ⟨afterStore, afterTyped⟩ := Host.checked_evaluation_type program callTyped typed run
  exact ⟨stage, detail, count, nodes, words, position, after, run, post, buffers, effect,
    memory.finish afterTyped, afterStore, afterTyped⟩

end Lanius.Extraction.Frontend
