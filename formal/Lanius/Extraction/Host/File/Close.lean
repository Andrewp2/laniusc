import Lanius.Extraction.Host.File.Open

namespace Lanius.Extraction.Host.File

open Lanius.Core Lanius.Semantics Lanius.CallContracts

def closedWorld (world : Lanius.World.State) (handle : Int) : Lanius.World.State := {
  world with
  calls := world.calls ++ [.close]
  fileHandles := world.fileHandles.filter (fun file => file.id != handle) }

/-- Close an existing handle, retaining registered arrays and caller locals.
The caller's fresh-handle invariant determines which handles remain. -/
theorem evaluatesClose (checked : CheckedExternal program .close 1)
    (initial : Allocation.Registry before) (handleId : Int) (handle : Lanius.World.FileHandle)
    (found : before.world.handle? handleId = some handle)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments [.signed .i32 handleId] before) :
    ∃ after, Evaluates program caller (.call checked.function.id arguments) (.signed .i32 0) after ∧
      Allocation.Registry after ∧ Frame before after ∧ after.world = closedWorld before.world handleId ∧
      PreservesViews before after (fun _ => True) := by
  obtain ⟨bindings, bound⟩ := checked.bindings [.signed .i32 handleId] rfl
  have call (ready : State) (synced : syncI32ViewsToHeap before = .ok ready) :
      Lanius.World.call ready.heap ready.world .close [.signed .i32 handleId] =
        .returned (.signed .i32 0) ready.heap (closedWorld before.world handleId) := by
    rw [Lanius.Properties.syncI32ViewsToHeap_preserves_world synced]
    have recorded : (Lanius.World.record before.world .close).handle? handleId = some handle := found
    simp only [Lanius.World.call, Lanius.World.callSimple]
    simp only [Lanius.World.closeHandle, recorded, Option.isSome_some, if_true]
    simp only [Lanius.World.record, closedWorld]
    rfl
  obtain ⟨after, evaluated, registry, frame, world⟩ :=
    evaluatesReadOnly initial argumentsResult checked.found bound checked.noBody checked.host call
  refine ⟨after, evaluated, registry, frame, world, ?_⟩
  intro disjoint kept member _ words contents range
  exact readOnlyPreservesView initial argumentsResult checked.found bound checked.noBody checked.host
    call disjoint member contents range evaluated

end Lanius.Extraction.Host.File
