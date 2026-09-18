import Lanius.Extraction.Entry.File.Process
import Lanius.Extraction.Frontend.Frame

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before ready : State} {input : Load.Input pipeline before} {data : SyntaxData}
variable {value : Value}

/-- A caller buffer outside the four file-loading write targets. Its initial
contents and registered view are ordinary entry resources, not a claim that
loading or parsing has already succeeded. -/
structure SavedBuffer (input : Load.Input pipeline before) where
  view : I32ArrayView
  contents : List Int
  member : view ∈ before.i32ArrayViews
  packedPath : view.root ≠ input.packedPath.root
  path : view.root ≠ input.pathOutput.root
  source : view.root ≠ input.source.root
  scratch : view.root ≠ input.scratch.root
  stored : before.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values contents)) }

theorem SavedBuffer.loaded (saved : SavedBuffer input) (loaded : Load.Loaded input ready) :
    ready.cellEntry? saved.view.root = some { id := saved.view.root, value := some (.array (signedI32Values saved.contents)) } :=
  loaded.preserved input.registry.disjoint saved.view saved.member
    ⟨input.registry.apart input.packedPathMember saved.member saved.packedPath.symm, saved.path, saved.source, saved.scratch⟩
    saved.contents (by simp only [readCellProjection, input.registry.roots saved.view saved.member, saved.stored, projectedValue])
    (input.representable saved.view saved.member saved.contents saved.stored)

theorem Load.FrontendBuffers.path_separate (buffers : Load.FrontendBuffers input data)
    (member : cell ∈ data.bufferRoots) : cell ≠ input.pathOutput.root := by
  obtain ⟨buffer, present, rfl⟩ := List.mem_map.mp member
  change buffer ∈ (data.sourceCell, CanonicalTokens.CanonicalizeModel.sourceIntegers data.request.source ++ []) ::
    (data.buffers []).tail at present
  rcases List.mem_cons.mp present with rfl | other
  · exact buffers.sourceCell ▸ input.sourcePathDistinct
  · obtain ⟨view, _, root, _, apart, _, _, _⟩ := buffers.other buffer other
    exact root ▸ apart

theorem Load.Loaded.path_prefix (loaded : Load.Loaded input ready) :
    I32Prefix ready input.pathOutput.root input.pathOutput.length
      (CanonicalTokens.CanonicalizeModel.sourceIntegers ((Lanius.World.utf8Bytes input.path).map UInt8.toFin)) := by
  obtain ⟨original, length, stored⟩ := loaded.path
  refine ⟨original.drop (Lanius.World.utf8Bytes input.path).length, ?_, ?_⟩
  · simp only [CanonicalTokens.CanonicalizeModel.sourceIntegers, List.length_map, List.length_drop, length]
    have := input.pathCapacity
    omega
  · simpa only [CanonicalTokens.CanonicalizeModel.sourceIntegers, List.map_map, Function.comp_def,
      UInt8.toFin_val, Int.ofNat_eq_natCast] using stored

theorem FrontendReturn.scopes (observed : FrontendReturn input data) {resultId : VarId} {typeId : TypeId}
    (effect : CellEffect CellSet.empty (observed.bound resultId typeId) (restoreLocals (observed.bound resultId typeId) ready)) :
    CellEffect CellSet.empty observed.calledState (restoreLocals observed.calledState ready) :=
  (Scope.bound observed.calledState resultId (observed.value typeId) observed.effect.wellFormed).transScoped effect observed.effect.wellFormed

theorem FrontendReturn.post_ready (observed : FrontendReturn input data) {resultId : VarId} {typeId : TypeId}
    (success : observed.status = 0)
    (effect : CellEffect CellSet.empty (observed.bound resultId typeId) (restoreLocals (observed.bound resultId typeId) ready)) :
    data.Post observed.status observed.detail observed.count observed.nodes observed.words observed.position observed.loadedState ready :=
  observed.result.preserved_success success observed.effect.wellFormed (observed.scopes effect)

theorem FrontendReturn.raw_ready (observed : FrontendReturn input data) {resultId : VarId} {typeId : TypeId}
    (effect : CellEffect CellSet.empty (observed.bound resultId typeId) (restoreLocals (observed.bound resultId typeId) ready)) :
    data.PaddedRawOutput observed.tail ready :=
  observed.raw.preserved observed.effect.wellFormed (observed.scopes effect)

theorem FrontendReturn.grammar_ready (observed : FrontendReturn input data) {resultId : VarId} {typeId : TypeId}
    (buffers : Load.FrontendBuffers input data) (valid : data.Valid)
    (effect : CellEffect CellSet.empty (observed.bound resultId typeId) (restoreLocals (observed.bound resultId typeId) ready)) :
    ready.cellEntry? data.grammarCell = some { id := data.grammarCell, value := some (.array (signedI32Values data.grammarWords)) } := by
  obtain ⟨_, _, owned⟩ := observed.loaded.frontend_input buffers
  have initial := owned (data.grammarCell, data.grammarWords) (by simp [SyntaxData.buffers])
  have called := observed.effect.preserves_entry observed.loaded.registry.wellFormed initial (SyntaxData.grammar_untouched valid)
  exact (observed.scopes effect).empty_preserves_entry observed.effect.wellFormed called

theorem FrontendReturn.saved_ready (observed : FrontendReturn input data) {resultId : VarId} {typeId : TypeId}
    (saved : SavedBuffer input) (untouched : ¬ data.writes saved.view.root)
    (effect : CellEffect CellSet.empty (observed.bound resultId typeId) (restoreLocals (observed.bound resultId typeId) ready)) :
    ready.cellEntry? saved.view.root = some { id := saved.view.root, value := some (.array (signedI32Values saved.contents)) } := by
  have called := observed.effect.preserves_entry observed.loaded.registry.wellFormed (saved.loaded observed.loaded) untouched
  exact (observed.scopes effect).empty_preserves_entry observed.effect.wellFormed called

theorem FrontendReturn.path_ready (observed : FrontendReturn input data) {resultId : VarId} {typeId : TypeId}
    (buffers : Load.FrontendBuffers input data)
    (effect : CellEffect CellSet.empty (observed.bound resultId typeId) (restoreLocals (observed.bound resultId typeId) ready)) :
    I32Prefix ready input.pathOutput.root input.pathOutput.length
      (CanonicalTokens.CanonicalizeModel.sourceIntegers ((Lanius.World.utf8Bytes input.path).map UInt8.toFin)) := by
  have untouched : ¬ data.writes input.pathOutput.root :=
    fun written => buffers.path_separate (SyntaxData.writes_in_roots written) rfl
  exact (observed.loaded.path_prefix.preserved observed.loaded.registry.wellFormed observed.effect untouched).preserved
    (after := restoreLocals observed.calledState ready) observed.effect.wellFormed (observed.scopes effect) (by simp [CellSet.empty])

theorem FrontendReturn.loaded_local (observed : FrontendReturn input data) {resultId id : VarId} {typeId : TypeId}
    (buffers : Load.FrontendBuffers input data) (found : observed.loadedState.local? id = some value)
    (notArray : ∀ elements, value ≠ .array elements) (different : resultId ≠ id)
    (kept : (observed.bound resultId typeId).local? id = some value → ready.local? id = some value) :
    ready.local? id = some value := by
  obtain ⟨_, _, owned⟩ := observed.loaded.frontend_input buffers
  have called := owned.preserves_local observed.loaded.registry.wellFormed observed.effect found notArray
  exact kept ((bindLocal_preserves_other_local observed.effect.wellFormed different).trans called)

def Load.Pipeline.boundLocals (pipeline : Load.Pipeline program) : List VarId :=
  [pipeline.path.length, pipeline.unpack.locals.cursor, pipeline.opened.handle, pipeline.read.count, pipeline.read.closed]

theorem FrontendReturn.original_binding (observed : FrontendReturn input data) {resultId id : VarId} {typeId : TypeId}
    (unshadowed : id ∉ pipeline.boundLocals) (different : resultId ≠ id)
    (kept : ready.cellId? id = (observed.bound resultId typeId).cellId? id) : ready.cellId? id = before.cellId? id := by
  have distinct : id ≠ pipeline.path.length ∧ id ≠ pipeline.unpack.locals.cursor ∧ id ≠ pipeline.opened.handle ∧
      id ≠ pipeline.read.count ∧ id ≠ pipeline.read.closed := by simpa only [Load.Pipeline.boundLocals,
        List.mem_cons, List.not_mem_nil, or_false, not_or] using unshadowed
  rw [kept, show (observed.bound resultId typeId).cellId? id = observed.calledState.cellId? id from
    bindLocal_preserves_other_cellId observed.calledState resultId id _ different]
  simp only [State.cellId?, observed.effect.locals]
  exact observed.loaded.bindings id distinct.1 distinct.2.1 distinct.2.2.1 distinct.2.2.2.1 distinct.2.2.2.2

theorem FrontendReturn.original_local (observed : FrontendReturn input data) {resultId id : VarId} {typeId : TypeId}
    (buffers : Load.FrontendBuffers input data) (found : before.local? id = some value)
    (notArray : ∀ elements, value ≠ .array elements) (unshadowed : id ∉ pipeline.boundLocals) (different : resultId ≠ id)
    (kept : (observed.bound resultId typeId).local? id = some value → ready.local? id = some value) :
    ready.local? id = some value := by
  have distinct : id ≠ pipeline.path.length ∧ id ≠ pipeline.unpack.locals.cursor ∧ id ≠ pipeline.opened.handle ∧
      id ≠ pipeline.read.count ∧ id ≠ pipeline.read.closed := by simpa only [Load.Pipeline.boundLocals,
        List.mem_cons, List.not_mem_nil, or_false, not_or] using unshadowed
  exact observed.loaded_local buffers
    (observed.loaded.locals id distinct.1 distinct.2.1 distinct.2.2.1 distinct.2.2.2.1 distinct.2.2.2.2 value notArray found)
    notArray different kept

end Lanius.Extraction.Entry.File
