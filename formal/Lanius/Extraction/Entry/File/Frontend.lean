import Lanius.Extraction.Entry.File.Load
import Lanius.Extraction.Frontend.Capacity.Call

namespace Lanius.Extraction.Entry.File.Load
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend
open Lanius.Extraction.RawLexer.LexInto

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Pipeline program} {before ready : State} {input : Input pipeline before} {data : SyntaxData}

/-- The seven non-source frontend buffers already exist before file loading.
Their registered views are disjoint from the path/read scratch writes. The
source bytes are the selected file's bytes, not an assumed parse result. -/
structure FrontendBuffers (input : Input pipeline before) (data : SyntaxData) where
  sourceCell : data.sourceCell = input.source.root
  sourceBytes : data.request.source = input.file.bytes.map UInt8.toFin
  other : ∀ buffer ∈ (data.buffers []).tail, ∃ view : I32ArrayView,
    view ∈ before.i32ArrayViews ∧ view.root = buffer.1 ∧
    view.root ≠ input.packedPath.root ∧ view.root ≠ input.pathOutput.root ∧
    view.root ≠ input.source.root ∧ view.root ≠ input.scratch.root ∧
    before.cellEntry? buffer.1 = some { id := buffer.1, value := some (.array (signedI32Values buffer.2)) }

theorem FrontendBuffers.sourceGrammar (buffers : FrontendBuffers input data) : data.sourceCell ≠ data.grammarCell := by
  obtain ⟨view, _, root, _, _, apart, _, _⟩ := buffers.other (data.grammarCell, data.grammarWords) (by simp [SyntaxData.buffers])
  intro same
  exact apart (root.trans (same.symm.trans buffers.sourceCell))

/-- File loading establishes the public padded frontend's complete physical
ownership predicate and the exact logical/physical length relation. -/
theorem Loaded.frontend_input (loaded : Loaded input ready) (buffers : FrontendBuffers input data) :
    ∃ tail : List Int, data.request.source.length + tail.length = input.source.length ∧ data.PaddedOwns tail ready := by
  obtain ⟨original, originalLength, _, sourceContents⟩ := loaded.source
  let tail := original.drop input.file.bytes.length
  have length : data.request.source.length + tail.length = input.source.length := by
    have fits := input.fileFits
    have capacity := input.sourceCapacity
    simp only [buffers.sourceBytes, List.length_map, tail, List.length_drop, originalLength]
    omega
  refine ⟨tail, length, ?_⟩
  intro buffer member
  change buffer ∈ (data.sourceCell, CanonicalTokens.CanonicalizeModel.sourceIntegers data.request.source ++ tail) ::
    (data.buffers []).tail at member
  rcases List.mem_cons.mp member with rfl | other
  · simpa only [buffers.sourceCell, buffers.sourceBytes, CanonicalTokens.CanonicalizeModel.sourceIntegers,
      List.map_map, Function.comp_def, UInt8.toFin_val, Int.ofNat_eq_natCast,
      Extraction.Input.copiedBuffer, List.nil_append, tail] using sourceContents
  · obtain ⟨view, member, root, packedApart, pathApart, sourceApart, scratchApart, contents⟩ := buffers.other buffer other
    have stored : before.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values buffer.2)) } := by
      simpa only [root] using contents
    have preserved := loaded.preserved input.registry.disjoint view member
      ⟨input.registry.apart input.packedPathMember member packedApart.symm, pathApart, sourceApart, scratchApart⟩ buffer.2
      (by simp only [readCellProjection, input.registry.roots view member, stored, projectedValue])
      (input.representable view member buffer.2 stored)
    simpa only [root] using preserved

/-- Use the frontend's physical buffer capacity at the file-loop boundary;
the logical count still comes from the completed read. Argument evaluation
is the usual call-administration premise, not a lexer/parser execution. -/
theorem Loaded.frontend_evaluates
    {visit : ParserTreeSource.CheckedVisit program} {materializer : ParserTreeSource.CheckedMaterialize visit}
    (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (fragment : Semantics.Capacity.Fragment.Checked program.core allowed)
    (included : allowed checked.source.function.id = true)
    (loaded : Loaded input ready) (buffers : FrontendBuffers input data) (valid : data.Valid)
    (argumentsResult : ArgumentsEvaluateTo program.core ready arguments
      (.slice Structure.i32Type data.sourceCell [] 0 input.source.length :: data.values.tail) ready) :
    ∃ tail : List Int, ∃ stage detail : Int, ∃ count nodes words : Nat, ∃ position : Int, ∃ after,
      data.request.source.length + tail.length = input.source.length ∧
      Evaluates program.core ready (.call checked.source.function.id arguments)
        (syntaxResult checked.tail.finish.constructor.typeId stage detail data.raw.length count nodes words position) after ∧
      data.Post stage detail count nodes words position ready after ∧ data.PaddedRawOutput tail after ∧
      CellEffect data.writes ready after ∧ Host.MemoryTail program.core ready after := by
  obtain ⟨tail, length, owned⟩ := loaded.frontend_input buffers
  have arguments : ArgumentsEvaluateTo program.core ready arguments (data.paddedValues tail.length) ready := by
    simpa only [SyntaxData.paddedValues, length] using argumentsResult
  obtain ⟨stage, detail, count, nodes, words, position, after, run, post, raw, effect, memory⟩ :=
    checked.padded_call_evaluates linked fragment included data valid buffers.sourceGrammar loaded.registry.wellFormed owned arguments
  exact ⟨tail, stage, detail, count, nodes, words, position, after, length, run, post, raw, effect, memory⟩

end Lanius.Extraction.Entry.File.Load
