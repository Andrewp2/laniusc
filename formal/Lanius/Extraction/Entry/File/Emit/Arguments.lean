import Lanius.Extraction.Entry.File.Collect
import Lanius.Extraction.CompactOutput.Unit.Arguments

namespace Lanius.Extraction.Entry.File.Emit
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

structure Stage where
  path : VarId
  pathLength : VarId
  source : VarId
  sourceLength : VarId
  raw : VarId
  result : VarId
  canonical : VarId
  tokens : VarId
  semantic : VarId
  records : VarId
  offsets : VarId
  nodes : VarId
  output : VarId
  position : VarId
  continuation : Stmt

def Stage.arguments (stage : Stage) (rawCount : FunctionId) : List Expr :=
  [read stage.path, read stage.pathLength, read stage.source, read stage.sourceLength,
    read stage.raw, number 65536, .call rawCount [read stage.result], read stage.canonical,
    number 65536, read stage.tokens, read stage.semantic, number 131072, read stage.records,
    number 1048576, read stage.offsets, read stage.nodes, read stage.output, number 16777216, read stage.position]

def Stage.assignment (stage : Stage) (function rawCount : FunctionId) : Stmt :=
  .expression (.assign .set (.local stage.position) (.call function (stage.arguments rawCount)))

def Stage.statement (stage : Stage) (function rawCount : FunctionId) : Stmt :=
  .sequence (stage.assignment function rawCount)
    (.sequence (.ifThenElse (binary .lessEqual (read stage.position) negativeOne)
      (returned (number 21)) .skip) stage.continuation)

def check? (function rawCount : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun stage : Stage => stage.statement function rawCount) statement) := do
  let .sequence (.expression (.assign .set (.local position) (.call _
    [.local path, .local pathLength, .local source, .local sourceLength, .local raw, _,
      .call _ [.local result], .local canonical, _, .local tokens, .local semantic, _,
      .local records, _, .local offsets, .local nodes, .local output, _, _])))
      (.sequence _ continuation) := statement | none
  let stage : Stage := ⟨path, pathLength, source, sourceLength, raw, result, canonical,
    tokens, semantic, records, offsets, nodes, output, position, continuation⟩
  let same ← Equality.statement? statement (stage.statement function rawCount)
  pure ⟨stage, same.equal⟩

def Stage.bindings (stage : Stage) (emission : Unit.Emission) : List (VarId × Value) :=
  [(stage.path, .slice i32 emission.pathCell [] 0 emission.pathCapacity),
    (stage.pathLength, .signed .i32 emission.path.length),
    (stage.source, .slice i32 emission.data.sourceCell [] 0 emission.sourceCapacity),
    (stage.sourceLength, .signed .i32 emission.data.request.source.length),
    (stage.raw, .slice i32 emission.data.rawCell [] 0 emission.data.records.length),
    (stage.canonical, .slice i32 emission.data.canonicalCell [] 0 emission.data.canonical.length),
    (stage.tokens, .signed .i32 emission.count),
    (stage.semantic, .slice i32 emission.semanticCell [] 0 emission.semanticOriginal.length),
    (stage.records, .slice i32 emission.data.recordsCell [] 0 emission.data.treeRecords.length),
    (stage.offsets, .slice i32 emission.data.offsetsCell [] 0 emission.data.treeOffsets.length),
    (stage.nodes, .signed .i32 emission.nodes),
    (stage.output, .slice i32 emission.outputCell [] 0 emission.original.length),
    (stage.position, .signed .i32 emission.position)]

def Stage.Reads (stage : Stage) (emission : Unit.Emission) (state : State) : Prop :=
  ∀ binding ∈ stage.bindings emission, state.local? binding.1 = some binding.2

/-- Evaluate all nineteen source arguments in order, including the embedded
raw-count accessor. Its fresh call cells are retained without changing storage. -/
theorem Stage.arguments_evaluate {status detail position : Int}
    (stage : Stage) (rawCount : Source.CheckedProjection program ["verified", "extraction"] "raw_count" typeId 2)
    (emission : Unit.Emission) (capacities : Syntax.Capacities emission.data)
    (semanticCapacity : emission.semanticOriginal.length = 131072) (outputCapacity : emission.capacity = 16777216)
    (wellFormed : StateWellFormed before) (reads : stage.Reads emission before)
    (resultRead : before.local? stage.result = some
      (syntaxResult typeId status detail emission.data.raw.length emission.count emission.nodes emission.words position)) :
    ∃ ready, ArgumentsEvaluateTo program.core before (stage.arguments rawCount.source.function.id) emission.values ready ∧
      CellEffect CellSet.empty before ready := by
  obtain ⟨ready, rawCall, effect, _⟩ := rawCount.call wellFormed
    (.cons (local_evaluates program.core resultRead) (.nil _ _)) (by rfl)
  have readBefore {id : VarId} {value : Value} (member : (id, value) ∈ stage.bindings emission) :=
    local_evaluates program.core (reads _ member)
  have readAfter {id : VarId} {value : Value} (member : (id, value) ∈ stage.bindings emission) :=
    local_evaluates program.core (effect.empty_preserves_local wellFormed (reads _ member))
  have literal (state : State) (value : Nat) : Evaluates program.core state (number value) (.signed .i32 value) state := ⟨1, rfl⟩
  refine ⟨ready, ?_, effect⟩
  simp only [Stage.arguments, Unit.Emission.values, capacities.raw, capacities.canonical,
    capacities.records, semanticCapacity, outputCapacity]
  apply ArgumentsEvaluateTo.cons (readBefore (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (readBefore (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (readBefore (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (readBefore (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (readBefore (by simp [Stage.bindings, capacities.raw]))
  apply ArgumentsEvaluateTo.cons (literal before 65536)
  apply ArgumentsEvaluateTo.cons rawCall
  apply ArgumentsEvaluateTo.cons (readAfter (by simp [Stage.bindings, capacities.canonical]))
  apply ArgumentsEvaluateTo.cons (literal ready 65536)
  apply ArgumentsEvaluateTo.cons (readAfter (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (readAfter (by simp [Stage.bindings, semanticCapacity]))
  apply ArgumentsEvaluateTo.cons (literal ready 131072)
  apply ArgumentsEvaluateTo.cons (readAfter (by simp [Stage.bindings, capacities.records]))
  apply ArgumentsEvaluateTo.cons (literal ready 1048576)
  apply ArgumentsEvaluateTo.cons (readAfter (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (readAfter (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (readAfter (by simp [Stage.bindings]))
  apply ArgumentsEvaluateTo.cons (literal ready 16777216)
  apply ArgumentsEvaluateTo.cons (readAfter (by simp [Stage.bindings]))
  exact .nil _ _

end Lanius.Extraction.Entry.File.Emit
