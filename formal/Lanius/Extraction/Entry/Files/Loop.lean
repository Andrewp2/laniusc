import Lanius.Extraction.Entry.Files.Control
import Lanius.Extraction.Entry.Files.Progress

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

def statement (checked : File.Checked program) (countId : VarId) : Stmt :=
  .whileLoop (condition checked.argument countId) checked.body

/-- The loop retains external inputs and runtime typing on early errors. On
normal completion it additionally returns all ordered certificates in the
physical output allocation and both cursors at their stopping values. -/
structure Result (checked : File.Checked program) (context : Typing.Context)
    (countId : VarId) (count : Nat) (sources : List SourceFile) (outputRoot : CellId)
    (before : State) (completion : Completion) (after : State) : Prop where
  external : File.Result before completion after
  locals : after.locals = before.locals
  typed : ∃ store, RuntimeStateHasType program.core context after store
  completed : completion = .next →
    Allocation.Registry after ∧ Host.RepresentableViews after ∧
    (∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh) ∧
    Finished count sources outputRoot checked.emitStage.position after ∧
    after.local? checked.argument = some (.signed .i32 (count + 1 : Nat)) ∧
    after.local? countId = some (.signed .i32 (count + 1 : Nat))
  carriedLocals : completion = .next → ∀ id value,
    File.Carried checked.pipeline checked.syntaxStage checked.resultsStage id →
    before.local? id = some value → (∀ elements, value ≠ .array elements) →
    before.cellId? id ≠ before.cellId? checked.argument →
    before.cellId? id ≠ before.cellId? checked.emitStage.position → after.local? id = some value

/-- Execute the actual ordered-file loop, constructing every body execution
from `File.Checked.executes`. The domain describes available paths/files,
buffer capacity, scalar bindings, and integer/handle bounds. It assumes neither
successful parsing nor accepted certificates and allows classified frontend
or output-capacity failure at any iteration. Recursion consumes one requested
file, establishing finite fuel for the whole loop on this domain. -/
theorem executes (checked : File.Checked program) (countId : VarId)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage countId)
    (statementTyped : Typing.StmtHasType program.core returnType context true checked.body)
    (count : Nat) (countFit : count + 1 ≤ 2147483647)
    {before : State} {store : StoreTyping}
    (resources : File.Resources checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage checked.argument before)
    (typed : RuntimeStateHasType program.core context before store)
    (units : List CompactDecode.UnitData) (sources : List SourceFile) (request : Request) (rest : List Request)
    (history : History count units sources resources.position resources.output.contents)
    (progress : resources.input.index = units.length + 1)
    (endpoint : resources.input.index + (request :: rest).length = count + 1)
    (pending : Pending before.world resources.input.index (request :: rest))
    (handles : before.world.nextFileHandle + rest.length ≤ 2147483647)
    (pathRoom : 1024 ≤ resources.input.packedPath.length * 4)
    (pathCapacity : 1024 ≤ resources.input.pathOutput.length)
    (countRead : before.local? countId = some (.signed .i32 (count + 1 : Nat)))
    (apart : before.cellId? countId ≠ before.cellId? checked.emitStage.position) :
    ∃ completion after, Executes program.core before (statement checked countId) completion after ∧
      Result checked context countId count (sources ++ (request :: rest).map Request.source)
        resources.output.view.root before completion after ∧
      Progress ((request :: rest).map Request.source) checked.emitStage.position resources.position completion after := by
  have remaining : resources.input.index < count + 1 := by simp only [List.length_cons] at endpoint; omega
  have moreUnits : units.length < count := by simp only [List.length_cons] at endpoint; omega
  have indexRead : before.local? checked.argument = some (.signed .i32 resources.input.index) := by
    exact (congrArg (fun id => before.local? id) checked.advanceRelation.selected).trans resources.input.indexRead
  have test : Evaluates program.core before (condition checked.argument countId) (.boolean true) before := by
    have decision : decide (resources.input.index ≠ count + 1) = true := by
      simp only [decide_eq_true_eq]
      omega
    simpa only [decision] using
      condition_evaluates program.core resources.input.index (count + 1) indexRead countRead
  obtain ⟨completion, middle, bodyRun, result, fileProgress, advanced, sameLocals, middleStore, middleTyped⟩ :=
    checked.executes resources typed statementTyped
  have identity := pending.current resources.input
  have sourceHead {bound : Nat} (supported : SourceDomain request.source bound) :
      SourceDomain {path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} bound := by
    simpa only [identity.1, identity.2, Request.source] using supported
  rcases result.completion with next | failed | failed
  · subst completion
    obtain ⟨registry, representable, views, frame, emitted⟩ := advanced rfl
    have countAfter := count_after resources frame sameLocals carried countRead (by omega) apart
    have restored : restoreLocals before middle = middle := by unfold restoreLocals; rw [← sameLocals]
    have kept : ∀ id value, File.Carried checked.pipeline checked.syntaxStage checked.resultsStage id →
        before.local? id = some value → (∀ elements, value ≠ .array elements) →
        before.cellId? id ≠ before.cellId? checked.argument →
        before.cellId? id ≠ before.cellId? checked.emitStage.position → middle.local? id = some value := by
      intro id value carried read notArray argumentApart positionApart
      simpa only [restored] using frame.locals id value carried read notArray argumentApart positionApart
    have indexAfter : middle.local? checked.argument = some (.signed .i32 (resources.input.index + 1 : Nat)) := by
      simpa only [restored] using frame.index
    cases rest with
    | nil =>
      obtain ⟨unit, position, contents, nextHistory, size, stored, read⟩ :=
        history.emitted moreUnits resources.outputCapacity emitted sameLocals
      have indexEnd : resources.input.index + 1 = count + 1 := by simpa only [List.length_singleton] using endpoint
      have falseTest : Evaluates program.core middle (condition checked.argument countId) (.boolean false) middle := by
        simpa only [indexEnd, ne_eq, not_true_eq_false, decide_false] using
          condition_evaluates program.core (resources.input.index + 1) (count + 1) indexAfter countAfter
      refine ⟨.next, middle, executesWhileTrue test bodyRun (executesWhileFalse falseTest), ?_, ?_⟩
      · refine ⟨result, sameLocals, ⟨middleStore, middleTyped⟩, ?_, fun _ => kept⟩
        intro _
        refine ⟨registry, representable, views, ?_, ?_, countAfter⟩
        · refine ⟨units ++ [unit], position, contents, ?_, ?_, size, stored, read⟩
          · simpa only [List.map_cons, List.map_nil, Request.source, identity.1, identity.2] using nextHistory
          · simp only [List.length_append, List.length_singleton]; omega
        · simpa only [indexEnd] using indexAfter
      · intro bounds supported nonnegative room
        cases supported with
        | cons head tail =>
          cases tail
          obtain ⟨_, cursor, read, bounded⟩ := fileProgress _ (sourceHead head) nonnegative (by simpa using room)
          exact ⟨rfl, cursor, by simpa only [restored] using read, by simpa using bounded⟩
    | cons nextRequest tail =>
      have nextSelected := pending.selected 1 nextRequest (by simp)
      obtain ⟨nextResources, nextIndex, nextPath, nextFile, _source, packedPath, pathOutput, _scratch,
          _grammar, _grammarWords, _roots, _semantic, outputView, _position⟩ :=
        File.Next.rebuild resources frame sameLocals checked.advanceRelation.selected checked.nextRelation checked.emitRelation
          registry representable views nextRequest.path nextRequest.file nextSelected
          (pending.files nextRequest (by simp)) (by simp only [List.length_cons] at handles; omega)
          (by simp only [List.length_cons] at endpoint; omega)
          (pending.nonempty nextRequest (by simp)) (pending.pathFits nextRequest (by simp))
          (by have bound := pending.pathFits nextRequest (by simp); simpa only [Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size] using
                Nat.le_trans bound pathRoom)
          (by have bound := pending.pathFits nextRequest (by simp); simpa only [Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size] using
                Nat.le_trans bound pathCapacity)
          (pending.fileFits nextRequest (by simp))
      have nextStored : middle.cellEntry? resources.output.view.root = some {
          id := resources.output.view.root, value := some (.array (signedI32Values nextResources.output.contents)) } := by
        simpa only [outputView] using nextResources.output.stored
      obtain ⟨unit, nextHistory⟩ := history.afterFile moreUnits emitted sameLocals nextResources.positionRead nextStored
      have nextPending : Pending middle.world nextResources.input.index (nextRequest :: tail) := by
        rw [nextIndex]
        exact pending.tail result.arguments result.files
      have handleCounter : middle.world.nextFileHandle = before.world.nextFileHandle + 1 := by
        obtain ⟨reads, _, world⟩ := frame.world
        simp only [world, File.Load.Available.loadedWorld]
      obtain ⟨finalCompletion, after, restRun, restResult, restProgress⟩ := executes checked countId carried statementTyped count countFit
        nextResources middleTyped (units ++ [unit]) (sources ++ [request.source]) nextRequest tail
        (by simpa only [identity.1, identity.2, Request.source] using nextHistory)
        (by simp only [nextIndex, List.length_append, List.length_singleton]; omega)
        (by simp only [nextIndex, List.length_cons] at *; omega)
        nextPending (by simp only [handleCounter, List.length_cons] at *; omega)
        (by simpa only [packedPath] using pathRoom) (by simpa only [pathOutput] using pathCapacity)
        countAfter (by simpa only [State.cellId?, sameLocals] using apart)
      refine ⟨finalCompletion, after, executesWhileTrueThen test bodyRun restRun, ?_, ?_⟩
      · refine ⟨⟨restResult.external.completion, restResult.external.arguments.trans result.arguments,
          restResult.external.files.trans result.files, restResult.external.handles.trans result.handles,
          restResult.external.stdout.trans result.stdout,
          fun next => (restResult.external.stderr next).trans (result.stderr rfl)⟩,
          restResult.locals.trans sameLocals, restResult.typed, ?_, ?_⟩
        · intro finished
          obtain ⟨registered, words, laterViews, output, index, argc⟩ := restResult.completed finished
          refine ⟨registered, words, ?_, ?_, index, argc⟩
          · obtain ⟨first, firstViews⟩ := views
            obtain ⟨later, laterViews⟩ := laterViews
            exact ⟨first ++ later, by rw [laterViews, firstViews, List.append_assoc]⟩
          · simpa only [outputView, List.map_cons, List.append_assoc, List.singleton_append] using output
        · intro finished id value preserved read notArray argumentApart positionApart
          exact restResult.carriedLocals finished id value preserved
            (kept id value preserved read notArray argumentApart positionApart) notArray
            (by simpa only [State.cellId?, sameLocals] using argumentApart)
            (by simpa only [State.cellId?, sameLocals] using positionApart)
      · intro bounds supported nonnegative room
        cases supported with
        | @cons _ headBound _ remainingBounds head tail =>
          simp only [List.sum_cons] at room ⊢
          obtain ⟨_, cursor, read, cursorBound⟩ := fileProgress _ (sourceHead head) nonnegative (by omega)
          have same : nextResources.position = (cursor : Int) := by
            have value := nextResources.positionRead.symm.trans (by simpa only [restored] using read)
            simpa only [Option.some.injEq, Value.signed.injEq, true_and] using value
          have nextNonnegative : 0 ≤ nextResources.position := by rw [same]; omega
          have nextRoom : nextResources.position.toNat + remainingBounds.sum ≤ 16777216 := by
            rw [same, Int.toNat_natCast]
            omega
          obtain ⟨finished, finalCursor, finalRead, finalBound⟩ := restProgress _ tail nextNonnegative nextRoom
          refine ⟨finished, finalCursor, finalRead, ?_⟩
          rw [same, Int.toNat_natCast] at finalBound
          omega
  · subst completion
    refine ⟨_, middle, executesWhileReturned test bodyRun, ⟨
      result, sameLocals, ⟨middleStore, middleTyped⟩, fun impossible => Completion.noConfusion impossible,
      fun impossible => Completion.noConfusion impossible⟩, ?_⟩
    intro bounds supported nonnegative room
    cases supported with
    | cons head tail =>
      simp only [List.sum_cons] at room
      have impossible := (fileProgress _ (sourceHead head) nonnegative (by omega)).1
      cases impossible
  · subst completion
    refine ⟨_, middle, executesWhileReturned test bodyRun, ⟨
      result, sameLocals, ⟨middleStore, middleTyped⟩, fun impossible => Completion.noConfusion impossible,
      fun impossible => Completion.noConfusion impossible⟩, ?_⟩
    intro bounds supported nonnegative room
    cases supported with
    | cons head tail =>
      simp only [List.sum_cons] at room
      have impossible := (fileProgress _ (sourceHead head) nonnegative (by omega)).1
      cases impossible
termination_by rest.length

end Lanius.Extraction.Entry.Files
