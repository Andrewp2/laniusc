import Lanius.Extraction.Host.Copy
import Lanius.Extraction.Host.External
import Lanius.Extraction.Host.Arguments
import Lanius.World.FileRead

namespace Lanius.Extraction.Host.File

open Lanius.Core Lanius.Semantics Lanius.Memory Lanius.Properties Lanius.CallContracts

/-- Construct a file-read call, obtaining exact packed bytes and an advanced
handle from the caller's registry and readable file. Unlike the earlier input
inversion lemma, this does not assume the read has already succeeded. -/
theorem evaluatesRead (checked : CheckedExternal program .read 3)
    (initial : Allocation.Registry before) (handleId : Int) (handle : Lanius.World.FileHandle)
    (file : Lanius.World.FileEntry) (request : Nat)
    (handleFound : before.world.handle? handleId = some handle) (readable : handle.readable = true)
    (fileFound : before.world.file? handle.path = some file)
    (member : view ∈ before.i32ArrayViews) (room : request ≤ view.length * 4)
    (bounded : request ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments
      [.signed .i32 handleId, .pointer view.address, .unsigned .usize request] before) :
    ∃ after, Evaluates program caller (.call checked.function.id arguments)
        (.signed .i32 ((file.bytes.drop handle.offset).take request).length) after ∧
      Allocation.Registry after ∧ Frame before after ∧
      after.world = { before.world with
        calls := before.world.calls ++ [.read]
        fileHandles := Lanius.World.replaceHandle before.world.fileHandles {
          handle with offset := handle.offset + ((file.bytes.drop handle.offset).take request).length } } ∧
      Copied view ((file.bytes.drop handle.offset).take request) after ∧
      PreservesViews before after (I32ViewRangesDisjoint view) := by
  obtain ⟨bindings, bound⟩ := checked.bindings [.signed .i32 handleId, .pointer view.address, .unsigned .usize request] rfl
  apply evaluatesCopy initial argumentsResult checked.found bound checked.noBody checked.host member
    (Nat.le_trans (List.length_take_le _ _) room)
  intro heap copied stored
  simpa only [i32Result_nat (Nat.le_trans (List.length_take_le _ _) bounded)] using
    Lanius.World.read_call_exact handleFound readable fileFound stored

end Lanius.Extraction.Host.File
