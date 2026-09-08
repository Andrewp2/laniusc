import Lanius.Extraction.SemanticTokens.Collect.Initialize
import Lanius.Extraction.SemanticTokens.Records

namespace Lanius.Extraction.SemanticTokens.Collect

/-- Logical history of the actual assignment stores, including initialization
and the untouched physical suffix. This is a proof view, not another exporter. -/
def writeUses (values : List Int) (uses : List Use) : List Int :=
  uses.foldl (fun words use => words.set use.slot use.kind) values

def written (original : List Int) (count : Nat) (uses : List Use) : List Int :=
  writeUses (initialized original (count * 2)) uses

theorem writeUses_length (values : List Int) (uses : List Use) :
    (writeUses values uses).length = values.length := by
  induction uses generalizing values with
  | nil => rfl
  | cons use uses ih => simpa only [writeUses, List.foldl_cons, List.length_set] using ih (values.set use.slot use.kind)

theorem written_length (capacity : count * 2 ≤ original.length) :
    (written original count uses).length = original.length := by
  rw [written, writeUses_length, initialized_length capacity]

theorem written_append : written original count (uses ++ more) = writeUses (written original count uses) more := by
  simp only [written, writeUses, List.foldl_append]

theorem written_snoc : written original count (uses ++ [use]) = (written original count uses).set use.slot use.kind := by
  simp only [written_append, writeUses, List.foldl_cons, List.foldl_nil]

theorem writeUses_untouched (absent : ∀ use ∈ uses, use.slot ≠ index) :
    (writeUses values uses)[index]? = values[index]? := by
  induction uses generalizing values with
  | nil => rfl
  | cons use uses ih =>
    have other := absent use (by simp)
    have tail := ih (values := values.set use.slot use.kind) (by intro next member; exact absent next (by simp [member]))
    simpa only [writeUses, List.foldl_cons, List.getElem?_set_ne other] using tail

/-- The next unique slot is still -1, derived from initialization and all
previous writes. No runtime-check or accepted-output premise is needed. -/
theorem written_available (bound : use.slot < count * 2)
    (unique : ((visited ++ use :: remaining).map Use.slot).Nodup) :
    (written original count visited)[use.slot]? = some (-1) := by
  have absent : ∀ previous ∈ visited, previous.slot ≠ use.slot := by
    have disjoint := (List.nodup_append.mp (by simpa only [List.map_append] using unique)).2.2
    intro previous member same
    exact disjoint _ (List.mem_map.mpr ⟨previous, member, rfl⟩) _ (by simp) same
  rw [written, writeUses_untouched absent]
  have inside : use.slot < (List.replicate (count * 2) (-1 : Int)).length := by simpa using bound
  simp only [initialized, BufferCopy.buffer, List.getElem?_append_left inside]
  simp [bound]

def priorUses (records : List RecordVisit) (index : Nat) : List Use :=
  (records.take index).flatMap RecordVisit.uses

theorem priorUses_step {records : List RecordVisit} {record : RecordVisit} {index : Nat}
    (found : records[index]? = some record) :
    priorUses records (index + 1) = priorUses records index ++ record.uses := by
  simp only [priorUses, List.take_add_one, found, Option.toList_some, List.flatMap_append,
    List.flatMap_cons, List.flatMap_nil, List.append_nil]

theorem record_uses_split {records : List RecordVisit} {record : RecordVisit} {index : Nat}
    (found : records[index]? = some record) :
    records.flatMap RecordVisit.uses =
      priorUses records index ++ record.uses ++ (records.drop (index + 1)).flatMap RecordVisit.uses := by
  have active := (List.getElem?_eq_some_iff.mp found).1
  have selected := (List.getElem?_eq_some_iff.mp found).2
  have dropped : records.drop index = record :: records.drop (index + 1) := by
    simpa only [selected] using List.drop_eq_getElem_cons active
  have split := congrArg (List.flatMap RecordVisit.uses) (List.take_append_drop index records)
  simpa only [List.flatMap_append, dropped, List.flatMap_cons, List.append_assoc, priorUses] using split.symm

end Lanius.Extraction.SemanticTokens.Collect
