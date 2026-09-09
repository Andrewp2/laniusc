import Lanius.Extraction.Allocation.Sequence

namespace Lanius.Extraction.Entry

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.CallContracts

theorem evaluatesArgc
    {program : Program} {function : Function} {before : State}
    (functionFound : program.function? function.id = some function)
    (parameters : function.parameters = []) (noBody : function.body = none)
    (host : function.external = some (.host .argc))
    (empty : before.i32ArrayViews = []) :
    Evaluates program before (.call function.id [])
      (Lanius.World.i32Result before.world.arguments.length)
      { before with world := Lanius.World.record before.world .argc } := by
  apply evaluatesHostCallReturned (ArgumentsEvaluateTo.nil program before) functionFound
    (bindings := []) (ready := before) (heap := before.heap)
    (world := Lanius.World.record before.world .argc)
    (by simp [bindParameters, parameters]) noBody host
  · simp [syncI32ViewsToHeap, empty, syncI32ViewsToHeapFrom]
  · simp [Lanius.World.call, Lanius.World.callSimple, Lanius.World.record]
  · simp [syncI32ViewsFromHeap, empty, syncI32ViewsFromHeapFrom]

structure Arguments where
  function : FunctionId
  count : Lanius.VarId
  continuation : Stmt

def Arguments.statement (entry : Arguments) : Stmt :=
  .letLocal entry.count (.scalar (.signed .i32)) (.call entry.function [])
    (.sequence (.ifThenElse
      (.binary .lessEqual (.local entry.count) (.value (.signed .i32 1)))
      (.sequence (.returnValue (some (.value (.signed .i32 1)))) .skip) .skip)
      entry.continuation)

def Arguments.ready (entry : Arguments) (before : State) : State :=
  ({ before with world := Lanius.World.record before.world .argc }).bindLocal entry.count
    (.signed .i32 before.world.arguments.length)

/-- A supported argument count reaches the continuation with an empty, valid
view registry. This derives the allocation component's initial resource state. -/
theorem Arguments.executes
    {program : Program} {function : Function} (entry : Arguments) (before : State)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (identity : entry.function = function.id)
    (functionFound : program.function? function.id = some function)
    (parameters : function.parameters = []) (noBody : function.body = none)
    (host : function.external = some (.host .argc))
    (wellFormed : StateWellFormed before) (empty : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length)
    (bounded : before.world.arguments.length < 2 ^ 31)
    (continuationRun : Allocation.Registry (entry.ready before) →
      ∃ after, Executes program (entry.ready before) entry.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before entry.statement completion after ∧ post after.world := by
  have lower : (0 : Int) ≤ before.world.arguments.length := Int.natCast_nonneg _
  have upper : (before.world.arguments.length : Int) < 2 ^ 32 := by omega
  have sign : ¬ (before.world.arguments.length : Int) ≥ 2 ^ 31 := by omega
  have result : Lanius.World.i32Result before.world.arguments.length =
      .signed .i32 before.world.arguments.length := by
    simp only [Lanius.World.i32Result, Lanius.World.wrapI32,
      Int.emod_eq_of_lt lower upper, if_neg sign]
  let called : State := { before with world := Lanius.World.record before.world .argc }
  have calledValid : StateWellFormed called :=
    ⟨wellFormed.heapWellFormed, wellFormed.cellIdsUnique,
      wellFormed.cellIdsBelowNext, wellFormed.localsReferenceCells⟩
  have evaluated := evaluatesArgc functionFound parameters noBody host empty
  rw [result] at evaluated
  have read : (entry.ready before).local? entry.count = some (.signed .i32 before.world.arguments.length) := by
    have fresh := bindCell_finds_fresh_cell called entry.count
      (some (.signed .i32 before.world.arguments.length)) calledValid
    simp only [Arguments.ready, State.bindLocal, State.local?, State.cellId?, State.bindCell,
      List.find?_cons, beq_self_eq_true]
    exact congrArg (fun cell => cell.bind Cell.value) fresh
  have test : Evaluates program (entry.ready before)
      (.binary .lessEqual (.local entry.count) (.value (.signed .i32 1)))
      (.boolean false) (entry.ready before) := by
    apply evaluatesEagerBinary (by decide) (by decide)
      ⟨1, evalLocal_of_local 0 program _ _ _ read⟩
      (show Evaluates program (entry.ready before) (.value (.signed .i32 1)) (.signed .i32 1)
        (entry.ready before) from ⟨1, rfl⟩)
    have greater : ¬ (before.world.arguments.length : Int) ≤ 1 := by omega
    simp [evalBinaryValue, evalSignedBinary, greater]
  have registry : Allocation.Registry (entry.ready before) :=
    (Allocation.Registry.of_empty_views calledValid empty).bindLocal _ _
  obtain ⟨after, continued, satisfied⟩ := continuationRun registry
  refine ⟨restoreLocals called after, ?_, satisfied⟩
  unfold Arguments.statement
  rw [identity]
  exact executesLetLocal evaluated
    (executesSequence (executesIfFalse test (executesSkip program _)) continued)

structure CheckedArguments (program : Program) (source : Stmt) where
  entry : Arguments
  exactSource : source = entry.statement
  function : Function
  identity : entry.function = function.id
  found : program.function? function.id = some function
  parameters : function.parameters = []
  noBody : function.body = none
  host : function.external = some (.host .argc)

def checkArguments? (program : Program) (source : Stmt) : Option (CheckedArguments program source) :=
  match source with
  | .letLocal count (.scalar (.signed .i32)) (.call id [])
      (.sequence (.ifThenElse (.binary .lessEqual (.local readCount) (.value (.signed .i32 1)))
        (.sequence (.returnValue (some (.value (.signed .i32 1)))) .skip) .skip) continuation) =>
      match found : program.function? id with
      | none => none
      | some function =>
          if shape : readCount = count ∧ function.parameters = [] ∧ function.body = none ∧
              function.external = some (.host .argc) then
            some ⟨⟨id, count, continuation⟩, by
              rcases shape with ⟨rfl, _⟩
              rfl,
              function, by
                have identity : function.id = id := by simpa using (List.find?_some found)
                exact identity.symm,
              by
                have identity : function.id = id := by simpa using (List.find?_some found)
                simpa only [identity] using found,
              shape.2.1, shape.2.2.1, shape.2.2.2⟩
          else none
  | _ => none

theorem CheckedArguments.executes (checked : CheckedArguments program source) (before : State)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : StateWellFormed before) (empty : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
    (continuationRun : Allocation.Registry (checked.entry.ready before) →
      ∃ after, Executes program (checked.entry.ready before) checked.entry.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before source completion after ∧ post after.world := by
  obtain ⟨after, executed, satisfied⟩ := checked.entry.executes before completion post
    checked.identity checked.found checked.parameters checked.noBody checked.host
    wellFormed empty enough bounded continuationRun
  exact ⟨after, checked.exactSource.symm ▸ executed, satisfied⟩

/-- Compose the checked argument entry and allocation sequence. The empty
initial registry is derived, rather than left as an intermediate premise. -/
theorem CheckedArguments.allocate (checked : CheckedArguments program source)
    (allocator : Allocation.CheckedAllocator program) (sequence : Allocation.Sequence)
    (continuation : checked.entry.continuation = sequence.statement allocator.function.id)
    (before : State) (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : StateWellFormed before) (empty : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
    (room : ∀ available, before.heap.remaining = some available → Allocation.byteCount sequence.buffers ≤ available)
    (continuationRun : ∀ ready, Allocation.HostReady sequence.buffers (checked.entry.ready before) ready →
      Allocation.Registry ready →
      ∃ after, Executes program ready sequence.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before source completion after ∧ post after.world := by
  apply checked.executes before completion post wellFormed empty enough bounded
  intro registry
  obtain ⟨after, executed, satisfied⟩ := allocator.executes sequence (checked.entry.ready before)
    completion post registry room continuationRun
  exact ⟨after, continuation.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry
