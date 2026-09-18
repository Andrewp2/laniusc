import Lanius.Extraction.Entry.File.Emit.Storage

namespace Lanius.Extraction.Entry.File.Emit
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before ready : State} {input : Load.Input pipeline before} {data : SyntaxData}

def Stage.connections (stage : Stage) (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    (resultsStage : Results.Stage) (collectStage : Collect.Stage) : List (VarId × VarId) :=
  [(stage.path, pipeline.unpack.locals.output), (stage.pathLength, pipeline.path.length),
    (stage.source, syntaxStage.source), (stage.sourceLength, pipeline.read.count),
    (stage.raw, syntaxStage.raw), (stage.result, syntaxStage.result), (stage.canonical, syntaxStage.canonical),
    (stage.tokens, resultsStage.tokens), (stage.semantic, collectStage.semantic),
    (stage.records, syntaxStage.records), (stage.offsets, syntaxStage.offsets), (stage.nodes, resultsStage.nodes)]

def Stage.carriedLocals (stage : Stage) : List VarId :=
  [stage.path, stage.source, stage.raw, stage.canonical, stage.semantic, stage.records, stage.offsets, stage.output, stage.position]

structure Relation (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    (resultsStage : Results.Stage) (collectStage : Collect.Stage) (stage : Stage) : Prop where
  connected : ∀ pair ∈ stage.connections pipeline syntaxStage resultsStage collectStage, pair.1 = pair.2
  carried : ∀ id ∈ stage.carriedLocals, id ∉ pipeline.boundLocals ∧ syntaxStage.result ≠ id ∧
    id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens
  loaded : ∀ id ∈ [stage.pathLength, stage.sourceLength], syntaxStage.result ≠ id ∧
    id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens

def checkRelation? (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    (resultsStage : Results.Stage) (collectStage : Collect.Stage) (stage : Stage) :
    Option (PLift (Relation pipeline syntaxStage resultsStage collectStage stage)) :=
  if valid : (∀ pair ∈ stage.connections pipeline syntaxStage resultsStage collectStage, pair.1 = pair.2) ∧
      (∀ id ∈ stage.carriedLocals, id ∉ pipeline.boundLocals ∧ syntaxStage.result ≠ id ∧
        id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens) ∧
      (∀ id ∈ [stage.pathLength, stage.sourceLength], syntaxStage.result ≠ id ∧
        id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens) then
    some ⟨⟨valid.1, valid.2.1, valid.2.2⟩⟩ else none

/-- Recover all emitter argument locals from the original input, completed
reader, and actual frontend result bindings. No intermediate reads are assumed. -/
theorem Stage.ready_reads {typeId : TypeId} {position : Int}
    (stage : Stage) (relation : Relation pipeline syntaxStage resultsStage collectStage stage)
    (observed : FrontendReturn input data) (buffers : Load.FrontendBuffers input data)
    (semantic output : SavedBuffer input)
    (reads : syntaxStage.Reads data input.source.length before)
    (semanticRead : before.local? collectStage.semantic = some (.slice i32 semantic.view.root [] 0 semantic.contents.length))
    (outputRead : before.local? stage.output = some (.slice i32 output.view.root [] 0 output.contents.length))
    (positionRead : before.local? stage.position = some (.signed .i32 position))
    (nodes : ready.local? resultsStage.nodes = some (.signed .i32 observed.nodes))
    (tokens : ready.local? resultsStage.tokens = some (.signed .i32 observed.count))
    (kept : ∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ∀ value,
      (observed.bound syntaxStage.result typeId).local? id = some value → ready.local? id = some value) :
    stage.Reads (emission observed semantic output position) ready := by
  have original {id : VarId} {value : Value} (member : id ∈ stage.carriedLocals)
      (found : before.local? id = some value) (notArray : ∀ elements, value ≠ .array elements) : ready.local? id = some value := by
    obtain ⟨unshadowed, different, notNode, notToken⟩ := relation.carried id member
    exact observed.original_local buffers found notArray unshadowed different (kept id notNode notToken value)
  have loaded {id : VarId} {value : Value} (member : id ∈ [stage.pathLength, stage.sourceLength])
      (found : observed.loadedState.local? id = some value) (notArray : ∀ elements, value ≠ .array elements) : ready.local? id = some value := by
    obtain ⟨different, notNode, notToken⟩ := relation.loaded id member
    exact observed.loaded_local buffers found notArray different (kept id notNode notToken value)
  have connected {left right : VarId} (member : (left, right) ∈ stage.connections pipeline syntaxStage resultsStage collectStage) : left = right :=
    relation.connected _ member
  intro binding member
  simp only [Stage.bindings, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · apply original (by simp [Stage.carriedLocals]) ?_ (by intro elements same; cases same)
    exact (connected (by simp [Stage.connections]) : stage.path = pipeline.unpack.locals.output).symm ▸ input.pathRead
  · apply loaded (by simp) ?_ (by intro elements same; cases same)
    have same : stage.pathLength = pipeline.path.length := connected (by simp [Stage.connections])
    simpa only [same, emission, List.length_map] using observed.loaded.pathCount
  · apply original (by simp [Stage.carriedLocals]) ?_ (by intro elements same; cases same)
    exact reads _ (by simp [Syntax.Stage.bufferBindings, emission,
      (connected (by simp [Stage.connections]) : stage.source = syntaxStage.source)])
  · apply loaded (by simp) ?_ (by intro elements same; cases same)
    have same : stage.sourceLength = pipeline.read.count := connected (by simp [Stage.connections])
    simpa only [same, emission, buffers.sourceBytes, List.length_map] using observed.loaded.count
  · apply original (by simp [Stage.carriedLocals]) ?_ (by intro elements same; cases same)
    exact reads _ (by simp [Syntax.Stage.bufferBindings, emission,
      (connected (by simp [Stage.connections]) : stage.raw = syntaxStage.raw)])
  · apply original (by simp [Stage.carriedLocals]) ?_ (by intro elements same; cases same)
    exact reads _ (by simp [Syntax.Stage.bufferBindings, emission,
      (connected (by simp [Stage.connections]) : stage.canonical = syntaxStage.canonical)])
  · exact (connected (by simp [Stage.connections]) : stage.tokens = resultsStage.tokens).symm ▸ tokens
  · apply original (by simp [Stage.carriedLocals]) ?_ (by intro elements same; cases same)
    exact (connected (by simp [Stage.connections]) : stage.semantic = collectStage.semantic).symm ▸ semanticRead
  · apply original (by simp [Stage.carriedLocals]) ?_ (by intro elements same; cases same)
    exact reads _ (by simp [Syntax.Stage.bufferBindings, emission,
      (connected (by simp [Stage.connections]) : stage.records = syntaxStage.records)])
  · apply original (by simp [Stage.carriedLocals]) ?_ (by intro elements same; cases same)
    exact reads _ (by simp [Syntax.Stage.bufferBindings, emission,
      (connected (by simp [Stage.connections]) : stage.offsets = syntaxStage.offsets)])
  · exact (connected (by simp [Stage.connections]) : stage.nodes = resultsStage.nodes).symm ▸ nodes
  · exact original (by simp [Stage.carriedLocals]) outputRead (by intro elements same; cases same)
  · exact original (by simp [Stage.carriedLocals]) positionRead (by intro elements same; cases same)

theorem Stage.result_ready {typeId : TypeId}
    (stage : Stage) (relation : Relation pipeline syntaxStage resultsStage collectStage stage)
    (supported : resultsStage.Supported) (binding : resultsStage.result = syntaxStage.result)
    (observed : FrontendReturn input data)
    (kept : ∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ∀ value,
      (observed.bound syntaxStage.result typeId).local? id = some value → ready.local? id = some value) :
    ready.local? stage.result = some (observed.value typeId) := by
  have same : stage.result = syntaxStage.result := relation.connected (stage.result, syntaxStage.result) (by simp [Stage.connections])
  rw [same]
  apply kept _ (binding ▸ supported.nodeResult.symm) (binding ▸ supported.tokenResult.symm)
  exact bindLocal_finds_local _ _ _ observed.effect.wellFormed

theorem Stage.Reads.preserved {stage : Stage} {unit : Unit.Emission}
    (reads : stage.Reads unit before) (wellFormed : StateWellFormed before)
    (stored : before.cellEntry? cell = some { id := cell, value := some (.array values) })
    (effect : CellEffect (CellSet.singleton cell) before after) : stage.Reads unit after := by
  intro binding member
  apply effect.preserves_local_of_distinct_value wellFormed (reads _ member) stored
  simp only [Stage.bindings, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    intro same <;> cases same

end Lanius.Extraction.Entry.File.Emit
