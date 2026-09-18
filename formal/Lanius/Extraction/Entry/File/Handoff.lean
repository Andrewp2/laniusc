import Lanius.Extraction.Entry.File.Advance

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before ready collected middle after : State}
variable {input : Load.Input pipeline before} {data : SyntaxData}

/-- Source locals which are not shadowed inside a file iteration. Cell
aliasing with the two updated cursors is checked separately. -/
def Carried (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    (resultsStage : Results.Stage) (id : VarId) : Prop :=
  id ∉ pipeline.boundLocals ∧ syntaxStage.result ≠ id ∧
    id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens

def checkCarried? (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    (resultsStage : Results.Stage) (id : VarId) : Option (PLift (Carried pipeline syntaxStage resultsStage id)) :=
  if valid : id ∉ pipeline.boundLocals ∧ syntaxStage.result ≠ id ∧
      id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens then some ⟨valid⟩ else none

/-- Logical resources returned by a successful file iteration, in the
original caller scope. Borrowed views may have been added: this deliberately
does not assert heap or view-list identity. -/
structure Handoff (input : Load.Input pipeline before) (data : SyntaxData)
    (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage)
    (argument position : VarId) (after : State) : Prop where
  world : ∃ reads, 0 < reads ∧ after.world = input.loadedWorld reads
  grammar : after.cellEntry? data.grammarCell = some {
    id := data.grammarCell, value := some (.array (signedI32Values data.grammarWords)) }
  index : (restoreLocals before after).local? argument = some (.signed .i32 (input.index + 1 : Nat))
  locals : ∀ id value, Carried pipeline syntaxStage resultsStage id →
    before.local? id = some value → (∀ elements, value ≠ .array elements) →
    before.cellId? id ≠ before.cellId? argument → before.cellId? id ≠ before.cellId? position →
    (restoreLocals before after).local? id = some value
  cursor : ∃ cursor : Int, 0 ≤ cursor ∧
    (restoreLocals before after).local? position = some (.signed .i32 cursor)

theorem Handoff.restore (frame : Handoff input data syntaxStage resultsStage argument position after)
    (caller : State) : Handoff input data syntaxStage resultsStage argument position (restoreLocals caller after) :=
  ⟨frame.world, frame.grammar, frame.index, frame.locals, frame.cursor⟩

/-- Derive the next iteration's persistent resources from the actual
frontend, collector, emitter, and cursor-update effects. No preservation of
the whole file body is supplied as an extra premise. -/
theorem handoff {typeId : TypeId} {position cursor : Int} {indexCell positionCell : CellId}
    (argument : VarId) (advanceRelation : Advance.Relation pipeline syntaxStage resultsStage argument) (emitStage : Emit.Stage)
    (emitRelation : Emit.Relation pipeline syntaxStage resultsStage collectStage emitStage)
    (observed : FrontendReturn input data) (buffers : Load.FrontendBuffers input data) (valid : data.Valid)
    (semantic output : SavedBuffer input)
    (semanticSeparate : ∀ cell ∈ data.bufferRoots, cell ≠ semantic.view.root)
    (outputSeparate : ∀ cell ∈ data.bufferRoots, cell ≠ output.view.root)
    (outputSemantic : output.view.root ≠ semantic.view.root)
    (positionRead : before.local? emitStage.position = some (.signed .i32 position))
    (wellFormed : StateWellFormed ready)
    (scopeEffect : CellEffect CellSet.empty (observed.bound syntaxStage.result typeId)
      (restoreLocals (observed.bound syntaxStage.result typeId) ready))
    (bindings : ∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens →
      ready.cellId? id = (observed.bound syntaxStage.result typeId).cellId? id)
    (kept : ∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ∀ value,
      (observed.bound syntaxStage.result typeId).local? id = some value → ready.local? id = some value)
    (collectorEffect : CellEffect (CellSet.singleton semantic.view.root) ready collected)
    (emitterEffect : CellEffect (CellSet.union (CellSet.singleton output.view.root) (CellSet.singleton positionCell)) collected middle)
    (indexBinding : before.cellId? argument = some indexCell)
    (positionBinding : before.cellId? emitStage.position = some positionCell)
    (indexOwned : (Assertion.localPointsTo argument indexCell (some (.signed .i32 (input.index + 1 : Nat)))).holds after)
    (nonnegative : 0 ≤ cursor)
    (positionOwned : (Assertion.localPointsTo emitStage.position positionCell (some (.signed .i32 cursor))).holds after)
    (advanceEffect : CellEffect (CellSet.singleton indexCell) middle after) :
    Handoff input data syntaxStage resultsStage argument emitStage.position after := by
  have semanticUntouched : ¬ data.writes semantic.view.root :=
    fun written => semanticSeparate _ (SyntaxData.writes_in_roots written) rfl
  have outputUntouched : ¬ data.writes output.view.root :=
    fun written => outputSeparate _ (SyntaxData.writes_in_roots written) rfl
  have semanticReady := observed.saved_ready semantic semanticUntouched scopeEffect
  have outputCollected := collectorEffect.preserves_entry wellFormed
    (observed.saved_ready output outputUntouched scopeEffect) outputSemantic
  have originalRead {id : VarId} {value : Value} (carried : Carried pipeline syntaxStage resultsStage id)
      (found : before.local? id = some value) (notArray : ∀ elements, value ≠ .array elements) :
      collected.local? id = some value :=
    collectorEffect.preserves_local_of_distinct_value wellFormed
      (observed.original_local buffers found notArray carried.1 carried.2.1
        (kept _ carried.2.2.1 carried.2.2.2 _)) semanticReady (notArray _)
  have originalBinding {id : VarId} (carried : Carried pipeline syntaxStage resultsStage id) :
      collected.cellId? id = before.cellId? id := by
    simpa only [State.cellId?, collectorEffect.locals] using
      observed.original_binding carried.1 carried.2.1 (bindings _ carried.2.2.1 carried.2.2.2)
  have grammarMember : data.grammarCell ∈ data.bufferRoots := by
    simp [SyntaxData.bufferRoots, SyntaxData.buffers]
  have grammarCollected := collectorEffect.preserves_entry wellFormed
    (observed.grammar_ready buffers valid scopeEffect) (semanticSeparate _ grammarMember)
  have carriedPosition : Carried pipeline syntaxStage resultsStage emitStage.position :=
    emitRelation.carried _ (by simp [Emit.Stage.carriedLocals])
  have positionCollected := originalRead carriedPosition positionRead (by intro elements same; cases same)
  have positionGrammar : positionCell ≠ data.grammarCell :=
    local_cell_ne_of_distinct_value positionCollected grammarCollected (by intro same; cases same)
      ((originalBinding carriedPosition).trans positionBinding)
  have grammarMiddle := emitterEffect.preserves_entry collectorEffect.wellFormed grammarCollected
    (fun written => written.elim (outputSeparate _ grammarMember) positionGrammar.symm)
  have carriedArgument : Carried pipeline syntaxStage resultsStage argument :=
    ⟨advanceRelation.loaded, advanceRelation.result, advanceRelation.nodes, advanceRelation.tokens⟩
  have indexCollected := originalRead carriedArgument (advanceRelation.selected.symm ▸ input.indexRead)
    (by intro elements same; cases same)
  have indexGrammar : indexCell ≠ data.grammarCell :=
    local_cell_ne_of_distinct_value indexCollected grammarCollected (by intro same; cases same)
      ((originalBinding carriedArgument).trans indexBinding)
  refine ⟨?_, advanceEffect.preserves_entry emitterEffect.wellFormed grammarMiddle indexGrammar.symm, ?_, ?_, ?_⟩
  · obtain ⟨reads, positive, world⟩ := observed.loaded.world
    exact ⟨reads, positive, advanceEffect.world.trans (emitterEffect.world.trans
      (collectorEffect.world.trans ((observed.scopes scopeEffect).world.trans (observed.effect.world.trans world))))⟩
  · exact Assertion.localPointsTo_local _ _ _ _ ⟨indexBinding, indexOwned.2⟩
  · intro id value carried found notArray apartIndex apartPosition
    have read := originalRead carried found notArray
    have binding := originalBinding carried
    have middleRead := emitterEffect.preserves_local collectorEffect.wellFormed read (by
      intro cell cellBinding written
      rcases written with outputCell | cursorCell
      · exact local_cell_ne_of_distinct_value read outputCollected (notArray _) cellBinding outputCell
      · apply apartPosition
        exact binding.symm.trans (cellBinding.trans ((congrArg some cursorCell).trans positionBinding.symm)))
    have afterRead := advanceEffect.preserves_local emitterEffect.wellFormed middleRead (by
      intro cell cellBinding written
      apply apartIndex
      have same : middle.cellId? id = before.cellId? id := by
        simpa only [State.cellId?, emitterEffect.locals] using binding
      exact same.symm.trans (cellBinding.trans ((congrArg some written).trans indexBinding.symm)))
    have finalBinding : after.cellId? id = before.cellId? id := by
      simpa only [State.cellId?, advanceEffect.locals, emitterEffect.locals] using binding
    change ((before.cellId? id).bind after.cell?) = some value
    simpa only [State.local?, finalBinding] using afterRead
  · exact ⟨cursor, nonnegative, Assertion.localPointsTo_local _ _ _ _ ⟨positionBinding, positionOwned.2⟩⟩

end Lanius.Extraction.Entry.File
