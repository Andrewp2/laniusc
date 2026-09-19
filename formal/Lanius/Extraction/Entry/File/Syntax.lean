import Lanius.Extraction.Entry.File.Frontend

namespace Lanius.Extraction.Entry.File.Syntax

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

/-- The actual file-loop call site. Capacities are explicit source literals;
the source count is a separate local supplied by the completed reader. -/
structure Stage where
  source : VarId
  length : VarId
  grammar : VarId
  raw : VarId
  canonical : VarId
  kinds : VarId
  workspace : VarId
  records : VarId
  offsets : VarId
  result : VarId
  resultType : Ty
  continuation : Stmt

def Stage.arguments (stage : Stage) : List Expr :=
  [read stage.source, read stage.length, read stage.grammar, number 2179,
    read stage.raw, number 65536, read stage.canonical, number 65536,
    read stage.kinds, number 65536, read stage.workspace, number 4194304,
    read stage.records, number 1048576, read stage.offsets, number 65536, number 1024]

def Stage.statement (stage : Stage) (function : FunctionId) : Stmt :=
  .letLocal stage.result stage.resultType (.call function stage.arguments) stage.continuation

def check? (function : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun stage : Stage => stage.statement function) statement) := do
  let .letLocal result resultType (.call _ [
    .local source, .local length, .local grammar, _, .local raw, _, .local canonical, _,
    .local kinds, _, .local workspace, _, .local records, _, .local offsets, _, _]) continuation := statement | none
  let stage : Stage := ⟨source, length, grammar, raw, canonical, kinds, workspace, records,
    offsets, result, resultType, continuation⟩
  let same ← Equality.statement? statement (stage.statement function)
  pure ⟨stage, same.equal⟩

def Stage.bufferLocals (stage : Stage) : List VarId :=
  [stage.source, stage.grammar, stage.raw, stage.canonical, stage.kinds, stage.workspace, stage.records, stage.offsets]

def Stage.bufferBindings (stage : Stage) (data : SyntaxData) (sourceCapacity : Nat) : List (VarId × Value) :=
  [(stage.source, .slice i32 data.sourceCell [] 0 sourceCapacity),
    (stage.grammar, .slice i32 data.grammarCell [] 0 data.grammarWords.length),
    (stage.raw, .slice i32 data.rawCell [] 0 data.records.length),
    (stage.canonical, .slice i32 data.canonicalCell [] 0 data.canonical.length),
    (stage.kinds, .slice i32 data.kindsCell [] 0 data.kinds.length),
    (stage.workspace, .slice i32 data.workspaceCell [] 0 data.workspaceValues.length),
    (stage.records, .slice i32 data.recordsCell [] 0 data.treeRecords.length),
    (stage.offsets, .slice i32 data.offsetsCell [] 0 data.treeOffsets.length)]

def Stage.Reads (stage : Stage) (data : SyntaxData) (sourceCapacity : Nat) (state : State) : Prop :=
  ∀ binding ∈ stage.bufferBindings data sourceCapacity, state.local? binding.1 = some binding.2

structure Capacities (data : SyntaxData) : Prop where
  grammar : data.grammarWords.length = 2179
  raw : data.records.length = 65536
  canonical : data.canonical.length = 65536
  kinds : data.kinds.length = 65536
  workspace : data.workspaceValues.length = 4194304
  records : data.treeRecords.length = 1048576
  offsets : data.treeOffsets.length = 65536
  depth : data.depth = 1024

/-- All seventeen arguments are evaluated from ordinary local contents and
the checked literals. No component execution is assumed here. -/
theorem Stage.arguments_evaluate (stage : Stage) (program : Program) (data : SyntaxData)
    (capacity : Capacities data) (reads : stage.Reads data sourceCapacity before)
    (count : before.local? stage.length = some (.signed .i32 data.request.source.length)) :
    ArgumentsEvaluateTo program before stage.arguments
      (.slice i32 data.sourceCell [] 0 sourceCapacity :: data.values.tail) before := by
  have readValue {id : VarId} {value : Value} (member : (id, value) ∈ stage.bufferBindings data sourceCapacity) :=
    local_evaluates program (reads _ member)
  have literal (value : Nat) : Evaluates program before (number value) (.signed .i32 value) before := evaluatesValue
  simp only [Stage.arguments, SyntaxData.values, List.tail_cons, RawLexer.LexInto.Structure.i32Type, i32,
    capacity.grammar, capacity.raw, capacity.canonical, capacity.kinds,
    capacity.workspace, capacity.records, capacity.offsets, capacity.depth]
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bufferBindings, i32]))
  apply ArgumentsEvaluateTo.cons (local_evaluates program count)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bufferBindings, i32, capacity.grammar]))
  apply ArgumentsEvaluateTo.cons (literal 2179)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bufferBindings, i32, capacity.raw]))
  apply ArgumentsEvaluateTo.cons (literal 65536)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bufferBindings, i32, capacity.canonical]))
  apply ArgumentsEvaluateTo.cons (literal 65536)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bufferBindings, i32, capacity.kinds]))
  apply ArgumentsEvaluateTo.cons (literal 65536)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bufferBindings, i32, capacity.workspace]))
  apply ArgumentsEvaluateTo.cons (literal 4194304)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bufferBindings, i32, capacity.records]))
  apply ArgumentsEvaluateTo.cons (literal 1048576)
  apply ArgumentsEvaluateTo.cons (readValue (by simp [Stage.bufferBindings, i32, capacity.offsets]))
  apply ArgumentsEvaluateTo.cons (literal 65536)
  apply ArgumentsEvaluateTo.cons (literal 1024)
  exact .nil _ _

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before ready : State} {input : Load.Input pipeline before} {data : SyntaxData}

/-- Static non-shadowing facts across the checked loading prefix. -/
structure Relation (pipeline : Load.Pipeline program) (stage : Stage) : Prop where
  count : stage.length = pipeline.read.count
  buffers : ∀ id ∈ stage.bufferLocals, id ≠ pipeline.path.length ∧ id ≠ pipeline.unpack.locals.cursor ∧
    id ≠ pipeline.opened.handle ∧ id ≠ pipeline.read.count ∧ id ≠ pipeline.read.closed

def checkRelation? (pipeline : Load.Pipeline program) (stage : Stage) : Option (PLift (Relation pipeline stage)) :=
  if valid : stage.length = pipeline.read.count ∧
      ∀ id ∈ stage.bufferLocals, id ≠ pipeline.path.length ∧ id ≠ pipeline.unpack.locals.cursor ∧
        id ≠ pipeline.opened.handle ∧ id ≠ pipeline.read.count ∧ id ≠ pipeline.read.closed then
    some ⟨⟨valid.1, valid.2⟩⟩ else none

theorem Stage.loaded_reads (stage : Stage) (relation : Relation pipeline stage)
    (loaded : Load.Loaded input ready) (reads : stage.Reads data input.source.length before) :
    stage.Reads data input.source.length ready := by
  intro binding member
  have localMember : binding.1 ∈ stage.bufferLocals := by
    simpa only [Stage.bufferBindings, Stage.bufferLocals, List.map_cons, List.map_nil] using
      List.mem_map_of_mem (f := Prod.fst) member
  obtain ⟨length, cursor, handle, count, closed⟩ := relation.buffers _ localMember
  apply loaded.locals _ length cursor handle count closed binding.2 ?_ (reads _ member)
  simp only [Stage.bufferBindings, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    intro elements same <;> cases same

/-- Execute the actual `let extracted = extract_syntax(...)` after loading.
The continuation receives the proved frontend result and its exact binding;
it is not asked to prove that the frontend ran. -/
theorem Stage.executes (stage : Stage) (relation : Relation pipeline stage)
    {visit : ParserTreeSource.CheckedVisit program} {materializer : ParserTreeSource.CheckedMaterialize visit}
    (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (fragment : Semantics.Capacity.Fragment.Checked program.core allowed)
    (included : allowed checked.source.function.id = true)
    (loaded : Load.Loaded input ready) (buffers : Load.FrontendBuffers input data)
    (valid : data.Valid) (capacities : Capacities data) (reads : stage.Reads data input.source.length before)
    (post : Scope.Post)
    (continuationRun : ∀ (tail : List Int) (status detail : Int) (count nodes words : Nat) (position : Int) called,
      data.request.source.length + tail.length = input.source.length →
      data.Post status detail count nodes words position ready called → data.PaddedRawOutput tail called →
      CellEffect data.writes ready called →
      Host.MemoryTail program.core ready called →
      let value := syntaxResult checked.tail.finish.constructor.typeId status detail data.raw.length count nodes words position
      let bound := called.bindLocal stage.result value
      bound.local? stage.result = some value →
      Prefix.Reaches program.core ready (stage.statement checked.source.function.id) bound stage.continuation →
      ∃ completion after, Executes program.core bound stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core ready (stage.statement checked.source.function.id) completion after ∧ post completion after := by
  have count : ready.local? stage.length = some (.signed .i32 data.request.source.length) := by
    simpa only [relation.count, buffers.sourceBytes, List.length_map] using loaded.count
  obtain ⟨tail, status, detail, count, nodes, words, position, called, length, run, result, raw, effect, memory⟩ :=
    loaded.frontend_evaluates checked linked fragment included buffers valid
      (stage.arguments_evaluate program.core data capacities (stage.loaded_reads relation loaded reads) count)
  let value := syntaxResult checked.tail.finish.constructor.typeId status detail data.raw.length count nodes words position
  have bound := Assertion.localPointsTo_local _ _ _ _ (bindLocal_owns_fresh called stage.result value
    effect.wellFormed)
  obtain ⟨completion, after, continued, done⟩ := continuationRun tail status detail count nodes words position called length result raw effect memory bound
    (.letLocal run .here)
  exact ⟨completion, restoreLocals called after, executesLetLocal run continued, post.restore completion called after done⟩

/-- The complete authenticated path/open/read/close/frontend prefix. The only
remaining execution premise is the source continuation after the frontend. -/
theorem loaded_syntax
    (pipeline : Load.Pipeline program) (stage : Stage)
    {visit : ParserTreeSource.CheckedVisit program} {materializer : ParserTreeSource.CheckedMaterialize visit}
    (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (source : pipeline.read.continuation = stage.statement checked.source.function.id)
    (relation : Relation pipeline stage)
    (fragment : Semantics.Capacity.Fragment.Checked program.core allowed)
    (included : allowed checked.source.function.id = true)
    (input : Load.Input pipeline before) (buffers : Load.FrontendBuffers input data)
    (valid : data.Valid) (capacities : Capacities data) (reads : stage.Reads data input.source.length before)
    (post : Scope.Post)
    (continuationRun : ∀ ready, Load.Loaded input ready →
      ∀ (tail : List Int) (status detail : Int) (count nodes words : Nat) (position : Int) called,
      data.request.source.length + tail.length = input.source.length →
      data.Post status detail count nodes words position ready called → data.PaddedRawOutput tail called →
      CellEffect data.writes ready called →
      Host.MemoryTail program.core ready called →
      let value := syntaxResult checked.tail.finish.constructor.typeId status detail data.raw.length count nodes words position
      let bound := called.bindLocal stage.result value
      bound.local? stage.result = some value →
      Prefix.Reaches program.core before (pipeline.path.statement pipeline.length.function.id) bound stage.continuation →
      ∃ completion after, Executes program.core bound stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before (pipeline.path.statement pipeline.length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  apply pipeline.executes input post
  intro ready loaded
  obtain ⟨completion, after, run, done⟩ := stage.executes relation checked linked fragment included loaded buffers valid capacities reads
    post (by
      intro tail status detail count nodes words position called length result raw effect memory
      dsimp only
      intro boundRead reached
      exact continuationRun ready loaded tail status detail count nodes words position called length result raw effect memory
        boundRead (loaded.reached.trans (source.symm ▸ reached)))
  exact ⟨completion, after, source.symm ▸ run, done⟩

end Lanius.Extraction.Entry.File.Syntax
