import Lanius.Extraction.Entry.File.Checked

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties

/-- An external requested path and its modeled file, not a parsed or accepted
unit. Repeated paths remain repeated entries in the ordered request. -/
structure Request where
  path : String
  file : Lanius.World.FileEntry

def Request.source (request : Request) : SourceFile :=
  { path := request.path, bytes := request.file.bytes.map UInt8.toNat }

/-- The ordinary loading domain of the remaining request. Syntax validity,
successful extraction, and certificate acceptance are deliberately absent. -/
structure Pending (world : Lanius.World.State) (index : Nat) (requests : List Request) : Prop where
  selected : ∀ offset request, requests[offset]? = some request →
    world.arguments[index + offset]? = some request.path
  files : ∀ request ∈ requests, world.file? (Lanius.World.utf8Bytes request.path) = some request.file
  nonempty : ∀ request ∈ requests, 0 < request.path.toUTF8.size
  pathFits : ∀ request ∈ requests, request.path.toUTF8.size ≤ 1024
  fileFits : ∀ request ∈ requests, request.file.bytes.length ≤ 65536

theorem Pending.tail (pending : Pending before index (request :: rest))
    (arguments : after.arguments = before.arguments) (files : after.files = before.files) :
    Pending after (index + 1) rest := by
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · intro offset found member
    have selected := pending.selected (offset + 1) found (by simpa only [List.getElem?_cons_succ] using member)
    simpa only [arguments, Nat.add_assoc, Nat.add_comm 1] using selected
  · intro found member
    simpa only [Lanius.World.State.file?, files] using pending.files found (List.mem_cons_of_mem _ member)
  · exact fun found member => pending.nonempty found (List.mem_cons_of_mem _ member)
  · exact fun found member => pending.pathFits found (List.mem_cons_of_mem _ member)
  · exact fun found member => pending.fileFits found (List.mem_cons_of_mem _ member)

theorem Pending.current {program : CoreSynthesis.Program.CheckedProgram artifacts}
    {pipeline : File.Load.Pipeline program} (input : File.Load.Input pipeline before)
    (pending : Pending before.world input.index (request :: rest)) :
    input.path = request.path ∧ input.file = request.file := by
  have selected := pending.selected 0 request (by simp)
  simp only [Nat.add_zero, input.selected, Option.some.injEq] at selected
  refine ⟨selected, ?_⟩
  have file := pending.files request (by simp)
  rw [← selected, input.fileFound] at file
  exact Option.some.inj file

/-- Matching every requested position and the stopping count rules out
omitted, duplicated, or extra argv entries in the logical request list. -/
theorem Pending.paths (pending : Pending world index requests)
    (endpoint : index + requests.length = world.arguments.length) :
    world.arguments.drop index = requests.map Request.path := by
  apply List.ext_getElem
  · simp only [List.length_drop, List.length_map]
    omega
  · intro offset left right
    have bound : offset < requests.length := by simpa only [List.length_map] using right
    have selected := pending.selected offset requests[offset] (List.getElem?_eq_getElem bound)
    obtain ⟨_, found⟩ := List.getElem?_eq_some_iff.mp selected
    simpa only [List.getElem_drop, List.getElem_map] using found

/-- Connect the loop's ordered external-input domain to the original
extractor contract, including repeated paths and exact source bytes. -/
theorem Pending.sources (pending : Pending world 1 requests)
    (endpoint : 1 + requests.length = world.arguments.length) :
    ExtractorContract.requestedSources? world = some (requests.map Request.source) := by
  unfold ExtractorContract.requestedSources?
  rw [pending.paths endpoint]
  have files := pending.files
  clear pending endpoint
  induction requests with
  | nil => rfl
  | cons request rest ih =>
    have file := files request List.mem_cons_self
    have tail := ih (fun found member => files found (List.mem_cons_of_mem _ member))
    have head : ExtractorContract.sourceFileInWorld? world request.path = some request.source := by
      simp [ExtractorContract.sourceFileInWorld?, file, Request.source]
    simp [List.map_cons, List.mapM_cons, head, tail]

end Lanius.Extraction.Entry.Files
