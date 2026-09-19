import Lanius.Extraction.Entry.File.Carry
import Lanius.Extraction.SemanticTokens.Frontend

namespace Lanius.Extraction.Entry.File.Collect
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens Lanius.Extraction.CompactOutput
open Lanius.Extraction.SemanticTokens.Collect (CheckedCollect argumentValues)

structure Stage where
  grammar : VarId
  kinds : VarId
  tokens : VarId
  records : VarId
  offsets : VarId
  nodes : VarId
  semantic : VarId
  continuation : Stmt

def Stage.arguments (stage : Stage) : List Expr :=
  [read stage.grammar, number 2179, read stage.kinds, read stage.tokens,
    read stage.records, number 1048576, read stage.offsets, read stage.nodes,
    read stage.semantic, number 131072]

def Stage.statement (stage : Stage) (function : FunctionId) : Stmt :=
  .sequence (.ifThenElse (binary .notEqual (.call function stage.arguments) (number 0))
    (returned (number 20)) .skip) stage.continuation

def check? (function : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun stage : Stage => stage.statement function) statement) := do
  let .sequence (.ifThenElse (.binary .notEqual (.call _
    [.local grammar, _, .local kinds, .local tokens, .local records, _,
      .local offsets, .local nodes, .local semantic, _]) _) _ _) continuation := statement | none
  let stage : Stage := ⟨grammar, kinds, tokens, records, offsets, nodes, semantic, continuation⟩
  let same ← Equality.statement? statement (stage.statement function)
  pure ⟨stage, same.equal⟩

def Stage.bufferLocals (stage : Stage) : List VarId :=
  [stage.grammar, stage.kinds, stage.records, stage.offsets, stage.semantic]

def Stage.bindings (stage : Stage) (data : SyntaxData) (outputCell : CellId) (original : List Int) : List (VarId × Value) :=
  [(stage.grammar, .slice i32 data.grammarCell [] 0 data.grammarWords.length),
    (stage.kinds, .slice i32 data.kindsCell [] 0 data.kinds.length),
    (stage.records, .slice i32 data.recordsCell [] 0 data.treeRecords.length),
    (stage.offsets, .slice i32 data.offsetsCell [] 0 data.treeOffsets.length),
    (stage.semantic, .slice i32 outputCell [] 0 original.length)]

def Stage.Reads (stage : Stage) (data : SyntaxData) (outputCell : CellId) (original : List Int) (state : State) : Prop :=
  ∀ binding ∈ stage.bindings data outputCell original, state.local? binding.1 = some binding.2

theorem Stage.arguments_evaluate {count nodeCount : Nat} (stage : Stage) (program : Program) (data : SyntaxData)
    (capacity : Syntax.Capacities data) (outputCapacity : original.length = 131072)
    (reads : stage.Reads data outputCell original before)
    (tokens : before.local? stage.tokens = some (.signed .i32 count))
    (nodes : before.local? stage.nodes = some (.signed .i32 nodeCount)) :
    ArgumentsEvaluateTo program before stage.arguments (collectorValues data count nodeCount outputCell original) before := by
  have readValue {id : VarId} {value : Value} (member : (id, value) ∈ stage.bindings data outputCell original) :=
    local_evaluates program (reads _ member)
  have literal (value : Nat) : Evaluates program before (number value) (.signed .i32 value) before := evaluatesValue
  simp only [Stage.arguments, collectorValues, argumentValues,
    capacity.grammar, capacity.records, outputCapacity]
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bindings, capacity.grammar]))
  apply ArgumentsEvaluateTo.cons (literal 2179)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (local_evaluates program tokens)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bindings, capacity.records]))
  apply ArgumentsEvaluateTo.cons (literal 1048576)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (local_evaluates program nodes)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bindings, outputCapacity]))
  apply ArgumentsEvaluateTo.cons (literal 131072)
  exact .nil _ _

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before ready : State} {input : Load.Input pipeline before} {data : SyntaxData}

/-- Identities and non-shadowing are checked against the actual source locals,
not supplied as successful runtime behavior. -/
structure Relation (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage) (stage : Stage) : Prop where
  grammar : stage.grammar = syntaxStage.grammar
  kinds : stage.kinds = syntaxStage.kinds
  records : stage.records = syntaxStage.records
  offsets : stage.offsets = syntaxStage.offsets
  tokens : stage.tokens = resultsStage.tokens
  nodes : stage.nodes = resultsStage.nodes
  buffers : ∀ id ∈ stage.bufferLocals, id ∉ pipeline.boundLocals ∧ syntaxStage.result ≠ id ∧
    id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens

def checkRelation? (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage) (stage : Stage) :
    Option (PLift (Relation pipeline syntaxStage resultsStage stage)) :=
  if valid : stage.grammar = syntaxStage.grammar ∧ stage.kinds = syntaxStage.kinds ∧
      stage.records = syntaxStage.records ∧ stage.offsets = syntaxStage.offsets ∧
      stage.tokens = resultsStage.tokens ∧ stage.nodes = resultsStage.nodes ∧
      ∀ id ∈ stage.bufferLocals, id ∉ pipeline.boundLocals ∧ syntaxStage.result ≠ id ∧
        id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens then
    some ⟨⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2.1, valid.2.2.2.2.1,
      valid.2.2.2.2.2.1, valid.2.2.2.2.2.2⟩⟩ else none

theorem Stage.initial_reads (stage : Stage) (relation : Relation pipeline syntaxStage resultsStage stage)
    (reads : syntaxStage.Reads data input.source.length before)
    (semantic : before.local? stage.semantic = some (.slice i32 outputCell [] 0 original.length)) :
    stage.Reads data outputCell original before := by
  intro binding member
  simp only [Stage.bindings, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl
  · exact reads _ (by simp [Syntax.Stage.bufferBindings, relation.grammar])
  · exact reads _ (by simp [Syntax.Stage.bufferBindings, relation.kinds])
  · exact reads _ (by simp [Syntax.Stage.bufferBindings, relation.records])
  · exact reads _ (by simp [Syntax.Stage.bufferBindings, relation.offsets])
  · exact semantic

theorem Stage.ready_reads (stage : Stage) (relation : Relation pipeline syntaxStage resultsStage stage)
    (observed : FrontendReturn input data) (buffers : Load.FrontendBuffers input data)
    (reads : stage.Reads data outputCell original before)
    (kept : ∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ∀ value,
      (observed.bound syntaxStage.result typeId).local? id = some value → ready.local? id = some value) :
    stage.Reads data outputCell original ready := by
  intro binding member
  have localMember : binding.1 ∈ stage.bufferLocals := by
    simpa only [Stage.bindings, Stage.bufferLocals, List.map_cons, List.map_nil] using
      List.mem_map_of_mem (f := Prod.fst) member
  obtain ⟨unshadowed, different, notNode, notToken⟩ := relation.buffers _ localMember
  apply observed.original_local buffers (reads _ member) ?_ unshadowed different (kept _ notNode notToken _)
  simp only [Stage.bindings, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl <;> intro elements same <;> cases same

/-- The real ten-argument collector and its error guard. The successful
frontend's token bound proves the production semantic buffer is sufficient. -/
theorem Stage.executes {count nodes words : Nat} (stage : Stage) (checked : CheckedCollect program)
    (memory : CellOnly.Region program.core (.expression (.call checked.source.function.id stage.arguments)))
    (result : FrontendResult data count nodes words ready) (valid : data.Valid)
    (capacities : Syntax.Capacities data) (kindsFit : data.grammar.grammar.n_kinds ≤ 32768)
    (wellFormed : StateWellFormed ready)
    (grammar : ready.cellEntry? data.grammarCell = some { id := data.grammarCell, value := some (.array (signedI32Values data.grammarWords)) })
    (output : ready.cellEntry? outputCell = some { id := outputCell, value := some (.array (signedI32Values original)) })
    (outputCapacity : original.length = 131072)
    (separate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ outputCell)
    (reads : stage.Reads data outputCell original ready)
    (tokenRead : ready.local? stage.tokens = some (.signed .i32 count))
    (nodeRead : ready.local? stage.nodes = some (.signed .i32 nodes))
    (post : Scope.Post)
    (continuationRun : ∀ collection : CollectionRecords data.grammar (artifactTokens data.tokens) result.parse.tree 0 0,
      ∀ collected, collected.cellEntry? outputCell = some { id := outputCell, value := some (.array
        (signedI32Values (collection.assignments.flatMap Assignment.words ++ original.drop (count * 2)))) } →
      CellEffect (CellSet.singleton outputCell) ready collected →
      HeapFrame ready collected →
      ∃ completion after, Executes program.core collected stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core ready (stage.statement checked.source.function.id) completion after ∧ post completion after := by
  have enough : count * 2 ≤ original.length := by
    have bound := result.kinds.length_le
    simp only [List.length_map, ← result.countEq, capacities.kinds] at bound
    omega
  obtain ⟨collection, collected, call, contents, effect⟩ := result.collect checked valid kindsFit wellFormed grammar output
    (by omega) separate (stage.arguments_evaluate program.core data capacities outputCapacity reads tokenRead nodeRead)
  simp only [if_pos enough] at call contents
  have guard : Evaluates program.core ready
      (binary .notEqual (.call checked.source.function.id stage.arguments) (number 0)) (.boolean false) collected :=
    evaluatesEagerBinary (by decide) (by decide) call
      (show Evaluates program.core collected (number 0) (.signed .i32 0) collected from evaluatesValue) rfl
  obtain ⟨completion, after, continued, done⟩ := continuationRun collection collected contents effect (memory.evaluates call)
  exact ⟨completion, after, executesSequence (executesIfFalse guard (executesSkip _ _)) continued, done⟩

end Lanius.Extraction.Entry.File.Collect
