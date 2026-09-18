import Lanius.Extraction.Entry.Certificate

namespace Lanius.Extraction.Entry

private structure Requests (world : Lanius.World.State) (paths : List String) where
  requests : List Files.Request
  paths : requests.map Files.Request.path = paths
  files : ∀ request ∈ requests, world.file? (Lanius.World.utf8Bytes request.path) = some request.file
  bounds : ∀ request ∈ requests, 0 < request.path.toUTF8.size ∧ request.path.toUTF8.size ≤ 1024 ∧
    request.file.bytes.length ≤ 65536

/-- Select the same ordered files as the modeled host. Repeated paths stay
repeated requests; an empty source file is valid input to the loading phase. -/
private def requests? (world : Lanius.World.State) :
    (paths : List String) → Option (Requests world paths)
  | [] => some {
      requests := []
      paths := rfl
      files := by intro _ member; cases member
      bounds := by intro _ member; cases member }
  | path :: rest =>
    match found : world.file? (Lanius.World.utf8Bytes path) with
    | none => none
    | some file =>
      if bounds : 0 < path.toUTF8.size ∧ path.toUTF8.size ≤ 1024 ∧ file.bytes.length ≤ 65536 then do
        let tail ← requests? world rest
        pure {
          requests := ⟨path, file⟩ :: tail.requests
          paths := by simpa only [List.map_cons] using congrArg (List.cons path) tail.paths
          files := by
            intro request member
            rcases List.mem_cons.mp member with rfl | later
            · exact found
            · exact tail.files request later
          bounds := by
            intro request member
            rcases List.mem_cons.mp member with rfl | later
            · exact bounds
            · exact tail.bounds request later }
      else none

/-- Produce the public loading-domain proof directly from process inputs.
This checks availability, path/file bounds, and handle freshness. It neither
parses the files nor assumes that extraction or certificate acceptance succeeds. -/
def checkLoadingDomain? (world : Lanius.World.State) : Option (PLift (LoadingDomain world)) :=
  if range : 1 < world.arguments.length ∧ world.arguments.length < 2 ^ 31 ∧
      (∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int)) then do
    let selected ← requests? world (world.arguments.drop 1)
    match shape : selected.requests with
    | [] => none
    | request :: rest =>
      if capacity : world.nextFileHandle + rest.length ≤ 2147483647 then
        have paths : (request :: rest).map Files.Request.path = world.arguments.drop 1 := by
          simpa only [shape] using selected.paths
        have files : ∀ current ∈ request :: rest,
            world.file? (Lanius.World.utf8Bytes current.path) = some current.file := by
          simpa only [shape] using selected.files
        have bounds : ∀ current ∈ request :: rest,
            0 < current.path.toUTF8.size ∧ current.path.toUTF8.size ≤ 1024 ∧
            current.file.bytes.length ≤ 65536 := by
          simpa only [shape] using selected.bounds
        have pending : Files.Pending world 1 (request :: rest) := {
          selected := by
            intro offset current found
            have selected := congrArg (fun paths => paths[offset]?) paths
            simp only [List.getElem?_map, found, Option.map_some, List.getElem?_drop] at selected
            exact selected.symm
          files
          nonempty := fun current member => (bounds current member).1
          pathFits := fun current member => (bounds current member).2.1
          fileFits := fun current member => (bounds current member).2.2 }
        have endpoint : 1 + (request :: rest).length = world.arguments.length := by
          have count := congrArg List.length paths
          simp only [List.length_map, List.length_drop] at count
          have := range.1
          omega
        some ⟨⟨range.1, range.2.1, ⟨request, rest, pending, endpoint, capacity⟩, range.2.2⟩⟩
      else none
  else none

/-- Check a loadable prefix ending immediately before a rejected file.
Only paths, file bounds, and the rejection's handle demand are inspected;
no syntax is parsed, and later arguments impose no conditions. -/
def checkLaterFailureDomain? (world : Lanius.World.State) (index : Nat) :
    Option (PLift (LaterFailureDomain world)) :=
  if range : 1 < index ∧ world.arguments.length < 2 ^ 31 ∧
      (∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int)) then do
    let issue ← File.checkRejection? world index
    let selected ← requests? world ((world.arguments.drop 1).take (index - 1))
    match shape : selected.requests with
    | [] => none
    | request :: rest =>
      if capacity : world.nextFileHandle + rest.length + File.Rejection.additionalHandles issue.1 ≤ 2147483647 then
        have paths : (request :: rest).map Files.Request.path = (world.arguments.drop 1).take (index - 1) := by
          simpa only [shape] using selected.paths
        have length : 1 + (request :: rest).length = index := by
          have amount := congrArg List.length paths
          have within := issue.2.down.index_lt
          simp only [List.length_map, List.length_take, List.length_drop] at amount
          omega
        have files : ∀ current ∈ request :: rest,
            world.file? (Lanius.World.utf8Bytes current.path) = some current.file := by
          simpa only [shape] using selected.files
        have bounds : ∀ current ∈ request :: rest,
            0 < current.path.toUTF8.size ∧ current.path.toUTF8.size ≤ 1024 ∧ current.file.bytes.length ≤ 65536 := by
          simpa only [shape] using selected.bounds
        have pending : Files.Pending world 1 (request :: rest) := {
          selected := by
            intro offset current found
            have within : offset < index - 1 := by
              have bound := (List.getElem?_eq_some_iff.mp found).1
              omega
            have selected := congrArg (fun paths => paths[offset]?) paths
            simp only [List.getElem?_map, found, Option.map_some, List.getElem?_take_of_lt within,
              List.getElem?_drop] at selected
            exact selected.symm
          files
          nonempty := fun current member => (bounds current member).1
          pathFits := fun current member => (bounds current member).2.1
          fileFits := fun current member => (bounds current member).2.2 }
        some ⟨⟨range.2.1, ⟨request, rest, issue.1, pending, length ▸ issue.2.down, capacity⟩, range.2.2⟩⟩
      else none
  else none

/-- Check external first-file overflow conditions without parsing its bytes,
executing the extractor, or imposing conditions on later arguments. -/
def checkOversizedFileDomain? (world : Lanius.World.State) : Option (PLift (OversizedFileDomain world)) :=
  match selected : world.arguments[1]? with
  | none => none
  | some path =>
    match found : world.file? (Lanius.World.utf8Bytes path) with
    | none => none
    | some file =>
      if valid : world.arguments.length < 2 ^ 31 ∧ 0 < path.toUTF8.size ∧ path.toUTF8.size ≤ 1024 ∧
          65536 < file.bytes.length ∧ world.nextFileHandle ≤ 2147483647 ∧
          ∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int) then
        some ⟨⟨valid.1, ⟨path, file, selected, found, valid.2.1, valid.2.2.1, valid.2.2.2.1⟩,
          valid.2.2.2.2.1, valid.2.2.2.2.2⟩⟩
      else none

end Lanius.Extraction.Entry
