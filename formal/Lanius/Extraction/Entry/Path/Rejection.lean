import Lanius.Extraction.Entry.File.Missing

namespace Lanius.Extraction.Entry.Path
open Lanius.Core Lanius.Semantics Lanius.Extraction.ExtractorContract

/-- External facts forcing rejection at an argument. This contains neither
an assumed run nor a condition on the validity of any other argument. -/
inductive Rejection (world : Lanius.World.State) (index : Nat) : Int → Prop where
  | invalid (path : String) (selected : world.arguments[index]? = some path)
      (bounded : path.toUTF8.size ≤ 2147483647)
      (bad : path.toUTF8.size = 0 ∨ 1025 ≤ path.toUTF8.size) : Rejection world index 2
  | missing (path : String) (selected : world.arguments[index]? = some path)
      (nonempty : 0 < path.toUTF8.size) (fits : path.toUTF8.size ≤ 1024)
      (absent : world.file? (Lanius.World.utf8Bytes path) = none) : Rejection world index 5

/-- Authenticate only the selected path's external rejection condition. -/
def checkRejection? (world : Lanius.World.State) (index : Nat) :
    Option (Sigma fun code : Int => PLift (Rejection world index code)) :=
  match selected : world.arguments[index]? with
  | none => none
  | some path =>
    if bounded : path.toUTF8.size ≤ 2147483647 then
      if bad : path.toUTF8.size = 0 ∨ 1025 ≤ path.toUTF8.size then
        some ⟨2, ⟨.invalid path selected bounded bad⟩⟩
      else
        match absent : world.file? (Lanius.World.utf8Bytes path) with
        | some _ => none
        | none => some ⟨5, ⟨.missing path selected (by omega) (by omega) absent⟩⟩
    else none

theorem Rejection.transport (issue : Rejection before index code)
    (arguments : after.arguments = before.arguments) (files : after.files = before.files) :
    Rejection after index code := by
  cases issue with
  | invalid path selected bounded bad =>
    exact .invalid path (by simpa only [arguments] using selected) bounded bad
  | missing path selected nonempty fits absent =>
    exact .missing path (by simpa only [arguments] using selected) nonempty fits
      (by simpa only [Lanius.World.State.file?, files] using absent)

theorem Rejection.index_lt (issue : Rejection world index code) : index < world.arguments.length := by
  cases issue with
  | invalid path selected _ _ => exact List.getElem?_eq_some_iff.mp selected |>.1
  | missing path selected _ _ _ => exact List.getElem?_eq_some_iff.mp selected |>.1

theorem Rejection.classified (issue : Rejection world index code) : FailureCode code := by
  cases issue
  · exact .badPath
  · exact .open

theorem Rejection.nonzero (issue : Rejection world index code) : code ≠ 0 := by
  cases issue <;> decide

/-- Both rejection kinds execute the existing source prefix using its actual
buffers. Only the call trace changes in the external world. -/
theorem Rejection.executes (issue : Rejection before.world index code)
    (pipeline : File.Load.Pipeline program) (initial : Allocation.Registry before)
    (buffers : Buffers pipeline.argument pipeline.unpack before)
    (indexRead : before.local? pipeline.path.argument = some (.signed .i32 index))
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ after, Executes program.core before (pipeline.path.statement pipeline.length.function.id)
        (.returned (some (.signed .i32 code))) after ∧ MemorySafe after ∧
      ∃ calls, after.world = { before.world with calls := before.world.calls ++ calls } := by
  cases issue with
  | invalid path selected bounded bad =>
    obtain ⟨after, run, registry, _, world⟩ := pipeline.path.rejects pipeline.length before initial
      index path indexRead selected bounded bad
    exact ⟨after, run, ⟨registry.wellFormed.heapWellFormed, registry.blocks⟩, [.argLen], world⟩
  | missing path selected nonempty fits absent =>
    obtain ⟨after, run, safe, world⟩ := pipeline.rejectsMissing buffers initial index path
      indexRead selected nonempty fits absent sizeFit
    exact ⟨after, run, safe, [.argLen, .argRead, .openRead], world⟩

end Lanius.Extraction.Entry.Path
