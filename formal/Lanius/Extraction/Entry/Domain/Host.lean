import Lanius.Extraction.Entry.Domain

namespace Lanius.Extraction.Entry

/-- Numeric and freshness assumptions for the modeled process host. Files
may be missing, oversized, or syntactically invalid. The default initial heap
has an unlimited allocation budget; finite exhaustion has its own theorem.
This model does not include asynchronous I/O errors or concurrent file changes. -/
structure HostDomain (world : Lanius.World.State) : Prop where
  bounded : world.arguments.length < 2 ^ 31
  paths : ∀ path ∈ world.arguments.drop 1, path.toUTF8.size ≤ 2147483647
  handles : world.nextFileHandle + (world.arguments.length - 2) ≤ 2147483647
  olderHandles : ∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int)

def checkHostDomain? (world : Lanius.World.State) : Option (PLift (HostDomain world)) :=
  if valid : world.arguments.length < 2 ^ 31 ∧
      (∀ path ∈ world.arguments.drop 1, path.toUTF8.size ≤ 2147483647) ∧
      world.nextFileHandle + (world.arguments.length - 2) ≤ 2147483647 ∧
      ∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int) then
    some ⟨⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2⟩⟩
  else none

private theorem emptyPending (world : Lanius.World.State) (index : Nat) : Files.Pending world index [] := by
  constructor
  · intro offset request found; simp at found
  all_goals intro request member; cases member

/-- Partition all requested paths using only host inputs, not parsing or a
successful prefix execution. In the failure case the retained prefix is exactly
the loadable part before the rejected argument. -/
private theorem classifyPaths (world : Lanius.World.State) (paths : List String) (index : Nat)
    (selected : world.arguments.drop index = paths)
    (bounded : ∀ path ∈ paths, path.toUTF8.size ≤ 2147483647) :
    (∃ requests, Files.Pending world index requests ∧ requests.length = paths.length) ∨
      ∃ requests code, Files.Pending world index requests ∧ File.Rejection world (index + requests.length) code := by
  induction paths generalizing index with
  | nil => exact .inl ⟨[], emptyPending world index, rfl⟩
  | cons path paths ih =>
    have current : world.arguments[index]? = some path := by
      have first := congrArg (fun entries => entries[0]?) selected
      simpa only [List.getElem?_drop, Nat.add_zero, List.getElem?_cons_zero] using first
    have reject {code : Int} (issue : File.Rejection world index code) :
        ∃ requests code, Files.Pending world index requests ∧ File.Rejection world (index + requests.length) code :=
      ⟨[], code, emptyPending world index, by simpa using issue⟩
    by_cases valid : 0 < path.toUTF8.size ∧ path.toUTF8.size ≤ 1024
    · cases found : world.file? (Lanius.World.utf8Bytes path) with
      | none => exact .inr (reject (.path (.missing path current valid.1 valid.2 found)))
      | some file =>
        by_cases fits : file.bytes.length ≤ 65536
        · have tail : world.arguments.drop (index + 1) = paths := by
            have dropped := congrArg (List.drop 1) selected
            simpa only [List.drop_drop, List.drop_succ_cons, List.drop_zero, Nat.add_comm 1] using dropped
          let request : Files.Request := ⟨path, file⟩
          have extend {requests} (pending : Files.Pending world (index + 1) requests) :
              Files.Pending world index (request :: requests) := by
            constructor
            · intro offset item member
              cases offset with
              | zero =>
                have same : request = item := by simpa only [List.getElem?_cons_zero, Option.some.injEq] using member
                cases same
                exact current
              | succ offset =>
                have next := pending.selected offset item (by simpa only [List.getElem?_cons_succ] using member)
                simpa only [Nat.add_assoc, Nat.add_comm 1] using next
            · intro item member
              rcases List.mem_cons.mp member with rfl | later
              · exact found
              · exact pending.files item later
            · intro item member
              rcases List.mem_cons.mp member with rfl | later
              · exact valid.1
              · exact pending.nonempty item later
            · intro item member
              rcases List.mem_cons.mp member with rfl | later
              · exact valid.2
              · exact pending.pathFits item later
            · intro item member
              rcases List.mem_cons.mp member with rfl | later
              · exact fits
              · exact pending.fileFits item later
          rcases ih (index + 1) tail (fun path member => bounded path (List.mem_cons_of_mem _ member)) with loaded | rejected
          · obtain ⟨requests, pending, length⟩ := loaded
            exact .inl ⟨request :: requests, extend pending, by simp only [List.length_cons, length]⟩
          · obtain ⟨requests, code, pending, issue⟩ := rejected
            exact .inr ⟨request :: requests, code, extend pending, by
              simpa only [List.length_cons, Nat.add_assoc, Nat.add_comm 1] using issue⟩
        · exact .inr (reject (.oversized path file current found valid.1 valid.2 (by omega)))
    · exact .inr (reject (.path (.invalid path current (bounded path List.mem_cons_self) (by omega))))

/-- Exhaustive external-input coverage under the stated host assumptions.
There is no assumption that the extractor runs, parses, or emits a certificate. -/
theorem HostDomain.classify (domain : HostDomain world) :
    world.arguments.length ≤ 1 ∨ LoadingDomain world ∨
      (∃ code, File.Rejection world 1 code) ∨ LaterFailureDomain world := by
  by_cases enough : 1 < world.arguments.length
  · rcases classifyPaths world (world.arguments.drop 1) 1 rfl domain.paths with loaded | rejected
    · obtain ⟨requests, pending, length⟩ := loaded
      have endpoint : 1 + requests.length = world.arguments.length := by
        simp only [List.length_drop] at length
        omega
      cases requests with
      | nil => simp at endpoint; omega
      | cons request rest =>
        exact .inr (.inl ⟨enough, domain.bounded, ⟨request, rest, pending, endpoint, by
          have handles := domain.handles
          simp only [List.length_cons] at endpoint
          omega⟩, domain.olderHandles⟩)
    · obtain ⟨requests, code, pending, issue⟩ := rejected
      cases requests with
      | nil => exact .inr (.inr (.inl ⟨code, by simpa using issue⟩))
      | cons request rest =>
        have extra : File.Rejection.additionalHandles code ≤ 1 := by
          unfold File.Rejection.additionalHandles
          split <;> omega
        have within := issue.index_lt
        exact .inr (.inr (.inr ⟨domain.bounded, ⟨request, rest, code, pending, issue, by
          have handles := domain.handles
          simp only [List.length_cons] at within
          omega⟩, domain.olderHandles⟩))
  · exact .inl (by omega)

end Lanius.Extraction.Entry
