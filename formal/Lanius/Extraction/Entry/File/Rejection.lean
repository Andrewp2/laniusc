import Lanius.Extraction.Entry.File.Checked
import Lanius.Extraction.Entry.File.Oversize
import Lanius.Extraction.Entry.Path.Rejection

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Extraction.ExtractorContract

/-- An external reason to reject a selected file-loop argument. No parsing,
successful prefix execution, or candidate output is part of the reason. -/
inductive Rejection (world : Lanius.World.State) (index : Nat) : Int → Prop where
  | path (issue : Path.Rejection world index code) : Rejection world index code
  | oversized (path : String) (file : Lanius.World.FileEntry)
      (selected : world.arguments[index]? = some path)
      (found : world.file? (Lanius.World.utf8Bytes path) = some file)
      (nonempty : 0 < path.toUTF8.size) (fits : path.toUTF8.size ≤ 1024)
      (oversize : 65536 < file.bytes.length) : Rejection world index 6

/-- Bad or absent paths need no new handle; oversized files must be opened
before the reader can discover their size and close them. -/
def Rejection.additionalHandles (code : Int) : Nat := if code = 6 then 1 else 0

def checkRejection? (world : Lanius.World.State) (index : Nat) :
    Option (Sigma fun code : Int => PLift (Rejection world index code)) :=
  match Path.checkRejection? world index with
  | some issue => some ⟨issue.1, ⟨.path issue.2.down⟩⟩
  | none =>
    match selected : world.arguments[index]? with
    | none => none
    | some path =>
      match found : world.file? (Lanius.World.utf8Bytes path) with
      | none => none
      | some file =>
        if valid : 0 < path.toUTF8.size ∧ path.toUTF8.size ≤ 1024 ∧ 65536 < file.bytes.length then
          some ⟨6, ⟨.oversized path file selected found valid.1 valid.2.1 valid.2.2⟩⟩
        else none

theorem Rejection.transport (issue : Rejection before index code)
    (arguments : after.arguments = before.arguments) (files : after.files = before.files) : Rejection after index code := by
  cases issue with
  | path bad => exact .path (bad.transport arguments files)
  | oversized path file selected found nonempty fits oversize =>
    exact .oversized path file (by simpa only [arguments] using selected)
      (by simpa only [Lanius.World.State.file?, files] using found) nonempty fits oversize

theorem Rejection.index_lt (issue : Rejection world index code) : index < world.arguments.length := by
  cases issue with
  | path bad => exact bad.index_lt
  | oversized _ _ selected _ _ _ _ => exact (List.getElem?_eq_some_iff.mp selected).1

/-- Execute rejection after an actual completed file. The handoff supplies
the reused buffers, aliases, and advanced index. The reason's handle demand
distinguishes failures before opening from oversized-file read/close failure. -/
theorem Rejection.afterFile (checked : Checked program)
    (diagnostics : Diagnostics.Read.Checked program checked.pipeline.path.argument checked.pipeline.read.count checked.pipeline.read.failure)
    (resources : Resources checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage checked.argument before)
    (frame : Handoff resources.input resources.data checked.syntaxStage checked.resultsStage checked.argument checked.emitStage.position middle)
    (sameLocals : middle.locals = before.locals)
    (registry : Allocation.Registry middle) (representable : Host.RepresentableViews middle)
    (views : ∃ fresh, middle.i32ArrayViews = before.i32ArrayViews ++ fresh)
    (issue : Rejection before.world (resources.input.index + 1) code)
    (handles : before.world.nextFileHandle + Rejection.additionalHandles code ≤ 2147483647)
    (indexFit : resources.input.index + 1 ≤ 2147483647)
    (packedLength : resources.input.packedPath.length = 256)
    (outputLength : resources.input.pathOutput.length = 1024) :
    ∃ after, Executes program.core middle checked.body (.returned (some (.signed .i32 code))) after ∧
      Nonempty (Failure middle after code) ∧ after.world.standardOutput = middle.world.standardOutput := by
  cases issue with
  | path bad =>
    have world : middle.world.arguments = before.world.arguments ∧ middle.world.files = before.world.files := by
      obtain ⟨_, _, world⟩ := frame.world
      simp only [world, Load.Available.loadedWorld, and_self]
    have current := bad.transport world.1 world.2
    let buffers := Next.pathBuffers frame sameLocals checked.advanceRelation.selected checked.nextRelation
      resources.positionRead views packedLength outputLength
    have indexRead : middle.local? checked.pipeline.path.argument = some (.signed .i32 (resources.input.index + 1 : Nat)) := by
      have restored : restoreLocals before middle = middle := by unfold restoreLocals; rw [← sameLocals]
      simpa only [restored, checked.advanceRelation.selected] using frame.index
    obtain ⟨after, run, safe, calls, afterWorld⟩ := current.executes checked.pipeline registry buffers indexRead resources.input.sizeFit
    refine ⟨after, run, ⟨⟨current.nonzero, current.classified, ?_, ?_, ?_, safe⟩⟩, ?_⟩
    all_goals simp only [afterWorld]
  | oversized path file selected found nonempty fits oversize =>
    have handleFit : before.world.nextFileHandle + 1 ≤ 2147483647 := by
      simpa only [Rejection.additionalHandles, ↓reduceIte] using handles
    let available := Next.inputNext frame sameLocals checked.advanceRelation.selected checked.nextRelation
      resources.positionRead registry representable views path file selected found handleFit resources.olderHandles nonempty fits
      (by simpa only [packedLength, Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size] using fits)
      (by simpa only [outputLength, Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size] using fits)
    have unshadowed : checked.pipeline.path.argument ∉ [checked.pipeline.path.length, checked.pipeline.unpack.locals.cursor,
        checked.pipeline.opened.handle, checked.pipeline.read.count, checked.pipeline.read.closed] := by
      simpa only [Load.Pipeline.boundLocals, checked.advanceRelation.selected] using checked.advanceRelation.loaded
    obtain ⟨after, run, safe, reads, _, bytes, world⟩ := checked.pipeline.rejectsOversized available diagnostics unshadowed indexFit oversize
    refine ⟨after, run, ⟨⟨by decide, .readOrClose, ?_, ?_, ?_, safe⟩⟩, ?_⟩
    all_goals simp only [world, Load.Available.loadedWorld]

end Lanius.Extraction.Entry.File
