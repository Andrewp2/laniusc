import Lanius.Extraction.Diagnostics.Arguments
import Lanius.Extraction.Frontend.Result

namespace Lanius.Extraction.Diagnostics

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend

structure FrontendAccessors (program : CoreSynthesis.Program.CheckedProgram artifacts) (typeId : TypeId) where
  status : Source.CheckedProjection program ["verified", "extraction"] "extraction_stage" typeId 0
  detail : Source.CheckedProjection program ["verified", "extraction"] "extraction_detail" typeId 1
  position : Source.CheckedProjection program ["verified", "extraction"] "error_position" typeId 6
  nodes : Source.CheckedProjection program ["verified", "extraction"] "node_count" typeId 4
  words : Source.CheckedProjection program ["verified", "extraction"] "tree_words" typeId 5

def FrontendAccessors.arguments (accessors : FrontendAccessors program typeId) (argument resultId : VarId) : List (Argument program) :=
  [.local argument, .field accessors.status resultId, .field accessors.detail resultId,
    .field accessors.position resultId, .field accessors.nodes resultId, .field accessors.words resultId]

structure CheckedFrontend (program : CoreSynthesis.Program.CheckedProgram artifacts) (typeId : TypeId)
    (argument resultId : VarId) (source : Stmt) where
  writer : Natural.Checked program
  accessors : FrontendAccessors program typeId
  exactSource : source = statement writer.source.source.function.id (accessors.arguments argument resultId) 28

def checkFrontend? (program : CoreSynthesis.Program.CheckedProgram artifacts) (typeId : TypeId)
    (argument resultId : VarId) (source : Stmt) : Option (CheckedFrontend program typeId argument resultId source) := do
  let writer ← Natural.check? program
  let status ← Source.checkProjection? program ["verified", "extraction"] "extraction_stage" typeId 0
  let detail ← Source.checkProjection? program ["verified", "extraction"] "extraction_detail" typeId 1
  let position ← Source.checkProjection? program ["verified", "extraction"] "error_position" typeId 6
  let nodes ← Source.checkProjection? program ["verified", "extraction"] "node_count" typeId 4
  let words ← Source.checkProjection? program ["verified", "extraction"] "tree_words" typeId 5
  let accessors : FrontendAccessors program typeId := ⟨status, detail, position, nodes, words⟩
  let equal ← Equality.statement? source (statement writer.source.source.function.id (accessors.arguments argument resultId) 28)
  pure ⟨writer, accessors, equal.equal⟩

/-- All six diagnostic calls are constructed from their checked source and
the real returned structure. Typing bounds every printed field; no formatter
execution, successful write, or caller-supplied field bound is assumed. -/
theorem CheckedFrontend.executes (checked : CheckedFrontend program typeId argument resultId source)
    (typed : RuntimeStateHasType program.core context before store)
    (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (argumentRead : before.local? argument = some (.signed .i32 index))
    (resultRead : before.local? resultId = some (syntaxResult typeId status detail raw tokens nodes words position)) :
    ∃ after, Executes program.core before source (.returned (some (.signed .i32 28))) after ∧
      Allocation.Registry after ∧ Host.RepresentableViews after ∧ Host.Effect CellSet.empty before after ∧
      Host.StderrOnly before.world after.world := by
  let items : List (Argument program × Int) := [
    (.local argument, index), (.field checked.accessors.status resultId, status),
    (.field checked.accessors.detail resultId, detail), (.field checked.accessors.position resultId, position),
    (.field checked.accessors.nodes resultId, nodes), (.field checked.accessors.words resultId, words)]
  have readable : ∀ item ∈ items, item.1.Reads before item.2 := by
    intro item member
    simp only [items, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl
    · exact argumentRead
    all_goals exact ⟨_, resultRead, rfl⟩
  obtain ⟨after, run, registered, values, effect, world⟩ := sequence checked.writer items 28 initial representable readable
    (fun item member => item.1.bounded typed.typed (readable item member))
  exact ⟨after, checked.exactSource.symm ▸ run, registered, values, effect, world⟩

end Lanius.Extraction.Diagnostics
