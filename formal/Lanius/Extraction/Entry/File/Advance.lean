import Lanius.Extraction.Entry.File.Emit.Reads

namespace Lanius.Extraction.Entry.File.Advance
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

def statement (argument : VarId) : Stmt :=
  .sequence (.expression (.assign .add (.local argument) (number 1))) .skip

def check? (source : Stmt) : Option (Source.CheckedStatement statement source) := do
  let .sequence (.expression (.assign .add (.local argument) _)) _ := source | none
  let same ← Equality.statement? source (statement argument)
  pure ⟨argument, same.equal⟩

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before ready collected middle : State}
variable {input : Load.Input pipeline before} {data : SyntaxData}

structure Relation (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage) (argument : VarId) : Prop where
  selected : argument = pipeline.path.argument
  loaded : argument ∉ pipeline.boundLocals
  result : syntaxStage.result ≠ argument
  nodes : argument ≠ resultsStage.nodes
  tokens : argument ≠ resultsStage.tokens

def checkRelation? (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage) (argument : VarId) :
    Option (PLift (Relation pipeline syntaxStage resultsStage argument)) :=
  if valid : argument = pipeline.path.argument ∧ argument ∉ pipeline.boundLocals ∧ syntaxStage.result ≠ argument ∧
      argument ≠ resultsStage.nodes ∧ argument ≠ resultsStage.tokens then
    some ⟨⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2.1, valid.2.2.2.2⟩⟩ else none

/-- Finish the actual file body. Recover the original argument cell through
all preceding scopes, protect it through collection/emission, and increment
that same cell. Cursor and output contents survive the increment unchanged. -/
theorem finishes {typeId : TypeId} {cursor : Int} {positionCell : CellId} {contents : List Int}
    (argument : VarId) (relation : Relation pipeline syntaxStage resultsStage argument)
    (emitStage : Emit.Stage) (emitRelation : Emit.Relation pipeline syntaxStage resultsStage collectStage emitStage)
    (observed : FrontendReturn input data) (buffers : Load.FrontendBuffers input data)
    (semantic output : SavedBuffer input)
    (semanticSeparate : ∀ cell ∈ data.bufferRoots, cell ≠ semantic.view.root)
    (outputSeparate : ∀ cell ∈ data.bufferRoots, cell ≠ output.view.root)
    (outputSemantic : output.view.root ≠ semantic.view.root)
    (differentCursors : before.cellId? argument ≠ before.cellId? emitStage.position)
    (bound : input.index + 1 ≤ 2147483647)
    (wellFormed : StateWellFormed ready)
    (scopeEffect : CellEffect CellSet.empty (observed.bound syntaxStage.result typeId)
      (restoreLocals (observed.bound syntaxStage.result typeId) ready))
    (bindings : ∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens →
      ready.cellId? id = (observed.bound syntaxStage.result typeId).cellId? id)
    (kept : ∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ∀ value,
      (observed.bound syntaxStage.result typeId).local? id = some value → ready.local? id = some value)
    (collectorEffect : CellEffect (CellSet.singleton semantic.view.root) ready collected)
    (positionOwned : (Assertion.localPointsTo emitStage.position positionCell (some (.signed .i32 cursor))).holds middle)
    (outputContents : middle.cellEntry? output.view.root = some { id := output.view.root, value := some (.array (signedI32Values contents)) })
    (emitterEffect : CellEffect (CellSet.union (CellSet.singleton output.view.root) (CellSet.singleton positionCell)) collected middle) :
    ∃ indexCell after, Executes program.core middle (statement argument) .next after ∧
      before.cellId? argument = some indexCell ∧ before.cellId? emitStage.position = some positionCell ∧
      (Assertion.localPointsTo argument indexCell (some (.signed .i32 (input.index + 1 : Nat)))).holds after ∧
      (Assertion.localPointsTo emitStage.position positionCell (some (.signed .i32 cursor))).holds after ∧
      after.cellEntry? output.view.root = some { id := output.view.root, value := some (.array (signedI32Values contents)) } ∧
      CellEffect (CellSet.singleton indexCell) middle after ∧ HeapFrame middle after := by
  have semanticUntouched : ¬ data.writes semantic.view.root := fun written => semanticSeparate _ (SyntaxData.writes_in_roots written) rfl
  have outputUntouched : ¬ data.writes output.view.root := fun written => outputSeparate _ (SyntaxData.writes_in_roots written) rfl
  have semanticReady := observed.saved_ready semantic semanticUntouched scopeEffect
  have outputCollected := collectorEffect.preserves_entry wellFormed (observed.saved_ready output outputUntouched scopeEffect) outputSemantic
  have originalRead : before.local? argument = some (.signed .i32 input.index) := relation.selected.symm ▸ input.indexRead
  have readyRead := observed.original_local buffers originalRead (by intro elements same; cases same) relation.loaded relation.result
    (kept _ relation.nodes relation.tokens _)
  have collectedRead := collectorEffect.preserves_local_of_distinct_value wellFormed readyRead semanticReady (by intro same; cases same)
  obtain ⟨indexCell, indexOwned⟩ := Assertion.exists_localPointsTo_of_local _ _ _ collectedRead
  have readyIndexBinding := observed.original_binding relation.loaded relation.result (bindings _ relation.nodes relation.tokens)
  have indexBinding : collected.cellId? argument = before.cellId? argument := by
    simpa only [State.cellId?, collectorEffect.locals] using readyIndexBinding
  have initialIndex : before.cellId? argument = some indexCell := indexBinding.symm.trans indexOwned.1
  obtain ⟨positionLoaded, positionResult, positionNodes, positionTokens⟩ :=
    emitRelation.carried emitStage.position (by simp [Emit.Stage.carriedLocals])
  have readyPositionBinding := observed.original_binding positionLoaded positionResult (bindings _ positionNodes positionTokens)
  have initialPosition : before.cellId? emitStage.position = some positionCell := by
    have current := positionOwned.1
    simp only [State.cellId?, emitterEffect.locals, collectorEffect.locals] at current
    exact readyPositionBinding.symm.trans current
  have apartPosition : indexCell ≠ positionCell := by
    intro same
    exact differentCursors (initialIndex.trans ((congrArg some same).trans initialPosition.symm))
  have apartOutput : indexCell ≠ output.view.root :=
    local_cell_ne_of_distinct_value collectedRead outputCollected (by intro same; cases same) indexOwned.1
  have middleIndex := emitterEffect.preserves_localPointsTo collectorEffect.wellFormed indexOwned
    (fun written => written.elim apartOutput apartPosition)
  obtain ⟨after, incremented, afterWF, afterIndex, modified⟩ := evaluatesIncrementOwnedI32Local program.core middle argument indexCell
    input.index emitterEffect.wellFormed middleIndex bound
  have effect := CellEffect.ofModifiesOnly modified afterWF
  exact ⟨indexCell, after, executesSequence (executesExpression incremented) (executesSkip _ _), initialIndex, initialPosition,
    afterIndex, effect.preserves_localPointsTo emitterEffect.wellFormed positionOwned apartPosition.symm,
    effect.preserves_entry emitterEffect.wellFormed outputContents apartOutput.symm, effect, HeapFrame.ofStoreEffect modified.toStoreEffect⟩

end Lanius.Extraction.Entry.File.Advance
