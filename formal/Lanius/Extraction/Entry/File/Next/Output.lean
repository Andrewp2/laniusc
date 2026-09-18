import Lanius.Extraction.Entry.File.Next.Frontend

namespace Lanius.Extraction.Entry.File.Next
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before after : State}
variable {input : Load.Input pipeline before} {data : SyntaxData}

/-- Reuse a semantic/output allocation with its current contents. In
particular, this does not replace an accumulated output prefix with the
original allocation contents. -/
theorem savedBuffer (nextInput : Load.Input pipeline after) (saved : SavedBuffer input)
    (sameSource : nextInput.source = input.source)
    (samePackedPath : nextInput.packedPath = input.packedPath)
    (samePath : nextInput.pathOutput = input.pathOutput)
    (sameScratch : nextInput.scratch = input.scratch)
    (retained : ∀ view ∈ before.i32ArrayViews, view ∈ after.i32ArrayViews) :
    ∃ nextSaved : SavedBuffer nextInput, nextSaved.view = saved.view ∧
      nextSaved.contents.length = saved.contents.length := by
  obtain ⟨elements, read, length, _⟩ := input.registry.arrays saved.view saved.member
  have exactValues : elements = signedI32Values saved.contents := by
    simpa only [readCellProjection, input.registry.roots saved.view saved.member, saved.stored, projectedValue,
      Except.ok.injEq, Value.array.injEq] using read.symm
  have oldLength : saved.contents.length = saved.view.length := by
    simpa only [exactValues, signedI32Values, List.length_map] using length
  obtain ⟨words, size, stored⟩ := nextInput.registry.storage (retained saved.view saved.member)
  exact ⟨{
    view := saved.view
    contents := words
    member := retained saved.view saved.member
    packedPath := samePackedPath.symm ▸ saved.packedPath
    path := samePath.symm ▸ saved.path
    source := sameSource.symm ▸ saved.source
    scratch := sameScratch.symm ▸ saved.scratch
    stored }, rfl, size.trans oldLength.symm⟩

theorem savedRead {argument positionId id : VarId} {position : Int}
    {nextInput : Load.Input pipeline after} {saved : SavedBuffer input} {nextSaved : SavedBuffer nextInput}
    (frame : Handoff input data syntaxStage resultsStage argument positionId after)
    (sameLocals : after.locals = before.locals) (selected : argument = pipeline.path.argument)
    (positionRead : before.local? positionId = some (.signed .i32 position))
    (carried : Carried pipeline syntaxStage resultsStage id)
    (read : before.local? id = some (.slice i32 saved.view.root [] 0 saved.contents.length))
    (sameView : nextSaved.view = saved.view) (sameLength : nextSaved.contents.length = saved.contents.length) :
    after.local? id = some (.slice i32 nextSaved.view.root [] 0 nextSaved.contents.length) := by
  rw [sameView, sameLength]
  exact stableLocal frame sameLocals selected positionRead carried read
    (by intro elements same; cases same) (by intro scalar same; cases same)

/-- The successful emitter's cursor is available in the actual returned
state once the outer file scope has closed. -/
theorem position {argument positionId : VarId}
    (frame : Handoff input data syntaxStage resultsStage argument positionId after)
    (sameLocals : after.locals = before.locals) :
    ∃ cursor : Int, 0 ≤ cursor ∧ after.local? positionId = some (.signed .i32 cursor) := by
  have restored : restoreLocals before after = after := by
    unfold restoreLocals
    rw [← sameLocals]
  simpa only [restored] using frame.cursor

/-- Existing handles remain older than the next fresh-handle counter after
the just-opened input handle has been closed. -/
theorem olderHandles {argument positionId : VarId}
    (frame : Handoff input data syntaxStage resultsStage argument positionId after)
    (older : ∀ handle ∈ before.world.fileHandles, handle.id < (before.world.nextFileHandle : Int)) :
    ∀ handle ∈ after.world.fileHandles, handle.id < (after.world.nextFileHandle : Int) := by
  obtain ⟨reads, _, world⟩ := frame.world
  intro handle member
  have old := older handle (by simpa only [world, Load.Available.loadedWorld] using member)
  simp only [world, Load.Available.loadedWorld]
  omega

end Lanius.Extraction.Entry.File.Next
