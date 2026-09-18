import Lanius.Extraction.Entry.File.Resources
import Lanius.Extraction.Entry.File.Next.Output

namespace Lanius.Extraction.Entry.File.Next
open Lanius.Core Lanius.Semantics Lanius.Properties
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before after : State}

/-- Assemble the complete next file invocation from the successful body's
handoff. Only the next file's external input/capacity conditions remain
premises. All memory, grammar, working-buffer, slice, and cursor resources
are derived from the completed iteration. -/
theorem rebuild {argument : VarId}
    (current : Resources pipeline syntaxStage collectStage emitStage argument before)
    (frame : Handoff current.input current.data syntaxStage resultsStage argument emitStage.position after)
    (sameLocals : after.locals = before.locals)
    (selected : argument = pipeline.path.argument)
    (relation : Relation pipeline syntaxStage resultsStage)
    (emitRelation : Emit.Relation pipeline syntaxStage resultsStage collectStage emitStage)
    (registry : Allocation.Registry after) (representable : Host.RepresentableViews after)
    (views : ∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh)
    (path : String) (file : Lanius.World.FileEntry)
    (nextSelected : before.world.arguments[current.input.index + 1]? = some path)
    (fileFound : before.world.file? (Lanius.World.utf8Bytes path) = some file)
    (handleFit : before.world.nextFileHandle + 1 ≤ 2147483647)
    (indexFit : current.input.index + 2 ≤ 2147483647)
    (nonempty : 0 < path.toUTF8.size) (pathFits : path.toUTF8.size ≤ 1024)
    (pathRoom : (Lanius.World.utf8Bytes path).length ≤ current.input.packedPath.length * 4)
    (pathCapacity : (Lanius.World.utf8Bytes path).length ≤ current.input.pathOutput.length)
    (fileFits : file.bytes.length ≤ 65536) :
    ∃ next : Resources pipeline syntaxStage collectStage emitStage argument after,
      next.input.index = current.input.index + 1 ∧ next.input.path = path ∧ next.input.file = file ∧
      next.input.source = current.input.source ∧ next.input.packedPath = current.input.packedPath ∧
      next.input.pathOutput = current.input.pathOutput ∧ next.input.scratch = current.input.scratch ∧
      next.data.grammar = current.data.grammar ∧ next.data.grammarWords = current.data.grammarWords ∧
      next.data.bufferRoots = current.data.bufferRoots ∧
      next.semantic.view = current.semantic.view ∧ next.output.view = current.output.view ∧ 0 ≤ next.position := by
  let incoming : Load.Input pipeline after := {
    toAvailable := inputNext frame sameLocals selected relation current.positionRead registry representable views
      path file nextSelected fileFound handleFit current.olderHandles nonempty pathFits pathRoom pathCapacity
    fileFits := fileFits }
  have retained (view : I32ArrayView) (member : view ∈ before.i32ArrayViews) : view ∈ after.i32ArrayViews := by
    obtain ⟨fresh, equal⟩ := views
    rw [equal]
    exact List.mem_append_left _ member
  obtain ⟨data, valid, capacities, ⟨buffers⟩, sameGrammar, sameGrammarWords, sameRoots, sameBindings⟩ :=
    frontend incoming current.buffers current.valid current.capacities rfl rfl rfl rfl retained frame.grammar
  obtain ⟨semantic, semanticView, semanticLength⟩ := savedBuffer incoming current.semantic rfl rfl rfl rfl retained
  obtain ⟨output, outputView, outputLength⟩ := savedBuffer incoming current.output rfl rfl rfl rfl retained
  obtain ⟨cursor, nonnegative, cursorRead⟩ := position frame sameLocals
  have semanticId : emitStage.semantic = collectStage.semantic :=
    emitRelation.connected (emitStage.semantic, collectStage.semantic) (by simp [Emit.Stage.connections])
  have carriedSemantic : Carried pipeline syntaxStage resultsStage collectStage.semantic :=
    semanticId ▸ emitRelation.carried emitStage.semantic (by simp [Emit.Stage.carriedLocals])
  let next : Resources pipeline syntaxStage collectStage emitStage argument after := {
    input := incoming
    data, buffers, valid, capacities
    reads := syntaxReads frame sameLocals selected relation current.positionRead current.reads (sameBindings syntaxStage)
    kindsFit := sameGrammar ▸ current.kindsFit
    grammarIdentity := by simpa only [sameGrammar] using current.grammarIdentity
    semantic, output
    semanticCapacity := semanticLength.trans current.semanticCapacity
    outputCapacity := outputLength.trans current.outputCapacity
    semanticRead := savedRead frame sameLocals selected current.positionRead carriedSemantic current.semanticRead semanticView semanticLength
    outputRead := savedRead frame sameLocals selected current.positionRead
      (emitRelation.carried emitStage.output (by simp [Emit.Stage.carriedLocals])) current.outputRead outputView outputLength
    position := cursor
    positionRead := cursorRead
    semanticSeparate := by simpa only [sameRoots, semanticView] using current.semanticSeparate
    outputSeparate := by simpa only [sameRoots, outputView] using current.outputSeparate
    outputSemantic := by simpa only [semanticView, outputView] using current.outputSemantic
    differentCursors := by simpa only [State.cellId?, sameLocals] using current.differentCursors
    indexBound := indexFit
    olderHandles := olderHandles frame current.olderHandles }
  exact ⟨next, rfl, rfl, rfl, rfl, rfl, rfl, rfl, sameGrammar, sameGrammarWords, sameRoots,
    semanticView, outputView, nonnegative⟩

end Lanius.Extraction.Entry.File.Next
