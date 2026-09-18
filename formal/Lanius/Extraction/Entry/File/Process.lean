import Lanius.Extraction.Entry.File.Syntax
import Lanius.Extraction.Entry.File.Results

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before : State}
variable {input : Load.Input pipeline before} {data : SyntaxData}

/-- Observations produced by the complete file-loading/frontend prefix.
Callers do not supply this record: `process` constructs it from ordinary
input resources and the checked lexer/parser execution theorem. -/
structure FrontendReturn (input : Load.Input pipeline before) (data : SyntaxData) where
  loadedState : State
  calledState : State
  loaded : Load.Loaded input loadedState
  tail : List Int
  status : Int
  detail : Int
  count : Nat
  nodes : Nat
  words : Nat
  position : Int
  length : data.request.source.length + tail.length = input.source.length
  result : data.Post status detail count nodes words position loadedState calledState
  raw : data.PaddedRawOutput tail calledState
  effect : CellEffect data.writes loadedState calledState
  memory : Host.MemoryTail program.core loadedState calledState

def FrontendReturn.value (observed : FrontendReturn input data) (typeId : TypeId) : Value :=
  syntaxResult typeId observed.status observed.detail data.raw.length observed.count observed.nodes observed.words observed.position

def FrontendReturn.bound (observed : FrontendReturn input data) (resultId : VarId) (typeId : TypeId) : State :=
  observed.calledState.bindLocal resultId (observed.value typeId)

theorem FrontendReturn.bound_wellFormed (observed : FrontendReturn input data) (resultId : VarId) (typeId : TypeId) :
    StateWellFormed (observed.bound resultId typeId) :=
  bindLocal_preserves_well_formed _ _ _ observed.effect.wellFormed

theorem FrontendReturn.bound_memory (observed : FrontendReturn input data) (resultId : VarId) (typeId : TypeId) :
    Host.MemoryTail program.core observed.loadedState (observed.bound resultId typeId) :=
  observed.memory.thenHeap ⟨rfl, rfl⟩

/-- One composed boundary from the original file-loop state to its two
remaining branches: diagnostics on frontend failure, or the collector after
both returned counts are bound. No successful component run, accessor result,
intermediate allocation invariant, or tight source buffer is assumed. -/
theorem process (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    {visit : ParserTreeSource.CheckedVisit program} {materializer : ParserTreeSource.CheckedMaterialize visit}
    (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (source : pipeline.read.continuation = syntaxStage.statement checked.source.function.id)
    (relation : Syntax.Relation pipeline syntaxStage)
    (fragment : Semantics.Capacity.Fragment.Checked program.core allowed)
    (included : allowed checked.source.function.id = true)
    (accessors : Results.Accessors program checked.tail.finish.constructor.typeId)
    (resultsStage : Results.Stage) (resultsSupported : resultsStage.Supported)
    (resultsSource : syntaxStage.continuation = resultsStage.statement accessors.status.source.function.id
      accessors.nodes.source.function.id accessors.tokens.source.function.id)
    (resultsBinding : resultsStage.result = syntaxStage.result)
    (input : Load.Input pipeline before) (data : SyntaxData) (buffers : Load.FrontendBuffers input data)
    (valid : data.Valid) (capacities : Syntax.Capacities data) (reads : syntaxStage.Reads data input.source.length before)
    (post : Scope.Post)
    (failureRun : ∀ observed : FrontendReturn input data, observed.status ≠ 0 → ∀ guarded,
      CellEffect CellSet.empty (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId) guarded →
      Host.MemoryTail program.core observed.loadedState guarded →
      Prefix.Reaches program.core before (pipeline.path.statement pipeline.length.function.id) guarded resultsStage.failure →
      ∃ completion after, Executes program.core guarded resultsStage.failure completion after ∧ post completion after)
    (continuationRun : ∀ observed : FrontendReturn input data, observed.status = 0 → ∀ ready,
      StateWellFormed ready →
      CellEffect CellSet.empty (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId)
        (restoreLocals (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId) ready) →
      Host.MemoryTail program.core observed.loadedState ready →
      ready.local? resultsStage.nodes = some (.signed .i32 observed.nodes) →
      ready.local? resultsStage.tokens = some (.signed .i32 observed.count) →
      (∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ready.cellId? id =
        (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId).cellId? id) →
      (∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ∀ value,
        (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId).local? id = some value →
        ready.local? id = some value) →
      ∃ completion after, Executes program.core ready resultsStage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before (pipeline.path.statement pipeline.length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  apply Syntax.loaded_syntax pipeline syntaxStage checked linked source relation fragment included input buffers valid capacities reads
    post
  intro loadedState loaded tail status detail count nodes words position calledState length result raw effect memory
  dsimp only
  intro resultRead syntaxReach
  let observed : FrontendReturn input data := {
    loadedState, calledState, loaded, tail, status, detail, count, nodes, words, position, length, result, raw, effect, memory }
  obtain ⟨completion, after, run, done⟩ := resultsStage.dispatch resultsSupported accessors
    (observed.bound_wellFormed syntaxStage.result checked.tail.finish.constructor.typeId)
    (by simpa only [FrontendReturn.bound, FrontendReturn.value, observed, resultsBinding] using resultRead)
    post (by
      intro failure guarded effect heap reached
      exact failureRun observed failure guarded effect
        ((observed.bound_memory syntaxStage.result checked.tail.finish.constructor.typeId).thenHeap heap)
        (syntaxReach.trans (resultsSource.symm ▸ reached))) (by
      intro success ready wellFormed effect heap
      exact continuationRun observed success ready wellFormed effect
        ((observed.bound_memory syntaxStage.result checked.tail.finish.constructor.typeId).thenHeap heap))
  exact ⟨completion, after, resultsSource.symm ▸ run, done⟩

end Lanius.Extraction.Entry.File
