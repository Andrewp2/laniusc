import Lanius.Extraction.Host.File.Read

namespace Lanius.Extraction.Host.File

open Lanius.Core Lanius.Semantics Lanius.CallContracts

def openedWorld (world : Lanius.World.State) (path : List UInt8) : Lanius.World.State := {
  world with
  calls := world.calls ++ [.openRead]
  fileHandles := world.fileHandles ++ [{ id := world.nextFileHandle, path, readable := true }]
  nextFileHandle := world.nextFileHandle + 1 }

/-- Open the exact path that was copied into the packed argument buffer.
The byte load after synchronization and both synchronization passes follow
from the retained resources; a matching readable file is the host premise. -/
theorem evaluatesOpen (checked : CheckedExternal program .openRead 2)
    (initial : Allocation.Registry before) (copied : Copied view path before)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ before.i32ArrayViews)
    (fileFound : before.world.file? path = some file)
    (bounded : before.world.nextFileHandle ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments [.pointer view.address, .unsigned .usize path.length] before) :
    ∃ after, Evaluates program caller (.call checked.function.id arguments)
        (.signed .i32 before.world.nextFileHandle) after ∧
      Allocation.Registry after ∧ Frame before after ∧ after.world = openedWorld before.world path ∧
      PreservesViews before after (fun _ => True) := by
  obtain ⟨bindings, bound⟩ := checked.bindings [.pointer view.address, .unsigned .usize path.length] rfl
  have call (ready : State) (synced : syncI32ViewsToHeap before = .ok ready) :
      Lanius.World.call ready.heap ready.world .openRead [.pointer view.address, .unsigned .usize path.length] =
        .returned (.signed .i32 before.world.nextFileHandle) ready.heap (openedWorld before.world path) := by
    have loaded := copied.loadAfterSync initial disjoint member synced
    rw [Lanius.Properties.syncI32ViewsToHeap_preserves_world synced]
    have found : (Lanius.World.record before.world .openRead).file? path = some file := fileFound
    simp only [Lanius.World.call, Lanius.World.callSimple, loaded, BEq.rfl, bne_self_eq_false,
      show (HostService.openRead == HostService.openAppend) = false from rfl]
    rw [Lanius.World.openFile_read_exact found]
    simp only [Lanius.World.record, openedWorld]
    rw [show Lanius.World.i32Result (Int.ofNat before.world.nextFileHandle) =
      .signed .i32 before.world.nextFileHandle from i32Result_nat bounded]
    rfl
  obtain ⟨after, evaluated, registry, frame, world⟩ :=
    evaluatesReadOnly initial argumentsResult checked.found bound checked.noBody checked.host call
  refine ⟨after, evaluated, registry, frame, world, ?_⟩
  intro separated kept present _ words contents range
  exact readOnlyPreservesView initial argumentsResult checked.found bound checked.noBody checked.host
    call separated present contents range evaluated

/-- A missing copied path returns minus one without creating a handle. No
bound or freshness assumption on the unused handle counter is needed. -/
theorem evaluatesMissing (checked : CheckedExternal program .openRead 2)
    (initial : Allocation.Registry before) (copied : Copied view path before)
    (member : view ∈ before.i32ArrayViews) (missing : before.world.file? path = none)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments
      [.pointer view.address, .unsigned .usize path.length] before) :
    ∃ after, Evaluates program caller (.call checked.function.id arguments) (.signed .i32 (-1)) after ∧
      Allocation.Registry after ∧ Frame before after ∧
      after.world = Lanius.World.record before.world .openRead := by
  obtain ⟨bindings, bound⟩ := checked.bindings [.pointer view.address, .unsigned .usize path.length] rfl
  apply evaluatesReadOnly initial argumentsResult checked.found bound checked.noBody checked.host
  intro ready synced
  have loaded := copied.loadAfterSync initial initial.disjoint member synced
  rw [Lanius.Properties.syncI32ViewsToHeap_preserves_world synced]
  have absent : (Lanius.World.record before.world .openRead).file? path = none := missing
  simp only [Lanius.World.call, Lanius.World.callSimple, loaded, BEq.rfl, bne_self_eq_false,
    show (HostService.openRead == HostService.openAppend) = false from rfl]
  simp only [Lanius.World.openFile, absent, Option.isNone_none, Bool.true_and, if_true]
  rfl

end Lanius.Extraction.Host.File
