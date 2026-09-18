import Lanius.Extraction.Entry.Files.Control
import Lanius.Extraction.Entry.Files.Loop
import Lanius.Extraction.Entry.File.Rejection

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Extraction.ExtractorContract

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

/-- A loadable prefix followed by an invalid/missing path or oversized file terminates with a
classified failure. A preceding file may itself fail extraction or encoding;
otherwise the rejected argument is reached using the actual retained buffers.
No successful execution of the prefix is assumed. -/
theorem rejectsAfter (checked : File.Checked program) (countId : VarId)
    (diagnostics : Diagnostics.Read.Checked program checked.pipeline.path.argument checked.pipeline.read.count checked.pipeline.read.failure)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage countId)
    (statementTyped : Typing.StmtHasType program.core returnType context true checked.body)
    (limit : Nat) (countFit : limit ≤ 2147483647)
    {before : State} {store : StoreTyping}
    (resources : File.Resources checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage checked.argument before)
    (typed : RuntimeStateHasType program.core context before store)
    (request : Request) (rest : List Request)
    (pending : Pending before.world resources.input.index (request :: rest))
    (issue : File.Rejection before.world (resources.input.index + (request :: rest).length) rejectedCode)
    (beforeEnd : resources.input.index + (request :: rest).length < limit)
    (handles : before.world.nextFileHandle + rest.length + File.Rejection.additionalHandles rejectedCode ≤ 2147483647)
    (packedLength : resources.input.packedPath.length = 256)
    (outputLength : resources.input.pathOutput.length = 1024)
    (countRead : before.local? countId = some (.signed .i32 limit))
    (apart : before.cellId? countId ≠ before.cellId? checked.emitStage.position) :
    ∃ code after, Executes program.core before (statement checked countId)
        (.returned (some (.signed .i32 code))) after ∧
      Nonempty (Failure before after code) ∧ after.world.standardOutput = before.world.standardOutput := by
  have remaining : resources.input.index < limit := by simp only [List.length_cons] at beforeEnd; omega
  have indexRead : before.local? checked.argument = some (.signed .i32 resources.input.index) :=
    (congrArg (fun id => before.local? id) checked.advanceRelation.selected).trans resources.input.indexRead
  have test : Evaluates program.core before (condition checked.argument countId) (.boolean true) before := by
    simpa [Nat.ne_of_lt remaining] using condition_evaluates program.core resources.input.index limit indexRead countRead
  obtain ⟨completion, middle, bodyRun, result, _progress, advanced, sameLocals, middleStore, middleTyped⟩ :=
    checked.executes resources typed statementTyped
  rcases result.completion with next | encoded | extracted
  · subst completion
    obtain ⟨registry, representable, views, frame, _emitted⟩ := advanced rfl
    have countAfter := count_after resources frame sameLocals carried countRead (by omega) apart
    have restored : restoreLocals before middle = middle := by unfold restoreLocals; rw [← sameLocals]
    have indexAfter : middle.local? checked.argument = some (.signed .i32 (resources.input.index + 1 : Nat)) := by
      simpa only [restored] using frame.index
    cases rest with
    | nil =>
      have bad : File.Rejection before.world (resources.input.index + 1) rejectedCode := by
        simpa only [List.length_singleton] using issue
      obtain ⟨after, rejected, ⟨failure⟩, stdout⟩ := bad.afterFile checked diagnostics resources frame sameLocals
        registry representable views (by simpa only [List.length_nil, Nat.add_zero] using handles)
        (by simp only [List.length_singleton] at beforeEnd; omega) packedLength outputLength
      have rejectTest : Evaluates program.core middle (condition checked.argument countId) (.boolean true) middle := by
        have less : resources.input.index + 1 < limit := by simpa only [List.length_singleton] using beforeEnd
        simpa [Nat.ne_of_lt less] using condition_evaluates program.core (resources.input.index + 1) limit indexAfter countAfter
      exact ⟨rejectedCode, after, executesWhileTrueThen test bodyRun (executesWhileReturned rejectTest rejected),
        ⟨⟨failure.nonzero, failure.classified, failure.arguments.trans result.arguments,
          failure.files.trans result.files, failure.handles.trans result.handles, failure.memorySafe⟩⟩,
        stdout.trans result.stdout⟩
    | cons nextRequest tail =>
      obtain ⟨nextResources, nextIndex, _nextPath, _nextFile, _source, packedPath, pathOutput, _scratch,
          _grammar, _words, _roots, _semantic, _output, _position⟩ :=
        File.Next.rebuild resources frame sameLocals checked.advanceRelation.selected checked.nextRelation checked.emitRelation
          registry representable views nextRequest.path nextRequest.file (pending.selected 1 nextRequest (by simp))
          (pending.files nextRequest (by simp)) (by simp only [List.length_cons] at handles; omega)
          (by simp only [List.length_cons] at beforeEnd; omega)
          (pending.nonempty nextRequest (by simp)) (pending.pathFits nextRequest (by simp))
          (by simpa only [packedLength, Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size] using pending.pathFits nextRequest (by simp))
          (by simpa only [outputLength, Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size] using pending.pathFits nextRequest (by simp))
          (pending.fileFits nextRequest (by simp))
      have nextPending : Pending middle.world nextResources.input.index (nextRequest :: tail) := by
        rw [nextIndex]
        exact pending.tail result.arguments result.files
      have nextIssue : File.Rejection middle.world (nextResources.input.index + (nextRequest :: tail).length) rejectedCode := by
        have same : nextResources.input.index + (nextRequest :: tail).length =
            resources.input.index + (request :: nextRequest :: tail).length := by
          simp only [nextIndex, List.length_cons]
          omega
        rw [same]
        exact issue.transport result.arguments result.files
      have handleCounter : middle.world.nextFileHandle = before.world.nextFileHandle + 1 := by
        obtain ⟨reads, _, world⟩ := frame.world
        simp only [world, File.Load.Available.loadedWorld]
      obtain ⟨code, after, restRun, ⟨failure⟩, stdout⟩ := rejectsAfter checked countId diagnostics carried statementTyped limit countFit
        nextResources middleTyped nextRequest tail nextPending nextIssue
        (by simp only [nextIndex, List.length_cons] at *; omega)
        (by simp only [handleCounter, List.length_cons] at *; omega)
        (by simpa only [packedPath] using packedLength) (by simpa only [pathOutput] using outputLength)
        countAfter (by simpa only [State.cellId?, sameLocals] using apart)
      exact ⟨code, after, executesWhileTrueThen test bodyRun restRun,
        ⟨⟨failure.nonzero, failure.classified, failure.arguments.trans result.arguments,
          failure.files.trans result.files, failure.handles.trans result.handles, failure.memorySafe⟩⟩,
        stdout.trans result.stdout⟩
  · subst completion
    exact ⟨21, middle, executesWhileReturned test bodyRun,
      ⟨⟨by decide, .encodeUnit, result.arguments, result.files, result.handles,
        memorySafe_of_runtimeStateHasType middleTyped⟩⟩, result.stdout⟩
  · subst completion
    exact ⟨28, middle, executesWhileReturned test bodyRun,
      ⟨⟨by decide, .extraction, result.arguments, result.files, result.handles,
        memorySafe_of_runtimeStateHasType middleTyped⟩⟩, result.stdout⟩
termination_by rest.length

end Lanius.Extraction.Entry.Files
