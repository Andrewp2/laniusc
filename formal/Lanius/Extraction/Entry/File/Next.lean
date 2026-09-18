import Lanius.Extraction.Entry.File.Handoff
import Lanius.Extraction.Entry.Path.Buffers

namespace Lanius.Extraction.Entry.File.Next
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before after : State}
variable {input : Load.Input pipeline before} {data : SyntaxData}

/-- The five buffer/pointer locals reused when loading the next file. -/
def loadLocals (pipeline : Load.Pipeline program) : List VarId :=
  [pipeline.argument.pointer, pipeline.unpack.locals.packed, pipeline.unpack.locals.output,
    pipeline.read.output, pipeline.read.packed]

def Relation (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage) : Prop :=
  ∀ id ∈ loadLocals pipeline ++ syntaxStage.bufferLocals, Carried pipeline syntaxStage resultsStage id

def checkRelation? (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage) :
    Option (PLift (Relation pipeline syntaxStage resultsStage)) :=
  if valid : ∀ id ∈ loadLocals pipeline ++ syntaxStage.bufferLocals, id ∉ pipeline.boundLocals ∧ syntaxStage.result ≠ id ∧
      id ≠ resultsStage.nodes ∧ id ≠ resultsStage.tokens then some ⟨valid⟩ else none

/-- Pointer and slice values cannot alias either scalar cursor. This derives
the physical separation from existing reads, rather than assuming all local
names denote different cells. -/
theorem stableLocal {argument positionId id : VarId} {position : Int} {value : Value}
    (frame : Handoff input data syntaxStage resultsStage argument positionId after)
    (sameLocals : after.locals = before.locals)
    (selected : argument = pipeline.path.argument)
    (positionRead : before.local? positionId = some (.signed .i32 position))
    (carried : Carried pipeline syntaxStage resultsStage id)
    (found : before.local? id = some value)
    (notArray : ∀ elements, value ≠ .array elements)
    (notScalar : ∀ scalar, value ≠ .signed .i32 scalar) : after.local? id = some value := by
  have different {cursor : VarId} {number : Int}
      (read : before.local? cursor = some (.signed .i32 number)) : before.cellId? id ≠ before.cellId? cursor := by
    intro same
    have equal : before.local? id = before.local? cursor := by simp only [State.local?, same]
    exact notScalar number (Option.some.inj (found.symm.trans (equal.trans read)))
  have restored : restoreLocals before after = after := by
    unfold restoreLocals
    rw [← sameLocals]
  simpa only [restored] using frame.locals id value carried found notArray
    (different (selected.symm ▸ input.indexRead)) (different positionRead)

/-- The next path's buffers survive a completed file regardless of whether
that next path is valid or its file exists. No next-file input is fabricated. -/
def pathBuffers {argument positionId : VarId} {position : Int}
    (frame : Handoff input data syntaxStage resultsStage argument positionId after)
    (sameLocals : after.locals = before.locals)
    (selected : argument = pipeline.path.argument)
    (relation : Relation pipeline syntaxStage resultsStage)
    (positionRead : before.local? positionId = some (.signed .i32 position))
    (views : ∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh)
    (packedLength : input.packedPath.length = 256) (outputLength : input.pathOutput.length = 1024) :
    Path.Buffers pipeline.argument pipeline.unpack after := by
  have retained {view : I32ArrayView} (member : view ∈ before.i32ArrayViews) : view ∈ after.i32ArrayViews := by
    obtain ⟨fresh, equal⟩ := views
    rw [equal]
    exact List.mem_append_left _ member
  have preserved {id : VarId} {value : Value} (member : id ∈ loadLocals pipeline)
      (found : before.local? id = some value) (notArray : ∀ elements, value ≠ .array elements)
      (notScalar : ∀ scalar, value ≠ .signed .i32 scalar) : after.local? id = some value :=
    stableLocal frame sameLocals selected positionRead (relation id (List.mem_append_left _ member)) found notArray notScalar
  exact {
    packed := input.packedPath
    output := input.pathOutput
    packedMember := retained input.packedPathMember
    outputMember := retained input.pathMember
    pointerRead := preserved (by simp [loadLocals]) input.pointerRead
      (by intro elements same; cases same) (by intro scalar same; cases same)
    packedRead := preserved (by simp [loadLocals]) input.packedPathRead
      (by intro elements same; cases same) (by intro scalar same; cases same)
    outputRead := preserved (by simp [loadLocals]) input.pathRead
      (by intro elements same; cases same) (by intro scalar same; cases same)
    packedLength, outputLength
    distinct := input.pathDistinct }

/-- Construct all loading resources for the next requested file from the
completed iteration. The new premises describe that next external file and
remaining numeric capacity, not intermediate execution or memory invariants. -/
def inputNext {argument positionId : VarId} {position : Int}
    (frame : Handoff input data syntaxStage resultsStage argument positionId after)
    (sameLocals : after.locals = before.locals)
    (selected : argument = pipeline.path.argument)
    (relation : Relation pipeline syntaxStage resultsStage)
    (positionRead : before.local? positionId = some (.signed .i32 position))
    (registry : Allocation.Registry after) (representable : Host.RepresentableViews after)
    (views : ∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh)
    (path : String) (file : Lanius.World.FileEntry)
    (nextSelected : before.world.arguments[input.index + 1]? = some path)
    (fileFound : before.world.file? (Lanius.World.utf8Bytes path) = some file)
    (handleFit : before.world.nextFileHandle + 1 ≤ 2147483647)
    (olderHandles : ∀ handle ∈ before.world.fileHandles, handle.id < (before.world.nextFileHandle : Int))
    (nonempty : 0 < path.toUTF8.size) (pathFits : path.toUTF8.size ≤ 1024)
    (pathRoom : (Lanius.World.utf8Bytes path).length ≤ input.packedPath.length * 4)
    (pathCapacity : (Lanius.World.utf8Bytes path).length ≤ input.pathOutput.length) : Load.Available pipeline after := by
  have world : after.world.arguments = before.world.arguments ∧ after.world.files = before.world.files ∧
      after.world.nextFileHandle = before.world.nextFileHandle + 1 ∧
      after.world.fileHandles = before.world.fileHandles := by
    obtain ⟨reads, _, equal⟩ := frame.world
    rw [equal]
    exact ⟨rfl, rfl, rfl, rfl⟩
  have retained {view : I32ArrayView} (member : view ∈ before.i32ArrayViews) : view ∈ after.i32ArrayViews := by
    obtain ⟨fresh, equal⟩ := views
    rw [equal]
    exact List.mem_append_left _ member
  have preserved {id : VarId} {value : Value} (member : id ∈ loadLocals pipeline)
      (found : before.local? id = some value) (notArray : ∀ elements, value ≠ .array elements)
      (notScalar : ∀ scalar, value ≠ .signed .i32 scalar) : after.local? id = some value :=
    stableLocal frame sameLocals selected positionRead (relation id (List.mem_append_left _ member)) found notArray notScalar
  refine {
    index := input.index + 1
    path, file
    packedPath := input.packedPath
    pathOutput := input.pathOutput
    source := input.source
    scratch := input.scratch
    registry, representable
    packedPathMember := retained input.packedPathMember
    pathMember := retained input.pathMember
    sourceMember := retained input.sourceMember
    scratchMember := retained input.scratchMember
    indexRead := ?_
    pointerRead := preserved (by simp [loadLocals]) input.pointerRead
      (by intro elements same; cases same) (by intro scalar same; cases same)
    packedPathRead := preserved (by simp [loadLocals]) input.packedPathRead
      (by intro elements same; cases same) (by intro scalar same; cases same)
    pathRead := preserved (by simp [loadLocals]) input.pathRead
      (by intro elements same; cases same) (by intro scalar same; cases same)
    sourceRead := preserved (by simp [loadLocals]) input.sourceRead
      (by intro elements same; cases same) (by intro scalar same; cases same)
    scratchRead := preserved (by simp [loadLocals]) input.scratchRead
      (by intro elements same; cases same) (by intro scalar same; cases same)
    selected := ?_
    fileFound := ?_
    handleFit := ?_
    fresh := ?_
    pathNonempty := nonempty
    pathFits, pathRoom, pathCapacity
    pathBound := input.pathBound
    pathDistinct := input.pathDistinct
    sourcePackedPathDistinct := input.sourcePackedPathDistinct
    sourcePathDistinct := input.sourcePathDistinct
    sourceScratchDistinct := input.sourceScratchDistinct
    pathScratchDistinct := input.pathScratchDistinct
    sourceCapacity := input.sourceCapacity
    sourceBound := input.sourceBound
    scratchCapacity := input.scratchCapacity
    sizeFit := input.sizeFit }
  · have restored : restoreLocals before after = after := by
      unfold restoreLocals
      rw [← sameLocals]
    simpa only [restored, selected] using frame.index
  · simpa only [world.1] using nextSelected
  · simpa only [Lanius.World.State.file?, world.2.1] using fileFound
  · simpa only [world.2.2.1] using handleFit
  · intro handle member
    have old := olderHandles handle (by simpa only [world.2.2.2] using member)
    simp only [world.2.2.1]
    omega

end Lanius.Extraction.Entry.File.Next
