import Lanius.Extraction.Entry.File.Collected
import Lanius.Extraction.Entry.File.Emit.Call

namespace Lanius.Extraction.Entry.File.Emit
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens Lanius.Extraction.CompactOutput

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before ready collected : State} {input : Load.Input pipeline before} {data : SyntaxData}

/-- All counts and source/path identities come from this actual file's
frontend observation. Only the pre-existing output cursor is an input. -/
def emission (observed : FrontendReturn input data) (semantic output : SavedBuffer input) (position : Int) : Unit.Emission := {
  data
  sourceCapacity := input.source.length
  path := (Lanius.World.utf8Bytes input.path).map UInt8.toFin
  pathCell := input.pathOutput.root
  pathCapacity := input.pathOutput.length
  semanticCell := semantic.view.root
  semanticOriginal := semantic.contents
  outputCell := output.view.root
  original := output.contents
  capacity := 16777216
  position
  count := observed.count
  nodes := observed.nodes
  words := observed.words }

/-- The complete unit-emitter storage contract follows from the loaded path,
frontend buffers, and collector effect. No serialization run is a premise. -/
theorem storage {resultId : VarId} {typeId : TypeId} {position : Int}
    (observed : FrontendReturn input data) (success : observed.status = 0)
    (buffers : Load.FrontendBuffers input data) (valid : data.Valid)
    (capacities : Syntax.Capacities data) (kindsFit : data.grammar.grammar.n_kinds ≤ 32768)
    (semantic output : SavedBuffer input) (semanticCapacity : semantic.contents.length = 131072)
    (outputCapacity : output.contents.length = 16777216)
    (semanticSeparate : ∀ cell ∈ data.bufferRoots, cell ≠ semantic.view.root)
    (outputSeparate : ∀ cell ∈ data.bufferRoots, cell ≠ output.view.root)
    (outputSemantic : output.view.root ≠ semantic.view.root)
    (wellFormed : StateWellFormed ready)
    (scopeEffect : CellEffect CellSet.empty (observed.bound resultId typeId) (restoreLocals (observed.bound resultId typeId) ready))
    (result : FrontendResult data observed.count observed.nodes observed.words ready)
    (collection : CollectionRecords data.grammar (artifactTokens data.tokens) result.parse.tree 0 0)
    (assignments : collected.cellEntry? semantic.view.root = some { id := semantic.view.root, value := some (.array
      (signedI32Values (collection.assignments.flatMap Assignment.words ++ semantic.contents.drop (observed.count * 2)))) })
    (effect : CellEffect (CellSet.singleton semantic.view.root) ready collected) :
    Unit.Storage (emission observed semantic output position) result collection collected := by
  have untouched : ¬ data.writes output.view.root := fun written => outputSeparate _ (SyntaxData.writes_in_roots written) rfl
  have separate : ∀ cell ∈ [data.sourceCell, data.rawCell, data.canonicalCell, data.recordsCell, data.offsetsCell], cell ≠ semantic.view.root := by
    intro cell member
    apply semanticSeparate cell
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl <;> simp [SyntaxData.bufferRoots, SyntaxData.buffers]
  have enough : observed.count * 2 ≤ semantic.contents.length := by
    have bound := result.kinds.length_le
    simp only [List.length_map, ← result.countEq, capacities.kinds] at bound
    omega
  apply Unit.Storage.of_collection valid kindsFit (observed.post_ready success scopeEffect) (observed.raw_ready scopeEffect)
    observed.length success wellFormed effect separate assignments
  · exact (observed.path_ready buffers scopeEffect).preserved wellFormed effect semantic.path.symm
  · exact effect.preserves_entry wellFormed (observed.saved_ready output untouched scopeEffect) outputSemantic
  · change ((Lanius.World.utf8Bytes input.path).map UInt8.toFin).length ≤ 2147483647
    simp only [List.length_map]
    exact Nat.le_trans input.pathCapacity input.pathBound
  · change semantic.contents.length ≤ 2147483647
    omega
  · exact enough
  · change 16777216 ≤ 2147483647
    decide
  · change 16777216 ≤ output.contents.length
    omega
  · intro cell member
    change cell ∈ [input.pathOutput.root, data.sourceCell, data.rawCell, data.canonicalCell,
      semantic.view.root, data.recordsCell, data.offsetsCell] at member
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact output.path
    · exact (outputSeparate _ (by simp [SyntaxData.bufferRoots, SyntaxData.buffers])).symm
    · exact (outputSeparate _ (by simp [SyntaxData.bufferRoots, SyntaxData.buffers])).symm
    · exact (outputSeparate _ (by simp [SyntaxData.bufferRoots, SyntaxData.buffers])).symm
    · exact outputSemantic
    · exact (outputSeparate _ (by simp [SyntaxData.bufferRoots, SyntaxData.buffers])).symm
    · exact (outputSeparate _ (by simp [SyntaxData.bufferRoots, SyntaxData.buffers])).symm

end Lanius.Extraction.Entry.File.Emit
