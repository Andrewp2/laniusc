import Lanius.Extraction.Frontend.Result
import Lanius.Extraction.Entry.Scope
import Lanius.Extraction.CompactOutput.Byte
import Lanius.Extraction.Source.Statement
import Lanius.Extraction.Source.Stops
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Entry.File.Results
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

structure Accessors (program : CoreSynthesis.Program.CheckedProgram artifacts) (typeId : TypeId) where
  status : Source.CheckedProjection program ["verified", "extraction"] "extraction_stage" typeId 0
  nodes : Source.CheckedProjection program ["verified", "extraction"] "node_count" typeId 4
  tokens : Source.CheckedProjection program ["verified", "extraction"] "token_count" typeId 3

def checkAccessors? (program : CoreSynthesis.Program.CheckedProgram artifacts) (typeId : TypeId) :
    Option (Accessors program typeId) := do
  let status ← Source.checkProjection? program ["verified", "extraction"] "extraction_stage" typeId 0
  let nodes ← Source.checkProjection? program ["verified", "extraction"] "node_count" typeId 4
  let tokens ← Source.checkProjection? program ["verified", "extraction"] "token_count" typeId 3
  pure ⟨status, nodes, tokens⟩

structure Stage where
  result : VarId
  nodes : VarId
  tokens : VarId
  failure : Stmt
  continuation : Stmt

def Stage.statement (stage : Stage) (status nodes tokens : FunctionId) : Stmt :=
  .sequence (.ifThenElse (binary .notEqual (.call status [read stage.result]) (number 0)) stage.failure .skip)
    (.letLocal stage.nodes i32 (.call nodes [read stage.result])
      (.letLocal stage.tokens i32 (.call tokens [read stage.result]) stage.continuation))

def check? (status nodes tokens : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun stage : Stage => stage.statement status nodes tokens) statement) := do
  let .sequence (.ifThenElse (.binary .notEqual (.call _ [.local result]) _) failure _)
    (.letLocal nodesLocal _ _ (.letLocal tokensLocal _ _ continuation)) := statement | none
  let stage : Stage := ⟨result, nodesLocal, tokensLocal, failure, continuation⟩
  let same ← Equality.statement? statement (stage.statement status nodes tokens)
  pure ⟨stage, same.equal⟩

structure Stage.Supported (stage : Stage) : Prop where
  nodeResult : stage.nodes ≠ stage.result
  tokenResult : stage.tokens ≠ stage.result
  tokenNode : stage.tokens ≠ stage.nodes
  failureStops : Source.CheckedStop stage.failure

def Stage.checkSupported? (stage : Stage) : Option (PLift stage.Supported) := do
  let stopped ← Source.checkStop? stage.failure
  if valid : stage.nodes ≠ stage.result ∧ stage.tokens ≠ stage.result ∧ stage.tokens ≠ stage.nodes then
    some ⟨⟨valid.1, valid.2.1, valid.2.2, stopped.down⟩⟩ else none

/-- Run the actual success guard and both count accessors. Each accessor's
fresh call cells and the caller's new local bindings are retained; all old
buffers and all non-shadowed locals are preserved for collection/emission. -/
theorem Stage.success {detail raw count nodes words position : Int}
    (stage : Stage) (supported : stage.Supported) (accessors : Accessors program typeId)
    (wellFormed : StateWellFormed before)
    (resultRead : before.local? stage.result = some (syntaxResult typeId 0 detail raw count nodes words position))
    (post : Scope.Post)
    (continuationRun : ∀ ready, StateWellFormed ready →
      CellEffect CellSet.empty before (restoreLocals before ready) →
      HeapFrame before ready →
      ready.local? stage.nodes = some (.signed .i32 nodes) → ready.local? stage.tokens = some (.signed .i32 count) →
      (∀ id, id ≠ stage.nodes → id ≠ stage.tokens → ready.cellId? id = before.cellId? id) →
      (∀ id, id ≠ stage.nodes → id ≠ stage.tokens → ∀ value, before.local? id = some value → ready.local? id = some value) →
      ∃ completion after, Executes program.core ready stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before
      (stage.statement accessors.status.source.function.id accessors.nodes.source.function.id accessors.tokens.source.function.id)
      completion after ∧ post completion after := by
  obtain ⟨guarded, statusCall, statusEffect, statusHeap⟩ := accessors.status.call wellFormed
    (.cons (local_evaluates program.core resultRead) (.nil _ _)) (by rfl)
  have guard : Evaluates program.core before
      (binary .notEqual (.call accessors.status.source.function.id [read stage.result]) (number 0)) (.boolean false) guarded :=
    evaluatesEagerBinary (by decide) (by decide) statusCall
      (show Evaluates program.core guarded (number 0) (.signed .i32 0) guarded from evaluatesValue) rfl
  have guardedResult := statusEffect.empty_preserves_local wellFormed resultRead
  obtain ⟨nodeCalled, nodeCall, nodeEffect, nodeHeap⟩ := accessors.nodes.call statusEffect.wellFormed
    (.cons (local_evaluates program.core guardedResult) (.nil _ _)) (by rfl)
  let nodeBound := nodeCalled.bindLocal stage.nodes (.signed .i32 nodes)
  have nodeBoundWF : StateWellFormed nodeBound := bindLocal_preserves_well_formed _ _ _ nodeEffect.wellFormed
  have nodeRead : nodeBound.local? stage.nodes = some (.signed .i32 nodes) := bindLocal_finds_local _ _ _ nodeEffect.wellFormed
  have nodeResult : nodeBound.local? stage.result = some (syntaxResult typeId 0 detail raw count nodes words position) :=
    (bindLocal_preserves_other_local nodeEffect.wellFormed supported.nodeResult).trans
      (nodeEffect.empty_preserves_local statusEffect.wellFormed guardedResult)
  obtain ⟨tokenCalled, tokenCall, tokenEffect, tokenHeap⟩ := accessors.tokens.call nodeBoundWF
    (.cons (local_evaluates program.core nodeResult) (.nil _ _)) (by rfl)
  let ready := tokenCalled.bindLocal stage.tokens (.signed .i32 count)
  have readyWF : StateWellFormed ready := bindLocal_preserves_well_formed _ _ _ tokenEffect.wellFormed
  have readyTokens : ready.local? stage.tokens = some (.signed .i32 count) := bindLocal_finds_local _ _ _ tokenEffect.wellFormed
  have readyNodes : ready.local? stage.nodes = some (.signed .i32 nodes) :=
    (bindLocal_preserves_other_local tokenEffect.wellFormed supported.tokenNode).trans
      (tokenEffect.empty_preserves_local nodeBoundWF nodeRead)
  have throughNodes := (Scope.called (statusEffect.trans nodeEffect) wellFormed).transScoped
    (Scope.bound nodeCalled stage.nodes (.signed .i32 nodes) nodeEffect.wellFormed) wellFormed
  have throughTokens := throughNodes.transScoped (Scope.called tokenEffect nodeBoundWF) wellFormed
  have effect : CellEffect CellSet.empty before (restoreLocals before ready) := throughTokens.transScoped
    (Scope.bound tokenCalled stage.tokens (.signed .i32 count) tokenEffect.wellFormed) wellFormed
  have kept (id : VarId) (notNode : id ≠ stage.nodes) (notToken : id ≠ stage.tokens)
      (value : Value) (found : before.local? id = some value) : ready.local? id = some value := by
    apply (bindLocal_preserves_other_local tokenEffect.wellFormed notToken.symm).trans
    apply tokenEffect.empty_preserves_local nodeBoundWF
    apply (bindLocal_preserves_other_local nodeEffect.wellFormed notNode.symm).trans
    exact (statusEffect.trans nodeEffect).empty_preserves_local wellFormed found
  have bindings (id : VarId) (notNode : id ≠ stage.nodes) (notToken : id ≠ stage.tokens) : ready.cellId? id = before.cellId? id := by
    rw [show ready.cellId? id = tokenCalled.cellId? id from bindLocal_preserves_other_cellId tokenCalled stage.tokens id _ notToken.symm]
    simp only [State.cellId?, tokenEffect.locals]
    change nodeBound.cellId? id = before.cellId? id
    rw [show nodeBound.cellId? id = nodeCalled.cellId? id from bindLocal_preserves_other_cellId nodeCalled stage.nodes id _ notNode.symm]
    simp only [State.cellId?, nodeEffect.locals, statusEffect.locals]
  have heap : HeapFrame before ready := (statusHeap.trans nodeHeap).trans
    ((show HeapFrame nodeCalled nodeBound from ⟨rfl, rfl⟩).trans
      (tokenHeap.trans (show HeapFrame tokenCalled ready from ⟨rfl, rfl⟩)))
  obtain ⟨completion, after, continued, done⟩ := continuationRun ready readyWF effect heap readyNodes readyTokens bindings kept
  exact ⟨completion, restoreLocals nodeCalled (restoreLocals tokenCalled after),
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesLetLocal nodeCall (executesLetLocal tokenCall continued)),
    post.restore completion nodeCalled _ (post.restore completion tokenCalled after done)⟩

/-- Dispatch on the actual status accessor. Failure executes only the checked
diagnostic branch; non-fallthrough follows from its source certificate rather
than a caller premise. Success executes both count bindings. The remaining
premises concern those two downstream executions, not the guard or accessors. -/
theorem Stage.dispatch {status detail raw count nodes words position : Int}
    (stage : Stage) (supported : stage.Supported) (accessors : Accessors program typeId)
    (wellFormed : StateWellFormed before)
    (resultRead : before.local? stage.result = some (syntaxResult typeId status detail raw count nodes words position))
    (post : Scope.Post)
    (failureRun : status ≠ 0 → ∀ guarded, CellEffect CellSet.empty before guarded →
      HeapFrame before guarded →
      Prefix.Reaches program.core before
        (stage.statement accessors.status.source.function.id accessors.nodes.source.function.id accessors.tokens.source.function.id)
        guarded stage.failure →
      ∃ completion after, Executes program.core guarded stage.failure completion after ∧ post completion after)
    (continuationRun : status = 0 → ∀ ready, StateWellFormed ready →
      CellEffect CellSet.empty before (restoreLocals before ready) →
      HeapFrame before ready →
      ready.local? stage.nodes = some (.signed .i32 nodes) → ready.local? stage.tokens = some (.signed .i32 count) →
      (∀ id, id ≠ stage.nodes → id ≠ stage.tokens → ready.cellId? id = before.cellId? id) →
      (∀ id, id ≠ stage.nodes → id ≠ stage.tokens → ∀ value, before.local? id = some value → ready.local? id = some value) →
      ∃ completion after, Executes program.core ready stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before
      (stage.statement accessors.status.source.function.id accessors.nodes.source.function.id accessors.tokens.source.function.id)
      completion after ∧ post completion after := by
  by_cases success : status = 0
  · subst status
    exact stage.success supported accessors wellFormed resultRead post (continuationRun rfl)
  · obtain ⟨guarded, statusCall, effect, heap⟩ := accessors.status.call wellFormed
      (.cons (local_evaluates program.core resultRead) (.nil _ _)) (by rfl)
    have guard : Evaluates program.core before
        (binary .notEqual (.call accessors.status.source.function.id [read stage.result]) (number 0)) (.boolean true) guarded :=
      evaluatesEagerBinary (by decide) (by decide) statusCall
        (show Evaluates program.core guarded (number 0) (.signed .i32 0) guarded from evaluatesValue)
        (by simp [evalBinaryValue, scalarEqual, success])
    obtain ⟨completion, after, failed, done⟩ := failureRun success guarded effect heap
      (.sequenceHead (.ifTrue guard .here))
    exact ⟨completion, after, executesSequenceNonNext (executesIfTrue guard failed)
      (supported.failureStops.not_next failed), done⟩

end Lanius.Extraction.Entry.File.Results
