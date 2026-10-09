import Lanius.Data.List
import Init.Data.List.Lemmas

namespace Lanius.Data

variable {α : Type u} {key : α → Nat} {values : List α}

/-- An interval is only a search hint. Every stored key must satisfy it. -/
structure LookupChunk (key : α → Nat) where
  lower : Nat
  upper : Nat
  values : List α
  bounded : values.all (fun value => decide (lower ≤ key value ∧ key value ≤ upper)) = true

namespace LookupChunk

def find? (chunk : LookupChunk key) (id : Nat) : Option α :=
  if chunk.lower ≤ id ∧ id ≤ chunk.upper then
    List.find? (fun value => key value == id) chunk.values
  else none

theorem find?_eq (chunk : LookupChunk key) (id : Nat) :
    chunk.find? id = chunk.values.find? (fun value => key value == id) := by
  unfold find?
  split
  · rw [List.find?_eq]
  · rename_i outside
    symm
    apply _root_.List.find?_eq_none.mpr
    intro value member
    have bounds := _root_.List.all_eq_true.mp chunk.bounded value member
    have bounded : chunk.lower ≤ key value ∧ key value ≤ chunk.upper := of_decide_eq_true bounds
    intro equal
    exact outside (eq_of_beq equal ▸ bounded)

end LookupChunk

/-- An executable lookup together with its exact first-match list meaning. -/
structure Lookup (key : α → Nat) (values : List α) where
  find? : Nat → Option α
  correct : ∀ id, find? id = values.find? (fun value => key value == id)

namespace Lookup

def linear (key : α → Nat) (values : List α) : Lookup key values :=
  ⟨fun id => List.find? (fun value => key value == id) values,
    fun _ => by rw [List.find?_eq]⟩

def chunksFind (chunks : List (LookupChunk key)) (id : Nat) : Option α :=
  match chunks with
  | [] => none
  | chunk :: rest => (chunk.find? id).or (chunksFind rest id)

theorem chunksFind_eq (chunks : List (LookupChunk key)) (id : Nat) :
    chunksFind chunks id =
      (List.flatten (List.map LookupChunk.values chunks)).find? (fun value => key value == id) := by
  rw [List.flatten_eq, List.map_eq]
  induction chunks with
  | nil => rfl
  | cons chunk rest ih =>
      simpa only [chunksFind, _root_.List.map_cons, _root_.List.flatten_cons,
        _root_.List.find?_append, LookupChunk.find?_eq, List.flatten_eq, List.map_eq] using
        congrArg (fun found => (chunk.values.find? (fun value => key value == id)).or found) ih

def ofChunks (chunks : List (LookupChunk key))
    (same : List.flatten (List.map LookupChunk.values chunks) = values) : Lookup key values :=
  ⟨chunksFind chunks, fun id => by rw [chunksFind_eq, same]⟩

end Lookup
end Lanius.Data
